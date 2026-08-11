--[[
	CombatSystem.luau
	-----------------
	Auto-battler combat (server-authoritative, hitscan).

	Mỗi Heartbeat, với mỗi unit sẵn sàng bắn (cooldown về 0):
	  1. Tìm mục tiêu theo ƯU TIÊN: enemy Units > enemy Buildings > enemy Mothership,
	     trong đó chọn cái GẦN NHẤT còn trong tầm (range).
	  2. Gây damage tức thì (hitscan). PlasmaCruiser: damage mọi enemy trong bán
	     kính AoE quanh mục tiêu.
	  3. Bắn RemoteEvent để client vẽ tia laser (VFX ở client, damage ở server).
	  4. Reset cooldown = 1 / fireRate.

	HP về 0: unit -> huỷ part; mothership -> loại người/bot đó (game over).

	M2 dùng "enemy dummy" (bấm E) để test. Bot thật ở M5 sẽ dùng chung hệ này.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Config)
local Util = require(ReplicatedStorage.Util)
local Remotes = require(ReplicatedStorage.Remotes)
local GameState = require(script.Parent.GameState)
local MothershipSystem = require(script.Parent.MothershipSystem)
local FleetSystem = require(script.Parent.FleetSystem)
local BuildingSystem = require(script.Parent.BuildingSystem)
local EconomySystem = require(script.Parent.EconomySystem)
local QuestSystem = require(script.Parent.QuestSystem)

local CombatSystem = {}

-- Còn địch (bot) nào sống không? (dùng cho điều kiện thắng)
local function anyEnemyAlive()
	for _, e in pairs(GameState.motherships) do
		if e.isBot and e.alive then
			return true
		end
	end
	return false
end

-- Tên hiển thị của 1 chủ (player -> tên tài khoản; bot -> "Bot N" theo id âm).
local function displayName(ownerId)
	if not ownerId then return nil end
	if ownerId < 0 then return "Bot " .. tostring(-ownerId) end
	local p = Players:GetPlayerByUserId(ownerId)
	return Config.PLAYER_PREFIX .. ((p and p.Name) or "Player")
end

-- Thống kê lúc chết/thắng để hiện lên bảng kết thúc.
local function statsFor(ent)
	local fleet = 0
	for _, u in ipairs(GameState.units) do
		if u.ownerId == ent.ownerId then fleet += 1 end
	end
	local survived = ent.spawnTime and (os.clock() - ent.spawnTime) or 0
	local s = ent.stats or {}
	return {
		survived = math.floor(survived),
		unitsKilled = s.unitsKilled or 0,
		mothershipsKilled = s.mothershipsKilled or 0,
		scrapSpent = math.floor(s.scrapSpent or 0),
		unitsLost = s.unitsLost or 0,
		gems = EconomySystem.getGems(ent.ownerId), -- gem thật đã kiếm được
		fleet = fleet,
	}
end

-- Thưởng Gem cuối trận theo thành tích (base + unit/tàu địch diệt + thời gian sống;
-- thắng cả trận +VICTORY_BONUS). Chỉ cho người chơi. Cộng TRƯỚC khi chụp stats để
-- bảng kết thúc hiện đúng số gem mới.
local function awardMatchGems(ent, isVictory)
	if ent.isBot then return end
	local g = Config.GEMS or {}
	local s = ent.stats or {}
	local survived = ent.spawnTime and (os.clock() - ent.spawnTime) or 0
	local reward = (g.MATCH_BASE or 0)
		+ (s.unitsKilled or 0) * (g.PER_UNIT_KILL or 0)
		+ (s.mothershipsKilled or 0) * (g.PER_SHIP_KILL or 0)
		+ math.floor(survived / 10) * (g.PER_10S_ALIVE or 0)
		+ (isVictory and (g.VICTORY_BONUS or 0) or 0)
	if reward > 0 then EconomySystem.addGem(ent.ownerId, reward) end
end

-- Xử lý Tàu Mẹ chết -> loại khỏi ván + phát GameOver (kèm killer + thống kê).
local function killMothership(ent)
	if not ent.alive then return end
	ent.alive = false
	local ownerId = ent.ownerId
	local wasBot = ent.isBot
	local killerName = displayName(ent.lastAttackerId)
	awardMatchGems(ent, false) -- thưởng Gem cuối trận (thua) trước khi chụp stats
	local deadStats = statsFor(ent)

	-- Ghi công + THƯỞNG scrap cho kẻ hạ Tàu Mẹ này.
	local killer = ent.lastAttackerId and GameState.motherships[ent.lastAttackerId]
	if killer then
		if killer.stats then killer.stats.mothershipsKilled += 1 end
		-- ③ BOUNTY: cộng thêm % scrap CỦA NẠN NHÂN (đọc TRƯỚC khi onDeath cắt 1/2)
		-- -> hạ kẻ giàu/dẫn đầu càng lời -> underdog có động lực gỡ điểm.
		local bounty = math.floor(EconomySystem.getScrap(ownerId) * (Config.ECONOMY.KILL_BOUNTY_RATE or 0))
		EconomySystem.add(ent.lastAttackerId, Config.ECONOMY.MOTHERSHIP_KILL_REWARD + bounty)
		EconomySystem.addGem(ent.lastAttackerId, Config.ECONOMY.MOTHERSHIP_KILL_GEM) -- +gem
		QuestSystem.onMothershipKill(ent.lastAttackerId) -- tiến độ quest (daily/weekly/unique)
		-- (thưởng scrap -> level tự lên vì level suy từ tổng scrap.)
	end

	if ent.part then
		Remotes.Shockwave:FireAllClients(ent.part.Position, 34, Color3.fromRGB(255, 140, 50)) -- Tàu Mẹ NỔ
		ent.part:Destroy()
	end
	GameState.motherships[ownerId] = nil
	-- Chết: scrap tụt còn 1/2 + tụt 1 cấp (scrap lưu bền theo owner).
	EconomySystem.onDeath(ownerId)
	-- Công trình của owner này biến mất theo Tàu Mẹ.
	BuildingSystem.destroyOwnerBuildings(ownerId)
	-- Quân còn lại KHÔNG bị huỷ: biến thành TÀN QUÂN đứng im, ai chạm vào thì chiếm.
	FleetSystem.convertToRemnants(ownerId)

	if not wasBot then
		-- Người chơi thua
		local player = Players:GetPlayerByUserId(ownerId)
		if player then
			Remotes.GameOver:FireClient(player, {
				result = "defeat",
				killer = killerName,
				stats = deadStats,
			})
		end
	else
		-- 1 địch chết -> nếu hết địch thì mọi người chơi còn sống đều thắng.
		-- (Bỏ qua khi MAINTAIN>0: bot luôn respawn nên không có "thắng do diệt sạch".)
		if (Config.BOT.MAINTAIN or 0) <= 0 and not anyEnemyAlive() then
			for _, e in pairs(GameState.motherships) do
				if not e.isBot then
					local p = Players:GetPlayerByUserId(e.ownerId)
					if p then
						awardMatchGems(e, true) -- thưởng Gem thắng trước khi chụp stats
						Remotes.GameOver:FireClient(p, {
							result = "victory",
							stats = statsFor(e),
						})
					end
				end
			end
		end
	end
end

CombatSystem.killMothership = killMothership -- expose cho OOB death (MothershipSystem.killFn)

-- Gây damage cho 1 entity (unit hoặc mothership) và xử lý chết.
local function damageEntity(ent, amount, attackerOwner)
	if ent.kind == "Mothership" then
		if not ent.alive then return end
		if attackerOwner then ent.lastAttackerId = attackerOwner end -- nhớ ai bắn phát cuối
		ent.lastDamageTime = os.clock() -- mốc "vừa trúng đòn" -> hoãn hồi máu
		ent.hp -= amount
		MothershipSystem.updateHealthBar(ent)
		if ent.hp <= 0 then
			killMothership(ent)
		end
	elseif ent.kind == "Building" then
		if not ent.part or not ent.part.Parent then return end
		ent.hp -= amount
		ent.lastDamageTime = os.clock() -- cho bot biết công trình đang bị đánh
		BuildingSystem.updateHealthBar(ent)
		-- Công trình của MÌNH bị địch đánh -> báo động minimap (throttle ~1s).
		if attackerOwner and attackerOwner ~= ent.ownerId then
			local p = Players:GetPlayerByUserId(ent.ownerId)
			if p and (os.clock() - (ent.lastAlert or 0)) > 1 then
				ent.lastAlert = os.clock()
				Remotes.BuildingAlert:FireClient(p, ent.part.Position)
			end
		end
		if ent.hp <= 0 then
			if attackerOwner then -- thưởng scrap cho kẻ phá công trình địch
				EconomySystem.add(attackerOwner, Config.ECONOMY.BUILDING_KILL_REWARD)
			end
			if ent.isWardenCore and CombatSystem.onWardenCore then
				-- Hạ trùm: thưởng + reset người kết liễu + Warden hồi sinh (WardenSystem lo).
				CombatSystem.onWardenCore(attackerOwner)
			end
			if ent.part then
				local r = ent.isWardenCore and 60 or 16 -- Warden nổ CỰC lớn
				Remotes.Shockwave:FireAllClients(ent.part.Position, r, Color3.fromRGB(255, 150, 60))
			end
			BuildingSystem.destroyBuilding(ent)
		end
	else -- Unit
		if not ent.part or not ent.part.Parent then return end
		ent.hp -= amount
		if ent.hp <= 0 then
			-- Thống kê: chủ unit +1 "quân mất", kẻ bắn +1 "địch hạ".
			local victimOwner = GameState.motherships[ent.ownerId]
			if victimOwner and victimOwner.stats then victimOwner.stats.unitsLost += 1 end
			local killer = attackerOwner and GameState.motherships[attackerOwner]
			if killer and killer.stats then killer.stats.unitsKilled += 1 end
			ent.part:Destroy() -- FleetSystem.cleanup sẽ gỡ khỏi list + update HUD
		end
	end
end

-- Đường bắn từ `attackerPos` tới Tàu Mẹ `ship` có bị unit phe-thủ chắn ngang không?
-- Chỉ chạy khi SHIP_GUARD bật. Một unit của chính chủ Tàu Mẹ được coi là "chắn" khi:
--   - nằm GIỮA attacker và ship (tham số chiếu t trong khoảng (edge, 1-edge)), và
--   - đủ sát đường bắn (khoảng cách vuông góc <= bán kính unit + lề).
-- => fleet dày ở phía nào thì che phía đó; fleet thủng/chết thì đường bắn hở -> ship dính đạn.
local function shotBlockedByFleet(attackerPos, ship)
	local guard = Config.COMBAT.SHIP_GUARD
	if not (guard and guard.ENABLED) then return false end
	local shipPos = ship.part.Position
	local edge = guard.EDGE_IGNORE or 0
	for _, u in ipairs(GameState.units) do
		if u.ownerId == ship.ownerId and u.part and u.part.Parent then
			local perp, t = Util.flatPointSegment(u.part.Position, attackerPos, shipPos)
			if t > edge and t < (1 - edge) then
				local blockR = (u.radius or 2) + guard.BLOCK_MARGIN
				if perp <= blockR then
					return true
				end
			end
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- LƯỚI KHÔNG GIAN cho targeting (thay quét O(n²) bằng quét ô lân cận).
-- Dựng 1 lần/frame ở updateCombat; findTarget chỉ duyệt các ô trong tầm.
-------------------------------------------------------------------------------
local GRID_CELL = 20
local unitGrid = {} -- [cx][cz] = { unit, ... } — dựng lại mỗi frame

local function rebuildUnitGrid()
	table.clear(unitGrid)
	for _, u in ipairs(GameState.units) do
		if u.part and u.part.Parent and not u.remnant then -- tàn quân trung lập: không vào lưới target
			local p = u.part.Position
			local cx = math.floor(p.X / GRID_CELL)
			local cz = math.floor(p.Z / GRID_CELL)
			local col = unitGrid[cx]
			if not col then col = {}; unitGrid[cx] = col end
			local cell = col[cz]
			if not cell then cell = {}; col[cz] = cell end
			cell[#cell + 1] = u
		end
	end
end

-- Enemy unit gần nhất trong tầm quanh `pos`, chỉ duyệt ô lân cận.
-- ringName (tuỳ chọn): chỉ tính unit thuộc ring đó. reject (tuỳ chọn): loại 1 unit.
local function gridNearestEnemyUnit(pos, myOwner, range, ringName, reject)
	local cx = math.floor(pos.X / GRID_CELL)
	local cz = math.floor(pos.Z / GRID_CELL)
	local r = math.ceil(range / GRID_CELL)
	local best, bestD
	for gx = cx - r, cx + r do
		local col = unitGrid[gx]
		if col then
			for gz = cz - r, cz + r do
				local cell = col[gz]
				if cell then
					for _, o in ipairs(cell) do
						if o.ownerId ~= myOwner and o ~= reject and o.part and o.part.Parent
							and (not ringName or o.ring == ringName) then
							local d = (o.part.Position - pos).Magnitude
							if d <= range and (not bestD or d < bestD) then best, bestD = o, d end
						end
					end
				end
			end
		end
	end
	return best
end

-- Enemy unit gần nhất Ở MỘT RING cụ thể (dùng cho BACKLINE_SEEK).
local function nearestEnemyUnitInRing(u, ringName)
	return gridNearestEnemyUnit(u.part.Position, u.ownerId, u.range, ringName)
end

-- Tối đa `n` enemy UNIT gần nhất trong tầm (dùng cho MULTI_TARGET) — quét lưới.
local function nearestEnemyUnits(u, n)
	local pos = u.part.Position
	local myOwner = u.ownerId
	local range = u.range
	local cx = math.floor(pos.X / GRID_CELL)
	local cz = math.floor(pos.Z / GRID_CELL)
	local r = math.ceil(range / GRID_CELL)
	local list = {}
	for gx = cx - r, cx + r do
		local col = unitGrid[gx]
		if col then
			for gz = cz - r, cz + r do
				local cell = col[gz]
				if cell then
					for _, other in ipairs(cell) do
						if other.ownerId ~= myOwner and other.part and other.part.Parent then
							local d = (other.part.Position - pos).Magnitude
							if d <= range then list[#list + 1] = { u = other, d = d } end
						end
					end
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.d < b.d end)
	local out = {}
	for i = 1, math.min(n, #list) do out[i] = list[i].u end
	return out
end

-- FOCUS-FIRE: mục tiêu do người chơi CLICK (owner.attackTarget). Trả về nó nếu còn
-- hợp lệ + hợp LOẠI mà unit này bắn được + trong tầm (Tàu Mẹ địch phải không bị fleet
-- của nó chắn). Không thoả -> nil (unit rơi về nhắm gần nhất -> vẫn tự vệ được).
local function focusTarget(u)
	local ownerEnt = GameState.motherships[u.ownerId]
	local ft = ownerEnt and ownerEnt.attackTarget
	if not ft then return nil end
	-- còn tồn tại + là địch?
	local ok = ft.part and ft.part.Parent and ft.ownerId ~= u.ownerId
	if ok and ft.kind == "Mothership" then ok = ft.alive end
	if not ok then ownerEnt.attackTarget = nil; return nil end -- mục tiêu chết/mất -> xoá
	-- unit này có bắn được LOẠI đó không? (Siege chỉ building; tháp chỉ unit)
	if u.targeting == "BUILDING_ONLY" and ft.kind ~= "Building" then return nil end
	if u.targeting == "UNITS_ONLY" and ft.kind ~= "Unit" then return nil end
	-- trong tầm?
	if (ft.part.Position - u.part.Position).Magnitude > u.range then return nil end
	-- Tàu Mẹ vẫn được "chắn thân" bảo vệ: còn fleet che thì chưa bắn xuyên được.
	if ft.kind == "Mothership" and shotBlockedByFleet(u.part.Position, ft) then return nil end
	return ft
end

-- Tìm mục tiêu tốt nhất cho 1 unit theo ưu tiên + gần nhất trong tầm.
local function findTarget(u)
	local pos = u.part.Position
	local myOwner = u.ownerId
	local range = u.range

	-- Ưu tiên TUYỆT ĐỐI: mục tiêu người chơi tự click (focus-fire cả fleet).
	local focus = focusTarget(u)
	if focus then return focus end

	-- UNITS_ONLY (tháp phòng thủ): ưu tiên enemy Unit gần nhất; không có thì bắn
	-- Tàu Mẹ địch đang áp sát base (nếu không bị fleet của nó chắn). KHÔNG bắn building.
	if u.targeting == "UNITS_ONLY" then
		local best = gridNearestEnemyUnit(pos, myOwner, range)
		if best then return best end
		local bestD
		for _, e in pairs(GameState.motherships) do
			if e.ownerId ~= myOwner and e.alive and e.part then
				local d = (e.part.Position - pos).Magnitude
				if d <= range and (not bestD or d < bestD) and not shotBlockedByFleet(pos, e) then
					best, bestD = e, d
				end
			end
		end
		return best
	end

	-- BUILDING_ONLY (Siege): chỉ nhắm enemy Building, bỏ qua Unit & Mothership.
	if u.targeting == "BUILDING_ONLY" then
		local best, bestD
		for _, b in ipairs(GameState.buildings) do
			if b.ownerId ~= myOwner and b.part and b.part.Parent then
				local d = (b.part.Position - pos).Magnitude
				if d <= range and (not bestD or d < bestD) then best, bestD = b, d end
			end
		end
		return best
	end

	-- BACKLINE_SEEK: ưu tiên pháo địch ở CORE; không có thì rơi về STANDARD.
	if u.targeting == "BACKLINE_SEEK" then
		local core = nearestEnemyUnitInRing(u, "CORE")
		if core then return core end
	end

	-- 1) enemy UNITS (quét lưới, không O(n²))
	local best = gridNearestEnemyUnit(pos, myOwner, range)
	if best then return best end
	local bestDist

	-- 2) enemy BUILDINGS
	for _, b in ipairs(GameState.buildings) do
		if b.ownerId ~= myOwner and b.part and b.part.Parent then
			local d = (b.part.Position - pos).Magnitude
			if d <= range and (not bestDist or d < bestDist) then
				best, bestDist = b, d
			end
		end
	end
	if best then return best end

	-- 3) enemy MOTHERSHIP — chỉ nhắm được nếu đường bắn KHÔNG bị fleet của nó chắn.
	--    (Đây là "chắn thân": còn tường unit che giữa thì địch không chạm được Tàu Mẹ.)
	for _, e in pairs(GameState.motherships) do
		if e.ownerId ~= myOwner and e.alive and e.part then
			local d = (e.part.Position - pos).Magnitude
			if d <= range and (not bestDist or d < bestDist) then
				if not shotBlockedByFleet(pos, e) then
					best, bestDist = e, d
				end
			end
		end
	end
	return best
