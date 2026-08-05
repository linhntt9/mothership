--[[
	MothershipSystem.luau
	---------------------
	Spawn và di chuyển các Tàu Mẹ (player + bot ở milestone sau).
	Server-authoritative: client chỉ gửi world-point con trỏ qua MoveInput,
	server mới thực sự dịch chuyển khối part.

	M0: chỉ có mothership của người chơi + lái theo chuột.
	  - Mỗi Heartbeat: steer part về targetPoint với SPEED, kẹp trong biên map.
	  - `facing` = hướng di chuyển hiện tại; giữ lại giá trị cũ khi đứng yên
	    (sẽ cần cho Split ở M3).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Util = require(ReplicatedStorage.Util)
local Remotes = require(ReplicatedStorage.Remotes)
local GameState = require(script.Parent.GameState)

local MothershipSystem = {}

local folder -- Folder chứa mọi mothership part trong workspace

-- Gắn thanh máu (BillboardGui) lên 1 part. Server tạo -> replicate xuống client.
local function attachHealthBar(part)
	local bb = Instance.new("BillboardGui")
	bb.Name = "HealthBar"
	bb.Size = UDim2.new(0, 90, 0, 10)
	bb.StudsOffsetWorldSpace = Vector3.new(0, Config.MOTHERSHIP.RADIUS + 4, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = part

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bg.BorderSizePixel = 0
	bg.Parent = bb

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	bb.Parent = part
	return fill
end

-- Cập nhật thanh máu theo hp/maxHp của entry.
function MothershipSystem.updateHealthBar(entry)
	if not entry.healthFill then return end
	local ratio = math.clamp(entry.hp / entry.maxHp, 0, 1)
	entry.healthFill.Size = UDim2.fromScale(ratio, 1)
	-- xanh -> vàng -> đỏ theo lượng máu
	entry.healthFill.BackgroundColor3 = Color3.fromRGB(
		math.floor(255 * (1 - ratio) + 90 * ratio),
		math.floor(80 * (1 - ratio) + 220 * ratio),
		90
	)
end

-- Tạo 1 mothership (player hoặc bot). PUBLIC để CombatSystem/BotSystem dùng chung.
function MothershipSystem.spawn(ownerId, isBot, spawnPos, teamColor)
	teamColor = teamColor or Config.TEAM.PLAYER

	local part = Instance.new("Part")
	part.Name = "Mothership_" .. tostring(ownerId)
	part.Anchored = true
	part.CanCollide = false
	part.Shape = Enum.PartType.Ball
	local r = Config.MOTHERSHIP.RADIUS
	-- Đĩa bay dẹt (ellipsoid): rộng & mỏng thay vì quả cầu
	part.Size = Vector3.new(r * 2.8, r * 1.2, r * 2.8)
	part.Position = spawnPos
	part.Color = teamColor
	part.Material = Enum.Material.Neon
	part:SetAttribute("OwnerUserId", ownerId)
	part.Parent = folder

	local fill = attachHealthBar(part)

	local entry = {
		kind = "Mothership",         -- dùng cho CombatSystem phân loại target
		ownerId = ownerId,
		isBot = isBot,
		teamColor = teamColor,       -- unit sẽ lấy màu này để phân biệt phe
		part = part,
		healthFill = fill,
		targetPoint = spawnPos,      -- ban đầu đứng yên tại chỗ spawn
		facing = Vector3.new(1, 0, 0),
		hp = Config.MOTHERSHIP.HP,
		maxHp = Config.MOTHERSHIP.HP,
		alive = true,
		-- Split (M3): split=true khi đang giữ Space; splitDist ramp mượt 0<->SPLIT_DIST
		split = false,
		splitDist = 0,
		-- Combat: mothership cũng tự bắn (dùng chung fire logic với unit ở CombatSystem)
		dmg = Config.MOTHERSHIP.DMG,
		range = Config.MOTHERSHIP.RANGE,
		fireRate = Config.MOTHERSHIP.FIRE_RATE,
		aoe = Config.MOTHERSHIP.AOE,
		cooldown = 0,
		-- Economy (M4)
		scrap = Config.ECONOMY.START_SCRAP,
		channel = nil, -- {buildingType, tier, point, node, timeLeft, total} khi đang xây
	}
	GameState.motherships[ownerId] = entry
	MothershipSystem.updateHealthBar(entry)
	return entry
end

-- Xoá sạch mọi mothership (dùng khi Restart).
function MothershipSystem.clearAll()
	for id, entry in pairs(GameState.motherships) do
		if entry.part then entry.part:Destroy() end
		GameState.motherships[id] = nil
	end
end

-- Spawn lại mothership cho tất cả người chơi đang online (dùng khi Restart).
function MothershipSystem.respawnPlayers()
	local spawnPos = Vector3.new(
		Config.PLAYER_SPAWN.X,
		Config.MOTHERSHIP.RADIUS,
		Config.PLAYER_SPAWN.Z
	)
	for _, player in ipairs(Players:GetPlayers()) do
		MothershipSystem.spawn(player.UserId, false, spawnPos, Config.TEAM.PLAYER)
	end
end

-- Xử lý input di chuyển từ client: chỉ nhận điểm hợp lệ, kẹp trong map.
local function onMoveInput(player, point)
	local entry = GameState.motherships[player.UserId]
	if not entry or not entry.alive then return end
	if typeof(point) ~= "Vector3" then return end -- không tin client mù quáng

	-- Giữ cao độ của mothership, chỉ dùng X,Z từ con trỏ
	local target = Vector3.new(point.X, entry.part.Position.Y, point.Z)
	entry.targetPoint = Util.clampToMap(target, Config.MAP.SIZE)
end

-- Tổng weight hạm đội của owner (để tính tốc độ theo tải).
local function usedWeight(ownerId)
	local w = 0
	for _, u in ipairs(GameState.units) do
		if u.ownerId == ownerId then
			w += (u.weight or 1)
		end
	end
	return w
end

-- Di chuyển 1 mothership 1 bước theo dt.
local function stepMothership(entry, dt)
	if not entry.alive then return end
	-- Đang channel build -> khoá di chuyển (tạo "khoảnh khắc sơ hở")
	if entry.channel then return end
	local pos = entry.part.Position
	local target = entry.targetPoint

	local dir = Util.flatDir(pos, target)
	local dist = Util.flatDist(pos, target)

	if dist <= Config.MOTHERSHIP.STOP_DIST or dir == Vector3.zero then
		return -- đã tới nơi -> đứng yên, giữ nguyên facing cũ
	end

	-- Tốc độ giảm theo tải hạm đội: nhiều quân -> nặng -> chậm
	local mult = math.clamp(
		1 - usedWeight(entry.ownerId) * Config.MOTHERSHIP.SPEED_WEIGHT_PENALTY,
		Config.MOTHERSHIP.SPEED_MIN_MULT,
		1
	)
	local speed = Config.MOTHERSHIP.SPEED * mult

	-- Không vượt quá đích trong 1 frame
	local step = math.min(speed * dt, dist)
	local newPos = pos + dir * step
	newPos = Util.clampToMap(newPos, Config.MAP.SIZE)

	entry.part.Position = newPos
	entry.facing = dir -- cập nhật hướng đang đi (dùng cho Split sau này)
end

function MothershipSystem.init()
	folder = Instance.new("Folder")
	folder.Name = "Motherships"
	folder.Parent = Workspace

	local spawnPos = Vector3.new(
		Config.PLAYER_SPAWN.X,
		Config.MOTHERSHIP.RADIUS,
		Config.PLAYER_SPAWN.Z
	)

	local function handlePlayer(player)
		MothershipSystem.spawn(player.UserId, false, spawnPos, Config.TEAM.PLAYER)
	end

	-- Người chơi đã vào từ trước (Play Solo) + người vào sau
	for _, player in ipairs(Players:GetPlayers()) do
		handlePlayer(player)
	end
	Players.PlayerAdded:Connect(handlePlayer)

	Players.PlayerRemoving:Connect(function(player)
		local entry = GameState.motherships[player.UserId]
		if entry then
			if entry.part then entry.part:Destroy() end
			GameState.motherships[player.UserId] = nil
		end
	end)

	Remotes.MoveInput.OnServerEvent:Connect(onMoveInput)

	RunService.Heartbeat:Connect(function(dt)
		for _, entry in pairs(GameState.motherships) do
			stepMothership(entry, dt)
		end
	end)

	print("[MothershipSystem] ready")
end

return MothershipSystem
