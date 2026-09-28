class_name PropBuilder
## 体素植被与道具：各生物群系的树木、竹、柳、枫、枯木与赤晶、灌木、芦苇、岩石、草丛与花、灵草（herb_node）、矿脉（ore_node）。
## 全部由程序生成 VoxelGrid → VoxelMesher 网格，按 (种类, 变体, LOD) 缓存；大量重复的用 MultiMesh 实例化。
## LOD1 为 2 倍体素降采样的远景网格。网格原点在树干底部中心（y=0 为地面）。

## 种类 → 体素边长、变体数、树干碰撞半径与高度（米）
const KINDS := {
	"pine_snow": {"vs": 0.5, "variants": 3, "trunk": 0.5, "height": 6.0},
	"pine": {"vs": 0.5, "variants": 3, "trunk": 0.5, "height": 6.0},
	"ancient": {"vs": 0.5, "variants": 3, "trunk": 1.4, "height": 10.0},
	"broadleaf": {"vs": 0.5, "variants": 3, "trunk": 0.45, "height": 5.0},
	"blossom": {"vs": 0.5, "variants": 2, "trunk": 0.4, "height": 4.0},
	"bamboo": {"vs": 0.25, "variants": 3, "trunk": 0.9, "height": 6.0},
	"willow": {"vs": 0.5, "variants": 2, "trunk": 0.45, "height": 5.0},
	"maple": {"vs": 0.5, "variants": 3, "trunk": 0.45, "height": 5.0},
	"dead": {"vs": 0.25, "variants": 3, "trunk": 0.35, "height": 4.0},
	"crystal": {"vs": 0.25, "variants": 3, "trunk": 0.9, "height": 3.0},
	"shrub": {"vs": 0.25, "variants": 3, "trunk": 0.0, "height": 0.0},
	"shrub_yellow": {"vs": 0.25, "variants": 3, "trunk": 0.0, "height": 0.0},
	"reed": {"vs": 0.125, "variants": 2, "trunk": 0.0, "height": 0.0},
	"rock_gray": {"vs": 0.5, "variants": 3, "trunk": 0.0, "height": 0.0},
	"rock_moss": {"vs": 0.5, "variants": 3, "trunk": 0.0, "height": 0.0},
	"rock_snow": {"vs": 0.5, "variants": 3, "trunk": 0.0, "height": 0.0},
	"rock_red": {"vs": 0.5, "variants": 3, "trunk": 0.0, "height": 0.0},
	"rock_yellow": {"vs": 0.5, "variants": 3, "trunk": 0.0, "height": 0.0},
	"pebble": {"vs": 0.25, "variants": 3, "trunk": 0.0, "height": 0.0},
	"grass": {"vs": 0.0625, "variants": 3, "trunk": 0.0, "height": 0.0},
	"grass_dry": {"vs": 0.0625, "variants": 2, "trunk": 0.0, "height": 0.0},
	"grass_snow": {"vs": 0.0625, "variants": 2, "trunk": 0.0, "height": 0.0},
	"flower": {"vs": 0.0625, "variants": 5, "trunk": 0.0, "height": 0.0},
	"lotus": {"vs": 0.125, "variants": 2, "trunk": 0.0, "height": 0.0},
}

const FLOWER_COLORS := [Color(0.95, 0.3, 0.3), Color(1.0, 0.85, 0.3), Color(0.95, 0.95, 0.95), Color(0.7, 0.45, 0.95), Color(1.0, 0.6, 0.75)]

static var _meshes: Dictionary = {}
## 可在工作线程中读取的副本（Godot 4.4 并发读取 const 容器不安全）
static var _kinds_rt: Dictionary = KINDS.duplicate(true)
static var _default_info: Dictionary = {"vs": 0.5, "variants": 1, "trunk": 0.0, "height": 0.0}


static func info(kind: String) -> Dictionary:
	return _kinds_rt.get(kind, _default_info)


static func variants(kind: String) -> int:
	return int(info(kind)["variants"])


