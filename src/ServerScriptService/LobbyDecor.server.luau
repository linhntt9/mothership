--[[
	LobbyDecor.server.luau  —  CHỈ THẨM MỸ (visual-only), HOÀN TOÀN CÔ LẬP.
	------------------------------------------------------------------------
	Mục tiêu: biến sảnh thành "sci-fi space command center" (tông Starbase):
	  sàn/tường tối kim loại, viền Neon CAM, vòng trần Neon TRẮNG, cửa kính
	  toàn cảnh nhìn ra vũ trụ, hệ mặt trời hologram ở giữa, biển hiệu cam phát sáng,
	  Lighting tối + Bloom + ColorCorrection cho neon "nổ" sáng điện ảnh.

	NGUYÊN TẮC (theo yêu cầu): KHÔNG sửa bất kỳ script/logic/biến nào khác.
	  - Không require, không đụng LobbySystem/Main/Config logic.
	  - Chỉ ĐỌC: chờ Folder "Lobby" (do LobbySystem tạo) xuất hiện rồi:
	      * đổi THUỘC TÍNH (Material/Color/Transparency) của part sẵn có,
	      * THÊM part trang trí (đều Anchored, CanCollide=false, CanQuery=false —
	        không ảnh hưởng va chạm / raycast con trỏ / mặt phẳng Y=0),
	      * set Lighting (khôi phục nguyên trạng khi rời sảnh -> không đổi visual trận).
	  - Mọi decor parent VÀO folder "Lobby" nên clearHall() dọn giúp, không rò rỉ.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local InsertService = game:GetService("InsertService")

-- ===== SKYBOX (asset id) — sảnh vs trận/test =====
local LOBBY_SKYBOX = 83555979203508    -- sảnh
-- Trận/test: nebula tím + tiểu hành tinh + hành tinh hồng (giống ảnh tham chiếu).
-- Nếu chưa ưng, đổi sang 1 trong: 79185969624817 · 230057997 · 158838449 · 107689530722174
local MATCH_SKYBOX = 101231340581451   -- "Purple Nebula Complex Space Skybox"

-- Đặt skybox từ asset id. Ưu tiên nạp asset dạng Sky (LoadAsset); nếu asset là
-- ẢNH thì fallback gán 6 mặt = ảnh đó. Luôn chỉ để 1 Sky trong Lighting.
local function setSkybox(assetId)
	for _, s in ipairs(Lighting:GetChildren()) do
		if s:IsA("Sky") then s:Destroy() end
	end
	-- Thử nạp asset (thường skybox toolbox = Sky có sẵn 6 mặt).
	local ok, model = pcall(function() return InsertService:LoadAsset(assetId) end)
	if ok and model then
		local sky = model:FindFirstChildWhichIsA("Sky", true)
		if sky then
			sky.Name = "Sky"; sky.Parent = Lighting
			model:Destroy()
			return
		end
		model:Destroy()
	end
	-- Fallback: asset là ẢNH -> gán cả 6 mặt.
	local ref = "rbxassetid://" .. tostring(assetId)
	local sky = Instance.new("Sky")
	sky.Name = "Sky"
	sky.SkyboxBk = ref; sky.SkyboxDn = ref; sky.SkyboxFt = ref
	sky.SkyboxLf = ref; sky.SkyboxRt = ref; sky.SkyboxUp = ref
	sky.Parent = Lighting
end

-- ===== BẢNG MÀU =====
local ORANGE = Color3.fromRGB(255, 120, 22)   -- accent chính (viền, sàn, hologram)
local WHITE  = Color3.fromRGB(238, 244, 255)   -- accent phụ (vòng trần, spotlight)
local DARK   = Color3.fromRGB(22, 24, 30)       -- kết cấu tối
local DARK2  = Color3.fromRGB(12, 13, 17)       -- sàn
local GLASS  = Color3.fromRGB(26, 40, 66)       -- kính (ngả xanh lạnh)

-- ===== HELPERS DỰNG PART =====
local function part(parent, size, cf, color, material, transparency)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false      -- không chắn raycast con trỏ / hover
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.Parent = parent
	return p
end

-- Vòng tròn ghép từ `seg` đoạn (đủ mượt). y = cao độ; radius = bán kính; h/t = cao/dày đoạn.
local function ring(parent, cx, cz, y, radius, seg, h, t, color, material, transparency)
	local step = 2 * math.pi / seg
	local segLen = (2 * math.pi * radius / seg) * 1.06 -- hơi chờm để liền mạch
	local center = Vector3.new(cx, y, cz)
	for i = 0, seg - 1 do
		local a = i * step
		local pos = Vector3.new(cx + math.cos(a) * radius, y, cz + math.sin(a) * radius)
		-- lookAt: -Z hướng vào tâm (bán kính), X tiếp tuyến -> size.X=chiều dài đoạn.
		part(parent, Vector3.new(segLen, h, t), CFrame.lookAt(pos, center), color, material, transparency)
	end
end

-- ===== HỆ MẶT TRỜI HOLOGRAM (xoay bằng Heartbeat của CHÍNH script này) =====
local activeSolar = nil -- { center = Vector3, bodies = { {part, r, speed, ang, tilt}, ... } }

local function buildSolar(parent, center)
	-- Mặt trời: cầu Neon cam mờ + PointLight.
	local sun = part(parent, Vector3.new(7, 7, 7), CFrame.new(center), ORANGE, Enum.Material.Neon, 0.25)
	sun.Shape = Enum.PartType.Ball
	local pl = Instance.new("PointLight")
	pl.Color = Color3.fromRGB(255, 170, 90); pl.Range = 34; pl.Brightness = 3; pl.Parent = sun

	local defs = {
		{ r = 10, spd = 0.85, sz = 1.6, col = Color3.fromRGB(120, 200, 255) },
		{ r = 15, spd = 0.58, sz = 2.4, col = Color3.fromRGB(120, 255, 170) },
		{ r = 21, spd = 0.40, sz = 2.0, col = Color3.fromRGB(200, 120, 255) },
		{ r = 28, spd = 0.28, sz = 3.0, col = Color3.fromRGB(255, 150, 90) },
	}
	local bodies = {}
	for i, d in ipairs(defs) do
		local ang0 = i * 1.4
		local pos = center + Vector3.new(math.cos(ang0) * d.r, 0, math.sin(ang0) * d.r)
		local pl2 = part(parent, Vector3.new(d.sz, d.sz, d.sz), CFrame.new(pos), d.col, Enum.Material.Neon, 0.15)
		pl2.Shape = Enum.PartType.Ball
		-- Trail vẽ QUỸ ĐẠO (vệt sáng theo hành tinh) — dùng thay Beam.
		local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, d.sz * 0.4, 0); a0.Parent = pl2
		local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -d.sz * 0.4, 0); a1.Parent = pl2
		local tr = Instance.new("Trail")
		tr.Attachment0 = a0; tr.Attachment1 = a1
		tr.Color = ColorSequence.new(d.col)
		tr.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1),
		})
		tr.LightEmission = 1; tr.FaceCamera = true; tr.WidthScale = NumberSequence.new(1, 0.1)
		tr.Lifetime = (2 * math.pi / d.spd) * 0.9 -- gần đủ 1 vòng -> thành đường quỹ đạo
		tr.Parent = pl2
		bodies[#bodies + 1] = { p = pl2, r = d.r, spd = d.spd, ang = ang0, tilt = 0.14 }
	end
	return { center = center, bodies = bodies }
end

-- ===== BIỂN HIỆU HOLOGRAM (BillboardGui cam phát sáng nổi trong không gian) =====
local function holoSign(parent, worldPos, text, size)
	local anchor = part(parent, Vector3.new(0.2, 0.2, 0.2), CFrame.new(worldPos), ORANGE, Enum.Material.Neon, 1)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(size or 320, (size or 320) * 0.28)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.Adornee = anchor
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1); l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack; l.TextScaled = true
	l.Text = text; l.TextColor3 = Color3.fromRGB(255, 170, 80)
	l.TextTransparency = 0.05
	local st = Instance.new("UIStroke"); st.Thickness = 2; st.Color = ORANGE; st.Transparency = 0.15; st.Parent = l
	l.Parent = bb
	bb.Parent = anchor
	return anchor
