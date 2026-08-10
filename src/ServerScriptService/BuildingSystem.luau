--[[
	BuildingSystem.luau
	-------------------
	Xây / nâng cấp công trình (server-authoritative).

	2 loại (M4):
	  - ScrapMine : chỉ đặt TRÊN mỏ trống (1 mine/mỏ) -> +income/s.
	  - DroneHub  : đặt trên mặt đất trống -> +fleet cap.

	Quy trình đặt:
	  client gửi PlaceBuilding(type, point) -> server validate (đủ scrap? vị trí
	  hợp lệ? Tàu Mẹ trong BUILD_RANGE?) -> nếu ok: trừ scrap + bắt đầu CHANNEL
	  (Tàu Mẹ bị khoá di chuyển BUILD_CHANNEL giây) -> xong channel thì dựng.

	Upgrade: click building của mình -> trừ scrap -> lên tier + full-heal (tức thì).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Util = require(ReplicatedStorage.Util)
local Remotes = require(ReplicatedStorage.Remotes)
local GameState = require(script.Parent.GameState)
local FleetSystem = require(script.Parent.FleetSystem)
local EconomySystem = require(script.Parent.EconomySystem)

local BuildingSystem = {}

local folder            -- Folder chứa building part
local MIN_BUILD_GAP = 28 -- khoảng cách tối thiểu giữa 2 building (studs; ~ cỡ 1 nhà)

-- Bảng tier theo loại
local function tierTable(buildingType)
	if buildingType == "ScrapMine" then
		return Config.ECONOMY.SCRAP_MINE
	elseif buildingType == "DroneHub" then
		return Config.ECONOMY.DRONE_HUB
	elseif buildingType == "LaserSat" then
		return Config.ECONOMY.LASER_SAT
	elseif buildingType == "PlasmaSat" then
		return Config.ECONOMY.PLASMA_SAT
	end
	return nil
end

local function isTower(buildingType)
	return buildingType == "LaserSat" or buildingType == "PlasmaSat"
end

-- Số building loại `bt` mà owner đang sở hữu (để chặn vượt MAX).
local function countOwned(ownerId, bt)
	local n = 0
	for _, b in ipairs(GameState.buildings) do
		if b.ownerId == ownerId and b.buildingType == bt then n += 1 end
	end
	return n
end

-------------------------------------------------------------------------------
-- Hình dạng + thanh máu
-------------------------------------------------------------------------------
-- Kích cỡ NỀN ~2.5× Tàu Mẹ (footprint ~38-42 studs, bằng ô đỏ trong ảnh). Nhân
-- thêm Config.ECONOMY.BUILD_SIZE_MULT khi dựng nếu muốn to/nhỏ hơn.
local VISUAL = {
	-- Footprint ~24 (nhỏ gọn), cao 7 ≈ chiều cao Tàu Mẹ (dẹt).
	ScrapMine = { size = Vector3.new(24, 7, 24), color = Color3.fromRGB(230, 180, 60) },
	DroneHub  = { size = Vector3.new(24, 7, 24), color = Color3.fromRGB(90, 190, 230) },
	LaserSat  = { size = Vector3.new(22, 8, 22), color = Color3.fromRGB(80, 220, 120) },
	PlasmaSat = { size = Vector3.new(24, 8, 24), color = Color3.fromRGB(210, 130, 255) },
}

local function attachHealthBar(part, heightOffset)
	local bb = Instance.new("BillboardGui")
	bb.Name = "HealthBar"
	bb.Size = UDim2.new(0, 70, 0, 8)
	bb.StudsOffsetWorldSpace = Vector3.new(0, heightOffset, 0)
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

function BuildingSystem.updateHealthBar(b)
	if not b.healthFill then return end
	local ratio = math.clamp(b.hp / b.maxHp, 0, 1)
	b.healthFill.Size = UDim2.fromScale(ratio, 1)
	b.healthFill.BackgroundColor3 = Color3.fromRGB(
		math.floor(255 * (1 - ratio) + 90 * ratio),
		math.floor(80 * (1 - ratio) + 220 * ratio),
		90
	)
end

-------------------------------------------------------------------------------
-- Tìm asteroid / kiểm tra vị trí
-------------------------------------------------------------------------------
-- Trả về mỏ (ore deposit) nằm dưới `point` (theo XZ) nếu có.
local function findOreDepositAt(point)
	local radius = Config.MAP.ORE_DEPOSIT_RADIUS + 2 -- +2 cho dễ click
	for node in pairs(GameState.oreDeposits) do
		if node and node.Parent then
			if Util.flatDist(point, node.Position) <= radius then
				return node
			end
		end
	end
	return nil
end

-- Có building nào quá gần point không? (giãn theo cỡ building đã phóng to)
local function tooCloseToBuilding(point)
	local gap = MIN_BUILD_GAP * (Config.ECONOMY.BUILD_SIZE_MULT or 1)
	for _, b in ipairs(GameState.buildings) do
		if b.part and Util.flatDist(point, b.part.Position) < gap then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- Dựng building (sau khi channel xong)
-------------------------------------------------------------------------------
-- Tên chủ (player: tên tài khoản; bot: "Bot N").
local function displayName(ownerId)
	if ownerId < 0 then return "Bot " .. tostring(-ownerId) end
	local p = Players:GetPlayerByUserId(ownerId)
	return Config.PLAYER_PREFIX .. ((p and p.DisplayName) or (p and p.Name) or "Player")
end

-- Bảng tên chủ nổi trên công trình (viền màu theo phe của chủ).
local function attachOwnerName(part, text, teamColor, yOffset)
	local bb = Instance.new("BillboardGui")
	bb.Name = "OwnerName"
	bb.Size = UDim2.new(0, 150, 0, 20)
	bb.StudsOffsetWorldSpace = Vector3.new(0, yOffset, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = part
	bb.MaxDistance = 600
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	local st = Instance.new("UIStroke"); st.Thickness = 2; st.Color = teamColor or Color3.fromRGB(20, 20, 20); st.Parent = l
	local cap = Instance.new("UITextSizeConstraint"); cap.MaxTextSize = 15; cap.Parent = l
	l.Parent = bb
	bb.Parent = part
end

-- Áp chỉ số theo tier hiện tại của building: máu + income/cap/combat.
-- fullHeal=true -> set hp = maxHp (dùng khi dựng & sau nâng cấp).
local function applyStats(b, fullHeal)
	local tiers = tierTable(b.buildingType)
	local stats = tiers[b.tier]
	-- HP theo công thức: hpBase * HP_TIER_MULT^(tier-1) (config chỉ điền hpBase).
	local hpMult = Config.ECONOMY.HP_TIER_MULT or 1.5
	b.maxHp = math.floor((tiers.hpBase or 300) * hpMult ^ (b.tier - 1) + 0.5)
	if fullHeal then b.hp = b.maxHp end
	if b.buildingType == "ScrapMine" then
		b.income = stats.income
	elseif b.buildingType == "DroneHub" then
		b.capBonus = stats.cap
	elseif isTower(b.buildingType) then
		local base = tiers.base
		b.dmg = base.dmg * stats.dmgMult -- +% damage theo tier
		b.range = base.range
		b.fireRate = base.fireRate
		b.aoe = base.aoe
		b.targeting = "UNITS_ONLY" -- tháp chỉ bắn quân địch
		b.cooldown = b.cooldown or 0
	end
end

local function createBuilding(ownerId, buildingType, tier, position, node)
	local v = VISUAL[buildingType]
	local mult = Config.ECONOMY.BUILD_SIZE_MULT or 1

	local part = Instance.new("Part")
	part.Name = buildingType
	part.Anchored = true
	part.CanCollide = false
	part.Size = v.size * mult          -- phóng to building
	part.Position = position
	part.Color = v.color
	part.Material = Enum.Material.Metal
	part:SetAttribute("OwnerUserId", ownerId)
	part:SetAttribute("Tier", tier)    -- cho client hiện UI nâng cấp
	part.Parent = folder

	local fill = attachHealthBar(part, part.Size.Y / 2 + 4)

	-- Tên chủ nổi phía trên thanh máu.
	local owner = GameState.motherships[ownerId]
	local teamColor = owner and owner.teamColor or Color3.fromRGB(200, 200, 200)
	attachOwnerName(part, displayName(ownerId), teamColor, part.Size.Y / 2 + 12)

	-- Tổng scrap đã đầu tư (để tính hoàn tiền khi bán).
	local tiers = tierTable(buildingType)
	local invested = 0
	for t = 1, tier do invested += tiers[t].cost end

	local b = {
		kind = "Building",
		buildingType = buildingType,
		ownerId = ownerId,
		tier = tier,
		part = part,
		healthFill = fill,
		node = node,      -- mỏ mà mine đứng trên (chỉ mine có)
		invested = invested,
	}
	applyStats(b, true)   -- set maxHp/hp + income/cap/combat theo tier
	table.insert(GameState.buildings, b)
	BuildingSystem.updateHealthBar(b)

	if buildingType == "DroneHub" then
		FleetSystem.sendFleetUpdate(ownerId) -- cap tăng
	end
	return b
end

-- Huỷ 1 building (do bị bắn chết / restart). Giải phóng asteroid, cập nhật cap.
function BuildingSystem.destroyBuilding(b)
	if b.node and GameState.oreDeposits[b.node] then
		GameState.oreDeposits[b.node].occupied = false
	end
	if b.part then b.part:Destroy() end
	for i = #GameState.buildings, 1, -1 do
		if GameState.buildings[i] == b then
			table.remove(GameState.buildings, i)
			break
		end
	end
	if b.buildingType == "DroneHub" then
		FleetSystem.sendFleetUpdate(b.ownerId)
	end
end

-- Huỷ toàn bộ công trình của 1 owner (khi Tàu Mẹ của họ chết).
function BuildingSystem.destroyOwnerBuildings(ownerId)
	for i = #GameState.buildings, 1, -1 do
		local b = GameState.buildings[i]
		if b.ownerId == ownerId then
			BuildingSystem.destroyBuilding(b) -- tự giải phóng mỏ + cập nhật cap
		end
	end
end

-- BÙ NHÌN TEST = CÔNG TRÌNH THẬT (loại có sẵn) phe địch (id -999), có máu THẬT nên
-- phá được (nổ + respawn chỗ khác do Main lo). Gắn cờ `dummy` -> KHÔNG đánh trả.
local DUMMY_OWNER = -999
local DUMMY_TYPES = { "DroneHub", "LaserSat", "PlasmaSat" } -- công trình đất (không cần mỏ)
function BuildingSystem.spawnDummy(pos, typeOverride)
	local bt = typeOverride or DUMMY_TYPES[math.random(#DUMMY_TYPES)]
	local b = createBuilding(DUMMY_OWNER, bt, 1, Vector3.new(pos.X, 40, pos.Z), nil)
	if b and b.part then
		b.part.Position = Vector3.new(pos.X, b.part.Size.Y / 2, pos.Z) -- đặt sát nền
		b.part:SetAttribute("Dummy", true) -- cho minimap nhận diện
		b.dummy = true                      -- CombatSystem bỏ qua khi bắn -> không đánh trả
	end
	return b
end

function BuildingSystem.clearAll()
	for i = #GameState.buildings, 1, -1 do
		local b = GameState.buildings[i]
		if b.node and GameState.oreDeposits[b.node] then
			GameState.oreDeposits[b.node].occupied = false
		end
		if b.part then b.part:Destroy() end
		GameState.buildings[i] = nil
	end
end

-------------------------------------------------------------------------------
-- Đặt building (bắt đầu channel)
-------------------------------------------------------------------------------
local function onPlaceBuilding(player, buildingType, point)
	if typeof(buildingType) ~= "string" or not tierTable(buildingType) then return end
	if typeof(point) ~= "Vector3" then return end

	local ownerId = player.UserId
	local owner = GameState.motherships[ownerId]
	if not owner or not owner.alive then return end

	if owner.channel then
		Remotes.Notify:FireClient(player, "Đang xây... chờ chút")
		return
	end

	-- Giới hạn số lượng mỗi loại (canon).
	if countOwned(ownerId, buildingType) >= (tierTable(buildingType).MAX or math.huge) then
		Remotes.Notify:FireClient(player, "Đã đạt tối đa loại này")
		return
	end

	point = Util.clampToMap(point, Config.MAP.SIZE)

	-- Tàu Mẹ phải trong tầm xây
	if Util.flatDist(owner.part.Position, point) > Config.ECONOMY.BUILD_RANGE then
		Remotes.Notify:FireClient(player, "Tàu Mẹ ở quá xa vị trí xây")
		return
	end

	local cost = EconomySystem.buildingCost(ownerId, buildingType, tierTable(buildingType)[1].cost)
	local buildPos, node

	if buildingType == "ScrapMine" then
		node = findOreDepositAt(point)
		if not node then
			Remotes.Notify:FireClient(player, "Mine chỉ đặt được trên MỎ (tinh thể)")
			return
		end
		if GameState.oreDeposits[node].occupied then
			Remotes.Notify:FireClient(player, "Mỏ này đã có mine")
			return
		end
		-- Đặt trên đỉnh mỏ
		local m = Config.ECONOMY.BUILD_SIZE_MULT or 1
		buildPos = Vector3.new(
			node.Position.X,
			VISUAL.ScrapMine.size.Y * m / 2 + 2,
			node.Position.Z
		)
	else -- đất trống: House + tháp phòng thủ
		if findOreDepositAt(point) then
			Remotes.Notify:FireClient(player, "Chỉ đặt trên đất trống (không trên mỏ)")
			return
		end
		if tooCloseToBuilding(point) then
			Remotes.Notify:FireClient(player, "Quá gần building khác")
			return
		end
		local m = Config.ECONOMY.BUILD_SIZE_MULT or 1
		buildPos = Vector3.new(point.X, VISUAL[buildingType].size.Y * m / 2, point.Z)
	end

	-- Đủ scrap?
	if EconomySystem.getScrap(ownerId) < cost then
		Remotes.Notify:FireClient(player, "Không đủ scrap!")
		return
	end

	-- Trừ tiền + reserve mỏ
	EconomySystem.spend(ownerId, cost)
	if node then
		GameState.oreDeposits[node].occupied = true
	end

	if Config.MOTHERSHIP.BUILD_CHANNEL <= 0 then
		-- Xây TỨC THÌ, không channel / không khoá di chuyển
		createBuilding(ownerId, buildingType, 1, buildPos, node)
		Remotes.Notify:FireClient(player, buildingType .. " đã xây")
	else
		-- Có channel: khoá di chuyển tới khi xong
		owner.channel = {
			buildingType = buildingType,
			tier = 1,
			point = buildPos,
			node = node,
			cost = cost,
			timeLeft = Config.MOTHERSHIP.BUILD_CHANNEL,
			total = Config.MOTHERSHIP.BUILD_CHANNEL,
		}
		Remotes.BuildStatus:FireClient(player, true, 0)
	end
end

local function onCancelBuild(player)
	local owner = GameState.motherships[player.UserId]
	if not owner or not owner.channel then return end
	local ch = owner.channel
	-- Hoàn tiền + giải phóng mỏ đã reserve
	EconomySystem.add(player.UserId, ch.cost)
	if ch.node and GameState.oreDeposits[ch.node] then
		GameState.oreDeposits[ch.node].occupied = false
	end
	owner.channel = nil
	Remotes.BuildStatus:FireClient(player, false, 0)
end

-------------------------------------------------------------------------------
-- Nâng cấp
-------------------------------------------------------------------------------
local function onUpgrade(player, part)
	if typeof(part) ~= "Instance" then return end
	local ownerId = player.UserId

	local b
	for _, bb in ipairs(GameState.buildings) do
		if bb.part == part and bb.ownerId == ownerId then
			b = bb
			break
		end
	end
	if not b then return end

	local tiers = tierTable(b.buildingType)
	local nextStats = tiers[b.tier + 1]
	if not nextStats then
		Remotes.Notify:FireClient(player, "Đã max tier")
		return
	end
	if EconomySystem.getScrap(ownerId) < nextStats.cost then
		Remotes.Notify:FireClient(player, "Không đủ scrap để nâng cấp")
		return
	end

	EconomySystem.spend(ownerId, nextStats.cost)
	b.tier += 1
	b.invested = (b.invested or 0) + nextStats.cost
	if b.part then b.part:SetAttribute("Tier", b.tier) end -- cho client UI
	applyStats(b, true) -- +stat theo tier + full heal (canon)
	if b.buildingType == "DroneHub" then
		FleetSystem.sendFleetUpdate(ownerId)
	end
	BuildingSystem.updateHealthBar(b)
	Remotes.Notify:FireClient(player, "Nâng cấp lên tier " .. b.tier)
end

-- Bán building: hoàn SELL_REFUND * tổng đã đầu tư, rồi huỷ.
local function onSell(player, part)
	if typeof(part) ~= "Instance" then return end
	local ownerId = player.UserId
	local b
	for _, bb in ipairs(GameState.buildings) do
		if bb.part == part and bb.ownerId == ownerId then b = bb; break end
	end
	if not b then return end
	local refund = math.floor((b.invested or 0) * Config.ECONOMY.SELL_REFUND)
	EconomySystem.add(ownerId, refund)
	BuildingSystem.destroyBuilding(b)
	Remotes.Notify:FireClient(player, ("Đã bán (+%d ◈)"):format(refund))
end

-------------------------------------------------------------------------------
-- Channel tick: đếm lùi, xong thì dựng
-------------------------------------------------------------------------------
local function updateChannels(dt)
	for ownerId, owner in pairs(GameState.motherships) do
		local ch = owner.channel
		if ch then
			ch.timeLeft -= dt
			local player = Players:GetPlayerByUserId(ownerId)
			if ch.timeLeft <= 0 then
				createBuilding(ownerId, ch.buildingType, ch.tier, ch.point, ch.node)
				owner.channel = nil
				if player then
					Remotes.BuildStatus:FireClient(player, false, 1)
					Remotes.Notify:FireClient(player, ch.buildingType .. " đã xây xong")
				end
			elseif player then
				local progress = 1 - (ch.timeLeft / ch.total)
				Remotes.BuildStatus:FireClient(player, true, progress)
			end
		end
	end
end

-- Bot đặt building trực tiếp (không qua remote/ghost). Xây tức thì. Trả về true nếu OK.
function BuildingSystem.botPlace(ownerId, buildingType, point)
	local tiers = tierTable(buildingType)
	if not tiers then return false end
	if countOwned(ownerId, buildingType) >= (tiers.MAX or math.huge) then return false end
	local owner = GameState.motherships[ownerId]
	if not owner or not owner.alive or owner.channel then return false end

	point = Util.clampToMap(point, Config.MAP.SIZE)
	if Util.flatDist(owner.part.Position, point) > Config.ECONOMY.BUILD_RANGE then return false end

	local cost = EconomySystem.buildingCost(ownerId, buildingType, tiers[1].cost)
	local buildPos, node
	local m = Config.ECONOMY.BUILD_SIZE_MULT or 1

	if buildingType == "ScrapMine" then
		node = findOreDepositAt(point)
		if not node or GameState.oreDeposits[node].occupied then return false end
		buildPos = Vector3.new(node.Position.X, VISUAL.ScrapMine.size.Y * m / 2 + 2, node.Position.Z)
	else
		if findOreDepositAt(point) or tooCloseToBuilding(point) then return false end
		buildPos = Vector3.new(point.X, VISUAL[buildingType].size.Y * m / 2, point.Z)
	end

	if EconomySystem.getScrap(ownerId) < cost then return false end

	EconomySystem.spend(ownerId, cost)
	if node then GameState.oreDeposits[node].occupied = true end
	createBuilding(ownerId, buildingType, 1, buildPos, node)
	return true
end

function BuildingSystem.init()
	folder = Instance.new("Folder")
	folder.Name = "Buildings"
	folder.Parent = Workspace

	Remotes.PlaceBuilding.OnServerEvent:Connect(onPlaceBuilding)
	Remotes.CancelBuild.OnServerEvent:Connect(onCancelBuild)
	Remotes.UpgradeBuilding.OnServerEvent:Connect(onUpgrade)
	Remotes.SellBuilding.OnServerEvent:Connect(onSell)

	RunService.Heartbeat:Connect(updateChannels)

	print("[BuildingSystem] ready")
end

return BuildingSystem
