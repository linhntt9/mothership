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
local MapSystem = require(script.Parent.MapSystem)
local MatchState = require(script.Parent.MatchState)

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
	Destroyer     = { class = "Part", shape = Enum.PartType.Block, size = Vector3.new(7.5, 4, 8), material = Enum.Material.Metal }, -- tank chắn vòng giữa
	PlasmaCruiser = { class = "Part", shape = Enum.PartType.Ball,  size = Vector3.new(5.2, 5.2, 5.2), material = Enum.Material.Neon },
	-- Bước 1
	Interceptor   = { class = "WedgePart", size = Vector3.new(2.8, 1.4, 5.4), material = Enum.Material.Neon },      -- dart mảnh, nhanh
	Battleship    = { class = "Part", shape = Enum.PartType.Block, size = Vector3.new(6.0, 3.0, 11.0), material = Enum.Material.Metal }, -- chiến hạm to
	-- Bước 2
	SiegeRailgun  = { class = "Part", shape = Enum.PartType.Block, size = Vector3.new(2.2, 2.2, 9.0), material = Enum.Material.Metal }, -- nòng pháo dài
	-- Bước 3a
	Titan         = { class = "Part", shape = Enum.PartType.Ball,  size = Vector3.new(28.5, 13.5, 28.5), material = Enum.Material.Metal }, -- TROLL khổng lồ (x3)
	-- Bước 3b
	Kamikaze      = { class = "WedgePart", size = Vector3.new(4.4, 0.9, 6.2), material = Enum.Material.Neon }, -- MŨI TÊN/tam giác dẹt lao cảm tử
}

-- Fleet cap tối đa của 1 owner = BASE_CAP + tổng bonus của các Drone Hub sở hữu.
function FleetSystem.getMaxCap(ownerId)
	if MatchState.isTest() then return 1000 end -- sandbox test: pop 1000 để xả quân
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
	p.Size = v.size * ((Config.UNIT_SIZE and Config.UNIT_SIZE[unitType]) or 1) -- hệ số size từ Config
	p.Position = pos
	p.Color = teamColor     -- màu = phe (bạn/địch)
	p.Material = v.material
	p.Parent = unitsFolder
	return p
end

-- Hệ số đánh đổi từ hero đang chọn của owner, áp cho unit thuộc `ring`.
-- Mỗi hero TĂNG 1 chỉ số nhóm (up) và GIẢM cùng cỡ ở nhóm khác (down).
-- Trả về (dmgMult, hpMult). Owner không chọn hero (hoặc là bot) -> 1, 1.
function FleetSystem.getHeroBuff(ownerId, ring)
	local heroId = GameState.activeHero[ownerId]
	local hero = heroId and Config.HERO_BY_ID[heroId]
	if not hero then
		return 1, 1
	end
	local dmgMult, hpMult = 1, 1
	local function apply(side, sign)
		if side and side.group == ring then
			if side.stat == "dmg" then
				dmgMult += sign * side.pct
			else -- "hp"
				hpMult += sign * side.pct
			end
		end
	end
	apply(hero.up, 1)
	apply(hero.down, -1)
	return dmgMult, hpMult
end

