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
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

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
	lbl.Position = UDim2.new(1, -14, 1, posY)
	lbl.Size = UDim2.new(0, 168, 0, 30)
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

-- Xếp phía TRÊN minimap (minimap 132 + đáy 12 ~ chiếm 144px dưới-phải).
local scrapLabel = makeCounter("Scrap", -190, Color3.fromRGB(255, 220, 120))
local fleetLabel = makeCounter("Fleet", -156, Color3.fromRGB(180, 220, 255))
local gemLabel = makeCounter("Gem", -224, Color3.fromRGB(200, 150, 255))
gemLabel.Text = "Gem: 0 ✦"
Remotes.GemUpdate.OnClientEvent:Connect(function(g)
	gemLabel.Text = ("Gem: %d ✦"):format(g)
end)

-------------------------------------------------------------------------------
-- Hotbar (dưới, giữa)
-------------------------------------------------------------------------------
local bar = Instance.new("Frame")
bar.Name = "Hotbar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -10)
bar.Size = UDim2.new(0, 13 * 61, 0, 52)
bar.BackgroundTransparency = 1
bar.Parent = gui
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 4)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = bar

-- Định nghĩa các nút. kind = "build" | "buy".
local BUY = Config.UNITS
local buttons = {}
local defs = {
	{ key = "ScrapMine",     kind = "build", label = "Mine",      hotkey = "Q", cost = Config.ECONOMY.SCRAP_MINE[1].cost, weight = 0 },
	{ key = "DroneHub",      kind = "build", label = "House",     hotkey = "R", cost = Config.ECONOMY.DRONE_HUB[1].cost,  weight = 0 },
	{ key = "LaserSat",      kind = "build", label = "LaserSat",  hotkey = "T", cost = Config.ECONOMY.LASER_SAT[1].cost,  weight = 0 },
	{ key = "PlasmaSat",     kind = "build", label = "PlasmaSat", hotkey = "Y", cost = Config.ECONOMY.PLASMA_SAT[1].cost, weight = 0 },
	{ key = "Drone",         kind = "buy",   label = "Drone",     hotkey = "1", cost = BUY.Drone.cost,         weight = BUY.Drone.weight },
	{ key = "Frigate",       kind = "buy",   label = "Frigate",   hotkey = "2", cost = BUY.Frigate.cost,       weight = BUY.Frigate.weight },
	{ key = "Destroyer",     kind = "buy",   label = "Destroyer", hotkey = "3", cost = BUY.Destroyer.cost,     weight = BUY.Destroyer.weight },
	{ key = "PlasmaCruiser", kind = "buy",   label = "Plasma",    hotkey = "4", cost = BUY.PlasmaCruiser.cost, weight = BUY.PlasmaCruiser.weight },
	{ key = "Interceptor",   kind = "buy",   label = "Intercept", hotkey = "5", cost = BUY.Interceptor.cost,  weight = BUY.Interceptor.weight },
	{ key = "Battleship",    kind = "buy",   label = "Battlesh",  hotkey = "6", cost = BUY.Battleship.cost,    weight = BUY.Battleship.weight },
	{ key = "SiegeRailgun",  kind = "buy",   label = "Siege",     hotkey = "7", cost = BUY.SiegeRailgun.cost,  weight = BUY.SiegeRailgun.weight },
	{ key = "Titan",         kind = "buy",   label = "Titan",     hotkey = "8", cost = BUY.Titan.cost,         weight = BUY.Titan.weight },
	{ key = "Kamikaze",      kind = "buy",   label = "Kamikaze",  hotkey = "9", cost = BUY.Kamikaze.cost,      weight = BUY.Kamikaze.weight },
}

