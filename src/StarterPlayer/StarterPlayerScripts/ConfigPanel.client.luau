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
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-------------------------------------------------------------------------------
-- Danh sách field tune được (label, path)
-------------------------------------------------------------------------------
local tunables = {}
local function add(label, path) table.insert(tunables, { label = label, path = path }) end

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

add("— CAMERA —", nil)
add("Height (gần/xa)", "CAMERA.HEIGHT")
add("Tilt", "CAMERA.TILT_OFFSET")

add("— HẠM ĐỘI —", nil)
add("Base Cap", "FLEET.BASE_CAP")
add("Orbit Spin", "FLEET.ORBIT_SPIN")
add("Split Dist", "FLEET.SPLIT_DIST")
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
add("Mine T1 income", "ECONOMY.SCRAP_MINE.1.income")
add("Mine T1 cost", "ECONOMY.SCRAP_MINE.1.cost")
add("Mine T2 income", "ECONOMY.SCRAP_MINE.2.income")
add("Mine T3 income", "ECONOMY.SCRAP_MINE.3.income")
add("Hub T1 cap", "ECONOMY.DRONE_HUB.1.cap")
add("Hub T1 cost", "ECONOMY.DRONE_HUB.1.cost")

add("— SCRAP RẢI —", nil)
add("Magnet Range", "PICKUP.MAGNET_RANGE")
add("Fly Speed", "PICKUP.FLY_SPEED")
add("Target Count", "PICKUP.TARGET_COUNT")

-- Chỉ số từng loại quân (áp dụng cho quân spawn mới)
for _, u in ipairs({ "Drone", "Frigate", "Destroyer", "PlasmaCruiser" }) do
	add("— " .. u .. " —", nil)
	add(u .. ".weight", "FLEET.WEIGHT." .. u)
	for _, stat in ipairs({ "cost", "hp", "dmg", "range", "fireRate", "speed", "aoe" }) do
		add(u .. "." .. stat, "UNITS." .. u .. "." .. stat)
	end
end

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
toggle.Size = UDim2.new(0, 44, 0, 44)
toggle.Position = UDim2.new(0, 10, 0, 10)
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
panel.Position = UDim2.new(0, 10, 0, 62)
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

-- Nút Tự sát / Chơi lại (reset ván ngay)
local restartBtn = Instance.new("TextButton")
restartBtn.Size = UDim2.new(1, -12, 0, 30)
restartBtn.Position = UDim2.new(0, 6, 0, 32)
restartBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
restartBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
restartBtn.Font = Enum.Font.GothamBold
restartBtn.TextSize = 15
restartBtn.Text = "☠ Tự sát / Chơi lại"
local rbc = Instance.new("UICorner"); rbc.CornerRadius = UDim.new(0, 6); rbc.Parent = restartBtn
restartBtn.Parent = panel
restartBtn.Activated:Connect(function()
	Remotes.Restart:FireServer()
end)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -12, 1, -74)
scroll.Position = UDim2.new(0, 6, 0, 68)
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
end

for i, def in ipairs(tunables) do
	if def.path == nil then
		makeHeaderRow(def.label, i)
	else
		makeFieldRow(def, i)
	end
end

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
