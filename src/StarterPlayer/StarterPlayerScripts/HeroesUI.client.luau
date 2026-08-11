--[[
	HeroesUI.client.luau  ->  MOTHERSHIP INDEX
	------------------------------------------
	Bách khoa toàn thư trong game, mở bằng nút "📖 Index" (góc trên-trái).
	3 tab:
	  • Quân        : 9 loại unit — chỉ số + vai trò.
	  • Công trình  : Mine / House / LaserSat / PlasmaSat — cost + tác dụng.
	  • Tàu Mẹ      : 9 class — passive + độ hiếm; con SỞ HỮU có nút "Lái".

	Gacha (mở hòm roll Tàu Mẹ) KHÔNG ở đây nữa — nó nằm ở zone "TÀU MẸ" trong sảnh.
	Chọn Tàu Mẹ để lái vẫn làm ở tab "Tàu Mẹ" (nút Lái) trên các con đã sở hữu.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local ClientBus = require(script.Parent.ClientBus)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GOLD = Color3.fromRGB(255, 210, 90)
local PANEL_BG = Color3.fromRGB(22, 26, 38)
local CARD_BG = Color3.fromRGB(32, 38, 54)
local CARD_SEL = Color3.fromRGB(44, 58, 44)
local CAT_COLOR = {
	Vanguard  = Color3.fromRGB(90, 200, 255),
	Guard     = Color3.fromRGB(120, 230, 140),
	Artillery = Color3.fromRGB(255, 170, 90),
}

-- Fallback: luôn coi như đã sở hữu con mặc định (phòng khi lỡ event HeroState lúc join).
local selectedHeroId = Config.DEFAULT_HERO
local ownedSet = { [Config.DEFAULT_HERO] = true }
local TABS = { "Quân", "Công trình", "Tàu Mẹ" }
local activeTab = "Quân"
local myShipMode = false -- true: chỉ hiện Tàu Mẹ đã sở hữu + Equip (mở từ nút My Ship)

-- Vai trò ngắn của từng unit (hiển thị trong Index).
local UNIT_ORDER = { "Drone", "Frigate", "Destroyer", "PlasmaCruiser", "Interceptor", "Battleship", "SiegeRailgun", "Titan", "Kamikaze" }
local UNIT_ROLE = {
	Drone = "Rẻ & đông. Bia đỡ đạn vòng ngoài, che pháo.",
	Frigate = "Bắn xa, xương sống DPS. Melt tank từ xa.",
	Destroyer = "Tank trâu, chắn vòng giữa, câu giờ.",
	PlasmaCruiser = "Nổ AoE quanh mục tiêu — khắc swarm.",
	Interceptor = "Nhanh nhất, ưu tiên xé pháo địch (backline).",
	Battleship = "Flagship: trâu + bắn 3 mục tiêu cùng lúc.",
	SiegeRailgun = "CHỈ phá công trình, tầm cực xa, nạp đạn chậm.",
	Titan = "Sóng xung: STUN + đẩy lệch đội hình địch.",
	Kamikaze = "Lao vào Tàu Mẹ/fleet địch rồi tự nổ AoE.",
}

-------------------------------------------------------------------------------
-- GUI
-------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "IndexUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 9
gui.Parent = playerGui

-- Nút mở Index (góc trên-trái, dưới hàng ⚙/Lobby)
local openBtn = Instance.new("TextButton")
openBtn.Name = "IndexButton"
openBtn.Position = UDim2.new(0, 12, 0, 94)
openBtn.Size = UDim2.new(0, 104, 0, 34)
openBtn.BackgroundColor3 = Color3.fromRGB(48, 54, 74)
openBtn.Font = Enum.Font.GothamBold
openBtn.TextSize = 15
openBtn.TextColor3 = GOLD
openBtn.Text = "📖 Index"
local obc = Instance.new("UICorner"); obc.CornerRadius = UDim.new(0, 8); obc.Parent = openBtn
openBtn.Visible = false -- ở sảnh dùng nút sidebar; nút này chỉ hiện trong TRẬN
openBtn.Parent = gui

local dim = Instance.new("TextButton")
dim.Size = UDim2.new(1, 0, 1, 0); dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.45; dim.Text = ""; dim.AutoButtonColor = false
dim.Visible = false; dim.ZIndex = 20; dim.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 600, 0, 460)
panel.BackgroundColor3 = PANEL_BG; panel.Visible = false; panel.ZIndex = 21; panel.Parent = gui
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 18); pc.Parent = panel
local ps = Instance.new("UIStroke"); ps.Thickness = 2; ps.Color = GOLD; ps.Transparency = 0.4; ps.Parent = panel