end

-- AoE: gom mọi enemy trong bán kính rồi mới gây damage (tránh sửa bảng khi đang duyệt).
local function applyAoe(centerPos, radius, attackerOwner, dmg, primary)
	local hits = {}
	for _, other in ipairs(GameState.units) do
		if other ~= primary and other.ownerId ~= attackerOwner and not other.remnant and other.part and other.part.Parent then
			if (other.part.Position - centerPos).Magnitude <= radius then
				table.insert(hits, other)
			end
		end
	end
	for _, e in pairs(GameState.motherships) do
		if e ~= primary and e.ownerId ~= attackerOwner and e.alive and e.part then
			if (e.part.Position - centerPos).Magnitude <= radius then
				table.insert(hits, e)
			end
		end
	end
	for _, ent in ipairs(hits) do
		damageEntity(ent, dmg, attackerOwner)
	end
end

-------------------------------------------------------------------------------
-- ĐẠN BAY (Lordz): xạ thủ (Archer/Mage) bắn projectile bay THẲNG theo hướng chốt
-- lúc bắn, trúng ĐỊCH ĐẦU TIÊN trên đường -> quân đứng trước ĐỠ ĐẠN cho tuyến sau
-- (mở rộng body-block ra mọi hướng). Đạn có aoe (Mage) -> nổ lan tại điểm trúng.
-------------------------------------------------------------------------------
local projectiles = {} -- logic thuần (KHÔNG Part) -> nhẹ mạng; VFX do client tự vẽ
local PROJ_MS_RADIUS = (Config.MOTHERSHIP.RADIUS or 6) * 1.4
local PROJ_BUILDING_RADIUS = 12

