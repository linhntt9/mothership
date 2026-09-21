--[[
	MusicController.client.luau
	---------------------------
	Nhạc nền tự đổi theo trạng thái trận:
	  • Lobby (sảnh)      -> Config.MUSIC.LOBBY
	  • Playing (trong trận) -> Config.MUSIC.GAMEPLAY
	Crossfade nhẹ khi chuyển. Thuần client.
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)

local M = Config.MUSIC or {}
local VOL = M.VOLUME or 0.5
local FADE = M.FADE or 1.2

local function makeTrack(id)
	local s = Instance.new("Sound")
	s.Name = "BGM_" .. tostring(id)
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Looped = true
	s.Volume = 0
	s.Parent = SoundService
	return s
end

local lobbyTrack = makeTrack(M.LOBBY or 9046476113)
local gameTrack = makeTrack(M.GAMEPLAY or 121621005771265)

local current = nil

local function switchTo(track)
	if current == track then return end
	local old = current
	current = track

	-- fade IN track mới
	if not track.IsPlaying then track:Play() end
	TweenService:Create(track, TweenInfo.new(FADE), { Volume = VOL }):Play()

	-- fade OUT track cũ rồi dừng
	if old then
		local tOut = TweenService:Create(old, TweenInfo.new(FADE), { Volume = 0 })
		tOut.Completed:Connect(function()
			if current ~= old then old:Stop() end
		end)
		tOut:Play()
	end
end

Remotes.MatchState.OnClientEvent:Connect(function(s)
	if s == "playing" then
		switchTo(gameTrack)
	else
		switchTo(lobbyTrack)
	end
end)

-- Bắt đầu ở sảnh.
switchTo(lobbyTrack)