-- Spawn 1 unit cho owner. ignoreCap=true để bỏ qua giới hạn cap (bot/debug).
-- Trả về true nếu thành công.
function FleetSystem.spawnUnit(ownerId, unitType, ignoreCap, guardPos)
	local stats = Config.UNITS[unitType]
	if not stats then
		return false
	end

	local owner = GameState.motherships[ownerId]
	if not guardPos and (not owner or not owner.alive) then
		return false
	end

	-- Kiểm tra fleet cap (trừ khi được phép bỏ qua)
	local weight = stats.weight or 1
	if not ignoreCap and FleetSystem.getUsedCap(ownerId) + weight > FleetSystem.getMaxCap(ownerId) then
		return false
	end

	-- Spawn ngay tại vị trí Tàu Mẹ rồi để nó bay ra ring cho đẹp
	local part = makeUnitPart(unitType, guardPos or owner.part.Position, (owner and owner.teamColor) or Config.TEAM.ENEMY)

	-- Buff hero (bị động, theo nhóm quân): nhân dmg/hp lúc spawn.
	local dmgMult, hpMult = FleetSystem.getHeroBuff(ownerId, stats.ring)
	local hp = math.floor(stats.hp * hpMult + 0.5)

	local vis = VISUAL[unitType]
	local unit = {
		kind = "Unit",          -- dùng cho CombatSystem phân loại target
		ownerId = ownerId,
		unitType = unitType,
		ring = stats.ring,      -- "SCREEN" | "GUARD" | "CORE"
		part = part,
		radius = math.max(part.Size.X, part.Size.Z) / 2, -- bán kính va chạm (theo size thực đã nhân hệ số)
		hp = hp,
		maxHp = hp,
		speed = stats.speed,
		weight = weight,
		-- Combat
		dmg = math.floor(stats.dmg * dmgMult + 0.5),
		range = stats.range,
		fireRate = stats.fireRate,
		aoe = stats.aoeRadius or 0,
		attack = stats.attack or "HITSCAN",       -- (Bước 3: COLLISION cho Kamikaze)
		targeting = stats.targeting or "STANDARD", -- (Bước 1-3: kiểu nhắm riêng)
		special = stats.special,                   -- (Bước 3: GRAVITY_STUN | KAMIKAZE)
		chargeTime = stats.chargeTime,             -- (Bước 2: telegraph nạp đạn Siege)
		projectile = stats.projectile,             -- (Lordz) bắn đạn bay thay vì hitscan
		projSpeed = stats.projSpeed,
		projRadius = stats.projRadius,
		projColor = stats.projColor,               -- màu đạn riêng (vd blast tím Battleship)
		coneAngle = stats.coneAngle,               -- (Lordz) Dragon: góc mở nón
		volleyCount = stats.volleyCount,           -- (Lordz) Battleship: số tia mỗi cụm laser
		melee = stats.melee,                       -- (Lordz) cận chiến: lao vào đánh áp sát
		aggro = stats.aggro,                       -- tầm phát hiện để bắt đầu lao phun
		-- Bước 3a — tham số CC (chỉ Titan có); pushOffset/stunnedUntil set lúc bị đánh.
		stunRadius = stats.stunRadius,
		stunDuration = stats.stunDuration,
		pushStrength = stats.pushStrength,
		-- Bước 3b — Kamikaze; armed/kamiTarget set khi lao.
		armRange = stats.armRange,
		guard = guardPos ~= nil, -- Warden guard: đứng gác, không cần Tàu Mẹ / không bị dọn
		cooldown = 0,           -- đếm lùi tới lần bắn kế
	}
	table.insert(GameState.units, unit)

	if not guardPos then FleetSystem.sendFleetUpdate(ownerId) end
	return true
end

-- BÙ NHÌN TEST: mục tiêu TĨNH, máu cực cao (gần như bất tử), KHÔNG bắn -> để quân
-- người chơi xả đạn thoải mái. Là "unit" phe địch (ownerId âm, không cần Tàu Mẹ) gắn
-- cờ `dummy`: không vào đội hình, không bị separation đẩy, không bị dọn khi thiếu chủ,
-- CombatSystem bỏ qua khi bắn.
local DUMMY_OWNER = -999
function FleetSystem.spawnDummy(pos)
	local part = makeUnitPart("Destroyer", pos, Config.TEAM.ENEMY)
	part.Size = part.Size * 2.6       -- bù nhìn TO cho dễ ngắm/xả đạn
	part:SetAttribute("Dummy", true)  -- để minimap nhận diện & hiển thị
	local unit = {
		kind = "Unit", ownerId = DUMMY_OWNER, unitType = "Destroyer", ring = "GUARD",
		part = part, radius = math.max(part.Size.X, part.Size.Z) / 2,
		hp = 1e12, maxHp = 1e12, speed = 0, weight = 0,
		dmg = 0, range = 0, fireRate = 1, aoe = 0,
		attack = "HITSCAN", targeting = "STANDARD",
		dummy = true, cooldown = 0,
	}
	table.insert(GameState.units, unit)
	return unit
end