-- Mô tả ngắn cách hoạt động (hiện khi hover nút).
local UDESC = {
	Drone = "Rẻ, đông. Bia đỡ đạn vòng ngoài, che pháo.",
	Frigate = "Bắn xa, xương sống DPS. Melt tank từ xa.",
	Destroyer = "Tank trâu, chắn vòng giữa, mua thời gian.",
	PlasmaCruiser = "Nổ AoE quanh mục tiêu — khắc swarm.",
	Interceptor = "Nhanh nhất, ưu tiên xé pháo địch (backline).",
	Battleship = "Flagship: trâu + bắn 3 mục tiêu cùng lúc.",
	SiegeRailgun = "CHỈ phá công trình, tầm cực xa, nạp đạn chậm.",
	Titan = "Sóng xung: STUN + đẩy lệch đội hình địch.",
	Kamikaze = "Lao vào Tàu Mẹ/fleet địch rồi tự nổ AoE.",
}
local BDESC = {
	ScrapMine = "Đặt trên mỏ → +scrap mỗi giây.",
	DroneHub = "Nhà: +giới hạn quân (population).",
	LaserSat = "Tháp phòng thủ bắn 1 mục tiêu.",
	PlasmaSat = "Tháp phòng thủ bắn AoE.",
}

local tip = Instance.new("Frame")
tip.Name = "Tooltip"
tip.AnchorPoint = Vector2.new(0.5, 1)
tip.Size = UDim2.new(0, 236, 0, 96)
tip.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
tip.BackgroundTransparency = 0.05
tip.Visible = false
tip.ZIndex = 20
local tipc = Instance.new("UICorner"); tipc.CornerRadius = UDim.new(0, 8); tipc.Parent = tip
local tipPad = Instance.new("UIPadding")
tipPad.PaddingTop = UDim.new(0, 8); tipPad.PaddingBottom = UDim.new(0, 8)
tipPad.PaddingLeft = UDim.new(0, 10); tipPad.PaddingRight = UDim.new(0, 10); tipPad.Parent = tip
local tipTxt = Instance.new("TextLabel")
tipTxt.Size = UDim2.fromScale(1, 1); tipTxt.BackgroundTransparency = 1
tipTxt.Font = Enum.Font.GothamMedium; tipTxt.TextSize = 14
tipTxt.TextColor3 = Color3.fromRGB(235, 240, 250); tipTxt.TextWrapped = true
tipTxt.TextXAlignment = Enum.TextXAlignment.Left; tipTxt.TextYAlignment = Enum.TextYAlignment.Top
tipTxt.RichText = true; tipTxt.ZIndex = 21; tipTxt.Text = ""; tipTxt.Parent = tip
tip.Parent = gui

local function showTip(def, btn)
	local body
	if def.kind == "buy" then
		local u = Config.UNITS[def.key]
		body = ("<b>%s</b>  <font color='#ffd86e'>%d ◈</font>\nPop %d · HP %d · Dmg %d · Tầm %d%s\n<font color='#a8b4c8'>%s</font>"):format(
			u.displayName, u.cost, u.weight, u.hp, u.dmg, u.range,
			(u.aoeRadius or 0) > 0 and (" · AoE " .. u.aoeRadius) or "",
			UDESC[def.key] or "")
	else
		body = ("<b>%s</b>  <font color='#ffd86e'>%d ◈</font>\n<font color='#a8b4c8'>%s</font>"):format(
			def.label, def.cost, BDESC[def.key] or "")
	end
	tipTxt.Text = body
	tip.Position = UDim2.fromOffset(btn.AbsolutePosition.X + btn.AbsoluteSize.X / 2, btn.AbsolutePosition.Y - 6)
	tip.Visible = true
end

for i, def in ipairs(defs) do
	local btn = Instance.new("TextButton")
	btn.Name = def.key
	btn.LayoutOrder = i
	btn.Size = UDim2.new(0, 57, 1, 0)
	btn.BackgroundColor3 = (def.kind == "build") and Color3.fromRGB(70, 90, 120) or Color3.fromRGB(50, 70, 60)
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBold
	btn.TextColor3 = Color3.fromRGB(240, 240, 240)
	btn.TextSize = 11
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

	btn.MouseEnter:Connect(function() showTip(def, btn) end)
	btn.MouseLeave:Connect(function() tip.Visible = false end)

	buttons[i] = { def = def, btn = btn }
end

-- (Layout cảm ứng mobile dựng ở cuối file — cụm Ability/Split/Shop + shop drawer.)

-- Các hàm cập nhật thêm (mobile layout đăng ký vào đây; gọi mỗi lần refresh).
local extraRefresh = {}

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
	for _, fn in ipairs(extraRefresh) do fn() end
end

Remotes.ScrapUpdate.OnClientEvent:Connect(function(scrap)
	state.scrap = scrap
	refreshButtons()
end)

