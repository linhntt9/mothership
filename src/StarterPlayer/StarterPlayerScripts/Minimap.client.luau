--[[
	Minimap.client.luau
	-------------------
	Bản đồ nhỏ góc trên-trái giúp người chơi thấy vị trí trên map lớn.

	Server là nguồn dữ liệu: mọi part (Tàu Mẹ, mỏ, building) đã replicate xuống
	client trong các Folder của workspace. Minimap chỉ ĐỌC vị trí + attribute
	"OwnerUserId" để chấm điểm, KHÔNG tự sinh state.

	Quy ước hướng: camera nhìn từ +Z xuống nên world +X = phải màn hình,
	world +Z = xuống màn hình. Minimap map thẳng (x -> ngang, z -> dọc) nên
	"hướng" trên minimap khớp với những gì thấy trên màn hình (bắc = trên).

	Chấm gì:
	  - Mỏ (ore deposit)      : chấm vàng nhỏ (mục tiêu để cắm Mine)
	  - Building của mình/địch : chấm nhỏ (xanh ngọc = mình, đỏ = địch)
	  - Tàu Mẹ địch            : chấm màu phe của nó
	  - Tàu Mẹ CỦA MÌNH        : chấm to nhất + viền trắng (dễ thấy "tôi đang ở đâu")
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local myId = player.UserId

local FRAME = 132 -- kích thước minimap (px) — nhỏ gọn ở góc dưới-phải

-- Màu chấm
local COL_DEPOSIT   = Color3.fromRGB(255, 210, 80)
local COL_MY_BLD    = Color3.fromRGB(80, 220, 200)
local COL_ENEMY_BLD = Color3.fromRGB(230, 90, 90)
local COL_MY_SHIP   = Color3.fromRGB(120, 255, 140)

-------------------------------------------------------------------------------
-- GUI khung
-------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "Minimap"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false   -- ẩn ở lobby; bật khi vào trận
gui.Parent = playerGui

local Remotes = require(ReplicatedStorage.Remotes)
Remotes.MatchState.OnClientEvent:Connect(function(s)
	gui.Enabled = (s == "playing")
end)

local mapFrame = Instance.new("Frame")
mapFrame.Name = "Map"
mapFrame.AnchorPoint = Vector2.new(1, 1)
mapFrame.Position = UDim2.new(1, -12, 1, -12) -- góc dưới-phải
mapFrame.Size = UDim2.fromOffset(FRAME, FRAME)
mapFrame.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
mapFrame.BackgroundTransparency = 0.25
mapFrame.ClipsDescendants = true
mapFrame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = mapFrame

local border = Instance.new("UIStroke")
border.Color = Color3.fromRGB(90, 110, 140)
border.Thickness = 1.5
border.Transparency = 0.3
border.Parent = mapFrame

-------------------------------------------------------------------------------
-- Chuyển toạ độ world (x,z) -> pixel trong khung minimap
-------------------------------------------------------------------------------
local function toMini(x, z)
	local size = Config.MAP.SIZE
	local half = size / 2
	local u = math.clamp((x + half) / size, 0, 1)
	local v = math.clamp((z + half) / size, 0, 1)
	return u * FRAME, v * FRAME
end

-------------------------------------------------------------------------------
-- Pool chấm: tái sử dụng Frame để không tạo/huỷ instance mỗi frame.
-------------------------------------------------------------------------------
local dots = {}
local used = 0

local function nextDot()
	used += 1
	local d = dots[used]
	if not d then
		d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.BorderSizePixel = 0
		d.ZIndex = 2
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0) -- tròn
		c.Parent = d
		local s = Instance.new("UIStroke")
		s.Thickness = 2
		s.Enabled = false
		s.Parent = d
		d.Parent = mapFrame
		dots[used] = d
	end
	d.Visible = true
	return d
end

local function placeDot(x, z, sizePx, color, strokeColor)
	local d = nextDot()
	local px, py = toMini(x, z)
	d.Size = UDim2.fromOffset(sizePx, sizePx)
	d.Position = UDim2.fromOffset(px, py)
	d.BackgroundColor3 = color
	d.ZIndex = (strokeColor and 5) or 2 -- Tàu Mẹ mình nổi lên trên
	local stroke = d:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Enabled = strokeColor ~= nil
		if strokeColor then stroke.Color = strokeColor end
	end
end

-------------------------------------------------------------------------------
-- Mũi tên chỉ HƯỚNG DI CHUYỂN của Tàu Mẹ mình + báo động khi công trình bị đánh.
-------------------------------------------------------------------------------
local arrow = Instance.new("TextLabel")
arrow.AnchorPoint = Vector2.new(0.5, 0.5)
arrow.Size = UDim2.fromOffset(18, 18)
arrow.BackgroundTransparency = 1
arrow.Font = Enum.Font.GothamBlack
arrow.TextSize = 18
arrow.Text = "▲"
arrow.TextColor3 = COL_MY_SHIP
arrow.ZIndex = 6
arrow.Visible = false
arrow.Parent = mapFrame
local lastShipPos = nil
local headingDeg = 0

-- Công trình của mình bị đánh -> chấm đỏ nhấp nháy trên minimap tại chỗ đó.
Remotes.BuildingAlert.OnClientEvent:Connect(function(pos)
	if typeof(pos) ~= "Vector3" then return end
	local px, py = toMini(pos.X, pos.Z)
	local a = Instance.new("Frame")
	a.AnchorPoint = Vector2.new(0.5, 0.5)
	a.Position = UDim2.fromOffset(px, py)
	a.Size = UDim2.fromOffset(9, 9)
	a.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	a.BorderSizePixel = 0
	a.ZIndex = 7
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = a
	a.Parent = mapFrame
	game:GetService("TweenService"):Create(
		a, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 3, true),
		{ Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 0.6 }
	):Play()
	game:GetService("Debris"):AddItem(a, 2.4)
end)

