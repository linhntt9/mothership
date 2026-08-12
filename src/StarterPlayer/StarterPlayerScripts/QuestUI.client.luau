--[[
	QuestUI.client.luau
	-------------------
	Panel Quests (mở bằng nút "Quest" ở sảnh — ClientBus.openQuests).
	3 tab: Daily / Weekly / Unique. Mỗi quest: tên + các mục tiêu (thanh tiến độ) +
	phần thưởng + nút NHẬN. Quest khoá (chuỗi) hiện mờ + 🔒. Đếm ngược reset trên đầu.

	State do server đẩy qua Remotes.QuestState (định kỳ + khi có tiến độ). Bấm NHẬN
	-> Remotes.ClaimQuest -> server xác thực & đẩy lại state.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local IS_TOUCH = game:GetService("UserInputService").TouchEnabled

local Remotes = require(ReplicatedStorage.Remotes)
local ClientBus = require(script.Parent.ClientBus)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GOLD = Color3.fromRGB(255, 210, 90)
local PANEL_BG = Color3.fromRGB(22, 26, 38)
local CARD_BG = Color3.fromRGB(32, 38, 54)

local state = nil          -- payload QuestState mới nhất
local stateClock = 0       -- os.clock() lúc nhận (để đếm ngược mượt)
local activeTab = "daily"

local function comma(n)
	local s = tostring(math.floor(n))
	s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return s
end

local function fmtReset(sec)
	sec = math.max(0, math.floor(sec))
	if sec >= 86400 then return ("%d ngày"):format(math.floor(sec / 86400)) end
	if sec >= 3600 then return ("%d giờ"):format(math.floor(sec / 3600)) end
	if sec >= 60 then return ("%d phút"):format(math.floor(sec / 60)) end
	return ("%d giây"):format(sec)
end

-------------------------------------------------------------------------------
-- GUI
-------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "QuestUI"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.DisplayOrder = 9; gui.Enabled = false
gui.Parent = playerGui

local dim = Instance.new("TextButton")
dim.Size = UDim2.new(1, 0, 1, 0); dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.45; dim.Text = ""; dim.AutoButtonColor = false; dim.ZIndex = 1; dim.Parent = gui

local panel = Instance.new("Frame")
if IS_TOUCH then
	panel.AnchorPoint = Vector2.new(0.5, 0); panel.Position = UDim2.new(0.5, 0, 0, 46)
	panel.Size = UDim2.new(0.9, 0, 0.82, 0)
	local szc = Instance.new("UISizeConstraint"); szc.MaxSize = Vector2.new(640, 500); szc.Parent = panel
else
	panel.AnchorPoint = Vector2.new(0.5, 0.5); panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0, 640, 0, 500)
end
panel.BackgroundColor3 = PANEL_BG; panel.ZIndex = 2; panel.Parent = gui
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 18); pc.Parent = panel
local ps = Instance.new("UIStroke"); ps.Thickness = 2; ps.Color = Color3.fromRGB(90, 180, 255); ps.Transparency = 0.4; ps.Parent = panel

local title = Instance.new("TextLabel")
title.Position = UDim2.new(0, 16, 0, 14); title.Size = UDim2.new(0, 240, 0, 32)
title.BackgroundTransparency = 1; title.Font = Enum.Font.GothamBlack; title.TextSize = 24
title.TextXAlignment = Enum.TextXAlignment.Left; title.Text = "📋 QUESTS"
title.TextColor3 = Color3.fromRGB(120, 200, 255); title.ZIndex = 3; title.Parent = panel

local resetLabel = Instance.new("TextLabel") -- đếm ngược reset (giữa)
resetLabel.AnchorPoint = Vector2.new(0.5, 0); resetLabel.Position = UDim2.new(0.5, 0, 0, 16)
resetLabel.Size = UDim2.new(0, 220, 0, 28); resetLabel.BackgroundTransparency = 1
resetLabel.Font = Enum.Font.GothamBold; resetLabel.TextSize = 20; resetLabel.Text = ""
resetLabel.TextColor3 = Color3.fromRGB(200, 220, 245); resetLabel.ZIndex = 3; resetLabel.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint = Vector2.new(1, 0); closeBtn.Position = UDim2.new(1, -12, 0, 12)
closeBtn.Size = UDim2.new(0, 30, 0, 30); closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeBtn.Text = "✕"; closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 16
closeBtn.TextColor3 = Color3.new(1, 1, 1); closeBtn.ZIndex = 4; closeBtn.Parent = panel
local cbc = Instance.new("UICorner"); cbc.CornerRadius = UDim.new(0, 8); cbc.Parent = closeBtn

