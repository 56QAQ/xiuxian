class_name VoxCanvas
extends RefCounted
## 体素画布：以“骨骼局部体素坐标”绘制，体素 (x,y,z) 占据 [x,x+1]×[y,y+1]×[z,z+1]（单位 VOXEL）。
## 数据四周各留 1 格空边，VoxMesh 可无边界检查地快速网格化（面剔除 + AO）。
## shift：网格整体的额外偏移（体素，可为小数），用于奇数宽度的部件居中对齐骨骼。
##
## 每个体素存一个 32 位整数：高 24 位为 sRGB 颜色，低 8 位为“属性字节” attr = 材质 << 4 | 发光等级(0~15)。
## 属性字节原样进入顶点色 alpha（attr / 255），由 voxel_char.gdshader 解码出材质与发光。
## 写入时使用画布当前材质 mat（set_mat() 切换）；颜色 alpha < 1 仍按旧约定表示发光（VoxelGrid.glow）。
## 注意：本类会在工作线程中使用（VoxMesh 并行生成），不得读取 const 数组/字典（Godot 4.4 线程问题），
## 需要的表一律放在 static var 中。

# ---- 材质（与 voxel_char.gdshader 中的表一致）
const M_CLOTH := 0     ## 布（哑光）
const M_SKIN := 1      ## 皮肤（柔和包裹光、暖色边缘）
const M_HAIR := 2      ## 头发（光泽、丝质高光）
const M_GOLD := 3      ## 金属饰件（金/铜：金属度高、低粗糙度）
const M_STEEL := 4     ## 钢/银（刃、银饰）
const M_GEM := 5       ## 宝石（高光 + 微自发光）
const M_LEATHER := 6   ## 皮革（略有光泽）
const M_FUR := 7       ## 毛皮
const M_EYE := 8       ## 眼睛（湿润高光，微亮）
const M_STONE := 9     ## 石
const M_SCALE := 10    ## 鳞/角质（蛇鳞、龙角、鸟喙）
const M_SILK := 11     ## 丝绸（柔和光泽）
const M_JADE := 12     ## 玉/漆（半透亮光泽）
const M_FLAME := 13    ## 火焰/光效（全自发光）

var lo: Vector3i
var hi: Vector3i
var sx: int
var sy: int
var sz: int
var sxy: int
var data: PackedInt32Array
var shift: Vector3 = Vector3.ZERO
## 当前写入材质
var mat: int = 0
var _mat_bits: int = 0


func _init(lo_: Vector3i, hi_: Vector3i) -> void:
	lo = lo_
	hi = hi_
	sx = hi.x - lo.x + 3
	sy = hi.y - lo.y + 3
	sz = hi.z - lo.z + 3
	sxy = sx * sy
	data = PackedInt32Array()
	data.resize(sx * sy * sz)


func set_mat(m: int) -> void:
	mat = m
	_mat_bits = (m & 15) << 4


# ================================================================ 颜色工具

## 旧接口：颜色 → 整数（材质 0，alpha<1 视为发光）
static func enc(c: Color) -> int:
	return encm(c, 0)


## 颜色 + 材质 → 整数
static func encm(c: Color, m: int) -> int:
	var g4 := 0
	if c.a < 0.999:
		g4 = clampi(roundi((1.0 - c.a) * 30.0), 1, 15)
	var v := (c.to_rgba32() & 0xFFFFFF00) | ((m & 15) << 4) | g4
	return v if v != 0 else 1


## 使用画布当前材质编码
func e(c: Color) -> int:
	var g4 := 0
	if c.a < 0.999:
		g4 = clampi(roundi((1.0 - c.a) * 30.0), 1, 15)
	var v := (c.to_rgba32() & 0xFFFFFF00) | _mat_bits | g4
	return v if v != 0 else 1


## 发光色（与 VoxelGrid.glow 相同）
static func glow(c: Color, s: float = 1.0) -> Color:
	return Color(c.r, c.g, c.b, 1.0 - 0.5 * clampf(s, 0.0, 1.0))


## 亮度缩放（保持 alpha）
static func tone(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0), c.a)


static func mixc(a: Color, b: Color, t: float) -> Color:
	return Color(lerpf(a.r, b.r, t), lerpf(a.g, b.g, t), lerpf(a.b, b.b, t), a.a)