-- Giá leo thang: server gửi giá hiện tại -> cập nhật nhãn + ngưỡng mua của nút.
Remotes.PricesUpdate.OnClientEvent:Connect(function(units, builds)
	for _, entry in ipairs(buttons) do
		local def = entry.def
		local cost = (def.kind == "build") and builds[def.key] or units[def.key]
		if cost then
			def.cost = cost
			entry.btn.Text = ("%s\n%d ◈\n[%s]"):format(def.label, cost, def.hotkey)
		end
	end
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
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -66)
hint.Size = UDim2.new(0, 720, 0, 16)
hint.BackgroundTransparency = 1
hint.TextColor3 = Color3.fromRGB(180, 185, 200)
hint.TextXAlignment = Enum.TextXAlignment.Center
hint.Font = Enum.Font.Gotham
hint.TextSize = 12
hint.Text = "1-4: mua quân | Q: Mine (trên mỏ) | R: Hub | click map để đặt | click building: nâng cấp | chuột phải: huỷ | SPACE: Split"
hint.Parent = gui

-------------------------------------------------------------------------------
-- Nút Về Lobby (trong trận) — góc trên-trái, cạnh nút ⚙
-------------------------------------------------------------------------------
local backBtn = Instance.new("TextButton")
backBtn.Name = "BackToLobby"
backBtn.Position = UserInputService.TouchEnabled and UDim2.new(0, 104, 0, 76) or UDim2.new(0, 58, 0, 52) -- mobile: cạnh ⚙, dưới Unibar
backBtn.Size = UDim2.new(0, 104, 0, 34)
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
-- Panel chọn building: click building của mình -> Nâng cấp / Bán
-------------------------------------------------------------------------------
local B_NAME = {
	ScrapMine = "Gold Mine", DroneHub = "House",
	LaserSat = "Laser Satellite", PlasmaSat = "Plasma Satellite",
}
local ECOKEY = {
	ScrapMine = "SCRAP_MINE", DroneHub = "DRONE_HUB",
	LaserSat = "LASER_SAT", PlasmaSat = "PLASMA_SAT",
}
local selectedPart = nil

-- Popup NEO Ở NHÀ (chiếu vị trí world -> màn hình mỗi frame). Sell trên, Upgrade dưới.
local pop = Instance.new("Frame")
pop.Name = "BuildingUI"
pop.AnchorPoint = Vector2.new(0.5, 0.5)
pop.Size = UDim2.new(0, 260, 0, 200)
pop.BackgroundTransparency = 1
pop.Visible = false
pop.Parent = gui

-- Nút Sell (phía trên nhà)
local sellBtn = Instance.new("TextButton")
sellBtn.AnchorPoint = Vector2.new(0.5, 0)
sellBtn.Position = UDim2.new(0.5, 0, 0, 0); sellBtn.Size = UDim2.new(0, 200, 0, 42)
sellBtn.BackgroundColor3 = Color3.fromRGB(225, 70, 70)
sellBtn.Font = Enum.Font.GothamBlack; sellBtn.TextSize = 22
sellBtn.TextColor3 = Color3.fromRGB(255, 255, 255); sellBtn.Text = "Sell"
local sc2 = Instance.new("UICorner"); sc2.CornerRadius = UDim.new(0, 10); sc2.Parent = sellBtn
sellBtn.Parent = pop

-- Khối Upgrade (phía dưới nhà): "Next level +X" + nút Upgrade cost
local ubox = Instance.new("Frame")
ubox.AnchorPoint = Vector2.new(0.5, 1)
ubox.Position = UDim2.new(0.5, 0, 1, 0); ubox.Size = UDim2.new(0, 240, 0, 78)
ubox.BackgroundColor3 = Color3.fromRGB(20, 40, 28); ubox.BackgroundTransparency = 0.1
local uc = Instance.new("UICorner"); uc.CornerRadius = UDim.new(0, 10); uc.Parent = ubox
ubox.Parent = pop

local nextLbl = Instance.new("TextLabel")
nextLbl.Position = UDim2.new(0, 10, 0, 6); nextLbl.Size = UDim2.new(1, -20, 0, 24)
nextLbl.BackgroundTransparency = 1; nextLbl.Font = Enum.Font.GothamBold; nextLbl.TextSize = 15
nextLbl.TextColor3 = Color3.fromRGB(220, 235, 210); nextLbl.TextXAlignment = Enum.TextXAlignment.Left
nextLbl.Text = ""; nextLbl.Parent = ubox

