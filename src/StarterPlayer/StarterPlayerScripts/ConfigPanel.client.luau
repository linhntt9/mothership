--[[
	ConfigPanel.client.luau
	-----------------------
	Bảng CONFIG in-game (dev tool). Cho phép chỉnh các số balance ngay khi chơi:
	sửa ô -> gửi Remotes.SetConfig(path, value) -> server cập nhật Config (bản
	server, nơi chạy simulation).

	Mở/đóng: nút ⚙ góc trên-trái, hoặc phím `~` (Backquote).

	LƯU Ý phạm vi áp dụng:
	  - Áp dụng NGAY: tốc độ/xoay/split/follow Tàu Mẹ & hạm đội, income mine,
	    cap hub, income tick, pickup, build range...
	  - Áp dụng cho quân/công trình SPAWN MỚI: các chỉ số combat của unit &
	    Tàu Mẹ (hp/dmg/range/fireRate...) được "chốt" lúc spawn -> mua quân mới
	    hoặc Restart để thấy đổi.
	  - Cần CHƠI LẠI (dựng lại map): MAP.SIZE, số mỏ, khoảng cách mỏ, spawn góc,
	    số orb/cụm scrap. Sửa số xong bấm "☠ Tự sát / Chơi lại".
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local ClientBus = require(script.Parent.ClientBus)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-------------------------------------------------------------------------------
-- Danh sách field tune được (label, path)
-------------------------------------------------------------------------------
-- Mỗi field thuộc 1 TAB. Mặc định "Game"; bot AI ở tab "Bot".
local tunables = {}
local function add(label, path, tab) table.insert(tunables, { label = label, path = path, tab = tab or "Game" }) end

add("— TÀU MẸ —", nil)
add("Speed", "MOTHERSHIP.SPEED")
add("Speed penalty/weight", "MOTHERSHIP.SPEED_WEIGHT_PENALTY")
add("Speed min mult", "MOTHERSHIP.SPEED_MIN_MULT")
add("HP", "MOTHERSHIP.HP")
add("Dmg", "MOTHERSHIP.DMG")
add("Range", "MOTHERSHIP.RANGE")
add("FireRate", "MOTHERSHIP.FIRE_RATE")
add("AoE", "MOTHERSHIP.AOE")
add("Build Channel (s)", "MOTHERSHIP.BUILD_CHANNEL")
add("Regen delay (s)", "MOTHERSHIP.REGEN_DELAY")
add("Regen rate (hp/s)", "MOTHERSHIP.REGEN_RATE")
add("Radar Range", "MOTHERSHIP.RADAR_RANGE")

add("— CAMERA —", nil)
add("Height (gần/xa)", "CAMERA.HEIGHT")
add("Tilt", "CAMERA.TILT_OFFSET")

-- MAP: các field này chỉ đổi khi map ĐƯỢC DỰNG LẠI -> bấm "Chơi lại" để áp.
add("— MAP (Chơi lại để áp) —", nil)
add("Kích thước map", "MAP.SIZE")
add("Số mỏ", "MAP.ORE_DEPOSIT_COUNT")
add("Khoảng cách mỏ", "MAP.ORE_DEPOSIT_MIN_GAP")
add("Spawn góc (0..1)", "MAP.SPAWN_FRAC")

add("— HẠM ĐỘI —", nil)
add("Base Cap", "FLEET.BASE_CAP")
add("Orbit Spin", "FLEET.ORBIT_SPIN")
add("Split Spread", "FLEET.SPLIT_SAT_SPREAD")
add("Follow Gain", "FLEET.FOLLOW_GAIN")
add("Inner Radius", "FLEET.INNER_RADIUS")
add("Ring Gap", "FLEET.RING_GAP")
add("Unit Spacing", "FLEET.UNIT_SPACING")
add("Ring Max Slots", "FLEET.RING_MAX_SLOTS")
add("Separation", "FLEET.SEPARATION_STRENGTH")

add("— KINH TẾ —", nil)
add("Start Scrap", "ECONOMY.START_SCRAP")
add("Income Tick (s)", "ECONOMY.INCOME_TICK")
add("Build Range", "ECONOMY.BUILD_RANGE")

add("— SCRAP RẢI —", nil)
add("Magnet Range", "PICKUP.MAGNET_RANGE")
add("Fly Speed", "PICKUP.FLY_SPEED")
add("Giá trị mỗi orb (+scrap)", "PICKUP.VALUE")
add("Mật độ orb /100k (Chơi lại)", "PICKUP.SCRAP_PER_100K")
add("Mật độ cụm /100k (Chơi lại)", "PICKUP.CLUSTER_PER_100K")
add("Cluster size (Chơi lại)", "PICKUP.CLUSTER_SIZE")

-- Chỉ số từng loại quân (áp dụng cho quân spawn mới)
for _, u in ipairs({ "Drone", "Frigate", "Destroyer", "PlasmaCruiser", "Interceptor", "Battleship", "SiegeRailgun", "Titan", "Kamikaze" }) do
	add("— " .. u .. " —", nil)
	for _, stat in ipairs({ "cost", "hp", "dmg", "range", "fireRate", "speed", "weight", "aoeRadius" }) do
		add(u .. "." .. stat, "UNITS." .. u .. "." .. stat)
	end
end

-- ===== TAB "BOT" — chỉnh AI bot =====
add("— BOT AI —", nil, "Bot")
add("Số bot đầu trận (Chơi lại)", "BOT_COUNT", "Bot")
add("Giữ bot trong sân (auto-respawn)", "BOT.MAINTAIN", "Bot")
add("Nhịp quyết định (s)", "BOT.DECISION_INTERVAL", "Bot")
add("Số mine mục tiêu", "BOT.TARGET_MINES", "Bot")
add("Ngưỡng tấn công (x địch)", "BOT.AGGRESS_RATIO", "Bot")
add("Lùi khi HP < (0..1)", "BOT.RETREAT_HP", "Bot")
add("Lùi khi fleet yếu < (x)", "BOT.RETREAT_WEAK", "Bot")
add("Mua quân mỗi nhịp", "BOT.BUY_PER_TICK", "Bot")

-- ===== TAB "Nhà" — chỉnh stat công trình (tower dmg/range áp cho building spawn mới) =====
add("— CHUNG —", nil, "Nhà")
add("Kích cỡ nhà (xN, xây mới)", "ECONOMY.BUILD_SIZE_MULT", "Nhà")
add("HP scale mỗi tier (x)", "ECONOMY.HP_TIER_MULT", "Nhà")

add("— GOLD MINE —", nil, "Nhà")
add("Mine · Max", "ECONOMY.SCRAP_MINE.MAX", "Nhà")
add("Mine T1 cost", "ECONOMY.SCRAP_MINE.1.cost", "Nhà")
add("Mine T1 income", "ECONOMY.SCRAP_MINE.1.income", "Nhà")
add("Mine T2 income", "ECONOMY.SCRAP_MINE.2.income", "Nhà")
add("Mine T3 income", "ECONOMY.SCRAP_MINE.3.income", "Nhà")
add("Mine HP nền", "ECONOMY.SCRAP_MINE.hpBase", "Nhà")

add("— HOUSE —", nil, "Nhà")
add("House · Max", "ECONOMY.DRONE_HUB.MAX", "Nhà")
add("House T1 cost", "ECONOMY.DRONE_HUB.1.cost", "Nhà")
add("House T1 cap", "ECONOMY.DRONE_HUB.1.cap", "Nhà")
add("House T2 cap", "ECONOMY.DRONE_HUB.2.cap", "Nhà")
add("House T3 cap", "ECONOMY.DRONE_HUB.3.cap", "Nhà")
add("House T4 cap", "ECONOMY.DRONE_HUB.4.cap", "Nhà")
add("House HP nền", "ECONOMY.DRONE_HUB.hpBase", "Nhà")

add("— LASER SAT —", nil, "Nhà")
add("Laser · Max", "ECONOMY.LASER_SAT.MAX", "Nhà")
add("Laser dmg (nền)", "ECONOMY.LASER_SAT.base.dmg", "Nhà")
add("Laser range", "ECONOMY.LASER_SAT.base.range", "Nhà")
add("Laser fireRate", "ECONOMY.LASER_SAT.base.fireRate", "Nhà")
add("Laser T1 cost", "ECONOMY.LASER_SAT.1.cost", "Nhà")
add("Laser HP nền", "ECONOMY.LASER_SAT.hpBase", "Nhà")

add("— PLASMA SAT —", nil, "Nhà")
add("Plasma · Max", "ECONOMY.PLASMA_SAT.MAX", "Nhà")
add("Plasma dmg (nền)", "ECONOMY.PLASMA_SAT.base.dmg", "Nhà")
add("Plasma range", "ECONOMY.PLASMA_SAT.base.range", "Nhà")
add("Plasma fireRate", "ECONOMY.PLASMA_SAT.base.fireRate", "Nhà")
add("Plasma AoE", "ECONOMY.PLASMA_SAT.base.aoe", "Nhà")
add("Plasma T1 cost", "ECONOMY.PLASMA_SAT.1.cost", "Nhà")
add("Plasma HP nền", "ECONOMY.PLASMA_SAT.hpBase", "Nhà")

-------------------------------------------------------------------------------
-- Đọc/ghi giá trị trong bản Config của client (để hiển thị & đồng bộ)
-------------------------------------------------------------------------------
local function getVal(path)
	local parts = string.split(path, ".")
	local t = Config
	for i = 1, #parts do
		local key = tonumber(parts[i]) or parts[i]
		t = t[key]
		if t == nil then return nil end
	end
	return t
end

local function setValClient(path, value)
	local parts = string.split(path, ".")
	local t = Config
	for i = 1, #parts - 1 do
		local key = tonumber(parts[i]) or parts[i]
		t = t[key]
		if type(t) ~= "table" then return end
	end
	local lastKey = tonumber(parts[#parts]) or parts[#parts]
	t[lastKey] = value
end

-------------------------------------------------------------------------------
-- GUI
-------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "ConfigPanel"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = playerGui

-- Nút mở/đóng
local toggle = Instance.new("TextButton")
toggle.Size = UDim2.new(0, 40, 0, 40)
toggle.Position = UDim2.new(0, 12, 0, 52) -- dưới topbar Roblox, cạnh trái nút Lobby
toggle.BackgroundColor3 = Color3.fromRGB(40, 46, 60)
toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 22
toggle.Text = "⚙"
local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 8); tc.Parent = toggle
toggle.Parent = gui

-- Khung panel
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 340, 0, 460)
panel.Position = UDim2.new(0, 12, 0, 98)
panel.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
panel.BackgroundTransparency = 0.05
panel.Active = true        -- hút input, không lọt xuống thao tác game
panel.Visible = false
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 10); pc.Parent = panel
panel.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(255, 220, 120)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.Text = "CONFIG (sửa số rồi Enter)"
title.Parent = panel

-- Hàng nút: Chơi lại | +Bot (góc) | +Bot gần (cạnh Tàu Mẹ để test ngay)
local function rowBtn(x, w, color, text, onClick, y)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(w, -6, 0, 30)
	b.Position = UDim2.new(x, 3, 0, y or 32)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.Text = text
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = b
	b.Parent = panel
	b.Activated:Connect(onClick)
	return b
end
-- matchOnly: các nút + vùng config CHỈ dùng ở trận thật -> ẩn khi vào sandbox test.
local matchOnly = {}
matchOnly[1] = rowBtn(0, 0.30, Color3.fromRGB(180, 60, 60), "☠ Chơi lại", function() Remotes.Restart:FireServer() end)
matchOnly[2] = rowBtn(0.30, 0.20, Color3.fromRGB(60, 120, 90), "＋ Bot", function() Remotes.AddBot:FireServer() end)
matchOnly[3] = rowBtn(0.50, 0.26, Color3.fromRGB(70, 150, 110), "＋ Bot gần", function() Remotes.AddBot:FireServer(true) end)
local botBtn
botBtn = rowBtn(0.76, 0.24, Color3.fromRGB(70, 90, 130), "👁 Bot", function()
	ClientBus.showBots = not ClientBus.showBots
	botBtn.Text = ClientBus.showBots and "👁 Bot ✓" or "👁 Bot"
	botBtn.BackgroundColor3 = ClientBus.showBots and Color3.fromRGB(80, 150, 90) or Color3.fromRGB(70, 90, 130)
end)

matchOnly[4] = botBtn

-- Hàng 2: SANDBOX Test Combat (nơi riêng) + bơm quân 2 phe + thoát về sảnh.
rowBtn(0, 0.30, Color3.fromRGB(150, 90, 60), "⚔ Test", function() Remotes.StartTest:FireServer() end, 66)
rowBtn(0.30, 0.26, Color3.fromRGB(70, 110, 160), "＋ Tôi", function() Remotes.TestSpawn:FireServer("me") end, 66)
rowBtn(0.56, 0.26, Color3.fromRGB(160, 80, 80), "＋ Dummy", function() Remotes.TestSpawn:FireServer("dummy") end, 66)
rowBtn(0.82, 0.18, Color3.fromRGB(90, 90, 110), "🏠", function() Remotes.ToLobby:FireServer() end, 66)

-- Tab bar (Game / Bot) — lọc field theo tab.
local setTab            -- gán sau khi tạo rows
local tabBtns = {}
local tabBar = Instance.new("Frame")
tabBar.Position = UDim2.new(0, 6, 0, 102)
tabBar.Size = UDim2.new(1, -12, 0, 26)
tabBar.BackgroundTransparency = 1
tabBar.Parent = panel
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.Parent = tabBar
for i, tname in ipairs({ "Game", "Bot", "Nhà" }) do
	local tb = Instance.new("TextButton")
	tb.LayoutOrder = i
	tb.Size = UDim2.new(0, 88, 1, 0)
	tb.BackgroundColor3 = Color3.fromRGB(40, 46, 60)
	tb.TextColor3 = Color3.fromRGB(230, 230, 235)
	tb.Font = Enum.Font.GothamBold
	tb.TextSize = 14
	tb.Text = tname
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = tb
	tb.Activated:Connect(function() setTab(tname) end)
	tb.Parent = tabBar
	tabBtns[tname] = tb
end

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -12, 1, -136)
scroll.Position = UDim2.new(0, 6, 0, 132)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 3)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll

