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
local MapSystem = require(script.Parent.MapSystem)

local MothershipSystem = {}

local folder -- Folder chứa mọi mothership part trong workspace

-- Vị trí spawn của player: góc dưới-trái, cách tâm SPAWN_FRAC * nửa-map.
-- Tính LIVE (mỗi lần spawn) từ Config.MAP -> đổi MAP.SIZE rồi Chơi lại là tự dãn.
-- Có Tàu Mẹ nào đang trong bán kính minD quanh pos không?
local function tooCloseToShip(pos, minD)
	for _, e in pairs(GameState.motherships) do
		if e.part and (e.part.Position - pos).Magnitude < minD then
			return true
		end
	end
	return false
end

-- Vị trí spawn NGẪU NHIÊN trên map khi vào trận: né mỏ + không quá gần Tàu Mẹ khác.
-- Thử tối đa 25 lần rồi fallback về 1 điểm ngẫu nhiên bất kỳ.
function MothershipSystem.playerSpawnPos()
	local half = Config.MAP.SIZE / 2
	local margin = 60
	local r = Config.MOTHERSHIP.RADIUS
	for _ = 1, 25 do
		local x = math.random(-half + margin, half - margin)
		local z = math.random(-half + margin, half - margin)
		local pos = MapSystem.resolveDeposits(Vector3.new(x, r, z), r * 2) -- đẩy ra khỏi mỏ
		if not tooCloseToShip(pos, 90) then
			return pos
		end
	end
	return Vector3.new(math.random(-half + margin, half - margin), r, math.random(-half + margin, half - margin))
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

-- Tạo hình của Tàu Mẹ đang lái (theo activeHero). Không có -> con mặc định.
function MothershipSystem.getHeroSkin(ownerId)
	local id = GameState.activeHero[ownerId] or Config.DEFAULT_HERO
	return Config.HERO_BY_ID[id] or Config.HERO_BY_ID[Config.DEFAULT_HERO]
end

-- Áp màu/vật liệu skin lên part. Ở TRẬN giữ màu phe (bạn/địch không lẫn), chỉ
-- đổi vật liệu; ở SẢNH hiện full màu skin để khoe.
local function applyHeroSkin(part, skin, inLobby, teamColor)
	part.Material = (skin and skin.material) or Enum.Material.Neon
	part.Reflectance = (skin and skin.reflectance) or 0
	part.Color = (inLobby and skin and skin.color) or teamColor
end

local function lighten(c, a)
	return c:Lerp(Color3.new(1, 1, 1), a)
end

