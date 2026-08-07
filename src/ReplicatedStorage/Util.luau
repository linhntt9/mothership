--[[
	Util.luau
	---------
	Các hàm math helper dùng chung: lerp, clamp, xử lý vector top-down,
	xoay góc, giới hạn trong map... Giữ thuần toán, không phụ thuộc game logic.

	Quy ước: game top-down nên mọi chuyển động nằm trên mặt phẳng XZ (Y giữ nguyên).
]]

local Util = {}

-- Nội suy tuyến tính
function Util.lerp(a, b, t)
	return a + (b - a) * t
end

-- Kẹp giá trị trong [min,max]
function Util.clamp(v, min, max)
	if v < min then return min end
	if v > max then return max end
	return v
end

-- Kẹp 1 điểm (Vector3) trong biên vuông map [-half, +half] trên trục X,Z
function Util.clampToMap(pos, mapSize)
	local half = mapSize / 2
	return Vector3.new(
		Util.clamp(pos.X, -half, half),
		pos.Y,
		Util.clamp(pos.Z, -half, half)
	)
end

-- Vector hướng phẳng (bỏ thành phần Y) đã chuẩn hoá. Trả về Vector3.zero nếu quá ngắn.
function Util.flatDir(from, to)
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if d.Magnitude < 1e-4 then
		return Vector3.zero
	end
	return d.Unit
end

-- Xoay 1 vector phẳng (XZ) đi 90° sang phải. Dùng cho Split (tính hướng "phải").
function Util.rotateRight90(dir)
	-- (x,z) -> (z,-x): quay -90° quanh trục Y -> hướng bên phải khi nhìn từ trên xuống
	return Vector3.new(dir.Z, 0, -dir.X)
end

-- Vector đơn vị từ 1 góc (rad) trên mặt phẳng XZ
function Util.angleToVector(theta)
	return Vector3.new(math.cos(theta), 0, math.sin(theta))
end

-- Khoảng cách phẳng (bỏ Y) giữa 2 điểm
function Util.flatDist(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Chiếu điểm p lên đoạn thẳng a->b (mặt phẳng XZ) và trả về:
--   perpDist : khoảng cách vuông góc từ p tới ĐƯỜNG thẳng ab
--   t        : vị trí chiếu dọc đoạn, 0 = tại a, 1 = tại b (đã kẹp [0,1])
-- Dùng cho "chắn thân": unit p chắn đường bắn a(attacker)->b(ship) khi perpDist nhỏ
-- và t nằm trong khoảng giữa (không tính unit ở sau lưng attacker hoặc sau ship).
function Util.flatPointSegment(p, a, b)
	local abx, abz = b.X - a.X, b.Z - a.Z
	local apx, apz = p.X - a.X, p.Z - a.Z
	local lenSq = abx * abx + abz * abz
	if lenSq < 1e-6 then
		-- a và b trùng nhau -> "đoạn" là 1 điểm
		return Util.flatDist(p, a), 0
	end
	local t = (apx * abx + apz * abz) / lenSq
	t = Util.clamp(t, 0, 1)
	-- điểm gần nhất trên đoạn
	local cx, cz = a.X + abx * t, a.Z + abz * t
	local dx, dz = p.X - cx, p.Z - cz
	return math.sqrt(dx * dx + dz * dz), t
end

return Util