local boxesByPath = {} -- [path] = TextBox (để đồng bộ số đã lưu)

local function makeHeaderRow(text, order)
	local lbl = Instance.new("TextLabel")
	lbl.LayoutOrder = order
	lbl.Size = UDim2.new(1, 0, 0, 22)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(120, 200, 255)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 13
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = text
	lbl.Parent = scroll
	return lbl
end

local function makeFieldRow(def, order)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundTransparency = 1
	row.Parent = scroll

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.62, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(220, 220, 225)
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 13
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = def.label
	lbl.Parent = row

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0.36, 0, 1, 0)
	box.Position = UDim2.new(0.64, 0, 0, 0)
	box.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
	box.TextColor3 = Color3.fromRGB(255, 255, 255)
	box.Font = Enum.Font.GothamBold
	box.TextSize = 13
	box.ClearTextOnFocus = false
	local v = getVal(def.path)
	box.Text = v and string.format("%g", v) or "?"
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 5); bc.Parent = box
	box.Parent = row
	boxesByPath[def.path] = box

	box.FocusLost:Connect(function()
		local n = tonumber(box.Text)
		if n then
			setValClient(def.path, n)          -- đồng bộ hiển thị client
			Remotes.SetConfig:FireServer(def.path, n) -- áp lên server
			box.Text = string.format("%g", n)
			box.BackgroundColor3 = Color3.fromRGB(40, 90, 55) -- flash xanh
			task.delay(0.4, function() box.BackgroundColor3 = Color3.fromRGB(35, 40, 52) end)
		else
			local cur = getVal(def.path)
			box.Text = cur and string.format("%g", cur) or "?"
		end
	end)
	return row