-- Dựng TRANG TRÍ 3D theo class/rarity, hàn (weld) vào thân để di chuyển cùng.
-- Silhouette khác nhau -> nhìn phát biết class (kể cả trong trận khi màu = phe):
--   Vanguard: gai/dart tỏa ra (bầy hung hãn) · Guard: vành giáp dày + khối giáp
--   (tank) · Artillery: tháp pháo giữa + nòng tỏa ra. Rarity: số đèn viền + vương miện.
local function buildHeroDeco(part, skin, inLobby, teamColor)
	local old = part:FindFirstChild("Deco")
	if old then old:Destroy() end
	if not skin then return end

	local deco = Instance.new("Folder")
	deco.Name = "Deco"
	deco.Parent = part

	local rXZ = part.Size.X / 2
	local topY = part.Size.Y / 2
	local baseColor = (inLobby and skin.color) or teamColor
	local accent = lighten(baseColor, 0.45)
	local lightColor = lighten(baseColor, 0.55)
	local mat = skin.material or Enum.Material.Neon

	local list = {} -- { {part, offset(CFrame cục bộ)} } để cập nhật bám tàu mỗi frame
	local function add(size, offset, yaw, color, material, class, shape)
		local d = Instance.new(class or "Part")
		d.Size = size
		d.Color = color
		d.Material = material or Enum.Material.SmoothPlastic
		-- Anchored: KHÔNG dùng weld (weld không bám khi thân anchored dời bằng .Position).
		-- Vị trí sẽ được stepMothership set lại theo thân mỗi frame.
		d.Anchored = true
		d.CanCollide = false; d.CanQuery = false; d.CastShadow = false
		if shape and d:IsA("Part") then d.Shape = shape end
		local cf = part.CFrame * CFrame.new(offset) * (yaw or CFrame.new())
		d.CFrame = cf
		d.Parent = deco
		table.insert(list, { part = d, offset = part.CFrame:ToObjectSpace(cf) })
	end

	-- Vòm buồng lái (mọi con)
	add(Vector3.new(rXZ * 0.95, topY * 1.7, rXZ * 0.95), Vector3.new(0, topY * 0.2, 0), nil,
		accent, Enum.Material.SmoothPlastic, "Part", Enum.PartType.Ball)

	-- Đèn viền quanh rìa (UFO) — số lượng theo rarity
	local lights = (skin.rarity == "Epic" and 12) or (skin.rarity == "Rare" and 9) or 6
	for i = 1, lights do
		local a = (i / lights) * math.pi * 2
		add(Vector3.new(rXZ * 0.16, rXZ * 0.16, rXZ * 0.16),
			Vector3.new(math.cos(a) * rXZ * 0.82, topY * 0.15, math.sin(a) * rXZ * 0.82),
			nil, lightColor, Enum.Material.Neon, "Part", Enum.PartType.Ball)
	end

	if skin.cat == "Vanguard" then
		for i = 1, 6 do
			local a = (i / 6) * math.pi * 2
			add(Vector3.new(rXZ * 0.32, topY * 0.5, rXZ * 1.05),
				Vector3.new(math.cos(a) * rXZ * 1.0, topY * 0.05, math.sin(a) * rXZ * 1.0),
				CFrame.Angles(0, -a, 0), accent, mat, "WedgePart")
		end
	elseif skin.cat == "Guard" then
		-- vành giáp dày (ellipsoid dẹt rộng) + 4 khối giáp
		add(Vector3.new(rXZ * 2.45, topY * 0.55, rXZ * 2.45), Vector3.new(0, 0, 0), nil,
			baseColor, Enum.Material.Metal, "Part", Enum.PartType.Ball)
		for i = 1, 4 do
			local a = (i / 4) * math.pi * 2
			add(Vector3.new(rXZ * 0.5, topY * 1.0, rXZ * 0.85),
				Vector3.new(math.cos(a) * rXZ * 1.0, topY * 0.25, math.sin(a) * rXZ * 1.0),
				CFrame.Angles(0, -a, 0), accent, Enum.Material.Metal)
		end
	else -- Artillery
		add(Vector3.new(rXZ * 0.65, topY * 1.5, rXZ * 0.65), Vector3.new(0, topY * 0.6, 0), nil,
			accent, Enum.Material.Metal)
		for i = 1, 4 do
			local a = (i / 4) * math.pi * 2
			add(Vector3.new(topY * 0.38, topY * 0.38, rXZ * 1.5),
				Vector3.new(math.cos(a) * rXZ * 0.65, topY * 0.4, math.sin(a) * rXZ * 0.65),
				CFrame.Angles(0, -a, 0), baseColor, Enum.Material.Metal)
		end
	end

	-- Vương miện Epic: chóp neon trên đỉnh
	if skin.rarity == "Epic" then
		add(Vector3.new(rXZ * 0.34, topY * 1.7, rXZ * 0.34), Vector3.new(0, topY * 1.5, 0), nil,
			lightColor, Enum.Material.Neon, "Part", Enum.PartType.Ball)
	end

	return list
end

