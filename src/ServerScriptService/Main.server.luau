--[[
	Main.server.luau
	----------------
	Bootstrap server. Khởi tạo các system theo đúng thứ tự phụ thuộc.

	Lưu ý: require Remotes SỚM để các RemoteEvent tồn tại trước khi client
	WaitForChild chúng.

	M0: Map + Mothership. Các system Fleet/Combat/Economy/Building/Bot sẽ được
	nối thêm vào đây ở các milestone sau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Config)
local Workspace = game:GetService("Workspace")

-- Map nhỏ (500 studs) & không có nhân vật để "neo" vùng stream. Tắt StreamingEnabled
-- để MỌI part (đặc biệt là Tàu Mẹ ở góc map) luôn replicate xuống client.
-- Nếu bật, client chỉ nhận part gần camera -> Tàu Mẹ ở xa không hiện -> màn đen.
pcall(function()
	Workspace.StreamingEnabled = false
end)

-- Game này KHÔNG dùng nhân vật (avatar). Tắt auto-spawn để tránh:
--   1) camera mặc định bám avatar tranh chấp với camera Scriptable -> chớp nháy
--   2) một khối vật lý avatar thừa rơi trên map
Players.CharacterAutoLoads = false

-- Tạo remotes trước tiên
local Remotes = require(ReplicatedStorage.Remotes)

local MatchState = require(ServerScriptService.MatchState)
local LobbySystem = require(ServerScriptService.LobbySystem)
local MapSystem = require(ServerScriptService.MapSystem)
local MothershipSystem = require(ServerScriptService.MothershipSystem)
local FleetSystem = require(ServerScriptService.FleetSystem)
local EconomySystem = require(ServerScriptService.EconomySystem)
local BuildingSystem = require(ServerScriptService.BuildingSystem)
local PickupSystem = require(ServerScriptService.PickupSystem)
local CombatSystem = require(ServerScriptService.CombatSystem)
local BotSystem = require(ServerScriptService.BotSystem)
local GameState = require(ServerScriptService.GameState)
local QuestSystem = require(ServerScriptService.QuestSystem)

-- Bọc trong pcall để 1 system lỗi không kéo sập cả game (coding standard mục 6)
local function safeInit(name, system)
	local ok, err = pcall(function()
		system.init()
	end)
	if not ok then
		warn(("[Main] %s.init() lỗi: %s"):format(name, tostring(err)))
	end
end

