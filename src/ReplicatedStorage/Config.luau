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
	SIZE = 2500,              -- baseplate 2500 x 2500 studs, tâm ở (0,0) — map lớn (x5 so với proto 500)
	-- MỎ (ore deposit): nơi DUY NHẤT đặt được Scrap Mine. Có hình dạng riêng
	-- (tinh thể phát sáng) để phân biệt với mặt đất trống (chỗ đặt Hub).
	ORE_DEPOSIT_COUNT = 24,    -- nhiều mỏ cho map lớn 2500 (proto 500 dùng 5)
	ORE_DEPOSIT_MIN_GAP = 130, -- khoảng cách tối thiểu giữa 2 mỏ (studs)
	ORE_DEPOSIT_RADIUS = 8,   -- bán kính "mặt" mỏ (dùng để snap & kiểm tra đặt mine)

	-- Spawn của player & bot nằm ở các GÓC map, cách tâm SPAWN_FRAC * nửa-map.
	-- Server tính LIVE từ SIZE lúc spawn -> đổi SIZE rồi Chơi lại là spawn tự dãn
	-- theo, không rơi ra ngoài biên. 0.8 = 80% về phía góc.
	SPAWN_FRAC = 0.8,
}
Config.BOT_COUNT = 2

-- Tiền tố danh hiệu gắn trước tên mọi người chơi (nameplate, leaderboard, bảng thua).
Config.PLAYER_PREFIX = "[Captain] "

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
-- LOBBY (sảnh 3D: Tàu Mẹ bay quanh, vào vùng cổng để mở shop / vào trận)
-------------------------------------------------------------------------------
Config.LOBBY = {
	SIZE = 300,                 -- sảnh vuông SIZE x SIZE; di chuyển Tàu Mẹ bị kẹp trong sảnh
	SPAWN = { X = 0, Z = 100 }, -- Tàu Mẹ xuất hiện ở cửa sảnh (phía dưới)
	ZONE_RADIUS = 30,           -- vào bán kính này quanh 1 cổng => mở shop/cổng đó
	-- Camera sảnh: chếch từ SAU LƯNG nhìn tới (thấy cổng phía trước + chân trời),
	-- khác camera top-down trong trận. Cổng nằm phía -Z nên "trước" = -Z, camera lùi +Z.
	CAM = { HEIGHT = 42, BACK = 58, LOOK_AHEAD = 48, LOOK_UP = 10, ZOOM_MIN = 0.55, ZOOM_MAX = 2.0, ROT_SENS = 0.006 },
	SHIP_SCALE = 1.9,                -- Tàu Mẹ ở lobby to hơn cho dễ nhìn/khoe skin
	MOVE_MULT = 1.7,                 -- lobby lái nhanh/mượt hơn (nhân vào tốc độ nền)
	-- Vị trí 3 cổng trong sảnh. id dùng cho client mở đúng panel.
	ZONES = {
		{ id = "class", label = "CLASS SHOP", x = -95, z = -15,  color = Color3.fromRGB(120, 170, 255) },
		{ id = "skin",  label = "SKIN SHOP",  x = 95,  z = -15,  color = Color3.fromRGB(210, 130, 255) },
		{ id = "gate",  label = "VÀO TRẬN",   x = 0,   z = -110, color = Color3.fromRGB(90, 220, 120) },
	},
}

-------------------------------------------------------------------------------
-- CAMERA (client)
-------------------------------------------------------------------------------
Config.CAMERA = {
	HEIGHT = 100,       -- studs phía trên mothership (nhỏ = gần hơn)
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
	BUILD_CHANNEL = 0.8, -- giây khoá di chuyển khi xây (canon: xây/nâng dừng di chuyển)
	STOP_DIST = 2,       -- khoảng cách coi như đã tới đích (tránh rung quanh target)
	MOVE_LEASH = 70,     -- đích di chuyển bị kẹp cách Tàu Mẹ tối đa bấy nhiêu studs
	                     -- (trỏ chuột chỉ "kéo" trong 1 khoảng -> điều khiển kiểu steer)

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
	-- Vị trí vòng đội hình xếp theo RING của từng unit: CORE (trong) -> GUARD (giữa)
	-- -> SCREEN (ngoài). Bán kính thực do INNER_RADIUS + RING_GAP nở đồng tâm ra
	-- ngoài (≈ CORE 12 / GUARD 20 / SCREEN 28). weight & aoe nằm trong Config.UNITS.
}