-- Áp lại skin cho Tàu Mẹ đang tồn tại (khi đổi con ở sảnh — không cần respawn).
function MothershipSystem.reskin(ownerId)
	local entry = GameState.motherships[ownerId]
	if not entry or not entry.part then return end
	local inLobby = not MatchState.isPlaying()
	local skin = MothershipSystem.getHeroSkin(ownerId)
	applyHeroSkin(entry.part, skin, inLobby, entry.teamColor)
	entry.deco = buildHeroDeco(entry.part, skin, inLobby, entry.teamColor)
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
	-- Tạo hình theo Tàu Mẹ đang lái (màu/vật liệu). Trận: giữ màu phe.
	local skin = MothershipSystem.getHeroSkin(ownerId)
	applyHeroSkin(part, skin, inLobby, teamColor)
	part.CastShadow = not inLobby -- lobby: tắt bóng đổ
	part:SetAttribute("OwnerUserId", ownerId)
	part.Parent = folder
	local decoList = buildHeroDeco(part, skin, inLobby, teamColor) -- trang trí 3D theo class/rarity

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
		deco = decoList,             -- part trang trí 3D (bám thân mỗi frame)
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
		-- Split (Lordz): splitLevel 0..SPLIT_MAX_LEVEL (số cụm = 2^level). rejoinAt = mốc
		-- bắt đầu tự gộp; rejoining/rejoinNext = máy trạng thái gộp dần. aimPoint = con trỏ
		-- thô (vệ tinh chase); satState = trạng thái anchor động của các cụm vệ tinh.
		splitLevel = 0,
		rejoinAt = 0,
		rejoining = false,
		rejoinNext = 0,
		aimPoint = nil,
		splitAimPoint = nil, -- (mobile) tap điểm trống khi split -> lái đội split tới đó
		satState = nil,
		attackTarget = nil, -- focus-fire: entity người chơi click để cả fleet nhắm (nil = auto)
		-- Combat: mothership cũng tự bắn (dùng chung fire logic với unit ở CombatSystem)
		dmg = Config.MOTHERSHIP.DMG,
		range = Config.MOTHERSHIP.RANGE,
		fireRate = Config.MOTHERSHIP.FIRE_RATE,
		aoe = Config.MOTHERSHIP.AOE,
		projectile = true, -- (Lordz) bắn ĐẠN BAY thay vì laser
		projSpeed = Config.MOTHERSHIP.PROJ_SPEED,
		projRadius = Config.MOTHERSHIP.PROJ_RADIUS,
		cooldown = 0,
		-- Economy (M4)
		scrap = Config.ECONOMY.START_SCRAP,
		gems = 0, -- thưởng khi hạ Tàu Mẹ địch
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
	for _, player in ipairs(Players:GetPlayers()) do
		-- Mỗi người 1 vị trí ngẫu nhiên riêng (gọi trong vòng lặp -> khác nhau).
		MothershipSystem.spawn(player.UserId, false, MothershipSystem.playerSpawnPos(), Config.TEAM.PLAYER)
	end
end

-- Xử lý input di chuyển từ client: chỉ nhận điểm hợp lệ, kẹp trong map.
-- Ranh giới di chuyển theo chế độ: sandbox test dùng vùng nhỏ (TEST_SIZE) -> KHÔNG cho
-- bay ra khỏi nền test; trận dùng MAP.SIZE; sảnh dùng LOBBY.SIZE.
local function moveBound()
	if MatchState.isTest() then return Config.MAP.TEST_SIZE or 500 end
	-- Trận: cho bay RA NGOÀI ranh 1 khoảng OOB_MARGIN (tới tường cứng) rồi bị đếm giờ.
	if MatchState.isPlaying() then return Config.MAP.SIZE + 2 * (Config.MAP.OOB_MARGIN or 240) end
	return Config.LOBBY.SIZE
end

-- killFn: Main gán = CombatSystem.killMothership (tránh vòng require). Dùng khi OOB chết.
MothershipSystem.killFn = nil