end

add("— SIZE QUÂN (× cỡ, áp quân spawn mới) —", nil, "Game")
add("Drone size", "UNIT_SIZE.Drone", "Game")
add("Frigate size", "UNIT_SIZE.Frigate", "Game")
add("Destroyer size", "UNIT_SIZE.Destroyer", "Game")
add("Plasma size", "UNIT_SIZE.PlasmaCruiser", "Game")
add("Interceptor size", "UNIT_SIZE.Interceptor", "Game")
add("Battleship size", "UNIT_SIZE.Battleship", "Game")
add("Siege size", "UNIT_SIZE.SiegeRailgun", "Game")
add("Titan size", "UNIT_SIZE.Titan", "Game")
add("Kamikaze size", "UNIT_SIZE.Kamikaze", "Game")

-- Config TEST (chỉ hiện trong sandbox ⚔ Test): tinh chỉnh tầm lao của cận chiến.
add("— CẬN CHIẾN: tầm lao (aggro) —", nil, "Game")
add("Drone aggro", "UNITS.Drone.aggro", "Game")
add("Destroyer aggro", "UNITS.Destroyer.aggro", "Game")
add("Interceptor aggro", "UNITS.Interceptor.aggro", "Game")
add("Titan aggro", "UNITS.Titan.aggro", "Game")