local title = Instance.new("TextLabel")
title.Position = UDim2.new(0, 0, 0, 14); title.Size = UDim2.new(1, 0, 0, 32)
title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBlack; title.TextSize = 24
title.Text = "📖 MOTHERSHIP INDEX"; title.TextColor3 = GOLD; title.ZIndex = 22; title.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0); closeBtn.Position = UDim2.new(1, -12, 0, 12)
closeBtn.Size = UDim2.new(0, 30, 0, 30); closeBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 44)
closeBtn.Text = "✕"; closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 16
closeBtn.TextColor3 = Color3.fromRGB(255, 200, 200); closeBtn.ZIndex = 23; closeBtn.Parent = panel
local cbc = Instance.new("UICorner"); cbc.CornerRadius = UDim.new(0, 8); cbc.Parent = closeBtn

local tabRow = Instance.new("Frame")
tabRow.Position = UDim2.new(0, 16, 0, 54); tabRow.Size = UDim2.new(1, -32, 0, 34)
tabRow.BackgroundTransparency = 1; tabRow.ZIndex = 22; tabRow.Parent = panel
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal; tabLayout.Padding = UDim.new(0, 8)
tabLayout.Parent = tabRow

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.new(0, 16, 0, 98); list.Size = UDim2.new(1, -32, 1, -114)
list.BackgroundTransparency = 1; list.BorderSizePixel = 0; list.ScrollBarThickness = 5
list.CanvasSize = UDim2.new(0, 0, 0, 0); list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ZIndex = 22; list.Parent = panel
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8); listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

-------------------------------------------------------------------------------
-- Card builder chung
-------------------------------------------------------------------------------
local function baseCard(order, swatchColor, height)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, height or 84); card.LayoutOrder = order
	card.BackgroundColor3 = CARD_BG; card.ZIndex = 22; card.Parent = list
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 12); cc.Parent = card
	local sw = Instance.new("Frame")
	sw.Position = UDim2.new(0, 12, 0, 12); sw.Size = UDim2.new(0, 20, 1, -24)
	sw.BackgroundColor3 = swatchColor; sw.ZIndex = 23; sw.Parent = card
	local swc = Instance.new("UICorner"); swc.CornerRadius = UDim.new(0, 6); swc.Parent = sw
	return card
end

local function addLabel(card, x, y, w, h, text, color, size, bold, wrap)
	local l = Instance.new("TextLabel")
	l.Position = UDim2.new(0, x, 0, y); l.Size = UDim2.new(1, w, 0, h)
	l.BackgroundTransparency = 1; l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextSize = size; l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top; l.TextWrapped = wrap or false
	l.Text = text; l.TextColor3 = color; l.ZIndex = 23; l.Parent = card
	return l
end

local function clearList()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end -- xoá cả Frame lẫn TextLabel (giữ UIListLayout)
	end
end

-------------------------------------------------------------------------------
-- Render từng tab
-------------------------------------------------------------------------------
local function renderUnits()
	for i, key in ipairs(UNIT_ORDER) do
		local u = Config.UNITS[key]
		if u then
			local card = baseCard(i, Color3.fromRGB(120, 200, 255), 84)
			addLabel(card, 44, 8, -180, 22, u.displayName or key, Color3.fromRGB(210, 230, 255), 17, true)
			addLabel(card, 44, 30, -180, 16,
				("💰%d  ♥%d  ⚔%d  ⤢%d  ⚡%.1f  ⧗%d"):format(u.cost, u.hp, u.dmg, u.range, u.fireRate, u.weight),
				Color3.fromRGB(180, 190, 210), 12, false)
			addLabel(card, 44, 48, -180, 32, UNIT_ROLE[key] or "", Color3.fromRGB(175, 185, 205), 12, false, true)
		end
	end
end

