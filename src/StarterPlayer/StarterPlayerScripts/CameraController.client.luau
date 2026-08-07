--[[
	CameraController.client.luau
	----------------------------
	Camera top-down bám theo Tàu Mẹ của người chơi.

	- Tìm part mothership của mình qua attribute "OwnerUserId" trong
	  workspace.Motherships (do server tạo & replicate xuống).
	- Camera đặt cao HEIGHT phía trên, lệch nhẹ TILT_OFFSET theo Z để có
	  góc nghiêng nhẹ (đẹp hơn top-down thuần), luôn nhìn xuống mothership.
	- Không xoay theo hướng di chuyển (giữ khung nhìn ổn định — kiểu Lordz).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local player = Players.LocalPlayer

-- Trong trận: camera top-down. Ở lobby: camera chếch từ sau lưng (thấy cổng + chân trời).
local playing = false

-- Điều khiển camera lobby: zoom (lăn chuột) + xoay quanh Tàu Mẹ (giữ chuột phải + rê).
local lobbyZoom = 1
local lobbyYaw = 0        -- góc xoay ngang (radian); 0 = ngay sau lưng
local lobbyPitch = 0      -- lệch góc ngẩng thêm/bớt so với mặc định (kéo dọc chuột phải)
local rotating = false
local lastMouseX, lastMouseY = nil, nil -- vị trí con trỏ frame trước (tính chênh lệch)

Remotes.MatchState.OnClientEvent:Connect(function(s)
	playing = (s == "playing")
	if playing then rotating = false end
end)

-- Zoom bằng lăn chuột (không lọc gameProcessed vì camera mặc định nuốt sự kiện này).
UserInputService.InputChanged:Connect(function(input)
	if playing then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local c = Config.LOBBY.CAM
		lobbyZoom = math.clamp(lobbyZoom - input.Position.Z * 0.12, c.ZOOM_MIN, c.ZOOM_MAX)
	end
end)

-- Giữ chuột phải = bật xoay; góc yaw cập nhật trong RenderStepped theo chênh lệch
-- vị trí con trỏ (cách này KHÔNG bị camera mặc định tranh chấp như MouseBehavior).
UserInputService.InputBegan:Connect(function(input)
	if playing then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rotating = true
		local mp = UserInputService:GetMouseLocation()
		lastMouseX, lastMouseY = mp.X, mp.Y
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rotating = false
		lastMouseX, lastMouseY = nil, nil
	end
end)

local folder = Workspace:WaitForChild("Motherships")
local myName = "Mothership_" .. player.UserId

-- Tìm Tàu Mẹ của mình NGAY (không yield): ưu tiên đúng tên, fallback mothership bất kỳ.
local function findMyShipNow()
	local ship = folder:FindFirstChild(myName)
	if ship then return ship end
	for _, part in ipairs(folder:GetChildren()) do
		if part.Name:match("^Mothership_") then
			return part
		end
	end
	return nil
end

-- Chờ lần đầu (Tàu Mẹ có thể replicate hơi trễ)
local myShip = folder:WaitForChild(myName, 15) or findMyShipNow()

RunService.RenderStepped:Connect(function()
	-- Ship bị huỷ (chết/Restart) -> tự tìm lại (ship mới sau Restart cùng tên).
	if not myShip or not myShip.Parent then
		myShip = findMyShipNow()
		if not myShip then return end
	end

	-- Lấy camera hiện tại mỗi frame & ÉP Scriptable liên tục. Nếu chỉ set 1 lần
	-- lúc khởi động, camera mặc định của Roblox có thể giành lại quyền -> chớp nháy.
	local camera = Workspace.CurrentCamera
	if not camera then return end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	-- Bám cứng vào vị trí Tàu Mẹ (như cũ — không nội suy).
	local pos = myShip.Position
	local camPos, lookAt
	if playing then
		-- Trong trận: top-down (nhìn thẳng xuống, hơi nghiêng theo Z).
		camPos = pos + Vector3.new(0, Config.CAMERA.HEIGHT, Config.CAMERA.TILT_OFFSET)
		lookAt = pos
	else
		-- Lobby: orbit cầu quanh Tàu Mẹ. Giữ chuột phải + rê: NGANG = xoay (yaw),
		-- DỌC = ngẩng/cúi (pitch). Lăn chuột = zoom khoảng cách.
		local c = Config.LOBBY.CAM
		if rotating then
			local mp = UserInputService:GetMouseLocation()
			if lastMouseX then
				lobbyYaw -= (mp.X - lastMouseX) * c.ROT_SENS
				-- Kéo LÊN (mp.Y giảm) -> pitch giảm -> camera hạ, nhìn lên trời/chân trời.
				lobbyPitch = math.clamp(lobbyPitch + (mp.Y - lastMouseY) * c.ROT_SENS, -0.75, 0.9)
			end
			lastMouseX, lastMouseY = mp.X, mp.Y
		end
		-- Bán kính + góc ngẩng nền suy từ HEIGHT/BACK; cộng lobbyPitch từ kéo dọc.
		-- Cận dưới ~0.05 rad (gần ngang tầm) -> thấy chân trời & trời; cận trên ~top-down.
		local radius = math.sqrt(c.HEIGHT * c.HEIGHT + c.BACK * c.BACK) * lobbyZoom
		local pitch = math.clamp(math.atan2(c.HEIGHT, c.BACK) + lobbyPitch, 0.05, 1.5)
		local cp = math.cos(pitch) * radius
		camPos = pos + Vector3.new(math.sin(lobbyYaw) * cp, math.sin(pitch) * radius, math.cos(lobbyYaw) * cp)
		-- Kéo xuống góc thấp (pitch nhỏ) -> NÂNG điểm nhìn lên trời để camera ngước lên.
		local skyBoost = math.max(0, 0.5 - pitch) * radius * 1.6
		lookAt = pos + Vector3.new(0, c.LOOK_UP + skyBoost, 0)
	end
	camera.CFrame = CFrame.lookAt(camPos, lookAt)
end)
