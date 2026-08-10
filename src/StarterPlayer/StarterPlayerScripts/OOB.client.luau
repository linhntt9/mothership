--[[
	OOB.client.luau
	---------------
	Overlay khi Tàu Mẹ RA KHỎI RANH map (server báo qua Remotes.OOBWarn):
	  - Làm tối màn hình (càng gần chết càng tối) — vẫn thấy đường để lái về.
	  - Đồng hồ đếm ngược + "Return to Battlegrounds!".
	remaining > 0 -> hiện; 0/nil -> ẩn (đã về ranh an toàn).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local player = Players.LocalPlayer
local OOB_TIME = (Config.MAP and Config.MAP.OOB_TIME) or 6

local gui = Instance.new("ScreenGui")
gui.Name = "OOBWarn"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local dark = Instance.new("Frame")
dark.Size = UDim2.fromScale(1, 1)
dark.BackgroundColor3 = Color3.new(0, 0, 0)
dark.BackgroundTransparency = 0.5
dark.BorderSizePixel = 0
dark.Parent = gui

local count = Instance.new("TextLabel")
count.AnchorPoint = Vector2.new(0.5, 0.5)
count.Position = UDim2.fromScale(0.5, 0.42)
count.Size = UDim2.fromOffset(220, 130)
count.BackgroundTransparency = 1
count.Font = Enum.Font.GothamBlack
count.TextSize = 96
count.TextColor3 = Color3.fromRGB(255, 90, 90)
count.Text = "5"
count.Parent = gui

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.6)
title.Size = UDim2.fromOffset(560, 46)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 30
title.TextColor3 = Color3.fromRGB(255, 235, 235)
title.Text = "Return to Battlegrounds!"
title.Parent = gui

Remotes.OOBWarn.OnClientEvent:Connect(function(remaining)
	remaining = tonumber(remaining) or 0
	if remaining > 0 then
		gui.Enabled = true
		count.Text = tostring(math.ceil(remaining))
		-- càng gần chết (remaining nhỏ) -> càng tối
		local frac = math.clamp(1 - remaining / OOB_TIME, 0, 1)
		dark.BackgroundTransparency = 0.55 - frac * 0.35
	else
		gui.Enabled = false
	end
end)
