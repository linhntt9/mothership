--[[
	TeamColors.client.luau
	----------------------
	Tô màu THEO PHE tương đối trên MỖI client (kiểu Lordz/.io):
	  • Của MÌNH (OwnerUserId == mình): XANH.
	  • Của người khác / bot: ĐỎ.
	=> trong trận (FFA) phân biệt tức thì tàu/quân mình vs địch, dù server cho mọi
	người chơi cùng màu "PLAYER". Thuần client, không đụng server/gameplay.

	Chỉ đổi màu THÂN part (không đụng deco/skin ở sảnh). Áp khi VÀO TRẬN.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local myId = Players.LocalPlayer.UserId
local FRIEND = Config.TEAM.PLAYER   -- xanh
local FOE = Config.TEAM.ENEMY       -- đỏ
local playing = false

local function tint(part)
	if not part:IsA("BasePart") then return end
	local owner = part:GetAttribute("OwnerUserId")
	if owner == nil then return end
	part.Color = (owner == myId) and FRIEND or FOE
end

-- Quét toàn bộ + tô (dùng khi vào trận).
local function tintAll()
	for _, name in ipairs({ "Units", "Motherships" }) do
		local f = Workspace:FindFirstChild(name)
		if f then
			for _, p in ipairs(f:GetChildren()) do tint(p) end
		end
	end
end

-- Bắt part mới (unit/tàu spawn) -> tô ngay.
local function hook(folderName)
	local f = Workspace:WaitForChild(folderName, 10)
	if not f then return end
	f.ChildAdded:Connect(function(p)
		if not playing then return end
		task.defer(tint, p) -- chờ attribute OwnerUserId set xong
	end)
end
hook("Units")
hook("Motherships")

Remotes.MatchState.OnClientEvent:Connect(function(s)
	playing = (s == "playing")
	if playing then
		task.defer(tintAll) -- vào trận: tô lại mọi thứ hiện có
	end
end)