end

-- ===== RE-SKIN part SẴN CÓ + THÊM KIẾN TRÚC =====
local function decorate(folder)
	if folder:GetAttribute("SciFiDecor") then return end
	folder:SetAttribute("SciFiDecor", true)

	-- (1) Đổi THUỘC TÍNH các part sẵn có (không đổi vị trí/kích cỡ/tên -> không đụng logic).
	for _, p in ipairs(folder:GetDescendants()) do
		if p:IsA("Part") then -- lobby toàn Part; dùng Part để .Shape luôn hợp lệ
			if p.Name == "LobbyFloor" then
				p.Color = Color3.fromRGB(96, 104, 122); p.Material = Enum.Material.Metal -- sàn xám sáng ăn đèn
			elseif p.Name:match("^Zone_") then
				-- Giữ nguyên đế vùng (chỉ dấu vùng kích hoạt) — không đụng.
			elseif p.Material == Enum.Material.SmoothPlastic and p.Size.Y >= 18 then
				p.Transparency = 1 -- ẩn tường hộp cũ -> lộ vũ trụ qua kính vòng mới
			elseif p.Material == Enum.Material.Neon and p.Shape ~= Enum.PartType.Cylinder and p.Size.Y <= 3 then
				p.Color = ORANGE -- viền neon (đỉnh tường) -> cam
			elseif p.Material == Enum.Material.Metal then
				p.Color = DARK   -- bục/gian hàng -> tối
			end
		end
	end

	-- Container decor riêng (nằm TRONG folder Lobby -> clearHall tự dọn).
	local d = Instance.new("Folder"); d.Name = "SciFiDecor"; d.Parent = folder

	-- (2) SÀN: (đã bỏ ring/nan hoa neon cam theo yêu cầu) — sàn để trơn.

	-- (3) CỬA KÍNH TOÀN CẢNH: vòng kính (Glass, hơi trong) + trụ neon cam giữa các tấm.
	ring(d, 0, 0, 13.5, 145, 40, 26, 0.6, GLASS, Enum.Material.Glass, 0.45)
	for i = 0, 39 do
		local a = i * (2 * math.pi / 40)
		local pos = Vector3.new(math.cos(a) * 145, 13.5, math.sin(a) * 145)
		part(d, Vector3.new(0.7, 27, 0.7), CFrame.lookAt(pos, Vector3.new(0, 13.5, 0)),
			ORANGE, Enum.Material.Neon, 0.15)
	end
	-- Bệ chân kính (vành kim loại tối) cho ra dáng "đài quan sát".
	ring(d, 0, 0, 0.8, 145, 40, 1.6, 3.2, DARK, Enum.Material.Metal, 0)

	-- (4) TRẦN: (đã bỏ 3 vòng neon). Vài đèn nền DỊU trên cao cho đều sáng (không chói).
	local lampSpots = {
		Vector3.new(0, 34, 0), Vector3.new(60, 30, 60), Vector3.new(-60, 30, 60),
		Vector3.new(60, 30, -60), Vector3.new(-60, 30, -60),
	}
	for _, c in ipairs(lampSpots) do
		local fill = part(d, Vector3.new(1, 1, 1), CFrame.new(c), WHITE, Enum.Material.Neon, 1)
		local fpl = Instance.new("PointLight")
		fpl.Color = WHITE; fpl.Range = 130; fpl.Brightness = 1.4; fpl.Parent = fill
	end

	-- (5) HỆ MẶT TRỜI HOLOGRAM ở giữa (nổi trên đầu, không chắn lối lái).
	activeSolar = buildSolar(d, Vector3.new(0, 18, 0))

	-- (6) (đã bỏ biển hiệu STARBASE / OBSERVATION DECK theo yêu cầu).