-- Dọn unit chết / mất chủ; trả về true nếu có thay đổi để cập nhật HUD.
local function cleanupUnits()
	local changedOwners = {}
	for i = #GameState.units, 1, -1 do
		local u = GameState.units[i]
		local dead = (not u.part) or (not u.part.Parent)
		local remove = dead
		if not dead and not u.remnant and not u.dummy and not u.guard then
			-- Không phải tàn quân: mất chủ (Tàu Mẹ chết/rời) -> huỷ.
			-- (Tàu Mẹ chết đã convertToRemnants nên quân của nó thành tàn quân, giữ lại.)
			local owner = GameState.motherships[u.ownerId]
			remove = (not owner) or (not owner.alive)
		end
		if remove then
			if u.part and u.part.Parent then u.part:Destroy() end
			table.remove(GameState.units, i)
			changedOwners[u.ownerId] = true
		end
	end
	for ownerId in pairs(changedOwners) do
		FleetSystem.sendFleetUpdate(ownerId)
	end
end

-- Biến toàn bộ quân của owner (Tàu Mẹ vừa chết) thành TÀN QUÂN trung lập:
-- đứng im (ownerId=0), xám, không bắn/không bị bắn; ai chạm vào thì chiếm.
function FleetSystem.convertToRemnants(ownerId)
	for _, u in ipairs(GameState.units) do
		if u.ownerId == ownerId then
			u.ownerId = 0
			u.remnant = true
			u.armed = nil
			u.engaged = nil
			u.meleeTarget = nil
			u.cooldown = 0
			if u.part then
				u.part.Color = Color3.fromRGB(155, 158, 165) -- xám = trung lập
			end
		end
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
	-- Unit không xuyên mỏ / công trình / Tàu Mẹ (unit-vs-unit do separationPass lo).
	newPos = MapSystem.resolveSolids(newPos, u.radius or 2, nil)
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
-- Buffer TÁI SỬ DỤNG (tránh cấp phát bảng mỗi frame -> giảm GC). An toàn vì
-- server chạy đơn luồng và các hàm dùng buffer không lồng nhau.
local _fbuckets = {} -- 9 xô theo Config.FORMATION_ORDER (tái dùng, tránh cấp phát mỗi frame)
for _i = 1, 9 do _fbuckets[_i] = {} end
local _ordered = {}

-- HEX packing: xếp unit thành lưới LỤC GIÁC (honeycomb), mỗi unit cách hàng xóm đúng S studs.
local SQRT3_2 = 0.8660254
local HEX_DIRS = { { 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, 0 }, { -1, 1 }, { 0, 1 } } -- 6 hàng xóm axial
local _hexQ, _hexR = {}, {} -- buffer ô hex (tái dùng)

-- Sinh `n` ô hex (axial) theo xoắn ốc từ tâm ra. skipCenter=true -> chừa ô (0,0) cho Tàu Mẹ.
local function buildHexSlots(n, skipCenter)
	local count = 0
	if not skipCenter then count = 1; _hexQ[1], _hexR[1] = 0, 0 end
	local k = 1
	while count < n do
		local q, r = HEX_DIRS[5][1] * k, HEX_DIRS[5][2] * k
		for i = 1, 6 do
			local dq, dr = HEX_DIRS[i][1], HEX_DIRS[i][2]
			for _ = 1, k do
				if count >= n then break end
				count += 1
				_hexQ[count], _hexR[count] = q, r
				q += dq; r += dr
			end
			if count >= n then break end
		end
		k += 1
	end
end

