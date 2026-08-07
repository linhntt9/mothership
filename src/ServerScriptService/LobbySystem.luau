--[[
	LobbySystem.luau
	----------------
	Dựng SẢNH 3D của lobby: 1 sàn + 3 "cổng" (Class Shop / Skin Shop / Vào trận).
	Tàu Mẹ của người chơi được spawn trong sảnh (Main điều phối) và bay quanh bằng
	hệ di chuyển sẵn có; client phát hiện Tàu Mẹ vào vùng cổng (theo Config.LOBBY.
	ZONES) để mở panel tương ứng.

	Chỉ tồn tại khi ở trạng thái LOBBY. startMatch dọn sảnh (clearHall) rồi dựng
	arena; về lobby thì ngược lại. Toàn bộ part gom trong Folder "Lobby" -> xoá gọn.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

local LobbySystem = {}

-- Bảng hiệu nổi trên 1 part.
local function makeLabel(parent, text, color, y)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 240, 0, 46)
	bb.StudsOffsetWorldSpace = Vector3.new(0, y, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = parent
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.Text = text
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	local st = Instance.new("UIStroke"); st.Thickness = 2.5; st.Color = color; st.Parent = l
	local cap = Instance.new("UITextSizeConstraint"); cap.MaxTextSize = 28; cap.Parent = l
	l.Parent = bb
	bb.Parent = parent
end

function LobbySystem.clearHall()
	local f = Workspace:FindFirstChild("Lobby")
	if f then f:Destroy() end
end

function LobbySystem.buildHall()
	LobbySystem.clearHall()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = Workspace

	local S = Config.LOBBY.SIZE
	local R = Config.LOBBY.ZONE_RADIUS
	local half = S / 2

	-- Sàn RỘNG hơn sảnh (kéo dài ra ngoài tường) -> nhìn như phòng đặt trên nền arena.
	local floor = Instance.new("Part")
	floor.Name = "LobbyFloor"
	floor.Anchored = true
	floor.Size = Vector3.new(S * 2.2, 4, S * 2.2)
	floor.Position = Vector3.new(0, -2, 0)
	floor.Color = Color3.fromRGB(206, 220, 238)
	floor.Material = Enum.Material.SmoothPlastic
	floor.TopSurface = Enum.SurfaceType.Smooth
	floor.Parent = folder

	-- Tường bao 3 phía (bắc + 2 bên) tạo "phòng" vật lý; chừa phía camera (nam) mở.
	local WALL_H = 22
	local function wall(cx, cz, sx, sz)
		local w = Instance.new("Part")
		w.Anchored = true
		w.Size = Vector3.new(sx, WALL_H, sz)
		w.Position = Vector3.new(cx, WALL_H / 2, cz)
		w.Color = Color3.fromRGB(228, 236, 248)
		w.Material = Enum.Material.SmoothPlastic
		w.Parent = folder
		local trim = Instance.new("Part") -- viền neon đỉnh tường
		trim.Anchored = true
		trim.Size = Vector3.new(sx, 1.5, sz)
		trim.Position = Vector3.new(cx, WALL_H + 0.75, cz)
		trim.Color = Color3.fromRGB(120, 180, 255)
		trim.Material = Enum.Material.Neon
		trim.Parent = folder
	end
	wall(0, -half, S, 4)   -- bắc (phông sau, nơi đặt các cổng)
	wall(-half, 0, 4, S)   -- tây
	wall(half, 0, 4, S)    -- đông

	for _, z in ipairs(Config.LOBBY.ZONES) do
		-- Đế phát sáng = vùng kích hoạt (bán kính = ZONE_RADIUS)
		local pad = Instance.new("Part")
		pad.Name = "Zone_" .. z.id
		pad.Anchored = true
		pad.CanCollide = false
		pad.CanQuery = false
		pad.Shape = Enum.PartType.Cylinder
		pad.Size = Vector3.new(1, R * 2, R * 2)
		pad.CFrame = CFrame.new(z.x, 0.3, z.z) * CFrame.Angles(0, 0, math.rad(90))
		pad.Color = z.color
		pad.Material = Enum.Material.Neon
		pad.Transparency = 0.55
		pad.Parent = folder

		if z.id == "gate" then
			-- Cổng dịch chuyển: 2 trụ + thanh ngang phát sáng
			for _, sx in ipairs({ -20, 20 }) do
				local pillar = Instance.new("Part")
				pillar.Anchored = true
				pillar.Size = Vector3.new(6, 44, 6)
				pillar.Position = Vector3.new(z.x + sx, 22, z.z)
				pillar.Color = z.color
				pillar.Material = Enum.Material.Neon
				pillar.Parent = folder
			end
			local bar = Instance.new("Part")
			bar.Anchored = true
			bar.Size = Vector3.new(52, 6, 6)
			bar.Position = Vector3.new(z.x, 46, z.z)
			bar.Color = z.color
			bar.Material = Enum.Material.Neon
			bar.Parent = folder
			makeLabel(bar, "▶ " .. z.label, z.color, 10)
		elseif z.id == "chest" then
			-- Rương vàng: thân + nắp + khoá phát sáng, đặt ngay giữa vùng.
			local body = Instance.new("Part")
			body.Anchored = true
			body.Size = Vector3.new(20, 12, 13)
			body.Position = Vector3.new(z.x, 6, z.z)
			body.Color = Color3.fromRGB(150, 100, 40)
			body.Material = Enum.Material.WoodPlanks
			body.Parent = folder
			local lid = Instance.new("Part")
			lid.Anchored = true
			lid.Size = Vector3.new(20.4, 6, 13.4)
			lid.Position = Vector3.new(z.x, 14, z.z)
			lid.Color = Color3.fromRGB(150, 100, 40)
			lid.Material = Enum.Material.WoodPlanks
			lid.Parent = folder
			for _, part in ipairs({ body, lid }) do
				local band = Instance.new("Part") -- viền vàng phát sáng
				band.Anchored = true
				band.Size = part.Size + Vector3.new(0.6, -part.Size.Y + 2.2, 0.6)
				band.Position = part.Position
				band.Color = z.color
				band.Material = Enum.Material.Neon
				band.Parent = folder
			end
			local lock = Instance.new("Part") -- khoá phía trước
			lock.Anchored = true
			lock.Size = Vector3.new(3.4, 4, 1)
			lock.Position = Vector3.new(z.x, 12, z.z + 6.7)
			lock.Color = z.color
			lock.Material = Enum.Material.Neon
			lock.Parent = folder
			makeLabel(lid, "🎁 " .. z.label, z.color, 12)
		else
			-- Gian hàng: 1 bục + bảng hiệu phía sau vùng kích hoạt
			local booth = Instance.new("Part")
			booth.Anchored = true
			booth.Size = Vector3.new(34, 18, 14)
			booth.Position = Vector3.new(z.x, 9, z.z - R - 8)
			booth.Color = Color3.fromRGB(40, 46, 62)
			booth.Material = Enum.Material.Metal
			booth.Parent = folder
			makeLabel(booth, z.label, z.color, 17)
		end
	end

	-- Tắt bóng đổ cho toàn sảnh (sạch, nhẹ).
	for _, p in ipairs(folder:GetDescendants()) do
		if p:IsA("BasePart") then p.CastShadow = false end
	end

	return folder
end

return LobbySystem