-- === CONFIG PERSISTENCE (DataStore) ===
-- Lưu các chỉ số chỉnh trong bảng ⚙ và NẠP LẠI cho lần Play sau.
-- (Trong Studio cần bật: Game Settings -> Security -> "Enable Studio Access to
--  API Services". Nếu tắt thì game vẫn chạy, chỉ không lưu được.)
local DataStoreService = game:GetService("DataStoreService")
local CONFIG_STORE, CONFIG_KEY = "MothershipConfig_v1", "overrides"
local overrides = {}        -- [path] = value đã set
local overridesDirty = false
local store
pcall(function() store = DataStoreService:GetDataStore(CONFIG_STORE) end)

-- Áp 1 override số lên Config (chỉ ghi đè field ĐANG LÀ SỐ — an toàn).
local function setConfigPath(path, value)
	local parts = string.split(path, ".")
	local t = Config
	for i = 1, #parts - 1 do
		local key = tonumber(parts[i]) or parts[i]
		t = t[key]
		if type(t) ~= "table" then return false end
	end
	local lastKey = tonumber(parts[#parts]) or parts[#parts]
	if type(t[lastKey]) ~= "number" then return false end
	t[lastKey] = value
	return true
end

-- Nạp override đã lưu & áp NGAY (trước khi system init/spawn đọc số).
if store then
	local ok, saved = pcall(function() return store:GetAsync(CONFIG_KEY) end)
	if ok and type(saved) == "table" then
		local applied = 0
		for path, value in pairs(saved) do
			if type(path) == "string" and type(value) == "number" and setConfigPath(path, value) then
				overrides[path] = value
				applied += 1
			end
		end
		if applied > 0 then
			print(("[Config] Nạp %d chỉ số đã lưu từ lần trước."):format(applied))
		end
	elseif not ok then
		warn("[Config] Không đọc được DataStore (bật 'Studio Access to API Services'?): " .. tostring(saved))
	end
else
	warn("[Config] DataStore không khả dụng — config sẽ KHÔNG được lưu.")
end

-- === PLAYER PERSISTENCE (DataStore) ===
-- Lưu các Tàu Mẹ (class) người chơi ĐÃ ROLL ĐƯỢC + con đang lái, nạp lại lần sau.
-- Cùng điều kiện với config: khi test trong Studio phải bật
-- Game Settings -> Security -> "Enable Studio Access to API Services".
local PLAYER_STORE = "MothershipPlayer_v1"
local playerStore
pcall(function() playerStore = DataStoreService:GetDataStore(PLAYER_STORE) end)
local playerDirty = {}     -- [uid] = true khi có thay đổi cần lưu (debounce)
local playerLastDaily = {} -- [uid] = os.time() lần nhận quà đăng nhập gần nhất
local giftJoin = {}        -- [uid] = os.clock() lúc vào (mốc tính active-time cho Gifts)
local giftClaimed = {}     -- [uid] = { [index]=true } quà đã nhận trong phiên
local initialized = {}     -- [uid] = true khi đã khởi tạo (chống chạy trùng PlayerAdded/boot)

local function playerKey(uid) return "u_" .. tostring(uid) end

-- Nạp dữ liệu 1 người chơi vào GameState (LUÔN đảm bảo sở hữu con mặc định),
-- nạp Gem đã tích, và phát quà ĐĂNG NHẬP HẰNG NGÀY nếu đủ hạn.
local function loadPlayer(uid)
	local owned, equipped, gems, lastDaily, questSaved
	if playerStore then
		local ok, data = pcall(function() return playerStore:GetAsync(playerKey(uid)) end)
		if ok and type(data) == "table" then
			if type(data.owned) == "table" then
				owned = {}
				for id in pairs(data.owned) do
					if Config.HERO_BY_ID[id] then owned[id] = true end -- bỏ id rác/đã xoá
				end
			end
			if type(data.equipped) == "string" and Config.HERO_BY_ID[data.equipped] then
				equipped = data.equipped
			end
			if type(data.gems) == "number" then gems = data.gems end
			if type(data.lastDaily) == "number" then lastDaily = data.lastDaily end
			if type(data.quests) == "table" then questSaved = data.quests end
		elseif not ok then
			warn(("[Player] Đọc DataStore lỗi (uid %s): %s"):format(tostring(uid), tostring(data)))
		end
	end
	QuestSystem.load(uid, questSaved) -- nạp tiến độ quest (hoặc tạo mới)
	-- Tàu sở hữu + con đang lái
	owned = owned or {}
	owned[Config.DEFAULT_HERO] = true                          -- luôn có Swarm Lord
	if not equipped or not owned[equipped] then equipped = Config.DEFAULT_HERO end
	GameState.ownedHeroes[uid] = owned
	GameState.activeHero[uid] = equipped

	-- Gem: người mới có sẵn START; xét quà đăng nhập hằng ngày.
	gems = gems or Config.GEMS.START
	local now = os.time()
	local dailyCd = (Config.GEMS.DAILY_HOURS or 24) * 3600
	local grantedDaily = false
	if not lastDaily or (now - lastDaily) >= dailyCd then
		gems += Config.GEMS.DAILY
		lastDaily = now
		grantedDaily = true
	end
	playerLastDaily[uid] = lastDaily
	EconomySystem.setGems(uid, gems)
	if grantedDaily then
		playerDirty[uid] = true
		local player = Players:GetPlayerByUserId(uid)
		if player then
			Remotes.Notify:FireClient(player, ("Quà đăng nhập: +%d 💎"):format(Config.GEMS.DAILY))
		end
	end
end

-- Ghi dữ liệu 1 người chơi xuống DataStore.
local function savePlayer(uid)
	if not playerStore then return end
	local owned = GameState.ownedHeroes[uid]
	if not owned then return end
	local data = {
		owned = owned,
		equipped = GameState.activeHero[uid],
		gems = EconomySystem.getGems(uid),
		lastDaily = playerLastDaily[uid],
		quests = QuestSystem.serialize(uid),
	}
	local ok, err = pcall(function() playerStore:SetAsync(playerKey(uid), data) end)
	if not ok then warn(("[Player] Lưu lỗi (uid %s): %s"):format(tostring(uid), tostring(err))) end
end

-- Lưu khi người chơi rời server (nếu có thay đổi treo).
Players.PlayerRemoving:Connect(function(player)
	local uid = player.UserId
	if playerDirty[uid] then
		playerDirty[uid] = nil
		savePlayer(uid)
	end
	giftJoin[uid] = nil
	giftClaimed[uid] = nil
	initialized[uid] = nil
	QuestSystem.unload(uid)
end)

-- Lưu định kỳ những ai vừa roll/đổi tàu (debounce, tránh spam DataStore).
if playerStore then
	task.spawn(function()
		while true do
			task.wait(6)
			for uid in pairs(playerDirty) do
				playerDirty[uid] = nil
				savePlayer(uid)
			end
		end
	end)
end

-- Server tắt: cố lưu nốt các thay đổi còn treo.
game:BindToClose(function()
	for uid in pairs(playerDirty) do
		savePlayer(uid)
	end
end)

safeInit("MapSystem", MapSystem)
safeInit("MothershipSystem", MothershipSystem)
safeInit("FleetSystem", FleetSystem)
safeInit("EconomySystem", EconomySystem)
safeInit("BuildingSystem", BuildingSystem)
safeInit("PickupSystem", PickupSystem)
safeInit("CombatSystem", CombatSystem)
safeInit("BotSystem", BotSystem)
safeInit("QuestSystem", QuestSystem)
-- Quest đổi -> đánh dấu lưu (persist chung bản ghi người chơi).
QuestSystem.onDirty = function(uid) playerDirty[uid] = true end

-------------------------------------------------------------------------------
-- VÒNG ĐỜI TRẬN (Lobby <-> Playing)
-------------------------------------------------------------------------------
local function broadcastState()
	Remotes.MatchState:FireAllClients(MatchState.isPlaying() and "playing" or "lobby")
end

local testGround -- nền phẳng của sandbox Test Combat (nơi RIÊNG, không phải arena)

-- Dọn sạch mọi entity trận (dùng khi về lobby hoặc trước khi dựng trận mới).
local function clearMatch()
	FleetSystem.clearAll()
	CombatSystem.clearProjectiles() -- dọn đạn bay còn lại
	BuildingSystem.clearAll()   -- dọn building trước để giải phóng node mỏ
	MothershipSystem.clearAll()
	BotSystem.clearAll()
	PickupSystem.clearAll()
	if testGround then testGround:Destroy(); testGround = nil end -- dọn nền sandbox
end

local function lobbyShipPos()
	return Vector3.new(Config.LOBBY.SPAWN.X, Config.MOTHERSHIP.RADIUS, Config.LOBBY.SPAWN.Z)
end

-- Spawn Tàu Mẹ "lobby" cho mọi người chơi (bay quanh sảnh, không combat).
local function spawnLobbyShips()
	for _, p in ipairs(Players:GetPlayers()) do
		MothershipSystem.spawn(p.UserId, false, lobbyShipPos(), Config.TEAM.PLAYER)
	end
end

-- Bắt đầu / chơi lại trận: dọn sảnh -> dựng map + rải scrap + spawn Tàu Mẹ + bot.
local function startMatch()
	clearMatch()                    -- dọn tàu lobby + mọi entity
	LobbySystem.clearHall()         -- gỡ sảnh 3D
	MatchState.set("PLAYING")
	MapSystem.rebuild()             -- dựng lại map theo số MAP hiện tại
	PickupSystem.reset()            -- rải scrap theo MAP.SIZE + PICKUP
	MothershipSystem.respawnPlayers()
	BotSystem.reset()               -- spawn bot
	QuestSystem.onMatchStart()      -- xét co-play bạn bè cho quest daily
	broadcastState()
	Remotes.TestState:FireAllClients(false)
	print("[Main] Vào trận.")
end

-- Về / vào lobby: dọn trận -> gỡ arena -> dựng sảnh 3D -> spawn Tàu Mẹ lobby.
local function enterLobby()
	clearMatch()
	MapSystem.clearAll()            -- gỡ arena (chỉ 1 cảnh tồn tại 1 lúc)
	LobbySystem.buildHall()         -- dựng sảnh 3D
	MatchState.set("LOBBY")
	spawnLobbyShips()
	broadcastState()
	Remotes.TestState:FireAllClients(false)
	print("[Main] Vào lobby.")
end

-- ── SANDBOX TEST COMBAT (nơi RIÊNG) ──────────────────────────────────────────
-- Nền phẳng riêng + Tàu Mẹ người chơi + CÔNG TRÌNH bù nhìn (phá được -> NỔ + respawn
-- CHỖ KHÁC) + 1 TÀU MẸ bù nhìn (tĩnh, không đánh trả). Không bot/kinh tế.
local TEST_MS_ID = -998     -- id Tàu Mẹ bù nhìn (khác -999 của công trình)
local TEST_BLD_TARGET = 12  -- số công trình bù nhìn luôn giữ trong sân
local testGen = 0           -- token tránh vòng maintain cũ chạy chồng

-- Điểm ngẫu nhiên trong vùng test (chừa lề để không sát biên).
local function testAreaPoint()
	local h = (Config.MAP.TEST_SIZE or 500) / 2 - 40
	return Vector3.new((math.random() - 0.5) * 2 * h, 0, (math.random() - 0.5) * 2 * h)
end

-- Tàu Mẹ bù nhìn: tĩnh, không AI, không bắn (cờ dummy) -> đích tập bắn cả Tàu Mẹ.
local function spawnTestMothership()
	local e = MothershipSystem.spawn(TEST_MS_ID, false, Vector3.new(0, Config.MOTHERSHIP.RADIUS, 150), Config.TEAM.ENEMY)
	if e then
		e.dummy = true
		if e.part then e.part:SetAttribute("Dummy", true) end
	end
end

-- Vòng DUY TRÌ sandbox: bù công trình bị phá (respawn CHỖ KHÁC) + hồi sinh Tàu Mẹ bù nhìn.
local function maintainTest(gen)
	task.spawn(function()
		while MatchState.isTest() and testGen == gen do
			task.wait(1.2)
			if not (MatchState.isTest() and testGen == gen) then break end
			local n = 0
			for _, b in ipairs(GameState.buildings) do
				if b.dummy then n += 1 end
			end
			for _ = 1, math.max(0, TEST_BLD_TARGET - n) do
				BuildingSystem.spawnDummy(testAreaPoint())
			end
			if not GameState.motherships[TEST_MS_ID] then
				spawnTestMothership()
			end
		end
	end)
end

local function startTest()
	clearMatch()
	LobbySystem.clearHall()
	MapSystem.clearAll()
	MatchState.set("TEST")
	testGen += 1

	testGround = Instance.new("Part")
	testGround.Name = "TestGround"
	testGround.Anchored = true
	testGround.CanCollide = false
	local gs = (Config.MAP.TEST_SIZE or 500) + 40
	testGround.Size = Vector3.new(gs, 2, gs)
	testGround.Position = Vector3.new(0, -1, 0)
	testGround.Color = Color3.fromRGB(38, 42, 52)
	testGround.Material = Enum.Material.SmoothPlastic
	testGround.Parent = workspace

	local R = Config.MOTHERSHIP.RADIUS
	for _, p in ipairs(Players:GetPlayers()) do
		MothershipSystem.spawn(p.UserId, false, Vector3.new(0, R, -120), Config.TEAM.PLAYER)
		EconomySystem.setScrap(p.UserId, 1000000)
	end
	-- Công trình bù nhìn ban đầu (grid); về sau maintainTest respawn cái bị phá.
	for i = 1, TEST_BLD_TARGET do
		local col = (i - 1) % 4
		local rowi = math.floor((i - 1) / 4)
		BuildingSystem.spawnDummy(Vector3.new((col - 1.5) * 55, 0, 20 + rowi * 55))
	end
	spawnTestMothership()
	maintainTest(testGen)

	broadcastState()
	Remotes.TestState:FireAllClients(true)
	print("[Main] Vào SANDBOX Test Combat.")
end

-- Bơm test: side "dummy" = thêm bù nhìn để bắn; còn lại = quân của người bấm (free).
local function onTestSpawn(player, side)
	if not MatchState.isTest() then return end
	local R = Config.MOTHERSHIP.RADIUS
	if side == "dummy" then
		-- Dummy MỚI xuất hiện NGAY GẦN người chơi (lưới nhỏ trước mũi Tàu Mẹ), giãn xa nhau.
		local ms = GameState.motherships[player.UserId]
		local base = (ms and ms.part) and ms.part.Position or Vector3.new(0, 0, 0)
		for i = 1, 8 do
			local col = (i - 1) % 4
			local rowi = math.floor((i - 1) / 4)
			BuildingSystem.spawnDummy(Vector3.new(base.X + (col - 1.5) * 55, 0, base.Z + 45 + rowi * 55))
		end
		return
	end
	for name in pairs(Config.UNITS) do
		for _ = 1, 3 do
			FleetSystem.spawnUnit(player.UserId, name, true) -- ignoreCap
		end
	end
end

Remotes.StartMatch.OnServerEvent:Connect(startMatch) -- bấm cổng "Vào trận" ở sảnh
Remotes.Restart.OnServerEvent:Connect(startMatch)    -- "Chơi lại" ở bảng kết thúc
Remotes.ToLobby.OnServerEvent:Connect(enterLobby)    -- "Lobby" ở bảng kết thúc
Remotes.StartTest.OnServerEvent:Connect(startTest)   -- (dev) vào sandbox Test Combat
Remotes.TestSpawn.OnServerEvent:Connect(onTestSpawn) -- (dev) bơm quân test

-- Người vào server: khởi tạo sở hữu Tàu Mẹ (mở sẵn con mặc định) + gửi trạng thái.
-- Guard `initialized`: chạy 1 lần/người (PlayerAdded + vòng quét boot có thể gọi trùng).
local function onPlayerAdded(player)
	local uid = player.UserId
	if initialized[uid] then return end
	initialized[uid] = true
	loadPlayer(uid) -- nạp Tàu Mẹ đã sở hữu + con đang lái + tiến độ quest + Gem
	giftJoin[uid] = os.clock() -- mốc tính active-time cho Gifts (reset mỗi phiên)
	giftClaimed[uid] = {}
	Remotes.MatchState:FireClient(player, MatchState.isPlaying() and "playing" or "lobby")
	Remotes.HeroState:FireClient(player, GameState.activeHero[uid], GameState.ownedHeroes[uid])
	local pos = MatchState.isPlaying() and MothershipSystem.playerSpawnPos() or lobbyShipPos()
	MothershipSystem.spawn(uid, false, pos, Config.TEAM.PLAYER)
	-- Gửi lại số Gem + trạng thái Quest sau khi client kịp kết nối handler.
	task.delay(2, function()
		if Players:GetPlayerByUserId(uid) then
			EconomySystem.sendGemUpdate(uid)
			QuestSystem.sendState(uid)
		end
	end)
end
Players.PlayerAdded:Connect(onPlayerAdded)

-- Chọn Tàu Mẹ để lái (chỉ con ĐÃ sở hữu). Đổi cả buff (quân spawn mới) lẫn tạo hình.
Remotes.SelectHero.OnServerEvent:Connect(function(player, heroId)
	local uid = player.UserId
	if typeof(heroId) ~= "string" or not Config.HERO_BY_ID[heroId] then return end
	local owned = GameState.ownedHeroes[uid] or {}
	if not owned[heroId] then return end -- chưa sở hữu -> bỏ qua
	GameState.activeHero[uid] = heroId
	playerDirty[uid] = true      -- lưu con đang lái
	MothershipSystem.reskin(uid) -- đổi tạo hình Tàu Mẹ ngay ở sảnh
	Remotes.HeroState:FireClient(player, heroId, owned)
end)

-- RƯƠNG CLASS ở sảnh: roll ra 1 Tàu Mẹ (theo weight/độ hiếm), CÓ THỂ trùng.
-- Reply: (ok, reward{isNew,id,name,rarity,color}|nil, cooldownConLai). Chỉ ở LOBBY.
local chestLastOpen = {} -- [uid] = tick() lần mở gần nhất
local function rollHero()
	local total = 0
	for _, h in ipairs(Config.HEROES) do total += (h.weight or 0) end
	local r = math.random() * total
	for _, h in ipairs(Config.HEROES) do
		r -= (h.weight or 0)
		if r <= 0 then return h end
	end
	return Config.HEROES[#Config.HEROES]
end
-- Số giây còn lại của lượt roll MIỄN PHÍ (client hiện đồng hồ đếm).
local function freeRemaining(uid)
	local last = chestLastOpen[uid]
	if not last then return 0 end
	return math.max(0, math.ceil(Config.LOBBY.CHEST.COOLDOWN - (tick() - last)))
end

-- Thực hiện 1 lượt roll: chọn tàu, ghi sở hữu, đánh dấu lưu nếu là tàu mới.
local function doRoll(uid)
	local h = rollHero()
	local owned = GameState.ownedHeroes[uid] or {}
	GameState.ownedHeroes[uid] = owned
	local isNew = not owned[h.id]
	owned[h.id] = true
	if isNew then playerDirty[uid] = true end -- có tàu mới -> lưu
	return { isNew = isNew, id = h.id, name = h.name, rarity = h.rarity, color = h.color }, owned
end

-- mode = "gem" (tốn Gem, không cooldown) | "free"/nil (miễn phí, có cooldown).
-- Reply: (ok, reward|nil, freeRemaining, reason). reason = "playing"|"cooldown"|"nogem".
Remotes.OpenChest.OnServerEvent:Connect(function(player, mode)
	local uid = player.UserId
	if MatchState.isPlaying() then
		Remotes.OpenChest:FireClient(player, false, nil, 0, "playing")
		return
	end
	if mode == "gem" then
		if not EconomySystem.trySpendGems(uid, Config.LOBBY.CHEST.GEM_COST) then
			Remotes.OpenChest:FireClient(player, false, nil, freeRemaining(uid), "nogem")
			return
		end
	else -- miễn phí: kiểm tra cooldown
		local now = tick()
		local last = chestLastOpen[uid]
		local cd = Config.LOBBY.CHEST.COOLDOWN
		if last and (now - last) < cd then
			Remotes.OpenChest:FireClient(player, false, nil, math.ceil(cd - (now - last)), "cooldown")
			return
		end
		chestLastOpen[uid] = now
	end

	local reward, owned = doRoll(uid)
	Remotes.OpenChest:FireClient(player, true, reward, freeRemaining(uid), nil)
	-- Cập nhật panel My Ship (owned mới) — giữ nguyên con đang lái.
	Remotes.HeroState:FireClient(player, GameState.activeHero[uid], owned)
end)

-- GIFTS: nhận quà mốc `index` nếu active-time đủ & chưa nhận trong phiên.
-- Reply: (index, ok, kind, amount). Scrap/Gem cộng qua EconomySystem (bền theo owner).
Remotes.ClaimGift.OnServerEvent:Connect(function(player, index)
	local uid = player.UserId
	if typeof(index) ~= "number" then return end
	local gift = Config.GIFTS[index]
	if not gift then return end
	local claimed = giftClaimed[uid]
	if not claimed then claimed = {}; giftClaimed[uid] = claimed end
	if claimed[index] then return end -- đã nhận
	local active = os.clock() - (giftJoin[uid] or os.clock())
	if active < gift.at then
		Remotes.ClaimGift:FireClient(player, index, false) -- chưa tới mốc
		return
	end
	claimed[index] = true
	if gift.kind == "gem" then
		EconomySystem.addGem(uid, gift.amount)
	else
		EconomySystem.add(uid, gift.amount) -- scrap (bền theo owner)
	end
	Remotes.ClaimGift:FireClient(player, index, true, gift.kind, gift.amount)
end)

-- Boot: vào thẳng lobby (dọn arena mà MapSystem.init vừa dựng, thay bằng sảnh).
enterLobby()

-- Chống race Play-Solo: người chơi có thể đã vào TRƯỚC khi PlayerAdded kết nối
-- (khi đó tàu sảnh do enterLobby spawn nhưng loadPlayer/quest chưa chạy). Quét lại.
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

-- DEV: sửa Config lúc chạy từ bảng config in-game + ghi nhận để LƯU.
Remotes.SetConfig.OnServerEvent:Connect(function(player, path, value)
	if typeof(path) ~= "string" or typeof(value) ~= "number" then return end
	if value ~= value or math.abs(value) == math.huge then return end -- chặn NaN/inf
	if setConfigPath(path, value) then
		overrides[path] = value
		overridesDirty = true
		print(("[Config] %s = %g (bởi %s)"):format(path, value, player.Name))
	end
end)

-- Client (bảng ⚙) xin bảng override hiện tại để hiển thị đúng số đã lưu.
Remotes.ConfigSync.OnServerEvent:Connect(function(player)
	local snapshot = {}
	for k, v in pairs(overrides) do snapshot[k] = v end
	Remotes.ConfigSync:FireClient(player, snapshot)
end)

-- Lưu override định kỳ nếu có thay đổi (debounce, tránh spam DataStore).
if store then
	task.spawn(function()
		while true do
			task.wait(4)
			if overridesDirty then
				overridesDirty = false
				local snapshot = {}
				for k, v in pairs(overrides) do snapshot[k] = v end
				local ok, err = pcall(function() store:SetAsync(CONFIG_KEY, snapshot) end)
				if not ok then
					warn("[Config] Lưu thất bại: " .. tostring(err))
				end
			end
		end
	end)
end

print("[Main] Mothership prototype — M0-M5 bootstrap xong.")
