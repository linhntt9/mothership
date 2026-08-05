--[[
	HUD.client.luau
	---------------
	Giao diện người chơi. Server là nguồn dữ liệu; HUD chỉ hiển thị + gửi ý định.

	M4:
	  - Scrap counter + Fleet counter (used/max).
	  - Hotbar dưới màn: 2 nút Xây (Mine/Hub) + 4 nút Mua quân, mỗi nút hiện cost,
	    tự xám khi không đủ scrap / đầy cap.
	  - Thanh trạng thái build channel.
	  - Dòng Notify ngắn (thiếu scrap, vị trí sai...).
	  - Màn Game Over + nút Chơi lại (M2).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local ClientBus = require(script.Parent.ClientBus)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Trạng thái để bật/tắt nút
local state = { scrap = 0, used = 0, max = 0 }

local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-------------------------------------------------------------------------------
-- Counters (góc dưới-phải): Scrap + Fleet
-------------------------------------------------------------------------------
local function makeCounter(name, posY, color)
	local lbl = Instance.new("TextLabel")
	lbl.Name = name
	lbl.AnchorPoint = Vector2.new(1, 1)
	lbl.Position = UDim2.new(1, -16, 1, posY)
	lbl.Size = UDim2.new(0, 200, 0, 38)
	lbl.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
	lbl.BackgroundTransparency = 0.25
	lbl.TextColor3 = color
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.Text = name
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = lbl
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 10); p.PaddingRight = UDim.new(0, 10); p.Parent = lbl
	lbl.Parent = gui
	return lbl
end

local scrapLabel = makeCounter("Scrap", -60, Color3.fromRGB(255, 220, 120))
local fleetLabel = makeCounter("Fleet", -16, Color3.fromRGB(180, 220, 255))

-------------------------------------------------------------------------------
-- Hotbar (dưới, giữa)
-------------------------------------------------------------------------------
local bar = Instance.new("Frame")
bar.Name = "Hotbar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -12)
bar.Size = UDim2.new(0, 6 * 116, 0, 66)
bar.BackgroundTransparency = 1
bar.Parent = gui
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 8)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = bar

-- Định nghĩa các nút. kind = "build" | "buy".
local BUY = Config.UNITS
local buttons = {}
local defs = {
	{ key = "ScrapMine",     kind = "build", label = "Mine",      hotkey = "Q", cost = Config.ECONOMY.SCRAP_MINE[1].cost, weight = 0 },
	{ key = "DroneHub",      kind = "build", label = "Hub",       hotkey = "R", cost = Config.ECONOMY.DRONE_HUB[1].cost,  weight = 0 },
	{ key = "Drone",         kind = "buy",   label = "Drone",     hotkey = "1", cost = BUY.Drone.cost,         weight = Config.FLEET.WEIGHT.Drone },
	{ key = "Frigate",       kind = "buy",   label = "Frigate",   hotkey = "2", cost = BUY.Frigate.cost,       weight = Config.FLEET.WEIGHT.Frigate },
	{ key = "Destroyer",     kind = "buy",   label = "Destroyer", hotkey = "3", cost = BUY.Destroyer.cost,     weight = Config.FLEET.WEIGHT.Destroyer },
	{ key = "PlasmaCruiser", kind = "buy",   label = "Plasma",    hotkey = "4", cost = BUY.PlasmaCruiser.cost, weight = Config.FLEET.WEIGHT.PlasmaCruiser },
}

for i, def in ipairs(defs) do
	local btn = Instance.new("TextButton")
	btn.Name = def.key
	btn.LayoutOrder = i
	btn.Size = UDim2.new(0, 108, 1, 0)
	btn.BackgroundColor3 = (def.kind == "build") and Color3.fromRGB(70, 90, 120) or Color3.fromRGB(50, 70, 60)
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBold
	btn.TextColor3 = Color3.fromRGB(240, 240, 240)
	btn.TextSize = 15
	btn.Text = ("%s\n%d ◈\n[%s]"):format(def.label, def.cost, def.hotkey)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = btn
	btn.Parent = bar

	btn.Activated:Connect(function()
		if def.kind == "build" then
			ClientBus.enterBuild:Fire(def.key)
		else
			Remotes.SpawnUnit:FireServer(def.key)
		end
	end)

	buttons[i] = { def = def, btn = btn }