## 色相微移 + 明度缩放（冷暖阴影用）
static func shade(c: Color, k: float, warm: float = 0.0) -> Color:
	var o := tone(c, k)
	if warm != 0.0:
		o = Color(clampf(o.r + warm * 0.06, 0.0, 1.0), o.g, clampf(o.b - warm * 0.06, 0.0, 1.0), o.a)
	return o


## 生成 4 个明暗变体（用于逐体素噪声），amt 为最大幅度
func tones4(c: Color, amt: float) -> PackedInt32Array:
	return PackedInt32Array([e(tone(c, 1.0 - amt)), e(tone(c, 1.0 - amt * 0.4)), e(c), e(tone(c, 1.0 + amt * 0.6))])


## 整数哈希（稳定、可复现）
static func h3(x: int, y: int, z: int) -> int:
	var h := x * 374761393 + y * 668265263 + z * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff


static func h1(x: int) -> int:
	return h3(x, 17, 91)


## 0~1 浮点哈希
static func hf(x: int, y: int, z: int) -> float:
	return float(h3(x, y, z) & 1023) / 1023.0


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
	if x < lo.x or y < lo.y or z < lo.z or x > hi.x or y > hi.y or z > hi.z:
		return
	data[(x - lo.x + 1) + sx * (y - lo.y + 1) + sxy * (z - lo.z + 1)] = e(c)


## 指定材质写入（不改变当前材质）
func putm(x: int, y: int, z: int, c: Color, m: int) -> void:
	set_raw(x, y, z, encm(c, m))


## 只给已有体素上色
func tint_at(x: int, y: int, z: int, c: Color) -> void:
	if get_raw(x, y, z) != 0:
		set_raw(x, y, z, e(c))


func clear_at(x: int, y: int, z: int) -> void:
	set_raw(x, y, z, 0)


func get_color(x: int, y: int, z: int) -> Color:
	var v := get_raw(x, y, z)
	return Color.hex((v & 0xFFFFFF00) | 0xFF)


## 已有体素的材质（空为 -1）
func get_mat(x: int, y: int, z: int) -> int:
	var v := get_raw(x, y, z)
	return -1 if v == 0 else (v >> 4) & 15


# ================================================================ 形状

## 实心盒 [a,b]（含端点），noise>0 时表面逐体素明暗变化
func box(a: Vector3i, b: Vector3i, c: Color, noise: float = 0.0) -> void:
	var x0 := maxi(mini(a.x, b.x), lo.x)
	var x1 := mini(maxi(a.x, b.x), hi.x)
	var y0 := maxi(mini(a.y, b.y), lo.y)
	var y1 := mini(maxi(a.y, b.y), hi.y)
	var z0 := maxi(mini(a.z, b.z), lo.z)
	var z1 := mini(maxi(a.z, b.z), hi.z)
	if noise <= 0.0:
		var v := e(c)
		for z in range(z0, z1 + 1):
			for y in range(y0, y1 + 1):
				var base := sx * (y - lo.y + 1) + sxy * (z - lo.z + 1) - lo.x + 1
				for x in range(x0, x1 + 1):
					data[base + x] = v
	else:
		var t := tones4(c, noise)
		var mid := t[2]
		for z in range(z0, z1 + 1):
			for y in range(y0, y1 + 1):
				var base := sx * (y - lo.y + 1) + sxy * (z - lo.z + 1) - lo.x + 1
				if z == z0 or z == z1 or y == y0 or y == y1:
					for x in range(x0, x1 + 1):
						data[base + x] = t[h3(x >> 1, y >> 1, z >> 1) & 3]
				else:
					for x in range(x0 + 1, x1):
						data[base + x] = mid
					data[base + x0] = t[h3(x0 >> 1, y >> 1, z >> 1) & 3]
					data[base + x1] = t[h3(x1 >> 1, y >> 1, z >> 1) & 3]


