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
local MatchState = require(script.Parent.MatchState)

local MothershipSystem = {}

local folder -- Folder chứa mọi mothership part trong workspace

-- Vị trí spawn của player: góc dưới-trái, cách tâm SPAWN_FRAC * nửa-map.
-- Tính LIVE (mỗi lần spawn) từ Config.MAP -> đổi MAP.SIZE rồi Chơi lại là tự dãn.
function MothershipSystem.playerSpawnPos()
	local s = (Config.MAP.SIZE / 2) * (Config.MAP.SPAWN_FRAC or 0.8)
	return Vector3.new(-s, Config.MOTHERSHIP.RADIUS, -s)
end

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

-- Bảng tên nổi trên đầu Tàu Mẹ (player: tên tài khoản; bot: "Bot N").
-- Viền màu theo phe để phân biệt bạn/địch.
local function attachNameplate(part, text, teamColor, yOffset)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Nameplate"
	bb.Size = UDim2.new(0, 200, 0, 26)
	bb.StudsOffsetWorldSpace = Vector3.new(0, yOffset or (Config.MOTHERSHIP.RADIUS + 9), 0)
	bb.AlwaysOnTop = true
	bb.Adornee = part
	bb.MaxDistance = 900

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.Text = text
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	local st = Instance.new("UIStroke")
	st.Thickness = 2.5
	st.Color = teamColor or Color3.fromRGB(20, 20, 20)
	st.Parent = lbl
	local cap = Instance.new("UITextSizeConstraint"); cap.MaxTextSize = 20; cap.Parent = lbl
	lbl.Parent = bb

	bb.Parent = part
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

	-- Idempotent: nếu owner đã có Tàu Mẹ (vd đổi cảnh lobby<->trận) thì dọn cái cũ.
	local existing = GameState.motherships[ownerId]
	if existing and existing.part then existing.part:Destroy() end

	local part = Instance.new("Part")
	part.Name = "Mothership_" .. tostring(ownerId)
	part.Anchored = true
	part.CanCollide = false
	part.Shape = Enum.PartType.Ball
	local r = Config.MOTHERSHIP.RADIUS
	-- Ở lobby phóng to cho dễ nhìn; trong trận giữ cỡ chuẩn.
	local inLobby = not MatchState.isPlaying()
	local scale = inLobby and (Config.LOBBY.SHIP_SCALE or 1) or 1
	-- Đĩa bay dẹt (ellipsoid): rộng & mỏng thay vì quả cầu
	part.Size = Vector3.new(r * 2.8, r * 1.2, r * 2.8) * scale
	part.Position = spawnPos
	part.Color = teamColor
	part.Material = Enum.Material.Neon
	part.CastShadow = not inLobby -- lobby: tắt bóng đổ
	part:SetAttribute("OwnerUserId", ownerId)
	part.Parent = folder

	-- Thanh máu: chỉ trong trận (lobby không cần).
	local fill = (not inLobby) and attachHealthBar(part) or nil

	-- Tên nổi trên đầu: player = tên tài khoản, bot = "Bot N".
	local nameText
	if isBot then
		nameText = "Bot " .. tostring(-ownerId)
	else
		local p = Players:GetPlayerByUserId(ownerId)
		nameText = Config.PLAYER_PREFIX .. ((p and p.DisplayName) or (p and p.Name) or "Player")
	end
	-- Đặt tên CAO HƠN cả thanh máu (RADIUS+4) lẫn thân tàu -> không bị che.
	local nameY = math.max(part.Size.Y / 2, Config.MOTHERSHIP.RADIUS + 4) + 8
	attachNameplate(part, nameText, teamColor, nameY)

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
		spawnTime = os.clock(),      -- để tính "thời gian sống" trên bảng kết thúc
		lastAttackerId = nil,        -- ai bắn phát cuối (hiện tên trên bảng chết)
		-- Thống kê trận (hiện trên bảng kết thúc)
		stats = { unitsKilled = 0, mothershipsKilled = 0, scrapSpent = 0, unitsLost = 0 },
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
	local spawnPos = MothershipSystem.playerSpawnPos()
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
	-- Ở lobby kẹp trong sảnh (nhỏ hơn), trong trận kẹp trong map.
	local bound = MatchState.isPlaying() and Config.MAP.SIZE or Config.LOBBY.SIZE
	entry.targetPoint = Util.clampToMap(target, bound)
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
	-- Ở lobby lái nhanh/trơn hơn (không tải hạm đội, di chuyển hub cho đã tay).
	if not MatchState.isPlaying() then
		speed = Config.MOTHERSHIP.SPEED * (Config.LOBBY.MOVE_MULT or 1)
	end

	-- Không vượt quá đích trong 1 frame
	local step = math.min(speed * dt, dist)
	local bound = MatchState.isPlaying() and Config.MAP.SIZE or Config.LOBBY.SIZE
	local newPos = pos + dir * step
	newPos = Util.clampToMap(newPos, bound)

	entry.part.Position = newPos
	entry.facing = dir -- cập nhật hướng đang đi (dùng cho Split sau này)
end

function MothershipSystem.init()
	folder = Instance.new("Folder")
	folder.Name = "Motherships"
	folder.Parent = Workspace

	-- KHÔNG auto-spawn ở đây nữa: người chơi chỉ có Tàu Mẹ khi VÀO TRẬN.
	-- Main.server gọi respawnPlayers() lúc bắt đầu trận, và spawn riêng cho
	-- người vào giữa trận. Ở lobby thì không có Tàu Mẹ nào trong workspace.

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
