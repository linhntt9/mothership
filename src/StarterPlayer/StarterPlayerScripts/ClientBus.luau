--[[
	ClientBus.luau
	--------------
	Kênh liên lạc nội bộ giữa các script CLIENT (cùng chạy trong PlayerScripts).
	Dùng để HUD (nút hotbar) báo cho InputController biết "vào chế độ đặt building".
]]

local ClientBus = {}

-- Fire(buildingType: string) khi người chơi bấm nút xây trên hotbar.
ClientBus.enterBuild = Instance.new("BindableEvent")

-- Fire(part: BasePart | nil) khi click 1 building của mình (mở panel Nâng cấp/Bán);
-- nil = bỏ chọn.
ClientBus.selectBuilding = Instance.new("BindableEvent")

-- Fire() để huỷ chế độ đặt building (nút ✕ trên mobile).
ClientBus.cancelBuild = Instance.new("BindableEvent")

-- Fire(open: bool) mở/đóng panel Heroes (khi Tàu Mẹ vào/ra vùng CLASS ở sảnh).
ClientBus.openHeroes = Instance.new("BindableEvent")

return ClientBus
