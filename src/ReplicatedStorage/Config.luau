--[[
	Config.luau
	------------
	TẤT CẢ balance numbers của game nằm ở đây. Không hard-code số rải rác
	trong các system khác — muốn tweak thì sửa đúng 1 chỗ này.

	Đơn vị:
	  - Khoảng cách / kích thước: studs
	  - Thời gian: giây (s)
	  - Máu: HP
	  - Tốc độ: studs/giây
]]

local Config = {}

-------------------------------------------------------------------------------
-- MAP
-------------------------------------------------------------------------------
Config.MAP = {
	SIZE = 500,               -- baseplate 500 x 500 studs, tâm ở (0,0)
	-- MỎ (ore deposit): nơi DUY NHẤT đặt được Scrap Mine. Có hình dạng riêng
	-- (tinh thể phát sáng) để phân biệt với mặt đất trống (chỗ đặt Hub).
	ORE_DEPOSIT_COUNT = 5,     -- rất ít mỏ, rải rác thưa
	ORE_DEPOSIT_MIN_GAP = 130, -- khoảng cách tối thiểu giữa 2 mỏ (studs) — rất thưa
	ORE_DEPOSIT_RADIUS = 8,   -- bán kính "mặt" mỏ (dùng để snap & kiểm tra đặt mine)
}

-- Vị trí spawn của người chơi: góc dưới-trái map (lưu dưới dạng x,z)
Config.PLAYER_SPAWN = { X = -200, Z = -200 }
Config.BOT_COUNT = 2

-- Bot AI (M5)
Config.BOT = {
	DECISION_INTERVAL = 1.5, -- giây giữa 2 lần "suy nghĩ"
	TARGET_MINES = 3,        -- số mine bot cố gắng xây
	AGGRESS_RATIO = 1.3,     -- fleetValue >= ratio * địch -> tấn công
	RETREAT_HP = 0.30,       -- HP < 30% -> lùi
	RETREAT_WEAK = 0.6,      -- fleetValue < 0.6 * địch -> lùi
	BUY_PER_TICK = 4,        -- số quân tối đa mua mỗi lần quyết định
}

-------------------------------------------------------------------------------
-- CAMERA (client)
-------------------------------------------------------------------------------
Config.CAMERA = {
	HEIGHT = 155,       -- studs phía trên mothership (nhỏ = gần hơn)
	TILT_OFFSET = 34,   -- lệch nhẹ theo trục Z để có góc nghiêng (0 = top-down thuần)
}

-------------------------------------------------------------------------------
-- MOTHERSHIP
-------------------------------------------------------------------------------
Config.MOTHERSHIP = {
	HP = 2000,
	SPEED = 70,          -- studs/s (tốc độ nền khi hạm đội trống)
	-- Càng nhiều quân càng nặng -> đi chậm. Tốc độ thực = SPEED * mult, với
	-- mult = clamp(1 - tổngWeight * SPEED_WEIGHT_PENALTY, SPEED_MIN_MULT, 1).
	SPEED_WEIGHT_PENALTY = 0.005, -- mỗi điểm weight giảm 0.5% tốc độ (weight giờ nặng hơn nên penalty nhỏ lại)
	SPEED_MIN_MULT = 0.55,        -- sàn: không chậm hơn 55% tốc độ nền
	RADIUS = 6,
	BUILD_CHANNEL = 0,   -- giây channel khi xây (0 = xây tức thì, không chờ)
	STOP_DIST = 2,       -- khoảng cách coi như đã tới đích (tránh rung quanh target)

	-- Mothership cũng tự đánh (M-tweak): hitscan như unit, có AoE nhẹ
	DMG = 45,
	RANGE = 48,
	FIRE_RATE = 1.5,     -- shot/s
	AOE = 10,            -- bán kính sát thương lan quanh mục tiêu
}

-------------------------------------------------------------------------------
-- FLEET CAP
-------------------------------------------------------------------------------
Config.FLEET = {
	BASE_CAP = 10,         -- cap khởi đầu; xây Drone Hub để tăng thêm
	DRONE_HUB_CAP_T1 = 8,  -- +8 cap mỗi hub tier 1
	ORBIT_SPIN = 0.3,      -- rad/s, tốc độ xoay chậm của cả hạm đội
	FOLLOW_GAIN = 10,      -- hệ số bám đội hình: tốc độ = dist * gain (càng xa càng nhanh)
	FOLLOW_MAX_MULT = 1.6, -- trần tốc độ bám = MOTHERSHIP.SPEED * mult (phải > 1 để không bị bỏ lại)

	-- Đội hình NHIỀU VÒNG ĐỒNG TÂM nở dần ra ngoài (nhìn đồ sộ như Lordz).
	-- Xếp tank ở trong, drone ở ngoài; mỗi vòng chứa nhiều unit theo chu vi,
	-- đầy thì nở ra vòng kế tiếp.
	INNER_RADIUS = 12,     -- bán kính vòng trong cùng (studs)
	RING_GAP = 8,          -- khoảng cách giữa 2 vòng đồng tâm (giãn -> trải rộng)
	UNIT_SPACING = 6,      -- khoảng cách cung giữa 2 unit trong 1 vòng
	RING_MIN_SLOTS = 6,    -- số slot tối thiểu mỗi vòng
	RING_MAX_SLOTS = 16,   -- số slot TỐI ĐA mỗi vòng: đầy là nở vòng mới -> trải rộng ra xa

	-- Chống chồng nhau (separation): unit đè lên nhau bị đẩy ra khi chạm trán.
	SEPARATION_STRENGTH = 0.4, -- phần overlap giải quyết mỗi frame (0 = tắt)
	SEPARATION_MAX = 4,        -- đẩy tối đa mỗi frame (studs) để không giật
	SPLIT_DIST = 25,       -- khoảng tách tối đa của 2 cánh khi Split
	SPLIT_RAMP = 0.4,      -- giây để tách/gộp mượt (ramp 0<->SPLIT_DIST)
	RING = {               -- bán kính các vòng quỹ đạo
		FRONT = 14,
		BACK = 22,
		OUTER = 30,
	},
	-- Weight phân hóa theo cost: rẻ = nhẹ, đắt = nặng.
	-- (cost: Drone 40 / Frigate 350 / Destroyer 500 / Plasma 1000)
	-- Ăn vào cap VÀ ghì tốc độ Tàu Mẹ -> quân đắt vừa chiếm nhiều ô vừa nặng hơn.
	WEIGHT = {
		Drone = 1,
		Frigate = 3,
		Destroyer = 5,
		PlasmaCruiser = 8,
	},
}

