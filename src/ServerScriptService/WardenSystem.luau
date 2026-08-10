--[[
	WardenSystem.luau
	-----------------
	WARDEN FORTRESS — TRÙM CUỐI ở tâm map (0,0). Thiết kế theo Lordz:
	  - CORE máu khổng lồ (isWardenCore). Ra đòn KẾT LIỄU core = hạ trùm.
	  - 12 THÁP PHÁP SƯ (nổ lan AoE): 4 sát core + 8 vòng ngoài -> phạt nặng nếu gom
	    quân chạy vào bừa; phải bắn tỉa từ xa (Siege/Archer).
	  - 4 TROLL (Titan) gác cổng, lao ra chặn.
	Là phe trung lập-thù (-500): mọi phe đều đánh được & bị nó bắn.
	Hạ trùm -> thưởng Gem + scrap cho người kết liễu, RESET quân/nhà của họ, rồi Warden
	HỒI SINH cho người khác săn tiếp (trận KHÔNG kết thúc — boss lặp lại).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local BuildingSystem = require(script.Parent.BuildingSystem)
local FleetSystem = require(script.Parent.FleetSystem)
local EconomySystem = require(script.Parent.EconomySystem)
local MatchState = require(script.Parent.MatchState)

local WardenSystem = {}

local WARDEN_OWNER = -500 -- phe pháo đài (thù với tất cả; không phải player/bot)

local function spawnTower(W, x, z)
	BuildingSystem.spawnCustom(WARDEN_OWNER, {
		name = "WardenTower",
		pos = Vector3.new(x, 0, z),
		size = Vector3.new(16, 24, 16),
		color = Color3.fromRGB(180, 70, 220),
		material = Enum.Material.Neon,
		hp = W.TOWER_HP, dmg = W.TOWER_DMG, range = W.TOWER_RANGE, fireRate = W.TOWER_FIRERATE,
		aoe = W.TOWER_AOE, targeting = "STANDARD",
		projectile = true, projSpeed = W.TOWER_PROJSPEED, projRadius = 2.4,
		projColor = Color3.fromRGB(200, 90, 255), -- cầu năng lượng tím nổ lan
	})
end

function WardenSystem.spawn()
	local W = Config.WARDEN
	if not (W and W.ENABLED) then return end

	-- CORE (không tự bắn — 12 tháp lo hoả lực).
	BuildingSystem.spawnCustom(WARDEN_OWNER, {
		name = "WardenCore",
		pos = Vector3.new(0, 0, 0),
		size = Vector3.new(W.CORE_SIZE, W.CORE_SIZE * 0.7, W.CORE_SIZE),
		color = Color3.fromRGB(150, 40, 60),
		material = Enum.Material.Neon,
		hp = W.CORE_HP,
		isCore = true,
	})

	-- 4 tháp sát core + 8 tháp vòng ngoài (đều Tháp Pháp Sư AoE).
	local ni = W.TOWERS_INNER or 4
	for i = 1, ni do
		local a = (i - 1) / ni * 2 * math.pi
		spawnTower(W, math.cos(a) * W.INNER_RING, math.sin(a) * W.INNER_RING)
	end
	local no = W.TOWERS_OUTER or 8
	for i = 1, no do
		local a = (i - 1) / no * 2 * math.pi
		spawnTower(W, math.cos(a) * W.OUTER_RING, math.sin(a) * W.OUTER_RING)
	end

	-- 4 TROLL (Titan) gác cổng.
	local Y = Config.MOTHERSHIP.RADIUS or 6
	local nt = W.TROLLS or 4
	for i = 1, nt do
		local a = (i - 1) / nt * 2 * math.pi + 0.4
		FleetSystem.spawnUnit(WARDEN_OWNER, "Titan", true, Vector3.new(math.cos(a) * W.TROLL_RING, Y, math.sin(a) * W.TROLL_RING))
	end

	print(("[WardenSystem] Warden Fortress spawned (%d tháp, %d troll)."):format(ni + no, nt))
end

-- Gọi khi CORE bị hạ (CombatSystem.onWardenCore). Chạy hoãn (task.defer) để không sửa
-- danh sách unit/building ngay trong vòng lặp combat.
function WardenSystem.onCoreDestroyed(killerId)
	local W = Config.WARDEN
	task.defer(function()
		-- Thưởng + RESET người ra đòn kết liễu (chỉ player thật).
		if killerId and killerId > 0 then
			EconomySystem.addGem(killerId, W.REWARD_GEM or 500)
			EconomySystem.add(killerId, W.REWARD_SCRAP or 5000)
			if W.RESET_KILLER then
				FleetSystem.clearOwner(killerId)             -- quân về 0
				BuildingSystem.destroyOwnerBuildings(killerId) -- nhà về 0
			end
			local p = Players:GetPlayerByUserId(killerId)
			if p then
				Remotes.Notify:FireClient(p, ("⚔ Hạ WARDEN! +%d Gems (quân & nhà bị reset)"):format(W.REWARD_GEM or 500))
			end
		end
		-- Dọn phần Warden còn lại (tháp/troll) rồi HỒI SINH sau vài giây.
		BuildingSystem.destroyOwnerBuildings(WARDEN_OWNER)
		FleetSystem.clearOwner(WARDEN_OWNER)
		task.wait(W.RESPAWN_DELAY or 4)
		if MatchState.isMatch() then
			WardenSystem.spawn()
		end
	end)
end

-- Warden là building/unit trong GameState -> BuildingSystem/FleetSystem.clearAll dọn.
function WardenSystem.clearAll() end

function WardenSystem.init()
	print("[WardenSystem] ready")
end

return WardenSystem
