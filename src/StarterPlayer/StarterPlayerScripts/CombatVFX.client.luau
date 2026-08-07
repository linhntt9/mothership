--[[
	CombatVFX.client.luau
	---------------------
	Vẽ tia laser khi server báo có phát bắn (Remotes.FireLaser).
	VFX thuần client: tạo 1 Part neon mảnh nối origin -> target, tự huỷ sau
	LASER_TIME giây. Damage đã do server xử lý, đây chỉ là hình ảnh.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local vfxFolder = Instance.new("Folder")
vfxFolder.Name = "LaserVFX"
vfxFolder.Parent = Workspace

Remotes.FireLaser.OnClientEvent:Connect(function(origin, target, color)
	if typeof(origin) ~= "Vector3" or typeof(target) ~= "Vector3" then return end
	local dist = (target - origin).Magnitude
	if dist < 0.1 then return end

	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = color or Color3.new(1, 1, 1)
	local thick = Config.COMBAT.LASER_THICK
	beam.Size = Vector3.new(thick, thick, dist)
	-- Trục Z của part chạy dọc origin->target (lookAt cho -Z hướng về target)
	beam.CFrame = CFrame.lookAt((origin + target) / 2, target)
	beam.Parent = vfxFolder

	Debris:AddItem(beam, Config.COMBAT.LASER_TIME)
end)

-- Telegraph nạp đạn Siege: tia mảnh phình to dần suốt `duration` rồi biến mất
-- (ngay sau đó server bắn phát chốt qua FireLaser).
Remotes.SiegeCharge.OnClientEvent:Connect(function(origin, target, color, duration)
	if typeof(origin) ~= "Vector3" or typeof(target) ~= "Vector3" then return end
	duration = tonumber(duration) or 0.5
	local dist = (target - origin).Magnitude
	if dist < 0.1 then return end

	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = color or Color3.new(1, 1, 1)
	beam.Transparency = 0.5
	beam.Size = Vector3.new(0.1, 0.1, dist)
	beam.CFrame = CFrame.lookAt((origin + target) / 2, target)
	beam.Parent = vfxFolder

	TweenService:Create(beam, TweenInfo.new(duration), {
		Size = Vector3.new(0.7, 0.7, dist),
		Transparency = 0,
	}):Play()
	Debris:AddItem(beam, duration + 0.05)
end)

-- Sóng xung Titan: cầu neon phình từ tâm ra bán kính rồi mờ dần.
Remotes.Shockwave.OnClientEvent:Connect(function(center, radius, color)
	if typeof(center) ~= "Vector3" then return end
	radius = tonumber(radius) or 18
	local orb = Instance.new("Part")
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CastShadow = false
	orb.Shape = Enum.PartType.Ball
	orb.Material = Enum.Material.Neon
	orb.Color = color or Color3.new(1, 1, 1)
	orb.Transparency = 0.4
	orb.Size = Vector3.new(2, 2, 2)
	orb.CFrame = CFrame.new(center)
	orb.Parent = vfxFolder
	TweenService:Create(orb, TweenInfo.new(0.4), {
		Size = Vector3.new(radius * 2, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(orb, 0.45)
end)
