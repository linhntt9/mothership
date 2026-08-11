--[[
	Remotes.luau
	------------
	Tạo & cấp phát các RemoteEvent dùng chung giữa client và server.

	- Trên SERVER: tạo folder + các RemoteEvent (nếu chưa có).
	- Trên CLIENT: chờ (WaitForChild) folder/event do server tạo ra rồi trả về.

	Nhờ vậy require từ 2 phía đều lấy đúng cùng 1 instance.

	Danh sách event dùng ở M0:
	  - MoveInput  : client -> server, gửi world-point con trỏ chuột (throttle ~10Hz)

	(Các event của Split / Buy / Build sẽ được thêm ở các milestone sau,
	 chỉ cần bổ sung tên vào bảng EVENT_NAMES bên dưới.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local isServer = RunService:IsServer()

-- Tên các remote cần có. Thêm event mới ở đây khi lên milestone sau.
local EVENT_NAMES = {
	"MoveInput",   -- (M0) client -> server: world-point con trỏ
	"SpawnUnit",   -- (M1) client -> server: yêu cầu spawn 1 unit (debug, chưa tính scrap)
	"FleetUpdate", -- (M1) server -> client: cập nhật used/max fleet cap để HUD hiển thị
	"FireLaser",   -- (M2) server -> client: vẽ tia laser (origin, target, color)
	"SiegeCharge", -- server -> client: telegraph nạp đạn Siege (origin, target, color, duration)
	"Shockwave",   -- server -> client: VFX sóng xung Titan (center, radius, color)
	"ConeBlast",   -- server -> client: VFX nón lửa Dragon (origin, dir, range, angle, color)
	"Explosion",   -- server -> client: VFX nổ lửa AoE (center, radius) — Kamikaze lao vào nổ
	"OOBWarn",     -- server -> client: ra khỏi ranh map (giây còn lại; 0 = an toàn/ẩn) -> overlay đếm giờ
	"ProjectileVFX", -- server -> client: VFX 1 viên đạn bay (origin, dir, speed, range, radius, color)
	"GameOver",    -- (M2) server -> client: kết thúc ván ("victory" | "defeat")
	"DebugEnemy",  -- (M2) client -> server: spawn 1 hạm đội địch dummy để test combat
	"Restart",     -- (M2) client -> server: reset ván chơi
	"SplitInput",  -- (M3) client -> server: bấm Space = phân hạch +1 bậc (Lordz)
	"AimInput",    -- client -> server: con trỏ THÔ (không kẹp leash) -> vệ tinh split chase
	"SplitAim",    -- (mobile) client -> server: tap điểm trống khi ĐANG SPLIT -> lái đội split tới đó
	"SetAttackTarget", -- client -> server: click 1 đối tượng địch -> CẢ fleet focus-fire (nil = bỏ)
	-- M4 — Economy & Buildings
	"ScrapUpdate",     -- server -> client: số scrap hiện tại
	"PlaceBuilding",   -- client -> server: đặt building (type, world point)
	"CancelBuild",     -- client -> server: huỷ channel đang xây
	"BuildStatus",     -- server -> client: trạng thái channel (đang xây, progress 0..1)
	"UpgradeBuilding", -- client -> server: nâng cấp building (truyền part)
	"SellBuilding",    -- client -> server: bán building (truyền part)
	"Notify",          -- server -> client: thông báo ngắn (thiếu scrap, vị trí sai...)
	"SetConfig",       -- (dev) client -> server: sửa 1 field số trong Config lúc chạy
	"ConfigSync",      -- (dev) client xin / server trả bảng override đã lưu để hiển thị đúng
	"Leaderboard",     -- (M5) server -> client: bảng xếp hạng {name, score, isPlayer}
	"AddBot",          -- (dev) client -> server: sinh thêm 1 bot khi đang chơi
	-- Vòng đời trận (Lobby)
	"StartMatch",      -- client -> server: bấm Play ở lobby -> vào trận
	"ToLobby",         -- client -> server: về lại lobby (từ bảng kết thúc)
	"StartTest",       -- (dev) client -> server: vào SANDBOX Test Combat (nơi riêng)
	"TestSpawn",       -- (dev) client -> server: spawn quân test miễn phí (side: "me"|"dummy")
	"TestState",       -- server -> client: đang ở sandbox Test Combat? (bool) -> lọc UI/minimap
	"MatchState",      -- server -> client: "lobby" | "playing" (đổi màn)
	"SelectHero",      -- (Heroes) client -> server: chọn hero (heroId) -> buff nhóm quân
	"HeroState",       -- (Heroes) server -> client: hero đang chọn (heroId | nil)
	"ClaimGift",       -- (Gifts) client -> server: nhận quà theo mốc active-time; reply (index, ok, kind, amount)
	"QuestState",      -- (Quest) server -> client: toàn bộ trạng thái quest (daily/weekly/unique)
	"ClaimQuest",      -- (Quest) client -> server: nhận thưởng 1 quest (questId)
	"OpenChest",       -- (Chest) client -> server: mở rương; server roll + reply (ok, reward, gems, cd)
	"GemUpdate",       -- server -> client: số gem hiện tại
	"LevelUpdate",     -- server -> client: cấp người chơi (thắng +1, thua -1)
	"PricesUpdate",    -- server -> client: giá hiện tại (leo thang) của unit & công trình
	"BuildingAlert",   -- server -> client: công trình của mình bị đánh (vị trí) -> minimap báo động
}

local function getFolder()
	if isServer then
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
		return folder
	else
		return ReplicatedStorage:WaitForChild("Remotes")
	end
end

local function getEvent(folder, name)
	if isServer then
		local ev = folder:FindFirstChild(name)
		if not ev then
			ev = Instance.new("RemoteEvent")
			ev.Name = name
			ev.Parent = folder
		end
		return ev
	else
		return folder:WaitForChild(name)
	end
end

local Remotes = {}
local folder = getFolder()
for _, name in ipairs(EVENT_NAMES) do
	Remotes[name] = getEvent(folder, name)
end

return Remotes
