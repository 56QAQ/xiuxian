class_name VoxelGrid
extends RefCounted
## 稠密体素网格。每个体素存一个 RGBA8 颜色（0 表示空）。
## 颜色 alpha < 1 表示自发光：发光强度 s∈[0,1] 编码为 alpha = 1 - 0.5·s（见 glow()）。

var sx: int
var sy: int
var sz: int
var data: PackedInt32Array


func _init(size_x: int = 16, size_y: int = 16, size_z: int = 16) -> void:
	sx = size_x
	sy = size_y
	sz = size_z
	data = PackedInt32Array()
	data.resize(sx * sy * sz)


static func glow(c: Color, strength: float = 1.0) -> Color:
	return Color(c.r, c.g, c.b, 1.0 - 0.5 * clampf(strength, 0.0, 1.0))


static func encode(c: Color) -> int:
	var v := c.to_rgba32()
	return v if v != 0 else 1


static func decode(v: int) -> Color:
	return Color.hex(v & 0xFFFFFFFF)


func size() -> Vector3i:
	return Vector3i(sx, sy, sz)


func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < sx and y < sy and z < sz


func index(x: int, y: int, z: int) -> int:
	return x + sx * (y + sy * z)


func get_raw(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= sx or y >= sy or z >= sz:
		return 0
	return data[x + sx * (y + sy * z)]


func is_solid(x: int, y: int, z: int) -> bool:
	return get_raw(x, y, z) != 0


func get_color(x: int, y: int, z: int) -> Color:
	return decode(get_raw(x, y, z))


func set_raw(x: int, y: int, z: int, v: int) -> void:
	if x < 0 or y < 0 or z < 0 or x >= sx or y >= sy or z >= sz:
		return
	data[x + sx * (y + sy * z)] = v


func set_color(x: int, y: int, z: int, c: Color) -> void:
	set_raw(x, y, z, encode(c))


func clear_voxel(x: int, y: int, z: int) -> void:
	set_raw(x, y, z, 0)


## 填充盒子 [a, b]（包含两端）
func fill_box(a: Vector3i, b: Vector3i, c: Color) -> void:
	var v := encode(c)
	for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				set_raw(x, y, z, v)


## 只给已有体素上色（不新增体素）
func paint_box(a: Vector3i, b: Vector3i, c: Color) -> void:
	var v := encode(c)
	for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				if get_raw(x, y, z) != 0:
					set_raw(x, y, z, v)


func clear_box(a: Vector3i, b: Vector3i) -> void:
	for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
				set_raw(x, y, z, 0)


## 填充椭球（中心与半径以体素为单位，可为小数）
func fill_ellipsoid(center: Vector3, radii: Vector3, c: Color) -> void:
	var v := encode(c)
	var lo := Vector3i((center - radii).floor())
	var hi := Vector3i((center + radii).ceil())
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var d := (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5) - center) / radii
				if d.length_squared() <= 1.0:
					set_raw(x, y, z, v)


## 沿 Y 轴的圆柱（中心 xz、半径、y 范围）
func fill_cylinder_y(cx: float, cz: float, radius: float, y0: int, y1: int, c: Color) -> void:
	var v := encode(c)
	for z in range(int(floor(cz - radius)), int(ceil(cz + radius)) + 1):
		for x in range(int(floor(cx - radius)), int(ceil(cx + radius)) + 1):
			var dx := x + 0.5 - cx
			var dz := z + 0.5 - cz
			if dx * dx + dz * dz <= radius * radius:
				for y in range(y0, y1 + 1):
					set_raw(x, y, z, v)


## 两点之间画粗线（体素球刷）
func fill_line(a: Vector3, b: Vector3, radius: float, c: Color) -> void:
	var steps := int(ceil(a.distance_to(b) * 2.0)) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(maxi(steps, 1)))
		if radius <= 0.5:
			set_color(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)), c)
		else:
			fill_ellipsoid(p, Vector3(radius, radius, radius), c)


func count_solid() -> int:
	var n := 0
	for v in data:
		if v != 0:
			n += 1
	return n


func duplicate_grid() -> VoxelGrid:
	var g := VoxelGrid.new(sx, sy, sz)
	g.data = data.duplicate()
	return g


## 以 X 轴中线镜像（x -> sx-1-x），用于对称绘制
func mirror_x_from_left() -> void:
	for z in sz:
		for y in sy:
			for x in sx / 2:
				set_raw(sx - 1 - x, y, z, get_raw(x, y, z))
