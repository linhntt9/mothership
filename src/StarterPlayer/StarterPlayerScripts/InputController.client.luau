--[[
	InputController.client.luau
	---------------------------
	Đọc input và gửi Ý ĐỊNH lên server (không tự quyết định gì).

	M0  Move  : mỗi frame tính world-point con trỏ (cắt tia camera với mặt Y=0),
	            gửi MoveInput ~10Hz -> server steer Tàu Mẹ.
	M1  Mua   : phím 1-4 = mua Drone/Frigate/Destroyer/Plasma (giờ tốn scrap).
	M2  Debug : phím E = gọi hạm đội địch.
	M3  Split : giữ Space = tách, thả = gộp.
	M4  Build : hotbar (HUD) -> ClientBus báo vào chế độ đặt building; ghost theo
	            chuột; chuột trái = đặt / (ngoài build) nâng cấp building đang trỏ;
	            chuột phải = thoát build / huỷ channel.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Remotes)
local ClientBus = require(script.Parent.ClientBus)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Tìm Tàu Mẹ của mình (để giữ đứng yên khi đang chọn chỗ xây)
local function getMyShip()
	local folder = Workspace:FindFirstChild("Motherships")
	if not folder then return nil end
	return folder:FindFirstChild("Mothership_" .. player.UserId)
end

-- Phím số -> loại unit muốn mua
local SPAWN_KEYS = {
	[Enum.KeyCode.One]   = "Drone",
	[Enum.KeyCode.Two]   = "Frigate",
	[Enum.KeyCode.Three] = "Destroyer",
	[Enum.KeyCode.Four]  = "PlasmaCruiser",
}

-- Kích cỡ ghost theo loại (khớp VISUAL bên BuildingSystem — chỉ để gợi ý)
local GHOST_SIZE = {
	ScrapMine = Vector3.new(7, 7, 7),
	DroneHub  = Vector3.new(10, 6, 10),
}

-------------------------------------------------------------------------------
-- Con trỏ -> world-point trên mặt map (Y = 0)
-------------------------------------------------------------------------------
local function cursorWorldPoint()
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local mp = UserInputService:GetMouseLocation()
	local ray = cam:ScreenPointToRay(mp.X, mp.Y)
	local dirY = ray.Direction.Y
	if math.abs(dirY) < 1e-6 then return nil end
	local t = -ray.Origin.Y / dirY
	if t < 0 then return nil end
	return ray.Origin + ray.Direction * t
end

-------------------------------------------------------------------------------
-- Chế độ đặt building
-------------------------------------------------------------------------------
local buildMode = nil   -- nil hoặc "ScrapMine"/"DroneHub"
local ghost = nil

local function clearGhost()
	if ghost then ghost:Destroy(); ghost = nil end
end

local function enterBuildMode(buildingType)
	buildMode = buildingType
	clearGhost()
	local size = GHOST_SIZE[buildingType] or Vector3.new(6, 6, 6)
	ghost = Instance.new("Part")
	ghost.Name = "BuildGhost"
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.Transparency = 0.5
	ghost.Color = Color3.fromRGB(120, 255, 150)
	ghost.Material = Enum.Material.Neon
	ghost.Size = size
	ghost.Parent = Workspace
end

local function exitBuildMode()
	buildMode = nil
	clearGhost()
end

ClientBus.enterBuild.Event:Connect(enterBuildMode)

-------------------------------------------------------------------------------
-- Raycast tìm building dưới con trỏ (để nâng cấp)
-------------------------------------------------------------------------------
local function buildingUnderCursor()
	local cam = Workspace.CurrentCamera
	local bf = Workspace:FindFirstChild("Buildings")
	if not cam or not bf then return nil end
	local mp = UserInputService:GetMouseLocation()
	local ray = cam:ScreenPointToRay(mp.X, mp.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { bf }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 3000, params)
	return result and result.Instance or nil
end

-------------------------------------------------------------------------------
-- Input
-------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- Chuột
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if buildMode then
			local pt = cursorWorldPoint()
			if pt then Remotes.PlaceBuilding:FireServer(buildMode, pt) end
			exitBuildMode() -- đặt xong -> ghost biến mất ngay (muốn xây tiếp: bấm Q/R lại)
		else
			local part = buildingUnderCursor()
			if part then Remotes.UpgradeBuilding:FireServer(part) end
		end
		return
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if buildMode then
			exitBuildMode()
		else
			Remotes.CancelBuild:FireServer() -- huỷ channel nếu đang xây
		end
		return
	end

	-- Bàn phím
	local unitType = SPAWN_KEYS[input.KeyCode]
	if unitType then
		Remotes.SpawnUnit:FireServer(unitType)                  -- 1-4: mua quân
	elseif input.KeyCode == Enum.KeyCode.Q then
		enterBuildMode("ScrapMine")                             -- Q: xây Mine
	elseif input.KeyCode == Enum.KeyCode.R then
		enterBuildMode("DroneHub")                              -- R: xây Hub
	elseif input.KeyCode == Enum.KeyCode.Space then
		Remotes.SplitInput:FireServer(true)
	elseif input.KeyCode == Enum.KeyCode.Escape then
		if buildMode then exitBuildMode() end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space then
		Remotes.SplitInput:FireServer(false)
	end
end)

-------------------------------------------------------------------------------
-- Vòng lặp: gửi move + cập nhật ghost
-------------------------------------------------------------------------------
local SEND_INTERVAL = 0.1 -- 10Hz
local accum = 0

RunService.RenderStepped:Connect(function(dt)
	local point = cursorWorldPoint()

	-- Ghost bám chuột khi đang ở chế độ xây
	if buildMode and ghost and point then
		local size = GHOST_SIZE[buildMode] or Vector3.new(6, 6, 6)
		ghost.Position = Vector3.new(point.X, size.Y / 2, point.Z)
	end

	-- Gửi move throttle 10Hz
	accum += dt
	if accum >= SEND_INTERVAL then
		accum = 0
		if buildMode then
			-- Đang chọn chỗ xây -> giữ Tàu Mẹ ĐỨNG YÊN (gửi chính vị trí của nó)
			local ship = getMyShip()
			if ship then
				Remotes.MoveInput:FireServer(ship.Position)
			end
		elseif point then
			Remotes.MoveInput:FireServer(point)
		end
	end
end)
