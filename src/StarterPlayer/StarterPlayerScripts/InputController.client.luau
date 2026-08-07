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

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local ClientBus = require(script.Parent.ClientBus)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Chỉ nhận input gameplay (mua/xây/split) khi ĐANG TRONG TRẬN. Ở lobby chỉ lái tàu.
local playing = false
Remotes.MatchState.OnClientEvent:Connect(function(s) playing = (s == "playing") end)

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
	[Enum.KeyCode.Five]  = "Interceptor",
	[Enum.KeyCode.Six]   = "Battleship",
	[Enum.KeyCode.Seven] = "SiegeRailgun",
	[Enum.KeyCode.Eight] = "Titan",
	[Enum.KeyCode.Nine]  = "Kamikaze",
}

-- Kích cỡ ghost theo loại (khớp VISUAL bên BuildingSystem — chỉ để gợi ý)
local GHOST_SIZE = {
	ScrapMine = Vector3.new(24, 7, 24),
	DroneHub  = Vector3.new(24, 7, 24),
	LaserSat  = Vector3.new(22, 8, 22),
	PlasmaSat = Vector3.new(24, 8, 24),
}

-------------------------------------------------------------------------------
-- Con trỏ -> world-point trên mặt map (Y = 0)
-------------------------------------------------------------------------------
local function cursorWorldPoint(screenPos)
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local mp = screenPos or UserInputService:GetMouseLocation()
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
ClientBus.cancelBuild.Event:Connect(function() if buildMode then exitBuildMode() end end)

-------------------------------------------------------------------------------
-- Raycast tìm building dưới con trỏ (để nâng cấp)
-------------------------------------------------------------------------------
local function buildingUnderCursor(screenPos)
	local cam = Workspace.CurrentCamera
	local bf = Workspace:FindFirstChild("Buildings")
	if not cam or not bf then return nil end
	local mp = screenPos or UserInputService:GetMouseLocation()
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
	if not playing then return end -- ở lobby: bỏ qua mua/xây/split (chỉ lái tàu)

	-- Chuột
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if buildMode then
			local pt = cursorWorldPoint()
			if pt then Remotes.PlaceBuilding:FireServer(buildMode, pt) end
			exitBuildMode() -- đặt xong -> ghost biến mất ngay (muốn xây tiếp: bấm Q/R lại)
		else
			local bpart = buildingUnderCursor()
			if bpart and bpart:GetAttribute("OwnerUserId") == player.UserId then
				ClientBus.selectBuilding:Fire(bpart) -- nhà MÌNH -> panel Nâng cấp/Bán
			else
				-- Nhà ĐỊCH / đất trống -> đóng panel; tấn công = lái Tàu Mẹ tới (trỏ chuột).
				ClientBus.selectBuilding:Fire(nil)
			end
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
		enterBuildMode("DroneHub")                              -- R: xây House
	elseif input.KeyCode == Enum.KeyCode.T then
		enterBuildMode("LaserSat")                              -- T: Laser Satellite
	elseif input.KeyCode == Enum.KeyCode.Y then
		enterBuildMode("PlasmaSat")                             -- Y: Plasma Satellite
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

-- LOBBY: lái bằng WASD. Camera nhìn về -Z (cổng ở trước) nên W = -Z (tiến),
-- S = +Z, A = -X, D = +X (trục thế giới, camera không xoay).
local LOBBY_AHEAD = 45 -- gửi đích cách tàu bao xa theo hướng phím -> chạy liên tục khi giữ

-- Hướng THEO CAMERA từ (phải, tới): fwd*fwdAmt + rgt*rightAmt (đều flatten XZ).
local function camDir(rightAmt, fwdAmt)
	local cam = Workspace.CurrentCamera
	if not cam then return Vector3.zero end
	local fwd = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
	fwd = (fwd.Magnitude > 1e-3) and fwd.Unit or Vector3.new(0, 0, -1)
	local rgt = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
	rgt = (rgt.Magnitude > 1e-3) and rgt.Unit or Vector3.new(1, 0, 0)
	local d = fwd * fwdAmt + rgt * rightAmt
	return (d.Magnitude > 0) and d.Unit or Vector3.zero