end

-- ===== LIGHTING: preset không gian (lưu nguyên trạng để KHÔI PHỤC khi vào trận) =====
local savedLighting = nil
local function ensureEffect(className, name, props)
	local e = Lighting:FindFirstChild(name)
	if not e then
		e = Instance.new(className); e.Name = name; e.Parent = Lighting
	end
	for k, v in pairs(props) do e[k] = v end
	return e
end

local function applySpaceLighting()
	if not savedLighting then
		savedLighting = {
			Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
			Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
			EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
			EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
			ExposureCompensation = Lighting.ExposureCompensation,
			GlobalShadows = Lighting.GlobalShadows,
		}
	end
	-- Sáng vừa phải (không tối đen, cũng KHÔNG cháy trắng).
	Lighting.Ambient = Color3.fromRGB(90, 95, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(115, 120, 140)
	Lighting.Brightness = 2
	Lighting.ClockTime = 14                               -- ban ngày
	Lighting.EnvironmentDiffuseScale = 0.7
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.ExposureCompensation = 0
	Lighting.GlobalShadows = false -- tắt bóng đổ động (nặng trên mobile)

	ensureEffect("BloomEffect", "LobbyBloom", { Intensity = 0.25, Size = 24, Threshold = 1.4, Enabled = true })
	ensureEffect("ColorCorrectionEffect", "LobbyCC", {
		Contrast = 0.05, Saturation = 0.05, Brightness = 0.02,
		TintColor = Color3.fromRGB(255, 252, 248), Enabled = true,
	})
	-- Bỏ Atmosphere mù (làm tối/đục). Skybox lobby.
	local atmo = Lighting:FindFirstChild("LobbyAtmo"); if atmo then atmo:Destroy() end
	setSkybox(LOBBY_SKYBOX)
end

-- Rời sảnh -> đặt lighting TRẬN sáng vừa (nâng bóng tối để thấy rõ tàu/quân trên nền
-- không gian tối) + skybox trận. Không cháy trắng, giữ chất "space".
local function restoreLighting()
	for _, n in ipairs({ "LobbyBloom", "LobbyCC", "LobbyAtmo" }) do
		local e = Lighting:FindFirstChild(n)
		if e then e:Destroy() end
	end
	savedLighting = nil
	Lighting.Ambient = Color3.fromRGB(80, 85, 100)        -- nâng bóng cho thấy rõ trong trận
	Lighting.OutdoorAmbient = Color3.fromRGB(105, 110, 130)
	Lighting.Brightness = 2.2
	Lighting.ClockTime = 14
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.ExposureCompensation = 0
	Lighting.GlobalShadows = false                         -- tránh viền tối gắt trên part phẳng
	setSkybox(MATCH_SKYBOX)
end

-- ===== HOOK: theo dõi Folder "Lobby" xuất hiện / biến mất =====
local function onLobbyAdded(child)
	if child.Name ~= "Lobby" or not child:IsA("Folder") then return end
	task.defer(function()
		-- Chờ buildHall nạp xong part (LobbyFloor) rồi mới trang trí.
		for _ = 1, 120 do
			if child:FindFirstChild("LobbyFloor") then break end
			RunService.Heartbeat:Wait()
		end
		if child.Parent then
			applySpaceLighting()
			decorate(child)
		end
	end)
end

Workspace.ChildAdded:Connect(onLobbyAdded)
Workspace.ChildRemoved:Connect(function(child)
	if child.Name == "Lobby" then
		activeSolar = nil
		restoreLighting() -- rời sảnh (vào trận) -> trả Lighting nguyên trạng, không đổi visual trận
	end
end)

-- Nếu server đã ở sảnh sẵn khi script chạy.
local existing = Workspace:FindFirstChild("Lobby")
if existing then onLobbyAdded(existing) end

-- Xoay hệ mặt trời hologram (chỉ khi đang có sảnh).
RunService.Heartbeat:Connect(function(dt)
	local s = activeSolar
	if not s then return end
	for _, b in ipairs(s.bodies) do
		if b.p.Parent then
			b.ang += b.spd * dt
			local x = math.cos(b.ang) * b.r
			local z = math.sin(b.ang) * b.r
			local y = math.sin(b.ang) * b.r * b.tilt -- nghiêng nhẹ cho ra quỹ đạo 3D
			b.p.CFrame = CFrame.new(s.center + Vector3.new(x, y, z))
		end
	end
end)
