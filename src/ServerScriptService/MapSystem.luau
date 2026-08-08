--[[
	MapSystem.luau
	--------------
	Sinh sân chơi: 1 baseplate phẳng 500x500 và các MỎ (ore deposit) rải rác.
	Mỏ là nơi DUY NHẤT đặt được Scrap Mine, có hình dạng riêng (đế đá tối + các
	tinh thể neon phát sáng) để phân biệt rõ với mặt đất trống (chỗ đặt Hub).

	Quy ước chiều cao: mặt trên của baseplate ở Y = 0. Mọi thứ đặt trên map
	sẽ nằm ở Y > 0 (mothership ở Y = RADIUS). Nhờ đó client có thể tính
	world-point con trỏ bằng cách cắt tia camera với mặt phẳng Y = 0.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local GameState = require(script.Parent.GameState)

local MapSystem = {}

local function makeBaseplate()
	local base = Instance.new("Part")
	base.Name = "Baseplate"
	base.Anchored = true
	base.Size = Vector3.new(Config.MAP.SIZE, 4, Config.MAP.SIZE)
	-- Đặt sao cho mặt trên ở Y = 0
	base.Position = Vector3.new(0, -2, 0)
	base.Color = Color3.fromRGB(20, 24, 34)
	base.Material = Enum.Material.SmoothPlastic
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.Parent = Workspace
	return base
end

-- Tạo 1 mỏ (ore deposit) tại (x,z): đế đá dẹt + vài tinh thể neon phát sáng.
-- Part chính (đế) được đăng ký vào GameState.oreDeposits và dùng để đặt mine.
local function makeOreDeposit(container, x, z)
	local r = Config.MAP.ORE_DEPOSIT_RADIUS

	-- Đế mỏ: trụ dẹt tối màu, mặt trên ~ Y=1.5
	local base = Instance.new("Part")
	base.Name = "OreDeposit"
	base.Anchored = true
	base.Shape = Enum.PartType.Cylinder
	-- Cylinder mặc định trục dài theo X -> xoay để nằm ngang (trục cao theo Y)
	base.Size = Vector3.new(3, r * 2, r * 2)
	base.CFrame = CFrame.new(x, 1.5, z) * CFrame.Angles(0, 0, math.rad(90))
	base.Color = Color3.fromRGB(55, 60, 75)
	base.Material = Enum.Material.Slate
	base.Parent = container

	-- Tinh thể neon mọc lên từ đế (hình dạng riêng, dễ nhận biết) — màu vàng
	local crystalColor = Color3.fromRGB(255, 210, 80)
	local n = math.random(3, 5)
	for i = 1, n do
		local h = math.random(5, 10)
		local shard = Instance.new("Part")
		shard.Name = "Crystal"
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanQuery = false
		shard.Size = Vector3.new(1.6, h, 1.6)
		local ang = (i / n) * math.pi * 2
		local rad = math.random(0, r - 2)
		local px = x + math.cos(ang) * rad
		local pz = z + math.sin(ang) * rad
		-- Nghiêng ngẫu nhiên nhẹ cho ra dáng cụm tinh thể
		shard.CFrame = CFrame.new(px, 1.5 + h / 2, pz)
			* CFrame.Angles(math.rad(math.random(-18, 18)), math.rad(math.random(0, 360)), math.rad(math.random(-18, 18)))
		shard.Color = crystalColor
		shard.Material = Enum.Material.Neon
		shard.Parent = base
	end

	GameState.oreDeposits[base] = { occupied = false }
	return base
end

-- Rải ORE_DEPOSIT_COUNT mỏ, giữ khoảng cách tối thiểu giữa các mỏ.
local function makeOreDeposits(container)
	local half = Config.MAP.SIZE / 2
	local margin = 60
	local gap = Config.MAP.ORE_DEPOSIT_MIN_GAP
	local placed = {}

	local made, attempts = 0, 0
	while made < Config.MAP.ORE_DEPOSIT_COUNT and attempts < 500 do
		attempts += 1
		local x = math.random(-half + margin, half - margin)
		local z = math.random(-half + margin, half - margin)
		local okSpot = true
		for _, pos in ipairs(placed) do
			if (Vector3.new(x, 0, z) - pos).Magnitude < gap then
				okSpot = false
				break
			end
		end
		if okSpot then
			makeOreDeposit(container, x, z)
			table.insert(placed, Vector3.new(x, 0, z))
			made += 1
		end
	end
	return made
end

-- Dọn baseplate / spawn mặc định của place mẫu (nếu có) để tránh z-fighting
-- với baseplate do script tạo (hai mặt phẳng trùng Y=0 sẽ nhấp nháy).
local function clearDefaultTerrain()
	for _, name in ipairs({ "Baseplate", "SpawnLocation" }) do
		local existing = Workspace:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
end

-- Dọn map hiện tại (baseplate + mọi mỏ) để dựng lại theo số Config mới.
-- Building phải được BuildingSystem.clearAll() dọn TRƯỚC (giải phóng node mỏ).
function MapSystem.clearAll()
	local dep = Workspace:FindFirstChild("OreDeposits")
	if dep then dep:Destroy() end
	table.clear(GameState.oreDeposits)
	local base = Workspace:FindFirstChild("Baseplate")
	if base then base:Destroy() end
end

-- Đẩy 1 vị trí ra ngoài mọi mỏ (để Tàu Mẹ/unit không đi xuyên mỏ).
-- pos: vị trí muốn tới; radius: bán kính va chạm của thực thể. Trả về vị trí đã
-- kẹp ra ngoài rìa mỏ (giữ nguyên Y). Mỏ thưa (~130 studs) nên chỉ chạm 1 mỏ/lần.
function MapSystem.resolveDeposits(pos, radius)
	local minBase = Config.MAP.ORE_DEPOSIT_RADIUS + (radius or 0)
	for node in pairs(GameState.oreDeposits) do
		if node.Parent then
			local dx = pos.X - node.Position.X
			local dz = pos.Z - node.Position.Z
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist < minBase then
				if dist > 1e-4 then
					local push = minBase - dist
					pos = Vector3.new(pos.X + dx / dist * push, pos.Y, pos.Z + dz / dist * push)
				else
					pos = Vector3.new(pos.X + minBase, pos.Y, pos.Z) -- trùng tâm -> đẩy lệch
				end
			end
		end
	end
	return pos
end

-- Đẩy `pos` ra ngoài 1 vòng tròn (tâm cx,cz, bán kính tối thiểu minD) trên mặt XZ.
local function pushOut(pos, cx, cz, minD)
	local dx, dz = pos.X - cx, pos.Z - cz
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist < minD then
		if dist > 1e-4 then
			local p = minD - dist
			return Vector3.new(pos.X + dx / dist * p, pos.Y, pos.Z + dz / dist * p)
		else
			return Vector3.new(pos.X + minD, pos.Y, pos.Z)
		end
	end
	return pos
end

-- Đẩy `pos` ra ngoài mọi VẬT CẢN CỨNG: mỏ + công trình + Tàu Mẹ (trừ selfPart).
--   includeUnits=false: KHÔNG né unit (dùng cho Tàu Mẹ — vật to không bị unit ghì).
-- radius = bán kính va chạm của thực thể đang di chuyển.
function MapSystem.resolveSolids(pos, radius, selfPart)
	radius = radius or 0
	-- Mỏ
	local dmin = Config.MAP.ORE_DEPOSIT_RADIUS + radius
	for node in pairs(GameState.oreDeposits) do
		if node.Parent then
			pos = pushOut(pos, node.Position.X, node.Position.Z, dmin)
		end
	end
	-- Công trình
	for _, b in ipairs(GameState.buildings) do
		local part = b.part
		if part and part.Parent and part ~= selfPart then
			pos = pushOut(pos, part.Position.X, part.Position.Z, math.max(part.Size.X, part.Size.Z) / 2 + radius)
		end
	end
	-- Tàu Mẹ khác
	for _, m in pairs(GameState.motherships) do
		local part = m.part
		if m.alive and part and part.Parent and part ~= selfPart then
			pos = pushOut(pos, part.Position.X, part.Position.Z, math.max(part.Size.X, part.Size.Z) / 2 + radius)
		end
	end
	return pos
end

function MapSystem.init()
	clearDefaultTerrain()
	-- KHÔNG dựng baseplate: arena là "không gian" (nền trời). Con trỏ vẫn tính
	-- world-point bằng cắt mặt phẳng Y=0 (không cần part sàn).

	local container = Instance.new("Folder")
	container.Name = "OreDeposits"
	container.Parent = Workspace

	local made = makeOreDeposits(container)

	print(("[MapSystem] Map %dx%d, %d ore deposits (mỏ)"):format(
		Config.MAP.SIZE, Config.MAP.SIZE, made))
end

-- Dựng lại map từ đầu theo Config hiện tại (dùng khi Chơi lại để áp số MAP mới).
function MapSystem.rebuild()
	MapSystem.clearAll()
	MapSystem.init()
end

return MapSystem
