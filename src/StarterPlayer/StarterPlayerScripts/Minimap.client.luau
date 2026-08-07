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

local FRAME = 200 -- kích thước minimap (px)

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
mapFrame.AnchorPoint = Vector2.new(0, 0)
mapFrame.Position = UDim2.new(0, 12, 0, 12)
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
-- Vẽ lại mỗi ~0.08s (12Hz là đủ mượt cho minimap, nhẹ CPU)
-------------------------------------------------------------------------------
local function redraw()
	used = 0

	-- 1) Mỏ (ore deposit)
	local deposits = Workspace:FindFirstChild("OreDeposits")
	if deposits then
		for _, part in ipairs(deposits:GetChildren()) do
			if part:IsA("BasePart") and part.Name == "OreDeposit" then
				placeDot(part.Position.X, part.Position.Z, 5, COL_DEPOSIT, nil)
			end
		end
	end

	-- 2) Building (mình vs địch)
	local buildings = Workspace:FindFirstChild("Buildings")
	if buildings then
		for _, part in ipairs(buildings:GetChildren()) do
			if part:IsA("BasePart") then
				local owner = part:GetAttribute("OwnerUserId")
				local col = (owner == myId) and COL_MY_BLD or COL_ENEMY_BLD
				placeDot(part.Position.X, part.Position.Z, 6, col, nil)
			end
		end
	end

	-- 3) Tàu Mẹ — mình vẽ to + viền trắng, địch dùng màu phe của nó
	local ships = Workspace:FindFirstChild("Motherships")
	if ships then
		for _, part in ipairs(ships:GetChildren()) do
			if part:IsA("BasePart") and part.Name:match("^Mothership_") then
				local owner = part:GetAttribute("OwnerUserId")
				if owner == myId then
					placeDot(part.Position.X, part.Position.Z, 13, COL_MY_SHIP, Color3.fromRGB(255, 255, 255))
				else
					placeDot(part.Position.X, part.Position.Z, 10, part.Color, nil)
				end
			end
		end
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
