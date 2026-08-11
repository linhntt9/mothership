--[[
	Lobby.client.luau
	-----------------
	Lobby = sảnh 3D vật lý (server LobbySystem dựng) + HUD 2D phủ lên (script này).
	Tàu Mẹ lái quanh sảnh; camera chếch sau lưng (CameraController). Bay vào vùng
	cổng 3D -> mở panel Class/Skin/Vào trận.

	HUD 2D (bám bố cục brief, KHÔNG che 3D):
	  - Trái : Store / Bag / Index
	  - Phải : Gifts / Quest / Rank / Pass  (badge đỏ)
	  - Trên : Level + XP (giữa), Leaderboard + Gems (phải)
	  - Dưới : Trade
	Các panel HUD hiện là PLACEHOLDER (bấm -> "Sắp có"); nút "Vào trận" chạy thật.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local ClientBus = require(script.Parent.ClientBus)

local player = Players.LocalPlayer
local uid = player.UserId
local playerGui = player:WaitForChild("PlayerGui")

local ZONES = Config.LOBBY.ZONES
local R2 = Config.LOBBY.ZONE_RADIUS * Config.LOBBY.ZONE_RADIUS
local PANEL_BG = Color3.fromRGB(24, 28, 40)
local PANEL_BG2 = Color3.fromRGB(15, 18, 28)

local gui = Instance.new("ScreenGui")
gui.Name = "Lobby"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 5
gui.Enabled = true
gui.Parent = playerGui

-------------------------------------------------------------------------------
-- Toast "Sắp có"
-------------------------------------------------------------------------------
local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 74)
toast.Size = UDim2.new(0, 420, 0, 38)
toast.BackgroundColor3 = PANEL_BG2
toast.BackgroundTransparency = 0.1
toast.TextColor3 = Color3.fromRGB(255, 225, 150)
toast.Font = Enum.Font.GothamBold
toast.TextSize = 16
toast.Text = ""
toast.Visible = false
toast.ZIndex = 40
local toc = Instance.new("UICorner"); toc.CornerRadius = UDim.new(0, 8); toc.Parent = toast
toast.Parent = gui
local toastN = 0
local function showToast(t)
	toast.Text = t; toast.Visible = true
	toastN += 1; local my = toastN
	task.delay(1.6, function() if my == toastN then toast.Visible = false end end)
end

-- Đánh dấu khi con trỏ đang trên nút HUD -> InputController bỏ qua lái tàu (để bấm được).
local function trackHover(el)
	el.MouseEnter:Connect(function() player:SetAttribute("LobbyHoverUI", true) end)
	el.MouseLeave:Connect(function() player:SetAttribute("LobbyHoverUI", false) end)
end

-- Gợi ý điều khiển (đáy giữa)
local ctrlHint = Instance.new("TextLabel")
ctrlHint.AnchorPoint = Vector2.new(0.5, 1)
ctrlHint.Position = UDim2.new(0.5, 0, 1, -14)
ctrlHint.Size = UDim2.new(0, 460, 0, 30)
ctrlHint.BackgroundColor3 = PANEL_BG2
ctrlHint.BackgroundTransparency = 0.35
ctrlHint.TextColor3 = Color3.fromRGB(210, 220, 235)
ctrlHint.Font = Enum.Font.GothamBold
ctrlHint.TextSize = 14
ctrlHint.Text = "WASD di chuyển  ·  Lăn chuột: zoom  ·  Lái vào cổng để mở"
local chc = Instance.new("UICorner"); chc.CornerRadius = UDim.new(0, 8); chc.Parent = ctrlHint
ctrlHint.Parent = gui

-------------------------------------------------------------------------------
-- Nút panel dọc (icon + label + badge)
-------------------------------------------------------------------------------
local function sideButton(parent, order, icon, label, badge, onClick)
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.new(0, 88, 0, 80)
	b.BackgroundColor3 = PANEL_BG
	b.Text = ""
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = b
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(60, 74, 100); st.Thickness = 1.5; st.Transparency = 0.4; st.Parent = b
	local ic = Instance.new("TextLabel")
	ic.Size = UDim2.new(1, 0, 0.6, 0); ic.Position = UDim2.new(0, 0, 0, 6)
	ic.BackgroundTransparency = 1; ic.Text = icon; ic.TextScaled = true
	ic.Font = Enum.Font.GothamBold; ic.TextColor3 = Color3.fromRGB(235, 240, 255)
	ic.Parent = b
	local lb = Instance.new("TextLabel")
	lb.Size = UDim2.new(1, 0, 0.34, 0); lb.Position = UDim2.new(0, 0, 0.64, 0)
	lb.BackgroundTransparency = 1; lb.Text = label; lb.TextScaled = true
	lb.Font = Enum.Font.GothamMedium; lb.TextColor3 = Color3.fromRGB(195, 205, 225)
	local lc = Instance.new("UITextSizeConstraint"); lc.MaxTextSize = 14; lc.Parent = lb
	lb.Parent = b
	if badge then
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(1, 0); d.Position = UDim2.new(1, -6, 0, 6)
		d.Size = UDim2.fromOffset(14, 14); d.BackgroundColor3 = Color3.fromRGB(235, 60, 60); d.ZIndex = 3
		local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = d
		d.Parent = b
	end
	b.Activated:Connect(function()
		if onClick then onClick() else showToast(label .. " — Sắp có (Phase sau)") end
	end)
	trackHover(b)
	b.Parent = parent
	return b
end

local function sideBar(side)
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(side == "left" and 0 or 1, 0.5)
	bar.Position = side == "left" and UDim2.new(0, 14, 0.5, 20) or UDim2.new(1, -14, 0.5, 20)
	bar.Size = UDim2.new(0, 88, 0, 420)
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Vertical
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Padding = UDim.new(0, 10); l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = bar
	return bar
end

local leftBar = sideBar("left")
sideButton(leftBar, 1, "🛒", "Store", false)
sideButton(leftBar, 2, "🚀", "My Ship", false, function() ClientBus.openIndex:Fire("MYSHIP") end)
sideButton(leftBar, 3, "📖", "Index", false, function() ClientBus.openIndex:Fire("Quân") end)
sideButton(leftBar, 4, "⚔", "Test", false, function() Remotes.StartTest:FireServer() end)

local openGifts -- (định nghĩa ở khối Gifts bên dưới)
local rightBar = sideBar("right")
sideButton(rightBar, 1, "🎁", "Gifts", true, function() if openGifts then openGifts() end end)
sideButton(rightBar, 2, "✔", "Quest", true, function() ClientBus.openQuests:Fire() end)
sideButton(rightBar, 3, "🏆", "Rank", false)
sideButton(rightBar, 4, "🎟", "Pass", true)

-------------------------------------------------------------------------------
-- TRÊN: Level + XP (giữa)
-------------------------------------------------------------------------------
local lvl = Instance.new("Frame")
lvl.AnchorPoint = Vector2.new(0.5, 0)
lvl.Position = UDim2.new(0.5, 0, 0, 12)
lvl.Size = UDim2.new(0, 300, 0, 42)
lvl.BackgroundColor3 = PANEL_BG2; lvl.BackgroundTransparency = 0.15
local lc2 = Instance.new("UICorner"); lc2.CornerRadius = UDim.new(0, 10); lc2.Parent = lvl
lvl.Parent = gui
local lvlText = Instance.new("TextLabel")
lvlText.Size = UDim2.new(0, 64, 1, 0); lvlText.Position = UDim2.new(0, 12, 0, 0)
lvlText.BackgroundTransparency = 1; lvlText.Text = "⭐ Lv1"; lvlText.Font = Enum.Font.GothamBold
lvlText.TextSize = 17; lvlText.TextColor3 = Color3.fromRGB(255, 220, 120)
lvlText.TextXAlignment = Enum.TextXAlignment.Left; lvlText.Parent = lvl
local xpBg = Instance.new("Frame")
xpBg.AnchorPoint = Vector2.new(0, 0.5); xpBg.Position = UDim2.new(0, 78, 0.5, 0)
xpBg.Size = UDim2.new(1, -90, 0, 12); xpBg.BackgroundColor3 = Color3.fromRGB(40, 46, 60)
local xc = Instance.new("UICorner"); xc.CornerRadius = UDim.new(1, 0); xc.Parent = xpBg
xpBg.Parent = lvl
local xpFill = Instance.new("Frame")
xpFill.Size = UDim2.new(0.15, 0, 1, 0); xpFill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
local xfc = Instance.new("UICorner"); xfc.CornerRadius = UDim.new(1, 0); xfc.Parent = xpFill
xpFill.Parent = xpBg
-- Cấp người chơi (thắng +1 / thua -1) — server gửi qua LevelUpdate.
Remotes.LevelUpdate.OnClientEvent:Connect(function(lv)
	lvlText.Text = "⭐ Lv" .. tostring(lv)
end)

-------------------------------------------------------------------------------
-- TRÊN-PHẢI: Leaderboard (placeholder) + Gems
-------------------------------------------------------------------------------
local lbBox = Instance.new("Frame")
lbBox.AnchorPoint = Vector2.new(1, 0)
lbBox.Position = UDim2.new(1, -14, 0, 12)
lbBox.Size = UDim2.new(0, 190, 0, 86)
lbBox.BackgroundColor3 = PANEL_BG2; lbBox.BackgroundTransparency = 0.2
local lbc = Instance.new("UICorner"); lbc.CornerRadius = UDim.new(0, 10); lbc.Parent = lbBox
lbBox.Parent = gui
local lbTitle = Instance.new("TextLabel")
lbTitle.Size = UDim2.new(1, 0, 0, 24); lbTitle.BackgroundTransparency = 1
lbTitle.Text = "🏆 XẾP HẠNG"; lbTitle.Font = Enum.Font.GothamBold; lbTitle.TextSize = 13
lbTitle.TextColor3 = Color3.fromRGB(255, 220, 120); lbTitle.Parent = lbBox
local lbBody = Instance.new("TextLabel")
lbBody.Position = UDim2.new(0, 8, 0, 26); lbBody.Size = UDim2.new(1, -16, 1, -30)
lbBody.BackgroundTransparency = 1; lbBody.Font = Enum.Font.Gotham; lbBody.TextSize = 13
lbBody.TextColor3 = Color3.fromRGB(200, 210, 225); lbBody.TextXAlignment = Enum.TextXAlignment.Left
lbBody.TextYAlignment = Enum.TextYAlignment.Top; lbBody.Text = "Chơi để leo hạng!"; lbBody.TextWrapped = true
lbBody.Parent = lbBox

local gemChip = Instance.new("Frame")
gemChip.AnchorPoint = Vector2.new(1, 0)
gemChip.Position = UDim2.new(1, -14, 0, 104)
gemChip.Size = UDim2.new(0, 190, 0, 40)
gemChip.BackgroundColor3 = PANEL_BG2; gemChip.BackgroundTransparency = 0.2
local ggc = Instance.new("UICorner"); ggc.CornerRadius = UDim.new(0, 10); ggc.Parent = gemChip
gemChip.Parent = gui
local gemText = Instance.new("TextLabel")
gemText.Size = UDim2.new(1, -50, 1, 0); gemText.Position = UDim2.new(0, 12, 0, 0)
gemText.BackgroundTransparency = 1; gemText.Text = "💎 0"; gemText.Font = Enum.Font.GothamBold
gemText.TextSize = 18; gemText.TextColor3 = Color3.fromRGB(150, 230, 255)
gemText.TextXAlignment = Enum.TextXAlignment.Left; gemText.Parent = gemChip
local gemPlus = Instance.new("TextButton")
gemPlus.AnchorPoint = Vector2.new(1, 0.5); gemPlus.Position = UDim2.new(1, -6, 0.5, 0)
gemPlus.Size = UDim2.fromOffset(32, 32); gemPlus.BackgroundColor3 = Color3.fromRGB(60, 180, 90)
gemPlus.Text = "+"; gemPlus.Font = Enum.Font.GothamBlack; gemPlus.TextSize = 22
gemPlus.TextColor3 = Color3.fromRGB(255, 255, 255)
local gpc = Instance.new("UICorner"); gpc.CornerRadius = UDim.new(0, 8); gpc.Parent = gemPlus
gemPlus.Parent = gemChip
gemPlus.Activated:Connect(function() showToast("Mua Gems (Robux) — Sắp có") end)
trackHover(gemPlus)
-- Gem kiếm được khi chiến đấu (server lưu theo player) -> hiện ở sảnh.
Remotes.GemUpdate.OnClientEvent:Connect(function(g)
	gemText.Text = "💎 " .. tostring(g)
end)

-------------------------------------------------------------------------------
-- Panel shop (class/skin) + panel cổng "Vào trận" — hiện khi vào vùng cổng 3D
-------------------------------------------------------------------------------
local shop = Instance.new("Frame")
shop.AnchorPoint = Vector2.new(0.5, 0.5); shop.Position = UDim2.new(0.5, 0, 0.44, 0)
shop.Size = UDim2.new(0, 440, 0, 230); shop.BackgroundColor3 = PANEL_BG; shop.Visible = false
local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 16); sc.Parent = shop
local ss = Instance.new("UIStroke"); ss.Thickness = 2; ss.Transparency = 0.3; ss.Parent = shop
shop.Parent = gui
local shopTitle = Instance.new("TextLabel")
shopTitle.Position = UDim2.new(0, 0, 0, 16); shopTitle.Size = UDim2.new(1, 0, 0, 42)
shopTitle.BackgroundTransparency = 1; shopTitle.Font = Enum.Font.GothamBlack; shopTitle.TextScaled = true
shopTitle.Text = ""; shopTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
local stc = Instance.new("UITextSizeConstraint"); stc.MaxTextSize = 28; stc.Parent = shopTitle
shopTitle.Parent = shop
local shopBody = Instance.new("TextLabel")
shopBody.Position = UDim2.new(0, 24, 0, 66); shopBody.Size = UDim2.new(1, -48, 1, -100)
shopBody.BackgroundTransparency = 1; shopBody.Font = Enum.Font.Gotham; shopBody.TextSize = 17
shopBody.TextWrapped = true; shopBody.TextColor3 = Color3.fromRGB(200, 210, 225)
shopBody.TextYAlignment = Enum.TextYAlignment.Top; shopBody.Text = ""; shopBody.Parent = shop
local shopFoot = Instance.new("TextLabel")
shopFoot.AnchorPoint = Vector2.new(0.5, 1); shopFoot.Position = UDim2.new(0.5, 0, 1, -12)
shopFoot.Size = UDim2.new(1, -24, 0, 20); shopFoot.BackgroundTransparency = 1
shopFoot.Font = Enum.Font.GothamMedium; shopFoot.TextSize = 13; shopFoot.TextColor3 = Color3.fromRGB(150, 160, 180)
shopFoot.Text = "(bay ra khỏi cổng để đóng)"; shopFoot.Parent = shop

