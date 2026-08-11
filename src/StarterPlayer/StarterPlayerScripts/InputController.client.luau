--[[
	InputController.client.luau
	---------------------------
	Đọc input và gửi Ý ĐỊNH lên server (không tự quyết định gì).

	M0  Move  : mỗi frame tính world-point con trỏ (cắt tia camera với mặt Y=0),
	            gửi MoveInput ~10Hz -> server steer Tàu Mẹ.
	M1  Mua   : phím 1-4 = mua Drone/Frigate/Destroyer/Plasma (giờ tốn scrap).
	M2  Debug : phím E = gọi hạm đội địch.
	M3  Split : bấm Space = phân hạch (Lordz) — mỗi lần nhân đôi số cụm (tối đa 16),
	            các cụm toả vòng quanh Tàu Mẹ; ngừng bấm vài giây thì tự gộp lại.
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
-- Raycast tìm ĐỐI TƯỢNG địch (Tàu Mẹ / quân / công trình) dưới con trỏ -> focus-fire.
local function enemyPartUnderCursor(screenPos)
	-- Ưu tiên TÀU MẸ địch: nếu con trỏ ở gần thân 1 Tàu Mẹ (không phải của mình) thì
	-- chọn nó ngay — kể cả khi fleet địch vây quanh (raycast dễ trúng quân che trước).
	local pt = cursorWorldPoint(screenPos)
	local mf = Workspace:FindFirstChild("Motherships")
	if pt and mf then
		local best, bestD
		for _, p in ipairs(mf:GetChildren()) do
			if p:IsA("BasePart") and p.Name ~= ("Mothership_" .. player.UserId) then
				local dx, dz = p.Position.X - pt.X, p.Position.Z - pt.Z
				local d = math.sqrt(dx * dx + dz * dz)
				local pickR = math.max(p.Size.X, p.Size.Z) / 2 + 8 -- bán kính chọn (lề 8 studs)
				if d <= pickR and (not bestD or d < bestD) then best, bestD = p, d end
			end
		end
		if best then return best end
	end
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	local folders = {}
	for _, name in ipairs({ "Motherships", "Units", "Buildings" }) do
		local f = Workspace:FindFirstChild(name)
		if f then folders[#folders + 1] = f end
	end
	if #folders == 0 then return nil end
	local mp = screenPos or UserInputService:GetMouseLocation()
	local ray = cam:ScreenPointToRay(mp.X, mp.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = folders
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 3000, params)
	return result and result.Instance or nil
end

-- Viền đỏ đánh dấu mục tiêu focus-fire đang chọn (thuần client).
local focusHL = Instance.new("Highlight")
focusHL.Name = "FocusTarget"
focusHL.FillTransparency = 0.75
focusHL.FillColor = Color3.fromRGB(255, 70, 70)
focusHL.OutlineColor = Color3.fromRGB(255, 40, 40)
focusHL.DepthMode = Enum.HighlightDepthMode.Occluded
focusHL.Enabled = false
focusHL.Parent = Workspace

-- Đặt/bỏ focus-fire: báo server + cập nhật viền. Bỏ qua nếu trỏ trúng Tàu Mẹ của MÌNH.
local function setFocus(part)
	if part and part.Name == ("Mothership_" .. player.UserId) then part = nil end
	Remotes.SetAttackTarget:FireServer(part) -- server tự lọc địch/bạn; nil = bỏ focus
	focusHL.Adornee = part
	focusHL.Enabled = part ~= nil
end

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
				-- Click ĐỐI TƯỢNG địch -> focus-fire CẢ fleet; click nền trống -> bỏ focus.
					setFocus(enemyPartUnderCursor())
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
		Remotes.SplitInput:FireServer() -- Space = phân hạch +1 bậc (Lordz), tự gộp sau vài giây
	elseif input.KeyCode == Enum.KeyCode.Escape then
		if buildMode then exitBuildMode() end
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
	-- Hỗ trợ cả WASD lẫn phím mũi tên (↑↓←→).
	local D = UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right)
	local A = UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left)
	local W = UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up)
	local S = UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down)
	local x = (D and 1 or 0) - (A and 1 or 0)
	local z = (W and 1 or 0) - (S and 1 or 0)
	if x == 0 and z == 0 then return Vector3.zero end
	return camDir(x, z)
end

