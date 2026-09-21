--[[
	KillFeed.client.luau
	--------------------
	Thông báo trong trận: ai đã tiêu diệt ai (Tàu Mẹ bị hạ).
	Server bắn Remotes.KillFeed(killerName|nil, victimName) tới mọi người.
	Hiện danh sách góc trên giữa, mới nhất trên cùng, tự mờ sau vài giây.
	Tô màu khi CHÍNH MÌNH liên quan (mình hạ = xanh, mình bị hạ = đỏ).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Remotes)

local player = Players.LocalPlayer
local myName = player.Name

local HOLD = 5        -- giây hiện rõ trước khi mờ
local FADE = 1.0      -- giây mờ dần
local MAX = 6         -- tối đa số dòng cùng lúc

local gui = Instance.new("ScreenGui")
gui.Name = "KillFeed"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local list = Instance.new("Frame")
list.AnchorPoint = Vector2.new(0.5, 0)
list.Position = UDim2.new(0.5, 0, 0, 14)
list.Size = UDim2.new(0, 520, 0, 200)
list.BackgroundTransparency = 1
list.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 4)
layout.Parent = list

local counter = 0

local function involves(name)
	return name and string.find(name, myName, 1, true) ~= nil
end

local function addEntry(killer, victim)
	counter += 1
	local iAmKiller = involves(killer)
	local iAmVictim = involves(victim)

	local row = Instance.new("TextButton")   -- TextButton để KHÔNG kêu tiếng UI (không Activated tự nhiên)
	row.AutoButtonColor = false
	row.Active = false
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Size = UDim2.new(0, 0, 0, 26)
	row.LayoutOrder = -counter               -- mới nhất trên cùng
	row.BackgroundColor3 = iAmVictim and Color3.fromRGB(120, 30, 30)
		or (iAmKiller and Color3.fromRGB(30, 90, 45) or Color3.fromRGB(18, 22, 32))
	row.BackgroundTransparency = 0.15
	row.Font = Enum.Font.GothamBold
	row.TextSize = 15
	row.TextColor3 = Color3.fromRGB(255, 255, 255)
	row.RichText = true
	if killer and killer ~= "" then
		row.Text = string.format("  %s  <font color=\"#ff7a3c\">\u{2694}</font>  %s  ", killer, victim)
	else
		row.Text = string.format("  <font color=\"#ff7a3c\">\u{2620}</font>  %s bị tiêu diệt  ", victim)
	end
	row.Parent = list
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = row
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(0, 0, 0); st.Transparency = 0.5; st.Thickness = 1; st.Parent = row

	-- Giới hạn số dòng: xoá dòng cũ nhất (LayoutOrder lớn nhất về giá trị âm nhỏ nhất)
	local rows = {}
	for _, ch in ipairs(list:GetChildren()) do
		if ch:IsA("TextButton") then table.insert(rows, ch) end
	end
	if #rows > MAX then
		table.sort(rows, function(a, b) return a.LayoutOrder > b.LayoutOrder end) -- cũ nhất trước
		rows[1]:Destroy()
	end

	-- Giữ rồi mờ dần -> huỷ.
	task.delay(HOLD, function()
		if not row or not row.Parent then return end
		local info = TweenInfo.new(FADE)
		TweenService:Create(row, info, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		TweenService:Create(st, info, { Transparency = 1 }):Play()
		task.delay(FADE + 0.1, function()
			if row then row:Destroy() end
		end)
	end)
end

Remotes.KillFeed.OnClientEvent:Connect(function(killer, victim)
	if victim then addEntry(killer, victim) end
end)
