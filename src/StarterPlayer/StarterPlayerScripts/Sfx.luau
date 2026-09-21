--[[
	Sfx.luau  (ModuleScript)
	------------------------
	Phát hiệu ứng âm thanh 2D theo tên, đọc id/volume/minGap từ Config.SFX.
	- Pool sẵn vài Sound/loại -> phát chồng được, không cấp phát mỗi lần.
	- minGap chống spam (VD tiếng bắn dồn dập).
	Dùng: local Sfx = require(script.Parent.Sfx); Sfx.play("build")
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local defs = Config.SFX or {}

local Sfx = {}

local POOL = 4
local pools = {}       -- [name] = { idx, sounds = {Sound} }
local lastPlay = {}    -- [name] = os.clock() lần cuối

local function ensurePool(name, d)
	local p = pools[name]
	if p then return p end
	p = { idx = 0, sounds = {} }
	for i = 1, POOL do
		local s = Instance.new("Sound")
		s.Name = "SFX_" .. name
		s.SoundId = "rbxassetid://" .. tostring(d.id)
		s.Volume = d.volume or 0.5
		s.Parent = SoundService
		p.sounds[i] = s
	end
	pools[name] = p
	return p
end

function Sfx.play(name)
	local d = defs[name]
	if not d or not d.id then return end

	local now = os.clock()
	if d.minGap and lastPlay[name] and (now - lastPlay[name]) < d.minGap then
		return
	end
	lastPlay[name] = now

	local p = ensurePool(name, d)
	p.idx = (p.idx % POOL) + 1
	local s = p.sounds[p.idx]
	s.Volume = d.volume or 0.5
	s.TimePosition = 0
	s:Play()
end

return Sfx