local function packRings(list, center, dt, skipCenter)
	local n = #list
	if n == 0 then return end

	-- Sắp theo THỨ TỰ VÒNG 9 lớp (Config.FORMATION_ORDER): 1 = trong cùng -> 9 = ngoài cùng.
	-- Giữ nguyên thứ tự gốc trong mỗi lớp (ổn định slot, không giật khi cùng loại đông).
	for _i = 1, 9 do table.clear(_fbuckets[_i]) end
	table.clear(_ordered)
	local ORDER = Config.FORMATION_ORDER
	for _, u in ipairs(list) do
		local oi = (ORDER and ORDER[u.unitType]) or 8
		table.insert(_fbuckets[oi], u)
	end
	local ordered = _ordered
	for L = 1, 9 do
		for _, u in ipairs(_fbuckets[L]) do table.insert(ordered, u) end
	end

	-- Xếp vào lưới LỤC GIÁC quanh center: mỗi unit cách hàng xóm đúng S studs (gap đều),
	-- kể cả khi split (mỗi cụm cũng dùng chung hàm này).
	local S = Config.FLEET.HEX_SPACING or 11
	buildHexSlots(n, skipCenter)
	for i = 1, n do
		local q, r = _hexQ[i], _hexR[i]
		local wx = S * (q + r * 0.5) -- axial -> world (6 hàng xóm cách đều S)
		local wz = S * SQRT3_2 * r
		local target = Vector3.new(center.X + wx, center.Y, center.Z + wz)
		local faceDir
		if wx ~= 0 or wz ~= 0 then faceDir = Vector3.new(wx, 0, wz).Unit end
		steerUnit(ordered[i], target, faceDir, dt)
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

-- Buffer tái sử dụng: gom unit theo owner + tối đa 16 CỤM khi split (Lordz-style).
local _ownerList = {}
local _clusters = {}
for _i = 1, 16 do _clusters[_i] = {} end
local TWO_PI = 2 * math.pi

-- Cập nhật vị trí toàn bộ unit theo quỹ đạo (gọi mỗi Heartbeat).
-- SPLIT Lordz: hạm đội chia C=2^level cụm. Cụm VUA bám ngay Tàu Mẹ (lõi phòng thủ),
-- C-1 cụm vệ tinh toả TRƯỚC MẶT theo hướng đi. Mỗi cụm 1 sub-leader anchor, unit
-- packRings quanh anchor. Hết giờ -> tự gộp dần, mọi cụm hút về toạ độ Vua.
-- Lane vệ tinh k (0..sat-1) -> [-1, 1] (rải đối xứng quanh trục con trỏ).
local function laneOffset(k, sat)
	if sat <= 1 then return 0 end
	return (k / (sat - 1) - 0.5) * 2
end

-- Tốc độ TB của 1 cụm (cụm toàn quân nhanh -> anchor phóng nhanh -> slingshot rõ).
local function avgSpeed(buf)
	local n = #buf
	if n == 0 then return 0 end
	local s = 0
	for _, u in ipairs(buf) do s += (u.speed or 30) end
	return s / n
end

