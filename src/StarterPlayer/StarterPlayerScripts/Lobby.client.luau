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
local function sideButton(parent, order, icon, label, badge)
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
	b.Activated:Connect(function() showToast(label .. " — Sắp có (Phase sau)") end)
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
sideButton(leftBar, 2, "🎒", "Bag", false)

local rightBar = sideBar("right")
sideButton(rightBar, 1, "🎁", "Gifts", true)
sideButton(rightBar, 2, "✔", "Quest", true)
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
chestPanel.Size = UDim2.new(0, 420, 0, 360); chestPanel.BackgroundColor3 = PANEL_BG; chestPanel.Visible = false
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

local chestBtn = Instance.new("TextButton")
chestBtn.AnchorPoint = Vector2.new(0.5, 1); chestBtn.Position = UDim2.new(0.5, 0, 1, -18)
chestBtn.Size = UDim2.new(0, 220, 0, 48); chestBtn.BackgroundColor3 = Color3.fromRGB(210, 160, 40)
chestBtn.Font = Enum.Font.GothamBlack; chestBtn.TextSize = 18; chestBtn.Text = "MỞ RƯƠNG"
chestBtn.TextColor3 = Color3.fromRGB(30, 24, 10); chestBtn.Parent = chestPanel
local cbtc = Instance.new("UICorner"); cbtc.CornerRadius = UDim.new(0, 10); cbtc.Parent = chestBtn

local function refreshChest()
	if chestRemaining > 0 then
		chestBtn.AutoButtonColor = false
		chestBtn.BackgroundColor3 = Color3.fromRGB(70, 74, 88)
		chestBtn.TextColor3 = Color3.fromRGB(180, 188, 205)
		chestBtn.Text = ("Chờ hồi ⏳ %ds"):format(math.ceil(chestRemaining))
	else
		chestBtn.AutoButtonColor = true
		chestBtn.BackgroundColor3 = Color3.fromRGB(210, 160, 40)
		chestBtn.TextColor3 = Color3.fromRGB(30, 24, 10)
		chestBtn.Text = "MỞ RƯƠNG"
	end
end

chestBtn.Activated:Connect(function()
	if chestRemaining > 0 then return end
	Remotes.OpenChest:FireServer()
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

-- Server trả kết quả mở rương: (ok, reward{isNew,name,rarity,color}|nil, cooldown).
Remotes.OpenChest.OnClientEvent:Connect(function(ok, reward, cooldown)
	chestRemaining = cooldown or 0
	if ok and reward then
		playGachaReveal(reward) -- hiệu ứng gacha
		if reward.isNew then
			chestReward.Text = ("🚀 TÀU MẸ MỚI!\n%s\n(%s)"):format(reward.name, reward.rarity or "")
		else
			chestReward.Text = ("Trùng: %s\n(đã sở hữu — chờ con mới)"):format(reward.name)
		end
		chestReward.TextColor3 = reward.color or CHEST_GOLD
	elseif not ok and (cooldown or 0) > 0 then
		chestReward.Text = "Rương đang hồi. Quay lại sau nhé!"
		chestReward.TextColor3 = Color3.fromRGB(210, 220, 235)
	end
	refreshChest()
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
