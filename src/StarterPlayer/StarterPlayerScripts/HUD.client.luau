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
gui.Enabled = false   -- ẩn ở lobby; chỉ hiện khi vào trận (nghe MatchState ở cuối file)
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
	{ key = "Drone",         kind = "buy",   label = "Drone",     hotkey = "1", cost = BUY.Drone.cost,         weight = BUY.Drone.weight },
	{ key = "Frigate",       kind = "buy",   label = "Frigate",   hotkey = "2", cost = BUY.Frigate.cost,       weight = BUY.Frigate.weight },
	{ key = "Destroyer",     kind = "buy",   label = "Destroyer", hotkey = "3", cost = BUY.Destroyer.cost,     weight = BUY.Destroyer.weight },
	{ key = "PlasmaCruiser", kind = "buy",   label = "Plasma",    hotkey = "4", cost = BUY.PlasmaCruiser.cost, weight = BUY.PlasmaCruiser.weight },
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
-- Nút Về Lobby (trong trận) — góc trên-trái, cạnh nút ⚙
-------------------------------------------------------------------------------
local backBtn = Instance.new("TextButton")
backBtn.Name = "BackToLobby"
backBtn.Position = UDim2.new(0, 62, 0, 10)
backBtn.Size = UDim2.new(0, 118, 0, 36)
backBtn.BackgroundColor3 = Color3.fromRGB(70, 120, 220)
backBtn.Font = Enum.Font.GothamBold
backBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
backBtn.TextSize = 16
backBtn.Text = "⌂ Lobby"
local bkc = Instance.new("UICorner"); bkc.CornerRadius = UDim.new(0, 8); bkc.Parent = backBtn
backBtn.Parent = gui
backBtn.Activated:Connect(function()
	Remotes.ToLobby:FireServer()
end)

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
-- Bảng kết thúc (card): tiêu đề + 3 ô thống kê + nút Chơi lại
-------------------------------------------------------------------------------
local overlay = Instance.new("Frame")
overlay.Name = "GameOver"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.45
overlay.Visible = false
overlay.ZIndex = 10
overlay.Parent = gui

local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.new(0.5, 0, 0.5, 0)
card.Size = UDim2.new(0, 480, 0, 328)
card.BackgroundColor3 = Color3.fromRGB(24, 28, 40)
card.ZIndex = 11
local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 18); cc.Parent = card
local cs = Instance.new("UIStroke"); cs.Thickness = 2; cs.Color = Color3.fromRGB(70, 90, 120); cs.Transparency = 0.3; cs.Parent = card
card.Parent = overlay

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 22); pad.PaddingBottom = UDim.new(0, 22)
pad.PaddingLeft = UDim.new(0, 24); pad.PaddingRight = UDim.new(0, 24)
pad.Parent = card

local vlist = Instance.new("UIListLayout")
vlist.FillDirection = Enum.FillDirection.Vertical
vlist.HorizontalAlignment = Enum.HorizontalAlignment.Center
vlist.Padding = UDim.new(0, 16)
vlist.SortOrder = Enum.SortOrder.LayoutOrder
vlist.Parent = card

-- Tiêu đề
local titleL = Instance.new("TextLabel")
titleL.LayoutOrder = 1
titleL.Size = UDim2.new(1, 0, 0, 60)
titleL.BackgroundTransparency = 1
titleL.Font = Enum.Font.GothamBlack
titleL.TextScaled = true
titleL.ZIndex = 12
titleL.Text = ""
titleL.Parent = card
local tconstr = Instance.new("UITextSizeConstraint"); tconstr.MaxTextSize = 38; tconstr.Parent = titleL

-- Lưới 6 chỉ số (2 cột x 3 hàng) như bảng tổng kết mẫu.
local statsGrid = Instance.new("Frame")
statsGrid.LayoutOrder = 2
statsGrid.Size = UDim2.new(1, 0, 0, 3 * 28 + 2 * 8)
statsGrid.BackgroundTransparency = 1
statsGrid.ZIndex = 12
statsGrid.Parent = card
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0, 205, 0, 28)
grid.CellPadding = UDim2.new(0, 12, 0, 8)
grid.FillDirectionMaxCells = 2
grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = statsGrid

