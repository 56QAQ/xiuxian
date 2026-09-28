class_name DestructibleFactory
## 可破坏物构造器：岩石、石柱、墙（含废墟）、石灯笼、木箱。
## 同参数的模板（体素网格 + 网格 + 碰撞）会缓存复用，未受损的实例共享它们。

const PALETTES := {
	"gray": [Color(0.55, 0.55, 0.55), Color(0.47, 0.48, 0.49), Color(0.62, 0.61, 0.58)],
	"moss": [Color(0.46, 0.49, 0.44), Color(0.40, 0.43, 0.39), Color(0.34, 0.52, 0.26)],
	"snow": [Color(0.56, 0.59, 0.66), Color(0.48, 0.51, 0.58), Color(0.93, 0.95, 1.0)],
	"red": [Color(0.62, 0.28, 0.19), Color(0.72, 0.40, 0.25), Color(0.30, 0.24, 0.23)],
	"yellow": [Color(0.80, 0.63, 0.37), Color(0.72, 0.54, 0.31), Color(0.66, 0.64, 0.34)],
	"sand": [Color(0.78, 0.70, 0.52), Color(0.70, 0.62, 0.46), Color(0.82, 0.76, 0.58)],
}

static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


static func _make(key: String, vs: float, org: Vector3, builder: Callable) -> VoxelDestructible:
	if not _cache.has(key):
		var g: VoxelGrid = builder.call()
		var mesh := VoxelMesher.build(g, vs, org)
		var shape: Shape3D = mesh.create_trimesh_shape() if mesh.get_surface_count() > 0 else null
		_cache[key] = {"grid": g, "mesh": mesh, "shape": shape}
	var e: Dictionary = _cache[key]
	var d := VoxelDestructible.new()
	d.setup((e["grid"] as VoxelGrid).duplicate_grid(), vs, org, e["mesh"], e["shape"], key)
	d.name = key.capitalize().replace(" ", "")
	return d