-- Hàng tab
local tabRow = Instance.new("Frame")
tabRow.Position = UDim2.new(0, 16, 0, 54); tabRow.Size = UDim2.new(1, -32, 0, 34)
tabRow.BackgroundTransparency = 1; tabRow.ZIndex = 3; tabRow.Parent = panel
local tl = Instance.new("UIListLayout"); tl.FillDirection = Enum.FillDirection.Horizontal
tl.Padding = UDim.new(0, 8); tl.Parent = tabRow

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.new(0, 16, 0, 98); list.Size = UDim2.new(1, -32, 1, -114)
list.BackgroundTransparency = 1; list.BorderSizePixel = 0; list.ScrollBarThickness = 5
list.CanvasSize = UDim2.new(0, 0, 0, 0); list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ZIndex = 3; list.Parent = panel
local ll = Instance.new("UIListLayout"); ll.Padding = UDim.new(0, 8); ll.SortOrder = Enum.SortOrder.LayoutOrder
ll.Parent = list

-------------------------------------------------------------------------------
-- Card
-------------------------------------------------------------------------------
local function rewardText(r)
	if r.kind == "gem" then return "💎 +" .. comma(r.amount)
	elseif r.kind == "scrap" then return "◈ +" .. comma(r.amount)
	elseif r.kind == "both" then return ("💎 +%s\n◈ +%s"):format(comma(r.gem or 0), comma(r.scrap or 0)) end
	return ""
end

local function makeCard(order, q)
	local nObj = #q.objectives
	local h = 44 + nObj * 34 + 12
	local locked = q.locked
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, h); card.LayoutOrder = order
	card.BackgroundColor3 = CARD_BG; card.BackgroundTransparency = locked and 0.35 or 0
	card.ZIndex = 3; card.Parent = list
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 12); cc.Parent = card

	-- Tên
	local nm = Instance.new("TextLabel")
	nm.Position = UDim2.new(0, 14, 0, 8); nm.Size = UDim2.new(1, -180, 0, 24)
	nm.BackgroundTransparency = 1; nm.Font = Enum.Font.GothamBlack; nm.TextSize = 18
	nm.TextXAlignment = Enum.TextXAlignment.Left; nm.Text = (locked and "🔒 " or "") .. q.name
	nm.TextColor3 = locked and Color3.fromRGB(150, 158, 175) or Color3.fromRGB(120, 200, 255)
	nm.ZIndex = 4; nm.Parent = card

	-- Mục tiêu + thanh tiến độ
	for i, o in ipairs(q.objectives) do
		local y = 36 + (i - 1) * 34
		local lab = Instance.new("TextLabel")
		lab.Position = UDim2.new(0, 14, 0, y); lab.Size = UDim2.new(1, -330, 0, 16)
		lab.BackgroundTransparency = 1; lab.Font = Enum.Font.GothamMedium; lab.TextSize = 13
		lab.TextXAlignment = Enum.TextXAlignment.Left; lab.Text = "◆ " .. o.label
		lab.TextColor3 = Color3.fromRGB(210, 218, 232); lab.ZIndex = 4; lab.Parent = card

		local barBg = Instance.new("Frame")
		barBg.Position = UDim2.new(0, 14, 0, y + 17); barBg.Size = UDim2.new(1, -330, 0, 8)
		barBg.BackgroundColor3 = Color3.fromRGB(45, 52, 70); barBg.ZIndex = 4; barBg.Parent = card
		local bbc = Instance.new("UICorner"); bbc.CornerRadius = UDim.new(1, 0); bbc.Parent = barBg
		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(math.clamp(o.cur / o.target, 0, 1), 0, 1, 0)
		fill.BackgroundColor3 = Color3.fromRGB(90, 200, 255); fill.ZIndex = 5; fill.Parent = barBg
		local fbc = Instance.new("UICorner"); fbc.CornerRadius = UDim.new(1, 0); fbc.Parent = fill

		local prog = Instance.new("TextLabel")
		prog.AnchorPoint = Vector2.new(1, 0); prog.Position = UDim2.new(1, -262, 0, y)
		prog.Size = UDim2.new(0, 62, 0, 24); prog.BackgroundTransparency = 1
		prog.Font = Enum.Font.GothamBold; prog.TextSize = 13; prog.TextXAlignment = Enum.TextXAlignment.Right
		prog.Text = ("%d/%d"):format(o.cur, o.target); prog.TextColor3 = Color3.fromRGB(200, 210, 228)
		prog.ZIndex = 4; prog.Parent = card
	end

	-- Phần thưởng (phải)
	local rew = Instance.new("TextLabel")
	rew.AnchorPoint = Vector2.new(1, 0.5); rew.Position = UDim2.new(1, -128, 0.5, 0)
	rew.Size = UDim2.new(0, 110, 1, -16); rew.BackgroundTransparency = 1
	rew.Font = Enum.Font.GothamBold; rew.TextSize = 15; rew.TextXAlignment = Enum.TextXAlignment.Right
	rew.Text = rewardText(q.reward); rew.TextColor3 = GOLD; rew.ZIndex = 4; rew.Parent = card

	-- Nút NHẬN / trạng thái
	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0.5); btn.Position = UDim2.new(1, -12, 0.5, 0)
	btn.Size = UDim2.new(0, 104, 0, 40); btn.Font = Enum.Font.GothamBold; btn.TextSize = 14
	btn.TextColor3 = Color3.new(1, 1, 1); btn.AutoButtonColor = false; btn.ZIndex = 4; btn.Parent = card
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = btn

	if q.claimed then
		btn.Text = "✓ Đã nhận"; btn.BackgroundColor3 = Color3.fromRGB(60, 110, 66)
	elseif locked then
		btn.Text = "🔒 Khoá"; btn.BackgroundColor3 = Color3.fromRGB(58, 62, 76)
		btn.TextColor3 = Color3.fromRGB(170, 178, 195)
	elseif q.owned == false then
		btn.Text = "Cần sở hữu"; btn.BackgroundColor3 = Color3.fromRGB(58, 62, 76)
		btn.TextColor3 = Color3.fromRGB(170, 178, 195)
	elseif q.complete then
		btn.Text = "NHẬN"; btn.BackgroundColor3 = GOLD; btn.TextColor3 = Color3.fromRGB(30, 24, 10)
		btn.AutoButtonColor = true
		btn.Activated:Connect(function() Remotes.ClaimQuest:FireServer(q.id) end)
	else
		btn.Text = "Chưa xong"; btn.BackgroundColor3 = Color3.fromRGB(50, 56, 74)
		btn.TextColor3 = Color3.fromRGB(160, 168, 186)
	end