local function renderBuildings()
	local E = Config.ECONOMY
	local defs = {
		{ name = "Scrap Mine", color = Color3.fromRGB(230, 180, 60), cost = E.SCRAP_MINE[1].cost,
		  eff = ("+%d scrap/giây · chỉ đặt TRÊN mỏ · tối đa %d"):format(E.SCRAP_MINE[1].income, E.SCRAP_MINE.MAX) },
		{ name = "House (Hub)", color = Color3.fromRGB(90, 190, 230), cost = E.DRONE_HUB[1].cost,
		  eff = ("+%d fleet cap · đất trống · tối đa %d"):format(E.DRONE_HUB[1].cap, E.DRONE_HUB.MAX) },
		{ name = "Laser Satellite", color = Color3.fromRGB(80, 220, 120), cost = E.LASER_SAT[1].cost,
		  eff = ("Tháp bắn ĐƠN mục tiêu · dmg %d, tầm %d · tối đa %d"):format(E.LASER_SAT.base.dmg, E.LASER_SAT.base.range, E.LASER_SAT.MAX) },
		{ name = "Plasma Satellite", color = Color3.fromRGB(210, 90, 230), cost = E.PLASMA_SAT[1].cost,
		  eff = ("Tháp AoE · dmg %d, tầm %d, AoE %d · tối đa %d"):format(E.PLASMA_SAT.base.dmg, E.PLASMA_SAT.base.range, E.PLASMA_SAT.base.aoe, E.PLASMA_SAT.MAX) },
	}
	for i, d in ipairs(defs) do
		local card = baseCard(i, d.color, 76)
		addLabel(card, 44, 10, -180, 22, d.name, Color3.fromRGB(220, 225, 240), 17, true)
		addLabel(card, 44, 32, -180, 16, ("Giá %d ◈"):format(d.cost), GOLD, 13, true)
		addLabel(card, 44, 50, -180, 20, d.eff, Color3.fromRGB(175, 185, 205), 12, false, true)
	end
end

local function selectHero(id)
	Remotes.SelectHero:FireServer(id)
end

local function renderMotherships()
	for i, hero in ipairs(Config.HEROES) do
		local owned = ownedSet[hero.id] == true
		local isSel = (hero.id == selectedHeroId)
		local rarCol = (Config.RARITY_COLOR and Config.RARITY_COLOR[hero.rarity]) or Color3.fromRGB(200, 200, 200)

		local card = baseCard(i, hero.color or Color3.new(1, 1, 1), 92)
		card.BackgroundColor3 = isSel and CARD_SEL or CARD_BG
		card.BackgroundTransparency = owned and 0 or 0.35

		addLabel(card, 44, 8, -180, 22, hero.name, CAT_COLOR[hero.cat] or Color3.new(1, 1, 1), 17, true)
		addLabel(card, 44, 30, -180, 16, string.upper(hero.rarity or "") .. " · " .. hero.cat, rarCol, 12, true)
		addLabel(card, 44, 48, -180, 38, hero.desc, Color3.fromRGB(185, 195, 212), 12, false, true)

		local btn = Instance.new("TextButton")
		btn.AnchorPoint = Vector2.new(1, 0.5); btn.Position = UDim2.new(1, -14, 0.5, 0)
		btn.Size = UDim2.new(0, 120, 0, 42); btn.Font = Enum.Font.GothamBold; btn.TextSize = 14
		btn.TextColor3 = Color3.new(1, 1, 1); btn.ZIndex = 23; btn.Parent = card
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = btn
		if not owned then
			btn.Text = "🔒 Mở ở Tàu Mẹ"; btn.BackgroundColor3 = Color3.fromRGB(58, 62, 76)
			btn.TextColor3 = Color3.fromRGB(170, 178, 195); btn.AutoButtonColor = false
		elseif isSel then
			btn.Text = "✓ Đang lái"; btn.BackgroundColor3 = Color3.fromRGB(70, 120, 70); btn.AutoButtonColor = false
		else
			btn.Text = "Lái"; btn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
			btn.Activated:Connect(function() selectHero(hero.id) end)
		end
	end
end