static func _hash3(x: int, y: int, z: int, s: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (s * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0xffff) / 65535.0


## 岩石：带噪声的椭球，顶面可覆盖苔/雪；size_m 为直径（米）；palette 见 PALETTES
static func rock(seed_v: int = 0, size_m: float = 3.0, palette: String = "gray") -> VoxelDestructible:
	var variant := posmod(seed_v, 5)
	var sz := clampi(int(round(size_m)), 1, 8)
	var vs := 0.3 if sz >= 3 else 0.2
	var key := "rock_%s_%d_%d" % [palette, sz, variant]
	var n := int(ceil(sz / vs)) + 2
	var ny := int(ceil(sz * 0.8 / vs)) + 2
	var org := Vector3(-n * vs * 0.5, -vs * 2.0, -n * vs * 0.5)
	return _make(key, vs, org, func() -> VoxelGrid:
		var cols: Array = PALETTES.get(palette, PALETTES["gray"])
		var g := VoxelGrid.new(n, ny, n)
		var noise := FastNoiseLite.new()
		noise.seed = variant * 101 + sz
		noise.frequency = 0.18
		var c := Vector3(n * 0.5, 1.0, n * 0.5)
		var rad := Vector3(n * 0.5 - 1.0, ny - 1.5, n * 0.5 - 1.0) * Vector3(1.0 - variant * 0.06, 1.0, 0.85 + variant * 0.04)
		for z in n:
			for y in ny:
				for x in n:
					var p := Vector3(x + 0.5, y + 0.5, z + 0.5)
					var d := ((p - c) / rad).length()
					d += noise.get_noise_3d(x, y, z) * 0.35
					if d < 1.0:
						var band := int(y / 2.0 + noise.get_noise_2d(x, z) * 2.0) % 2
						var cc: Color = cols[band]
						cc = cc.lightened((_hash3(x, y, z, variant) - 0.5) * 0.08)
						g.set_color(x, y, z, cc)
		# 顶面覆盖层（苔/雪/枯草）
		if palette == "moss" or palette == "snow" or palette == "yellow":
			for z in n:
				for x in n:
					for y in range(ny - 1, -1, -1):
						if g.is_solid(x, y, z):
							if y >= 2 and (palette == "snow" or noise.get_noise_2d(x * 2.0, z * 2.0) > -0.15):
								g.set_color(x, y, z, (cols[2] as Color).lightened((_hash3(x, y, z, 3) - 0.5) * 0.1))
							break
		return g)


## 石柱 / 红漆柱：height 米，radius 米；ruined=true 时顶部参差
static func pillar(height: float = 4.0, body: Color = Color(0.62, 0.14, 0.11), trim: Color = Color(0.85, 0.68, 0.30), radius: float = 0.4, ruined: bool = false) -> VoxelDestructible:
	var vs := 0.2
	var key := "pillar_%d_%d_%s_%s_%d" % [int(height * 10), int(radius * 100), body.to_html(false), trim.to_html(false), int(ruined)]
	var r := radius / vs
	var n := int(ceil(r * 2.0 + 3.0))
	var ny := int(ceil(height / vs))
	var org := Vector3(-n * vs * 0.5, -vs, -n * vs * 0.5)
	return _make(key, vs, org, func() -> VoxelGrid:
		var g := VoxelGrid.new(n, ny, n)
		var c := n * 0.5
		var stone := Color(0.64, 0.63, 0.60)
		for y in ny:
			var rr := r
			var cc := body
			if y < 2:
				rr = r + 1.4
				cc = stone
			elif y < 3:
				rr = r + 0.8
				cc = stone.darkened(0.1)
			elif y >= ny - 2:
				rr = r + 1.0
				cc = trim
			elif (y - 3) % 7 == 0:
				cc = trim
			if ruined and y > ny * 0.55:
				continue
			for z in n:
				for x in n:
					var dx := x + 0.5 - c
					var dz := z + 0.5 - c
					if dx * dx + dz * dz <= rr * rr:
						g.set_color(x, y, z, cc.lightened((_hash3(x, y, z, 7) - 0.5) * 0.06))
		if ruined:
			var top := int(ny * 0.55)
			for z in n:
				for x in n:
					var extra := int(_hash3(x, 0, z, 11) * 6.0)
					for y in range(top, mini(top + extra, ny)):
						var dx := x + 0.5 - c
						var dz := z + 0.5 - c
						if dx * dx + dz * dz <= r * r:
							g.set_color(x, y, z, body.darkened(0.1))
		return g)


## 墙：长 length（x）、高 height、厚 0.5；style "brick"（砖墙）/"ruin"（残垣）/"white"（粉墙黛瓦）
static func wall(length: float = 6.0, height: float = 3.0, style: String = "brick", seed_v: int = 0) -> VoxelDestructible:
	var vs := 0.25
	var key := "wall_%s_%d_%d_%d" % [style, int(length * 4), int(height * 4), posmod(seed_v, 3)]
	var nx := int(ceil(length / vs))
	var ny := int(ceil(height / vs))
	var nz := 2
	var org := Vector3(-nx * vs * 0.5, -vs, -nz * vs * 0.5)
	return _make(key, vs, org, func() -> VoxelGrid:
		var g := VoxelGrid.new(nx, ny, nz)
		var b1 := Color(0.60, 0.58, 0.55)
		var b2 := Color(0.52, 0.50, 0.48)
		var mortar := Color(0.72, 0.70, 0.66)
		if style == "ruin":
			b1 = Color(0.58, 0.55, 0.50)
			b2 = Color(0.47, 0.45, 0.42)
		for x in nx:
			var top := ny
			if style == "ruin":
				top = int(ny * (0.45 + 0.55 * absf(sin(x * 0.37 + seed_v))) - _hash3(x, 0, 0, seed_v) * 3.0)
				top = clampi(top, 2, ny)
			for y in top:
				for z in nz:
					var c: Color
					if style == "white":
						c = Color(0.92, 0.90, 0.86) if y > 2 else Color(0.5, 0.5, 0.52)
						if y >= ny - 2:
							c = Color(0.24, 0.26, 0.31)
					else:
						var row := y / 2
						var bx := (x + (row % 2) * 2) / 4
						c = b1 if (bx + row) % 2 == 0 else b2
						if y % 2 == 1 and (x + (row % 2) * 2) % 4 == 3:
							c = mortar
					g.set_color(x, y, z, c.lightened((_hash3(x, y, z, seed_v) - 0.5) * 0.06))
		return g)


## 石灯笼：底座、灯柱、发光灯室、屋顶
static func lantern(glow: Color = Color(1.0, 0.72, 0.38), stone: Color = Color(0.66, 0.65, 0.61)) -> VoxelDestructible:
	var vs := 0.125
	var key := "lantern_%s_%s" % [glow.to_html(false), stone.to_html(false)]
	var n := 8
	var ny := 16
	var org := Vector3(-n * vs * 0.5, -vs, -n * vs * 0.5)
	return _make(key, vs, org, func() -> VoxelGrid:
		var g := VoxelGrid.new(n, ny, n)
		var dark := stone.darkened(0.15)
		g.fill_box(Vector3i(0, 0, 0), Vector3i(7, 1, 7), dark)
		g.fill_box(Vector3i(1, 2, 1), Vector3i(6, 2, 6), stone)
		g.fill_box(Vector3i(3, 3, 3), Vector3i(4, 7, 4), stone)
		g.fill_box(Vector3i(1, 8, 1), Vector3i(6, 8, 6), stone)
		g.fill_box(Vector3i(2, 9, 2), Vector3i(5, 11, 5), stone)
		g.fill_box(Vector3i(3, 9, 2), Vector3i(4, 10, 5), VoxelGrid.glow(glow, 0.9))
		g.fill_box(Vector3i(2, 9, 3), Vector3i(5, 10, 4), VoxelGrid.glow(glow, 0.9))
		g.fill_box(Vector3i(0, 12, 0), Vector3i(7, 12, 7), dark)
		g.fill_box(Vector3i(1, 13, 1), Vector3i(6, 13, 6), stone)
		g.fill_box(Vector3i(3, 14, 3), Vector3i(4, 15, 4), dark)
		return g)


## 木箱（size 米见方）
static func crate(size: float = 1.0, wood: Color = Color(0.58, 0.40, 0.22)) -> VoxelDestructible:
	var vs := 0.125
	var n := clampi(int(round(size / vs)), 4, 16)
	var key := "crate_%d_%s" % [n, wood.to_html(false)]
	var org := Vector3(-n * vs * 0.5, 0.0, -n * vs * 0.5)
	return _make(key, vs, org, func() -> VoxelGrid:
		var g := VoxelGrid.new(n, n, n)
		var frame := wood.darkened(0.3)
		for z in n:
			for y in n:
				for x in n:
					var ex := x == 0 or x == n - 1
					var ey := y == 0 or y == n - 1
					var ez := z == 0 or z == n - 1
					var edges := int(ex) + int(ey) + int(ez)
					var c := wood if (y / 2) % 2 == 0 else wood.darkened(0.08)
					if edges >= 2:
						c = frame
					g.set_color(x, y, z, c.lightened((_hash3(x, y, z, 5) - 0.5) * 0.08))
		return g)