local function flatUnitDir(from, to)
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if d.Magnitude < 1e-3 then return nil end
	return d.Unit
end

-- Địch ĐẦU TIÊN chạm đạn quanh `pos` (unit qua lưới + Mothership + Building). nil nếu trống.
local function firstEnemyHit(pr, pos)
	local best, bestD
	local cx = math.floor(pos.X / GRID_CELL)
	local cz = math.floor(pos.Z / GRID_CELL)
	for gx = cx - 1, cx + 1 do
		local col = unitGrid[gx]
		if col then
			for gz = cz - 1, cz + 1 do
				local cell = col[gz]
				if cell then
					for _, u in ipairs(cell) do
						if not pr.buildingOnly and u.ownerId ~= pr.ownerId then
							local d = (u.part.Position - pos).Magnitude
							if d <= pr.radius + (u.radius or 2) and (not bestD or d < bestD) then best, bestD = u, d end
						end
					end
				end
			end
		end
	end
	for _, e in pairs(GameState.motherships) do
		if not pr.buildingOnly and e.ownerId ~= pr.ownerId and e.alive and e.part then
			local d = (e.part.Position - pos).Magnitude
			if d <= pr.radius + PROJ_MS_RADIUS and (not bestD or d < bestD) then best, bestD = e, d end
		end
	end
	for _, b in ipairs(GameState.buildings) do
		if b.ownerId ~= pr.ownerId and b.part and b.part.Parent then
			local d = (b.part.Position - pos).Magnitude
			if d <= pr.radius + PROJ_BUILDING_RADIUS and (not bestD or d < bestD) then best, bestD = b, d end
		end
	end
	return best