-- MÔ PHỎNG VỆ TINH (multi-vector attraction to cursor). Mỗi cụm vệ tinh = 1 anchor
-- ĐỘNG (pos+vel) tự chase con trỏ (owner.aimPoint):
--   - funnel  : gần con trỏ thì lane co về 0 -> các cụm chụm vào 1 điểm.
--   - slingshot: bám bằng quán tính -> cụm nhanh vọt qua con trỏ rồi lượn vòng.
--   - deflection: 2 anchor quá sát -> đẩy góc để chạy song song, không dính nhau.
-- Khi GỘP (owner.rejoining): mọi anchor hút thẳng về Vua (center) -> re-center.
-- Dùng buffer _clusters đã được updateFormation nạp: cụm vệ tinh j dùng _clusters[j+1].
local function stepSatellites(owner, center, C, dt)
	local F = Config.FLEET
	local sat = C - 1
	local st = owner.satState or {}
	owner.satState = st

	-- Điểm "master": con trỏ thô; khi gộp -> Vua; thiếu con trỏ -> trước mặt Tàu Mẹ.
	local masterPt
	if owner.rejoining then
		masterPt = center
	elseif owner.aimPoint then
		masterPt = owner.aimPoint
	else
		local f = owner.facing or Vector3.new(1, 0, 0)
		masterPt = center + Vector3.new(f.X, 0, f.Z) * 120
	end
	local md = Vector3.new(masterPt.X - center.X, 0, masterPt.Z - center.Z)
	if md.Magnitude < 1e-3 then
		local f = owner.facing or Vector3.new(1, 0, 0)
		md = Vector3.new(f.X, 0, f.Z)
		md = (md.Magnitude > 1e-3) and md.Unit or Vector3.new(1, 0, 0)
	else
		md = md.Unit
	end
	local perp = Vector3.new(-md.Z, 0, md.X)

	local spread   = F.SPLIT_SAT_SPREAD or 40
	local funnel   = F.SPLIT_SAT_FUNNEL or 120
	local accelK   = F.SPLIT_SAT_ACCEL or 9
	local speedMul = F.SPLIT_SAT_SPEED_MULT or 1.3
	local minGap   = F.SPLIT_SAT_MINGAP or 28
	local repel    = F.SPLIT_SAT_REPEL or 80
	local burst    = F.SPLIT_SAT_BURST or 100
	local maxRange = F.SPLIT_SAT_MAX_RANGE or 280
	local baseSpeed = Config.MOTHERSHIP.SPEED or 70

	-- Cụm mới tách ra -> bung từ Vua với xung tốc dọc lane (split launch).
	for j = 1, sat do
		if not st[j] then
			local lane = laneOffset(j - 1, sat)
			local dir = md + perp * (lane * 0.8)
			dir = (dir.Magnitude > 1e-3) and dir.Unit or md
			st[j] = { pos = center, vx = dir.X * burst, vz = dir.Z * burst }
		end
	end
	for j = sat + 1, 16 do st[j] = nil end

	-- PASS 1: tính vận tốc mới (đọc vị trí HIỆN TẠI của mọi anchor -> đối xứng).
	for j = 1, sat do
		local a = st[j]
		local target
		if owner.rejoining then
			target = center
		else
			local dAim = (masterPt - a.pos).Magnitude
			local spreadMag = spread * math.clamp(dAim / funnel, 0, 1) -- funnel: gần -> 0
			target = masterPt + perp * (laneOffset(j - 1, sat) * spreadMag)
		end
		-- kẹp đích trong tầm quanh Vua
		local offx, offz = target.X - center.X, target.Z - center.Z
		local offm = math.sqrt(offx * offx + offz * offz)
		if offm > maxRange then
			target = Vector3.new(center.X + offx / offm * maxRange, center.Y, center.Z + offz / offm * maxRange)
		end

		local maxSpeed = math.max(avgSpeed(_clusters[j + 1]), baseSpeed) * speedMul
		local tx, tz = target.X - a.pos.X, target.Z - a.pos.Z
		local tm = math.sqrt(tx * tx + tz * tz)
		local desx, desz = 0, 0
		if tm > 1e-3 then desx, desz = tx / tm * maxSpeed, tz / tm * maxSpeed end
		local k = math.min(accelK * dt, 1)
		local vx = a.vx + (desx - a.vx) * k
		local vz = a.vz + (desz - a.vz) * k

		-- angular deflection: đẩy khỏi anchor khác quá sát
		for o = 1, sat do
			if o ~= j then
				local b = st[o]
				local dx, dz = a.pos.X - b.pos.X, a.pos.Z - b.pos.Z
				local m = math.sqrt(dx * dx + dz * dz)
				if m > 1e-3 and m < minGap then
					local push = repel * (1 - m / minGap) * dt
					vx += dx / m * push
					vz += dz / m * push
				end
			end
		end
		-- kẹp tốc độ
		local sp = math.sqrt(vx * vx + vz * vz)
		if sp > maxSpeed and sp > 1e-3 then
			vx, vz = vx / sp * maxSpeed, vz / sp * maxSpeed
		end
		a._nx, a._nz = vx, vz
	end

	-- PASS 2: tích hợp vị trí + xếp đội hình cụm quanh anchor.
	for j = 1, sat do
		local a = st[j]
		a.vx, a.vz = a._nx or 0, a._nz or 0
		a.pos = Vector3.new(a.pos.X + a.vx * dt, center.Y, a.pos.Z + a.vz * dt)
		local buf = _clusters[j + 1]
		if #buf > 0 then
			packRings(buf, a.pos, dt, false) -- cụm vệ tinh: hex đặc từ tâm (không chừa lỗ)
		end
	end
end