## 圆角盒：四条竖棱（沿 Y）削去 r 格（r=1 削一个角体素，r=2 削成 45° 倒角）
func rbox(a: Vector3i, b: Vector3i, c: Color, r: int = 1, noise: float = 0.0) -> void:
	box(a, b, c, noise)
	if r <= 0:
		return
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var z0 := mini(a.z, b.z)
	var z1 := maxi(a.z, b.z)
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for k in r:
			for j in r - k:
				set_raw(x0 + k, y, z0 + j, 0)
				set_raw(x1 - k, y, z0 + j, 0)
				set_raw(x0 + k, y, z1 - j, 0)
				set_raw(x1 - k, y, z1 - j, 0)


## 只重新上色已有体素
func paint(a: Vector3i, b: Vector3i, c: Color, noise: float = 0.0) -> void:
	var t := tones4(c, noise) if noise > 0.0 else PackedInt32Array([e(c), e(c), e(c), e(c)])
	for z in range(maxi(mini(a.z, b.z), lo.z), mini(maxi(a.z, b.z), hi.z) + 1):
		for y in range(maxi(mini(a.y, b.y), lo.y), mini(maxi(a.y, b.y), hi.y) + 1):
			for x in range(maxi(mini(a.x, b.x), lo.x), mini(maxi(a.x, b.x), hi.x) + 1):
				var i := idx(x, y, z)
				if data[i] != 0:
					data[i] = t[h3(x >> 1, y >> 1, z >> 1) & 3]


func clear(a: Vector3i, b: Vector3i) -> void:
	for z in range(maxi(mini(a.z, b.z), lo.z), mini(maxi(a.z, b.z), hi.z) + 1):
		for y in range(maxi(mini(a.y, b.y), lo.y), mini(maxi(a.y, b.y), hi.y) + 1):
			for x in range(maxi(mini(a.x, b.x), lo.x), mini(maxi(a.x, b.x), hi.x) + 1):
				data[idx(x, y, z)] = 0


## 椭球（中心/半径为体素单位，可为小数）
func ellipsoid(center: Vector3, radii: Vector3, c: Color, noise: float = 0.0) -> void:
	var t := tones4(c, noise) if noise > 0.0 else PackedInt32Array([e(c), e(c), e(c), e(c)])
	var l := Vector3i((center - radii).floor())
	var h := Vector3i((center + radii).ceil())
	var inv := Vector3(1.0 / maxf(radii.x, 0.01), 1.0 / maxf(radii.y, 0.01), 1.0 / maxf(radii.z, 0.01))
	for z in range(maxi(l.z, lo.z), mini(h.z, hi.z) + 1):
		var dz := (z + 0.5 - center.z) * inv.z
		for y in range(maxi(l.y, lo.y), mini(h.y, hi.y) + 1):
			var dy := (y + 0.5 - center.y) * inv.y
			var r2 := dz * dz + dy * dy
			if r2 > 1.0:
				continue
			for x in range(maxi(l.x, lo.x), mini(h.x, hi.x) + 1):
				var dx := (x + 0.5 - center.x) * inv.x
				if dx * dx + r2 <= 1.0:
					data[idx(x, y, z)] = t[h3(x >> 1, y >> 1, z >> 1) & 3]


## 两点之间的粗线（球刷）
func line(a: Vector3, b: Vector3, radius: float, c: Color, noise: float = 0.0) -> void:
	var steps := int(ceil(a.distance_to(b) * 2.0)) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(maxi(steps, 1)))
		if radius <= 0.5:
			put(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)), c)
		else:
			ellipsoid(p, Vector3(radius, radius, radius), c, noise)


## 竖向圆柱（沿 Y，y0..y1），截面椭圆半径 r
func cyl_y(cx: float, cz: float, y0: int, y1: int, r: Vector2, c: Color) -> void:
	var v := e(c)
	for z in range(int(floor(cz - r.y)), int(ceil(cz + r.y)) + 1):
		for x in range(int(floor(cx - r.x)), int(ceil(cx + r.x)) + 1):
			var dx := (x + 0.5 - cx) / r.x
			var dz := (z + 0.5 - cz) / r.y
			if dx * dx + dz * dz <= 1.0:
				for y in range(mini(y0, y1), maxi(y0, y1) + 1):
					set_raw(x, y, z, v)


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


## 体素是否在 d 方向暴露（邻格为空）
func is_exposed(x: int, y: int, z: int, d: Vector3i) -> bool:
	return get_raw(x, y, z) != 0 and get_raw(x + d.x, y + d.y, z + d.z) == 0