-------------------------------------------------------------------------------
-- UNITS (hitscan; unit KHÔNG rời formation — vừa bay quỹ đạo vừa bắn)
-------------------------------------------------------------------------------
-- Schema mỗi unit: displayName, cost, hp, dmg, range, fireRate, speed,
--   ring (SCREEN|GUARD|CORE), weight, aoeRadius (0=đơn mục tiêu),
--   attack (HITSCAN|COLLISION), targeting (STANDARD|BUILDING_ONLY|
--   MOTHERSHIP_FLEET_ONLY|BACKLINE_SEEK|MULTI_TARGET), special (nil|GRAVITY_STUN|KAMIKAZE).
-- Bước 0: 4 unit cũ giữ nguyên chỉ số, chỉ ĐỔI RING (tank ra GUARD, pháo vào CORE).
Config.UNITS = {
	-- cost / weight (=population) / maxCount lấy theo canon Lordz. hp/dmg/range/
	-- fireRate không có trong wiki nên giữ giá trị đã tune. maxCount = trần số
	-- lượng unit loại đó 1 owner được có cùng lúc.
	Drone = { -- Soldier
		displayName = "Drone",
		cost = 15, hp = 40, dmg = 6, range = 18, fireRate = 2.0, speed = 55,
		ring = "SCREEN", weight = 1, aoeRadius = 0, maxCount = 200,
		attack = "HITSCAN", targeting = "STANDARD",
	},
	Frigate = { -- Archer
		displayName = "Frigate",
		cost = 125, hp = 120, dmg = 18, range = 40, fireRate = 1.2, speed = 32,
		ring = "CORE", weight = 2, aoeRadius = 0, maxCount = 200,
		attack = "HITSCAN", targeting = "STANDARD",
	},
	Destroyer = { -- Barbarian (canon không nêu số -> ước lượng)
		displayName = "Destroyer",
		cost = 200, hp = 600, dmg = 20, range = 22, fireRate = 0.8, speed = 22,
		ring = "GUARD", weight = 3, aoeRadius = 0, maxCount = 100,
		attack = "HITSCAN", targeting = "STANDARD",
	},
	PlasmaCruiser = { -- Mage
		displayName = "Plasma",
		cost = 450, hp = 200, dmg = 30, range = 34, fireRate = 0.6, speed = 26,
		ring = "CORE", weight = 8, aoeRadius = 12, maxCount = 125,
		attack = "HITSCAN", targeting = "STANDARD",
	},
	-- Bước 1 — biến thể targeting riêng (dùng chung khung hitscan):
	Interceptor = { -- Knight
		displayName = "Interceptor",
		cost = 75, hp = 90, dmg = 12, range = 22, fireRate = 1.6, speed = 70,
		ring = "SCREEN", weight = 2, aoeRadius = 0, maxCount = 200,
		attack = "HITSCAN", targeting = "BACKLINE_SEEK", -- ưu tiên pháo địch ở CORE
	},
	Battleship = { -- Dragon
		displayName = "Battleship",
		cost = 2500, hp = 900, dmg = 35, range = 34, fireRate = 1.0, speed = 24,
		ring = "GUARD", weight = 15, aoeRadius = 0, maxCount = 66,
		attack = "HITSCAN", targeting = "MULTI_TARGET", -- bắn tối đa 3 unit gần nhất
	},
	-- Bước 2 — pháo công thành: CHỈ bắn Building, tầm xa nhất, bắn chậm có nạp đạn.
	SiegeRailgun = { -- Ballista
		displayName = "Siege",
		cost = 1000, hp = 150, dmg = 120, range = 60, fireRate = 0.25, speed = 20,
		ring = "CORE", weight = 10, aoeRadius = 0, maxCount = 100,
		attack = "HITSCAN", targeting = "BUILDING_ONLY",
		chargeTime = 0.5, -- telegraph: nạp đạn 0.5s trước khi bắn
	},
	-- Bước 3a — CC: mỗi 1/fireRate giây phát sóng xung STUN + đẩy lệch đội hình địch.
	Titan = { -- Troll
		displayName = "Titan",
		cost = 3000, hp = 700, dmg = 15, range = 20, fireRate = 0.5, speed = 20,
		ring = "GUARD", weight = 15, aoeRadius = 0, maxCount = 5,
		attack = "HITSCAN", targeting = "STANDARD", special = "GRAVITY_STUN",
		stunRadius = 18,    -- bán kính sóng xung
		stunDuration = 1.5, -- giây địch không bắn được (refresh, không cộng dồn)
		pushStrength = 10,  -- studs đẩy lệch khỏi slot (rồi lerp về, không teleport)
	},
	-- Bước 3b — suicide: rời formation lao vào Mothership/fleet địch rồi nổ AoE.
	Kamikaze = { -- Sapper
		displayName = "Kamikaze",
		cost = 150, hp = 30, dmg = 200, range = 6, fireRate = 1, speed = 65,
		ring = "SCREEN", weight = 1, aoeRadius = 6, maxCount = 24, -- aoeRadius = bán kính nổ
		attack = "COLLISION", targeting = "MOTHERSHIP_FLEET_ONLY", special = "KAMIKAZE",
		armRange = 45, -- Mothership/fleet địch vào tầm này -> rời quỹ đạo, lao thẳng
	},
}