## 取得网格（缓存）。lod=1 为降采样远景网格。
static func mesh(kind: String, variant: int = 0, lod: int = 0) -> ArrayMesh:
	variant = posmod(variant, variants(kind))
	var key := "%s_%d_%d" % [kind, variant, lod]
	if _meshes.has(key):
		return _meshes[key]
	var g := grid(kind, variant)
	var vs := float(info(kind)["vs"])
	if lod > 0:
		g = downsample(g)
		vs *= 2.0
	var org := Vector3(-g.sx * vs * 0.5, 0.0, -g.sz * vs * 0.5)
	var m := VoxelMesher.build(g, vs, org, lod == 0)
	_meshes[key] = m
	return m


## 预先生成全部网格（主线程；避免流式加载时卡顿）
static func warm_up(kinds: Array = []) -> void:
	if kinds.is_empty():
		kinds = KINDS.keys()
	for k in kinds:
		for v in variants(k):
			mesh(k, v, 0)
			if float(info(k)["vs"]) >= 0.25:
				mesh(k, v, 1)


## 2× 降采样：8 个子体素中 ≥3 个实心则实心，颜色取第一个实心
static func downsample(g: VoxelGrid) -> VoxelGrid:
	var nx := (g.sx + 1) / 2
	var ny := (g.sy + 1) / 2
	var nz := (g.sz + 1) / 2
	var o := VoxelGrid.new(nx, ny, nz)
	for z in nz:
		for y in ny:
			for x in nx:
				var cnt := 0
				var first := 0
				for dz in 2:
					for dy in 2:
						for dx in 2:
							var v := g.get_raw(x * 2 + dx, y * 2 + dy, z * 2 + dz)
							if v != 0:
								cnt += 1
								if first == 0 or dy == 1:
									first = v
				if cnt >= 3:
					o.set_raw(x, y, z, first)
	return o


static func _h(x: int, y: int, z: int, s: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (s * 40503)
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0xffff) / 65535.0


## 颜色钳制到 [0,1]（VoxelGrid.encode 不做钳制）
static func _cl(c: Color) -> Color:
	return Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0), clampf(c.a, 0.0, 1.0))


## 带逐体素明暗扰动的椭球
static func _blob(g: VoxelGrid, c: Vector3, r: Vector3, col: Color, var_amt: float, seed_v: int, top_col: Color = Color(0, 0, 0, 0)) -> void:
	var lo := Vector3i((c - r).floor())
	var hi := Vector3i((c + r).ceil())
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var d := ((Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5) - c) / r).length_squared()
				var jag := 0.85 + 0.3 * _h(x, y, z, seed_v)
				if d <= jag:
					var k := 1.0 + (_h(x, y, z, seed_v + 7) - 0.5) * var_amt
					var cc := col
					if top_col.a > 0.0 and y > c.y + r.y * 0.35:
						cc = top_col
					g.set_color(x, y, z, _cl(Color(cc.r * k, cc.g * k, cc.b * k, cc.a)))


static func grid(kind: String, v: int) -> VoxelGrid:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + v * 977
	match kind:
		"pine_snow", "pine":
			return _pine(rng, v, kind == "pine_snow")
		"ancient":
			return _ancient(rng, v)
		"broadleaf":
			return _broadleaf(rng, v, [Color(0.30, 0.55, 0.24), Color(0.36, 0.60, 0.26), Color(0.26, 0.50, 0.28)][v % 3], Color(0.40, 0.66, 0.30))
		"maple":
			return _broadleaf(rng, v, [Color(0.82, 0.22, 0.14), Color(0.90, 0.42, 0.14), Color(0.74, 0.16, 0.18)][v % 3], Color(0.95, 0.55, 0.2))
		"blossom":
			return _broadleaf(rng, v, Color(0.96, 0.66, 0.76), Color(1.0, 0.82, 0.88))
		"bamboo":
			return _bamboo(rng, v)
		"willow":
			return _willow(rng, v)
		"dead":
			return _dead(rng, v)
		"crystal":
			return _crystal(rng, v)
		"shrub":
			return _shrub(rng, v, Color(0.26, 0.50, 0.22))
		"shrub_yellow":
			return _shrub(rng, v, Color(0.66, 0.62, 0.28))
		"reed":
			return _reed(rng, v)
		"rock_gray":
			return _rock(rng, v, Color(0.54, 0.54, 0.54), Color(0, 0, 0, 0))
		"rock_moss":
			return _rock(rng, v, Color(0.45, 0.48, 0.44), Color(0.32, 0.50, 0.24))
		"rock_snow":
			return _rock(rng, v, Color(0.55, 0.58, 0.65), Color(0.94, 0.96, 1.0))
		"rock_red":
			return _rock(rng, v, Color(0.60, 0.27, 0.18), Color(0, 0, 0, 0))
		"rock_yellow":
			return _rock(rng, v, Color(0.78, 0.62, 0.36), Color(0, 0, 0, 0))
		"pebble":
			return _pebble(rng, v)
		"grass":
			return _grass(rng, v, Color(0.36, 0.62, 0.26), Color(0.50, 0.74, 0.32))
		"grass_dry":
			return _grass(rng, v, Color(0.62, 0.58, 0.30), Color(0.76, 0.70, 0.40))
		"grass_snow":
			return _grass(rng, v, Color(0.42, 0.52, 0.40), Color(0.85, 0.9, 0.95))
		"flower":
			return _flower(rng, v)
		"lotus":
			return _lotus(rng, v)
	return VoxelGrid.new(1, 1, 1)