-------------------------------------------------------------------------------
-- La bàn (giữa-trên): vòng + kim chỉ HƯỚNG Tàu Mẹ đang đi; chữ N (bắc = trên).
-------------------------------------------------------------------------------
local compass = Instance.new("Frame")
compass.AnchorPoint = Vector2.new(0.5, 0)
compass.Position = UDim2.new(0.5, 0, 0, 12)
compass.Size = UDim2.fromOffset(56, 56)
compass.BackgroundColor3 = Color3.fromRGB(15, 18, 28)
compass.BackgroundTransparency = 0.25
local ccc = Instance.new("UICorner"); ccc.CornerRadius = UDim.new(1, 0); ccc.Parent = compass
local ccs = Instance.new("UIStroke"); ccs.Color = Color3.fromRGB(90, 110, 140); ccs.Transparency = 0.3; ccs.Parent = compass
compass.Parent = gui
local nMark = Instance.new("TextLabel")
nMark.AnchorPoint = Vector2.new(0.5, 0); nMark.Position = UDim2.new(0.5, 0, 0, 1); nMark.Size = UDim2.fromOffset(14, 14)
nMark.BackgroundTransparency = 1; nMark.Font = Enum.Font.GothamBold; nMark.TextSize = 12
nMark.Text = "N"; nMark.TextColor3 = Color3.fromRGB(255, 120, 120); nMark.Parent = compass
local needle = Instance.new("TextLabel")
needle.AnchorPoint = Vector2.new(0.5, 0.5); needle.Position = UDim2.fromScale(0.5, 0.5); needle.Size = UDim2.fromOffset(44, 44)
needle.BackgroundTransparency = 1; needle.Font = Enum.Font.GothamBlack; needle.TextSize = 36
needle.Text = "↑"; needle.TextColor3 = COL_MY_SHIP; needle.Parent = compass

-------------------------------------------------------------------------------
-- Vẽ lại mỗi ~0.08s (12Hz là đủ mượt cho minimap, nhẹ CPU)
-------------------------------------------------------------------------------
local function redraw()
	used = 0

	-- CHỈ hiện của MÌNH: nhà của mình + Tàu Mẹ của mình (không lộ bot/mỏ/địch).
	-- 1) Building của mình
	local buildings = Workspace:FindFirstChild("Buildings")
	if buildings then
		for _, part in ipairs(buildings:GetChildren()) do
			if part:IsA("BasePart") and part:GetAttribute("OwnerUserId") == myId then
				placeDot(part.Position.X, part.Position.Z, 6, COL_MY_BLD, nil)
			end
		end
	end

	-- 2) Tàu Mẹ của mình -> MŨI TÊN chỉ hướng đi (không phải chấm tròn)
	local ships = Workspace:FindFirstChild("Motherships")
	local myShip = ships and ships:FindFirstChild("Mothership_" .. myId)
	if myShip then
		local mp = myShip.Position
		local px, py = toMini(mp.X, mp.Z)
		arrow.Position = UDim2.fromOffset(px, py)
		arrow.Visible = true
		if lastShipPos then
			local dx, dz = mp.X - lastShipPos.X, mp.Z - lastShipPos.Z
			if (dx * dx + dz * dz) > 0.25 then -- đang di chuyển -> cập nhật hướng
				headingDeg = math.deg(math.atan2(dx, -dz))
			end
		end
		arrow.Rotation = headingDeg
		needle.Rotation = headingDeg -- kim la bàn cùng hướng
		lastShipPos = mp
	else
		arrow.Visible = false
	end

	-- Ẩn các chấm thừa của lần vẽ trước
	for i = used + 1, #dots do
		dots[i].Visible = false
	end
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc >= 0.08 then
		acc = 0
		redraw()
	end
end)
