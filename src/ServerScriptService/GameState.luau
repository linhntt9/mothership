--[[
	GameState.luau
	--------------
	Bảng trạng thái trung tâm của server. Mọi system đọc/ghi entity qua đây
	để tránh mỗi system tự giữ 1 bản dữ liệu riêng.

	M0 mới chỉ dùng `motherships`. Các bảng units/buildings/bots sẽ được các
	milestone sau dùng tới — khai báo sẵn cho gọn.

	Cấu trúc 1 mothership entry (keyed theo ownerId):
	{
		ownerId    = number,          -- UserId người chơi, hoặc id âm cho bot
		isBot      = boolean,
		part       = Part,            -- khối vật lý trong workspace
		targetPoint= Vector3,         -- điểm world con trỏ đang chỉ tới (đích di chuyển)
		facing     = Vector3,         -- hướng di chuyển gần nhất (giữ lại khi đứng yên)
		hp         = number,
		maxHp      = number,
		alive      = boolean,
	}
]]

local GameState = {}

GameState.motherships = {} -- [ownerId] = entry (xem cấu trúc ở trên)
GameState.units = {}       -- (M1+) danh sách unit
GameState.buildings = {}   -- (M4+) danh sách building
GameState.oreDeposits = {} -- (M4+) [depositPart] = { occupied = bool } — nơi đặt Scrap Mine
GameState.pickups = {}     -- (M4+) list orb scrap: { part, value, flyingTo=ownerId|nil }
GameState.activeHero = {}  -- [ownerId] = heroId (Tàu Mẹ ĐANG LÁI -> buff + tạo hình)
GameState.ownedHeroes = {} -- [ownerId] = { [heroId]=true } (Tàu Mẹ đã sở hữu; roll từ Rương)
GameState.gems = {}        -- [ownerId] = số Gems (currency phụ; hiện chưa dùng nhiều)

return GameState