-- OUT-OF-BOUNDS (chỉ trận thật): ra khỏi ranh map (MAP.SIZE/2) -> đếm ngược OOB_TIME giây;
-- không quay về -> Tàu Mẹ CHẾT. Gửi OOBWarn cho người chơi để hiện overlay đếm giờ.
local function updateOOB(entry)
	local half = Config.MAP.SIZE / 2
	local p = entry.part.Position
	local oob = (math.abs(p.X) > half) or (math.abs(p.Z) > half)
	local player = (not entry.isBot) and Players:GetPlayerByUserId(entry.ownerId) or nil
	if oob then
		entry.oobStart = entry.oobStart or os.clock()
		local remaining = (Config.MAP.OOB_TIME or 6) - (os.clock() - entry.oobStart)
		if remaining <= 0 then
			entry.oobStart = nil
			if player then Remotes.OOBWarn:FireClient(player, 0) end
			local fn = MothershipSystem.killFn
			if fn then task.defer(function() if entry.alive then fn(entry) end end) end -- hoãn: tránh sửa list giữa vòng
		elseif player then
			Remotes.OOBWarn:FireClient(player, remaining)
		end
	elseif entry.oobStart then
		entry.oobStart = nil
		if player then Remotes.OOBWarn:FireClient(player, 0) end -- đã về -> ẩn overlay
	end
end

local function onMoveInput(player, point)
	local entry = GameState.motherships[player.UserId]
	if not entry or not entry.alive then return end
	if typeof(point) ~= "Vector3" then return end -- không tin client mù quáng

	-- Giữ cao độ của mothership, chỉ dùng X,Z từ con trỏ
	local target = Vector3.new(point.X, entry.part.Position.Y, point.Z)
	-- Ở lobby kẹp trong sảnh (nhỏ hơn), trong trận kẹp trong map.
	local bound = moveBound()
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

-- Di chuyển 1 mothership 1 bước theo dt. Trả về true NẾU CÓ dời vị trí (để loop chỉ
-- cập nhật deco khi tàu thực sự di chuyển -> đỡ ngập replicate khi đứng yên).
local function stepMothership(entry, dt)
	if not entry.alive then return false end
	if MatchState.isMatch() then updateOOB(entry) end -- đếm giờ OOB (chạy cả khi đứng yên)
	-- Đang channel build -> khoá di chuyển (tạo "khoảnh khắc sơ hở")
	if entry.channel then return false end
	local pos = entry.part.Position
	local target = entry.targetPoint

	local dir = Util.flatDir(pos, target)
	local dist = Util.flatDist(pos, target)

	if dist <= Config.MOTHERSHIP.STOP_DIST or dir == Vector3.zero then
		return false -- đã tới nơi -> đứng yên, giữ nguyên facing cũ
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
	local bound = moveBound()
	local newPos = pos + dir * step
	newPos = Util.clampToMap(newPos, bound)
	-- Không xuyên mỏ / công trình / Tàu Mẹ khác (bỏ qua chính mình; KHÔNG bị unit ghì).
	newPos = MapSystem.resolveSolids(newPos, Config.MOTHERSHIP.RADIUS * 1.4, entry.part)

	entry.part.Position = newPos
	entry.facing = dir -- cập nhật hướng đang đi (dùng cho Split sau này)
	return true
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
			local moved = stepMothership(entry, dt)

			-- Tự hồi máu khi RA KHỎI giao tranh (không trúng đòn trong REGEN_DELAY giây).
			if entry.alive and Config.MOTHERSHIP.REGEN_RATE > 0 and entry.hp < entry.maxHp then
				if (os.clock() - (entry.lastDamageTime or 0)) >= Config.MOTHERSHIP.REGEN_DELAY then
					entry.hp = math.min(entry.maxHp, entry.hp + Config.MOTHERSHIP.REGEN_RATE * dt)
					MothershipSystem.updateHealthBar(entry)
				end
			end

			-- Deco 3D bám theo thân — CHỈ cập nhật khi tàu DI CHUYỂN (đứng yên thì giữ
			-- nguyên -> giảm mạnh replicate CFrame trên mobile).
			if moved and entry.deco and entry.part then
				local bcf = entry.part.CFrame
				for _, d in ipairs(entry.deco) do
					if d.part and d.part.Parent then
						d.part.CFrame = bcf * d.offset
					end
				end
			end
		end
	end)

	print("[MothershipSystem] ready")
end

return MothershipSystem