# ================================================================ 树

static func _pine(rng: RandomNumberGenerator, v: int, snowy: bool) -> VoxelGrid:
	var h := 20 + v * 3 + rng.randi_range(0, 2)
	var w := 13
	var g := VoxelGrid.new(w, h + 2, w)
	var c := w / 2
	var bark := Color(0.34, 0.24, 0.17)
	g.fill_box(Vector3i(c, 0, c), Vector3i(c, h - 2, c), bark)
	var leaf := Color(0.14, 0.33, 0.24) if snowy else Color(0.16, 0.38, 0.22)
	var snow := Color(0.93, 0.95, 1.0)
	var tiers := 5 + v
	for t in tiers:
		var y0 := 4 + t * (h - 6) / tiers
		var rr := 6.0 * (1.0 - float(t) / tiers) + 1.2
		for dy in 3:
			var r2 := rr - dy * 0.9
			for z in w:
				for x in w:
					var dx := x + 0.5 - (c + 0.5)
					var dz := z + 0.5 - (c + 0.5)
					var d := sqrt(dx * dx + dz * dz)
					if d <= r2 + _h(x, y0 + dy, z, v) * 0.8 - 0.4:
						var k := 0.9 + 0.2 * _h(x, y0 + dy, z, v + 3)
						var cc := _cl(Color(leaf.r * k, leaf.g * k, leaf.b * k))
						if snowy and dy == 2 and _h(x, y0, z, 9) > 0.25:
							cc = snow
						elif snowy and dy == 1 and d > r2 - 1.0 and _h(x, y0, z, 11) > 0.5:
							cc = snow
						g.set_color(x, y0 + dy, z, cc)
	g.set_color(c, h, c, snow if snowy else leaf)
	g.set_color(c, h - 1, c, leaf)
	return g


