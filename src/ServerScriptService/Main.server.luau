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

safeInit("MapSystem", MapSystem)
safeInit("MothershipSystem", MothershipSystem)
safeInit("FleetSystem", FleetSystem)
safeInit("EconomySystem", EconomySystem)
safeInit("BuildingSystem", BuildingSystem)
safeInit("PickupSystem", PickupSystem)
safeInit("CombatSystem", CombatSystem)
safeInit("BotSystem", BotSystem)

-------------------------------------------------------------------------------
-- VÒNG ĐỜI TRẬN (Lobby <-> Playing)
-------------------------------------------------------------------------------
local function broadcastState()
	Remotes.MatchState:FireAllClients(MatchState.isPlaying() and "playing" or "lobby")
end

-- Dọn sạch mọi entity trận (dùng khi về lobby hoặc trước khi dựng trận mới).
local function clearMatch()
	FleetSystem.clearAll()
	BuildingSystem.clearAll()   -- dọn building trước để giải phóng node mỏ
	MothershipSystem.clearAll()
	BotSystem.clearAll()
	PickupSystem.clearAll()
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
	broadcastState()
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
	print("[Main] Vào lobby.")
end

Remotes.StartMatch.OnServerEvent:Connect(startMatch) -- bấm cổng "Vào trận" ở sảnh
Remotes.Restart.OnServerEvent:Connect(startMatch)    -- "Chơi lại" ở bảng kết thúc
Remotes.ToLobby.OnServerEvent:Connect(enterLobby)    -- "Lobby" ở bảng kết thúc

-- Người vào server: khởi tạo sở hữu Tàu Mẹ (mở sẵn con mặc định) + gửi trạng thái.
Players.PlayerAdded:Connect(function(player)
	local uid = player.UserId
	GameState.ownedHeroes[uid] = GameState.ownedHeroes[uid] or { [Config.DEFAULT_HERO] = true }
	GameState.activeHero[uid] = GameState.activeHero[uid] or Config.DEFAULT_HERO
	Remotes.MatchState:FireClient(player, MatchState.isPlaying() and "playing" or "lobby")
	Remotes.HeroState:FireClient(player, GameState.activeHero[uid], GameState.ownedHeroes[uid])
	local pos = MatchState.isPlaying() and MothershipSystem.playerSpawnPos() or lobbyShipPos()
	MothershipSystem.spawn(uid, false, pos, Config.TEAM.PLAYER)
end)

-- Chọn Tàu Mẹ để lái (chỉ con ĐÃ sở hữu). Đổi cả buff (quân spawn mới) lẫn tạo hình.
Remotes.SelectHero.OnServerEvent:Connect(function(player, heroId)
	local uid = player.UserId
	if typeof(heroId) ~= "string" or not Config.HERO_BY_ID[heroId] then return end
	local owned = GameState.ownedHeroes[uid] or {}
	if not owned[heroId] then return end -- chưa sở hữu -> bỏ qua
	GameState.activeHero[uid] = heroId
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
Remotes.OpenChest.OnServerEvent:Connect(function(player)
	local uid = player.UserId
	if MatchState.isPlaying() then
		Remotes.OpenChest:FireClient(player, false, nil, 0)
		return
	end
	local now = tick()
	local last = chestLastOpen[uid]
	local cd = Config.CHEST.COOLDOWN
	if last and (now - last) < cd then
		Remotes.OpenChest:FireClient(player, false, nil, math.ceil(cd - (now - last)))
		return
	end
	chestLastOpen[uid] = now

	local h = rollHero()
	local owned = GameState.ownedHeroes[uid] or {}
	GameState.ownedHeroes[uid] = owned
	local isNew = not owned[h.id]
	owned[h.id] = true

	Remotes.OpenChest:FireClient(player, true, {
		isNew = isNew, id = h.id, name = h.name, rarity = h.rarity, color = h.color,
	}, cd)
	-- Cập nhật panel chọn Tàu Mẹ (owned mới) — giữ nguyên con đang lái.
	Remotes.HeroState:FireClient(player, GameState.activeHero[uid], owned)
end)

-- Boot: vào thẳng lobby (dọn arena mà MapSystem.init vừa dựng, thay bằng sảnh).
enterLobby()

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
