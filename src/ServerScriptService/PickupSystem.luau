--[[
	PickupSystem.luau
	-----------------
	Scrap rải rác + "mỏ" (cụm scrap) trên map, hút vào Tàu Mẹ khi tới gần.

	- Khởi tạo: rải các "mỏ" (cụm dày, giá trị cao) + bù orb lẻ cho đủ mật độ.
	  Số lượng = MẬT ĐỘ (Config.PICKUP.*_PER_100K) x diện tích map -> tự co giãn
	  theo MAP.SIZE. Định kỳ respawn orb lẻ để map luôn có scrap.
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
local MatchState = require(script.Parent.MatchState)

local PickupSystem = {}

local folder
local ORB_Y = 3 -- độ cao orb lơ lửng trên mặt map

-- Số lượng scrap tính theo MẬT ĐỘ x DIỆN TÍCH map -> tự co giãn khi đổi MAP.SIZE.
local function areaUnits()
	return (Config.MAP.SIZE * Config.MAP.SIZE) / 100000 -- số "đơn vị 100k studs²"
end
local function targetOrbs()
	return math.floor(areaUnits() * Config.PICKUP.SCRAP_PER_100K + 0.5)
end
local function clusterCount()
	return math.max(0, math.floor(areaUnits() * Config.PICKUP.CLUSTER_PER_100K + 0.5))
end

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

-- === RẢI ĐỀU (jittered grid / stratified) ===
-- Chia map thành lưới ~N ô, mỗi ô 1 điểm ở giữa + lệch ngẫu nhiên trong ô. Phủ
-- ĐỀU khắp map (không vón cục như random thuần) nhưng vẫn trông tự nhiên.
local JITTER = 0.85 -- mức lệch trong ô (0 = đúng tâm ô/rất đều, 1 = tràn cả ô)

local function gridCols(count)
	return math.max(1, math.ceil(math.sqrt(math.max(1, count))))
end

-- Trả về `count` điểm {x,z} rải đều: xáo danh sách ô rồi lấy đủ count ô khắp map.
local function evenPoints(count, margin)
	local pts = {}
	if count <= 0 then return pts end
	local half = Config.MAP.SIZE / 2 - margin
	local cols = gridCols(count)
	local cell = (half * 2) / cols
	local cells = {}
	for gx = 0, cols - 1 do
		for gz = 0, cols - 1 do
			cells[#cells + 1] = { gx, gz }
		end
	end
	for i = #cells, 2, -1 do -- xáo Fisher-Yates
		local j = math.random(i)
		cells[i], cells[j] = cells[j], cells[i]
	end
	for i = 1, math.min(count, #cells) do
		local gx, gz = cells[i][1], cells[i][2]
		pts[#pts + 1] = {
			x = -half + (gx + 0.5) * cell + (math.random() - 0.5) * cell * JITTER,
			z = -half + (gz + 0.5) * cell + (math.random() - 0.5) * cell * JITTER,
		}
	end
	return pts
end

-- 1 điểm rải-đều ngẫu nhiên (dùng cho respawn lẻ): chọn 1 ô bất kỳ của lưới cỡ
-- theo tổng orb rồi lệch trong ô -> respawn cũng trải đều, không dồn về 1 chỗ.
local function evenPoint(margin, count)
	local half = Config.MAP.SIZE / 2 - margin
	local cols = gridCols(count)
	local cell = (half * 2) / cols
	local gx, gz = math.random(0, cols - 1), math.random(0, cols - 1)
	return
		-half + (gx + 0.5) * cell + (math.random() - 0.5) * cell * JITTER,
		-half + (gz + 0.5) * cell + (math.random() - 0.5) * cell * JITTER
end

-- Rải 1 orb lẻ ở vị trí rải-đều (dùng cho respawn định kỳ).
local function spawnRandomOrb()
	local x, z = evenPoint(30, targetOrbs())
	makeOrb(x, z, Config.PICKUP.VALUE)
end

-- Rải 1 "mỏ" (cụm orb dày) quanh 1 tâm cho trước.
local function spawnClusterAt(cx, cz)
	for _ = 1, Config.PICKUP.CLUSTER_SIZE do
		local ox = randRange(-Config.PICKUP.CLUSTER_SPREAD, Config.PICKUP.CLUSTER_SPREAD)
		local oz = randRange(-Config.PICKUP.CLUSTER_SPREAD, Config.PICKUP.CLUSTER_SPREAD)
		makeOrb(cx + ox, cz + oz, Config.PICKUP.VALUE)
	end
end

local function spawnInitial()
	-- Cụm: tâm rải ĐỀU trên lưới -> hết cảnh "chỗ nhiều cụm, chỗ không có".
	for _, p in ipairs(evenPoints(clusterCount(), 60)) do
		spawnClusterAt(p.x, p.z)
	end
	-- Orb lẻ: rải đều cho đủ tổng mục tiêu.
	local remaining = targetOrbs() - #GameState.pickups
	for _, p in ipairs(evenPoints(remaining, 30)) do
		makeOrb(p.x, p.z, Config.PICKUP.VALUE)
	end
end

-- Tìm "thợ hút" gần orb nhất trong tầm: Tàu Mẹ HOẶC fleet unit. Trả về part + ownerId
-- để orb bay tới đó và cộng scrap cho chủ (cả hạm đội cùng gom scrap).
local function nearestAttractorInMagnet(pos)
	local bestPart, bestOwner, bestD
	local range = Config.PICKUP.MAGNET_RANGE
	for _, e in pairs(GameState.motherships) do
		if e.alive and e.part then
			local d = (e.part.Position - pos).Magnitude
			if d <= range and (not bestD or d < bestD) then bestPart, bestOwner, bestD = e.part, e.ownerId, d end
		end
	end
	for _, u in ipairs(GameState.units) do
		if u.part and u.part.Parent then
			local d = (u.part.Position - pos).Magnitude
			if d <= range and (not bestD or d < bestD) then bestPart, bestOwner, bestD = u.part, u.ownerId, d end
		end
	end
	return bestPart, bestOwner
end

local function updatePickups(dt)
	for i = #GameState.pickups, 1, -1 do
		local p = GameState.pickups[i]
		if not p.part or not p.part.Parent then
			table.remove(GameState.pickups, i)
		elseif p.flyingTo then
			-- Mục tiêu hút (Tàu Mẹ/unit) còn tồn tại không?
			if not p.flyPart or not p.flyPart.Parent then
				p.flyingTo = nil; p.flyPart = nil -- mất mục tiêu -> hút lại
			else
				local pos = p.part.Position
				local delta = p.flyPart.Position - pos
				local dist = delta.Magnitude
				if dist <= Config.PICKUP.COLLECT_DIST then
					EconomySystem.add(p.flyingTo, p.value) -- cộng scrap cho chủ
					p.part:Destroy()
					table.remove(GameState.pickups, i)
				else
					local step = math.min(Config.PICKUP.FLY_SPEED * dt, dist)
					p.part.Position = pos + delta.Unit * step
					local shrink = math.clamp(dist / Config.PICKUP.MAGNET_RANGE, 0.25, 1)
					p.part.Size = Vector3.new(p.baseSize, p.baseSize, p.baseSize) * shrink
				end
			end
		else
			local part, ownerId = nearestAttractorInMagnet(p.part.Position)
			if part then p.flyingTo = ownerId; p.flyPart = part end
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

	-- KHÔNG rải scrap ở init: chỉ rải khi vào trận (Main gọi PickupSystem.reset).

	RunService.Heartbeat:Connect(updatePickups)

	-- Bù orb lẻ định kỳ — CHỈ khi đang trong trận (lobby không có scrap).
	task.spawn(function()
		while true do
			task.wait(Config.PICKUP.RESPAWN_INTERVAL)
			if MatchState.isPlaying() then
				local need = targetOrbs() - #GameState.pickups
				for _ = 1, math.min(need, Config.PICKUP.RESPAWN_BATCH) do
					spawnRandomOrb()
				end
			end
		end
	end)

	print("[PickupSystem] ready")
end

return PickupSystem
