class_name VoxCanvas
extends RefCounted
## 体素画布：以“骨骼局部体素坐标”绘制，体素 (x,y,z) 占据 [x,x+1]×[y,y+1]×[z,z+1]（单位 VOXEL）。
## 数据四周各留 1 格空边，VoxMesh 可无边界检查地快速网格化（面剔除 + AO）。
## shift：网格整体的额外偏移（体素，可为小数），用于奇数宽度的部件居中对齐骨骼。
## 颜色一律存为 RGBA8 整数（与 VoxelGrid 相同编码；alpha<1 表示自发光）。

var lo: Vector3i
var hi: Vector3i
var sx: int
var sy: int
var sz: int
var sxy: int
var data: PackedInt32Array
var shift: Vector3 = Vector3.ZERO


func _init(lo_: Vector3i, hi_: Vector3i) -> void:
	lo = lo_
	hi = hi_
	sx = hi.x - lo.x + 3
	sy = hi.y - lo.y + 3
	sz = hi.z - lo.z + 3
	sxy = sx * sy
	data = PackedInt32Array()
	data.resize(sx * sy * sz)


# ================================================================ 颜色工具

static func enc(c: Color) -> int:
	var v := c.to_rgba32()
	return v if v != 0 else 1


## 亮度缩放（保持 alpha）
static func tone(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0), c.a)


static func mixc(a: Color, b: Color, t: float) -> Color:
	return Color(lerpf(a.r, b.r, t), lerpf(a.g, b.g, t), lerpf(a.b, b.b, t), a.a)


## 生成 4 个明暗变体（用于逐体素噪声），amt 为最大幅度
static func tones4(c: Color, amt: float) -> PackedInt32Array:
	return PackedInt32Array([enc(tone(c, 1.0 - amt)), enc(tone(c, 1.0 - amt * 0.4)), enc(c), enc(tone(c, 1.0 + amt * 0.6))])


## 整数哈希（稳定、可复现）
static func h3(x: int, y: int, z: int) -> int:
	var h := x * 374761393 + y * 668265263 + z * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff


static func h1(x: int) -> int:
	return h3(x, 17, 91)


# ================================================================ 基础读写

func idx(x: int, y: int, z: int) -> int:
	return (x - lo.x + 1) + sx * (y - lo.y + 1) + sxy * (z - lo.z + 1)


func has(x: int, y: int, z: int) -> bool:
	return x >= lo.x and y >= lo.y and z >= lo.z and x <= hi.x and y <= hi.y and z <= hi.z


func get_raw(x: int, y: int, z: int) -> int:
	if x < lo.x or y < lo.y or z < lo.z or x > hi.x or y > hi.y or z > hi.z:
		return 0
	return data[(x - lo.x + 1) + sx * (y - lo.y + 1) + sxy * (z - lo.z + 1)]


func solid(x: int, y: int, z: int) -> bool:
	return get_raw(x, y, z) != 0


func set_raw(x: int, y: int, z: int, v: int) -> void:
	if x < lo.x or y < lo.y or z < lo.z or x > hi.x or y > hi.y or z > hi.z:
		return
	data[(x - lo.x + 1) + sx * (y - lo.y + 1) + sxy * (z - lo.z + 1)] = v


func put(x: int, y: int, z: int, c: Color) -> void:
	set_raw(x, y, z, enc(c))


## 只给已有体素上色
func tint_at(x: int, y: int, z: int, c: Color) -> void:
	if get_raw(x, y, z) != 0:
		set_raw(x, y, z, enc(c))


func clear_at(x: int, y: int, z: int) -> void:
	set_raw(x, y, z, 0)


func get_color(x: int, y: int, z: int) -> Color:
	return Color.hex(get_raw(x, y, z) & 0xFFFFFFFF)


# ================================================================ 形状

## 实心盒 [a,b]（含端点），noise>0 时逐体素明暗变化
func box(a: Vector3i, b: Vector3i, c: Color, noise: float = 0.0) -> void:
	var x0 := maxi(mini(a.x, b.x), lo.x)
	var x1 := mini(maxi(a.x, b.x), hi.x)
	var y0 := maxi(mini(a.y, b.y), lo.y)
	var y1 := mini(maxi(a.y, b.y), hi.y)
	var z0 := maxi(mini(a.z, b.z), lo.z)
	var z1 := mini(maxi(a.z, b.z), hi.z)
	if noise <= 0.0:
		var v := enc(c)
		for z in range(z0, z1 + 1):
			for y in range(y0, y1 + 1):
				var base := sx * (y - lo.y + 1) + sxy * (z - lo.z + 1) - lo.x + 1
				for x in range(x0, x1 + 1):
					data[base + x] = v
	else:
		# 只有盒子表面的体素需要噪声（内部不可见，直接填基色）
		var t := tones4(c, noise)
		var mid := t[2]
		for z in range(z0, z1 + 1):
			for y in range(y0, y1 + 1):
				var base := sx * (y - lo.y + 1) + sxy * (z - lo.z + 1) - lo.x + 1
				if z == z0 or z == z1 or y == y0 or y == y1:
					for x in range(x0, x1 + 1):
						data[base + x] = t[h3(x, y, z) & 3]
				else:
					for x in range(x0 + 1, x1):
						data[base + x] = mid
					data[base + x0] = t[h3(x0, y, z) & 3]
					data[base + x1] = t[h3(x1, y, z) & 3]


