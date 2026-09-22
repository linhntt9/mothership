--[[
	MothershipAvatar.client.luau
	----------------------------
	Gắn AVATAR (ảnh đầu người chơi) nổi TRÊN ĐẦU mỗi Tàu Mẹ của NGƯỜI CHƠI trong
	thế giới 3D — giúp nhận ra ai là người, ai là bot. Thuần client (thumbnail load
	ở client), KHÔNG đụng server/logic. Bot (id âm) không có avatar -> bỏ qua.

	Nhận diện chủ qua tên part: "Mothership_<userId>" (userId > 0 = người chơi).
	BillboardGui parent thẳng vào part nên tự biến mất khi Tàu Mẹ bị huỷ.
]]

local Workspace = game:GetService("Workspace")

local seen = setmetatable({}, { __mode = "k" }) -- part -> true (weak: part huỷ thì tự dọn)

local function attach(part)
	if not part:IsA("BasePart") or seen[part] then return end
	local id = tonumber(tostring(part.Name):match("^Mothership_(-?%d+)$"))
	if not id or id <= 0 then return end -- chỉ người chơi (bot id âm)
	seen[part] = true

	local bb = Instance.new("BillboardGui")
	bb.Name = "PlayerAvatar"
	bb.Size = UDim2.fromOffset(60, 60)
	bb.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 7, 0) -- nổi phía trên tàu
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 700
	bb.Adornee = part
	bb.Parent = part

	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
	img.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(id) .. "&w=150&h=150"
	img.Parent = bb
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = img
	local s = Instance.new("UIStroke"); s.Thickness = 2.5; s.Transparency = 0.15; s.Color = part.Color; s.Parent = img -- viền màu team
end

local function watch(folder)
	for _, p in ipairs(folder:GetChildren()) do attach(p) end
	folder.ChildAdded:Connect(attach)
end

local mf = Workspace:FindFirstChild("Motherships")
if mf then watch(mf) end
Workspace.ChildAdded:Connect(function(child)
	if child.Name == "Motherships" then watch(child) end
end)