-------------------------------------------------------------------------------
-- SCRAP PICKUP (scrap rải rác + "mỏ" gom cụm, hút vào Tàu Mẹ)
-------------------------------------------------------------------------------
Config.PICKUP = {
	-- MẬT ĐỘ scrap: số lượng tính theo DIỆN TÍCH map (studs²) nên đổi MAP.SIZE là
	-- scrap tự co/giãn giữ mật độ. Đơn vị: "trên mỗi 100.000 studs²".
	-- (Map 2500 -> diện tích 6.25M -> 62.5 đơn vị: 5*62.5≈312 orb, 0.35*62.5≈22 cụm.)
	SCRAP_PER_100K   = 5,    -- số orb scrap lẻ duy trì / 100k studs²
	CLUSTER_PER_100K = 0.35, -- số "mỏ" (cụm scrap dày) / 100k studs²
	CLUSTER_SIZE     = 7,    -- orb mỗi mỏ
	CLUSTER_SPREAD   = 22,   -- bán kính rải orb trong 1 mỏ (studs)

	VALUE            = 30,   -- chạm 1 orb scrap = +VALUE scrap (phẳng cho mọi orb, kể cả trong cụm)

	MAGNET_RANGE     = 26,   -- Tàu Mẹ hút orb trong tầm này (studs)
	COLLECT_DIST     = 4,    -- tới khoảng này thì thu + cộng scrap
	FLY_SPEED        = 120,  -- tốc độ orb bay vào (studs/s)

	RESPAWN_INTERVAL = 2,    -- mỗi 2s bù orb lẻ cho đủ mật độ mục tiêu
	RESPAWN_BATCH    = 14,   -- số orb bù mỗi đợt (map lớn tiêu thụ nhiều hơn)
}