end

-- WASD (PC) -> hướng theo camera. IsKeyDown = phím vật lý (Telex-proof); không lái khi gõ ⚙.
local function wasdDir()
	if UserInputService:GetFocusedTextBox() then return Vector3.zero end
	local x = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
	local z = (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
	if x == 0 and z == 0 then return Vector3.zero end
	return camDir(x, z)
end

-- ===== MOBILE (cảm ứng): joystick di chuyển + chạm để đặt/chọn nhà =====
local isTouch = UserInputService.TouchEnabled
local stickVec = Vector2.new(0, 0) -- hướng joystick (-1..1): X=phải, Y=tới
if isTouch then
	local pgui = player:WaitForChild("PlayerGui")
	local tgui = Instance.new("ScreenGui")
	tgui.Name = "TouchControls"; tgui.ResetOnSpawn = false; tgui.IgnoreGuiInset = true; tgui.Parent = pgui
	local R = 70
	local base = Instance.new("Frame")
	base.AnchorPoint = Vector2.new(0.5, 0.5)
	base.Position = UDim2.new(0, 130, 1, -130)
	base.Size = UDim2.fromOffset(R * 2, R * 2)
	base.BackgroundColor3 = Color3.fromRGB(20, 24, 34); base.BackgroundTransparency = 0.55
	local bcn = Instance.new("UICorner"); bcn.CornerRadius = UDim.new(1, 0); bcn.Parent = base
	base.Parent = tgui
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5); knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromOffset(64, 64); knob.BackgroundColor3 = Color3.fromRGB(120, 170, 255); knob.BackgroundTransparency = 0.1
	local kcn = Instance.new("UICorner"); kcn.CornerRadius = UDim.new(1, 0); kcn.Parent = knob
	knob.Parent = base

	local joyTouch = nil
	local function baseCenter() return base.AbsolutePosition + base.AbsoluteSize / 2 end
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or joyTouch then return end
		local d = Vector2.new(input.Position.X, input.Position.Y) - baseCenter()
		if d.Magnitude <= R + 45 then joyTouch = input end -- chạm gần joystick -> điều khiển stick
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input ~= joyTouch or input.UserInputType ~= Enum.UserInputType.Touch then return end
		local d = Vector2.new(input.Position.X, input.Position.Y) - baseCenter()
		if d.Magnitude > R then d = d.Unit * R end
		knob.Position = UDim2.new(0.5, d.X, 0.5, d.Y)
		stickVec = Vector2.new(d.X / R, -d.Y / R)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == joyTouch then
			joyTouch = nil; stickVec = Vector2.new(0, 0); knob.Position = UDim2.fromScale(0.5, 0.5)
		end
	end)

	-- Chạm thế giới (không phải GUI) -> đặt nhà (đang build) / chọn nhà (trong trận).
	UserInputService.TouchTapInWorld:Connect(function(pos, processedByUI)
		if processedByUI or not playing then return end
		if buildMode then
			local pt = cursorWorldPoint(pos)
			if pt then Remotes.PlaceBuilding:FireServer(buildMode, pt) end
			exitBuildMode()
		else
			local bpart = buildingUnderCursor(pos)
			if bpart and bpart:GetAttribute("OwnerUserId") == player.UserId then
				ClientBus.selectBuilding:Fire(bpart)
			else
				ClientBus.selectBuilding:Fire(nil)
			end
		end
	end)
end

-- Hover công trình -> viền sáng (Highlight).
local hoverHL = Instance.new("Highlight")
hoverHL.Name = "BuildingHover"
hoverHL.FillTransparency = 1
hoverHL.OutlineColor = Color3.fromRGB(255, 240, 120)
hoverHL.OutlineTransparency = 0
hoverHL.DepthMode = Enum.HighlightDepthMode.Occluded
hoverHL.Enabled = false
hoverHL.Parent = Workspace

