--[[
	EnemyHealthReveal.client.luau
	-----------------------------
	Ẩn thanh máu (HealthBar) ở XA; chỉ hiện khi Tàu Mẹ của MÌNH cách <= REVEAL studs.
	Áp cho:
	  • Tàu Mẹ (folder Motherships) — tàu của MÌNH luôn hiện.
	  • Công trình: mỏ / hub / tháp (folder Buildings).
	(Quân trong folder Units không có thanh máu riêng nên bỏ qua.)

	Thuần client (mỗi người thấy khác nhau tuỳ vị trí). Chỉ bật/tắt Enabled của
	BillboardGui đã replicate — không đụng server, không xoá gì.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local player = Players.LocalPlayer
local myName = "Mothership_" .. player.UserId
local REVEAL = (Config.CAMERA and Config.CAMERA.ENEMY_HP_REVEAL_DIST) or 250

local motherships = Workspace:WaitForChild("Motherships")

-- Toggle mọi HealthBar trong `folder` theo khoảng cách tới myPos.
-- alwaysOwn = true -> Tàu Mẹ của mình luôn hiện (bỏ qua khoảng cách).
local function gateFolder(folder, myPos, reveal2, alwaysOwn)
	if not folder then return end
	for _, part in ipairs(folder:GetChildren()) do
		if part:IsA("BasePart") then
			local hb = part:FindFirstChild("HealthBar")
			if hb then
				if alwaysOwn and part.Name == myName then
					hb.Enabled = true
				elseif myPos then
					local dx = part.Position.X - myPos.X
					local dz = part.Position.Z - myPos.Z
					hb.Enabled = (dx * dx + dz * dz) <= reveal2
				else
					hb.Enabled = false -- mình chưa có tàu -> ẩn hết cho gọn
				end
			end
		end
	end
end

-- Throttle ~7Hz.
local accum = 0
RunService.RenderStepped:Connect(function(dt)
	accum += dt
	if accum < 0.15 then return end
	accum = 0

	local myShip = motherships:FindFirstChild(myName)
	local myPos = myShip and myShip.Position or nil
	local reveal2 = REVEAL * REVEAL

	gateFolder(motherships, myPos, reveal2, true)
	gateFolder(Workspace:FindFirstChild("Buildings"), myPos, reveal2, false)
end)