-- Vào cổng "VÀO TRẬN" là TỰ khởi trận (không cần bấm nút). Cờ chống gọi lặp.
local requestedMatch = false

local SHOP_BODY = {
	skin = "Skin Tàu Mẹ · hạm đội · màu laser. Mua ở đây sẽ hiện ngay trên tàu bạn.\n\n(Sắp có — Phase 3)",
}

-------------------------------------------------------------------------------
-- Panel RƯƠNG THƯỞNG (vào vùng "chest"): mở nhận Gems, có hồi chiêu.
-------------------------------------------------------------------------------
local CHEST_GOLD = Color3.fromRGB(255, 205, 70)
local chestRemaining = 0 -- giây còn lại tới lần mở kế (server là nguồn chuẩn)

local chestPanel = Instance.new("Frame")
chestPanel.AnchorPoint = Vector2.new(0.5, 0.5); chestPanel.Position = UDim2.new(0.5, 0, 0.46, 0)
chestPanel.Size = UDim2.new(0, 420, 0, 440); chestPanel.BackgroundColor3 = PANEL_BG; chestPanel.Visible = false
local ccc = Instance.new("UICorner"); ccc.CornerRadius = UDim.new(0, 16); ccc.Parent = chestPanel
local ccs = Instance.new("UIStroke"); ccs.Thickness = 2; ccs.Color = CHEST_GOLD; ccs.Transparency = 0.25; ccs.Parent = chestPanel
chestPanel.Parent = gui