-- Giữ phím 1-9 -> đẻ quân liên tục (tap = 1 con; giữ > HOLD_DELAY thì lặp mỗi HOLD_RATE).
local spawnHeld, spawnAccum = 0, 0
local HOLD_DELAY, HOLD_RATE = 0.25, 0.12

RunService.RenderStepped:Connect(function(dt)
	local point = cursorWorldPoint()

	-- Hover công trình -> hiện viền (trong trận, không ở chế độ xây).
	if playing and not buildMode then
		local hp = buildingUnderCursor()
		hoverHL.Adornee = hp
		hoverHL.Enabled = hp ~= nil
	elseif hoverHL.Enabled then
		hoverHL.Enabled = false
	end

	-- Giữ phím 1-9 -> đẻ quân liên tục.
	if playing and not UserInputService:GetFocusedTextBox() then
		local held = false
		for key in pairs(SPAWN_KEYS) do
			if UserInputService:IsKeyDown(key) then held = true; break end
		end
		if held then
			spawnHeld += dt
			spawnAccum += dt
			if spawnHeld > HOLD_DELAY and spawnAccum >= HOLD_RATE then
				spawnAccum = 0
				for key, utype in pairs(SPAWN_KEYS) do
					if UserInputService:IsKeyDown(key) then Remotes.SpawnUnit:FireServer(utype) end
				end
			end
		else
			spawnHeld, spawnAccum = 0, 0
		end
	end

	-- Ghost bám chuột khi đang ở chế độ xây
	if buildMode and ghost and point then
		local size = GHOST_SIZE[buildMode] or Vector3.new(6, 6, 6)
		ghost.Position = Vector3.new(point.X, size.Y / 2, point.Z)
	end

	-- Gửi move throttle 10Hz
	accum += dt
	if accum >= SEND_INTERVAL then
		accum = 0
		if isTouch then
			-- MOBILE: lái bằng joystick (camera-relative). Build/mở UI nhà -> đứng yên.
			local ship = getMyShip()
			if ship then
				if buildMode or player:GetAttribute("BuildingUIOpen") then
					Remotes.MoveInput:FireServer(ship.Position)
				elseif stickVec.Magnitude > 0.15 then
					local reach = playing and (Config.MOTHERSHIP.MOVE_LEASH or 70) or LOBBY_AHEAD
					Remotes.MoveInput:FireServer(ship.Position + camDir(stickVec.X, stickVec.Y) * reach)
				else
					Remotes.MoveInput:FireServer(ship.Position)
				end
			end
		elseif buildMode then
			-- Đang chọn chỗ xây -> giữ Tàu Mẹ ĐỨNG YÊN (gửi chính vị trí của nó)
			local ship = getMyShip()
			if ship then
				Remotes.MoveInput:FireServer(ship.Position)
			end
		elseif playing then
			local ship = getMyShip()
			if player:GetAttribute("BuildingUIOpen") then
				-- Đang mở UI nâng cấp nhà -> Tàu Mẹ ĐỨNG YÊN.
				if ship then Remotes.MoveInput:FireServer(ship.Position) end
			elseif point then
				-- Leash: kẹp đích cách Tàu Mẹ tối đa MOVE_LEASH (trỏ chuột kéo trong 1 khoảng).
				if ship then
					local sp = ship.Position
					local flat = Vector3.new(point.X - sp.X, 0, point.Z - sp.Z)
					local leash = Config.MOTHERSHIP.MOVE_LEASH or 1e9
					if flat.Magnitude > leash then
						point = sp + flat.Unit * leash
					end
				end
				Remotes.MoveInput:FireServer(point)
			end
		else
			-- Lobby: lái bằng WASD (giữ = tiến theo hướng phím, thả = dừng).
			local ship = getMyShip()
			if ship then
				local dir = wasdDir()
				if dir.Magnitude > 0 then
					Remotes.MoveInput:FireServer(ship.Position + dir.Unit * LOBBY_AHEAD)
				else
					Remotes.MoveInput:FireServer(ship.Position)
				end
			end
		end
	end
end)