-- ===== MOBILE (cảm ứng): joystick di chuyển + chạm để đặt/chọn nhà =====
local isTouch = UserInputService.TouchEnabled
local stickVec = Vector2.new(0, 0) -- hướng joystick (-1..1): X=phải, Y=tới
local dragWorld = nil              -- world point dưới ngón đang KÉO (lái bằng cách di màn hình)
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

	-- ===== KÉO bất kỳ đâu (ngoài joystick/GUI) để LÁI =====
	-- Một chạm chưa rõ TAP hay KÉO: di quá ngưỡng -> thành KÉO (lái tới điểm dưới ngón).
	local moveTouch, candidate, candStart = nil, nil, nil
	local DRAG_THRESH = 12
	UserInputService.InputBegan:Connect(function(input, gp)
		if input.UserInputType ~= Enum.UserInputType.Touch or gp then return end -- gp: chạm trúng nút GUI
		if input == joyTouch then return end -- joystick tự lo
		candidate = input
		candStart = Vector2.new(input.Position.X, input.Position.Y)
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		if input == candidate and candStart
			and (Vector2.new(input.Position.X, input.Position.Y) - candStart).Magnitude > DRAG_THRESH then
			moveTouch = input; candidate = nil -- đã di đủ xa -> chuyển sang LÁI
		end
		if input == moveTouch then
			dragWorld = cursorWorldPoint(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == moveTouch then moveTouch = nil; dragWorld = nil end
		if input == candidate then candidate = nil end
	end)

	-- TAP (chạm nhanh) thế giới: build -> đặt nhà · nhà mình -> panel · còn lại -> khoá mục tiêu địch.
	UserInputService.TouchTapInWorld:Connect(function(pos, processedByUI)
		if processedByUI or not playing then return end
		if buildMode then
			local pt = cursorWorldPoint(pos)
			if pt then Remotes.PlaceBuilding:FireServer(buildMode, pt) end
			exitBuildMode()
		else
			local bpart = buildingUnderCursor(pos)
			if bpart and bpart:GetAttribute("OwnerUserId") == player.UserId then
				ClientBus.selectBuilding:Fire(bpart) -- nhà mình -> nâng cấp/bán
			else
				local enemy = enemyPartUnderCursor(pos)
				if enemy then
					setFocus(enemy) -- tap tàu/quân địch -> CẢ fleet focus-fire (đội split lao vào địch)
				else
					setFocus(nil) -- bỏ focus...
					local pt = cursorWorldPoint(pos)
					if pt then Remotes.SplitAim:FireServer(pt) end -- ...và LÁI đội split tới điểm tap (nếu đang split)
				end
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
			-- MOBILE: lái bằng KÉO màn hình (ưu tiên) hoặc joystick. Build/mở UI nhà -> đứng yên.
			local ship = getMyShip()
			if ship then
				local sp = ship.Position
				-- Người chơi tự điều khiển -> huỷ auto-lái tới cổng.
				if ClientBus.autoGo and (dragWorld or stickVec.Magnitude > 0.15) then ClientBus.autoGo = nil end
				if buildMode or player:GetAttribute("BuildingUIOpen") then
					Remotes.MoveInput:FireServer(sp)
				elseif dragWorld then
					-- Kéo màn hình: lái tới điểm dưới ngón (kẹp leash như PC) + AimInput cho vệ tinh split.
					Remotes.AimInput:FireServer(dragWorld)
					local flat = Vector3.new(dragWorld.X - sp.X, 0, dragWorld.Z - sp.Z)
					local leash = playing and (Config.MOTHERSHIP.MOVE_LEASH or 1e9) or 1e9
					local target = (flat.Magnitude > leash) and (sp + flat.Unit * leash) or dragWorld
					Remotes.MoveInput:FireServer(target)
				elseif stickVec.Magnitude > 0.15 then
					local reach = playing and (Config.MOTHERSHIP.MOVE_LEASH or 70) or LOBBY_AHEAD
					Remotes.MoveInput:FireServer(sp + camDir(stickVec.X, stickVec.Y) * reach)
				elseif (not playing) and ClientBus.autoGo then
					-- Sảnh: chạm cổng -> Tàu Mẹ TỰ lái tới đó (tới nơi thì applyZone tự vào trận).
					local g = ClientBus.autoGo
					if (Vector3.new(g.X - sp.X, 0, g.Z - sp.Z)).Magnitude < 8 then ClientBus.autoGo = nil end
					Remotes.MoveInput:FireServer(Vector3.new(g.X, sp.Y, g.Z))
				else
					Remotes.MoveInput:FireServer(sp)
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
					Remotes.AimInput:FireServer(point) -- con trỏ THÔ (trước leash) -> vệ tinh split chase
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