local chestTitle = Instance.new("TextLabel")
chestTitle.Position = UDim2.new(0, 0, 0, 16); chestTitle.Size = UDim2.new(1, 0, 0, 34)
chestTitle.BackgroundTransparency = 1; chestTitle.Font = Enum.Font.GothamBlack; chestTitle.TextSize = 24
chestTitle.Text = "🎁 RƯƠNG TÀU MẸ"; chestTitle.TextColor3 = CHEST_GOLD; chestTitle.Parent = chestPanel

-- Bảng tỉ lệ ra (tính từ weight trong Config.HEROES).
local dropLabel = Instance.new("TextLabel")
dropLabel.Position = UDim2.new(0, 20, 0, 54); dropLabel.Size = UDim2.new(1, -40, 0, 150)
dropLabel.BackgroundTransparency = 1; dropLabel.Font = Enum.Font.Gotham; dropLabel.TextSize = 13
dropLabel.TextXAlignment = Enum.TextXAlignment.Left; dropLabel.TextYAlignment = Enum.TextYAlignment.Top
dropLabel.RichText = true; dropLabel.TextColor3 = Color3.fromRGB(210, 218, 232)
dropLabel.Parent = chestPanel
do
	local total = 0
	for _, h in ipairs(Config.HEROES) do total += (h.weight or 0) end
	local lines = { "<b>Tỉ lệ ra:</b>" }
	for _, h in ipairs(Config.HEROES) do
		local pct = total > 0 and (h.weight or 0) / total * 100 or 0
		local col = (Config.RARITY_COLOR and Config.RARITY_COLOR[h.rarity]) or Color3.fromRGB(200, 200, 200)
		local hex = string.format("#%02X%02X%02X",
			math.floor(col.R * 255), math.floor(col.G * 255), math.floor(col.B * 255))
		table.insert(lines, ("<font color=\"%s\">%s — %.1f%%</font>"):format(hex, h.name, pct))
	end
	dropLabel.Text = table.concat(lines, "\n")
end

local chestReward = Instance.new("TextLabel")
chestReward.Position = UDim2.new(0, 20, 0, 210); chestReward.Size = UDim2.new(1, -40, 0, 66)
chestReward.BackgroundTransparency = 1; chestReward.Font = Enum.Font.GothamBold; chestReward.TextSize = 20
chestReward.TextWrapped = true; chestReward.Text = "Mở rương để roll ra Tàu Mẹ mới!"
chestReward.TextColor3 = Color3.fromRGB(210, 220, 235); chestReward.Parent = chestPanel

-- Hai nút: MIỄN PHÍ (mỗi COOLDOWN 1 lượt) & ROLL bằng Gem (tốn Gem, không chờ).
local GEM_COST = (Config.LOBBY.CHEST and Config.LOBBY.CHEST.GEM_COST) or 100

local freeBtn = Instance.new("TextButton")
freeBtn.AnchorPoint = Vector2.new(0.5, 1); freeBtn.Position = UDim2.new(0.5, 0, 1, -114)
freeBtn.Size = UDim2.new(1, -40, 0, 40)
freeBtn.Font = Enum.Font.GothamBold; freeBtn.TextSize = 15
freeBtn.Text = "MIỄN PHÍ"; freeBtn.TextColor3 = Color3.fromRGB(20, 40, 20)
freeBtn.Parent = chestPanel
local fbc = Instance.new("UICorner"); fbc.CornerRadius = UDim.new(0, 10); fbc.Parent = freeBtn

local gemBtn = Instance.new("TextButton")
gemBtn.AnchorPoint = Vector2.new(0, 1); gemBtn.Position = UDim2.new(0, 20, 1, -18)
gemBtn.Size = UDim2.new(0.5, -26, 0, 44)
gemBtn.Font = Enum.Font.GothamBold; gemBtn.TextSize = 15
gemBtn.BackgroundColor3 = Color3.fromRGB(90, 150, 240); gemBtn.TextColor3 = Color3.new(1, 1, 1)
gemBtn.Text = ("ROLL ×1 · %d 💎"):format(GEM_COST)
gemBtn.Parent = chestPanel
local gbc = Instance.new("UICorner"); gbc.CornerRadius = UDim.new(0, 10); gbc.Parent = gemBtn