-------------------------------------------------------------------------------
-- UNITS (hitscan; unit KHÔNG rời formation — vừa bay quỹ đạo vừa bắn)
-------------------------------------------------------------------------------
Config.UNITS = {
	Drone = {
		cost = 40,  hp = 40,  dmg = 6,  range = 18, fireRate = 2.0, speed = 55, ring = "OUTER", aoe = 0,
	},
	Frigate = {
		cost = 350, hp = 120, dmg = 18, range = 40, fireRate = 1.2, speed = 32, ring = "BACK",  aoe = 0,
	},
	Destroyer = {
		cost = 500, hp = 600, dmg = 20, range = 22, fireRate = 0.8, speed = 22, ring = "FRONT", aoe = 0,
	},
	PlasmaCruiser = {
		cost = 1000, hp = 200, dmg = 30, range = 34, fireRate = 0.6, speed = 26, ring = "BACK", aoe = 12,
	},
}

-------------------------------------------------------------------------------
-- SCRAP PICKUP (scrap rải rác + "mỏ" gom cụm, hút vào Tàu Mẹ)
-------------------------------------------------------------------------------
Config.PICKUP = {
	TARGET_COUNT     = 70,   -- số orb scrap duy trì trên map
	CLUSTER_COUNT    = 6,    -- số "mỏ" (cụm scrap dày) lúc khởi tạo
	CLUSTER_SIZE     = 7,    -- orb mỗi mỏ
	CLUSTER_SPREAD   = 22,   -- bán kính rải orb trong 1 mỏ (studs)

	VALUE_MIN        = 8,    -- giá trị orb lẻ
	VALUE_MAX        = 20,
	CLUSTER_VALUE_MIN = 18,  -- orb trong mỏ giàu hơn
	CLUSTER_VALUE_MAX = 40,

	MAGNET_RANGE     = 26,   -- Tàu Mẹ hút orb trong tầm này (studs)
	COLLECT_DIST     = 4,    -- tới khoảng này thì thu + cộng scrap
	FLY_SPEED        = 120,  -- tốc độ orb bay vào (studs/s)

	RESPAWN_INTERVAL = 2,    -- mỗi 2s bù orb lẻ cho đủ TARGET_COUNT
	RESPAWN_BATCH    = 5,    -- số orb bù mỗi đợt
}

-------------------------------------------------------------------------------
-- COMBAT / VFX
-------------------------------------------------------------------------------
Config.COMBAT = {
	LASER_TIME = 0.08,   -- giây tia laser hiện trên client
	LASER_THICK = 0.35,  -- độ dày tia (studs)
}

-- Màu phe (đồng thời tô cho unit để phân biệt bạn/địch; loại unit phân biệt bằng
-- hình dạng + kích cỡ). Bot sau này có thể lấy màu khác từ bảng này.
Config.TEAM = {
	PLAYER = Color3.fromRGB(70, 150, 255), -- xanh
	ENEMY  = Color3.fromRGB(255, 80, 80),  -- đỏ
}

-------------------------------------------------------------------------------
-- ECONOMY
-------------------------------------------------------------------------------
Config.ECONOMY = {
	START_SCRAP = 500,
	INCOME_TICK = 1.0, -- giây

	SCRAP_MINE = {
		-- chỉ đặt được TRÊN mỏ (ore deposit), 1 mine / mỏ
		[1] = { cost = 250, income = 30, hp = 300 },
		[2] = { cost = 400, income = 55, hp = 500 },
		[3] = { cost = 800, income = 90, hp = 800 },
	},

	-- "Nhà lính": mỗi hub +25 cap (T1). Nâng T2 lên +40.
	DRONE_HUB = {
		[1] = { cost = 500, cap = 25, hp = 400 },
		[2] = { cost = 700, cap = 40, hp = 600 },
	},

	BUILD_RANGE = 250,      -- rất rộng: đặt được ở bất kỳ mỏ nào nhìn thấy trên màn hình
	SELL_REFUND = 0.5,      -- bán building thu hồi 50%
	RAID_LOOT = 0.5,        -- (stretch) phá building địch -> attacker +50% build cost
}

return Config