local upBtn = Instance.new("TextButton")
upBtn.AnchorPoint = Vector2.new(0.5, 1)
upBtn.Position = UDim2.new(0.5, 0, 1, -6); upBtn.Size = UDim2.new(1, -16, 0, 40)
upBtn.BackgroundColor3 = Color3.fromRGB(70, 120, 230)
upBtn.Font = Enum.Font.GothamBlack; upBtn.TextSize = 18
upBtn.TextColor3 = Color3.fromRGB(255, 255, 255); upBtn.Text = "Upgrade"
local upc = Instance.new("UICorner"); upc.CornerRadius = UDim.new(0, 8); upc.Parent = upBtn
upBtn.Parent = ubox

local function closeUI()
	pop.Visible = false
	selectedPart = nil
	player:SetAttribute("BuildingUIOpen", false)
end

sellBtn.Activated:Connect(function()
	if selectedPart and selectedPart.Parent then Remotes.SellBuilding:FireServer(selectedPart) end
	closeUI()
end)
upBtn.Activated:Connect(function()
	if selectedPart and selectedPart.Parent then Remotes.UpgradeBuilding:FireServer(selectedPart) end
end)

-- Cập nhật nội dung "Next level" theo tier hiện tại (đọc attribute Tier từ part).
local function refreshUpgradeInfo(part)
	local cfg = Config.ECONOMY[ECOKEY[part.Name] or ""]
	local tier = part:GetAttribute("Tier") or 1
	local nxt = cfg and cfg[tier + 1]
	if nxt then
		upBtn.Visible = true
		upBtn.Text = ("Upgrade   %d ◈"):format(nxt.cost)
		local cur = cfg[tier]
		local delta = ""
		if part.Name == "ScrapMine" then
			delta = ("+%d income"):format((nxt.income or 0) - (cur.income or 0))
		elseif part.Name == "DroneHub" then
			delta = ("+%d pop"):format((nxt.cap or 0) - (cur.cap or 0))
		else
			delta = ("+%d%% dmg"):format(math.floor(((nxt.dmgMult or 1) - (cur.dmgMult or 1)) * 100 + 0.5))
		end
		nextLbl.Text = "Next level:  " .. delta
	else
		upBtn.Visible = false
		nextLbl.Text = "MAX LEVEL"
	end
end

ClientBus.selectBuilding.Event:Connect(function(part)
	selectedPart = part
	if part then
		refreshUpgradeInfo(part)
		pop.Visible = true
		player:SetAttribute("BuildingUIOpen", true) -- Tàu Mẹ đứng yên
	else
		closeUI()
	end
end)

-- Mỗi frame: neo popup lên vị trí nhà + tự đóng nếu nhà mất; cập nhật giá nâng cấp.
RunService.RenderStepped:Connect(function()
	if not selectedPart then return end
	if not selectedPart.Parent then closeUI(); return end
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local vp, onScreen = cam:WorldToViewportPoint(selectedPart.Position)
	pop.Visible = onScreen
	if onScreen then
		pop.Position = UDim2.fromOffset(vp.X, vp.Y)
		refreshUpgradeInfo(selectedPart)
	end
end)

