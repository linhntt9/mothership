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

-- Fire(tabName?: string) mở Index (bách khoa) — gọi từ nút sidebar sảnh / HUD.
--   tabName: "Quân" | "Công trình" | "Tàu Mẹ" (nil = tab hiện tại).
ClientBus.openIndex = Instance.new("BindableEvent")

-- Fire() mở panel Quests (gọi từ nút sidebar "Quest" ở sảnh).
ClientBus.openQuests = Instance.new("BindableEvent")

-- (dev) Cờ hiện vị trí bot trên minimap (bật/tắt từ bảng ⚙). Minimap đọc mỗi lần vẽ.
ClientBus.showBots = false

-- (mobile lobby) Vector3 | nil: điểm Tàu Mẹ TỰ LÁI tới (chạm cổng -> tàu tự đi vào).
-- InputController đọc ở nhánh sảnh; huỷ khi người chơi tự kéo tay.
ClientBus.autoGo = nil

return ClientBus
