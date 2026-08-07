--[[
	FleetSystem.luau
	----------------
	Quản lý hạm đội bay quanh Tàu Mẹ theo quỹ đạo (orbital formation).

	M1:
	  - Spawn unit (debug qua phím 1-4, chưa tính scrap — economy ở M4).
	  - Mỗi unit thuộc 1 RING (SCREEN ngoài / GUARD giữa / CORE trong) theo Config.
	  - Mỗi Heartbeat: xếp unit đều quanh vòng của ring, cả hạm đội xoay chậm,
	    unit steer mượt về slot của mình (không teleport) -> cảm giác "đuôi bám".
	  - Fleet cap: usedCap (tổng weight) không vượt maxCap; gửi HUD cập nhật.

	MATH FORMATION (top-down, mặt phẳng XZ):
	  globalTheta += ORBIT_SPIN * dt                      -- góc quay chung, chậm
	  slotAngle   = globalTheta + 2π * (i-1) / N          -- N = số unit trong ring
	  targetPos   = center + ringRadius * (cos, 0, sin)   -- center = vị trí Tàu Mẹ
	  unit.pos   -> steer về targetPos với unit.speed     -- lerp theo bước speed*dt

	Lưu ý: unit KHÔNG rời formation để đuổi địch (chủ ý thiết kế). Bắn nhau là
	việc của CombatSystem (M2), unit vẫn giữ quỹ đạo.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Util = require(ReplicatedStorage.Util)
local Remotes = require(ReplicatedStorage.Remotes)
local GameState = require(script.Parent.GameState)

local FleetSystem = {}

local unitsFolder            -- Folder chứa mọi unit part trong workspace
local globalTheta = 0        -- góc quay chung của mọi hạm đội (rad)

-- Hình dạng / kích cỡ theo loại unit. MÀU lấy theo phe (owner.teamColor) để phân
-- biệt bạn/địch; LOẠI phân biệt bằng shape + size (Drone: cầu nhỏ, Plasma: cầu to,
-- Frigate: khối dẹt, Destroyer: khối to).
-- Dáng riêng theo loại (dễ phân biệt); màu = phe (đặt ở makeUnitPart).
--   Drone: mũi tên (wedge)  | Frigate: thanh dài | Destroyer: đĩa dẹt | Plasma: cầu neon
local VISUAL = {
	Drone         = { class = "WedgePart", size = Vector3.new(3.4, 1.8, 4.2), material = Enum.Material.Neon },
	Frigate       = { class = "Part", shape = Enum.PartType.Block, size = Vector3.new(2.6, 1.4, 5.8), material = Enum.Material.Metal },
	Destroyer     = { class = "Part", shape = Enum.PartType.Ball,  size = Vector3.new(7.4, 3.2, 7.4), material = Enum.Material.Metal },
	PlasmaCruiser = { class = "Part", shape = Enum.PartType.Ball,  size = Vector3.new(5.2, 5.2, 5.2), material = Enum.Material.Neon },
	-- Bước 1
	Interceptor   = { class = "WedgePart", size = Vector3.new(2.8, 1.4, 5.4), material = Enum.Material.Neon },      -- dart mảnh, nhanh
	Battleship    = { class = "Part", shape = Enum.PartType.Block, size = Vector3.new(6.0, 3.0, 11.0), material = Enum.Material.Metal }, -- chiến hạm to
	-- Bước 2
	SiegeRailgun  = { class = "Part", shape = Enum.PartType.Block, size = Vector3.new(2.2, 2.2, 9.0), material = Enum.Material.Metal }, -- nòng pháo dài
	-- Bước 3a
	Titan         = { class = "Part", shape = Enum.PartType.Ball,  size = Vector3.new(9.5, 4.5, 9.5), material = Enum.Material.Metal }, -- khối CC to
	-- Bước 3b
	Kamikaze      = { class = "WedgePart", size = Vector3.new(2.4, 1.4, 3.6), material = Enum.Material.Neon }, -- dart nhỏ suicide
}

-- Fleet cap tối đa của 1 owner = BASE_CAP + tổng bonus của các Drone Hub sở hữu.
function FleetSystem.getMaxCap(ownerId)
	local cap = Config.FLEET.BASE_CAP
	for _, b in ipairs(GameState.buildings) do
		if b.ownerId == ownerId and b.buildingType == "DroneHub" then
			-- đọc thẳng Config theo tier -> tune sống được
			local stats = Config.ECONOMY.DRONE_HUB[b.tier]
			cap += (stats and stats.cap) or 0
		end
	end
	return cap
end

-- Tổng weight fleet hiện tại của owner.
function FleetSystem.getUsedCap(ownerId)
	local used = 0
	for _, u in ipairs(GameState.units) do
		if u.ownerId == ownerId then
			used += u.weight
		end
	end
	return used
end

-- Gửi cập nhật fleet cap cho 1 player (HUD dùng để hiển thị used/max).
function FleetSystem.sendFleetUpdate(ownerId)
	local player = Players:GetPlayerByUserId(ownerId)
	if player then
		Remotes.FleetUpdate:FireClient(player, FleetSystem.getUsedCap(ownerId), FleetSystem.getMaxCap(ownerId))
	end
end

local function makeUnitPart(unitType, pos, teamColor)
	local v = VISUAL[unitType]
	local p = Instance.new(v.class or "Part")
	p.Name = "Unit_" .. unitType
	p.Anchored = true       -- vị trí do server tự set, không dùng physics
	p.CanCollide = false    -- không xô đẩy nhau / Tàu Mẹ
	p.CastShadow = false
	if v.shape and p:IsA("Part") then
		p.Shape = v.shape
	end
	p.Size = v.size
	p.Position = pos
	p.Color = teamColor     -- màu = phe (bạn/địch)
	p.Material = v.material
	p.Parent = unitsFolder
	return p
end

-- Spawn 1 unit cho owner. ignoreCap=true để bỏ qua giới hạn cap (bot/debug).
-- Trả về true nếu thành công.
function FleetSystem.spawnUnit(ownerId, unitType, ignoreCap)
	local stats = Config.UNITS[unitType]
	if not stats then
		return false
	end

	local owner = GameState.motherships[ownerId]
	if not owner or not owner.alive then
		return false
	end

	-- Kiểm tra fleet cap (trừ khi được phép bỏ qua)
	local weight = stats.weight or 1
	if not ignoreCap and FleetSystem.getUsedCap(ownerId) + weight > FleetSystem.getMaxCap(ownerId) then
		return false
	end

	-- Spawn ngay tại vị trí Tàu Mẹ rồi để nó bay ra ring cho đẹp
	local part = makeUnitPart(unitType, owner.part.Position, owner.teamColor)

	local vis = VISUAL[unitType]
	local unit = {
		kind = "Unit",          -- dùng cho CombatSystem phân loại target
		ownerId = ownerId,
		unitType = unitType,
		ring = stats.ring,      -- "SCREEN" | "GUARD" | "CORE"
		part = part,
		radius = math.max(vis.size.X, vis.size.Z) / 2, -- bán kính va chạm (separation)
		hp = stats.hp,
		maxHp = stats.hp,
		speed = stats.speed,
		weight = weight,
		-- Combat
		dmg = stats.dmg,
		range = stats.range,
		fireRate = stats.fireRate,
		aoe = stats.aoeRadius or 0,
		attack = stats.attack or "HITSCAN",       -- (Bước 3: COLLISION cho Kamikaze)
		targeting = stats.targeting or "STANDARD", -- (Bước 1-3: kiểu nhắm riêng)
		special = stats.special,                   -- (Bước 3: GRAVITY_STUN | KAMIKAZE)
		chargeTime = stats.chargeTime,             -- (Bước 2: telegraph nạp đạn Siege)
		-- Bước 3a — tham số CC (chỉ Titan có); pushOffset/stunnedUntil set lúc bị đánh.
		stunRadius = stats.stunRadius,
		stunDuration = stats.stunDuration,
		pushStrength = stats.pushStrength,
		-- Bước 3b — Kamikaze; armed/kamiTarget set khi lao.
		armRange = stats.armRange,
		cooldown = 0,           -- đếm lùi tới lần bắn kế
	}
	table.insert(GameState.units, unit)

	FleetSystem.sendFleetUpdate(ownerId)
	return true
end

-- Dọn unit chết / mất chủ; trả về true nếu có thay đổi để cập nhật HUD.
local function cleanupUnits()
	local changedOwners = {}
	for i = #GameState.units, 1, -1 do
		local u = GameState.units[i]
		local owner = GameState.motherships[u.ownerId]
		local dead = (not u.part) or (not u.part.Parent)
		local ownerGone = (not owner) or (not owner.alive)
		if dead or ownerGone then
			if u.part and u.part.Parent then
				u.part:Destroy()
			end
			table.remove(GameState.units, i)
			changedOwners[u.ownerId] = true
		end
	end
	for ownerId in pairs(changedOwners) do
		FleetSystem.sendFleetUpdate(ownerId)
	end
end

-- Steer 1 unit mượt về vị trí đích. Tốc độ bám TỈ LỆ với khoảng cách (đội hình
-- càng bị kéo giãn thì unit chạy càng nhanh để đuổi kịp), nhưng trần tốc độ luôn
-- LỚN HƠN tốc độ Tàu Mẹ -> không bao giờ bị bỏ lại thành "đuôi sao chổi".
-- min() theo dist tạo độ trễ nhỏ ổn định -> cảm giác đuôi bám mượt.
local function steerUnit(u, target, faceDir, dt)
	local part = u.part
	local pos = part.Position
	-- Bước 3a — bị Titan đẩy: cộng offset vào đích rồi cho offset tan dần -> unit
	-- steer ra rồi TỰ về slot mượt (không teleport).
	if u.pushOffset then
		target = target + u.pushOffset
		u.pushOffset = u.pushOffset:Lerp(Vector3.zero, 1 - math.exp(-dt / 0.35))
		if u.pushOffset.Magnitude < 0.3 then u.pushOffset = nil end
	end
	local delta = target - pos
	local dist = delta.Magnitude
	local newPos = pos
	if dist > 0.05 then
		local maxSpeed = math.max(u.speed, Config.MOTHERSHIP.SPEED * Config.FLEET.FOLLOW_MAX_MULT)
		local speed = math.min(dist * Config.FLEET.FOLLOW_GAIN, maxSpeed)
		local step = math.min(speed * dt, dist)
		newPos = pos + delta.Unit * step
	end
	-- Xoay mặt hướng ra ngoài (mũi tên chĩa ra); nếu không có hướng thì chỉ dời vị trí
	if faceDir and (faceDir.X ~= 0 or faceDir.Z ~= 0) then
		part.CFrame = CFrame.lookAt(newPos, newPos + Vector3.new(faceDir.X, 0, faceDir.Z))
	else
		part.Position = newPos
	end
end

-- Lớp đội hình theo RING: CORE (trong) -> GUARD (giữa) -> SCREEN (ngoài).
-- => pháo (CORE) được che trong cùng, tank (GUARD) chắn giữa, bia (SCREEN) ngoài.
local RING_LAYER = { CORE = 1, GUARD = 2, SCREEN = 3 }

-- "Bề ngang" của 1 unit (studs) — dùng để scale khoảng cách theo kích cỡ.
local BASE_FOOTPRINT = 4.2 -- ~ cỡ Drone, làm chuẩn (scale = 1)
local function unitFootprint(unitType)
	local v = VISUAL[unitType]
	return v and math.max(v.size.X, v.size.Z) or BASE_FOOTPRINT
end

-- Xếp 1 nhóm unit thành NHIỀU VÒNG ĐỒNG TÂM quanh `center`:
--   - Sắp theo lớp (tank trong -> drone ngoài), giữ thứ tự gốc trong từng lớp
--     (ổn định slot, không giật).
--   - Vòng r chứa capacity = chu vi / UNIT_SPACING unit; đầy thì nở ra r+RING_GAP.
-- => hạm đội càng đông càng nở nhiều vòng ra ngoài, nhìn đồ sộ.
local function packRings(list, center, dt)
	local n = #list
	if n == 0 then return end

	-- Bucket theo lớp để sắp ổn định (không dùng table.sort tránh đảo chỗ mỗi frame)
	local buckets = { {}, {}, {} }
	for _, u in ipairs(list) do
		local L = RING_LAYER[u.ring] or 3
		table.insert(buckets[L], u)
	end
	local ordered = {}
	for L = 1, 3 do
		for _, u in ipairs(buckets[L]) do
			table.insert(ordered, u)
		end
	end

	local i = 1
	local radius = Config.FLEET.INNER_RADIUS
	local ringIndex = 0
	while i <= n do
		-- Scale theo cỡ unit mở đầu vòng: unit CÀNG TO -> spacing & gap càng lớn,
		-- slot mỗi vòng càng ít. (Vì đã sort theo lớp nên mỗi vòng gần như 1 cỡ.)
		local scale = unitFootprint(ordered[i].unitType) / BASE_FOOTPRINT
		local spacing = Config.FLEET.UNIT_SPACING * scale
		local circ = 2 * math.pi * radius
		local capacity = math.clamp(
			math.floor(circ / spacing),
			Config.FLEET.RING_MIN_SLOTS,
			Config.FLEET.RING_MAX_SLOTS
		)
		local ringCount = math.min(capacity, n - i + 1)
		-- lệch pha mỗi vòng để không tạo "nan hoa" thẳng hàng
		local phase = globalTheta + ringIndex * 0.6
		for k = 0, ringCount - 1 do
			local u = ordered[i + k]
			local slotAngle = phase + (2 * math.pi) * k / ringCount
			local cosA, sinA = math.cos(slotAngle), math.sin(slotAngle)
			local target = Vector3.new(
				center.X + cosA * radius,
				center.Y,
				center.Z + sinA * radius
			)
			-- hướng ra ngoài (xuyên tâm) -> unit chĩa mũi ra
			steerUnit(u, target, Vector3.new(cosA, 0, sinA), dt)
		end
		i += ringCount
		radius += Config.FLEET.RING_GAP * scale -- gap giãn theo cỡ unit
		ringIndex += 1
	end
end

-- Đưa cur tiến về target, mỗi bước tối đa maxStep (ramp mượt, không giật).
local function moveToward(cur, target, maxStep)
	if cur < target then
		return math.min(cur + maxStep, target)
	else
		return math.max(cur - maxStep, target)
	end
end

-- Cập nhật vị trí toàn bộ unit theo quỹ đạo (gọi mỗi Heartbeat).
local function updateFormation(dt)
	-- Góc quay chung, chậm -> cả hạm đội "sống"
	globalTheta = (globalTheta + Config.FLEET.ORBIT_SPIN * dt) % (2 * math.pi)

	-- Gom unit theo owner (giữ thứ tự list -> slot ổn định, không giật).
	-- BỎ QUA Kamikaze đã kích hoạt (u.armed): nó rời formation, CombatSystem tự lái.
	local groups = {}
	for _, u in ipairs(GameState.units) do
		if not u.armed then
			groups[u.ownerId] = groups[u.ownerId] or {}
			table.insert(groups[u.ownerId], u)
		end
	end

	local rampRate = Config.FLEET.SPLIT_DIST / Config.FLEET.SPLIT_RAMP -- studs/s

	for ownerId, list in pairs(groups) do
		local owner = GameState.motherships[ownerId]
		if owner and owner.alive then
			local center = owner.part.Position

			-- Ramp splitDist về mục tiêu (SPLIT_DIST nếu đang giữ Space, else 0)
			local wantDist = owner.split and Config.FLEET.SPLIT_DIST or 0
			owner.splitDist = moveToward(owner.splitDist, wantDist, rampRate * dt)

			if owner.splitDist <= 0.1 then
				-- Bình thường: toàn hạm đội thành nhiều vòng đồng tâm quanh Tàu Mẹ
				packRings(list, center, dt)
			else
				-- Split: chia hạm đội theo chẵn/lẻ -> 2 cánh, mỗi cánh tự packRings
				-- quanh tâm cánh của nó (lệch sang trái/phải theo hướng đi).
				local right = Util.rotateRight90(owner.facing)
				local leftWing, rightWing = {}, {}
				for i, u in ipairs(list) do
					if i % 2 == 1 then
						table.insert(leftWing, u)
					else
						table.insert(rightWing, u)
					end
				end
				packRings(leftWing, center - right * owner.splitDist, dt)
				packRings(rightWing, center + right * owner.splitDist, dt)
			end
		end
	end
end

-- Nhận cờ Split từ client (giữ/thả Space). Server là nơi quyết định.
local function onSplitInput(player, flag)
	local owner = GameState.motherships[player.UserId]
	if owner then
		owner.split = (flag == true)
	end
end

-- Đẩy tách các unit đè lên nhau (kể cả khác phe khi chạm trán) để không overlap.
-- Dùng lưới không gian để chỉ so unit ở ô lân cận -> nhẹ hơn O(n^2).
local SEP_CELL = 12
local function separationPass()
	local units = GameState.units
	local strength = Config.FLEET.SEPARATION_STRENGTH
	if strength <= 0 then return end
	local maxPush = Config.FLEET.SEPARATION_MAX

	-- Dựng lưới + reset lực đẩy
	local grid = {}
	for _, u in ipairs(units) do
		local part = u.part
		if part and part.Parent and not u.armed then -- Kamikaze đang lao: không xô đẩy
			local p = part.Position
			local kx = math.floor(p.X / SEP_CELL)
			local kz = math.floor(p.Z / SEP_CELL)
			grid[kx] = grid[kx] or {}
			grid[kx][kz] = grid[kx][kz] or {}
			table.insert(grid[kx][kz], u)
			u._sx, u._sz = 0, 0
		end
	end

	-- Tính lực đẩy từ các unit trong 9 ô lân cận
	for _, u in ipairs(units) do
		local part = u.part
		if part and part.Parent then
			local p = part.Position
			local kx = math.floor(p.X / SEP_CELL)
			local kz = math.floor(p.Z / SEP_CELL)
			for gx = kx - 1, kx + 1 do
				local col = grid[gx]
				if col then
					for gz = kz - 1, kz + 1 do
						local cell = col[gz]
						if cell then
							for _, o in ipairs(cell) do
								if o ~= u then
									local op = o.part.Position
									local dx, dz = p.X - op.X, p.Z - op.Z
									local dist = math.sqrt(dx * dx + dz * dz)
									local minDist = (u.radius or 2) + (o.radius or 2)
									if dist > 0.001 and dist < minDist then
										local overlap = (minDist - dist) * strength
										u._sx += (dx / dist) * overlap
										u._sz += (dz / dist) * overlap
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- Áp lực đẩy (kẹp để không giật)
	for _, u in ipairs(units) do
		local part = u.part
		if part and part.Parent and not u.armed and (u._sx ~= 0 or u._sz ~= 0) then
			local mag = math.sqrt(u._sx * u._sx + u._sz * u._sz)
			if mag > maxPush then
				u._sx = u._sx / mag * maxPush
				u._sz = u._sz / mag * maxPush
			end
			local p = part.Position
			part.Position = Vector3.new(p.X + u._sx, p.Y, p.Z + u._sz)
		end
	end
end

-- Xoá sạch mọi unit (dùng khi Restart).
function FleetSystem.clearAll()
	for i = #GameState.units, 1, -1 do
		local u = GameState.units[i]
		if u.part then u.part:Destroy() end
		GameState.units[i] = nil
	end
end

function FleetSystem.init()
	unitsFolder = Instance.new("Folder")
	unitsFolder.Name = "Units"
	unitsFolder.Parent = Workspace

	-- Mua unit (SpawnUnit) do EconomySystem xử lý (có trừ scrap).
	Remotes.SplitInput.OnServerEvent:Connect(onSplitInput)

	RunService.Heartbeat:Connect(function(dt)
		cleanupUnits()
		updateFormation(dt)
		separationPass() -- đẩy tách sau khi đã về đội hình -> không đè nhau
	end)

	-- Gửi HUD định kỳ (phòng khi client vào trễ hoặc lỡ update)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, entry in pairs(GameState.motherships) do
				if not entry.isBot then
					FleetSystem.sendFleetUpdate(entry.ownerId)
				end
			end
		end
	end)

	print("[FleetSystem] ready")
end

return FleetSystem