static func _ancient(rng: RandomNumberGenerator, v: int) -> VoxelGrid:
	var w := 34
	var h := 40 + v * 3
	var g := VoxelGrid.new(w, h, w)
	var c := Vector3(w * 0.5, 0, w * 0.5)
	var bark := Color(0.30, 0.22, 0.16)
	var bark2 := Color(0.36, 0.27, 0.19)
	var moss := Color(0.28, 0.42, 0.20)
	var trunk_h := 20 + v * 2
	# 粗干（略扭）
	for y in trunk_h:
		var r := 3.2 - y * 0.05
		var ox := sin(y * 0.15 + v) * 0.8
		var oz := cos(y * 0.12 + v * 2.0) * 0.8
		for z in w:
			for x in w:
				var dx := x + 0.5 - (c.x + ox)
				var dz := z + 0.5 - (c.z + oz)
				if dx * dx + dz * dz <= r * r:
					var cc := bark if (x + y / 3) % 2 == 0 else bark2
					if y < 6 and _h(x, y, z, 5) > 0.7:
						cc = moss
					g.set_color(x, y, z, cc)
	# 板根
	for i in 5:
		var a := i * TAU / 5.0 + v
		var dir := Vector3(cos(a), 0, sin(a))
		for s in 8:
			var p := c + dir * (2.5 + s * 0.7) + Vector3(0, 3.0 - s * 0.4, 0)
			g.fill_ellipsoid(p, Vector3(1.0, 1.2, 1.0), bark)
	# 主枝
	var tips: Array[Vector3] = []
	for i in 5:
		var a := i * TAU / 5.0 + rng.randf_range(-0.4, 0.4)
		var start := c + Vector3(0, trunk_h - 4 - i, 0)
		var tip := start + Vector3(cos(a) * rng.randf_range(7, 11), rng.randf_range(5, 9), sin(a) * rng.randf_range(7, 11))
		g.fill_line(start, tip, 1.2, bark)
		tips.append(tip)
	tips.append(c + Vector3(0, trunk_h + 6, 0))
	g.fill_line(c + Vector3(0, trunk_h - 2, 0), c + Vector3(0, trunk_h + 6, 0), 1.5, bark)
	# 树冠
	var leaf: Color = [Color(0.20, 0.42, 0.20), Color(0.24, 0.48, 0.22), Color(0.18, 0.38, 0.24)][v % 3]
	var top: Color = leaf.lightened(0.18)
	for t in tips:
		var rad := Vector3(rng.randf_range(6.0, 8.0), rng.randf_range(3.5, 4.5), rng.randf_range(6.0, 8.0))
		_blob(g, t + Vector3(0, 1.5, 0), rad, leaf, 0.22, v * 13 + int(t.x), top)
	# 垂藤
	for i in 26:
		var x := rng.randi_range(3, w - 4)
		var z := rng.randi_range(3, w - 4)
		var y := h - 1
		while y > 0 and not g.is_solid(x, y, z):
			y -= 1
		if y < trunk_h:
			continue
		var ln := rng.randi_range(3, 9)
		for k in ln:
			var yy := y - 1 - k
			if yy <= 2 or g.is_solid(x, yy, z):
				break
			g.set_color(x, yy, z, Color(0.30, 0.52, 0.22).darkened(k * 0.03))
	return g


static func _broadleaf(rng: RandomNumberGenerator, v: int, leaf: Color, top: Color) -> VoxelGrid:
	var w := 23
	var h := 21 + v * 2
	var g := VoxelGrid.new(w, h, w)
	var c := Vector3(w * 0.5, 0, w * 0.5)
	var bark := Color(0.36, 0.26, 0.18)
	var trunk_h := 6 + v
	g.fill_cylinder_y(c.x, c.z, 1.0, 0, trunk_h + 2, bark)
	var blobs := 4 + v
	for i in blobs:
		var a := i * TAU / blobs + rng.randf_range(-0.4, 0.4)
		var r := rng.randf_range(3.5, 5.5)
		var p := c + Vector3(cos(a) * r, trunk_h + rng.randf_range(3.0, 7.0), sin(a) * r)
		g.fill_line(c + Vector3(0, trunk_h, 0), p, 0.6, bark)
		_blob(g, p, Vector3(rng.randf_range(4.0, 5.2), rng.randf_range(3.0, 3.8), rng.randf_range(4.0, 5.2)), leaf, 0.22, v * 7 + i, top)
	_blob(g, c + Vector3(0, trunk_h + 8.5, 0), Vector3(5.0, 3.8, 5.0), leaf, 0.22, v * 5, top)
	return g


