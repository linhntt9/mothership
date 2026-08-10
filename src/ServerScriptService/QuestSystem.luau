--[[
	QuestSystem.luau
	----------------
	3 loại nhiệm vụ (Config.QUESTS):
	  • Daily  (reset 24h): playSecs (active) + dKills + coplay (bạn bè).
	  • Weekly (reset 7 ngày): wKills.
	  • Unique (không reset): 1 quest / mỗi Tàu Mẹ — "Hạ N Tàu Mẹ khi lái con đó".

	"kills" = SỐ TÀU MẸ địch/bot hạ được (CombatSystem gọi onMothershipKill).
	Daily/Weekly mở khoá theo chuỗi (quest sau khoá tới khi NHẬN xong quest trước).
	Tiến độ + đã-nhận + mốc reset LƯU qua DataStore (Main serialize/load vào bản ghi
	người chơi). Reward: scrap/gem cộng qua EconomySystem (bền theo owner).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local GameState = require(script.Parent.GameState)
local EconomySystem = require(script.Parent.EconomySystem)

local QuestSystem = {}

-- Main gán hàm này để đánh dấu cần lưu (persist) khi quest đổi.
QuestSystem.onDirty = function(_uid) end

local data = {} -- [uid] = bảng tiến độ (xem newData)

-- Danh sách Unique quest dựng 1 lần từ Config.HEROES (mỗi con 1 quest).
local uniqueQuests = {}
for _, h in ipairs(Config.HEROES) do
	local n = Config.QUESTS.UNIQUE_KILL_TARGET
	table.insert(uniqueQuests, {
		id = "u_" .. h.id,
		name = h.name,
		shipId = h.id,
		objectives = {
			{ type = "killAs", shipId = h.id, target = n,
			  label = ("Hạ %d Tàu Mẹ khi lái %s"):format(n, h.name) },
		},
		reward = { kind = "both", gem = Config.QUESTS.UNIQUE_REWARD.gem, scrap = Config.QUESTS.UNIQUE_REWARD.scrap },
	})
end

local function newData()
	local now = os.time()
	return {
		db = math.floor(now / Config.QUESTS.DAILY_RESET),   -- bucket daily hiện tại
		wb = math.floor(now / Config.QUESTS.WEEKLY_RESET),  -- bucket weekly
		dKills = 0, playSecs = 0, coplay = false,
		wKills = 0,
		uKills = {},   -- [heroId] = số Tàu Mẹ hạ khi lái con đó
		dClaimed = {}, wClaimed = {}, uClaimed = {},
	}
end

-- Reset khi sang chu kỳ mới (xoá tiến độ + đã-nhận của daily/weekly; unique giữ).
local function resetIfNeeded(uid)
	local d = data[uid]; if not d then return end
	local now = os.time()
	local db = math.floor(now / Config.QUESTS.DAILY_RESET)
	local wb = math.floor(now / Config.QUESTS.WEEKLY_RESET)
	if d.db ~= db then
		d.db = db; d.dKills = 0; d.playSecs = 0; d.coplay = false; d.dClaimed = {}
	end
	if d.wb ~= wb then
		d.wb = wb; d.wKills = 0; d.wClaimed = {}
	end
end

-- Nạp từ bản ghi đã lưu (hoặc tạo mới) rồi reset nếu qua chu kỳ.
function QuestSystem.load(uid, saved)
	local d = newData()
	if type(saved) == "table" then
		d.db = tonumber(saved.db) or d.db
		d.wb = tonumber(saved.wb) or d.wb
		d.dKills = tonumber(saved.dKills) or 0
		d.playSecs = tonumber(saved.playSecs) or 0
		d.coplay = saved.coplay == true
		d.wKills = tonumber(saved.wKills) or 0
		if type(saved.uKills) == "table" then
			for k, v in pairs(saved.uKills) do
				if Config.HERO_BY_ID[k] and type(v) == "number" then d.uKills[k] = v end
			end
		end
		for _, key in ipairs({ "dClaimed", "wClaimed", "uClaimed" }) do
			if type(saved[key]) == "table" then
				for k, v in pairs(saved[key]) do if v == true then d[key][k] = true end end
			end
		end
	end
	data[uid] = d
	resetIfNeeded(uid)
end

-- Trả bảng để LƯU (plain table).
function QuestSystem.serialize(uid)
	local d = data[uid]
	if not d then return nil end
	return {
		db = d.db, wb = d.wb,
		dKills = d.dKills, playSecs = math.floor(d.playSecs), coplay = d.coplay,
		wKills = d.wKills,
		uKills = d.uKills,
		dClaimed = d.dClaimed, wClaimed = d.wClaimed, uClaimed = d.uClaimed,
	}
end

function QuestSystem.unload(uid) data[uid] = nil end

-- Giá trị hiện tại của 1 objective.
local function objCur(d, obj)
	local t = obj.type
	if t == "playSecs" then return math.floor(d.playSecs)
	elseif t == "dKills" then return d.dKills
	elseif t == "wKills" then return d.wKills
	elseif t == "coplay" then return d.coplay and 1 or 0
	elseif t == "killAs" then return d.uKills[obj.shipId] or 0 end
	return 0
end

local function questComplete(d, quest)
	for _, o in ipairs(quest.objectives) do
		if objCur(d, o) < o.target then return false end
	end
	return true
end

-- Dựng payload cho client.
local function buildState(uid)
	resetIfNeeded(uid)
	local d = data[uid]; if not d then return nil end
	local now = os.time()

	local function section(list, claimedTbl, isUnique)
		local out = {}
		for i, q in ipairs(list) do
			local objs = {}
			for _, o in ipairs(q.objectives) do
				local cur = objCur(d, o)
				table.insert(objs, { label = o.label, cur = math.min(cur, o.target), target = o.target })
			end
			local locked = false
			if not isUnique and i > 1 then
				locked = not claimedTbl[list[i - 1].id] -- chuỗi: khoá tới khi nhận quest trước
			end
			local owned = true
			if isUnique then
				local o = GameState.ownedHeroes[uid]
				owned = (o and o[q.shipId]) == true
			end
			table.insert(out, {
				id = q.id, name = q.name, objectives = objs, reward = q.reward,
				complete = questComplete(d, q), claimed = claimedTbl[q.id] == true,
				locked = locked, owned = owned,
			})
		end
		return out
	end

	return {
		dailyResetIn = (d.db + 1) * Config.QUESTS.DAILY_RESET - now,
		weeklyResetIn = (d.wb + 1) * Config.QUESTS.WEEKLY_RESET - now,
		daily = section(Config.QUESTS.daily, d.dClaimed, false),
		weekly = section(Config.QUESTS.weekly, d.wClaimed, false),
		unique = section(uniqueQuests, d.uClaimed, true),
	}
end

function QuestSystem.sendState(uid)
	local player = Players:GetPlayerByUserId(uid)
	if not player then return end
	local st = buildState(uid)
	if st then Remotes.QuestState:FireClient(player, st) end
end

-- Hạ 1 Tàu Mẹ địch: killerId là người chơi -> cộng kills daily/weekly + unique(con đang lái).
function QuestSystem.onMothershipKill(killerId)
	if not killerId or killerId <= 0 then return end
	local d = data[killerId]; if not d then return end
	resetIfNeeded(killerId)
	d.dKills += 1
	d.wKills += 1
	local ship = GameState.activeHero[killerId]
	if ship then d.uKills[ship] = (d.uKills[ship] or 0) + 1 end
	QuestSystem.onDirty(killerId)
	QuestSystem.sendState(killerId)
end

-- Vào trận: đánh dấu coplay cho những người có BẠN BÈ Roblox cùng server.
function QuestSystem.onMatchStart()
	local humans = {}
	for _, p in ipairs(Players:GetPlayers()) do table.insert(humans, p) end
	if #humans < 2 then return end
	for _, p in ipairs(humans) do
		local d = data[p.UserId]
		if d and not d.coplay then
			task.spawn(function()
				for _, other in ipairs(humans) do
					if other ~= p then
						local ok, isFriend = pcall(function() return p:IsFriendsWith(other.UserId) end)
						if ok and isFriend then
							d.coplay = true
							QuestSystem.onDirty(p.UserId)
							QuestSystem.sendState(p.UserId)
							break
						end
					end
				end
			end)
		end
	end
end

-- Tìm quest theo id (trả về quest def + bảng claimed + có phải unique).
local function findQuest(questId)
	for _, q in ipairs(Config.QUESTS.daily) do if q.id == questId then return q, "d" end end
	for _, q in ipairs(Config.QUESTS.weekly) do if q.id == questId then return q, "w" end end
	for _, q in ipairs(uniqueQuests) do if q.id == questId then return q, "u" end end
	return nil
end

-- Nhận thưởng 1 quest (client bấm NHẬN). Xác thực đủ điều kiện + chưa nhận + không khoá.
function QuestSystem.claim(player, questId)
	local uid = player.UserId
	local d = data[uid]; if not d then return end
	resetIfNeeded(uid)
	local quest, cat = findQuest(questId)
	if not quest then return end

	local claimedTbl = (cat == "d" and d.dClaimed) or (cat == "w" and d.wClaimed) or d.uClaimed
	if claimedTbl[questId] then return end            -- đã nhận
	if not questComplete(d, quest) then return end    -- chưa đủ

	-- Khoá chuỗi (daily/weekly): phải nhận xong quest trước.
	if cat ~= "u" then
		local list = (cat == "d") and Config.QUESTS.daily or Config.QUESTS.weekly
		for i, q in ipairs(list) do
			if q.id == questId then
				if i > 1 and not claimedTbl[list[i - 1].id] then return end
				break
			end
		end
	end

	claimedTbl[questId] = true
	local r = quest.reward
	if r.kind == "gem" then
		EconomySystem.addGem(uid, r.amount)
	elseif r.kind == "scrap" then
		EconomySystem.add(uid, r.amount)
	elseif r.kind == "both" then
		if r.gem then EconomySystem.addGem(uid, r.gem) end
		if r.scrap then EconomySystem.add(uid, r.scrap) end
	end
	QuestSystem.onDirty(uid)
	QuestSystem.sendState(uid)
end

function QuestSystem.init()
	Remotes.ClaimQuest.OnServerEvent:Connect(function(player, questId)
		if typeof(questId) == "string" then QuestSystem.claim(player, questId) end
	end)

	-- Cộng playtime (active) mỗi giây + đẩy state định kỳ cho client mở panel.
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(1)
			tick += 1
			for _, p in ipairs(Players:GetPlayers()) do
				local d = data[p.UserId]
				if d then
					resetIfNeeded(p.UserId)
					d.playSecs += 1
				end
			end
			if tick % 5 == 0 then -- 5s/lần: đồng bộ tiến độ (playtime/đếm ngược)
				for _, p in ipairs(Players:GetPlayers()) do
					QuestSystem.sendState(p.UserId)
				end
			end
		end
	end)

	print("[QuestSystem] ready")
end

return QuestSystem
