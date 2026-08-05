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

local MapSystem = require(ServerScriptService.MapSystem)
local MothershipSystem = require(ServerScriptService.MothershipSystem)
local FleetSystem = require(ServerScriptService.FleetSystem)
local EconomySystem = require(ServerScriptService.EconomySystem)
local BuildingSystem = require(ServerScriptService.BuildingSystem)
local PickupSystem = require(ServerScriptService.PickupSystem)
local CombatSystem = require(ServerScriptService.CombatSystem)
local BotSystem = require(ServerScriptService.BotSystem)

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

-- Restart: xoá sạch unit + building + mothership + reset scrap trên map, spawn lại.
Remotes.Restart.OnServerEvent:Connect(function()
	FleetSystem.clearAll()
	BuildingSystem.clearAll()
	MothershipSystem.clearAll()
	PickupSystem.reset()
	MothershipSystem.respawnPlayers()
	BotSystem.reset()
	print("[Main] Restart ván chơi.")
end)

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