static func _bamboo(rng: RandomNumberGenerator, v: int) -> VoxelGrid:
	var w := 18
	var h := 44 + v * 4
	var g := VoxelGrid.new(w, h, w)
	var stalk := Color(0.40, 0.62, 0.28)
	var node := Color(0.58, 0.74, 0.36)
	var leaf := Color(0.30, 0.56, 0.26)
	var n := 11 + v * 3
	for i in n:
		var x := rng.randi_range(3, w - 4)
		var z := rng.randi_range(3, w - 4)
		var sh := rng.randi_range(h - 16, h - 4)
		var lean := rng.randf_range(-0.06, 0.06)
		var lean2 := rng.randf_range(-0.06, 0.06)
		for y in sh:
			var xx := clampi(x + int(y * lean), 0, w - 1)
			var zz := clampi(z + int(y * lean2), 0, w - 1)
			g.set_color(xx, y, zz, node if y % 7 == 0 else stalk.darkened(_h(i, y, 0, v) * 0.1))
			if y > sh * 0.45 and y % 5 == 0:
				for k in 3:
					var dx := rng.randi_range(-2, 2)
					var dz := rng.randi_range(-2, 2)
					g.set_color(clampi(xx + dx, 0, w - 1), y + 1, clampi(zz + dz, 0, w - 1), leaf.lightened(rng.randf() * 0.15))
		var tx := clampi(x + int(sh * lean), 0, w - 1)
		var tz := clampi(z + int(sh * lean2), 0, w - 1)
		_blob(g, Vector3(tx + 0.5, sh - 1, tz + 0.5), Vector3(2.2, 2.5, 2.2), leaf, 0.25, i + v * 11)
	return g


static func _willow(rng: RandomNumberGenerator, v: int) -> VoxelGrid:
	var w := 19
	var h := 20 + v * 2
	var g := VoxelGrid.new(w, h, w)
	var c := Vector3(w * 0.5, 0, w * 0.5)
	var bark := Color(0.34, 0.27, 0.20)
	var trunk_h := 10 + v
	g.fill_cylinder_y(c.x, c.z, 1.0, 0, trunk_h, bark)
	var leaf := Color(0.50, 0.70, 0.30)
	var leaf2 := Color(0.42, 0.62, 0.26)
	_blob(g, c + Vector3(0, trunk_h + 3, 0), Vector3(6.5, 3.0, 6.5), leaf2, 0.2, v, leaf)
	# 垂枝
	for z in w:
		for x in w:
			var dx := x + 0.5 - c.x
			var dz := z + 0.5 - c.z
			var d := sqrt(dx * dx + dz * dz)
			if d < 3.0 or d > 8.5 or _h(x, 0, z, v) < 0.45:
				continue
			var y := h - 1
			while y > 0 and not g.is_solid(x, y, z):
				y -= 1
			if y <= 0:
				y = trunk_h + 1
			var ln := rng.randi_range(5, 12)
			for k in ln:
				var yy := y - 1 - k
				if yy <= 1:
					break
				g.set_color(x, yy, z, leaf if k % 3 != 2 else leaf2)
	return g


static func _dead(rng: RandomNumberGenerator, v: int) -> VoxelGrid:
	var w := 20
	var h := 28 + v * 4
	var g := VoxelGrid.new(w, h, w)
	var c := Vector3(w * 0.5, 0, w * 0.5)
	var char_c := Color(0.13, 0.11, 0.11)
	var ember := VoxelGrid.glow(Color(1.0, 0.35, 0.1), 0.7)
	g.fill_cylinder_y(c.x, c.z, 1.1, 0, h * 2 / 3, char_c)
	for i in 4 + v:
		var y0 := rng.randi_range(h / 3, h * 2 / 3)
		var a := rng.randf() * TAU
		var tip := c + Vector3(cos(a) * rng.randf_range(4, 8), y0 + rng.randf_range(3, 8), sin(a) * rng.randf_range(4, 8))
		g.fill_line(c + Vector3(0, y0, 0), tip, 0.5, char_c)
		var tip2 := tip + Vector3(rng.randf_range(-3, 3), rng.randf_range(1, 4), rng.randf_range(-3, 3))
		g.fill_line(tip, tip2, 0.4, char_c)
	# 余烬裂纹
	for i in 10:
		var y := rng.randi_range(1, h / 2)
		var a := rng.randf() * TAU
		var x := int(c.x + cos(a) * 1.2)
		var z := int(c.z + sin(a) * 1.2)
		if g.is_solid(x, y, z):
			g.set_color(x, y, z, ember)
	return g


