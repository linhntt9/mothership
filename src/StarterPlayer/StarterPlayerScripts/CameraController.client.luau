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

local Config = require(ReplicatedStorage.Config)

local player = Players.LocalPlayer

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

	local pos = myShip.Position
	local camPos = pos + Vector3.new(0, Config.CAMERA.HEIGHT, Config.CAMERA.TILT_OFFSET)
	camera.CFrame = CFrame.lookAt(camPos, pos)
end)