end

-- Bật/xám nút theo scrap + cap hiện tại
local function refreshButtons()
	scrapLabel.Text = ("Scrap: %d ◈"):format(state.scrap)
	fleetLabel.Text = ("Fleet: %d/%d"):format(state.used, state.max)
	fleetLabel.TextColor3 = (state.used >= state.max)
		and Color3.fromRGB(255, 150, 150) or Color3.fromRGB(180, 220, 255)

	for _, entry in ipairs(buttons) do
		local def = entry.def
		local ok = state.scrap >= def.cost
		if def.kind == "buy" and (state.used + def.weight) > state.max then
			ok = false
		end
		entry.btn.AutoButtonColor = ok
		entry.btn.TextTransparency = ok and 0 or 0.45
		entry.btn.BackgroundTransparency = ok and 0 or 0.5
	end
end

Remotes.ScrapUpdate.OnClientEvent:Connect(function(scrap)
	state.scrap = scrap
	refreshButtons()
end)
Remotes.FleetUpdate.OnClientEvent:Connect(function(used, max)
	state.used, state.max = used, max
	refreshButtons()
end)
refreshButtons()

-------------------------------------------------------------------------------
-- Build status (giữa, hơi trên hotbar)
-------------------------------------------------------------------------------
local buildStatus = Instance.new("TextLabel")
buildStatus.AnchorPoint = Vector2.new(0.5, 1)
buildStatus.Position = UDim2.new(0.5, 0, 1, -86)
buildStatus.Size = UDim2.new(0, 320, 0, 30)
buildStatus.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
buildStatus.BackgroundTransparency = 0.2
buildStatus.TextColor3 = Color3.fromRGB(255, 230, 150)
buildStatus.Font = Enum.Font.GothamBold
buildStatus.TextSize = 16
buildStatus.Visible = false
local bsc = Instance.new("UICorner"); bsc.CornerRadius = UDim.new(0, 6); bsc.Parent = buildStatus
buildStatus.Parent = gui

Remotes.BuildStatus.OnClientEvent:Connect(function(active, progress)
	buildStatus.Visible = active
	if active then
		buildStatus.Text = ("Đang xây... %d%% (đứng yên)"):format(math.floor(progress * 100))
	end
end)

-------------------------------------------------------------------------------
-- Notify (giữa trên)
-------------------------------------------------------------------------------
local notify = Instance.new("TextLabel")
notify.AnchorPoint = Vector2.new(0.5, 0)
notify.Position = UDim2.new(0.5, 0, 0, 70)
notify.Size = UDim2.new(0, 460, 0, 34)
notify.BackgroundTransparency = 1
notify.TextColor3 = Color3.fromRGB(255, 200, 200)
notify.Font = Enum.Font.GothamBold
notify.TextSize = 18
notify.Text = ""
notify.Parent = gui

local notifyToken = 0
Remotes.Notify.OnClientEvent:Connect(function(text)
	notify.Text = text
	notifyToken += 1
	local myToken = notifyToken
	task.delay(2, function()
		if myToken == notifyToken then notify.Text = "" end
	end)
end)

-------------------------------------------------------------------------------
-- Hint phím
-------------------------------------------------------------------------------
local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0, 1)
hint.Position = UDim2.new(0, 16, 1, -16)
hint.Size = UDim2.new(0, 560, 0, 24)
hint.BackgroundTransparency = 1
hint.TextColor3 = Color3.fromRGB(200, 200, 210)
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Font = Enum.Font.Gotham
hint.TextSize = 14
hint.Text = "1-4: mua quân | Q: Mine (trên mỏ) | R: Hub | click map để đặt | click building: nâng cấp | chuột phải: huỷ | SPACE: Split"
hint.Parent = gui