## 只重新上色已有体素
func paint(a: Vector3i, b: Vector3i, c: Color, noise: float = 0.0) -> void:
	var t := tones4(c, noise) if noise > 0.0 else PackedInt32Array([enc(c), enc(c), enc(c), enc(c)])
	for z in range(maxi(mini(a.z, b.z), lo.z), mini(maxi(a.z, b.z), hi.z) + 1):
		for y in range(maxi(mini(a.y, b.y), lo.y), mini(maxi(a.y, b.y), hi.y) + 1):
			for x in range(maxi(mini(a.x, b.x), lo.x), mini(maxi(a.x, b.x), hi.x) + 1):
				var i := idx(x, y, z)
				if data[i] != 0:
					data[i] = t[h3(x, y, z) & 3]


func clear(a: Vector3i, b: Vector3i) -> void:
	for z in range(maxi(mini(a.z, b.z), lo.z), mini(maxi(a.z, b.z), hi.z) + 1):
		for y in range(maxi(mini(a.y, b.y), lo.y), mini(maxi(a.y, b.y), hi.y) + 1):
			for x in range(maxi(mini(a.x, b.x), lo.x), mini(maxi(a.x, b.x), hi.x) + 1):
				data[idx(x, y, z)] = 0


## 空心盒壳（厚 1），只在盒子外表面放体素（省去不可见内部）
func shell(a: Vector3i, b: Vector3i, c: Color, noise: float = 0.0) -> void:
	box(a, b, c, noise)


## 椭球（中心/半径为体素单位，可为小数）
func ellipsoid(center: Vector3, radii: Vector3, c: Color, noise: float = 0.0) -> void:
	var t := tones4(c, noise) if noise > 0.0 else PackedInt32Array([enc(c), enc(c), enc(c), enc(c)])
	var l := Vector3i((center - radii).floor())
	var h := Vector3i((center + radii).ceil())
	for z in range(maxi(l.z, lo.z), mini(h.z, hi.z) + 1):
		for y in range(maxi(l.y, lo.y), mini(h.y, hi.y) + 1):
			for x in range(maxi(l.x, lo.x), mini(h.x, hi.x) + 1):
				var d := (Vector3(x + 0.5, y + 0.5, z + 0.5) - center) / radii
				if d.length_squared() <= 1.0:
					data[idx(x, y, z)] = t[h3(x, y, z) & 3]


## 两点之间的粗线（球刷）
func line(a: Vector3, b: Vector3, radius: float, c: Color, noise: float = 0.0) -> void:
	var steps := int(ceil(a.distance_to(b) * 2.0)) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(maxi(steps, 1)))
		if radius <= 0.5:
			put(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)), c)
		else:
			ellipsoid(p, Vector3(radius, radius, radius), c, noise)


## 以 X 中线镜像：把 x < 中线 的体素复制到对侧（覆盖）
func mirror_x_from_neg() -> void:
	var s := lo.x + hi.x
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var mx := s - x
				if mx <= x:
					break
				data[idx(mx, y, z)] = data[idx(x, y, z)]


## 表面体素描边：给指定区域中暴露在 dir 方向的体素换色（例如底边变暗）
func is_exposed(x: int, y: int, z: int, d: Vector3i) -> bool:
	return get_raw(x, y, z) != 0 and get_raw(x + d.x, y + d.y, z + d.z) == 0


## 颜色乘以系数（仅已有体素，区域内）
func darken_box(a: Vector3i, b: Vector3i, k: float) -> void:
	for z in range(maxi(mini(a.z, b.z), lo.z), mini(maxi(a.z, b.z), hi.z) + 1):
		for y in range(maxi(mini(a.y, b.y), lo.y), mini(maxi(a.y, b.y), hi.y) + 1):
			for x in range(maxi(mini(a.x, b.x), lo.x), mini(maxi(a.x, b.x), hi.x) + 1):
				var i := idx(x, y, z)
				if data[i] != 0:
					data[i] = enc(tone(Color.hex(data[i] & 0xFFFFFFFF), k))


## 统计实体体素
func count_solid() -> int:
	var n := 0
	for v in data:
		if v != 0:
			n += 1
	return n