-- Nút ROLL ×10 (Gem, đảm bảo ít nhất 1 Rare+) — kiểu Genshin.
local gem10Btn = Instance.new("TextButton")
gem10Btn.AnchorPoint = Vector2.new(1, 1); gem10Btn.Position = UDim2.new(1, -20, 1, -18)
gem10Btn.Size = UDim2.new(0.5, -26, 0, 44)
gem10Btn.Font = Enum.Font.GothamBold; gem10Btn.TextSize = 15
gem10Btn.BackgroundColor3 = Color3.fromRGB(150, 110, 240); gem10Btn.TextColor3 = Color3.new(1, 1, 1)
gem10Btn.Text = ("ROLL ×10 · %d 💎"):format(GEM_COST * 10)
gem10Btn.Parent = chestPanel
local g10c = Instance.new("UICorner"); g10c.CornerRadius = UDim.new(0, 10); g10c.Parent = gem10Btn

-- Thanh PITY ("cầu Epic"): còn bao nhiêu lượt tới Epic đảm bảo (server cập nhật).
local pityLabel = Instance.new("TextLabel")
pityLabel.AnchorPoint = Vector2.new(0.5, 1); pityLabel.Position = UDim2.new(0.5, 0, 1, -164)
pityLabel.Size = UDim2.new(1, -40, 0, 18); pityLabel.BackgroundTransparency = 1
pityLabel.Font = Enum.Font.GothamBold; pityLabel.TextSize = 13
pityLabel.TextColor3 = Color3.fromRGB(255, 210, 120); pityLabel.TextXAlignment = Enum.TextXAlignment.Center
pityLabel.Text = ""; pityLabel.Parent = chestPanel

local function refreshChest()
	if chestRemaining > 0 then
		freeBtn.AutoButtonColor = false
		freeBtn.BackgroundColor3 = Color3.fromRGB(70, 74, 88)
		freeBtn.TextColor3 = Color3.fromRGB(180, 188, 205)
		freeBtn.Text = ("MIỄN PHÍ ⏳ %ds"):format(math.ceil(chestRemaining))
	else
		freeBtn.AutoButtonColor = true
		freeBtn.BackgroundColor3 = Color3.fromRGB(120, 210, 120)
		freeBtn.TextColor3 = Color3.fromRGB(20, 40, 20)
		freeBtn.Text = "MIỄN PHÍ ✓"
	end
end

freeBtn.Activated:Connect(function()
	if chestRemaining > 0 then return end
	Remotes.OpenChest:FireServer("free")
end)
gemBtn.Activated:Connect(function()
	Remotes.OpenChest:FireServer("gem")
end)
gem10Btn.Activated:Connect(function()
	Remotes.OpenChest:FireServer("gem10")
end)

-- Hiệu ứng GACHA: orb quay hồi hộp -> flash màu rarity -> thẻ Tàu Mẹ bật ra.
local function playGachaReveal(reward)
	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")
	local rarity = reward.rarity or "Common"
	local rarCol = (Config.RARITY_COLOR and Config.RARITY_COLOR[rarity]) or CHEST_GOLD
	local skinCol = reward.color or CHEST_GOLD

	local ov = Instance.new("Frame")
	ov.Size = UDim2.fromScale(1, 1); ov.BackgroundColor3 = Color3.new(0, 0, 0)
	ov.BackgroundTransparency = 1; ov.ZIndex = 50; ov.Parent = gui
	TweenService:Create(ov, TweenInfo.new(0.3), { BackgroundTransparency = 0.4 }):Play()

	-- Orb quay (giai đoạn hồi hộp)
	local orb = Instance.new("Frame")
	orb.AnchorPoint = Vector2.new(0.5, 0.5); orb.Position = UDim2.new(0.5, 0, 0.45, 0)
	orb.Size = UDim2.new(0, 24, 0, 24); orb.BackgroundColor3 = CHEST_GOLD
	orb.Rotation = 0; orb.ZIndex = 51; orb.Parent = ov
	local oc = Instance.new("UICorner"); oc.CornerRadius = UDim.new(0, 6); oc.Parent = orb
	local os_ = Instance.new("UIStroke"); os_.Color = Color3.new(1, 1, 1); os_.Thickness = 2; os_.Parent = orb

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5); label.Position = UDim2.new(0.5, 0, 0.66, 0)
	label.Size = UDim2.new(0, 500, 0, 40); label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack; label.TextSize = 26; label.Text = "Đang mở..."
	label.TextColor3 = Color3.fromRGB(230, 230, 240); label.ZIndex = 51; label.Parent = ov

	TweenService:Create(orb, TweenInfo.new(1.3, Enum.EasingStyle.Quad), {
		Size = UDim2.new(0, 130, 0, 130), Rotation = 900,
	}):Play()
	task.spawn(function()
		local cols = { Color3.fromRGB(190, 200, 215), Color3.fromRGB(90, 180, 255), Color3.fromRGB(200, 120, 255), CHEST_GOLD }
		for i = 1, 11 do
			if not ov.Parent then return end
			orb.BackgroundColor3 = cols[(i % #cols) + 1]
			task.wait(0.11)
		end
	end)

	task.delay(1.35, function()
		if not ov.Parent then return end
		orb:Destroy()

		-- Flash màu rarity
		local flash = Instance.new("Frame")
		flash.Size = UDim2.fromScale(1, 1); flash.BackgroundColor3 = rarCol
		flash.BackgroundTransparency = 0.05; flash.ZIndex = 52; flash.Parent = ov
		TweenService:Create(flash, TweenInfo.new(0.55), { BackgroundTransparency = 1 }):Play()
		Debris:AddItem(flash, 0.6)

		-- Thẻ kết quả bật ra
		local card = Instance.new("Frame")
		card.AnchorPoint = Vector2.new(0.5, 0.5); card.Position = UDim2.new(0.5, 0, 0.45, 0)
		card.Size = UDim2.new(0, 0, 0, 0); card.BackgroundColor3 = Color3.fromRGB(24, 28, 40)
		card.ZIndex = 53; card.Parent = ov
		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 18); cc.Parent = card
		local cs = Instance.new("UIStroke"); cs.Color = rarCol; cs.Thickness = 3; cs.Parent = card

		local sw = Instance.new("Frame"); sw.AnchorPoint = Vector2.new(0.5, 0)
		sw.Position = UDim2.new(0.5, 0, 0, 24); sw.Size = UDim2.new(0, 96, 0, 96)
		sw.BackgroundColor3 = skinCol; sw.ZIndex = 54; sw.Parent = card
		local swc = Instance.new("UICorner"); swc.CornerRadius = UDim.new(1, 0); swc.Parent = sw
		local sws = Instance.new("UIStroke"); sws.Color = Color3.new(1, 1, 1); sws.Thickness = 2; sws.Transparency = 0.3; sws.Parent = sw

		local badge = Instance.new("TextLabel"); badge.Position = UDim2.new(0, 0, 0, 130)
		badge.Size = UDim2.new(1, 0, 0, 22); badge.BackgroundTransparency = 1
		badge.Font = Enum.Font.GothamBlack; badge.TextSize = 16
		badge.Text = reward.isNew and "★ TÀU MẸ MỚI ★" or "TRÙNG (đã sở hữu)"
		badge.TextColor3 = reward.isNew and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(180, 188, 205)
		badge.ZIndex = 54; badge.Parent = card

		local nm = Instance.new("TextLabel"); nm.Position = UDim2.new(0, 0, 0, 154)
		nm.Size = UDim2.new(1, 0, 0, 30); nm.BackgroundTransparency = 1
		nm.Font = Enum.Font.GothamBlack; nm.TextSize = 24; nm.Text = reward.name
		nm.TextColor3 = skinCol; nm.ZIndex = 54; nm.Parent = card

		local rr = Instance.new("TextLabel"); rr.Position = UDim2.new(0, 0, 0, 186)
		rr.Size = UDim2.new(1, 0, 0, 20); rr.BackgroundTransparency = 1
		rr.Font = Enum.Font.GothamBold; rr.TextSize = 15; rr.Text = string.upper(rarity)
		rr.TextColor3 = rarCol; rr.ZIndex = 54; rr.Parent = card

		local hint = Instance.new("TextLabel"); hint.AnchorPoint = Vector2.new(0.5, 1)
		hint.Position = UDim2.new(0.5, 0, 1, -12); hint.Size = UDim2.new(1, 0, 0, 18)
		hint.BackgroundTransparency = 1; hint.Font = Enum.Font.Gotham; hint.TextSize = 12
		hint.Text = "Bấm để đóng"; hint.TextColor3 = Color3.fromRGB(150, 158, 175); hint.ZIndex = 54; hint.Parent = card

		TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 300, 0, 236),
		}):Play()
		-- Epic/Rare: nhấp viền cho lung linh
		if rarity ~= "Common" then
			task.spawn(function()
				while ov.Parent do
					TweenService:Create(cs, TweenInfo.new(0.6), { Thickness = 6 }):Play(); task.wait(0.6)
					TweenService:Create(cs, TweenInfo.new(0.6), { Thickness = 3 }):Play(); task.wait(0.6)
				end
			end)
		end

		local closeBtn = Instance.new("TextButton"); closeBtn.Size = UDim2.fromScale(1, 1)
		closeBtn.BackgroundTransparency = 1; closeBtn.Text = ""; closeBtn.ZIndex = 55; closeBtn.Parent = ov
		local closed = false
		local function doClose()
			if closed then return end; closed = true
			TweenService:Create(ov, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
			Debris:AddItem(ov, 0.3)
		end
		closeBtn.Activated:Connect(doClose)
		task.delay(4.5, doClose)
	end)