local function updateFormation(dt)
	-- Góc quay chung, chậm -> cả hạm đội "sống"
	globalTheta = (globalTheta + Config.FLEET.ORBIT_SPIN * dt) % (2 * math.pi)

	local F = Config.FLEET
	local maxLevel = F.SPLIT_MAX_LEVEL or 4
	local now = os.clock()

	-- Duyệt theo TỪNG owner, gom unit của owner vào buffer dùng lại (không cấp phát
	-- bảng groups mỗi frame). Bỏ qua Kamikaze đã kích hoạt (u.armed): CombatSystem tự lái.
	for ownerId, owner in pairs(GameState.motherships) do
		if owner.alive and owner.part then
			table.clear(_ownerList)
			for _, u in ipairs(GameState.units) do
				if u.ownerId == ownerId and not u.armed and not u.engaged then
					table.insert(_ownerList, u) -- đang lao cận chiến (engaged) -> CombatSystem tự lái
				end
			end

			if #_ownerList > 0 then
				local center = owner.part.Position

				-- Máy trạng thái GỘP: hết cooldown (động) không bấm -> vào chế độ gộp;
				-- gộp thì hạ 1 bậc mỗi SPLIT_REJOIN_STEP (16→8→…→1), vệ tinh hút về Vua.
				local level = (owner.split and now < (owner.rejoinAt or 0)) and 1 or 0 -- split nhị phân + cooldown
				if false then -- (máy gộp cũ đã bỏ; split giờ nhị phân, luôn 2 đội)
					if not owner.rejoining and now >= (owner.rejoinAt or 0) then
						owner.rejoining = true
						owner.rejoinNext = now
					end
					if owner.rejoining and now >= (owner.rejoinNext or 0) then
						level -= 1
						owner.splitLevel = level
						-- Đứng yên -> gom nhanh; đang lái chạy -> gom chậm (cụm rượt đuôi Vua).
						local moving = owner.targetPoint
							and Util.flatDist(owner.part.Position, owner.targetPoint) > (Config.MOTHERSHIP.STOP_DIST or 2) * 3
						owner.rejoinNext = now + (moving and (F.SPLIT_REJOIN_STEP_MOVING or 1.4) or (F.SPLIT_REJOIN_STEP or 0.5))
					end
				end
				level = math.clamp(level, 0, maxLevel)

				local C = 2 ^ level -- 1,2,4,8,16
				if C <= 1 then
					-- 1 cụm: đội hình quanh Tàu Mẹ; xoá state vệ tinh -> split sau bung lại từ đầu.
					owner.splitOffset = Vector3.zero -- hợp về 1 đội -> reset offset
					packRings(_ownerList, center, dt, true) -- hex quanh Tàu Mẹ (chừa ô giữa cho ship)
				else
					-- Chia round-robin: cụm 1 = VUA (bám Tàu Mẹ), cụm 2..C = vệ tinh CHASE con trỏ.
					for j = 1, C do table.clear(_clusters[j]) end
					for idx, u in ipairs(_ownerList) do
						table.insert(_clusters[((idx - 1) % C) + 1], u)
					end
					if #_clusters[1] > 0 then
						packRings(_clusters[1], center, dt, true) -- cụm Vua: hex quanh Tàu Mẹ (chừa ô giữa)
					end
					-- ĐỘI 2: cách CỐ ĐỊNH theo hướng đi; nếu đang TARGET (click) thì phóng về mục tiêu.
						local dir, dist
						local ft = owner.attackTarget
						if ft and ft.part and ft.part.Parent and ft.ownerId ~= ownerId and (ft.kind ~= "Mothership" or ft.alive) then
							local tx, tz = ft.part.Position.X - center.X, ft.part.Position.Z - center.Z
							local mm = math.sqrt(tx * tx + tz * tz)
							if mm > 1e-3 then dir = Vector3.new(tx / mm, 0, tz / mm) end
							dist = math.clamp(mm, F.SPLIT_FIXED_DIST or 65, F.SPLIT_TARGET_MAX or 200)
						end
						if not dir then
							local f = owner.facing or Vector3.new(1, 0, 0)
							local mm = math.sqrt(f.X * f.X + f.Z * f.Z)
							dir = mm > 1e-3 and Vector3.new(f.X / mm, 0, f.Z / mm) or Vector3.new(1, 0, 0)
							dist = F.SPLIT_FIXED_DIST or 65
						end
						local desired = dir * dist
						local cur = owner.splitOffset or Vector3.zero
						local dd = desired - cur
						local dmv = dd.Magnitude
						local stp = (F.SPLIT_OFFSET_SPEED or 240) * dt
						owner.splitOffset = (dmv <= stp or dmv < 1e-4) and desired or (cur + dd.Unit * stp)
						if #_clusters[2] > 0 then packRings(_clusters[2], center + owner.splitOffset, dt, false) end
				end
			end
		end
	end