static func _crystal(rng: RandomNumberGenerator, v: int) -> VoxelGrid:
	var w := 16
	var h := 24 + v * 3
	var g := VoxelGrid.new(w, h, w)
	var base := Color(0.20, 0.14, 0.15)
	g.fill_ellipsoid(Vector3(w * 0.5, 0.5, w * 0.5), Vector3(4.5, 2.0, 4.5), base)
	for i in 4 + v:
		var x := rng.randi_range(3, w - 4)
		var z := rng.randi_range(3, w - 4)
		var ch := rng.randi_range(h / 3, h - 1)
		var r := rng.randf_range(1.2, 2.2)
		var lean := Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized()
		var bright := VoxelGrid.glow(Color(1.0, 0.22, 0.12).lerp(Color(1.0, 0.5, 0.3), rng.randf()), 0.75)
		var dark := VoxelGrid.glow(Color(0.7, 0.08, 0.1), 0.45)
		for k in ch:
			var p := Vector3(x + 0.5, 1.0, z + 0.5) + lean * k
			var rr := r * (1.0 - float(k) / ch * 0.8)
			g.fill_ellipsoid(p, Vector3(rr, 0.7, rr), bright if (k + i) % 4 != 0 else dark)
	return g


static func _shrub(rng: RandomNumberGenerator, v: int, leaf: Color) -> VoxelGrid:
	var w := 10
	var g := VoxelGrid.new(w, 7, w)
	for i in 2 + v:
		var p := Vector3(rng.randf_range(3.5, 6.5), rng.randf_range(2.0, 3.0), rng.randf_range(3.5, 6.5))
		_blob(g, p, Vector3(rng.randf_range(2.2, 3.2), rng.randf_range(1.8, 2.6), rng.randf_range(2.2, 3.2)), leaf, 0.25, v * 3 + i, leaf.lightened(0.15))
	return g


static func _reed(rng: RandomNumberGenerator, v: int) -> VoxelGrid:
	var w := 12
	var g := VoxelGrid.new(w, 18, w)
	var stem := Color(0.52, 0.62, 0.32)
	var head := Color(0.50, 0.36, 0.22)
	for i in 14 + v * 4:
		var x := rng.randi_range(1, w - 2)
		var z := rng.randi_range(1, w - 2)
		var sh := rng.randi_range(8, 17)
		for y in sh:
			g.set_color(x, y, z, stem.darkened(rng.randf() * 0.1))
		if rng.randf() < 0.6:
			g.set_color(x, sh - 1, z, head)
			g.set_color(x, sh - 2, z, head)
	return g


static func _rock(rng: RandomNumberGenerator, v: int, c: Color, top: Color) -> VoxelGrid:
	var w := 7 + v * 2
	var hh := 4 + v
	var g := VoxelGrid.new(w, hh, w)
	var n := FastNoiseLite.new()
	n.seed = v * 31 + int(c.r * 100)
	n.frequency = 0.3
	for z in w:
		for y in hh:
			for x in w:
				var p := Vector3(x + 0.5, y + 0.5, z + 0.5)
				var d := ((p - Vector3(w * 0.5, 0.0, w * 0.5)) / Vector3(w * 0.5, hh, w * 0.46)).length() + n.get_noise_3d(x, y, z) * 0.3
				if d < 1.0:
					var k := 0.9 + 0.2 * _h(x, y, z, v)
					g.set_color(x, y, z, _cl(Color(c.r * k, c.g * k, c.b * k)))
	if top.a > 0.0:
		for z in w:
			for x in w:
				for y in range(hh - 1, -1, -1):
					if g.is_solid(x, y, z):
						if y >= 1 and n.get_noise_2d(x * 3.0, z * 3.0) > -0.2:
							g.set_color(x, y, z, _cl(top.lightened(_h(x, y, z, 2) * 0.1)))
						break
	return g


static func _pebble(rng: RandomNumberGenerator, v: int) -> VoxelGrid:
	var g := VoxelGrid.new(6, 3, 6)
	var c := Color(0.5, 0.5, 0.5).lerp(Color(0.6, 0.55, 0.45), v * 0.4)
	g.fill_ellipsoid(Vector3(3, 0.5, 3), Vector3(2.6, 1.8, 2.0 + v * 0.3), c)
	return g