## 颜色乘以系数（仅已有体素，区域内；保留属性字节）
func darken_box(a: Vector3i, b: Vector3i, k: float) -> void:
	for z in range(maxi(mini(a.z, b.z), lo.z), mini(maxi(a.z, b.z), hi.z) + 1):
		for y in range(maxi(mini(a.y, b.y), lo.y), mini(maxi(a.y, b.y), hi.y) + 1):
			for x in range(maxi(mini(a.x, b.x), lo.x), mini(maxi(a.x, b.x), hi.x) + 1):
				var i := idx(x, y, z)
				var v := data[i]
				if v != 0:
					var c := Color.hex((v & 0xFFFFFF00) | 0xFF)
					var o := (tone(c, k).to_rgba32() & 0xFFFFFF00) | (v & 0xFF)
					data[i] = o if o != 0 else 1


## 表面图案：在平面上逐行盖印像素画。rows 自上而下，字符查 pal（缺失或 "." 跳过）。
## 平面由 origin（左上角体素）与两轴 right/down 定义；only_solid=true 时只改已有体素的颜色。
## pal 值可以是 Color 或 [Color, 材质]。
func stamp(rows: Array, pal: Dictionary, origin: Vector3i, right: Vector3i, down: Vector3i, only_solid: bool = false) -> void:
	for r in rows.size():
		var row: String = rows[r]
		for j in row.length():
			var ch := row[j]
			if ch == "." or ch == " " or not pal.has(ch):
				continue
			var p := origin + right * j + down * r
			var pv: Variant = pal[ch]
			var v: int
			if pv is Array:
				v = encm(pv[0], int(pv[1]))
			else:
				v = e(pv)
			if only_solid and get_raw(p.x, p.y, p.z) == 0:
				continue
			set_raw(p.x, p.y, p.z, v)


## 统计实体体素
func count_solid() -> int:
	var n := 0
	for v in data:
		if v != 0:
			n += 1
	return n


# ================================================================ LOD

## 2× 降采样（LOD1）：每 2×2×2 块中实体数 >= min_fill 即保留；颜色取块内实体体素的平均色，属性取最后一个。
## 结果体素尺寸为原来的 2 倍；shift 按半尺寸换算（网格化时 vs 也要 ×2）。
## 以源数据为主循环（空格只读一次），比逐目标格读 8 次快得多。
func downsample(min_fill: int = 2) -> VoxCanvas:
	var nlo := Vector3i(floori(lo.x / 2.0), floori(lo.y / 2.0), floori(lo.z / 2.0))
	var nhi := Vector3i(floori(hi.x / 2.0), floori(hi.y / 2.0), floori(hi.z / 2.0))
	var o := VoxCanvas.new(nlo, nhi)
	o.shift = shift * 0.5
	var n := o.data.size()
	var cnt := PackedInt32Array()
	var sr := PackedInt32Array()
	var sg := PackedInt32Array()
	var sb := PackedInt32Array()
	var at := PackedInt32Array()
	cnt.resize(n)
	sr.resize(n)
	sg.resize(n)
	sb.resize(n)
	at.resize(n)
	var d := data
	var osx := o.sx
	var osxy := o.sxy
	for z in range(lo.z, hi.z + 1):
		var oz := osxy * ((z >> 1) - nlo.z + 1)
		var bz := sxy * (z - lo.z + 1)
		for y in range(lo.y, hi.y + 1):
			var row := bz + sx * (y - lo.y + 1) - lo.x + 1
			var orow := oz + osx * ((y >> 1) - nlo.y + 1) - nlo.x + 1
			for x in range(lo.x, hi.x + 1):
				var v := d[row + x]
				if v == 0:
					continue
				var oi := orow + (x >> 1)
				cnt[oi] += 1
				sr[oi] += (v >> 24) & 255
				sg[oi] += (v >> 16) & 255
				sb[oi] += (v >> 8) & 255
				at[oi] = v & 255
	var od := o.data
	for i in n:
		var c := cnt[i]
		if c >= min_fill:
			var v2 := ((sr[i] / c) << 24) | ((sg[i] / c) << 16) | ((sb[i] / c) << 8) | at[i]
			od[i] = v2 if v2 != 0 else 1
	o.data = od
	return o