-- MY SHIP: CHỈ Tàu Mẹ đã sở hữu, nút Equip / trạng thái Đã Equip.
local function renderMyShip()
	local order = 0
	for _, hero in ipairs(Config.HEROES) do
		if ownedSet[hero.id] then
			order += 1
			local isSel = (hero.id == selectedHeroId)
			local rarCol = (Config.RARITY_COLOR and Config.RARITY_COLOR[hero.rarity]) or Color3.fromRGB(200, 200, 200)
			local card = baseCard(order, hero.color or Color3.new(1, 1, 1), 92)
			card.BackgroundColor3 = isSel and CARD_SEL or CARD_BG
			addLabel(card, 44, 8, -180, 22, hero.name, CAT_COLOR[hero.cat] or Color3.new(1, 1, 1), 17, true)
			addLabel(card, 44, 30, -180, 16, string.upper(hero.rarity or "") .. " · " .. hero.cat, rarCol, 12, true)
			addLabel(card, 44, 48, -180, 38, hero.desc, Color3.fromRGB(185, 195, 212), 12, false, true)
			local btn = Instance.new("TextButton")
			btn.AnchorPoint = Vector2.new(1, 0.5); btn.Position = UDim2.new(1, -14, 0.5, 0)
			btn.Size = UDim2.new(0, 120, 0, 42); btn.Font = Enum.Font.GothamBold; btn.TextSize = 14
			btn.TextColor3 = Color3.new(1, 1, 1); btn.ZIndex = 23; btn.Parent = card
			local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = btn
			if isSel then
				btn.Text = "✓ Đã Equip"; btn.BackgroundColor3 = Color3.fromRGB(70, 120, 70); btn.AutoButtonColor = false
			else
				btn.Text = "Equip"; btn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
				btn.Activated:Connect(function() selectHero(hero.id) end)
			end
		end
	end
	if order == 0 then
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0, 60); lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.Gotham; lbl.TextSize = 15; lbl.TextWrapped = true
		lbl.Text = "Chưa sở hữu Tàu Mẹ nào.\nMở Rương ở zone TÀU MẸ để nhận!"
		lbl.TextColor3 = Color3.fromRGB(180, 188, 205); lbl.ZIndex = 22; lbl.Parent = list
	end
end

local function render()
	clearList()
	if myShipMode then
		renderMyShip()
	elseif activeTab == "Quân" then
		renderUnits()
	elseif activeTab == "Công trình" then
		renderBuildings()
	else
		renderMotherships()
	end
end

-------------------------------------------------------------------------------
-- Tabs
-------------------------------------------------------------------------------
local tabButtons = {}
local function setTab(name)
	activeTab = name
	for n, b in pairs(tabButtons) do
		local on = (n == name)
		b.BackgroundColor3 = on and GOLD or Color3.fromRGB(40, 46, 62)
		b.TextColor3 = on and Color3.fromRGB(15, 18, 26) or Color3.fromRGB(200, 208, 224)
	end
	render()
end
for i, name in ipairs(TABS) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 176, 1, 0); b.LayoutOrder = i
	b.Font = Enum.Font.GothamBold; b.TextSize = 15; b.Text = name
	b.BackgroundColor3 = Color3.fromRGB(40, 46, 62); b.TextColor3 = Color3.fromRGB(200, 208, 224)
	b.ZIndex = 23; b.Parent = tabRow
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = b
	tabButtons[name] = b
	b.Activated:Connect(function() setTab(name) end)
end

-------------------------------------------------------------------------------
-- Mở / đóng
-------------------------------------------------------------------------------
local function setOpen(open)
	dim.Visible = open; panel.Visible = open
	if open then
		tabRow.Visible = not myShipMode
		title.Text = myShipMode and "🚀 TÀU CỦA TÔI" or "📖 MOTHERSHIP INDEX"
		-- Không có tab -> list lấp luôn khoảng tab.
		if myShipMode then
			list.Position = UDim2.new(0, 16, 0, 54); list.Size = UDim2.new(1, -32, 1, -70)
			render()
		else
			list.Position = UDim2.new(0, 16, 0, 98); list.Size = UDim2.new(1, -32, 1, -114)
			setTab(activeTab)
		end
	end
end
openBtn.Activated:Connect(function() myShipMode = false; setOpen(not panel.Visible) end)
closeBtn.Activated:Connect(function() setOpen(false) end)
dim.Activated:Connect(function() setOpen(false) end)

Remotes.HeroState.OnClientEvent:Connect(function(heroId, owned)
	selectedHeroId = heroId
	if type(owned) == "table" then ownedSet = owned end
	if panel.Visible then render() end
end)

-- Mở Index từ nút sidebar sảnh (My Ship / Index) — có thể chỉ định tab.
ClientBus.openIndex.Event:Connect(function(tab)
	if tab == "MYSHIP" then
		myShipMode = true
	else
		myShipMode = false
		if type(tab) == "string" and tabButtons[tab] then activeTab = tab end
	end
	setOpen(true)
end)

-- Nút 📖 chỉ hiện trong TRẬN (ở sảnh đã có nút sidebar).
Remotes.MatchState.OnClientEvent:Connect(function(s)
	openBtn.Visible = false -- (yêu cầu) KHÔNG hiện nút Index trong trận; ở sảnh mở từ sidebar
end)