end

local function renderTab()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	if not state then return end
	local quests = state[activeTab] or {}
	for i, q in ipairs(quests) do makeCard(i, q) end
end

-------------------------------------------------------------------------------
-- Tabs
-------------------------------------------------------------------------------
local tabDefs = { { id = "daily", label = "Daily" }, { id = "weekly", label = "Weekly" }, { id = "unique", label = "Unique" } }
local tabButtons = {}
local function setTab(id)
	activeTab = id
	for tid, b in pairs(tabButtons) do
		local on = (tid == id)
		b.BackgroundColor3 = on and Color3.fromRGB(90, 180, 255) or Color3.fromRGB(40, 46, 62)
		b.TextColor3 = on and Color3.fromRGB(15, 18, 26) or Color3.fromRGB(200, 208, 224)
	end
	renderTab()
end
for i, t in ipairs(tabDefs) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 120, 1, 0); b.LayoutOrder = i; b.Font = Enum.Font.GothamBold
	b.TextSize = 15; b.Text = t.label; b.ZIndex = 4; b.Parent = tabRow
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 8); bc.Parent = b
	tabButtons[t.id] = b
	b.Activated:Connect(function() setTab(t.id) end)
end

-------------------------------------------------------------------------------
-- Reset countdown (đầu panel) — tick mỗi frame khi mở
-------------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	if not gui.Enabled or not state then return end
	if activeTab == "unique" then
		resetLabel.Text = "Vĩnh viễn"
		return
	end
	local base = (activeTab == "daily") and state.dailyResetIn or state.weeklyResetIn
	local remain = (base or 0) - (os.clock() - stateClock)
	resetLabel.Text = "Reset sau " .. fmtReset(remain)
end)

-------------------------------------------------------------------------------
-- Mở / đóng + nhận state
-------------------------------------------------------------------------------
local function close() gui.Enabled = false end
closeBtn.Activated:Connect(close)
dim.Activated:Connect(close)

ClientBus.openQuests.Event:Connect(function()
	setTab(activeTab)
	gui.Enabled = true
end)

Remotes.QuestState.OnClientEvent:Connect(function(payload)
	state = payload; stateClock = os.clock()
	if gui.Enabled then renderTab() end
end)

-- Vào trận thì đóng.
Remotes.MatchState.OnClientEvent:Connect(function(s)
	if s == "playing" then gui.Enabled = false end
end)
