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