static func _grass(rng: RandomNumberGenerator, v: int, base: Color, tip: Color) -> VoxelGrid:
	var w := 12
	var g := VoxelGrid.new(w, 12, w)
	for i in 16 + v * 4:
		var x := rng.randi_range(1, w - 2)
		var z := rng.randi_range(1, w - 2)
		var sh := rng.randi_range(3, 11)
		var dx := rng.randi_range(-1, 1)
		var dz := rng.randi_range(-1, 1)
		for y in sh:
			var xx := clampi(x + (dx if y > sh * 0.6 else 0), 0, w - 1)
			var zz := clampi(z + (dz if y > sh * 0.6 else 0), 0, w - 1)
			g.set_color(xx, y, zz, base.lerp(tip, float(y) / sh))
	return g


static func _flower(rng: RandomNumberGenerator, v: int) -> VoxelGrid:
	var w := 10
	var g := VoxelGrid.new(w, 12, w)
	var stem := Color(0.30, 0.55, 0.24)
	var petal: Color = FLOWER_COLORS[v % FLOWER_COLORS.size()]
	for i in 4:
		var x := rng.randi_range(2, w - 3)
		var z := rng.randi_range(2, w - 3)
		var sh := rng.randi_range(5, 10)
		for y in sh:
			g.set_color(x, y, z, stem)
		g.set_color(x, sh, z, Color(1.0, 0.9, 0.3))
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			g.set_color(x + d.x, sh, z + d.z, petal)
		g.set_color(x, sh + 1, z, petal)
		# 叶
		g.set_color(x + 1, 2, z, stem.lightened(0.1))
		g.set_color(x - 1, 3, z, stem.lightened(0.1))
	return g


static func _lotus(rng: RandomNumberGenerator, v: int) -> VoxelGrid:
	var g := VoxelGrid.new(12, 4, 12)
	var pad := Color(0.25, 0.52, 0.28)
	g.fill_cylinder_y(6, 6, 5.0, 0, 0, pad)
	g.clear_box(Vector3i(6, 0, 1), Vector3i(7, 0, 6))
	if v == 1:
		var pink := Color(1.0, 0.7, 0.8)
		g.fill_box(Vector3i(4, 1, 5), Vector3i(6, 2, 7), pink)
		g.set_color(5, 3, 6, Color(1.0, 0.85, 0.9))
	return g


# ================================================================ 灵草 / 矿脉

static func _herb_grid(item_id: String) -> Array:
	match item_id:
		"herb_fire_ganoderma":
			var g := VoxelGrid.new(10, 9, 10)
			var stalk := Color(0.55, 0.30, 0.20)
			var cap := VoxelGrid.glow(Color(1.0, 0.34, 0.12), 0.55)
			var rim := VoxelGrid.glow(Color(1.0, 0.72, 0.3), 0.8)
			g.fill_box(Vector3i(4, 0, 4), Vector3i(5, 4, 5), stalk)
			g.fill_ellipsoid(Vector3(5, 5.5, 5), Vector3(4.5, 1.6, 4.0), cap)
			for z in 10:
				for x in 10:
					for y in range(8, -1, -1):
						if g.is_solid(x, y, z) and y >= 5:
							var dx := x + 0.5 - 5.0
							var dz := z + 0.5 - 5.0
							if dx * dx + dz * dz > 11.0:
								g.set_color(x, y, z, rim)
							break
			g.fill_box(Vector3i(1, 0, 6), Vector3i(2, 2, 7), stalk)
			g.fill_ellipsoid(Vector3(2, 3, 7), Vector3(2.2, 1.0, 2.0), cap)
			return [g, 0.07]
		_:
			var g := VoxelGrid.new(12, 12, 12)
			var leaf := Color(0.30, 0.72, 0.52)
			var leaf2 := Color(0.45, 0.85, 0.62)
			var dew := VoxelGrid.glow(Color(0.6, 0.95, 1.0), 1.0)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(item_id)
			for i in 7:
				var a := i * TAU / 7.0
				var ln := rng.randi_range(4, 6)
				var h := rng.randi_range(5, 9)
				for k in ln:
					var t := float(k) / ln
					var x := int(6.0 + cos(a) * k * 0.9)
					var z := int(6.0 + sin(a) * k * 0.9)
					var y := int(t * h * (1.2 - t))
					g.set_color(clampi(x, 0, 11), clampi(y, 0, 11), clampi(z, 0, 11), leaf if k % 2 == 0 else leaf2)
				var tx := clampi(int(6.0 + cos(a) * ln * 0.9), 0, 11)
				var tz := clampi(int(6.0 + sin(a) * ln * 0.9), 0, 11)
				g.set_color(tx, clampi(int(h * 0.2) + 1, 0, 11), tz, dew)
			g.fill_box(Vector3i(5, 0, 5), Vector3i(6, 8, 6), leaf.darkened(0.1))
			g.fill_box(Vector3i(5, 9, 5), Vector3i(6, 10, 6), dew)
			return [g, 0.06]