-------------------------------------------------------------------------------
-- COMBAT / VFX
-------------------------------------------------------------------------------
Config.COMBAT = {
	LASER_TIME = 0.08,   -- giây tia laser hiện trên client
	LASER_THICK = 0.35,  -- độ dày tia (studs)

	-- CHẮN THÂN (body-block): địch chỉ bắn được Tàu Mẹ nếu KHÔNG có unit phe-thủ
	-- nào chắn ngang đường bắn attacker -> Tàu Mẹ. Unit chắn khi khoảng cách vuông
	-- góc tới đường bắn <= (nửa bề ngang unit + BLOCK_MARGIN) và nằm giữa 2 đầu.
	-- => fleet thành "bức tường"; fleet thủng/chết thì Tàu Mẹ mới phơi mình.
	SHIP_GUARD = {
		ENABLED = true,      -- tắt để quay lại hành vi cũ (bắn xuyên fleet)
		BLOCK_MARGIN = 2,    -- lề cộng thêm vào bán kính chắn của mỗi unit (studs); to = tường "kín" hơn
		EDGE_IGNORE = 0.06,  -- bỏ qua unit quá sát attacker/ship (t ngoài [EDGE, 1-EDGE]) — tránh tự-chắn ảo
	},
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
	BUILD_SIZE_MULT = 1, -- hệ số nhân KÍCH CỠ nhà (kích cỡ nền đã ~2.5× Tàu Mẹ; tăng để to hơn)
	-- HP nhà tính theo công thức: hp(tier) = hpBase * HP_TIER_MULT^(tier-1).
	-- Config chỉ cần điền hpBase mỗi loại; nâng tier tự cộng máu theo hệ số này.
	HP_TIER_MULT = 1.5,

	-- GOLD MINE: income, chỉ đặt trên mỏ, tối đa MAX cái. hp = hpBase * scale^(tier-1).
	SCRAP_MINE = {
		MAX = 5, hpBase = 750,
		[1] = { cost = 250, income = 30 },
		[2] = { cost = 400, income = 55 },
		[3] = { cost = 800, income = 90 },
	},

	-- HOUSE (Drone Hub): +fleet cap ("population"), đất trống, 4 tier, tối đa MAX.
	DRONE_HUB = {
		MAX = 10, hpBase = 750,
		[1] = { cost = 250,  cap = 25 },
		[2] = { cost = 500,  cap = 50 },
		[3] = { cost = 750,  cap = 75 },
		[4] = { cost = 1000, cap = 100 },
	},

	-- LASER SATELLITE (Arrow Tower): tháp phòng thủ ĐƠN mục tiêu, đất trống, tối đa 30.
	-- Nâng tier = +% damage (dmgMult). base = chỉ số bắn nền.
	LASER_SAT = {
		MAX = 30, hpBase = 900,
		base = { dmg = 14, range = 42, fireRate = 1.5, aoe = 0 },
		[1] = { cost = 500,  dmgMult = 1.00 },
		[2] = { cost = 250,  dmgMult = 1.15 },
		[3] = { cost = 500,  dmgMult = 1.30 },
		[4] = { cost = 1000, dmgMult = 1.45 },
	},

	-- PLASMA SATELLITE (Mage Tower): tháp phòng thủ AoE, đất trống, tối đa 10.
	PLASMA_SAT = {
		MAX = 10, hpBase = 1000,
		base = { dmg = 26, range = 36, fireRate = 0.9, aoe = 11 },
		[1] = { cost = 1500, dmgMult = 1.00 },
		[2] = { cost = 500,  dmgMult = 1.10 },
		[3] = { cost = 1000, dmgMult = 1.20 },
		[4] = { cost = 2000, dmgMult = 1.30 },
	},

	BUILD_RANGE = 250,      -- rất rộng: đặt được ở bất kỳ mỏ nào nhìn thấy trên màn hình
	SELL_REFUND = 0.5,      -- bán building thu hồi 50% tổng scrap đã đầu tư
	RAID_LOOT = 0.5,        -- (stretch) phá building địch -> attacker +50% build cost
}

return Config