-------------------------------------------------------------------------------
-- Leaderboard (góc trên-phải)
-------------------------------------------------------------------------------
local lb = Instance.new("Frame")
lb.Name = "Leaderboard"
lb.AnchorPoint = Vector2.new(1, 0)
lb.Position = UDim2.new(1, -16, 0, 16)
lb.Size = UDim2.new(0, 200, 0, 0)
lb.AutomaticSize = Enum.AutomaticSize.Y
lb.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
lb.BackgroundTransparency = 0.25
local lbc = Instance.new("UICorner"); lbc.CornerRadius = UDim.new(0, 8); lbc.Parent = lb
local lbpad = Instance.new("UIPadding")
lbpad.PaddingTop = UDim.new(0, 6); lbpad.PaddingBottom = UDim.new(0, 6)
lbpad.PaddingLeft = UDim.new(0, 8); lbpad.PaddingRight = UDim.new(0, 8)
lbpad.Parent = lb
local lblist = Instance.new("UIListLayout")
lblist.Padding = UDim.new(0, 2); lblist.SortOrder = Enum.SortOrder.LayoutOrder
lblist.Parent = lb
lb.Parent = gui

local lbTitle = Instance.new("TextLabel")
lbTitle.LayoutOrder = 0
lbTitle.Size = UDim2.new(1, 0, 0, 22)
lbTitle.BackgroundTransparency = 1
lbTitle.TextColor3 = Color3.fromRGB(255, 220, 120)
lbTitle.Font = Enum.Font.GothamBold
lbTitle.TextSize = 15
lbTitle.Text = "BẢNG XẾP HẠNG"
lbTitle.Parent = lb

local lbRows = {}
Remotes.Leaderboard.OnClientEvent:Connect(function(list)
	for _, r in ipairs(lbRows) do r:Destroy() end
	table.clear(lbRows)
	for i, entry in ipairs(list) do
		local row = Instance.new("TextLabel")
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 20)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.Gotham
		row.TextSize = 14
		row.TextXAlignment = Enum.TextXAlignment.Left
		local mine = (entry.id == player.UserId)
		row.TextColor3 = mine and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(220, 220, 225)
		row.Font = mine and Enum.Font.GothamBold or Enum.Font.Gotham
		row.Text = ("%d. %s — %d"):format(i, entry.name, entry.score)
		row.Parent = lb
		table.insert(lbRows, row)
	end
end)

-------------------------------------------------------------------------------
-- Game Over
-------------------------------------------------------------------------------
local overlay = Instance.new("Frame")
overlay.Name = "GameOver"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.4
overlay.Visible = false
overlay.ZIndex = 10
overlay.Parent = gui

local resultLabel = Instance.new("TextLabel")
resultLabel.AnchorPoint = Vector2.new(0.5, 0.5)
resultLabel.Position = UDim2.new(0.5, 0, 0.42, 0)
resultLabel.Size = UDim2.new(0, 600, 0, 90)
resultLabel.BackgroundTransparency = 1
resultLabel.Font = Enum.Font.GothamBlack
resultLabel.TextScaled = true
resultLabel.ZIndex = 11
resultLabel.Text = ""
resultLabel.Parent = overlay

local restartBtn = Instance.new("TextButton")
restartBtn.AnchorPoint = Vector2.new(0.5, 0.5)
restartBtn.Position = UDim2.new(0.5, 0, 0.58, 0)
restartBtn.Size = UDim2.new(0, 220, 0, 60)
restartBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 220)
restartBtn.Font = Enum.Font.GothamBold
restartBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
restartBtn.TextScaled = true
restartBtn.Text = "Chơi lại"
restartBtn.ZIndex = 11
local btnCorner = Instance.new("UICorner"); btnCorner.CornerRadius = UDim.new(0, 10); btnCorner.Parent = restartBtn
restartBtn.Parent = overlay

restartBtn.Activated:Connect(function()
	overlay.Visible = false
	Remotes.Restart:FireServer()
end)

Remotes.GameOver.OnClientEvent:Connect(function(result)
	if result == "victory" then
		resultLabel.Text = "VICTORY"
		resultLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
	else
		resultLabel.Text = "YOU DIED"
		resultLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
	end
	overlay.Visible = true
end)
