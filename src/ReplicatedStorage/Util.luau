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

return Util