## 灵草节点（group "herb_node"，meta "item_id"）
static func make_herb(item_id: String) -> Node3D:
	var key := "herb_" + item_id
	if not _meshes.has(key):
		var r := _herb_grid(item_id)
		var g: VoxelGrid = r[0]
		var vs: float = r[1]
		_meshes[key] = VoxelMesher.build(g, vs, Vector3(-g.sx * vs * 0.5, 0, -g.sz * vs * 0.5))
	var n := Node3D.new()
	n.name = "Herb"
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	n.add_to_group("herb_node")
	n.set_meta("item_id", item_id)
	return n


## 矿脉节点（StaticBody3D，world 层；group "ore_node"，meta "item_id"）
static func make_ore(item_id: String, variant: int = 0) -> StaticBody3D:
	var key := "ore_%s_%d" % [item_id, variant % 2]
	var vs := 0.25
	if not _meshes.has(key):
		var g := VoxelGrid.new(10, 7, 9)
		var rock := Color(0.36, 0.35, 0.37)
		var n := FastNoiseLite.new()
		n.seed = variant + 17
		n.frequency = 0.35
		g.fill_ellipsoid(Vector3(5, 1.5, 4.5), Vector3(4.8, 4.5, 4.2), rock)
		for z in 9:
			for y in 7:
				for x in 10:
					if g.is_solid(x, y, z):
						var nv := n.get_noise_3d(x, y, z)
						if item_id == "ore_gengjin":
							if nv > 0.25:
								g.set_color(x, y, z, VoxelGrid.glow(Color(1.0, 0.9, 0.45), 0.6))
						elif nv > 0.3:
							g.set_color(x, y, z, Color(0.62, 0.66, 0.74))
						elif nv < -0.4:
							g.set_color(x, y, z, Color(0.26, 0.25, 0.28))
		if item_id == "ore_gengjin":
			for i in 3:
				var x := 3 + i * 2
				for y in range(4, 7):
					g.set_color(x, y, 4 + (i % 2), VoxelGrid.glow(Color(1.0, 0.95, 0.6), 0.9))
		_meshes[key] = VoxelMesher.build(g, vs, Vector3(-g.sx * vs * 0.5, -vs, -g.sz * vs * 0.5))
	var body := StaticBody3D.new()
	body.name = "Ore"
	body.collision_layer = 1
	body.collision_mask = 0
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 1.4, 2.0)
	cs.shape = bs
	cs.position = Vector3(0, 0.55, 0)
	body.add_child(cs)
	body.add_to_group("ore_node")
	body.set_meta("item_id", item_id)
	return body


## 单独的树（带树干碰撞），用于建筑群中的点缀
static func make_tree(kind: String, variant: int = 0, collide: bool = true) -> Node3D:
	var root: Node3D
	var inf := info(kind)
	if collide and float(inf["trunk"]) > 0.0:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = float(inf["trunk"])
		cyl.height = float(inf["height"])
		cs.shape = cyl
		cs.position = Vector3(0, cyl.height * 0.5, 0)
		body.add_child(cs)
		root = body
	else:
		root = Node3D.new()
	root.name = kind.capitalize().replace(" ", "")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(kind, variant, 0)
	root.add_child(mi)
	return root
