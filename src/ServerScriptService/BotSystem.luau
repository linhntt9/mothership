--[[
	BotSystem.luau
	--------------
	2 bot AI đối thủ, dùng CHUNG hệ thống với người chơi (mothership + fleet +
	economy + building + combat). FSM đơn giản, quyết định mỗi DECISION_INTERVAL:

	  RETREAT : HP < 30% hoặc fleet yếu hơn nhiều -> lùi về "nhà".
	  EXPAND  : chưa đủ mine -> lái tới mỏ trống gần nhất -> xây mine.
	  AGGRESS : fleet value >= 1.3x địch gần nhất -> lái tới đánh.
	  ECONOMY : còn lại -> đi gom scrap rải + mua quân.

	Mỗi lần quyết định bot cũng luôn: mua thêm quân (mix) nếu đủ scrap & còn cap,
	và xây 1 Drone Hub khi cap gần đầy. Bot cũng tự nhặt scrap (magnet dùng chung).

	Cũng lo LEADERBOARD: gửi bảng điểm cho client mỗi giây.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Util = require(ReplicatedStorage.Util)
local Remotes = require(ReplicatedStorage.Remotes)
local GameState = require(script.Parent.GameState)
local MatchState = require(script.Parent.MatchState)
local MothershipSystem = require(script.Parent.MothershipSystem)
local FleetSystem = require(script.Parent.FleetSystem)
local EconomySystem = require(script.Parent.EconomySystem)
local BuildingSystem = require(script.Parent.BuildingSystem)

local BotSystem = {}

local botStates = {} -- [ownerId(<0)] = { home, name, timer, state }

-- Vị trí spawn bot (xa góc của người chơi ở dưới-trái) + màu riêng từng bot
-- Spawn bot ở 3 góc còn lại. Toạ độ tính LIVE trong spawnBots() (theo % nửa-map)
-- nên đổi MAP.SIZE rồi Chơi lại là bot tự dãn ra góc mới, không rơi ra ngoài biên.
local function botSpawns()
	local s = (Config.MAP.SIZE / 2) * (Config.MAP.SPAWN_FRAC or 0.8)
	local r = Config.MOTHERSHIP.RADIUS
	return {
		Vector3.new(s, r, s),
		Vector3.new(s, r, -s),
		Vector3.new(-s, r, s),
	}
end
local BOT_COLORS = {
	Color3.fromRGB(255, 80, 80),   -- đỏ
	Color3.fromRGB(225, 120, 255), -- tím
	Color3.fromRGB(255, 170, 60),  -- cam
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function fleetValue(ownerId)
	local v = 0
	for _, u in ipairs(GameState.units) do
		if u.ownerId == ownerId then
			local s = Config.UNITS[u.unitType]
			v += (s and s.cost) or 0
		end
	end
	return v
end

local function nearestEnemyMothership(ownerId, pos)
	local best, bd
	for _, e in pairs(GameState.motherships) do
		if e.ownerId ~= ownerId and e.alive and e.part then
			local d = (e.part.Position - pos).Magnitude
			if not bd or d < bd then best, bd = e, d end
		end
	end
	return best
end

-- Building địch gần nhất (dùng cho raider tập trung phá công trình).
local function nearestEnemyBuilding(ownerId, pos)
	local best, bd
	for _, b in ipairs(GameState.buildings) do
		if b.ownerId ~= ownerId and b.part and b.part.Parent then
			local d = (b.part.Position - pos).Magnitude
			if not bd or d < bd then best, bd = b, d end
		end
	end
	return best
end

local function nearestEmptyDeposit(pos)
	local best, bd
	for node, info in pairs(GameState.oreDeposits) do
		if node.Parent and not info.occupied then
			local d = (node.Position - pos).Magnitude
			if not bd or d < bd then best, bd = node, d end
		end
	end
	return best
end

local function ownMineCount(ownerId)
	local c = 0
	for _, b in ipairs(GameState.buildings) do
		if b.ownerId == ownerId and b.buildingType == "ScrapMine" then c += 1 end
	end
	return c
end

local function ownBuildingCount(ownerId, btype)
	local c = 0
	for _, b in ipairs(GameState.buildings) do
		if b.ownerId == ownerId and b.buildingType == btype then c += 1 end
	end
	return c
end

-- Công trình của mình vừa bị đánh (trong 3s) -> trả về để về phòng thủ.
local function threatenedBuilding(ownerId)
	local now = os.clock()
	for _, b in ipairs(GameState.buildings) do
		if b.ownerId == ownerId and b.part and b.part.Parent
			and b.lastDamageTime and (now - b.lastDamageTime) < 3 then
			return b
		end
	end
	return nil
end

local function nearestPickup(pos)
	local best, bd
	for _, p in ipairs(GameState.pickups) do
		if p.part and p.part.Parent and not p.flyingTo then
			local d = (p.part.Position - pos).Magnitude
			if not bd or d < bd then best, bd = p, d end
		end
	end
	return best
end

-- Mua 1 đợt quân (mix). Ưu tiên đa dạng, chủ yếu Drone, thỉnh thoảng nặng đô.
local function botBuy(ownerId)
	for _ = 1, Config.BOT.BUY_PER_TICK do
		if FleetSystem.getUsedCap(ownerId) >= FleetSystem.getMaxCap(ownerId) then break end
		local scrap = EconomySystem.getScrap(ownerId)
		local r = math.random()
		local pick
		if scrap >= Config.UNITS.PlasmaCruiser.cost and r < 0.08 then
			pick = "PlasmaCruiser"
		elseif scrap >= Config.UNITS.Destroyer.cost and r < 0.25 then
			pick = "Destroyer"
		elseif scrap >= Config.UNITS.Frigate.cost and r < 0.55 then
			pick = "Frigate"
		elseif scrap >= Config.UNITS.Drone.cost then
			pick = "Drone"
		else
			break
		end
		local ok = EconomySystem.tryBuy(ownerId, pick)
		if not ok and pick ~= "Drone" then
			ok = EconomySystem.tryBuy(ownerId, "Drone") -- fallback lấp cap
		end
		if not ok then break end
	end
end

-------------------------------------------------------------------------------
-- Quyết định 1 bot
-------------------------------------------------------------------------------
local function decide(ownerId)
	local entry = GameState.motherships[ownerId]
	if not entry or not entry.alive then return end
	local st = botStates[ownerId]
	local pos = entry.part.Position

	-- RAIDER: chỉ lao vào phá công trình địch (không kinh tế, không lùi, không mua thêm).
	if st.raider then
		local b = nearestEnemyBuilding(ownerId, pos)
		if b then
			entry.targetPoint = b.part.Position
		else
			local e = nearestEnemyMothership(ownerId, pos)
			entry.targetPoint = e and e.part.Position or pos
		end
		entry.split = false
		st.state = "RAID"
		return
	end

	-- Mua quân lấp cap
	botBuy(ownerId)

	-- XÂY CĂN CỨ (mỗi lần quyết định thử 1 công trình; vị trí xoay quanh nhà cho trải đều):
	--   ưu tiên Hub (nâng cap) khi cap gần đầy -> rồi Tháp thủ khi kinh tế đã vững.
	local scrap = EconomySystem.getScrap(ownerId)
	local used = FleetSystem.getUsedCap(ownerId)
	local maxc = FleetSystem.getMaxCap(ownerId)
	st.buildAngle = (st.buildAngle or 0) + 1.3
	local function nearHome(radius)
		return st.home + Vector3.new(math.cos(st.buildAngle) * radius, 0, math.sin(st.buildAngle) * radius)
	end
	if used >= maxc - 2 and ownBuildingCount(ownerId, "DroneHub") < Config.BOT.TARGET_HUBS
		and scrap >= Config.ECONOMY.DRONE_HUB[1].cost then
		BuildingSystem.botPlace(ownerId, "DroneHub", nearHome(36))
	elseif ownMineCount(ownerId) >= 2 and ownBuildingCount(ownerId, "LaserSat") < Config.BOT.TARGET_TOWERS
		and scrap >= Config.ECONOMY.LASER_SAT[1].cost + Config.BOT.SCRAP_RESERVE then
		BuildingSystem.botPlace(ownerId, "LaserSat", nearHome(46))
	end

	-- Chọn trạng thái
	local hpFrac = entry.hp / entry.maxHp
	local myVal = fleetValue(ownerId) + 1
	local enemy = nearestEnemyMothership(ownerId, pos)
	local enemyVal = enemy and (fleetValue(enemy.ownerId) + 1) or 0

	-- Ưu tiên: sống sót -> bành trướng kinh tế -> chỉ đánh khi ĐỦ LỰC & vượt trội rõ.
	-- Mặc định ECONOMY (gom scrap + xây) -> bot gây dựng trước, không lao vào đấm sớm.
	local threat = threatenedBuilding(ownerId)
	local state
	if hpFrac < Config.BOT.RETREAT_HP or (enemy and myVal < enemyVal * Config.BOT.RETREAT_WEAK) then
		state = "RETREAT"
	elseif threat then
		state = "DEFEND" -- công trình đang bị đánh -> về cứu
	elseif ownMineCount(ownerId) < Config.BOT.TARGET_MINES and nearestEmptyDeposit(pos) then
		state = "EXPAND"
	elseif enemy and myVal >= Config.BOT.MIN_ARMY_VALUE and myVal >= enemyVal * Config.BOT.AGGRESS_RATIO then
		state = "AGGRESS"
	else
		state = "ECONOMY"
	end
	st.state = state
	entry.split = false

	-- Hành động theo trạng thái (đặt targetPoint -> MothershipSystem tự lái)
	if state == "EXPAND" then
		local dep = nearestEmptyDeposit(pos)
		if dep then
			if EconomySystem.getScrap(ownerId) >= Config.ECONOMY.SCRAP_MINE[1].cost then
				-- Đủ tiền: tới mỏ và cắm mine.
				entry.targetPoint = dep.Position
				if Util.flatDist(pos, dep.Position) <= Config.ECONOMY.BUILD_RANGE then
					BuildingSystem.botPlace(ownerId, "ScrapMine", dep.Position)
				end
			else
				-- Chưa đủ tiền -> ĐI GOM SCRAP (không đứng ì) tới khi mua nổi mine.
				local orb = nearestPickup(pos)
				entry.targetPoint = orb and orb.part.Position or dep.Position
			end
		end
	elseif state == "DEFEND" and threat then
		entry.targetPoint = threat.part.Position -- về chỗ công trình bị đánh để đánh trả
	elseif state == "AGGRESS" and enemy then
		-- Đôi khi RAID công trình địch (phá kinh tế / chiếm đóng) thay vì đấm thẳng Tàu Mẹ.
		local raidB = (math.random() < Config.BOT.RAID_CHANCE) and nearestEnemyBuilding(ownerId, pos) or nil
		entry.targetPoint = raidB and raidB.part.Position or enemy.part.Position
	elseif state == "RETREAT" then
		entry.targetPoint = st.home
	else -- ECONOMY: gom scrap rải
		local orb = nearestPickup(pos)
		entry.targetPoint = orb and orb.part.Position or st.home
	end
end

-------------------------------------------------------------------------------
-- Leaderboard
-------------------------------------------------------------------------------
local function nameOf(ownerId)
	if ownerId < 0 then
		return botStates[ownerId] and botStates[ownerId].name or "Bot"
	end
	local p = Players:GetPlayerByUserId(ownerId)
	return Config.PLAYER_PREFIX .. (p and p.Name or "Player")
end

local function scoreOf(ownerId)
	local buildV = 0
	for _, b in ipairs(GameState.buildings) do
		if b.ownerId == ownerId then
			buildV += (b.buildingType == "ScrapMine") and 300 or 500
		end
	end
	return math.floor(EconomySystem.getScrap(ownerId) + fleetValue(ownerId) + buildV)
end

local function broadcastLeaderboard()
	local list = {}
	for id, e in pairs(GameState.motherships) do
		if e.alive then
			table.insert(list, { name = nameOf(id), score = scoreOf(id), id = id })
		end
	end
	table.sort(list, function(a, b) return a.score > b.score end)
	Remotes.Leaderboard:FireAllClients(list)
end

-------------------------------------------------------------------------------
-- Spawn / reset
-------------------------------------------------------------------------------
local function spawnBots()
	local spawns = botSpawns()
	for i = 1, Config.BOT_COUNT do
		local id = -i
		local pos = spawns[i] or Vector3.new(0, Config.MOTHERSHIP.RADIUS, 0)
		local color = BOT_COLORS[i] or Config.TEAM.ENEMY
		MothershipSystem.spawn(id, true, pos, color)
		botStates[id] = {
			home = pos,
			name = "Bot " .. i,
			timer = math.random() * Config.BOT.DECISION_INTERVAL, -- lệch nhịp
			state = "ECONOMY",
		}
	end
end

-- id âm chưa dùng tiếp theo (nhỏ hơn mọi id bot hiện có, kể cả bot đã chết còn
-- lưu state) -> luôn duy nhất.
local function nextBotId()
	local m = 0
	for id in pairs(botStates) do
		if id < m then m = id end
	end
	return m - 1
end

-- Sinh THÊM 1 bot khi đang chơi (nút "Tạo bot" ở bảng ⚙). Bot mới tự tham gia
-- vòng quyết định (loop đọc botStates) + leaderboard ngay.
-- nearPos (tùy chọn): spawn bot NGAY GẦN điểm này (vd cạnh Tàu Mẹ người chơi) để
-- test combat/tháp ngay; không truyền -> spawn ở góc như thường.
-- raider (tùy chọn): spawn kèm đội quân sẵn + CHỈ tập trung phá công trình địch
-- (dùng cho nút "＋ Bot gần" để test tháp/base defense).
local RAIDER_FLEET = { Drone = 6, Frigate = 3, Destroyer = 2 }

function BotSystem.addBot(nearPos, raider)
	if not MatchState.isPlaying() then return false end -- chỉ tạo bot khi đang trong trận
	local id = nextBotId()
	local n = -id                       -- 1,2,3... dùng để đặt tên & chọn màu
	local pos
	if nearPos then
		local ang = math.random() * math.pi * 2
		pos = Util.clampToMap(
			Vector3.new(nearPos.X + math.cos(ang) * 55, Config.MOTHERSHIP.RADIUS, nearPos.Z + math.sin(ang) * 55),
			Config.MAP.SIZE
		)
	else
		local spawns = botSpawns()
		local base = spawns[((n - 1) % #spawns) + 1]
		pos = Util.clampToMap(
			Vector3.new(base.X + math.random(-40, 40), Config.MOTHERSHIP.RADIUS, base.Z + math.random(-40, 40)),
			Config.MAP.SIZE
		)
	end
	local color = BOT_COLORS[n] or Color3.fromHSV(math.random(), 0.65, 1)

	MothershipSystem.spawn(id, true, pos, color)
	botStates[id] = {
		home = pos,
		name = (raider and "Raider " or "Bot ") .. n,
		timer = math.random() * Config.BOT.DECISION_INTERVAL,
		state = "ECONOMY",
		raider = raider or nil,
	}

	if raider then
		-- Đội quân sẵn, ép CHỈ đánh building (BUILDING_ONLY) để test phòng thủ.
		for utype, cnt in pairs(RAIDER_FLEET) do
			for _ = 1, cnt do FleetSystem.spawnUnit(id, utype, true) end
		end
		for _, u in ipairs(GameState.units) do
			if u.ownerId == id then u.targeting = "BUILDING_ONLY" end
		end
	end

	broadcastLeaderboard()
	print(("[BotSystem] +1 %s (id %d)"):format(raider and "raider" or "bot", id))
	return true
end

function BotSystem.reset()
	table.clear(botStates)
	spawnBots()
end

-- Chỉ dọn state bot (mothership bot đã bị MothershipSystem.clearAll huỷ) — dùng
-- khi về lobby để không còn bot "ma" trong bảng quyết định.
function BotSystem.clearAll()
	table.clear(botStates)
end

function BotSystem.init()
	-- KHÔNG spawn bot ở init: bot chỉ có khi vào trận (Main gọi BotSystem.reset).

	-- Nút "Tạo bot" ở bảng ⚙. near=true -> spawn cạnh Tàu Mẹ người bấm (test nhanh).
	Remotes.AddBot.OnServerEvent:Connect(function(player, near)
		local nearPos
		if near then
			local e = GameState.motherships[player.UserId]
			nearPos = e and e.part and e.part.Position or nil
		end
		BotSystem.addBot(nearPos, near == true) -- bot gần = raider (có sẵn quân, phá công trình)
	end)

	RunService.Heartbeat:Connect(function(dt)
		for id, st in pairs(botStates) do
			local e = GameState.motherships[id]
			if e and e.alive then
				st.timer += dt
				if st.timer >= Config.BOT.DECISION_INTERVAL then
					st.timer = 0
					decide(id)
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			broadcastLeaderboard()
		end
	end)

	print("[BotSystem] ready — " .. Config.BOT_COUNT .. " bots")
end

return BotSystem
