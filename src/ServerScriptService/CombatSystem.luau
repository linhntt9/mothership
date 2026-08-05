--[[
	CombatSystem.luau
	-----------------
	Auto-battler combat (server-authoritative, hitscan).

	Mỗi Heartbeat, với mỗi unit sẵn sàng bắn (cooldown về 0):
	  1. Tìm mục tiêu theo ƯU TIÊN: enemy Units > enemy Buildings > enemy Mothership,
	     trong đó chọn cái GẦN NHẤT còn trong tầm (range).
	  2. Gây damage tức thì (hitscan). PlasmaCruiser: damage mọi enemy trong bán
	     kính AoE quanh mục tiêu.
	  3. Bắn RemoteEvent để client vẽ tia laser (VFX ở client, damage ở server).
	  4. Reset cooldown = 1 / fireRate.

	HP về 0: unit -> huỷ part; mothership -> loại người/bot đó (game over).

	M2 dùng "enemy dummy" (bấm E) để test. Bot thật ở M5 sẽ dùng chung hệ này.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Util = require(ReplicatedStorage.Util)
local Remotes = require(ReplicatedStorage.Remotes)
local GameState = require(script.Parent.GameState)
local MothershipSystem = require(script.Parent.MothershipSystem)
local FleetSystem = require(script.Parent.FleetSystem)
local BuildingSystem = require(script.Parent.BuildingSystem)

local CombatSystem = {}

-- Còn địch (bot) nào sống không? (dùng cho điều kiện thắng)
local function anyEnemyAlive()
	for _, e in pairs(GameState.motherships) do
		if e.isBot and e.alive then
			return true
		end
	end
	return false
end

-- Xử lý Tàu Mẹ chết -> loại khỏi ván + phát GameOver.
local function killMothership(ent)
	if not ent.alive then return end
	ent.alive = false
	local ownerId = ent.ownerId
	local wasBot = ent.isBot

	if ent.part then ent.part:Destroy() end
	GameState.motherships[ownerId] = nil
	-- Unit của chủ này sẽ được FleetSystem.cleanup tự dọn (owner đã mất)

	if not wasBot then
		-- Người chơi thua
		local player = Players:GetPlayerByUserId(ownerId)
		if player then
			Remotes.GameOver:FireClient(player, "defeat")
		end
	else
		-- 1 địch chết -> nếu hết địch thì mọi người chơi còn sống đều thắng
		if not anyEnemyAlive() then
			for _, e in pairs(GameState.motherships) do
				if not e.isBot then
					local p = Players:GetPlayerByUserId(e.ownerId)
					if p then
						Remotes.GameOver:FireClient(p, "victory")
					end
				end
			end
		end
	end
end

-- Gây damage cho 1 entity (unit hoặc mothership) và xử lý chết.
local function damageEntity(ent, amount)
	if ent.kind == "Mothership" then
		if not ent.alive then return end
		ent.hp -= amount
		MothershipSystem.updateHealthBar(ent)
		if ent.hp <= 0 then
			killMothership(ent)
		end
	elseif ent.kind == "Building" then
		if not ent.part or not ent.part.Parent then return end
		ent.hp -= amount
		BuildingSystem.updateHealthBar(ent)
		if ent.hp <= 0 then
			BuildingSystem.destroyBuilding(ent)
		end
	else -- Unit
		if not ent.part or not ent.part.Parent then return end
		ent.hp -= amount
		if ent.hp <= 0 then
			ent.part:Destroy() -- FleetSystem.cleanup sẽ gỡ khỏi list + update HUD
		end
	end
end

-- Tìm mục tiêu tốt nhất cho 1 unit theo ưu tiên + gần nhất trong tầm.
local function findTarget(u)
	local pos = u.part.Position
	local myOwner = u.ownerId
	local range = u.range

	local best, bestDist

	-- 1) enemy UNITS
	for _, other in ipairs(GameState.units) do
		if other.ownerId ~= myOwner and other.part and other.part.Parent then
			local d = (other.part.Position - pos).Magnitude
			if d <= range and (not bestDist or d < bestDist) then
				best, bestDist = other, d
			end
		end
	end
	if best then return best end

	-- 2) enemy BUILDINGS
	for _, b in ipairs(GameState.buildings) do
		if b.ownerId ~= myOwner and b.part and b.part.Parent then
			local d = (b.part.Position - pos).Magnitude
			if d <= range and (not bestDist or d < bestDist) then
				best, bestDist = b, d
			end
		end
	end
	if best then return best end

	-- 3) enemy MOTHERSHIP
	for _, e in pairs(GameState.motherships) do
		if e.ownerId ~= myOwner and e.alive and e.part then
			local d = (e.part.Position - pos).Magnitude
			if d <= range and (not bestDist or d < bestDist) then
				best, bestDist = e, d
			end
		end
	end
	return best
end

-- AoE: gom mọi enemy trong bán kính rồi mới gây damage (tránh sửa bảng khi đang duyệt).
local function applyAoe(centerPos, radius, attackerOwner, dmg, primary)
	local hits = {}
	for _, other in ipairs(GameState.units) do
		if other ~= primary and other.ownerId ~= attackerOwner and other.part and other.part.Parent then
			if (other.part.Position - centerPos).Magnitude <= radius then
				table.insert(hits, other)
			end
		end
	end
	for _, e in pairs(GameState.motherships) do
		if e ~= primary and e.ownerId ~= attackerOwner and e.alive and e.part then
			if (e.part.Position - centerPos).Magnitude <= radius then
				table.insert(hits, e)
			end
		end
	end
	for _, ent in ipairs(hits) do
		damageEntity(ent, dmg)
	end
end

-- Một "attacker" (unit HOẶC mothership) bắn 1 nhịp nếu sẵn sàng.
local function fireEntity(attacker, dt)
	local part = attacker.part
	if not part or not part.Parent then return end

	attacker.cooldown = math.max(0, (attacker.cooldown or 0) - dt)
	if attacker.cooldown > 0 then return end

	local target = findTarget(attacker)
	if not target then return end

	local owner = GameState.motherships[attacker.ownerId]
	local color = (owner and owner.teamColor) or Color3.new(1, 1, 1)
	local origin = part.Position
	local tpos = target.part.Position -- chốt vị trí trước khi target có thể bị huỷ

	damageEntity(target, attacker.dmg)
	if (attacker.aoe or 0) > 0 then
		applyAoe(tpos, attacker.aoe, attacker.ownerId, attacker.dmg, target)
	end

	Remotes.FireLaser:FireAllClients(origin, tpos, color)
	attacker.cooldown = 1 / attacker.fireRate
end

local function updateCombat(dt)
	-- Units bắn
	for _, u in ipairs(GameState.units) do
		fireEntity(u, dt)
	end

	-- Motherships cũng bắn (snapshot trước vì fireEntity có thể xoá mothership chết)
	local msList = {}
	for _, e in pairs(GameState.motherships) do
		msList[#msList + 1] = e
	end
	for _, e in ipairs(msList) do
		if e.alive then
			fireEntity(e, dt)
		end
	end
end

-- (Địch dummy debug đã được thay bằng bot thật ở BotSystem — M5.)

function CombatSystem.init()
	RunService.Heartbeat:Connect(function(dt)
		updateCombat(dt)
	end)

	print("[CombatSystem] ready")
end

return CombatSystem