end

local function spawnProjectile(attacker, target)
	local origin = attacker.part.Position
	local dir = flatUnitDir(origin, target.part.Position)
	if not dir then return end
	local owner = GameState.motherships[attacker.ownerId]
	local color = attacker.projColor or (owner and owner.teamColor) or Color3.new(1, 1, 1)
	local speed = attacker.projSpeed or 90
	local range = attacker.range or 40
	local r = attacker.projRadius or 1.6
	-- LOGIC (server): chỉ số, không tạo Part -> không có gì replicate mỗi frame.
	projectiles[#projectiles + 1] = {
		pos = origin, dir = dir, speed = speed, range = range, traveled = 0,
		dmg = attacker.dmg, aoe = attacker.aoe or 0, ownerId = attacker.ownerId, radius = r, color = color,
		buildingOnly = attacker.targeting == "BUILDING_ONLY", -- Siege: đạn chỉ va chạm công trình
	}
	-- VFX (client): bay ĐÚNG tới mục tiêu rồi dừng (không xuyên qua) — gửi khoảng cách tới mục tiêu.
	local visDist = math.min(range, (target.part.Position - origin).Magnitude)
	Remotes.ProjectileVFX:FireAllClients(origin, dir, speed, visDist, r, color)
end

local function updateProjectiles(dt)
	for i = #projectiles, 1, -1 do
		local pr = projectiles[i]
		local step = pr.speed * dt
		pr.pos = pr.pos + pr.dir * step
		pr.traveled += step
		local hit = firstEnemyHit(pr, pr.pos)
		if hit then
			local hitPos = hit.part.Position -- chốt trước khi damage (có thể huỷ part)
			if pr.aoe > 0 then
				applyAoe(hitPos, pr.aoe, pr.ownerId, pr.dmg, hit) -- nổ lan (trừ primary)
				Remotes.Explosion:FireAllClients(hitPos, pr.aoe, pr.color) -- VFX nổ AoE (màu theo đạn)
			end
			damageEntity(hit, pr.dmg, pr.ownerId) -- primary
			table.remove(projectiles, i)
		elseif pr.traveled >= pr.range then
			-- Hết tầm: đạn có AoE (vd blast Battleship) vẫn NỔ tại điểm cuối.
			if pr.aoe > 0 then
				applyAoe(pr.pos, pr.aoe, pr.ownerId, pr.dmg, nil)
				Remotes.Explosion:FireAllClients(pr.pos, pr.aoe, pr.color)
			end
			table.remove(projectiles, i)
		end
	end
