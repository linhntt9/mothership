--[[
	EconomySystem.luau
	------------------
	Kinh tế scrap (server-authoritative).

	- Mỗi INCOME_TICK giây: cộng scrap cho từng owner = tổng income của các
	  Scrap Mine họ sở hữu.
	- Mua unit (Remotes.SpawnUnit): kiểm tra đủ scrap + đủ cap -> trừ scrap ->
	  gọi FleetSystem.spawnUnit.
	- Cung cấp API scrap (get/spend/add) cho BuildingSystem dùng chung.

	scrap được lưu trên chính entry mothership (entry.scrap).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local GameState = require(script.Parent.GameState)
local FleetSystem = require(script.Parent.FleetSystem)

local EconomySystem = {}

function EconomySystem.getScrap(ownerId)
	local e = GameState.motherships[ownerId]
	return e and e.scrap or 0
end

function EconomySystem.sendScrapUpdate(ownerId)
	local player = Players:GetPlayerByUserId(ownerId)
	if player then
		Remotes.ScrapUpdate:FireClient(player, math.floor(EconomySystem.getScrap(ownerId)))
	end
end

-- Trừ scrap nếu đủ. Trả về true nếu trừ thành công.
function EconomySystem.spend(ownerId, amount)
	local e = GameState.motherships[ownerId]
	if not e then return false end
	if e.scrap < amount then return false end
	e.scrap -= amount
	if e.stats then e.stats.scrapSpent += amount end -- thống kê "scrap đã tiêu"
	EconomySystem.sendScrapUpdate(ownerId)
	return true
end

-- Cộng scrap (hoàn tiền, loot...).
function EconomySystem.add(ownerId, amount)
	local e = GameState.motherships[ownerId]
	if not e then return end
	e.scrap += amount
	EconomySystem.sendScrapUpdate(ownerId)
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
	if EconomySystem.getScrap(ownerId) < stats.cost then
		return false, "scrap"
	end

	EconomySystem.spend(ownerId, stats.cost)
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
					local inc = incomeOf(ownerId)
					if inc > 0 then
						e.scrap += inc
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
				end
			end
		end
	end)

	print("[EconomySystem] ready")
end

return EconomySystem