end

-- Nhận tín hiệu Split từ client: MỖI lần bấm Space = phân hạch +1 bậc (nhân đôi số
-- cụm). Server quyết định cấp + hẹn giờ tự gộp. Bấm liên tục -> giữ trạng thái tách.
local function onSplitInput(player)
	local owner = GameState.motherships[player.UserId]
	if not owner then return end
	local maxLevel = Config.FLEET.SPLIT_MAX_LEVEL or 4
	owner.split = true -- LUÔN tách 2 đội (giữ tới hết cooldown)
	-- Cooldown GIỮ split = BASE + (cấp-1)×PER_LEVEL (stacking) + số_quân×PER_UNIT (scale-to-size).
	local F = Config.FLEET
	local n = 0
	for _, u in ipairs(GameState.units) do
		if u.ownerId == player.UserId and not u.remnant then n += 1 end
	end
	local delay = (F.SPLIT_REJOIN_BASE or 6)
		+ 0 -- (bỏ stacking theo cấp; split giờ nhị phân)
		+ n * (F.SPLIT_REJOIN_PER_UNIT or 0.04)
	owner.rejoinAt = os.clock() + math.min(delay, F.SPLIT_REJOIN_MAX or 30)
	owner.rejoining = false -- bấm split lại -> huỷ chế độ gộp, chase con trỏ + gia hạn cooldown
end

-- Con trỏ THÔ từ client (không kẹp leash) -> điểm master cho vệ tinh split chase.
local function onAimInput(player, pt)
	if typeof(pt) ~= "Vector3" then return end
	local owner = GameState.motherships[player.UserId]
	if owner then owner.aimPoint = pt end
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
		if part and part.Parent and not u.armed and not u.dummy and not u.engaged then -- lao/bù nhìn: không xô đẩy
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

	-- Áp lực đẩy (kẹp để không giật). Tàn quân KHÔNG bị đẩy (đứng im chờ được chiếm).
	for _, u in ipairs(units) do
		local part = u.part
		if part and part.Parent and not u.armed and not u.remnant and not u.dummy and not u.engaged
			and u._sx and (u._sx ~= 0 or u._sz ~= 0) then
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

-- Tàu Mẹ chạm (trong CAPTURE_RANGE) tàn quân đứng im -> chiếm về đội mình (nếu còn cap).
function FleetSystem.captureRemnants()
	local range = Config.FLEET.CAPTURE_RANGE or 18
	for _, u in ipairs(GameState.units) do
		if u.remnant and u.part and u.part.Parent then
			for id, ms in pairs(GameState.motherships) do
				if ms.alive and ms.part then
					local d = (ms.part.Position - u.part.Position).Magnitude
					if d <= range then
						if FleetSystem.getUsedCap(id) + (u.weight or 1) <= FleetSystem.getMaxCap(id) then
							u.ownerId = id
							u.remnant = false
							u.cooldown = 0
							u.part.Color = ms.teamColor -- nhuộm màu phe mới
							FleetSystem.sendFleetUpdate(id)
						end
						break -- đã gặp 1 Tàu Mẹ trong tầm -> khỏi xét tiếp
					end
				end
			end
		end
	end
end

-- Xoá toàn bộ unit của 1 owner (dùng khi reset người kết liễu Warden / dọn guard Warden).
function FleetSystem.clearOwner(ownerId)
	for i = #GameState.units, 1, -1 do
		local u = GameState.units[i]
		if u.ownerId == ownerId then
			if u.part then u.part:Destroy() end
			table.remove(GameState.units, i)
		end
	end
	FleetSystem.sendFleetUpdate(ownerId)
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
	Remotes.AimInput.OnServerEvent:Connect(onAimInput)

	RunService.Heartbeat:Connect(function(dt)
		cleanupUnits()
		FleetSystem.captureRemnants() -- Tàu Mẹ chạm tàn quân -> chiếm
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
