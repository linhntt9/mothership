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
local MothershipSystem = require(script.Parent.MothershipSystem)
local FleetSystem = require(script.Parent.FleetSystem)
local EconomySystem = require(script.Parent.EconomySystem)
local BuildingSystem = require(script.Parent.BuildingSystem)

local BotSystem = {}

local botStates = {} -- [ownerId(<0)] = { home, name, timer, state }

-- Vị trí spawn bot (xa góc của người chơi ở dưới-trái) + màu riêng từng bot
local BOT_SPAWNS = {
	Vector3.new(200, Config.MOTHERSHIP.RADIUS, 200),
	Vector3.new(200, Config.MOTHERSHIP.RADIUS, -200),
	Vector3.new(-200, Config.MOTHERSHIP.RADIUS, 200),
}
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

	-- Kinh tế: luôn cố mua quân + xây hub khi cap gần đầy
	botBuy(ownerId)
	local used = FleetSystem.getUsedCap(ownerId)
	local maxc = FleetSystem.getMaxCap(ownerId)
	if used >= maxc - 1 and EconomySystem.getScrap(ownerId) >= Config.ECONOMY.DRONE_HUB[1].cost then
		BuildingSystem.botPlace(ownerId, "DroneHub", st.home + Vector3.new(18, 0, 0))
	end

	-- Chọn trạng thái
	local hpFrac = entry.hp / entry.maxHp
	local myVal = fleetValue(ownerId) + 1
	local enemy = nearestEnemyMothership(ownerId, pos)
	local enemyVal = enemy and (fleetValue(enemy.ownerId) + 1) or 0

	local state
	if hpFrac < Config.BOT.RETREAT_HP or (enemy and myVal < enemyVal * Config.BOT.RETREAT_WEAK) then
		state = "RETREAT"
	elseif ownMineCount(ownerId) < Config.BOT.TARGET_MINES and nearestEmptyDeposit(pos) then
		state = "EXPAND"
	elseif enemy and myVal >= enemyVal * Config.BOT.AGGRESS_RATIO then
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
			entry.targetPoint = dep.Position
			if Util.flatDist(pos, dep.Position) <= Config.ECONOMY.BUILD_RANGE then
				BuildingSystem.botPlace(ownerId, "ScrapMine", dep.Position)
			end
		end
	elseif state == "AGGRESS" and enemy then
		entry.targetPoint = enemy.part.Position
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
	return p and p.Name or "Player"
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
	for i = 1, Config.BOT_COUNT do
		local id = -i
		local pos = BOT_SPAWNS[i] or Vector3.new(0, Config.MOTHERSHIP.RADIUS, 0)
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

function BotSystem.reset()
	table.clear(botStates)
	spawnBots()
end

function BotSystem.init()
	spawnBots()

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