end

function CombatSystem.clearProjectiles()
	table.clear(projectiles)
end

-- Một "attacker" (unit HOẶC mothership) bắn 1 nhịp nếu sẵn sàng.
local function fireEntity(attacker, dt)
	local part = attacker.part
	if not part or not part.Parent then return end
	if attacker.remnant then return end -- tàn quân trung lập: không bắn
	if attacker.dummy then return end   -- bù nhìn test: chỉ chịu đòn, KHÔNG gây damage
	if attacker.melee then return end   -- cận chiến: lao & đánh áp sát ở updateMelee riêng

	-- Bước 3b: Kamikaze không bắn (chỉ lao va chạm) -> CombatSystem lo riêng.
	if attacker.attack == "COLLISION" then return end

	-- Bước 3a: đang bị STUN -> không bắn (mọi kiểu: hitscan/multi/charge).
	if attacker.stunnedUntil and os.clock() < attacker.stunnedUntil then return end

	attacker.cooldown = math.max(0, (attacker.cooldown or 0) - dt)

	-- Đang NẠP ĐẠN (telegraph): đếm lùi rồi mới bắn phát chốt.
	if attacker.charging then
		attacker.chargeLeft -= dt
		if attacker.chargeLeft > 0 then return end
		attacker.charging = false
		local t = attacker.chargeTarget
		attacker.chargeTarget = nil
		-- Re-validate: mục tiêu còn tồn tại + trong tầm (có thể bị phá/đi xa giữa chừng).
		if t and t.part and t.part.Parent
			and (t.part.Position - part.Position).Magnitude <= attacker.range then
			local owner = GameState.motherships[attacker.ownerId]
			local color = (owner and owner.teamColor) or Color3.new(1, 1, 1)
			spawnProjectile(attacker, t) -- (Lordz) nạp xong -> bắn ĐẠN shell bay (không laser)
		end
		attacker.cooldown = 1 / attacker.fireRate
		return
	end

	if attacker.cooldown > 0 then return end

	-- (Lordz) VOLLEY: Battleship bắn 1 CỤM laser vào tối đa volleyCount địch gần nhất,
	-- rồi nghỉ lâu (fireRate thấp) -> "1 lượt bắn giãn ra".
	if attacker.targeting == "VOLLEY" then
		local targets = nearestEnemyUnits(attacker, attacker.volleyCount or 6)
		if #targets == 0 then return end
		local owner = GameState.motherships[attacker.ownerId]
		local color = (owner and owner.teamColor) or Color3.new(1, 1, 1)
		local origin = part.Position
		for _, t in ipairs(targets) do
			damageEntity(t, attacker.dmg, attacker.ownerId)
			Remotes.FireLaser:FireAllClients(origin, t.part.Position, color)
		end
		attacker.cooldown = 1 / attacker.fireRate
		return
	end

	-- (Lordz) DRAGON CONE: phun NÓN AoE — sát thương MỌI địch trong tầm + trong góc
	-- coneAngle quanh hướng tới địch gần nhất (quét nhiều mục tiêu cùng 1 nhịp).
	if attacker.targeting == "CONE" then
		local aim = findTarget(attacker)
		if not aim then return end
		local origin = part.Position
		local dir = flatUnitDir(origin, aim.part.Position)
		if not dir then return end
		local rng = attacker.range
		local halfCos = math.cos((attacker.coneAngle or 1.05) / 2)
		local function inCone(tp)
			if (tp - origin).Magnitude > rng then return false end
			local to = flatUnitDir(origin, tp)
			return to ~= nil and to:Dot(dir) >= halfCos
		end
		for _, o in ipairs(GameState.units) do
			if o.ownerId ~= attacker.ownerId and not o.remnant and o.part and o.part.Parent and inCone(o.part.Position) then
				damageEntity(o, attacker.dmg, attacker.ownerId)
			end
		end
		for _, e in pairs(GameState.motherships) do
			if e.ownerId ~= attacker.ownerId and e.alive and e.part and inCone(e.part.Position)
				and not shotBlockedByFleet(origin, e) then
				damageEntity(e, attacker.dmg, attacker.ownerId)
			end
		end
		-- VFX: sóng BLAST vòng cung (tím) do client vẽ.
		Remotes.ConeBlast:FireAllClients(origin, dir, rng, attacker.coneAngle or 1.2, Color3.fromRGB(225, 70, 240))
		attacker.cooldown = 1 / attacker.fireRate
		return
	end

	local target = findTarget(attacker)
	if not target then return end

	-- (Lordz) ĐẠN BAY: xạ thủ bắn projectile bay thẳng (trúng địch đầu tiên) thay hitscan.
	if attacker.projectile then
		spawnProjectile(attacker, target)
		attacker.cooldown = 1 / attacker.fireRate
		return
	end

	-- Telegraph: unit có chargeTime (Siege) -> bắt đầu NẠP ĐẠN thay vì bắn ngay.
	if (attacker.chargeTime or 0) > 0 then
		attacker.charging = true
		attacker.chargeLeft = attacker.chargeTime
		attacker.chargeTarget = target
		local o = GameState.motherships[attacker.ownerId]
		local col = (o and o.teamColor) or Color3.new(1, 1, 1)
		Remotes.SiegeCharge:FireAllClients(part.Position, target.part.Position, col, attacker.chargeTime)
		return
	end

	local owner = GameState.motherships[attacker.ownerId]
	local color = (owner and owner.teamColor) or Color3.new(1, 1, 1)
	local origin = part.Position
	local tpos = target.part.Position -- chốt vị trí trước khi target có thể bị huỷ

	damageEntity(target, attacker.dmg, attacker.ownerId)
	if (attacker.aoe or 0) > 0 then
		applyAoe(tpos, attacker.aoe, attacker.ownerId, attacker.dmg, target)
	end

	Remotes.FireLaser:FireAllClients(origin, tpos, color)
	attacker.cooldown = 1 / attacker.fireRate
