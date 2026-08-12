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

-- ===== CẢM ỨNG (mobile) ở lobby: 1 ngón (nửa phải) kéo = xoay+pitch; 2 ngón = pinch zoom =====
local touches = {}      -- [input] = Vector2 vị trí
local camTouch = nil    -- ngón đang xoay
local lastPinch = nil   -- khoảng cách 2 ngón lần trước
local function touchCount() local n = 0 for _ in pairs(touches) do n += 1 end return n end
UserInputService.InputBegan:Connect(function(input, gp)
	if input.UserInputType ~= Enum.UserInputType.Touch then return end
	touches[input] = Vector2.new(input.Position.X, input.Position.Y)
	if playing or gp then return end
	local cam = Workspace.CurrentCamera
	local vpx = (cam and cam.ViewportSize.X) or 1000
	if touchCount() == 1 and input.Position.X > vpx * 0.42 then camTouch = input end -- nửa phải = xoay
end)
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch or not touches[input] then return end
	local newp = Vector2.new(input.Position.X, input.Position.Y)
	local old = touches[input]; touches[input] = newp
	if playing then return end
	local c = Config.LOBBY.CAM
	if touchCount() >= 2 then
		camTouch = nil
		local a, b
		for _, p in pairs(touches) do if not a then a = p else b = p end end
		if a and b then
			local d = (a - b).Magnitude
			if lastPinch then lobbyZoom = math.clamp(lobbyZoom - (d - lastPinch) * 0.004, c.ZOOM_MIN, c.ZOOM_MAX) end
			lastPinch = d
		end
	elseif input == camTouch then
		local delta = newp - old
		lobbyYaw -= delta.X * c.ROT_SENS
		lobbyPitch = math.clamp(lobbyPitch + delta.Y * c.ROT_SENS, -0.75, 0.9)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch then return end
	touches[input] = nil
	if input == camTouch then camTouch = nil end
	if touchCount() < 2 then lastPinch = nil end
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

RunService.RenderStepped:Connect(function(dt)
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

	-- Bám cứng vào vị trí Tàu Mẹ (part đã được ShipSmooth nội suy mượt ở client).
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
