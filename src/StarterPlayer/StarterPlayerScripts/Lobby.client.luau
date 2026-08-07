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
chestPanel.Size = UDim2.new(0, 400, 0, 250); chestPanel.BackgroundColor3 = PANEL_BG; chestPanel.Visible = false
local ccc = Instance.new("UICorner"); ccc.CornerRadius = UDim.new(0, 16); ccc.Parent = chestPanel
local ccs = Instance.new("UIStroke"); ccs.Thickness = 2; ccs.Color = CHEST_GOLD; ccs.Transparency = 0.25; ccs.Parent = chestPanel
chestPanel.Parent = gui

local chestTitle = Instance.new("TextLabel")
chestTitle.Position = UDim2.new(0, 0, 0, 16); chestTitle.Size = UDim2.new(1, 0, 0, 34)
chestTitle.BackgroundTransparency = 1; chestTitle.Font = Enum.Font.GothamBlack; chestTitle.TextSize = 24
chestTitle.Text = "🎁 RƯƠNG CLASS"; chestTitle.TextColor3 = CHEST_GOLD; chestTitle.Parent = chestPanel

local chestReward = Instance.new("TextLabel")
chestReward.Position = UDim2.new(0, 20, 0, 62); chestReward.Size = UDim2.new(1, -40, 0, 90)
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

-- Server trả kết quả mở rương: (ok, reward{isNew,name,rarity,color}|nil, cooldown).
Remotes.OpenChest.OnClientEvent:Connect(function(ok, reward, cooldown)
	chestRemaining = cooldown or 0
	if ok and reward then
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
	-- Rời vùng CLASS -> đóng panel Heroes.
	if current and current.id == "class" and (not z or z.id ~= "class") then
		ClientBus.openHeroes:Fire(false)
	end
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
		shop.Visible = false                 -- vùng CLASS mở panel Heroes riêng
		chestPanel.Visible = false
		ClientBus.openHeroes:Fire(true)
	elseif z.id == "chest" then
		shop.Visible = false                 -- vùng RƯƠNG mở panel thưởng
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
