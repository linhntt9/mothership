--[[
	HeroesUI.client.luau
	--------------------
	Panel "Heroes" (như Lordz): chọn 1 HERO -> buff BỊ ĐỘNG cho 1 nhóm quân.

	- Mở khi Tàu Mẹ bay vào vùng CLASS ở sảnh (ClientBus.openHeroes).
	- 3 tab theo 3 nhóm: Vanguard / Guard / Artillery (Config.HERO_CATS).
	- Mỗi hero = 1 thẻ: tên + mô tả buff + nút "Chọn" (đang chọn -> "Đang dùng").
	- Bấm chọn -> Remotes.SelectHero; server xác nhận qua Remotes.HeroState.

	Buff chỉ áp cho quân SPAWN MỚI sau khi chọn (khớp server). Mở khoá bằng medal +
	nâng cấp cấp hero là Phase meta sau — hiện mở sẵn mọi hero, buff cố định theo Config.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local ClientBus = require(script.Parent.ClientBus)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Màu theo nhóm (khớp tinh thần 3 vòng SCREEN/GUARD/CORE).
local CAT_COLOR = {
	Vanguard  = Color3.fromRGB(90, 200, 255),
	Guard     = Color3.fromRGB(120, 230, 140),
	Artillery = Color3.fromRGB(255, 170, 90),
}
local GOLD = Color3.fromRGB(255, 210, 90)
local PANEL_BG = Color3.fromRGB(22, 26, 38)
local CARD_BG = Color3.fromRGB(32, 38, 54)
local CARD_SEL = Color3.fromRGB(44, 58, 44)

local selectedHeroId = nil   -- Tàu Mẹ đang lái (server xác nhận)
local ownedSet = {}          -- { [heroId]=true } Tàu Mẹ đã sở hữu
local activeTab = Config.HERO_CATS[1]

-------------------------------------------------------------------------------
-- Dựng GUI
-------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "HeroesUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 8
gui.Enabled = false
gui.Parent = playerGui

-- Nền mờ (bấm ra ngoài để đóng)
local dim = Instance.new("TextButton")
dim.Size = UDim2.new(1, 0, 1, 0); dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.45; dim.Text = ""; dim.AutoButtonColor = false
dim.ZIndex = 1; dim.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 560, 0, 420)
panel.BackgroundColor3 = PANEL_BG; panel.ZIndex = 2; panel.Parent = gui
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 18); pc.Parent = panel
local ps = Instance.new("UIStroke"); ps.Thickness = 2; ps.Color = GOLD; ps.Transparency = 0.4; ps.Parent = panel

local title = Instance.new("TextLabel")
title.Position = UDim2.new(0, 0, 0, 14); title.Size = UDim2.new(1, 0, 0, 34)
title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBlack; title.TextSize = 24
title.Text = "TÀU MẸ"; title.TextColor3 = GOLD; title.ZIndex = 3; title.Parent = panel
local subtitle = Instance.new("TextLabel")
subtitle.Position = UDim2.new(0, 0, 0, 46); subtitle.Size = UDim2.new(1, 0, 0, 18)
subtitle.BackgroundTransparency = 1; subtitle.Font = Enum.Font.Gotham; subtitle.TextSize = 13
subtitle.Text = "Chọn Tàu Mẹ để lái — mỗi con 1 tạo hình + passive đánh đổi. Mở thêm ở Rương Class."
subtitle.TextColor3 = Color3.fromRGB(170, 180, 200); subtitle.ZIndex = 3; subtitle.Parent = panel

-- Nút đóng
local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0); closeBtn.Position = UDim2.new(1, -12, 0, 12)
closeBtn.Size = UDim2.new(0, 30, 0, 30); closeBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 44)
closeBtn.Text = "✕"; closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 16
closeBtn.TextColor3 = Color3.fromRGB(255, 200, 200); closeBtn.ZIndex = 4; closeBtn.Parent = panel
local cbc = Instance.new("UICorner"); cbc.CornerRadius = UDim.new(0, 8); cbc.Parent = closeBtn

-- Hàng tab
local tabRow = Instance.new("Frame")
tabRow.Position = UDim2.new(0, 16, 0, 74); tabRow.Size = UDim2.new(1, -32, 0, 36)
tabRow.BackgroundTransparency = 1; tabRow.ZIndex = 3; tabRow.Parent = panel
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8); tabLayout.Parent = tabRow

-- Vùng thẻ hero (cuộn dọc)
local list = Instance.new("ScrollingFrame")
list.Position = UDim2.new(0, 16, 0, 120); list.Size = UDim2.new(1, -32, 1, -136)
list.BackgroundTransparency = 1; list.BorderSizePixel = 0
list.ScrollBarThickness = 5; list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y; list.ZIndex = 3; list.Parent = panel
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8); listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

-------------------------------------------------------------------------------
-- Render
-------------------------------------------------------------------------------
local tabButtons = {}

local function selectHero(heroId)
	Remotes.SelectHero:FireServer(heroId)   -- server phản hồi qua HeroState -> refresh
end

