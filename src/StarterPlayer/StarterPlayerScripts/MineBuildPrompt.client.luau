--[[
	MineBuildPrompt.client.luau
	---------------------------
	Lái Tàu Mẹ tới gần mỏ TRỐNG (<= MINE_PROMPT_REACH) -> tự hiện:
	  • GHOST translucent bám lên mỏ (preview vị trí xây)
	  • Prompt "[E] Build Mine" nổi trên mỏ
	Nhấn E (PC) hoặc chạm prompt (mobile) -> build ScrapMine tại mỏ đó.
	Thuần client (đo từ Tàu Mẹ). Server validate + snap như thường.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local player = Players.LocalPlayer
local myName = "Mothership_" .. player.UserId
local REACH = (Config.ECONOMY and Config.ECONOMY.MINE_PROMPT_REACH) or 85
local DEP_R = ((Config.MAP and Config.MAP.ORE_DEPOSIT_RADIUS) or 22) + 6 -- bán kính coi mỏ là "đã có mine"
local GHOST_SIZE = Vector3.new(24, 7, 24)

local current = nil -- mỏ đang được prompt

-- GHOST (preview) — luôn trong Workspace, ẩn bằng Transparency khi không có mỏ.
local ghost = Instance.new("Part")
ghost.Name = "MineGhost"
ghost.Anchored = true; ghost.CanCollide = false; ghost.CanQuery = false; ghost.CastShadow = false
ghost.Material = Enum.Material.Neon
ghost.Color = Color3.fromRGB(120, 255, 150)
ghost.Size = GHOST_SIZE
ghost.Transparency = 1
ghost.Parent = Workspace

-- PROMPT "[E] Build Mine" — BillboardGui, Adornee đổi theo mỏ hiện tại. Frame là
-- TextButton để mobile CHẠM vào cũng build được.
local bb = Instance.new("BillboardGui")
bb.Name = "MineBuildPrompt"
bb.Size = UDim2.fromOffset(150, 44)
bb.StudsOffsetWorldSpace = Vector3.new(0, 11, 0)
bb.AlwaysOnTop = true
bb.Enabled = false
bb.Parent = player:WaitForChild("PlayerGui")

local btn = Instance.new("TextButton")
btn.Size = UDim2.fromScale(1, 1); btn.AutoButtonColor = false; btn.Text = ""
btn.BackgroundColor3 = Color3.fromRGB(20, 26, 38); btn.BackgroundTransparency = 0.15
btn.Parent = bb
local uc = Instance.new("UICorner"); uc.CornerRadius = UDim.new(0, 8); uc.Parent = btn
local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(120, 255, 150); st.Thickness = 2; st.Parent = btn

local keyBadge = Instance.new("TextLabel")
keyBadge.Size = UDim2.fromOffset(30, 30); keyBadge.Position = UDim2.fromOffset(8, 7)
keyBadge.BackgroundColor3 = Color3.fromRGB(120, 255, 150); keyBadge.TextColor3 = Color3.fromRGB(10, 20, 12)
keyBadge.Font = Enum.Font.GothamBlack; keyBadge.TextSize = 18; keyBadge.Text = "E"
local kc = Instance.new("UICorner"); kc.CornerRadius = UDim.new(0, 6); kc.Parent = keyBadge
keyBadge.Parent = btn

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -46, 1, 0); label.Position = UDim2.fromOffset(44, 0); label.BackgroundTransparency = 1
label.TextColor3 = Color3.new(1, 1, 1); label.Font = Enum.Font.GothamBold; label.TextSize = 16
label.TextXAlignment = Enum.TextXAlignment.Left; label.Text = "Build Mine"
label.Parent = btn

local function flatDist2(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return dx * dx + dz * dz
end

-- Mỏ "đã có mine" nếu có 1 công trình nằm ngay trên nó.
local function isOccupied(dep)
	local bf = Workspace:FindFirstChild("Buildings")
	if not bf then return false end
	local r2 = DEP_R * DEP_R
	for _, b in ipairs(bf:GetChildren()) do
		if b:IsA("BasePart") and flatDist2(b.Position, dep.Position) <= r2 then
			return true
		end
	end
	return false
end

local function buildCurrent()
	if current and current.Parent then
		Remotes.PlaceBuilding:FireServer("ScrapMine", current.Position)
	end
end

btn.Activated:Connect(buildCurrent) -- mobile: chạm prompt
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.E then buildCurrent() end -- PC: phím E
end)

local accum = 0
RunService.RenderStepped:Connect(function(dt)
	accum += dt
	if accum < 0.1 then return end
	accum = 0

	local mf = Workspace:FindFirstChild("Motherships")
	local ship = mf and mf:FindFirstChild(myName)
	local of = Workspace:FindFirstChild("OreDeposits")
	if not ship or not of then
		current = nil; bb.Enabled = false; ghost.Transparency = 1; return
	end

	-- mỏ TRỐNG gần nhất trong tầm
	local best, bestD2 = nil, REACH * REACH
	for _, dep in ipairs(of:GetChildren()) do
		if dep:IsA("BasePart") then
			local d2 = flatDist2(ship.Position, dep.Position)
			if d2 <= bestD2 and not isOccupied(dep) then
				best, bestD2 = dep, d2
			end
		end
	end

	current = best
	if best then
		bb.Adornee = best
		bb.Enabled = true
		ghost.CFrame = CFrame.new(best.Position.X, GHOST_SIZE.Y / 2 + 1, best.Position.Z)
		ghost.Transparency = 0.55
	else
		bb.Enabled = false
		ghost.Transparency = 1
	end
end)