end

-- Hiệu ứng GACHA kiểu Genshin: overlay đen + sao nền -> TIA SÁNG dọc màu theo độ
-- hiếm CAO NHẤT của lượt (xanh<tím<vàng) -> bùng sáng -> các thẻ Tàu Mẹ hiện so le.
-- Nhận list (x1 = 1 phần tử, x10 = 10). Có nút BỎ QUA để nhảy thẳng tới reveal.
local RARITY_RANK = { Common = 1, Rare = 2, Epic = 3 }
local SKY_COLOR = {
	Common = Color3.fromRGB(90, 170, 255),   -- xanh dương
	Rare   = Color3.fromRGB(190, 120, 255),   -- tím
	Epic   = Color3.fromRGB(255, 205, 70),    -- vàng
}
local function playGenshinReveal(list)
	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")
	if #list == 0 then return end

	local best = "Common"
	for _, r in ipairs(list) do
		if (RARITY_RANK[r.rarity] or 1) > (RARITY_RANK[best] or 1) then best = r.rarity end
	end
	local skyCol = SKY_COLOR[best] or SKY_COLOR.Common

	local ov = Instance.new("Frame")
	ov.Size = UDim2.fromScale(1, 1); ov.BackgroundColor3 = Color3.new(0, 0, 0)
	ov.BackgroundTransparency = 1; ov.ZIndex = 60; ov.Parent = gui
	TweenService:Create(ov, TweenInfo.new(0.35), { BackgroundTransparency = 0.1 }):Play()

	-- Sao nền lấp lánh.
	for _ = 1, 26 do
		local sz = math.random(2, 5)
		local s = Instance.new("Frame")
		s.Size = UDim2.fromOffset(sz, sz); s.BackgroundColor3 = Color3.new(1, 1, 1)
		s.BackgroundTransparency = 0.2 + math.random() * 0.5
		s.Position = UDim2.fromScale(math.random(), math.random())
		s.ZIndex = 61; s.Parent = ov
		local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(1, 0); sc.Parent = s
	end

	-- Nút BỎ QUA.
	local skip = Instance.new("TextButton")
	skip.AnchorPoint = Vector2.new(1, 0); skip.Position = UDim2.new(1, -18, 0, 16)
	skip.Size = UDim2.fromOffset(104, 30); skip.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
	skip.BackgroundTransparency = 0.2; skip.Font = Enum.Font.GothamBold; skip.TextSize = 13
	skip.TextColor3 = Color3.fromRGB(220, 226, 240); skip.Text = "BỎ QUA ⏩"; skip.ZIndex = 90; skip.Parent = ov
	local skc = Instance.new("UICorner"); skc.CornerRadius = UDim.new(0, 8); skc.Parent = skip

	-- Tia sáng dọc giữa màn (giai đoạn hồi hộp).
	local beam = Instance.new("Frame")
	beam.AnchorPoint = Vector2.new(0.5, 0.5); beam.Position = UDim2.fromScale(0.5, 0.5)
	beam.Size = UDim2.new(0, 6, 0, 0); beam.BackgroundColor3 = skyCol
	beam.BackgroundTransparency = 0.1; beam.ZIndex = 62; beam.Parent = ov
	local bg = Instance.new("UIGradient"); bg.Rotation = 90
	bg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
	}); bg.Parent = beam

	local done = false
	local function reveal()
		if done then return end; done = true
		skip.Visible = false
		if beam.Parent then beam:Destroy() end

		-- Bùng sáng màu sky.
		local flash = Instance.new("Frame")
		flash.Size = UDim2.fromScale(1, 1); flash.BackgroundColor3 = skyCol
		flash.BackgroundTransparency = 0; flash.ZIndex = 70; flash.Parent = ov
		TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		Debris:AddItem(flash, 0.65)

		-- Lưới thẻ (10 -> 5x2; 1 -> 1 thẻ lớn).
		local n = #list
		local cols = n > 1 and 5 or 1
		local rows = math.ceil(n / cols)
		local cw = n > 1 and 122 or 250
		local ch = n > 1 and 152 or 300
		local gap = 12
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0.5); holder.Position = UDim2.fromScale(0.5, 0.46)
		holder.BackgroundTransparency = 1; holder.ZIndex = 71; holder.Parent = ov
		holder.Size = UDim2.fromOffset(cols * cw + (cols - 1) * gap, rows * ch + (rows - 1) * gap)

		local big = n == 1
		for idx, r in ipairs(list) do
			local rar = r.rarity or "Common"
			local rarCol = (Config.RARITY_COLOR and Config.RARITY_COLOR[rar]) or CHEST_GOLD
			local ci = (idx - 1) % cols
			local ri = math.floor((idx - 1) / cols)

			local card = Instance.new("Frame")
			card.AnchorPoint = Vector2.new(0.5, 0.5)
			card.Position = UDim2.fromOffset(ci * (cw + gap) + cw / 2, ri * (ch + gap) + ch / 2)
			card.Size = UDim2.fromOffset(cw, ch); card.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
			card.BackgroundTransparency = 1; card.ZIndex = 72; card.Parent = holder
			local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 12); cc.Parent = card
			local cs = Instance.new("UIStroke"); cs.Color = rarCol; cs.Thickness = big and 3 or 2.5; cs.Transparency = 1; cs.Parent = card

			local sw = Instance.new("Frame"); sw.AnchorPoint = Vector2.new(0.5, 0)
			sw.Position = UDim2.new(0.5, 0, 0, big and 30 or 16)
			sw.Size = UDim2.fromOffset(big and 112 or 56, big and 112 or 56)
			sw.BackgroundColor3 = r.color or rarCol; sw.BackgroundTransparency = 1; sw.ZIndex = 73; sw.Parent = card
			local swc = Instance.new("UICorner"); swc.CornerRadius = UDim.new(1, 0); swc.Parent = sw
			local sws = Instance.new("UIStroke"); sws.Color = Color3.new(1, 1, 1); sws.Thickness = 2; sws.Transparency = 1; sws.Parent = sw

			local nm = Instance.new("TextLabel"); nm.AnchorPoint = Vector2.new(0.5, 1)
			nm.Position = UDim2.new(0.5, 0, 1, big and -52 or -26); nm.Size = UDim2.new(1, -8, 0, 32)
			nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBlack; nm.TextSize = big and 22 or 12
			nm.TextWrapped = true; nm.Text = r.name; nm.TextColor3 = r.color or rarCol
			nm.TextTransparency = 1; nm.ZIndex = 73; nm.Parent = card

			local rr = Instance.new("TextLabel"); rr.AnchorPoint = Vector2.new(0.5, 1)
			rr.Position = UDim2.new(0.5, 0, 1, big and -26 or -8); rr.Size = UDim2.new(1, -8, 0, 18)
			rr.BackgroundTransparency = 1; rr.Font = Enum.Font.GothamBold; rr.TextSize = big and 15 or 11
			rr.Text = string.upper(rar); rr.TextColor3 = rarCol; rr.TextTransparency = 1; rr.ZIndex = 73; rr.Parent = card

			local badge
			if r.isNew then
				badge = Instance.new("TextLabel"); badge.AnchorPoint = Vector2.new(1, 0)
				badge.Position = UDim2.new(1, -6, 0, 6); badge.Size = UDim2.fromOffset(40, 16)
				badge.BackgroundColor3 = Color3.fromRGB(120, 255, 150); badge.Font = Enum.Font.GothamBlack
				badge.TextSize = 10; badge.Text = "NEW"; badge.TextColor3 = Color3.fromRGB(10, 40, 20)
				badge.TextTransparency = 1; badge.BackgroundTransparency = 1; badge.ZIndex = 74; badge.Parent = card
				local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 4); bc.Parent = badge
			end

			task.delay((idx - 1) * (n > 1 and 0.08 or 0), function()
				if not card.Parent then return end
				card.Size = UDim2.fromOffset(cw * 0.8, ch * 0.8)
				TweenService:Create(card, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = UDim2.fromOffset(cw, ch), BackgroundTransparency = 0 }):Play()
				TweenService:Create(cs, TweenInfo.new(0.3), { Transparency = 0 }):Play()
				TweenService:Create(sw, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
				TweenService:Create(sws, TweenInfo.new(0.3), { Transparency = 0.3 }):Play()
				TweenService:Create(nm, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
				TweenService:Create(rr, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
				if badge then
					TweenService:Create(badge, TweenInfo.new(0.3), { BackgroundTransparency = 0, TextTransparency = 0 }):Play()
				end
				-- Epic: nhấp viền lung linh.
				if rar == "Epic" then
					task.spawn(function()
						while card.Parent do
							TweenService:Create(cs, TweenInfo.new(0.6), { Thickness = (big and 6 or 5) }):Play(); task.wait(0.6)
							TweenService:Create(cs, TweenInfo.new(0.6), { Thickness = (big and 3 or 2.5) }):Play(); task.wait(0.6)
						end
					end)
				end
			end)
		end

		local hint = Instance.new("TextLabel"); hint.AnchorPoint = Vector2.new(0.5, 1)
		hint.Position = UDim2.new(0.5, 0, 1, -22); hint.Size = UDim2.new(0, 420, 0, 20)
		hint.BackgroundTransparency = 1; hint.Font = Enum.Font.Gotham; hint.TextSize = 13
		hint.Text = "Bấm để đóng"; hint.TextColor3 = Color3.fromRGB(170, 178, 195); hint.ZIndex = 90; hint.Parent = ov

		local closeBtn = Instance.new("TextButton"); closeBtn.Size = UDim2.fromScale(1, 1)
		closeBtn.BackgroundTransparency = 1; closeBtn.Text = ""; closeBtn.ZIndex = 80; closeBtn.Parent = ov
		local closed = false
		local function doClose()
			if closed then return end; closed = true
			TweenService:Create(ov, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
			Debris:AddItem(ov, 0.3)
		end
		closeBtn.Activated:Connect(doClose)
		task.delay((#list - 1) * 0.08 + 5, doClose)
	end

	TweenService:Create(beam, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 22, 1, 0), BackgroundTransparency = 0,
	}):Play()
	skip.Activated:Connect(reveal)
	task.delay(1.35, reveal)
end

-- Server trả kết quả: (ok, reward|nil, freeRemaining, reason, pityInfo).
-- reward.multi=true -> reward.rolls là mảng 10 kết quả. reason = "playing"|"cooldown"|"nogem".
Remotes.OpenChest.OnClientEvent:Connect(function(ok, reward, freeLeft, reason, pityInfo)
	chestRemaining = freeLeft or 0
	if pityInfo and pityInfo.max then
		local left = math.max(0, (pityInfo.max or 0) - (pityInfo.n or 0))
		pityLabel.Text = left <= 0 and "✨ Lượt tới CHẮC CHẮN ra Epic!"
			or ("🔮 Cầu Epic đảm bảo sau %d lượt"):format(left)
	end
	if ok and reward then
		local list = reward.multi and reward.rolls or { reward }
		playGenshinReveal(list) -- hiệu ứng gacha kiểu Genshin
		if reward.multi then
			-- Gộp tóm tắt cho dòng chữ dưới panel (đếm mới/trùng + con hiếm nhất).
			local newN, best = 0, "Common"
			for _, r in ipairs(list) do
				if r.isNew then newN += 1 end
				if (RARITY_RANK[r.rarity] or 1) > (RARITY_RANK[best] or 1) then best = r.rarity end
			end
			reward.isNew = newN > 0
			reward.name = ("Roll ×10 — %d mới · %d trùng · hiếm nhất %s"):format(newN, #list - newN, best)
			reward.rarity = ""
			reward.color = nil
		end
		if reward.isNew then
			chestReward.Text = ("🚀 TÀU MẸ MỚI!\n%s (%s)"):format(reward.name, reward.rarity or "")
		else
			chestReward.Text = ("Trùng: %s (đã sở hữu)"):format(reward.name)
		end
		chestReward.TextColor3 = reward.color or CHEST_GOLD
	elseif reason == "nogem" then
		chestReward.Text = ("Không đủ Gem (cần %d 💎)"):format(GEM_COST)
		chestReward.TextColor3 = Color3.fromRGB(255, 170, 170)
	elseif reason == "cooldown" then
		chestReward.Text = "Lượt free đang hồi — dùng Gem để roll ngay!"
		chestReward.TextColor3 = Color3.fromRGB(210, 220, 235)
	end
	refreshChest()
end)

-------------------------------------------------------------------------------
-- GIFTS: thang thưởng theo THỜI GIAN ONLINE phiên (nút 🎁). Mốc chưa tới -> tối
-- + 🔒 + đếm ngược; tới mốc -> sáng, bấm nhận (server xác thực & chống trùng).
-------------------------------------------------------------------------------
local GIFTS = Config.GIFTS or {}
local giftClaimed = {}          -- [index]=true (đã nhận trong phiên)
local giftStart = os.clock()    -- mốc client tính active-time (~lúc vào)
local function activeTime() return os.clock() - giftStart end

local function comma(n)
	local s = tostring(math.floor(n))
	s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return s
end
local function fmtTime(sec)
	sec = math.max(0, math.floor(sec))
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
	return ("%d:%02d"):format(m, s)
end

local giftsGui = Instance.new("Frame")
giftsGui.Size = UDim2.new(1, 0, 1, 0); giftsGui.BackgroundColor3 = Color3.new(0, 0, 0)
giftsGui.BackgroundTransparency = 0.45; giftsGui.Visible = false; giftsGui.ZIndex = 60; giftsGui.Parent = gui
local giftsDim = Instance.new("TextButton") -- bấm nền để đóng
giftsDim.Size = UDim2.new(1, 0, 1, 0); giftsDim.BackgroundTransparency = 1; giftsDim.Text = ""
giftsDim.AutoButtonColor = false; giftsDim.ZIndex = 60; giftsDim.Parent = giftsGui

local giftPanel = Instance.new("Frame")
giftPanel.AnchorPoint = Vector2.new(0.5, 0.5); giftPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
giftPanel.Size = UDim2.new(0, 636, 0, 520); giftPanel.BackgroundColor3 = PANEL_BG
giftPanel.ZIndex = 61; giftPanel.Parent = giftsGui
local gpc = Instance.new("UICorner"); gpc.CornerRadius = UDim.new(0, 18); gpc.Parent = giftPanel
local gps = Instance.new("UIStroke"); gps.Thickness = 2; gps.Color = Color3.fromRGB(90, 180, 255); gps.Transparency = 0.4; gps.Parent = giftPanel

local giftTitle = Instance.new("TextLabel")
giftTitle.Position = UDim2.new(0, 0, 0, 14); giftTitle.Size = UDim2.new(1, 0, 0, 34)
giftTitle.BackgroundTransparency = 1; giftTitle.Font = Enum.Font.GothamBlack; giftTitle.TextSize = 26
giftTitle.Text = "🎁 GIFTS"; giftTitle.TextColor3 = Color3.fromRGB(120, 200, 255); giftTitle.ZIndex = 62
giftTitle.Parent = giftPanel
local giftSub = Instance.new("TextLabel")
giftSub.Position = UDim2.new(0, 0, 0, 44); giftSub.Size = UDim2.new(1, 0, 0, 18)
giftSub.BackgroundTransparency = 1; giftSub.Font = Enum.Font.Gotham; giftSub.TextSize = 13
giftSub.Text = "Phần thưởng mở dần theo thời gian online phiên này."
giftSub.TextColor3 = Color3.fromRGB(170, 180, 200); giftSub.ZIndex = 62; giftSub.Parent = giftPanel

local giftClose = Instance.new("TextButton")
giftClose.AnchorPoint = Vector2.new(1, 0); giftClose.Position = UDim2.new(1, -12, 0, 12)
giftClose.Size = UDim2.new(0, 30, 0, 30); giftClose.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
giftClose.Text = "✕"; giftClose.Font = Enum.Font.GothamBold; giftClose.TextSize = 16
giftClose.TextColor3 = Color3.new(1, 1, 1); giftClose.ZIndex = 63; giftClose.Parent = giftPanel
local gcc = Instance.new("UICorner"); gcc.CornerRadius = UDim.new(0, 8); gcc.Parent = giftClose

local giftGrid = Instance.new("Frame")
giftGrid.Position = UDim2.new(0, 20, 0, 74); giftGrid.Size = UDim2.new(1, -40, 1, -90)
giftGrid.BackgroundTransparency = 1; giftGrid.ZIndex = 61; giftGrid.Parent = giftPanel
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0, 138, 0, 138); grid.CellPadding = UDim2.new(0, 10, 0, 10)
grid.SortOrder = Enum.SortOrder.LayoutOrder; grid.Parent = giftGrid

-- Dựng 12 ô quà
local giftTiles = {}
for i, g in ipairs(GIFTS) do
	local isGem = (g.kind == "gem")
	local tile = Instance.new("TextButton")
	tile.LayoutOrder = i; tile.Text = ""; tile.AutoButtonColor = false
	tile.BackgroundColor3 = Color3.fromRGB(40, 90, 150); tile.ZIndex = 62; tile.Parent = giftGrid
	local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 12); tc.Parent = tile
	local tsk = Instance.new("UIStroke"); tsk.Thickness = 1.5; tsk.Transparency = 0.4
	tsk.Color = Color3.fromRGB(80, 140, 210); tsk.Parent = tile

	local icon = Instance.new("TextLabel")
	icon.AnchorPoint = Vector2.new(0.5, 0); icon.Position = UDim2.new(0.5, 0, 0, 14)
	icon.Size = UDim2.new(0, 74, 0, 74); icon.BackgroundTransparency = 1; icon.TextScaled = true
	icon.Font = Enum.Font.GothamBold; icon.Text = isGem and "💎" or "◈"
	icon.TextColor3 = isGem and Color3.fromRGB(150, 230, 255) or Color3.fromRGB(255, 220, 120)
	icon.ZIndex = 63; icon.Parent = tile

	local amt = Instance.new("TextLabel")
	amt.AnchorPoint = Vector2.new(0.5, 1); amt.Position = UDim2.new(0.5, 0, 1, -10)
	amt.Size = UDim2.new(1, -8, 0, 24); amt.BackgroundTransparency = 1; amt.Font = Enum.Font.GothamBlack
	amt.TextSize = 18; amt.Text = "+" .. comma(g.amount)
	amt.TextColor3 = Color3.new(1, 1, 1); amt.ZIndex = 63; amt.Parent = tile

	local lock = Instance.new("TextLabel")
	lock.Position = UDim2.new(0, 6, 0, 4); lock.Size = UDim2.new(0, 22, 0, 22)
	lock.BackgroundTransparency = 1; lock.Font = Enum.Font.GothamBold; lock.TextSize = 18
	lock.Text = "🔒"; lock.TextColor3 = Color3.fromRGB(255, 210, 90); lock.ZIndex = 64; lock.Parent = tile

	local timer = Instance.new("TextLabel")
	timer.AnchorPoint = Vector2.new(1, 0); timer.Position = UDim2.new(1, -6, 0, 4)
	timer.Size = UDim2.new(0, 80, 0, 20); timer.BackgroundTransparency = 1
	timer.Font = Enum.Font.GothamBold; timer.TextSize = 15; timer.TextXAlignment = Enum.TextXAlignment.Right
	timer.Text = ""; timer.TextColor3 = Color3.new(1, 1, 1); timer.ZIndex = 64; timer.Parent = tile

	tile.Activated:Connect(function()
		if giftClaimed[i] then return end
		if activeTime() < g.at then return end -- chưa tới mốc (server cũng chặn)
		Remotes.ClaimGift:FireServer(i)
	end)

	giftTiles[i] = { tile = tile, icon = icon, amt = amt, lock = lock, timer = timer, stroke = tsk, gift = g }
end

local function refreshGifts()
	local now = activeTime()
	for i, t in ipairs(giftTiles) do
		local g = t.gift
		if giftClaimed[i] then
			-- ĐÃ NHẬN: xanh lá + dấu ✓
			t.tile.BackgroundColor3 = Color3.fromRGB(50, 110, 60)
			t.stroke.Color = Color3.fromRGB(120, 220, 130)
			t.lock.Visible = false; t.timer.Text = "✓"; t.timer.TextColor3 = Color3.fromRGB(150, 255, 160)
			t.icon.TextTransparency = 0.3; t.amt.TextTransparency = 0.3
		elseif now >= g.at then
			-- SẴN SÀNG: sáng
			t.tile.BackgroundColor3 = Color3.fromRGB(45, 130, 210)
			t.stroke.Color = Color3.fromRGB(150, 210, 255)
			t.lock.Visible = false; t.timer.Text = "NHẬN"; t.timer.TextColor3 = Color3.fromRGB(200, 255, 210)
			t.icon.TextTransparency = 0; t.amt.TextTransparency = 0
		else
			-- KHÓA: tối + 🔒 + đếm ngược
			t.tile.BackgroundColor3 = Color3.fromRGB(34, 46, 64)
			t.stroke.Color = Color3.fromRGB(60, 74, 100)
			t.lock.Visible = true
			t.timer.Text = fmtTime(g.at - now); t.timer.TextColor3 = Color3.fromRGB(230, 236, 250)
			t.icon.TextTransparency = 0.55; t.amt.TextTransparency = 0.4
		end
	end
end

openGifts = function()
	refreshGifts()
	giftsGui.Visible = true
end
local function closeGifts() giftsGui.Visible = false end
giftClose.Activated:Connect(closeGifts)
giftsDim.Activated:Connect(closeGifts)

-- Server trả kết quả nhận quà.
Remotes.ClaimGift.OnClientEvent:Connect(function(index, ok, kind, amount)
	if ok then
		giftClaimed[index] = true
		showToast(("Đã nhận +%s %s"):format(comma(amount), kind == "gem" and "💎" or "◈ Scrap"))
	else
		showToast("Chưa tới lúc nhận quà này")
	end
	if giftsGui.Visible then refreshGifts() end
end)

-------------------------------------------------------------------------------
-- Phát hiện Tàu Mẹ vào vùng cổng 3D
-------------------------------------------------------------------------------
local function myShip()
	local f = Workspace:FindFirstChild("Motherships")
	return f and f:FindFirstChild("Mothership_" .. uid) or nil
end
local function zoneAt(pos)
	for _, z in ipairs(ZONES) do
		local dx, dz = pos.X - z.x, pos.Z - z.z
		if dx * dx + dz * dz <= R2 then return z end
	end
	return nil
end

local current = nil
local function applyZone(z)
	if z == current then return end
	current = z
	if not z then
		shop.Visible = false
		chestPanel.Visible = false
	elseif z.id == "gate" then
		shop.Visible = false
		chestPanel.Visible = false
		if not requestedMatch then           -- vào cổng -> tự vào trận ngay
			requestedMatch = true
			showToast("Đang vào trận...")
			Remotes.StartMatch:FireServer()
		end
	elseif z.id == "class" then
		-- Zone TÀU MẸ = rương gacha (mở hòm roll Tàu Mẹ + xem tỉ lệ).
		shop.Visible = false
		chestPanel.Visible = true
		refreshChest()
	else
		chestPanel.Visible = false
		shop.Visible = true
		shopTitle.Text = z.label; shopTitle.TextColor3 = z.color
		shopBody.Text = SHOP_BODY[z.id] or "Sắp có"
		local st = shop:FindFirstChildOfClass("UIStroke"); if st then st.Color = z.color end
	end
end

local acc = 0
RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then return end
	-- Đếm lùi hồi chiêu rương (mượt từng frame; server đã đặt mốc chuẩn).
	if chestRemaining > 0 then
		chestRemaining = math.max(0, chestRemaining - dt)
		if chestPanel.Visible then refreshChest() end
	end
	acc += dt
	if acc < 0.1 then return end
	acc = 0
	if giftsGui.Visible then refreshGifts() end -- cập nhật đếm ngược quà
	local ship = myShip()
	if ship then applyZone(zoneAt(ship.Position)) end
end)

-------------------------------------------------------------------------------
-- Ẩn/hiện lobby theo trạng thái trận
-------------------------------------------------------------------------------
Remotes.MatchState.OnClientEvent:Connect(function(s)
	if s == "playing" then
		gui.Enabled = false; applyZone(nil)
	else
		gui.Enabled = true
		requestedMatch = false -- cho phép vào cổng khởi trận lại
		current = nil          -- đánh giá lại vùng ở tick kế
	end
end)
