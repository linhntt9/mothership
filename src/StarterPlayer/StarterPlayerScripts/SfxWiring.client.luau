--[[
	SfxWiring.client.luau
	---------------------
	Móc mọi sự kiện game -> Sfx.play(...). Thuần client.
	  • laser / đạn      : Remotes.FireLaser / ProjectileVFX  -> "shot" (cull theo khoảng cách)
	  • bị tấn công      : Remotes.CombatNotify("def")        -> "alert"
	  • xây nhà          : Buildings ChildAdded (của mình)    -> "build"
	  • spawn unit       : Units ChildAdded (của mình)        -> "spawn"
	  • UI click / hover : mọi GuiButton trong PlayerGui      -> "uiClick" / "uiHover"
	(xoá/bán nhà "delete" phát ngay tại nút Sell trong HUD.)
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)
local Remotes = require(ReplicatedStorage.Remotes)
local Sfx = require(script.Parent.Sfx)

local player = Players.LocalPlayer
local myId = player.UserId
local myName = "Mothership_" .. myId
local HEAR = (Config.SFX and Config.SFX.SHOT_HEAR_DIST) or 220
local HEAR2 = HEAR * HEAR

local function myShipPos()
	local f = Workspace:FindFirstChild("Motherships")
	local s = f and f:FindFirstChild(myName)
	return s and s.Position or nil
end

-- Chỉ phát tiếng bắn nếu điểm bắn ở gần Tàu Mẹ mình (tránh nghe cả map).
local function near(pos)
	if typeof(pos) ~= "Vector3" then return false end
	local sp = myShipPos()
	if not sp then return false end
	local dx, dz = pos.X - sp.X, pos.Z - sp.Z
	return (dx * dx + dz * dz) <= HEAR2
end

-------------------------------------------------------------------------------
-- COMBAT
-------------------------------------------------------------------------------
-- Chỉ giữ tiếng LASER (hitscan). Bỏ tiếng đạn (ProjectileVFX) để combat đỡ loạn.
Remotes.FireLaser.OnClientEvent:Connect(function(origin, target)
	if near(target or origin) then Sfx.play("shot") end
end)
Remotes.CombatNotify.OnClientEvent:Connect(function(kind)
	if kind == "def" then Sfx.play("alert") end -- "def" = MÌNH bị tấn công
end)

-- Nhặt scrap (server báo khi orb bay vào) + báo lỗi/không đủ (Notify).
Remotes.ScrapCollect.OnClientEvent:Connect(function() Sfx.play("collect") end)
-- Notify: kind="ok" -> tiếng thông báo thường; còn lại -> tiếng lỗi.
Remotes.Notify.OnClientEvent:Connect(function(_, kind)
	Sfx.play(kind == "ok" and "notify" or "fail")
end)

-- Kết trận thắng/thua.
Remotes.GameOver.OnClientEvent:Connect(function(payload)
	local r = type(payload) == "table" and payload.result or payload
	if r == "victory" then Sfx.play("victory")
	elseif r == "defeat" then Sfx.play("defeat") end
end)

-- Mở rương gacha (chỉ khi roll thành công) & nhận quà.
Remotes.OpenChest.OnClientEvent:Connect(function(ok) if ok then Sfx.play("chest") end end)
Remotes.ClaimGift.OnClientEvent:Connect(function(_, ok) if ok then Sfx.play("claim") end end)

-- Vào trận.
Remotes.MatchState.OnClientEvent:Connect(function(s)
	if s == "playing" then Sfx.play("matchStart") end
end)

-- (Đã tắt tiếng nổ combat — Explosion/Shockwave/ConeBlast — để combat đỡ loạn.
--  Muốn bật lại thì nối lại các remote này -> Sfx.play("explode").)

-- Hạ Warden (broadcast toàn server).
Remotes.WardenDown.OnClientEvent:Connect(function() Sfx.play("warden") end)

-- SFX level up: ĐÃ TẮT (level suy từ scrap dao động liên tục -> gây loạn).
-- Muốn bật lại: bỏ comment khối dưới.
-- local maxLevel = nil
-- Remotes.LevelUpdate.OnClientEvent:Connect(function(lv)
-- 	if type(lv) == "number" then
-- 		if maxLevel and lv > maxLevel then Sfx.play("levelup") end
-- 		maxLevel = math.max(maxLevel or lv, lv)
-- 	end
-- end)

-------------------------------------------------------------------------------
-- XÂY NHÀ / SPAWN UNIT: nghe theo ChildAdded của mình (defer để attribute kịp set)
-------------------------------------------------------------------------------
-- Spawn unit: unit của mình xuất hiện.
local function hookUnits(folder)
	folder.ChildAdded:Connect(function(ch)
		task.defer(function()
			if ch and ch:IsA("BasePart") and ch:GetAttribute("OwnerUserId") == myId then
				Sfx.play("spawn")
			end
		end)
	end)
end

-- Xây (ScrapMine có tiếng riêng) + nâng cấp (nghe khi Tier tăng) — chỉ nhà của mình.
local function hookBuildings(folder)
	folder.ChildAdded:Connect(function(ch)
		task.defer(function()
			if not (ch and ch:IsA("BasePart") and ch:GetAttribute("OwnerUserId") == myId) then return end
			local bt = ch:GetAttribute("BuildingType")
			Sfx.play(bt == "ScrapMine" and "buildMine" or "build")
			local prevTier = ch:GetAttribute("Tier") or 1
			ch:GetAttributeChangedSignal("Tier"):Connect(function()
				local t = ch:GetAttribute("Tier") or prevTier
				-- chỉ nhà CỦA MÌNH + Tier thực sự TĂNG mới kêu (chốt an toàn với bot/địch)
				if t > prevTier and ch:GetAttribute("OwnerUserId") == myId then
					Sfx.play("upgrade")
				end
				prevTier = t
			end)
		end)
	end)
end

local hooked = {}
local function tryHook(inst)
	if hooked[inst] then return end
	if inst.Name == "Buildings" then hooked[inst] = true; hookBuildings(inst)
	elseif inst.Name == "Units" then hooked[inst] = true; hookUnits(inst) end
end
for _, c in ipairs(Workspace:GetChildren()) do tryHook(c) end
Workspace.ChildAdded:Connect(tryHook)  -- bắt cả khi folder tạo lại sau Restart

-------------------------------------------------------------------------------
-- UI: mọi GuiButton -> hover + click
-------------------------------------------------------------------------------
local hookedBtns = setmetatable({}, { __mode = "k" })
local function hookButton(btn)
	if hookedBtns[btn] then return end
	hookedBtns[btn] = true
	btn.MouseEnter:Connect(function() Sfx.play("uiHover") end)
	btn.Activated:Connect(function() Sfx.play("uiClick") end)
end

local pgui = player:WaitForChild("PlayerGui")
for _, d in ipairs(pgui:GetDescendants()) do
	if d:IsA("GuiButton") then hookButton(d) end
end
pgui.DescendantAdded:Connect(function(d)
	if d:IsA("GuiButton") then hookButton(d) end
end)
