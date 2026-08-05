--[[
	PickupSystem.luau
	-----------------
	Scrap rải rác + "mỏ" (cụm scrap) trên map, hút vào Tàu Mẹ khi tới gần.

	- Khởi tạo: rải CLUSTER_COUNT "mỏ" (cụm dày, giá trị cao) + bù orb lẻ cho đủ
	  TARGET_COUNT. Định kỳ respawn orb lẻ để map luôn có scrap.
	- Mỗi Heartbeat:
	    * orb chưa bị hút: nếu có Tàu Mẹ trong MAGNET_RANGE -> gán flyingTo.
	    * orb đang bay: lerp về phía Tàu Mẹ (FLY_SPEED), nhỏ dần; tới COLLECT_DIST
	      thì cộng scrap cho chủ + huỷ orb (hiệu ứng "bay vào").
	- Ai cũng hút được (player + bot) -> công bằng cho M5.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Util = require(ReplicatedStorage.Util)
local GameState = require(script.Parent.GameState)
local EconomySystem = require(script.Parent.EconomySystem)

local PickupSystem = {}

local folder
local ORB_Y = 3 -- độ cao orb lơ lửng trên mặt map

local function randRange(a, b)
	return a + math.random() * (b - a)
end

local function makeOrb(x, z, value)
	local orb = Instance.new("Part")
	orb.Name = "Scrap"
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CastShadow = false
	orb.Shape = Enum.PartType.Ball
	-- orb to/nhỏ theo giá trị cho dễ đọc
	local s = 1.6 + value / 25
	orb.Size = Vector3.new(s, s, s)
	orb.Position = Vector3.new(x, ORB_Y, z)
	orb.Color = Color3.fromRGB(255, 210, 80)
	orb.Material = Enum.Material.Neon
	orb.Parent = folder

	table.insert(GameState.pickups, { part = orb, value = value, flyingTo = nil, baseSize = s })
end

-- Rải 1 orb lẻ ở vị trí ngẫu nhiên trong map (chừa mép).
local function spawnRandomOrb()
	local half = Config.MAP.SIZE / 2 - 30
	makeOrb(
		math.random(-half, half),
		math.random(-half, half),
		math.floor(randRange(Config.PICKUP.VALUE_MIN, Config.PICKUP.VALUE_MAX))
	)
end

-- Rải 1 "mỏ": cụm orb giá trị cao quanh 1 tâm ngẫu nhiên.
local function spawnCluster()
	local half = Config.MAP.SIZE / 2 - 60
	local cx, cz = math.random(-half, half), math.random(-half, half)
	for _ = 1, Config.PICKUP.CLUSTER_SIZE do
		local ox = randRange(-Config.PICKUP.CLUSTER_SPREAD, Config.PICKUP.CLUSTER_SPREAD)
		local oz = randRange(-Config.PICKUP.CLUSTER_SPREAD, Config.PICKUP.CLUSTER_SPREAD)
		makeOrb(cx + ox, cz + oz,
			math.floor(randRange(Config.PICKUP.CLUSTER_VALUE_MIN, Config.PICKUP.CLUSTER_VALUE_MAX)))
	end
end

local function spawnInitial()
	for _ = 1, Config.PICKUP.CLUSTER_COUNT do
		spawnCluster()
	end
	while #GameState.pickups < Config.PICKUP.TARGET_COUNT do
		spawnRandomOrb()
	end
end

-- Tìm Tàu Mẹ gần orb nhất trong tầm hút.
local function nearestMothershipInMagnet(pos)
	local best, bestD
	for _, e in pairs(GameState.motherships) do
		if e.alive and e.part then
			local d = (e.part.Position - pos).Magnitude
			if d <= Config.PICKUP.MAGNET_RANGE and (not bestD or d < bestD) then
				best, bestD = e, d
			end
		end
	end
	return best
end

local function updatePickups(dt)
	for i = #GameState.pickups, 1, -1 do
		local p = GameState.pickups[i]
		if not p.part or not p.part.Parent then
			table.remove(GameState.pickups, i)
		elseif p.flyingTo then
			local owner = GameState.motherships[p.flyingTo]
			if not owner or not owner.alive or not owner.part then
				p.flyingTo = nil -- mất chủ -> nằm lại
			else
				local pos = p.part.Position
				local target = owner.part.Position
				local delta = target - pos
				local dist = delta.Magnitude
				if dist <= Config.PICKUP.COLLECT_DIST then
					-- Thu: cộng scrap + huỷ orb
					EconomySystem.add(p.flyingTo, p.value)
					p.part:Destroy()
					table.remove(GameState.pickups, i)
				else
					local step = math.min(Config.PICKUP.FLY_SPEED * dt, dist)
					p.part.Position = pos + delta.Unit * step
					-- Nhỏ dần khi lại gần cho cảm giác "hút vào"
					local shrink = math.clamp(dist / Config.PICKUP.MAGNET_RANGE, 0.25, 1)
					p.part.Size = Vector3.new(p.baseSize, p.baseSize, p.baseSize) * shrink
				end
			end
		else
			local owner = nearestMothershipInMagnet(p.part.Position)
			if owner then
				p.flyingTo = owner.ownerId
			end
		end
	end
end

function PickupSystem.clearAll()
	for i = #GameState.pickups, 1, -1 do
		local p = GameState.pickups[i]
		if p.part then p.part:Destroy() end
		GameState.pickups[i] = nil
	end
end

function PickupSystem.reset()
	PickupSystem.clearAll()
	spawnInitial()
end

function PickupSystem.init()
	folder = Instance.new("Folder")
	folder.Name = "Scrap"
	folder.Parent = Workspace

	spawnInitial()

	RunService.Heartbeat:Connect(updatePickups)

	-- Bù orb lẻ định kỳ để map luôn có scrap
	task.spawn(function()
		while true do
			task.wait(Config.PICKUP.RESPAWN_INTERVAL)
			local need = Config.PICKUP.TARGET_COUNT - #GameState.pickups
			for _ = 1, math.min(need, Config.PICKUP.RESPAWN_BATCH) do
				spawnRandomOrb()
			end
		end
	end)

	print("[PickupSystem] ready")
end

return PickupSystem