-------------------------------------------------------------------------------
-- LAYOUT CẢM ỨNG (mobile): resource strip trên-trái · rank chip trên-phải ·
-- shop drawer giữa-dưới (tab Quân/Nhà, cuộn ngang) · cụm Ability/Split/Shop dưới-phải.
-- Joystick (di chuyển) do InputController lo (góc dưới-trái). Chỉ bật khi TouchEnabled.
-------------------------------------------------------------------------------
if UserInputService.TouchEnabled then
	-- Ẩn các thành phần layout PC
	bar.Visible = false
	hint.Visible = false
	scrapLabel.Visible = false; fleetLabel.Visible = false; gemLabel.Visible = false
	lb.Visible = false -- bảng xếp hạng đầy đủ -> thay bằng rank chip gọn

	local PANEL = Color3.fromRGB(18, 24, 40)
	local STROKE = Color3.fromRGB(57, 80, 122)
	local function pill(parent, w)
		local f = Instance.new("Frame")
		f.Size = UDim2.new(0, w, 0, 30); f.BackgroundColor3 = PANEL; f.BackgroundTransparency = 0.08
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 15); c.Parent = f
		local s = Instance.new("UIStroke"); s.Color = STROKE; s.Transparency = 0.3; s.Parent = f
		f.Parent = parent
		return f
	end

	-- ===== TOP-LEFT: resource strip (Scrap · Gem · Fleet cap) =====
	local strip = Instance.new("Frame")
	strip.Position = UDim2.new(0, 58, 0, 8); strip.Size = UDim2.new(0, 300, 0, 30)
	strip.BackgroundTransparency = 1; strip.Parent = gui
	local sl = Instance.new("UIListLayout")
	sl.FillDirection = Enum.FillDirection.Horizontal; sl.Padding = UDim.new(0, 6)
	sl.VerticalAlignment = Enum.VerticalAlignment.Center; sl.Parent = strip

	local scrapPill = pill(strip, 96); scrapPill.LayoutOrder = 1
	local mScrap = Instance.new("TextLabel")
	mScrap.Size = UDim2.fromScale(1, 1); mScrap.BackgroundTransparency = 1; mScrap.Font = Enum.Font.GothamBold
	mScrap.TextSize = 14; mScrap.TextColor3 = Color3.fromRGB(255, 210, 100); mScrap.Text = "◈ 0"; mScrap.Parent = scrapPill

	local gemPill = pill(strip, 84); gemPill.LayoutOrder = 2
	local mGem = Instance.new("TextLabel")
	mGem.Size = UDim2.fromScale(1, 1); mGem.BackgroundTransparency = 1; mGem.Font = Enum.Font.GothamBold
	mGem.TextSize = 14; mGem.TextColor3 = Color3.fromRGB(200, 150, 255); mGem.Text = "◆ 0"; mGem.Parent = gemPill

	local fleetPill = pill(strip, 110); fleetPill.LayoutOrder = 3
	local fBar = Instance.new("Frame")
	fBar.AnchorPoint = Vector2.new(0, 0.5); fBar.Position = UDim2.new(0, 8, 0.5, 0); fBar.Size = UDim2.new(0, 56, 0, 8)
	fBar.BackgroundColor3 = Color3.fromRGB(43, 58, 92); fBar.Parent = fleetPill
	local fbc = Instance.new("UICorner"); fbc.CornerRadius = UDim.new(1, 0); fbc.Parent = fBar
	local fFill = Instance.new("Frame")
	fFill.Size = UDim2.new(0, 0, 1, 0); fFill.BackgroundColor3 = Color3.fromRGB(102, 211, 138); fFill.Parent = fBar
	local ffc = Instance.new("UICorner"); ffc.CornerRadius = UDim.new(1, 0); ffc.Parent = fFill
	local fTxt = Instance.new("TextLabel")
	fTxt.AnchorPoint = Vector2.new(1, 0.5); fTxt.Position = UDim2.new(1, -8, 0.5, 0); fTxt.Size = UDim2.new(0, 42, 1, 0)
	fTxt.BackgroundTransparency = 1; fTxt.Font = Enum.Font.GothamBold; fTxt.TextSize = 11
	fTxt.TextColor3 = Color3.fromRGB(207, 227, 255); fTxt.TextXAlignment = Enum.TextXAlignment.Right; fTxt.Text = "0/0"; fTxt.Parent = fleetPill

	local mGemVal = 0
	Remotes.GemUpdate.OnClientEvent:Connect(function(g) mGemVal = g; mGem.Text = "◆ " .. tostring(g) end)

	-- ===== TOP-RIGHT: rank chip (dưới minimap) =====
	local rankChip = pill(gui, 116)
	rankChip.AnchorPoint = Vector2.new(1, 0); rankChip.Position = UDim2.new(1, -12, 0, 152)
	local rankTxt = Instance.new("TextLabel")
	rankTxt.Size = UDim2.fromScale(1, 1); rankTxt.BackgroundTransparency = 1; rankTxt.Font = Enum.Font.GothamBold
	rankTxt.TextSize = 13; rankTxt.TextColor3 = Color3.fromRGB(255, 210, 100); rankTxt.Text = "#? · –"; rankTxt.Parent = rankChip
	Remotes.Leaderboard.OnClientEvent:Connect(function(list)
		for i, e in ipairs(list) do
			if e.id == player.UserId then rankTxt.Text = ("#%d · %d"):format(i, e.score); break end
		end
	end)

	-- ===== SHOP DRAWER (giữa-dưới) — tab Quân/Nhà + cuộn ngang =====
	local drawer = Instance.new("Frame")
	drawer.AnchorPoint = Vector2.new(0.5, 1); drawer.Position = UDim2.new(0.5, 0, 1, -14)
	drawer.Size = UDim2.new(0, 360, 0, 118); drawer.BackgroundColor3 = Color3.fromRGB(14, 23, 48)
	drawer.BackgroundTransparency = 0.05; drawer.Visible = false; drawer.ZIndex = 6; drawer.Parent = gui
	local dcc = Instance.new("UICorner"); dcc.CornerRadius = UDim.new(0, 14); dcc.Parent = drawer
	local dcs = Instance.new("UIStroke"); dcs.Color = STROKE; dcs.Transparency = 0.3; dcs.Parent = drawer

	local tabRow = Instance.new("Frame")
	tabRow.Position = UDim2.new(0, 10, 0, 8); tabRow.Size = UDim2.new(1, -20, 0, 24)
	tabRow.BackgroundTransparency = 1; tabRow.ZIndex = 7; tabRow.Parent = drawer
	local trl = Instance.new("UIListLayout"); trl.FillDirection = Enum.FillDirection.Horizontal
	trl.Padding = UDim.new(0, 6); trl.Parent = tabRow

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.new(0, 10, 0, 40); scroll.Size = UDim2.new(1, -20, 0, 68)
	scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.ScrollBarThickness = 4; scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.X; scroll.ZIndex = 7; scroll.Parent = drawer
	local scl = Instance.new("UIListLayout"); scl.FillDirection = Enum.FillDirection.Horizontal
	scl.Padding = UDim.new(0, 6); scl.SortOrder = Enum.SortOrder.LayoutOrder; scl.Parent = scroll

	local activeTab = "buy"
	local mShopBtns = {}
	local function closeDrawer() drawer.Visible = false end

	local function renderShop()
		for _, e in ipairs(mShopBtns) do e.btn:Destroy() end
		table.clear(mShopBtns)
		local order = 0
		for _, def in ipairs(defs) do
			if def.kind == activeTab then
				order += 1
				local b = Instance.new("TextButton")
				b.LayoutOrder = order; b.Size = UDim2.new(0, 62, 1, 0)
				b.BackgroundColor3 = (def.kind == "build") and Color3.fromRGB(70, 90, 120) or Color3.fromRGB(50, 70, 60)
				b.Font = Enum.Font.GothamBold; b.TextSize = 11; b.TextColor3 = Color3.fromRGB(240, 240, 240)
				b.Text = ("%s\n%d ◈"):format(def.label, def.cost); b.ZIndex = 8; b.Parent = scroll
				local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
				b.Activated:Connect(function()
					if def.kind == "build" then
						ClientBus.enterBuild:Fire(def.key); closeDrawer()
					else
						Remotes.SpawnUnit:FireServer(def.key)
					end
				end)
				table.insert(mShopBtns, { def = def, btn = b })
			end
		end
		refreshButtons() -- áp trạng thái đủ/thiếu ngay
	end

	local tabBtns = {}
	local function setTab(k)
		activeTab = k
		for kk, tb in pairs(tabBtns) do
			tb.BackgroundColor3 = (kk == k) and Color3.fromRGB(90, 46, 166) or Color3.fromRGB(34, 49, 79)
		end
		renderShop()
	end
	for _, t in ipairs({ { k = "buy", label = "Quân" }, { k = "build", label = "Nhà" } }) do
		local tb = Instance.new("TextButton")
		tb.Size = UDim2.new(0, 70, 1, 0); tb.Font = Enum.Font.GothamBold; tb.TextSize = 12
		tb.TextColor3 = Color3.fromRGB(235, 240, 250); tb.Text = t.label; tb.ZIndex = 8; tb.Parent = tabRow
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = tb
		tabBtns[t.k] = tb
		tb.Activated:Connect(function() setTab(t.k) end)
	end

	-- ===== CỤM HÀNH ĐỘNG (dưới-phải): Ability (lớn) · Split · Shop =====
	local ability = Instance.new("TextButton")
	ability.AnchorPoint = Vector2.new(1, 1); ability.Position = UDim2.new(1, -16, 1, -16)
	ability.Size = UDim2.new(0, 92, 0, 92); ability.BackgroundColor3 = Color3.fromRGB(90, 46, 166)
	ability.Font = Enum.Font.GothamBold; ability.TextSize = 13; ability.TextColor3 = Color3.fromRGB(255, 255, 255)
	ability.Text = "SPAWN"; ability.TextSize = 16; ability.ZIndex = 6; ability.Parent = gui
	local abc = Instance.new("UICorner"); abc.CornerRadius = UDim.new(1, 0); abc.Parent = ability
	local abs = Instance.new("UIStroke"); abs.Color = Color3.fromRGB(185, 140, 255); abs.Thickness = 2; abs.Parent = ability
	-- SPAWN = mở/đóng drawer triệu hồi quân + công trình.
	ability.Activated:Connect(function()
		drawer.Visible = not drawer.Visible
		if drawer.Visible then setTab(activeTab) end
	end)

	local function smallAction(x, y, label, color)
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(1, 1); b.Position = UDim2.new(1, x, 1, y); b.Size = UDim2.new(0, 56, 0, 56)
		b.BackgroundColor3 = color; b.Font = Enum.Font.GothamBold; b.TextSize = 12
		b.TextColor3 = Color3.fromRGB(235, 242, 255); b.Text = label; b.ZIndex = 6; b.Parent = gui
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = b
		local s = Instance.new("UIStroke"); s.Color = STROKE; s.Transparency = 0.2; s.Parent = b
		return b
	end
	-- Split (giữ để tách bầy) — bên trái Spawn
	local splitBtn = smallAction(-116, -46, "Split", Color3.fromRGB(30, 42, 68))
	splitBtn.MouseButton1Down:Connect(function() Remotes.SplitInput:FireServer(true) end)
	splitBtn.MouseButton1Up:Connect(function() Remotes.SplitInput:FireServer(false) end)

	-- Cancel xây (chỉ hiện khi đang ở chế độ đặt building)
	local cancelBtn = smallAction(-116, -108, "✕ Huỷ", Color3.fromRGB(120, 46, 52))
	cancelBtn.Visible = false
	cancelBtn.Activated:Connect(function()
		ClientBus.cancelBuild:Fire(); Remotes.CancelBuild:FireServer(); cancelBtn.Visible = false
	end)
	ClientBus.enterBuild.Event:Connect(function() cancelBtn.Visible = true end)
	ClientBus.cancelBuild.Event:Connect(function() cancelBtn.Visible = false end)

	-- Cập nhật resource strip + trạng thái nút shop mỗi lần refresh.
	table.insert(extraRefresh, function()
		mScrap.Text = "◈ " .. tostring(state.scrap)
		local ratio = state.max > 0 and math.clamp(state.used / state.max, 0, 1) or 0
		fFill.Size = UDim2.new(ratio, 0, 1, 0)
		fFill.BackgroundColor3 = (state.used >= state.max) and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(102, 211, 138)
		fTxt.Text = ("%d/%d"):format(state.used, state.max)
		for _, e in ipairs(mShopBtns) do
			local def = e.def
			local ok = state.scrap >= def.cost
			if def.kind == "buy" and (state.used + def.weight) > state.max then ok = false end
			e.btn.AutoButtonColor = ok
			e.btn.TextTransparency = ok and 0 or 0.45
			e.btn.BackgroundTransparency = ok and 0 or 0.5
			e.btn.Text = ("%s\n%d ◈"):format(def.label, def.cost)
		end
	end)

	setTab("buy")
	refreshButtons()
end

-------------------------------------------------------------------------------
-- Ẩn/hiện HUD theo trạng thái trận (lobby: ẩn, playing: hiện)
-------------------------------------------------------------------------------
Remotes.MatchState.OnClientEvent:Connect(function(s)
	closeUI() -- đóng popup nhà + nhả cờ đứng yên
	if s == "playing" then
		overlay.Visible = false -- vào trận mới -> tắt bảng kết thúc còn sót
		gui.Enabled = true
	else
		gui.Enabled = false
	end
end)
