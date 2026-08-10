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

-- Đạn bay (Lordz): mỗi client TỰ vẽ 1 viên neon bay thẳng rồi tự huỷ. Damage/va chạm
-- do server tính riêng -> đây chỉ là hình ảnh (fire-and-forget, không replicate chuyển động).
Remotes.ProjectileVFX.OnClientEvent:Connect(function(origin, dir, speed, range, radius, color)
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or dir.Magnitude < 1e-3 then return end
	dir = dir.Unit
	speed = tonumber(speed) or 90
	range = tonumber(range) or 40
	radius = tonumber(radius) or 1.6
	local life = math.clamp(range / speed, 0.05, 3)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color or Color3.new(1, 1, 1)
	p.Size = Vector3.new(radius * 1.3, radius * 1.3, math.max(radius * 1.9, 3)) -- to -> orb nặng
	p.CFrame = CFrame.lookAt(origin, origin + dir)
	p.Parent = vfxFolder
	local endPos = origin + dir * range
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(endPos, endPos + dir),
	}):Play()
	Debris:AddItem(p, life + 0.05)
	-- Loé va chạm nhỏ tại điểm đạn tới (đọc là "trúng", không xuyên qua).
	task.delay(life, function()
		local f = Instance.new("Part")
		f.Anchored = true; f.CanCollide = false; f.CanQuery = false; f.CastShadow = false
		f.Shape = Enum.PartType.Ball; f.Material = Enum.Material.Neon
		f.Color = color or Color3.new(1, 1, 1)
		f.Size = Vector3.new(radius * 2.4, radius * 2.4, radius * 2.4)
		f.CFrame = CFrame.new(endPos)
		f.Parent = vfxFolder
		TweenService:Create(f, TweenInfo.new(0.12), { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 }):Play()
		Debris:AddItem(f, 0.16)
	end)
end)

-- BLAST vòng cung (Battleship): sóng năng lượng hình LƯỠI LIỀM bung ra trước mặt rồi
-- lan tới tầm range, phình to + mờ dần (to ở tâm cung, nhỏ ra mép -> dáng crescent).
Remotes.ConeBlast.OnClientEvent:Connect(function(origin, dir, range, angle, color)
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or dir.Magnitude < 1e-3 then return end
	dir = dir.Unit
	range = tonumber(range) or 42
	angle = tonumber(angle) or 1.2
	local baseAng = math.atan2(dir.Z, dir.X)
	local col = color or Color3.fromRGB(225, 70, 240)
	local startR = 8
	local M = 13
	for i = 0, M - 1 do
		local frac = (M == 1) and 0 or (i / (M - 1) - 0.5) -- -0.5..0.5 dọc cung
		local a = baseAng + frac * angle
		local d = Vector3.new(math.cos(a), 0, math.sin(a))
		local w = 3 + 7 * (1 - math.min(1, math.abs(frac) * 2)) -- to ở tâm, nhỏ ở mép
		local ball = Instance.new("Part")
		ball.Anchored = true; ball.CanCollide = false; ball.CanQuery = false; ball.CastShadow = false
		ball.Shape = Enum.PartType.Ball
		ball.Material = Enum.Material.Neon
		ball.Color = col
		ball.Transparency = 0.1
		ball.Size = Vector3.new(w, w, w)
		ball.CFrame = CFrame.new(origin + d * startR)
		ball.Parent = vfxFolder
		TweenService:Create(ball, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(origin + d * range),
			Size = Vector3.new(w * 1.8, w * 1.8, w * 1.8),
			Transparency = 1,
		}):Play()
		Debris:AddItem(ball, 0.34)
	end
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