end

-- Bước 3a — GRAVITY_STUN: mỗi 1/fireRate giây, Titan phát sóng xung quanh nó:
-- STUN (refresh, không cộng dồn) + đẩy lệch slot mọi enemy UNIT trong bán kính.
-- Chỉ ảnh hưởng enemy Unit (không Building/Mothership); không friendly fire.
local function updateShockwaves(dt)
	for _, u in ipairs(GameState.units) do
		if u.special == "GRAVITY_STUN" and u.part and u.part.Parent then
			u.shockCd = (u.shockCd or 0) - dt
			if u.shockCd <= 0 then
				u.shockCd = 1 / u.fireRate
				local center = u.part.Position
				local radius = u.stunRadius or 18
				for _, other in ipairs(GameState.units) do
					if other.ownerId ~= u.ownerId and other.part and other.part.Parent then
						if (other.part.Position - center).Magnitude <= radius then
							other.stunnedUntil = os.clock() + (u.stunDuration or 1.5) -- refresh
							local dir = Util.flatDir(center, other.part.Position)
							if dir ~= Vector3.zero then
								other.pushOffset = dir * (u.pushStrength or 10)
							end
						end
					end
				end
				local owner = GameState.motherships[u.ownerId]
				local color = (owner and owner.teamColor) or Color3.new(1, 1, 1)
				Remotes.Shockwave:FireAllClients(center, radius, color)
			end
		end
	end
end

-- Bước 3b — KAMIKAZE: ngoại lệ formation duy nhất. Bình thường bay SCREEN; khi có
-- Mothership/fleet địch vào arm range -> rời quỹ đạo lao thẳng (ưu tiên Mothership),
-- chạm ~KAMI_COLLIDE thì nổ AoE trúng mọi Mothership/fleet địch quanh đó rồi tự huỷ.
-- KHÔNG đụng Building; không friendly fire. hp thấp nên bị bắn rơi trước khi chạm.
local KAMI_COLLIDE = 3

local function nearestEnemyMothershipInRange(u, rng)
	local pos = u.part.Position
	local best, bd
	for _, e in pairs(GameState.motherships) do
		if e.ownerId ~= u.ownerId and e.alive and e.part then
			local d = (e.part.Position - pos).Magnitude
			if d <= rng and (not bd or d < bd) then best, bd = e, d end
		end
	end
	return best
end

local function nearestEnemyUnitInRange(u, rng)
	local pos = u.part.Position
	local best, bd
	for _, o in ipairs(GameState.units) do
		if o ~= u and o.ownerId ~= u.ownerId and o.part and o.part.Parent then
			local d = (o.part.Position - pos).Magnitude
			if d <= rng and (not bd or d < bd) then best, bd = o, d end
		end
	end
	return best
end