-- Tạo rows + gắn tab để lọc.
local rows = {} -- { inst, tab }
for i, def in ipairs(tunables) do
	local inst = (def.path == nil) and makeHeaderRow(def.label, i) or makeFieldRow(def, i)
	rows[#rows + 1] = { inst = inst, tab = def.tab }
end

-- Đổi tab: hiện field đúng tab, tô sáng nút tab đang chọn.
function setTab(t)
	for _, r in ipairs(rows) do
		r.inst.Visible = (r.tab == t)
	end
	for name, btn in pairs(tabBtns) do
		btn.BackgroundColor3 = (name == t) and Color3.fromRGB(70, 120, 200) or Color3.fromRGB(40, 46, 60)
	end
end
setTab("Game")

-- Lọc UI theo SANDBOX test: ẩn nút/bảng config của trận thật, chỉ chừa hàng test.
local function applyTestFilter(isTest)
	for _, b in ipairs(matchOnly) do b.Visible = not isTest end
	tabBar.Visible = not isTest              -- test: ẩn tab trận (chỉ còn field test)
	scroll.Visible = true                    -- luôn hiện vùng field
	setTab(isTest and "Test" or "Game")      -- test -> field aggro; thường -> tab Game
end
Remotes.TestState.OnClientEvent:Connect(applyTestFilter)

-- Đồng bộ số đã lưu từ server -> cập nhật Config client + ô hiển thị
Remotes.ConfigSync.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	for path, value in pairs(data) do
		if type(value) == "number" then
			setValClient(path, value)
			local box = boxesByPath[path]
			if box then box.Text = string.format("%g", value) end
		end
	end
end)
Remotes.ConfigSync:FireServer() -- xin số đã lưu ngay khi vào

-------------------------------------------------------------------------------
-- Đóng/mở
-------------------------------------------------------------------------------
local function setOpen(open)
	panel.Visible = open
	toggle.Text = open and "✕" or "⚙"
end
toggle.Activated:Connect(function() setOpen(not panel.Visible) end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Backquote then
		setOpen(not panel.Visible)
	end
end)