local function renderCards()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local order = 0
	for _, hero in ipairs(Config.HEROES) do
		if hero.cat == activeTab then
			order += 1
			local owned = ownedSet[hero.id] == true
			local isSel = (hero.id == selectedHeroId)
			local rarCol = (Config.RARITY_COLOR and Config.RARITY_COLOR[hero.rarity]) or Color3.fromRGB(200, 200, 200)

			local card = Instance.new("Frame")
			card.Size = UDim2.new(1, 0, 0, 90); card.LayoutOrder = order
			card.BackgroundColor3 = isSel and CARD_SEL or CARD_BG
			card.BackgroundTransparency = owned and 0 or 0.35 -- khoá thì mờ đi
			card.ZIndex = 3; card.Parent = list
			local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 12); cc.Parent = card
			local cs = Instance.new("UIStroke"); cs.Thickness = isSel and 2 or 1
			cs.Color = isSel and Color3.fromRGB(120, 230, 140) or Color3.fromRGB(60, 68, 88)
			cs.Transparency = isSel and 0 or 0.4; cs.Parent = card

			-- Ô màu = tạo hình Tàu Mẹ (màu skin của con này).
			local swatch = Instance.new("Frame")
			swatch.Position = UDim2.new(0, 12, 0, 12); swatch.Size = UDim2.new(0, 22, 0, 66)
			swatch.BackgroundColor3 = hero.color or Color3.new(1, 1, 1); swatch.ZIndex = 4; swatch.Parent = card
			local swc = Instance.new("UICorner"); swc.CornerRadius = UDim.new(0, 6); swc.Parent = swatch

			local nm = Instance.new("TextLabel")
			nm.Position = UDim2.new(0, 44, 0, 8); nm.Size = UDim2.new(1, -180, 0, 22)
			nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBold; nm.TextSize = 17
			nm.TextXAlignment = Enum.TextXAlignment.Left; nm.Text = hero.name
			nm.TextColor3 = CAT_COLOR[hero.cat] or Color3.new(1, 1, 1); nm.ZIndex = 4; nm.Parent = card

			local rar = Instance.new("TextLabel")
			rar.Position = UDim2.new(0, 44, 0, 30); rar.Size = UDim2.new(1, -180, 0, 16)
			rar.BackgroundTransparency = 1; rar.Font = Enum.Font.GothamBold; rar.TextSize = 12
			rar.TextXAlignment = Enum.TextXAlignment.Left; rar.Text = string.upper(hero.rarity or "")
			rar.TextColor3 = rarCol; rar.ZIndex = 4; rar.Parent = card

			local ds = Instance.new("TextLabel")
			ds.Position = UDim2.new(0, 44, 0, 48); ds.Size = UDim2.new(1, -180, 0, 38)
			ds.BackgroundTransparency = 1; ds.Font = Enum.Font.Gotham; ds.TextSize = 12
			ds.TextXAlignment = Enum.TextXAlignment.Left; ds.TextYAlignment = Enum.TextYAlignment.Top
			ds.TextWrapped = true; ds.Text = hero.desc
			ds.TextColor3 = Color3.fromRGB(185, 195, 212); ds.ZIndex = 4; ds.Parent = card

			local btn = Instance.new("TextButton")
			btn.AnchorPoint = Vector2.new(1, 0.5); btn.Position = UDim2.new(1, -14, 0.5, 0)
			btn.Size = UDim2.new(0, 120, 0, 42)
			btn.Font = Enum.Font.GothamBold; btn.TextSize = 14
			btn.TextColor3 = Color3.new(1, 1, 1); btn.ZIndex = 4; btn.Parent = card
			local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = btn

			if not owned then
				btn.Text = "🔒 Mở từ Rương"
				btn.BackgroundColor3 = Color3.fromRGB(58, 62, 76)
				btn.TextColor3 = Color3.fromRGB(170, 178, 195)
				btn.AutoButtonColor = false
			elseif isSel then
				btn.Text = "✓ Đang lái"
				btn.BackgroundColor3 = Color3.fromRGB(70, 120, 70)
				btn.AutoButtonColor = false
			else
				btn.Text = "Lái"
				btn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
				btn.Activated:Connect(function() selectHero(hero.id) end)
			end
		end
	end
end

local function setTab(cat)
	activeTab = cat
	for name, b in pairs(tabButtons) do
		local on = (name == cat)
		b.BackgroundColor3 = on and (CAT_COLOR[name] or GOLD) or Color3.fromRGB(40, 46, 62)
		b.TextColor3 = on and Color3.fromRGB(15, 18, 26) or Color3.fromRGB(200, 208, 224)
	end
	renderCards()
end

for i, cat in ipairs(Config.HERO_CATS) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 168, 1, 0); b.LayoutOrder = i
	b.Font = Enum.Font.GothamBold; b.TextSize = 15; b.Text = cat
	b.BackgroundColor3 = Color3.fromRGB(40, 46, 62); b.TextColor3 = Color3.fromRGB(200, 208, 224)
	b.ZIndex = 4; b.Parent = tabRow
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = b
	tabButtons[cat] = b
	b.Activated:Connect(function() setTab(cat) end)
end

-------------------------------------------------------------------------------
-- Mở / đóng + đồng bộ hero đang chọn
-------------------------------------------------------------------------------
local function close() gui.Enabled = false end
closeBtn.Activated:Connect(close)
dim.Activated:Connect(close)

ClientBus.openHeroes.Event:Connect(function(open)
	if open then
		setTab(activeTab)
		gui.Enabled = true
	else
		gui.Enabled = false
	end
end)

-- Server báo (Tàu Mẹ đang lái, tập sở hữu) — lúc vào server, khi chọn, khi mở rương.
Remotes.HeroState.OnClientEvent:Connect(function(heroId, owned)
	selectedHeroId = heroId
	if type(owned) == "table" then ownedSet = owned end
	if gui.Enabled then renderCards() end
end)

-- Vào trận thì đóng panel.
Remotes.MatchState.OnClientEvent:Connect(function(s)
	if s == "playing" then gui.Enabled = false end
end)
