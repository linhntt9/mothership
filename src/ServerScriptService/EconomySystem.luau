--[[
	EconomySystem.luau
	------------------
	Kinh tế scrap (server-authoritative).

	- Mỗi INCOME_TICK giây: cộng scrap cho từng owner = tổng income của các
	  Scrap Mine họ sở hữu.
	- Mua unit (Remotes.SpawnUnit): kiểm tra đủ scrap + đủ cap -> trừ scrap ->
	  gọi FleetSystem.spawnUnit.
	- Cung cấp API scrap (get/spend/add) cho BuildingSystem dùng chung.

	scrap LƯU BỀN theo owner (scrapByOwner) — sống qua trận<->sảnh. Level suy từ tổng scrap.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local GameState = require(script.Parent.GameState)
local FleetSystem = require(script.Parent.FleetSystem)

local EconomySystem = {}

-- Scrap & Level LƯU BỀN theo owner (sống qua trận<->sảnh; không nằm trên entry
-- nên Tàu Mẹ chết/đổi cảnh không mất). Bot (id âm) cũng dùng chung, vô hại.
local scrapByOwner = {}

local function ensure(ownerId)
	if scrapByOwner[ownerId] == nil then
		scrapByOwner[ownerId] = Config.ECONOMY.START_SCRAP -- khởi điểm (250 @ lvl1)
	end
end

function EconomySystem.getScrap(ownerId)
	ensure(ownerId)
	return scrapByOwner[ownerId]
end

-- Level SUY TỪ tổng scrap tích luỹ (theo mốc SCRAP_PER_LEVEL). Tăng khi giàu lên
-- (thắng/thu nhập), giảm khi nghèo đi (chết mất 1/2 scrap).
function EconomySystem.getLevel(ownerId)
	return 1 + math.floor(EconomySystem.getScrap(ownerId) / (Config.ECONOMY.SCRAP_PER_LEVEL or 1000))
end

-- ③ RUBBER-BAND: hệ số income theo độ giàu. Nghèo -> ~MAX (kiếm nhanh, đuổi kịp),
-- giàu -> ~MIN (kiếm chậm, chống snowball vô hạn). Đường cong mượt:
--   mult = MAX - (MAX-MIN) * scrap/(scrap + SOFTCAP)
--   scrap=0 -> MAX ; scrap=SOFTCAP -> ~giữa ; scrap->∞ -> MIN.
function EconomySystem.getIncomeMult(ownerId)
	local E = Config.ECONOMY
	local maxM = E.INCOME_MULT_MAX or 1
	local minM = E.INCOME_MULT_MIN or 1
	local soft = E.INCOME_WEALTH_SOFTCAP or 5000
	local s = EconomySystem.getScrap(ownerId)
	return maxM - (maxM - minM) * (s / (s + soft))
end

function EconomySystem.sendScrapUpdate(ownerId)
	local player = Players:GetPlayerByUserId(ownerId)
	if player then
		Remotes.ScrapUpdate:FireClient(player, math.floor(EconomySystem.getScrap(ownerId)))
		Remotes.LevelUpdate:FireClient(player, EconomySystem.getLevel(ownerId)) -- level suy từ scrap
	end
end

function EconomySystem.sendLevelUpdate(ownerId)
	local player = Players:GetPlayerByUserId(ownerId)
	if player then
		Remotes.LevelUpdate:FireClient(player, EconomySystem.getLevel(ownerId))
	end
end

-- Trừ scrap nếu đủ. Trả về true nếu trừ thành công.
function EconomySystem.spend(ownerId, amount)
	ensure(ownerId)
	if scrapByOwner[ownerId] < amount then return false end
	scrapByOwner[ownerId] -= amount
	local e = GameState.motherships[ownerId]
	if e and e.stats then e.stats.scrapSpent += amount end
	EconomySystem.sendScrapUpdate(ownerId)
	return true
end

-- Đặt thẳng số scrap (dùng cho sandbox Test: cho 1M để mua thoải mái).
function EconomySystem.setScrap(ownerId, amount)
	ensure(ownerId)
	scrapByOwner[ownerId] = amount
	EconomySystem.sendScrapUpdate(ownerId)
end

-- Cộng scrap (income, loot, thưởng...).
function EconomySystem.add(ownerId, amount)
	ensure(ownerId)
	scrapByOwner[ownerId] += amount
	EconomySystem.sendScrapUpdate(ownerId)
end

-- CHẾT: scrap tụt còn DEATH_SCRAP_KEEP (vd 1/2) + tụt 1 cấp. (Quân/công trình do
-- CombatSystem lo huỷ.) -> trừng phạt, thúc đẩy chơi cẩn thận.
function EconomySystem.onDeath(ownerId)
	ensure(ownerId)
	-- Scrap còn 1/2 -> level TỰ tụt (vì suy từ scrap). Không chỉnh level riêng.
	scrapByOwner[ownerId] = math.floor(scrapByOwner[ownerId] * (Config.ECONOMY.DEATH_SCRAP_KEEP or 0.5))
	EconomySystem.sendScrapUpdate(ownerId)
end

-- GIÁ LEO THANG unit: base * (1 + số-cùng-loại-đang-có * UNIT_PRICE_STEP).
function EconomySystem.unitCost(ownerId, unitType)
	local stats = Config.UNITS[unitType]
	if not stats then return math.huge end
	local count = 0
	for _, u in ipairs(GameState.units) do
		if u.ownerId == ownerId and u.unitType == unitType and not u.remnant then count += 1 end
	end
	return math.floor(stats.cost * (1 + count * (Config.ECONOMY.UNIT_PRICE_STEP or 0)))
end

-- GIÁ LEO THANG công trình: baseCost * (1 + số-cùng-loại-đang-có * BUILDING_PRICE_STEP).
function EconomySystem.buildingCost(ownerId, buildingType, baseCost)
	local count = 0
	for _, b in ipairs(GameState.buildings) do
		if b.ownerId == ownerId and b.buildingType == buildingType then count += 1 end
	end
	return math.floor(baseCost * (1 + count * (Config.ECONOMY.BUILDING_PRICE_STEP or 0)))
end

-- GEM (thưởng khi hạ Tàu Mẹ). Lưu THEO player (bền qua trận<->sảnh), không mất
-- khi Tàu Mẹ chết / đổi cảnh. Key = ownerId (bot cũng có nhưng không hiện).
local gemsByOwner = {}

function EconomySystem.getGems(ownerId)
	return gemsByOwner[ownerId] or 0
end

function EconomySystem.sendGemUpdate(ownerId)
	local player = Players:GetPlayerByUserId(ownerId)
	if player then
		Remotes.GemUpdate:FireClient(player, math.floor(EconomySystem.getGems(ownerId)))
	end
end

function EconomySystem.addGem(ownerId, amount)
	gemsByOwner[ownerId] = (gemsByOwner[ownerId] or 0) + amount
	EconomySystem.sendGemUpdate(ownerId)
end

-- Gửi bảng GIÁ hiện tại (đã leo thang) để HUD hiển thị đúng.
local BUILD_TIER = { ScrapMine = "SCRAP_MINE", DroneHub = "DRONE_HUB", LaserSat = "LASER_SAT", PlasmaSat = "PLASMA_SAT" }
function EconomySystem.sendPrices(ownerId)
	local player = Players:GetPlayerByUserId(ownerId)
	if not player then return end
	local units = {}
	for name in pairs(Config.UNITS) do units[name] = EconomySystem.unitCost(ownerId, name) end
	local builds = {}
	for bt, key in pairs(BUILD_TIER) do
		local tiers = Config.ECONOMY[key]
		if tiers and tiers[1] then builds[bt] = EconomySystem.buildingCost(ownerId, bt, tiers[1].cost) end
	end
	Remotes.PricesUpdate:FireClient(player, units, builds)
end

-- Tổng income/giây của owner (đọc thẳng Config theo tier -> tune sống được).
local function incomeOf(ownerId)
	local total = Config.ECONOMY.BASE_INCOME or 0 -- thu nhập nền +10/s
	for _, b in ipairs(GameState.buildings) do
		if b.ownerId == ownerId and b.buildingType == "ScrapMine" then
			local stats = Config.ECONOMY.SCRAP_MINE[b.tier]
			total += (stats and stats.income) or 0
		end
	end
	return total
end

-- Số unit loại `unitType` mà owner đang có (cho trần maxCount).
local function countUnits(ownerId, unitType)
	local n = 0
	for _, u in ipairs(GameState.units) do
		if u.ownerId == ownerId and u.unitType == unitType then n += 1 end
	end
	return n
end

-- Mua 1 unit cho owner (dùng chung cho player & bot). Trả về ok, reason.
--   reason: "cap" | "scrap" | "type" | "dead" | "max" khi thất bại.
function EconomySystem.tryBuy(ownerId, unitType)
	local stats = Config.UNITS[unitType]
	if not stats then return false, "type" end
	local owner = GameState.motherships[ownerId]
	if not owner or not owner.alive then return false, "dead" end

	-- Trần số lượng mỗi loại unit (canon Lordz).
	if stats.maxCount and countUnits(ownerId, unitType) >= stats.maxCount then
		return false, "max"
	end

	local weight = stats.weight or 1
	if FleetSystem.getUsedCap(ownerId) + weight > FleetSystem.getMaxCap(ownerId) then
		return false, "cap"
	end
	-- GIÁ LEO THANG theo số cùng loại đang có.
	local cost = EconomySystem.unitCost(ownerId, unitType)
	if EconomySystem.getScrap(ownerId) < cost then
		return false, "scrap"
	end

	EconomySystem.spend(ownerId, cost)
	FleetSystem.spawnUnit(ownerId, unitType)
	return true
end

-- Xử lý mua unit từ client (player): trừ scrap rồi spawn + báo lỗi nếu có.
local function onBuyUnit(player, unitType)
	if typeof(unitType) ~= "string" then return end -- không tin client
	local ok, reason = EconomySystem.tryBuy(player.UserId, unitType)
	if not ok then
		if reason == "cap" then
			Remotes.Notify:FireClient(player, "Đầy fleet cap!")
		elseif reason == "scrap" then
			Remotes.Notify:FireClient(player, "Không đủ scrap!")
		elseif reason == "max" then
			Remotes.Notify:FireClient(player, "Đã đạt tối đa loại quân này!")
		end
	end
end

function EconomySystem.init()
	Remotes.SpawnUnit.OnServerEvent:Connect(onBuyUnit)

	-- Income tick
	task.spawn(function()
		while true do
			task.wait(Config.ECONOMY.INCOME_TICK)
			for ownerId, e in pairs(GameState.motherships) do
				if e.alive then
					local inc = incomeOf(ownerId) * EconomySystem.getIncomeMult(ownerId) -- ③ rubber-band
					if inc > 0 then
						EconomySystem.add(ownerId, inc) -- vào kho scrap bền
						if not e.isBot then
							EconomySystem.sendScrapUpdate(ownerId)
						end
					end
				end
			end
		end
	end)

	-- Gửi scrap định kỳ cho người chơi (đồng bộ HUD khi vào trễ / sau Restart)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for ownerId, e in pairs(GameState.motherships) do
				if not e.isBot then
					EconomySystem.sendScrapUpdate(ownerId)
					EconomySystem.sendGemUpdate(ownerId)
					EconomySystem.sendLevelUpdate(ownerId)
					EconomySystem.sendPrices(ownerId)
				end
			end
		end
	end)

	print("[EconomySystem] ready")
end

return EconomySystem