local function explodeKamikaze(u)
	local center = u.part.Position
	local ownerId = u.ownerId
	local r = u.aoe or 6
	-- Gom enemy UNIT + MOTHERSHIP trong bán kính nổ (KHÔNG building, không phe mình).
	local hits = {}
	for _, o in ipairs(GameState.units) do
		if o ~= u and o.ownerId ~= ownerId and o.part and o.part.Parent
			and (o.part.Position - center).Magnitude <= r then
			hits[#hits + 1] = o
		end
	end
	for _, e in pairs(GameState.motherships) do
		if e.ownerId ~= ownerId and e.alive and e.part
			and (e.part.Position - center).Magnitude <= r then
			hits[#hits + 1] = e
		end
	end
	for _, ent in ipairs(hits) do
		damageEntity(ent, u.dmg, ownerId)
	end
	Remotes.Explosion:FireAllClients(center, r) -- VFX nổ lửa AoE khi Kamikaze lao vào nổ
	if u.part then u.part:Destroy() end
end

local function updateKamikazes(dt)
	for _, u in ipairs(GameState.units) do
		if u.special == "KAMIKAZE" and u.part and u.part.Parent then
			local rng = u.armRange or 45
			if not u.armed then
				local tgt = nearestEnemyMothershipInRange(u, rng) or nearestEnemyUnitInRange(u, rng)
				if tgt then u.armed = true; u.kamiTarget = tgt end
			else
				-- Mục tiêu chết/mất giữa đường -> re-acquire; không có thì về formation.
				local t = u.kamiTarget
				if not (t and t.part and t.part.Parent) then
					t = nearestEnemyMothershipInRange(u, rng) or nearestEnemyUnitInRange(u, rng)
					u.kamiTarget = t
					if not t then u.armed = false end
				end
				if u.armed and u.kamiTarget then
					local pos = u.part.Position
					local tp = u.kamiTarget.part.Position
					local dir = Util.flatDir(pos, tp)
					local dist = Util.flatDist(pos, tp)
					if dist <= KAMI_COLLIDE then
						explodeKamikaze(u)
					elseif dir ~= Vector3.zero then
						local np = pos + dir * math.min(u.speed * dt, dist)
						np = Vector3.new(np.X, pos.Y, np.Z)
						u.part.CFrame = CFrame.lookAt(np, np + dir)
					end
				end
			end
		end
	end
end

-- Địch GẦN NHẤT (unit/mothership/building) trong bán kính rng — cho cận chiến bắt mục tiêu.
local function nearestEnemyFrom(pos, ownerId, rng)
	local best = gridNearestEnemyUnit(pos, ownerId, rng) -- units qua lưới không gian (nhẹ)
	local bd = best and (best.part.Position - pos).Magnitude or nil
	for _, e in pairs(GameState.motherships) do
		if e.ownerId ~= ownerId and e.alive and e.part then
			local d = (e.part.Position - pos).Magnitude
			if d <= rng and (not bd or d < bd) then best, bd = e, d end
		end
	end
	for _, b in ipairs(GameState.buildings) do
		if b.ownerId ~= ownerId and b.part and b.part.Parent then
			local d = (b.part.Position - pos).Magnitude
			if d <= rng and (not bd or d < bd) then best, bd = b, d end
		end
	end
	return best
end

local function meleeTargetValid(t, myOwner)
	if not (t and t.part and t.part.Parent) then return false end
	if t.ownerId == myOwner then return false end
	if t.kind == "Mothership" and not t.alive then return false end
	return true
end

-- Tầm "chỉ huy" (đo từ TÀU MẸ tới mục tiêu click): trong tầm này thì MỌI cận chiến
-- lao vào ĐÚNG mục tiêu người chơi chọn (đổi target theo click, bất kể lính đang ở đâu);
-- lái Tàu Mẹ ra xa quá -> bỏ mục tiêu, quay về đội hình.
local MELEE_FOCUS_LEASH = 220

-- CẬN CHIẾN (Lordz Swarm AI): unit melee bẻ đội hình LAO THẲNG vào mục tiêu (ưu tiên
-- cái người chơi CLICK; không có thì địch gần nhất trong aggro). Tới tầm -> đánh áp sát;
-- mục tiêu ra khỏi tầm -> nhả & quay về đội hình.
local function updateMelee(dt)
	for _, u in ipairs(GameState.units) do
		if u.melee and u.part and u.part.Parent and not u.remnant then
			local aggro = (Config.UNITS[u.unitType] and Config.UNITS[u.unitType].aggro) or u.aggro or 100
			local owner = GameState.motherships[u.ownerId]
			-- PLAYER: aggro đo từ Tàu Mẹ (lái xa -> lính nhả về). BOT/guard: đo từ CHÍNH con lính
			-- -> tự đánh mọi kẻ tới gần (bot hung hãn như trước, không cần lái sát).
			local oPos = (owner and owner.part and not owner.isBot) and owner.part.Position or u.part.Position
			-- NHẮM tính theo vị trí TÀU MẸ (chỉ huy): ưu tiên mục tiêu CLICK (focus), không thì
			-- địch gần nhất trong aggro TÍNH TỪ TÀU MẸ. Lái Tàu Mẹ RA XA bãi địch -> mọi melee
			-- mất mục tiêu -> NHẢ & quay về đội hình (gọi về được, không lock chết).
			local t = nil
			if oPos then
				local focus = owner and owner.attackTarget -- owner có thể nil (guard Warden) -> tránh crash
				if focus and meleeTargetValid(focus, u.ownerId)
					and (focus.part.Position - oPos).Magnitude <= MELEE_FOCUS_LEASH then
					t = focus
				else
					t = nearestEnemyFrom(oPos, u.ownerId, aggro)
				end
			end
			u.meleeTarget = t
			u.engaged = (t ~= nil)
			if t then
				local pos = u.part.Position
				local tp = t.part.Position
				local dist = Util.flatDist(pos, tp)
				-- Tầm với = range + bán kính THỰC của mục tiêu -> đứng NGOÀI nhà/địch mà đánh (giữ khoảng cách).
				local reach = (u.range or 8) + (t.radius or (t.part and math.max(t.part.Size.X, t.part.Size.Z) / 2) or 4)
				u.cooldown = math.max(0, (u.cooldown or 0) - dt)
				if dist > reach then
					local dir = Util.flatDir(pos, tp)
					if dir ~= Vector3.zero then
						local step = math.min((u.speed or 40) * dt, dist - reach) -- dừng ĐÚNG khoảng hover
						local np = pos + dir * step
						np = Vector3.new(np.X, pos.Y, np.Z)
						u.part.CFrame = CFrame.lookAt(np, np + dir)
					end
				elseif u.cooldown <= 0 then
					damageEntity(t, u.dmg, u.ownerId)
					local color = (owner and owner.teamColor) or Color3.new(1, 1, 1)
					Remotes.FireLaser:FireAllClients(pos, tp, color) -- loé chém áp sát
					u.cooldown = 1 / (u.fireRate or 1)
				end
			end
		end
	end
end

-- Chống CHỒNG khi tấn công: đẩy tách unit cận chiến đang lao/đánh (engaged) khỏi nhau
-- + khỏi mục tiêu to -> lính VÂY quanh mục tiêu thay vì đè lên nhau. Chạy SAU updateMelee
-- (cùng Heartbeat) nên không bị ghi đè. Dùng lưới đã dựng đầu frame.
local MELEE_SEP_MAX = 4
local function separateMelee()
	for _, u in ipairs(GameState.units) do
		if u.melee and u.engaged and u.part and u.part.Parent then
			local pos = u.part.Position
			local cx = math.floor(pos.X / GRID_CELL)
			local cz = math.floor(pos.Z / GRID_CELL)
			local sx, sz = 0, 0
			for gx = cx - 1, cx + 1 do
				local col = unitGrid[gx]
				if col then
					for gz = cz - 1, cz + 1 do
						local cell = col[gz]
						if cell then
							for _, o in ipairs(cell) do
								if o ~= u and o.part and o.part.Parent then
									local op = o.part.Position
									local dx, dz = pos.X - op.X, pos.Z - op.Z
									local d = math.sqrt(dx * dx + dz * dz)
									local minD = (u.radius or 2) + (o.radius or 2)
									if d > 0.001 and d < minD then
										local push = (minD - d) * 0.5
										sx += dx / d * push
										sz += dz / d * push
									end
								end
							end
						end
					end
				end
			end
			local m = math.sqrt(sx * sx + sz * sz)
			if m > MELEE_SEP_MAX then sx, sz = sx / m * MELEE_SEP_MAX, sz / m * MELEE_SEP_MAX end
			if m > 0.001 then
				u.part.Position = Vector3.new(pos.X + sx, pos.Y, pos.Z + sz)
			end
		end
	end
end

local function updateCombat(dt)
	rebuildUnitGrid() -- dựng lưới 1 lần/frame để findTarget quét ô lân cận (không O(n²))
	updateProjectiles(dt) -- đạn bay di chuyển + va chạm (dùng lưới vừa dựng)
	updateShockwaves(dt)
	updateKamikazes(dt)
	updateMelee(dt) -- cận chiến lao vào + đánh áp sát
	separateMelee() -- đẩy tách lính đang đánh -> không chồng lên nhau

	-- Units bắn
	for _, u in ipairs(GameState.units) do
		fireEntity(u, dt)
	end

	-- Tháp phòng thủ (building có .dmg) cũng bắn quân địch.
	for _, b in ipairs(GameState.buildings) do
		if b.dmg then fireEntity(b, dt) end
	end

	-- Motherships cũng bắn (snapshot trước vì fireEntity có thể xoá mothership chết)
	local msList = {}
	for _, e in pairs(GameState.motherships) do
		msList[#msList + 1] = e
	end
	for _, e in ipairs(msList) do
		if e.alive then
			fireEntity(e, dt)
		end
	end
end

-- (Địch dummy debug đã được thay bằng bot thật ở BotSystem — M5.)

-- Tìm entity (Mothership/Unit/Building) có part == `part` để chuyển click -> mục tiêu.
local function resolveEntity(part)
	for _, e in pairs(GameState.motherships) do
		if e.part == part then return e end
	end
	for _, u in ipairs(GameState.units) do
		if u.part == part and not u.remnant then return u end
	end
	for _, b in ipairs(GameState.buildings) do
		if b.part == part then return b end
	end
	return nil
end

-- Client click 1 đối tượng -> đặt focus-fire cho CẢ fleet của người đó (nil = bỏ).
local function onSetAttackTarget(player, part)
	local owner = GameState.motherships[player.UserId]
	if not owner then return end
	if part == nil then owner.attackTarget = nil; return end
	if typeof(part) ~= "Instance" then return end
	local ent = resolveEntity(part)
	-- Chỉ nhận mục tiêu ĐỊCH còn sống (không tự bắn mình / tàn quân).
	if ent and ent.ownerId ~= player.UserId then
		owner.attackTarget = ent
	else
		owner.attackTarget = nil
	end
end

function CombatSystem.init()
	Remotes.SetAttackTarget.OnServerEvent:Connect(onSetAttackTarget)

	RunService.Heartbeat:Connect(function(dt)
		updateCombat(dt)
	end)

	print("[CombatSystem] ready")
end

return CombatSystem
