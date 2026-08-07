--[[
	MatchState.luau
	---------------
	Trạng thái vòng đời trận (server). Module THUẦN state — không require system
	nào khác để tránh vòng phụ thuộc. Các system chỉ đọc isPlaying() để tự gate
	(vd PickupSystem không bù scrap khi đang ở lobby). Việc dàn dựng bắt đầu/kết
	thúc trận (spawn/clear) do Main.server điều phối vì nó đã require mọi system.

	  "LOBBY"   : đang ở màn ụ tàu, chưa có entity trận nào.
	  "PLAYING" : đang trong trận.
]]

local MatchState = {}

MatchState.current = "LOBBY"

function MatchState.isPlaying()
	return MatchState.current == "PLAYING"
end

function MatchState.set(s)
	MatchState.current = s
end

return MatchState