local statLabels = {}
local function makeStat(order, key, caption)
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextSize = 16
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = Color3.fromRGB(210, 218, 232)
	l.ZIndex = 13
	l.Text = caption .. ": -"
	l.Parent = statsGrid
	statLabels[key] = { lbl = l, caption = caption }
end
-- Fill trái->phải: (Sống sót | Scrap tiêu) / (Địch hạ | Quân mất) / (Tàu Mẹ hạ | Gems)
makeStat(1, "survived", "Sống sót")
makeStat(2, "scrapSpent", "Scrap tiêu")
makeStat(3, "unitsKilled", "Địch hạ")
makeStat(4, "unitsLost", "Quân mất")
makeStat(5, "mothershipsKilled", "Tàu Mẹ hạ")
makeStat(6, "gems", "Gems")

local function setStat(key, text)
	local s = statLabels[key]
	if s then s.lbl.Text = s.caption .. ": " .. text end
end

-- Nút Chơi lại
local btnRow = Instance.new("Frame")
btnRow.LayoutOrder = 3
btnRow.Size = UDim2.new(1, 0, 0, 62)
btnRow.BackgroundTransparency = 1
btnRow.ZIndex = 12
btnRow.Parent = card
local brl = Instance.new("UIListLayout")
brl.FillDirection = Enum.FillDirection.Horizontal
brl.HorizontalAlignment = Enum.HorizontalAlignment.Center
brl.VerticalAlignment = Enum.VerticalAlignment.Center
brl.Padding = UDim.new(0, 12)
brl.Parent = btnRow

local function makeEndBtn(order, text, color, onClick)
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.new(0, 200, 1, 0)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBlack
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.TextScaled = true
	b.Text = text
	b.ZIndex = 12
	local cap = Instance.new("UITextSizeConstraint"); cap.MaxTextSize = 24; cap.Parent = b
	local cor = Instance.new("UICorner"); cor.CornerRadius = UDim.new(0, 14); cor.Parent = b
	b.Parent = btnRow
	b.Activated:Connect(function()
		overlay.Visible = false
		onClick()
	end)
	return b
end
makeEndBtn(1, "⟳ Chơi lại", Color3.fromRGB(60, 180, 90), function() Remotes.Restart:FireServer() end)
makeEndBtn(2, "⌂ Lobby", Color3.fromRGB(70, 120, 220), function() Remotes.ToLobby:FireServer() end)

local function fmtTime(sec)
	sec = math.max(0, math.floor(sec or 0))
	return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

Remotes.GameOver.OnClientEvent:Connect(function(payload)
	-- Tương thích cả payload cũ (string) lẫn mới (table)
	local result, killer, stats
	if type(payload) == "table" then
		result, killer, stats = payload.result, payload.killer, payload.stats
	else
		result = payload
	end
	stats = stats or {}

	if result == "victory" then
		titleL.Text = "CHIẾN THẮNG!"
		titleL.TextColor3 = Color3.fromRGB(120, 255, 140)
	else
		titleL.Text = killer and (killer .. " đã tiêu diệt bạn") or "TÀU MẸ BỊ HẠ"
		titleL.TextColor3 = Color3.fromRGB(255, 110, 110)
	end

	setStat("survived", fmtTime(stats.survived))
	setStat("scrapSpent", tostring(stats.scrapSpent or 0))
	setStat("unitsKilled", tostring(stats.unitsKilled or 0))
	setStat("unitsLost", tostring(stats.unitsLost or 0))
	setStat("mothershipsKilled", tostring(stats.mothershipsKilled or 0))
	setStat("gems", tostring(stats.gems or 0) .. " 💎")

	overlay.Visible = true
end)

-------------------------------------------------------------------------------
-- Ẩn/hiện HUD theo trạng thái trận (lobby: ẩn, playing: hiện)
-------------------------------------------------------------------------------
Remotes.MatchState.OnClientEvent:Connect(function(s)
	if s == "playing" then
		overlay.Visible = false -- vào trận mới -> tắt bảng kết thúc còn sót
		gui.Enabled = true
	else
		gui.Enabled = false
	end
end)
