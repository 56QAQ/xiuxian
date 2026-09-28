class_name TerrainGen
extends RefCounted
## 大地图地形（1024×1024 米，1 米方块柱，高度约 0~100 米，海平面 12 米）。
##
## 由种子确定性生成：
##   区域中心（软 Voronoi + 域扭曲）→ 2 米粗网格混合各区域高度函数（多线程）
##   → Image 三次插值放大到 1 米 → 细节噪声 → 剑峰/石林/火山口/熔岩池/洞府山丘
##   → POI 平台压平 → 道路 → 取整为方块高度（hmap）。
## 区域：中央青云坊市平原、北天剑宗雪峰、东青木谷古林、南玄水阁湖泽、西离火殿赤岩火山、西南厚土宗黄土台地，四周海洋。
##
## 线程安全：generate() 完成后，只读查询与 build_chunk_arrays()/build_lod_arrays() 可在工作线程并发调用；
## carve_crater() 只能在主线程调用（写入时 Packed 数组写时复制，工作线程持有的旧快照不受影响）。

const SIZE := 1024
const CHUNK := 32
const CHUNKS := SIZE / CHUNK
const SEA_LEVEL := 12          ## 柱顶 y < SEA_LEVEL 的方块在水下
const WATER_Y := 11.8          ## 水面高度
const DEFAULT_SEED := 20250917
const MAX_H := 120
const LOD_CELL := 4            ## 远景 LOD 网格边长（米）
const LOD_N := SIZE / LOD_CELL
const LOD_TILE := 64           ## 每个 LOD 分块的格数（64 × 4 米 = 256 米）
const LOD_TILES := LOD_N / LOD_TILE

const MACRO_STEP := 2
const MN := SIZE / MACRO_STEP  ## 粗网格边长（样本数）
const WARP := 85.0
const T_HEIGHT := 42.0         ## 高度混合的软化距离
const T_BIOME := 16.0          ## 地表混合的软化距离

# 区域 / 生物群系
const R_PLAINS := 0
const R_SNOW := 1
const R_FOREST := 2
const R_LAKE := 3
const R_VOLCANIC := 4
const R_PLATEAU := 5
const R_OCEAN := 6
const REGION_COUNT := 6
const BIOME_NAMES := ["plains", "snow", "forest", "lake", "volcanic", "plateau", "ocean"]
const BIOME_CN := ["平原", "雪峰", "古林", "湖泽", "赤岩", "黄土台地", "海"]
## 区域中心基准（会按种子抖动）
const REGION_BASE := [Vector2(512, 512), Vector2(500, 150), Vector2(872, 470), Vector2(560, 872), Vector2(150, 440), Vector2(222, 832)]
const REGION_SECT := ["", "tianjian", "qingmu", "xuanshui", "lihuo", "houtu"]
## 各区域细节噪声幅度（米）
const REGION_ROUGH := [1.3, 3.2, 2.2, 0.9, 2.2, 1.1]

# 列标记位
const F_ROAD := 1
const F_PAVED := 2
const F_LAVA := 4
const F_NOPROP := 8     ## 不生成树木/岩石（POI、道路）
const F_SCORCH := 16    ## 弹坑焦土
const F_FIELD := 32     ## 药田
const F_NOGRASS := 64   ## 不生成草花（建筑群内部）

# 地表类型
const S_GRASS := 0
const S_FOREST := 1
const S_SNOW := 2
const S_STONE := 3
const S_SAND := 4
const S_MUD := 5
const S_WETGRASS := 6
const S_ASH := 7
const S_REDROCK := 8
const S_OBSIDIAN := 9
const S_LAVA := 10
const S_LOESS := 11
const S_DRYGRASS := 12
const S_ROAD := 13
const S_PAVED := 14
const S_GRAVEL := 15
const S_SCORCH := 16
const S_ALPINE := 17
const S_BLACKSAND := 18
const S_SNOWROCK := 19
const S_FIELD := 20
const S_CANOPY := 21     ## 远景 LOD 树冠

## 地表调色（sRGB）：[顶面, 顶块侧面, 表土, 表土厚度, 岩层 A, 岩层 B]
const SURF := [
	[Color(0.41, 0.63, 0.28), Color(0.44, 0.50, 0.27), Color(0.52, 0.38, 0.25), 3, Color(0.50, 0.50, 0.50), Color(0.44, 0.45, 0.46)],   # 草地
	[Color(0.26, 0.50, 0.22), Color(0.32, 0.40, 0.22), Color(0.38, 0.28, 0.19), 3, Color(0.42, 0.46, 0.41), Color(0.36, 0.40, 0.36)],   # 林地
	[Color(0.94, 0.96, 1.00), Color(0.90, 0.93, 0.98), Color(0.78, 0.84, 0.92), 2, Color(0.55, 0.58, 0.65), Color(0.47, 0.50, 0.58)],   # 雪
	[Color(0.56, 0.56, 0.56), Color(0.53, 0.53, 0.53), Color(0.50, 0.50, 0.50), 1, Color(0.50, 0.50, 0.51), Color(0.44, 0.45, 0.46)],   # 岩石
	[Color(0.88, 0.80, 0.58), Color(0.86, 0.77, 0.55), Color(0.84, 0.74, 0.52), 3, Color(0.78, 0.68, 0.48), Color(0.72, 0.62, 0.43)],   # 沙
	[Color(0.43, 0.38, 0.27), Color(0.40, 0.34, 0.24), Color(0.36, 0.30, 0.22), 3, Color(0.46, 0.43, 0.39), Color(0.41, 0.38, 0.35)],   # 泥
	[Color(0.36, 0.62, 0.36), Color(0.38, 0.46, 0.28), Color(0.36, 0.30, 0.22), 3, Color(0.46, 0.46, 0.44), Color(0.40, 0.41, 0.40)],   # 湿草
	[Color(0.35, 0.30, 0.29), Color(0.33, 0.27, 0.25), Color(0.30, 0.24, 0.22), 2, Color(0.56, 0.24, 0.17), Color(0.67, 0.35, 0.22)],   # 火山灰
	[Color(0.67, 0.31, 0.20), Color(0.62, 0.28, 0.19), Color(0.60, 0.27, 0.18), 1, Color(0.60, 0.26, 0.18), Color(0.73, 0.41, 0.25)],   # 赤岩
	[Color(0.15, 0.12, 0.17), Color(0.18, 0.14, 0.19), Color(0.20, 0.15, 0.18), 2, Color(0.50, 0.22, 0.16), Color(0.40, 0.18, 0.14)],   # 黑曜石
	[Color(1.00, 0.50, 0.10, 0.5), Color(0.95, 0.35, 0.06, 0.62), Color(0.15, 0.12, 0.17), 2, Color(0.50, 0.22, 0.16), Color(0.40, 0.18, 0.14)],   # 熔岩
	[Color(0.83, 0.67, 0.39), Color(0.80, 0.63, 0.36), Color(0.78, 0.60, 0.34), 4, Color(0.74, 0.54, 0.30), Color(0.87, 0.73, 0.47)],   # 黄土
	[Color(0.67, 0.65, 0.33), Color(0.72, 0.61, 0.35), Color(0.78, 0.60, 0.34), 3, Color(0.74, 0.54, 0.30), Color(0.87, 0.73, 0.47)],   # 枯草
	[Color(0.64, 0.56, 0.42), Color(0.56, 0.46, 0.33), Color(0.52, 0.38, 0.25), 2, Color(0.50, 0.50, 0.50), Color(0.44, 0.45, 0.46)],   # 道路
	[Color(0.68, 0.67, 0.64), Color(0.62, 0.61, 0.58), Color(0.56, 0.55, 0.53), 1, Color(0.50, 0.50, 0.50), Color(0.44, 0.45, 0.46)],   # 铺地
	[Color(0.56, 0.54, 0.50), Color(0.52, 0.50, 0.47), Color(0.50, 0.48, 0.45), 2, Color(0.50, 0.50, 0.50), Color(0.44, 0.45, 0.46)],   # 砾石
	[Color(0.24, 0.20, 0.18), Color(0.30, 0.24, 0.20), Color(0.40, 0.30, 0.22), 2, Color(0.46, 0.44, 0.42), Color(0.40, 0.38, 0.36)],   # 焦土
	[Color(0.45, 0.60, 0.42), Color(0.46, 0.49, 0.36), Color(0.44, 0.36, 0.27), 2, Color(0.55, 0.58, 0.65), Color(0.47, 0.50, 0.58)],   # 高山草甸
	[Color(0.22, 0.20, 0.23), Color(0.24, 0.21, 0.24), Color(0.26, 0.22, 0.24), 3, Color(0.50, 0.22, 0.16), Color(0.40, 0.18, 0.14)],   # 黑沙
	[Color(0.60, 0.62, 0.68), Color(0.56, 0.58, 0.64), Color(0.53, 0.56, 0.62), 1, Color(0.55, 0.58, 0.65), Color(0.47, 0.50, 0.58)],   # 雪岩
	[Color(0.36, 0.26, 0.17), Color(0.40, 0.30, 0.20), Color(0.44, 0.33, 0.22), 2, Color(0.50, 0.50, 0.50), Color(0.44, 0.45, 0.46)],   # 药田
	[Color(0.22, 0.44, 0.21), Color(0.20, 0.40, 0.19), Color(0.18, 0.36, 0.18), 7, Color(0.30, 0.22, 0.15), Color(0.30, 0.22, 0.15)],   # 树冠（LOD）
]

## 线程安全的运行时副本（Godot 4.4 中并发读取 const（只读）Array 会共用一个临时 Variant，导致内存错误）
static var _surf_top := _surf_col(0)
static var _surf_side := _surf_col(1)
static var _surf_sub := _surf_col(2)
static var _surf_a := _surf_col(4)
static var _surf_b := _surf_col(5)
static var _surf_depth := _surf_depth_arr()
static var _region_rough := PackedFloat32Array(REGION_ROUGH)
static var _biome_names := PackedStringArray(BIOME_NAMES)
static var _ao := PackedFloat32Array([0.56, 0.72, 0.87, 1.0])


static func _surf_col(i: int) -> PackedColorArray:
	var out := PackedColorArray()
	for e in SURF:
		out.append(e[i])
	return out


static func _surf_depth_arr() -> PackedInt32Array:
	var out := PackedInt32Array()
	for e in SURF:
		out.append(int(e[3]))
	return out


## 坊市铺地（局部矩形：中心 x, z, 半宽 x, 半宽 z），BuildingBuilder 与此一致
const TOWN_HALF := Vector2(96, 74)
const TOWN_PAVED := [Rect2(-80, -5, 160, 10), Rect2(-16, -16, 32, 32), Rect2(-4.5, -64, 9, 128)]
const SECT_HALF := Vector2(46, 52)
## 宗门铺地（局部矩形）：山门前广场、中轴路、主院、主殿台基、横向小路
const SECT_PAVED := [Rect2(-12, -52, 24, 6), Rect2(-4, -52, 8, 40), Rect2(-22, -14, 44, 34), Rect2(-15, 20, 30, 20), Rect2(-31, -33, 62, 6)]
const HOME_HALF := Vector2(11, 17)
## 洞府石室在局部 z ∈ [HOME_CAVE_Z0, HOME_HALF.y]（后部），前院在其前
const HOME_CAVE_Z0 := 1

## 地形被修改（弹坑）：受影响区块、被移除的地表样本 [[Vector3, Color]...]、位置与半径
signal changed(chunks: Array, samples: Array, pos: Vector3, radius: float)

var seed_value: int
var hmap := PackedByteArray()      ## 方块高度（柱顶 y），索引 z * SIZE + x
var flags := PackedByteArray()     ## 列标记位 F_*
var biome_a := PackedByteArray()   ## 粗网格：主区域
var biome_b := PackedByteArray()   ## 粗网格：次区域
var biome_t := PackedFloat32Array()  ## 粗网格：次区域占比 0~0.5
var region_centers := PackedVector2Array()
var pois: Array[Dictionary] = []
var craters: Array[Dictionary] = []
var volcano := Vector4()           ## x, z, 半径, 火山口岩浆高度
var spires: Array[Vector4] = []    ## x, z, 半径, 峰顶高度
var roads: Array[PackedVector2Array] = []
var lod_heights := PackedInt32Array()  ## LOD_N × LOD_N
var home_cave_heights := PackedByteArray()  ## 洞府石室范围内压平前的高度（局部行优先）
var home_cave_rect := Rect2i()
var gen_ms := 0.0

var n_warp: FastNoiseLite
var n_base: FastNoiseLite
var n_hill: FastNoiseLite
var n_ridge: FastNoiseLite
var n_lake: FastNoiseLite
var n_mesa: FastNoiseLite
var n_detail: FastNoiseLite
var n_patch: FastNoiseLite

var _map_cache: Dictionary = {}
var _macro_h := PackedFloat32Array()
var _macro_r := PackedFloat32Array()
var _hf := PackedFloat32Array()

static var _shared: Dictionary = {}


# ================================================================ 共享实例

## 当前游戏种子（GS.world 为空时使用默认种子）
static func default_seed() -> int:
	return int(GS.world.get("seed", DEFAULT_SEED))


## 取得（并按需生成）该种子的共享地形。同一会话内弹坑等修改会保留。
static func shared(seed_v: int = -1) -> TerrainGen:
	if seed_v == -1:
		seed_v = default_seed()
	if not _shared.has(seed_v):
		_shared.clear()
		var t := TerrainGen.new(seed_v)
		t.generate()
		_shared[seed_v] = t
	return _shared[seed_v]


func _init(seed_v: int = DEFAULT_SEED) -> void:
	seed_value = seed_v
	n_warp = _mk(11, 1.0 / 240.0, 3)
	n_base = _mk(23, 1.0 / 260.0, 4)
	n_hill = _mk(37, 1.0 / 95.0, 3)
	n_ridge = _mk(41, 1.0 / 210.0, 5, FastNoiseLite.FRACTAL_RIDGED)
	n_lake = _mk(53, 1.0 / 85.0, 3)
	n_mesa = _mk(67, 1.0 / 110.0, 2)
	n_detail = _mk(71, 1.0 / 22.0, 3)
	n_patch = _mk(83, 1.0 / 38.0, 2)


func _mk(off: int, freq: float, octaves: int, fractal: int = FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = (seed_value + off * 7919) & 0x7fffffff
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	n.fractal_lacunarity = 2.0
	n.fractal_gain = 0.5
	return n


# ================================================================ 生成

func generate() -> void:
	var t0 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value)
	_place_regions(rng)
	_place_volcano(rng)
	_build_macro()
	_build_fine()
	_place_pois(rng)
	_place_spires(rng)
	_apply_features()
	_apply_pois()
	_apply_roads()
	_finalize()
	_build_lod_heights()
	_macro_h = PackedFloat32Array()
	_macro_r = PackedFloat32Array()
	_hf = PackedFloat32Array()
	gen_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _place_regions(rng: RandomNumberGenerator) -> void:
	region_centers.resize(REGION_COUNT)
	for i in REGION_COUNT:
		var j := Vector2(rng.randf_range(-22, 22), rng.randf_range(-22, 22))
		if i == R_PLAINS:
			j *= 0.3
		region_centers[i] = REGION_BASE[i] + j


func _place_volcano(rng: RandomNumberGenerator) -> void:
	var c: Vector2 = region_centers[R_VOLCANIC]
	var away := (c - region_centers[R_PLAINS]).normalized()
	var p := c + away * 35.0 + away.orthogonal() * rng.randf_range(-40, 40)
	volcano = Vector4(p.x, p.y, 125.0, 0.0)


## 粗网格（2 米）：区域权重、混合高度、细节幅度、主/次区域
func _build_macro() -> void:
	var n := MN * MN
	_macro_h.resize(n)
	_macro_r.resize(n)
	biome_a.resize(n)
	biome_b.resize(n)
	biome_t.resize(n)
	var gid := WorkerThreadPool.add_group_task(_macro_row, MN, 4, true, "terrain_macro")
	WorkerThreadPool.wait_for_group_task_completion(gid)


func _macro_row(j: int) -> void:
	var dist := PackedFloat32Array()
	dist.resize(REGION_COUNT)
	var z := j * MACRO_STEP + 1.0
	var rc := region_centers
	for i in MN:
		var x := i * MACRO_STEP + 1.0
		var wx := x + n_warp.get_noise_2d(x, z) * WARP
		var wz := z + n_warp.get_noise_2d(x + 7919.0, z - 3571.0) * WARP
		var dmin := 1e9
		var dsec := 1e9
		var ka := 0
		var kb := 0
		for k in REGION_COUNT:
			var c: Vector2 = rc[k]
			var d := sqrt((wx - c.x) * (wx - c.x) + (wz - c.y) * (wz - c.y))
			if k == R_PLAINS:
				d += 25.0
			dist[k] = d
			if d < dmin:
				dsec = dmin
				kb = ka
				dmin = d
				ka = k
			elif d < dsec:
				dsec = d
				kb = k
		var hs := 0.0
		var rs := 0.0
		var ws := 0.0
		for k in REGION_COUNT:
			var w := exp(-(dist[k] - dmin) / T_HEIGHT)
			if w < 0.015:
				continue
			hs += w * _region_height(k, x, z)
			rs += w * _region_rough[k]
			ws += w
		var h := hs / ws
		var rough := rs / ws
		# 火山锥
		var vd := Vector2(x - volcano.x, z - volcano.y).length()
		if vd < volcano.z:
			h += 60.0 * pow(1.0 - vd / volcano.z, 1.6)
		# 海岸
		var e := minf(minf(wx, wz), minf(SIZE - wx, SIZE - wz))
		var o := 1.0 - smoothstep(22.0, 78.0, e)
		if o > 0.0:
			h = lerpf(h, 4.0 + 2.5 * n_base.get_noise_2d(x * 3.0, z * 3.0), o)
			rough = lerpf(rough, 0.8, o)
		var idx := j * MN + i
		_macro_h[idx] = h
		_macro_r[idx] = rough
		if o > 0.6:
			biome_a[idx] = R_OCEAN
			biome_b[idx] = ka
			biome_t[idx] = 0.0
		else:
			biome_a[idx] = ka
			biome_b[idx] = kb
			biome_t[idx] = 1.0 / (1.0 + exp((dsec - dmin) / T_BIOME))


func _region_height(k: int, x: float, z: float) -> float:
	match k:
		R_PLAINS:
			var hill := maxf(n_hill.get_noise_2d(x, z), 0.0)
			return 15.8 + 3.2 * n_base.get_noise_2d(x, z) + 7.0 * hill * hill
		R_SNOW:
			var r := (n_ridge.get_noise_2d(x, z) + 1.0) * 0.5
			return 30.0 + 64.0 * r * r * (0.55 + 0.45 * r) + 6.0 * n_base.get_noise_2d(x, z)
		R_FOREST:
			return 22.0 + 7.0 * n_base.get_noise_2d(x, z) + 12.0 * absf(n_hill.get_noise_2d(x, z))
		R_LAKE:
			return 11.3 + 6.5 * n_lake.get_noise_2d(x, z) + 1.5 * n_base.get_noise_2d(x, z)
		R_VOLCANIC:
			var v := 22.0 + 10.0 * n_base.get_noise_2d(x, z) + 9.0 * n_hill.get_noise_2d(x, z)
			var step := 5.0
			var f := v / step
			return floorf(f) * step + step * smoothstep(0.72, 1.0, f - floorf(f))
		R_PLATEAU:
			var m := smoothstep(-0.04, 0.12, n_mesa.get_noise_2d(x, z))
			var hill2 := n_hill.get_noise_2d(x, z)
			var top := 42.0 + 3.0 * floorf(hill2 * 2.0 + 0.5)
			return lerpf(18.0 + 3.0 * hill2, top, m)
	return 16.0


## 1 米网格：放大粗网格 + 细节噪声
func _build_fine() -> void:
	var img := Image.create_empty(MN, MN, false, Image.FORMAT_RGF)
	var buf := PackedFloat32Array()
	buf.resize(MN * MN * 2)
	for i in MN * MN:
		buf[i * 2] = _macro_h[i]
		buf[i * 2 + 1] = _macro_r[i]
	img.set_data(MN, MN, false, Image.FORMAT_RGF, buf.to_byte_array())
	img.resize(SIZE, SIZE, Image.INTERPOLATE_CUBIC)
	var up := img.get_data().to_float32_array()
	var det := n_detail.get_image(SIZE, SIZE, false, false, false).get_data()
	_hf.resize(SIZE * SIZE)
	for i in SIZE * SIZE:
		_hf[i] = up[i * 2] + (det[i] / 127.5 - 1.0) * up[i * 2 + 1]
	flags.resize(SIZE * SIZE)
	flags.fill(0)


# ================================================================ POI 布局

func _place_pois(rng: RandomNumberGenerator) -> void:
	pois.clear()
	var town_c: Vector2 = region_centers[R_PLAINS]
	var town := _poi("town", "青云坊市", "town", town_c, Vector2(0, 1))
	town["half"] = TOWN_HALF
	town["margin"] = 34.0
	town["height"] = clampi(int(_avg_hf(town_c, 30.0)), SEA_LEVEL + 5, 24)
	pois.append(town)
	# 五宗
	var toward := {"tianjian": 78.0, "qingmu": 95.0, "xuanshui": 70.0, "lihuo": 95.0, "houtu": 70.0}
	var hclamp := {"tianjian": Vector2i(30, 56), "qingmu": Vector2i(19, 36), "xuanshui": Vector2i(14, 14), "lihuo": Vector2i(22, 40), "houtu": Vector2i(30, 44)}
	for k in range(1, REGION_COUNT):
		var sid: String = REGION_SECT[k]
		var rc: Vector2 = region_centers[k]
		var dir := (town_c - rc).normalized()
		var p := rc + dir * float(toward[sid])
		var face := _cardinal(town_c - p)
		var sd: Dictionary = DB.sect(sid)
		var sp := _poi("sect_" + sid, str(sd.get("name", sid)), "sect", p, face)
		sp["sect_id"] = sid
		sp["half"] = SECT_HALF
		sp["margin"] = 30.0 if sid != "xuanshui" else 16.0
		var hc: Vector2i = hclamp[sid]
		sp["height"] = clampi(int(_avg_hf(p, 24.0)), hc.x, hc.y)
		sp["region"] = BIOME_NAMES[k]
		pois.append(sp)
	# 洞府：坊市东北方向的山坡
	var ang := deg_to_rad(-45.0 + rng.randf_range(-18.0, 18.0))
	var hdir := Vector2(cos(ang), sin(ang))
	var hp := town_c + hdir * 168.0
	var hface := _cardinal(town_c - hp)
	var home := _poi("home", "洞府", "home", hp, hface)
	home["half"] = HOME_HALF
	home["margin"] = 5.0
	home["height"] = clampi(int(_hf_at(hp.x, hp.y)), SEA_LEVEL + 4, 30)
	pois.append(home)
	# 秘境入口
	var fc: Vector2 = region_centers[R_FOREST]
	var sc: Vector2 = region_centers[R_SNOW]
	var lc: Vector2 = region_centers[R_LAKE]
	var vc: Vector2 = region_centers[R_VOLCANIC]
	var pc: Vector2 = region_centers[R_PLATEAU]
	var portal_spots := [
		["herb_valley", fc + (town_c - fc).normalized() * 150.0 + (town_c - fc).normalized().orthogonal() * 75.0],
		["ancient_abode", town_c.lerp(sc, 0.55) + (sc - town_c).normalized().orthogonal() * 95.0],
		["herb_valley", lc + Vector2(135, -30)],
		["ancient_abode", vc + (town_c - vc).normalized().orthogonal() * -115.0],
		["ancient_abode", pc + (town_c - pc).normalized().orthogonal() * 95.0],
	]
	var pi := 0
	for spot in portal_spots:
		var rid: String = spot[0]
		var pos := _find_land(spot[1], 16.0)
		var rdef: Dictionary = DB.secret_realms.get(rid, {})
		var pp := _poi("portal_%d" % pi, "%s·秘境入口" % str(rdef.get("name", rid)), "portal", pos, _cardinal(town_c - pos))
		pp["realm_id"] = rid
		pp["half"] = Vector2(10, 10)
		pp["round"] = true
		pp["margin"] = 8.0
		pp["height"] = maxi(int(_avg_hf(pos, 6.0)), SEA_LEVEL + 2)
		pp["region"] = BIOME_NAMES[_region_at(pos.x, pos.y)]
		pois.append(pp)
		pi += 1
	# 地标
	var lm := [
		["landmark_volcano", "赤炎火山", Vector2(volcano.x, volcano.y), false],
		["landmark_sword_tomb", "剑冢", _find_land(sc + (town_c - sc).normalized() * 40.0 + (town_c - sc).normalized().orthogonal() * -150.0, 16.0), true],
		["landmark_battlefield", "古战场遗迹", _find_land(town_c.lerp((sc + vc) * 0.5, 0.62), 16.0), true],
		["landmark_ancient_tree", "千年灵木", _find_land(fc + (town_c - fc).normalized().orthogonal() * 85.0 + Vector2(30, 0), 16.0), true],
		["landmark_stone_forest", "石林", _find_land(pc + (town_c - pc).normalized() * -40.0 + Vector2(0, -60), 16.0), false],
		["landmark_moon_lake", "望月湖", lc + Vector2(-70, 20), false],
	]
	for l in lm:
		var lp := _poi(l[0], l[1], "landmark", l[2], _cardinal(town_c - l[2]))
		lp["round"] = true
		lp["region"] = BIOME_NAMES[_region_at(lp["pos"].x, lp["pos"].z)]
		if l[3]:
			lp["half"] = Vector2(18, 18)
			lp["margin"] = 12.0
			lp["height"] = maxi(int(_avg_hf(l[2], 8.0)), SEA_LEVEL + 2)
		pois.append(lp)


func _poi(id: String, pname: String, ptype: String, p: Vector2, face: Vector2) -> Dictionary:
	# 中心取整：旋转 90° 倍数后，局部整数坐标与地形 1 米网格对齐
	p = p.round()
	var yaw := atan2(-face.x, -face.y)
	return {"id": id, "name": pname, "type": ptype, "pos": Vector3(p.x, 0.0, p.y),
		"facing": Vector3(face.x, 0.0, face.y), "yaw": yaw, "half": Vector2.ZERO, "margin": 0.0}


## 最接近的四个正方向之一
static func _cardinal(v: Vector2) -> Vector2:
	if absf(v.x) > absf(v.y):
		return Vector2(signf(v.x), 0)
	return Vector2(0, signf(v.y) if v.y != 0.0 else 1.0)


func _find_land(p: Vector2, min_h: float) -> Vector2:
	p = p.clamp(Vector2(90, 90), Vector2(SIZE - 90, SIZE - 90))
	if _avg_hf(p, 6.0) >= min_h and _free_of_pois(p, 30.0):
		return p
	for ring in range(1, 14):
		var r := ring * 10.0
		for a in 12:
			var q := p + Vector2(cos(a * TAU / 12.0), sin(a * TAU / 12.0)) * r
			if q.x < 80 or q.y < 80 or q.x > SIZE - 80 or q.y > SIZE - 80:
				continue
			if _avg_hf(q, 6.0) >= min_h and _free_of_pois(q, 30.0):
				return q
	return p


func _free_of_pois(p: Vector2, gap: float) -> bool:
	for poi in pois:
		var half: Vector2 = poi["half"]
		var r := half.length() + float(poi["margin"]) + gap
		if Vector2(poi["pos"].x, poi["pos"].z).distance_to(p) < r:
			return false
	return true


func _place_spires(rng: RandomNumberGenerator) -> void:
	spires.clear()
	var sc: Vector2 = region_centers[R_SNOW]
	var sect_p := _poi_pos2("sect_tianjian")
	var town_c: Vector2 = region_centers[R_PLAINS]
	var tries := 0
	while spires.size() < 18 and tries < 400:
		tries += 1
		var p := sc + Vector2(rng.randf_range(-240, 240), rng.randf_range(-120, 150))
		if p.x < 70 or p.y < 60 or p.x > SIZE - 70:
			continue
		if p.distance_to(sect_p) < 80.0 or _dist_to_segment(p, town_c, sect_p) < 30.0:
			continue
		if _region_at(p.x, p.y) != R_SNOW:
			continue
		var ok := true
		for s in spires:
			if Vector2(s.x, s.y).distance_to(p) < 24.0:
				ok = false
				break
		if not ok:
			continue
		var base := _hf_at(p.x, p.y)
		var top := clampf(base + rng.randf_range(22.0, 48.0), 60.0, 104.0)
		spires.append(Vector4(p.x, p.y, rng.randf_range(5.0, 10.0), top))
	# 石林（西南）
	var pc: Vector2 = region_centers[R_PLATEAU]
	var stone_c := _poi_pos2("landmark_stone_forest")
	var houtu_p := _poi_pos2("sect_houtu")
	tries = 0
	var count := 0
	while count < 16 and tries < 300:
		tries += 1
		var p := stone_c + Vector2(rng.randf_range(-70, 70), rng.randf_range(-70, 70))
		if p.distance_to(houtu_p) < 75.0 or _dist_to_segment(p, town_c, houtu_p) < 20.0:
			continue
		if _region_at(p.x, p.y) != R_PLATEAU:
			continue
		var base := _hf_at(p.x, p.y)
		spires.append(Vector4(p.x, p.y, rng.randf_range(2.5, 5.0), base + rng.randf_range(10.0, 22.0)))
		count += 1


func _poi_pos2(id: String) -> Vector2:
	for p in pois:
		if p["id"] == id:
			return Vector2(p["pos"].x, p["pos"].z)
	return Vector2(-9999, -9999)


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ================================================================ 1 米特征

func _apply_features() -> void:
	# 剑峰 / 石林
	for s in spires:
		var r := s.z
		var x0 := maxi(int(s.x - r - 2), 0)
		var x1 := mini(int(s.x + r + 2), SIZE - 1)
		var z0 := maxi(int(s.y - r - 2), 0)
		var z1 := mini(int(s.y + r + 2), SIZE - 1)
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var dx := x + 0.5 - s.x
				var dz := z + 0.5 - s.y
				var ang := atan2(dz, dx)
				var rr := r * (0.82 + 0.18 * sin(ang * 3.0 + s.x) + 0.1 * sin(ang * 7.0 + s.y))
				var d := sqrt(dx * dx + dz * dz) / rr
				if d >= 1.0:
					continue
				var idx := z * SIZE + x
				var h := lerpf(s.w, _hf[idx], pow(d, 3.0))
				if h > _hf[idx]:
					_hf[idx] = h
	# 火山口：环形山顶 + 岩浆湖
	var vr := 22.0
	var rim := _hf_at(volcano.x + vr, volcano.y)
	var lava_y := floorf(rim - 11.0)
	volcano.w = lava_y
	for z in range(int(volcano.y - vr - 4), int(volcano.y + vr + 5)):
		for x in range(int(volcano.x - vr - 4), int(volcano.x + vr + 5)):
			if x < 0 or z < 0 or x >= SIZE or z >= SIZE:
				continue
			var d := Vector2(x + 0.5 - volcano.x, z + 0.5 - volcano.y).length()
			var idx := z * SIZE + x
			if d < vr:
				var bowl := lerpf(lava_y, _hf[idx], smoothstep(vr * 0.62, vr, d))
				_hf[idx] = minf(_hf[idx], bowl)
				if d < vr * 0.7:
					_hf[idx] = lava_y + 0.01
					flags[idx] |= F_LAVA | F_NOPROP
	# 赤岩熔岩池
	var vcen: Vector2 = region_centers[R_VOLCANIC]
	for z in range(int(vcen.y - 230), int(vcen.y + 230)):
		if z < 0 or z >= SIZE:
			continue
		for x in range(int(vcen.x - 200), int(vcen.x + 230)):
			if x < 0 or x >= SIZE:
				continue
			var mi := (z >> 1) * MN + (x >> 1)
			if biome_a[mi] != R_VOLCANIC or biome_t[mi] > 0.3:
				continue
			var ln := n_lake.get_noise_2d(x * 1.3 + 400.0, z * 1.3)
			if ln < 0.42:
				continue
			var idx := z * SIZE + x
			var level := 18.0
			if _hf[idx] < level + 9.0:
				if ln > 0.47:
					_hf[idx] = minf(_hf[idx], level + 0.01)
					if _hf[idx] >= level - 0.5:
						_hf[idx] = level + 0.01
						flags[idx] |= F_LAVA | F_NOPROP
				else:
					_hf[idx] = minf(_hf[idx], level + 1.01)
	# 洞府山丘（在洞府后方隆起）
	var home := find_poi("home")
	var hp := Vector2(home["pos"].x, home["pos"].z)
	var back := -Vector2(home["facing"].x, home["facing"].z)
	var hill_c := hp + back * 40.0
	for z in range(int(hill_c.y - 100), int(hill_c.y + 100)):
		for x in range(int(hill_c.x - 100), int(hill_c.x + 100)):
			if x < 0 or z < 0 or x >= SIZE or z >= SIZE:
				continue
			var d := Vector2(x + 0.5, z + 0.5).distance_to(hill_c)
			_hf[z * SIZE + x] += 30.0 * exp(-(d * d) / (38.0 * 38.0))


## 压平 POI 平台
func _apply_pois() -> void:
	for p in pois:
		var half: Vector2 = p["half"]
		if half == Vector2.ZERO or not p.has("height"):
			continue
		var c := Vector2(p["pos"].x, p["pos"].z)
		var target := float(p["height"])
		var margin: float = p["margin"]
		var is_round: bool = p.get("round", false)
		var wh := _world_half(p)
		var ext := wh + Vector2(margin, margin)
		var ptype: String = p["type"]
		# 洞府石室：记录压平前的高度，供建筑还原山体
		if ptype == "home":
			var cave := _home_cave_world_rect(p)
			home_cave_rect = cave
			home_cave_heights.resize(cave.size.x * cave.size.y)
			for z in cave.size.y:
				for x in cave.size.x:
					home_cave_heights[z * cave.size.x + x] = clampi(int(floor(_hf[(cave.position.y + z) * SIZE + cave.position.x + x])), 1, 250)
		for z in range(int(c.y - ext.y) - 1, int(c.y + ext.y) + 2):
			if z < 0 or z >= SIZE:
				continue
			for x in range(int(c.x - ext.x) - 1, int(c.x + ext.x) + 2):
				if x < 0 or x >= SIZE:
					continue
				var q := Vector2(x + 0.5, z + 0.5) - c
				var d: float
				if is_round:
					d = q.length() - wh.x
				else:
					var dx := absf(q.x) - wh.x
					var dz := absf(q.y) - wh.y
					if dx > 0.0 and dz > 0.0:
						d = Vector2(dx, dz).length()
					else:
						d = maxf(dx, dz)
				if d > margin:
					continue
				# 洞府：石室部分不做边缘过渡（山体紧贴石室）
				if ptype == "home" and d > 0.0 and _local_z(p, Vector2(x + 0.5, z + 0.5)) > HOME_CAVE_Z0 - 0.5:
					continue
				var idx := z * SIZE + x
				if d <= 0.0:
					_hf[idx] = target + 0.01
					flags[idx] |= F_NOPROP
					if ptype == "sect" or ptype == "town" or ptype == "home":
						flags[idx] |= F_NOGRASS
					if ptype == "portal" and d < -3.0:
						flags[idx] |= F_PAVED
				else:
					var t := smoothstep(margin, 0.0, d)
					_hf[idx] = lerpf(_hf[idx], target + 0.01, t)
					if t > 0.6:
						flags[idx] |= F_NOPROP
		if ptype == "town":
			_paint_local_rects(p, TOWN_PAVED, F_PAVED | F_NOPROP)
		elif ptype == "sect":
			_paint_local_rects(p, SECT_PAVED, F_PAVED | F_NOPROP)
		elif ptype == "home":
			# 前院药田
			_paint_local_rects(p, [Rect2(-8, -15, 7, 8), Rect2(1, -15, 7, 8)], F_FIELD | F_NOPROP)


## POI 的世界轴向半宽（考虑 90° 旋转）
static func _world_half(p: Dictionary) -> Vector2:
	var half: Vector2 = p["half"]
	var f: Vector3 = p["facing"]
	if absf(f.x) > 0.5:
		return Vector2(half.y, half.x)
	return half


## 局部坐标（x 右, z 后；前方为 -z = facing）→ 世界 xz
static func local_to_world2(p: Dictionary, l: Vector2) -> Vector2:
	var f := Vector2(p["facing"].x, p["facing"].z)
	var back := -f
	var right := Vector2(back.y, -back.x)  # 与节点 basis.x 一致（rotation.y = yaw）
	return Vector2(p["pos"].x, p["pos"].z) + right * l.x + back * l.y


## 世界 xz → POI 局部 z（后方为正）
static func _local_z(p: Dictionary, w: Vector2) -> float:
	var f := Vector2(p["facing"].x, p["facing"].z)
	return (w - Vector2(p["pos"].x, p["pos"].z)).dot(-f)


func _paint_local_rects(p: Dictionary, rects: Array, bits: int) -> void:
	for r in rects:
		var rr: Rect2 = r
		var a := local_to_world2(p, rr.position)
		var b := local_to_world2(p, rr.end)
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		for z in range(int(round(lo.y)), int(round(hi.y))):
			for x in range(int(round(lo.x)), int(round(hi.x))):
				if x >= 0 and z >= 0 and x < SIZE and z < SIZE:
					flags[z * SIZE + x] |= bits


func _home_cave_world_rect(p: Dictionary) -> Rect2i:
	var a := local_to_world2(p, Vector2(-HOME_HALF.x, HOME_CAVE_Z0))
	var b := local_to_world2(p, Vector2(HOME_HALF.x, HOME_HALF.y))
	var lo := Vector2i(int(round(minf(a.x, b.x))), int(round(minf(a.y, b.y))))
	var hi := Vector2i(int(round(maxf(a.x, b.x))), int(round(maxf(a.y, b.y))))
	return Rect2i(lo, hi - lo)


## 道路：坊市 → 各宗山门、洞府
func _apply_roads() -> void:
	roads.clear()
	var town := find_poi("town")
	var tc := Vector2(town["pos"].x, town["pos"].z)
	var targets: Array[Vector2] = []
	for p in pois:
		if p["type"] == "sect":
			var f := Vector2(p["facing"].x, p["facing"].z)
			targets.append(Vector2(p["pos"].x, p["pos"].z) + f * (SECT_HALF.y + 6.0))
		elif p["type"] == "home":
			var f := Vector2(p["facing"].x, p["facing"].z)
			targets.append(Vector2(p["pos"].x, p["pos"].z) + f * (HOME_HALF.y + 3.0))
	var ri := 0
	for tgt in targets:
		var a := tc + (tgt - tc).normalized() * 20.0
		var line := PackedVector2Array()
		var n := maxi(int(a.distance_to(tgt) / 3.0), 2)
		var perp := (tgt - a).normalized().orthogonal()
		var amp := 10.0 + 6.0 * sin(float(ri) * 2.3 + seed_value % 7)
		for i in n + 1:
			var t := float(i) / n
			var off := sin(t * PI * (1.5 + (ri % 2))) * amp * sin(t * PI) + n_warp.get_noise_2d(t * 400.0, ri * 50.0) * 8.0 * sin(t * PI)
			line.append(a.lerp(tgt, t) + perp * off)
		roads.append(line)
		_carve_road(line)
		ri += 1


func _carve_road(line: PackedVector2Array) -> void:
	var n := line.size()
	var hs := PackedFloat32Array()
	hs.resize(n)
	for i in n:
		hs[i] = _hf_at(line[i].x, line[i].y)
	# 平滑纵断面
	var sm := PackedFloat32Array()
	sm.resize(n)
	for i in n:
		var s := 0.0
		var c := 0
		for k in range(i - 6, i + 7):
			if k >= 0 and k < n:
				s += hs[k]
				c += 1
		sm[i] = maxf(s / c, SEA_LEVEL + 1.01)
	var half_w := 1.9
	var shoulder := 3.6
	for i in n - 1:
		var a := line[i]
		var b := line[i + 1]
		var x0 := maxi(int(minf(a.x, b.x) - shoulder) - 1, 0)
		var x1 := mini(int(maxf(a.x, b.x) + shoulder) + 1, SIZE - 1)
		var z0 := maxi(int(minf(a.y, b.y) - shoulder) - 1, 0)
		var z1 := mini(int(maxf(a.y, b.y) + shoulder) + 1, SIZE - 1)
		var ab := b - a
		var l2 := maxf(ab.length_squared(), 0.001)
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var q := Vector2(x + 0.5, z + 0.5)
				var t := clampf((q - a).dot(ab) / l2, 0.0, 1.0)
				var d := q.distance_to(a + ab * t)
				if d > shoulder:
					continue
				var idx := z * SIZE + x
				if flags[idx] & (F_PAVED | F_LAVA | F_FIELD):
					continue
				var rh := lerpf(sm[i], sm[i + 1], t)
				if absf(_hf[idx] - rh) > 9.0:
					continue
				if d <= half_w:
					_hf[idx] = floorf(rh) + 0.01
					flags[idx] |= F_ROAD | F_NOPROP
				elif flags[idx] & F_ROAD == 0:
					_hf[idx] = lerpf(_hf[idx], floorf(rh) + 0.01, 0.5 * smoothstep(shoulder, half_w, d))
					flags[idx] |= F_NOPROP


func _finalize() -> void:
	hmap.resize(SIZE * SIZE)
	for i in SIZE * SIZE:
		hmap[i] = clampi(int(floor(_hf[i])), 1, MAX_H)


func _build_lod_heights() -> void:
	lod_heights.resize(LOD_N * LOD_N)
	for cz in LOD_N:
		for cx in LOD_N:
			lod_heights[cz * LOD_N + cx] = _lod_cell_height(cx, cz)


## LOD 格高度：格内 4 个采样的平均值，略微下沉以免盖住近景
func _lod_cell_height(cx: int, cz: int) -> int:
	var s := 0
	var c := 0
	for z in range(cz * LOD_CELL, cz * LOD_CELL + LOD_CELL, 2):
		var row := z * SIZE
		for x in range(cx * LOD_CELL, cx * LOD_CELL + LOD_CELL, 2):
			s += hmap[row + x]
			c += 1
	return int(round(float(s) / c)) - 1


# ================================================================ 查询

func _hf_at(x: float, z: float) -> float:
	var ix := clampi(int(x), 0, SIZE - 1)
	var iz := clampi(int(z), 0, SIZE - 1)
	return _hf[iz * SIZE + ix]


func _avg_hf(p: Vector2, r: float) -> float:
	var s := 0.0
	var c := 0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			s += _hf_at(p.x + dx * r * 0.5, p.y + dz * r * 0.5)
			c += 1
	return s / c


func _region_at(x: float, z: float) -> int:
	var i := clampi(int(x) >> 1, 0, MN - 1)
	var j := clampi(int(z) >> 1, 0, MN - 1)
	return biome_a[j * MN + i]


## 方块柱顶高度（整数米）。世界外返回 0。
func get_block_height(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= SIZE or z >= SIZE:
		return 0
	return hmap[z * SIZE + x]


## 地面视觉高度（所在方块柱顶）
func get_ground_y(x: float, z: float) -> float:
	return float(get_block_height(floori(x), floori(z)))


## 与碰撞一致的平滑高度（柱顶中心之间双线性插值）
func get_height(x: float, z: float) -> float:
	var fx := x - 0.5
	var fz := z - 0.5
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	var ax := clampi(ix, 0, SIZE - 1)
	var bx := clampi(ix + 1, 0, SIZE - 1)
	var az := clampi(iz, 0, SIZE - 1)
	var bz := clampi(iz + 1, 0, SIZE - 1)
	var h00 := float(hmap[az * SIZE + ax])
	var h10 := float(hmap[az * SIZE + bx])
	var h01 := float(hmap[bz * SIZE + ax])
	var h11 := float(hmap[bz * SIZE + bx])
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## 生物群系名：plains snow forest lake volcanic plateau ocean
func get_biome(x: float, z: float) -> String:
	return _biome_names[_region_at(x, z)]


## 该处是否为水面（柱顶低于海平面，且不是熔岩）
func is_water(x: float, z: float) -> bool:
	var ix := floori(x)
	var iz := floori(z)
	if ix < 0 or iz < 0 or ix >= SIZE or iz >= SIZE:
		return true
	return hmap[iz * SIZE + ix] < SEA_LEVEL


func is_lava(x: float, z: float) -> bool:
	var ix := floori(x)
	var iz := floori(z)
	if ix < 0 or iz < 0 or ix >= SIZE or iz >= SIZE:
		return false
	return flags[iz * SIZE + ix] & F_LAVA != 0


func get_flags(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= SIZE or z >= SIZE:
		return 0
	return flags[z * SIZE + x]


func find_poi(id: String) -> Dictionary:
	for p in pois:
		if p["id"] == id:
			return p
	return {}


## 地块坡度（与四邻最大高差）
func slope_at(x: int, z: int) -> int:
	var h := get_block_height(x, z)
	return maxi(maxi(absi(h - get_block_height(x - 1, z)), absi(h - get_block_height(x + 1, z))),
		maxi(absi(h - get_block_height(x, z - 1)), absi(h - get_block_height(x, z + 1))))


# ================================================================ 地表

static func _hash2(x: int, z: int) -> float:
	var h := (x * 374761393 + z * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


## 抖动后的区域（过渡带呈斑块状混合）
func _dither_region(x: int, z: int, patch: float) -> int:
	var mi := clampi(z >> 1, 0, MN - 1) * MN + clampi(x >> 1, 0, MN - 1)
	var a := biome_a[mi]
	var t := biome_t[mi]
	if t <= 0.001:
		return a
	var u := 0.45 * _hash2(x, z) + 0.55 * (patch * 0.5 + 0.5)
	return biome_b[mi] if u < t else a


## 地表类型。hw/he/hn/hs 为四邻高度。
func surface_at(x: int, z: int, h: int, hw: int, he: int, hn: int, hs: int, fl: int, patch: float) -> int:
	if fl & F_LAVA:
		return S_LAVA
	if fl & F_SCORCH:
		return S_SCORCH
	if fl & F_PAVED:
		return S_PAVED
	if fl & F_FIELD:
		return S_FIELD
	if fl & F_ROAD:
		return S_ROAD if h >= SEA_LEVEL else S_GRAVEL
	var r := _dither_region(x, z, patch)
	if h < SEA_LEVEL:
		match r:
			R_VOLCANIC:
				return S_BLACKSAND
			R_SNOW:
				return S_GRAVEL
			R_LAKE:
				return S_MUD if h < SEA_LEVEL - 3 and patch < 0.2 else S_SAND
		return S_SAND if h >= SEA_LEVEL - 4 else S_GRAVEL
	var slope := maxi(maxi(absi(h - hw), absi(h - he)), maxi(absi(h - hn), absi(h - hs)))
	if h <= SEA_LEVEL + 1 and (hw < SEA_LEVEL or he < SEA_LEVEL or hn < SEA_LEVEL or hs < SEA_LEVEL):
		match r:
			R_VOLCANIC:
				return S_BLACKSAND
			R_SNOW:
				return S_GRAVEL
			R_LAKE:
				return S_WETGRASS if patch > 0.3 else S_SAND
		return S_SAND
	match r:
		R_PLAINS:
			if slope >= 4:
				return S_STONE
			return S_GRASS
		R_SNOW:
			var snowline := 27.0 + 7.0 * patch
			if slope >= 5:
				return S_SNOWROCK
			if h >= snowline:
				return S_SNOW
			return S_ALPINE if slope < 3 else S_STONE
		R_FOREST:
			if slope >= 4:
				return S_STONE
			return S_FOREST
		R_LAKE:
			if slope >= 4:
				return S_STONE
			return S_MUD if patch < -0.38 else S_WETGRASS
		R_VOLCANIC:
			if slope >= 3:
				return S_REDROCK
			return S_REDROCK if patch > 0.5 else S_ASH
		R_PLATEAU:
			if slope >= 3:
				return S_LOESS
			return S_DRYGRASS if patch > 0.05 else S_LOESS
		R_OCEAN:
			return S_SAND
	return S_GRASS


## 顶面颜色（含斑块与逐柱扰动）
static func top_color(s: int, x: int, z: int, patch: float) -> Color:
	var c: Color = _surf_top[s]
	var hv := _hash2(x, z)
	match s:
		S_GRASS, S_FOREST, S_WETGRASS, S_ALPINE:
			if patch > 0.0:
				c = c.lerp(Color(0.62, 0.66, 0.30), patch * 0.35)
			else:
				c = c.lerp(Color(0.20, 0.42, 0.22), -patch * 0.3)
		S_DRYGRASS, S_LOESS:
			c = c.lerp(Color(0.78, 0.56, 0.30), maxf(patch, 0.0) * 0.3)
		S_SNOW:
			hv = 0.5 + (hv - 0.5) * 0.3
	var k := 0.94 + 0.12 * hv
	return Color(c.r * k, c.g * k, c.b * k, c.a)


# ================================================================ 网格

## 构建区块网格数组与碰撞高度（可在工作线程调用）。
## 返回 {"arrays": Array（Mesh.ARRAY_MAX）或 [], "collision": PackedFloat32Array(33×33)}
func build_chunk_arrays(cx: int, cz: int) -> Dictionary:
	var hm := hmap
	var fl := flags
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	var w := CHUNK + 2
	var lh := PackedInt32Array()
	lh.resize(w * w)
	for lz in w:
		var wz := z0 + lz - 1
		for lx in w:
			var wx := x0 + lx - 1
			if wx < 0 or wz < 0 or wx >= SIZE or wz >= SIZE:
				lh[lz * w + lx] = 0
			else:
				lh[lz * w + lx] = hm[wz * SIZE + wx]
	var surf := PackedByteArray()
	surf.resize(CHUNK * CHUNK)
	var topc := PackedColorArray()
	topc.resize(CHUNK * CHUNK)
	for lz in CHUNK:
		for lx in CHUNK:
			var x := x0 + lx
			var z := z0 + lz
			var c := (lz + 1) * w + lx + 1
			var patch := n_patch.get_noise_2d(x, z)
			var s := surface_at(x, z, lh[c], lh[c - 1], lh[c + 1], lh[c - w], lh[c + w], fl[z * SIZE + x], patch)
			# 熔岩边缘为黑曜石
			if s == S_ASH or s == S_REDROCK:
				if fl[z * SIZE + mini(x + 1, SIZE - 1)] & F_LAVA or fl[z * SIZE + maxi(x - 1, 0)] & F_LAVA \
						or fl[mini(z + 1, SIZE - 1) * SIZE + x] & F_LAVA or fl[maxi(z - 1, 0) * SIZE + x] & F_LAVA:
					s = S_OBSIDIAN
			surf[lz * CHUNK + lx] = s
			topc[lz * CHUNK + lx] = top_color(s, x, z, patch)
	var arrays := mesh_columns(CHUNK, CHUNK, lh, 1.0, Vector3(x0, 0, z0), surf, topc, x0, z0)
	var col := PackedFloat32Array()
	col.resize(33 * 33)
	for j in 33:
		var wz := mini(z0 + j, SIZE - 1)
		for i in 33:
			col[j * 33 + i] = float(hm[wz * SIZE + mini(x0 + i, SIZE - 1)])
	return {"arrays": arrays, "collision": col}


## 远景 LOD 树冠：返回 0 无、1 林木、2 雪松、3 平原树丛、4 垂柳（与 PropScatter 的密度大致一致）
func _lod_canopy(cx: int, cz: int) -> int:
	var x := cx * LOD_CELL + LOD_CELL / 2
	var z := cz * LOD_CELL + LOD_CELL / 2
	var idx := z * SIZE + x
	if flags[idx] & (F_NOPROP | F_LAVA | F_ROAD | F_PAVED | F_FIELD):
		return 0
	var h := int(hmap[idx])
	if h < SEA_LEVEL or slope_at(x, z) >= 3:
		return 0
	var r := _region_at(x, z)
	var hv := _hash2(cx * 7 + 3, cz * 13 + 5)
	match r:
		R_FOREST:
			return 1 if hv < 0.55 else 0
		R_SNOW:
			return 2 if hv < 0.3 and h < 58 else 0
		R_PLAINS:
			var grove := n_patch.get_noise_2d(x * 0.5 + 900.0, z * 0.5)
			return 3 if grove > 0.3 and hv < 0.45 else 0
		R_LAKE:
			return 4 if hv < 0.15 else 0
	return 0


## 远景 LOD 分块（每块 LOD_TILE×LOD_TILE 个 LOD_CELL 米格子 = 256 米），林区叠加方块树冠
func build_lod_arrays(tx: int, tz: int) -> Array:
	var n := LOD_TILE
	var w := n + 2
	var lh := PackedInt32Array()
	lh.resize(w * w)
	var canopy := PackedByteArray()
	canopy.resize(w * w)
	for lz in w:
		var cz := tz * n + lz - 1
		for lx in w:
			var cx := tx * n + lx - 1
			if cx < 0 or cz < 0 or cx >= LOD_N or cz >= LOD_N:
				lh[lz * w + lx] = 0
			else:
				var cn := _lod_canopy(cx, cz)
				canopy[lz * w + lx] = cn
				var extra := 0
				if cn != 0:
					extra = 6 + int(_hash2(cx, cz) * 4.0) if cn != 2 else 7 + int(_hash2(cx, cz) * 5.0)
				lh[lz * w + lx] = lod_heights[cz * LOD_N + cx] + extra
	var surf := PackedByteArray()
	surf.resize(n * n)
	var topc := PackedColorArray()
	topc.resize(n * n)
	for lz in n:
		for lx in n:
			var x := (tx * n + lx) * LOD_CELL + LOD_CELL / 2
			var z := (tz * n + lz) * LOD_CELL + LOD_CELL / 2
			var patch := n_patch.get_noise_2d(x, z)
			# 使用格中心所在 1 米柱的真实地表（与近景一致）
			var fl := flags[z * SIZE + x]
			var i1 := z * SIZE + x
			var s := surface_at(x, z, hmap[i1], hmap[i1 - 1], hmap[i1 + 1], hmap[i1 - SIZE], hmap[i1 + SIZE], fl, patch)
			var cn := canopy[(lz + 1) * w + lx + 1]
			var tc := top_color(s, x, z, patch)
			if cn != 0:
				var hv := _hash2(x, z)
				s = S_CANOPY
				match cn:
					1:
						tc = Color(0.20, 0.42, 0.20).lerp(Color(0.28, 0.50, 0.22), hv)
						if hv > 0.93:
							tc = Color(0.80, 0.32, 0.16)
					2:
						tc = Color(0.14, 0.32, 0.24) if hv < 0.55 else Color(0.90, 0.93, 0.98)
					3:
						tc = Color(0.30, 0.55, 0.24) if hv < 0.8 else Color(0.95, 0.68, 0.78)
					4:
						tc = Color(0.46, 0.66, 0.30)
			surf[lz * n + lx] = s
			topc[lz * n + lx] = tc
	return mesh_columns(n, n, lh, float(LOD_CELL), Vector3(tx * n * LOD_CELL, 0, tz * n * LOD_CELL), surf, topc, tx * n, tz * n)


static func _ao3(s1: bool, s2: bool, c: bool) -> int:
	if s1 and s2:
		return 0
	return 3 - (int(s1) + int(s2) + int(c))


## 方块柱网格：顶面（逐顶点 AO）+ 侧面（按表土/岩层分段合并，底部接地处压暗）。
## lh 带 1 格边框，尺寸 (nx+2)×(nz+2)。
static func mesh_columns(nx: int, nz: int, lh: PackedInt32Array, cell: float, origin: Vector3,
		surf: PackedByteArray, topc: PackedColorArray, hx0: int, hz0: int) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var w := nx + 2
	var ao := _ao
	var s_side := _surf_side
	var s_sub := _surf_sub
	var s_a := _surf_a
	var s_b := _surf_b
	var s_depth := _surf_depth
	var up := Vector3.UP
	var nxp := Vector3(1, 0, 0)
	var nxn := Vector3(-1, 0, 0)
	var nzp := Vector3(0, 0, 1)
	var nzn := Vector3(0, 0, -1)
	for lz in nz:
		for lx in nx:
			var c := (lz + 1) * w + lx + 1
			var h := lh[c]
			var s := surf[lz * nx + lx]
			var tc := topc[lz * nx + lx]
			var fy := float(h)
			var X := origin.x + lx * cell
			var Z := origin.z + lz * cell
			var X1 := X + cell
			var Z1 := Z + cell
			var hw := lh[c - 1]
			var he := lh[c + 1]
			var hn := lh[c - w]
			var hs := lh[c + w]
			# 顶面
			var ow := hw > h
			var oe := he > h
			var on := hn > h
			var os := hs > h
			var a00 := _ao3(ow, on, lh[c - w - 1] > h)
			var a10 := _ao3(oe, on, lh[c - w + 1] > h)
			var a11 := _ao3(oe, os, lh[c + w + 1] > h)
			var a01 := _ao3(ow, os, lh[c + w - 1] > h)
			var b := verts.size()
			verts.append(Vector3(X, fy, Z))
			verts.append(Vector3(X1, fy, Z))
			verts.append(Vector3(X1, fy, Z1))
			verts.append(Vector3(X, fy, Z1))
			normals.append(up)
			normals.append(up)
			normals.append(up)
			normals.append(up)
			colors.append(_shade(tc, ao[a00]))
			colors.append(_shade(tc, ao[a10]))
			colors.append(_shade(tc, ao[a11]))
			colors.append(_shade(tc, ao[a01]))
			if a00 + a11 >= a10 + a01:
				indices.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
			else:
				indices.append_array([b + 1, b + 2, b + 3, b + 1, b + 3, b])
			# 侧面
			if hw < h or he < h or hn < h or hs < h:
				var hash_c := _hash2(hx0 + lx, hz0 + lz)
				var off := int(hash_c * 2.99)
				for dir in 4:
					var hn2: int
					match dir:
						0:
							hn2 = he
						1:
							hn2 = hw
						2:
							hn2 = hs
						_:
							hn2 = hn
					if hn2 >= h:
						continue
					var nrm: Vector3 = [nxp, nxn, nzp, nzn][dir]
					var y := h
					var seg := 0
					while y > hn2:
						var yb: int
						var col: Color
						if seg == 0:
							yb = y - 1
							col = s_side[s]
						elif seg == 1:
							yb = maxi(y - s_depth[s], hn2)
							col = s_sub[s]
						else:
							var band := floori(float(y - 1 + off) / 3.0)
							yb = band * 3 - off
							col = s_a[s] if (band & 1) == 0 else s_b[s]
							var k := 0.93 + 0.14 * _hash2(band, hx0 + lx + (hz0 + lz) * 7)
							col = Color(col.r * k, col.g * k, col.b * k, col.a)
						yb = maxi(yb, hn2)
						seg += 1
						if yb >= y:
							continue
						var fb := float(yb)
						var ft := float(y)
						var bot := 0.62 if yb == hn2 else 1.0
						var cb := _shade(col, bot)
						var q := verts.size()
						match dir:
							0:
								verts.append(Vector3(X1, fb, Z))
								verts.append(Vector3(X1, fb, Z1))
								verts.append(Vector3(X1, ft, Z1))
								verts.append(Vector3(X1, ft, Z))
								colors.append(cb)
								colors.append(cb)
								colors.append(col)
								colors.append(col)
							1:
								verts.append(Vector3(X, fb, Z))
								verts.append(Vector3(X, ft, Z))
								verts.append(Vector3(X, ft, Z1))
								verts.append(Vector3(X, fb, Z1))
								colors.append(cb)
								colors.append(col)
								colors.append(col)
								colors.append(cb)
							2:
								verts.append(Vector3(X, fb, Z1))
								verts.append(Vector3(X, ft, Z1))
								verts.append(Vector3(X1, ft, Z1))
								verts.append(Vector3(X1, fb, Z1))
								colors.append(cb)
								colors.append(col)
								colors.append(col)
								colors.append(cb)
							_:
								verts.append(Vector3(X, fb, Z))
								verts.append(Vector3(X1, fb, Z))
								verts.append(Vector3(X1, ft, Z))
								verts.append(Vector3(X, ft, Z))
								colors.append(cb)
								colors.append(cb)
								colors.append(col)
								colors.append(col)
						normals.append(nrm)
						normals.append(nrm)
						normals.append(nrm)
						normals.append(nrm)
						indices.append_array([q, q + 1, q + 2, q, q + 2, q + 3])
						y = yb
	if verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


static func _shade(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


# ================================================================ 弹坑

## 炸出弹坑：降低碗状区域高度，通知流式加载器重建网格与碰撞、喷出碎块。本会话内保留。
## 返回受影响的区块坐标。只能在主线程调用。
func carve_crater(pos: Vector3, radius: float) -> Array[Vector2i]:
	var res := carve_crater_data(pos, radius)
	var chunks: Array[Vector2i] = res["chunks"]
	if not chunks.is_empty():
		changed.emit(chunks, res["samples"], pos, radius)
	return chunks


## 在 pos 处炸出碗状弹坑（只改数据，返回受影响区块与被移除的地表样本）。
## 返回 {"chunks": Array[Vector2i], "samples": Array[[Vector3, Color]]}
func carve_crater_data(pos: Vector3, radius: float) -> Dictionary:
	var r := clampf(radius, 1.0, 24.0)
	var depth := r * 0.55
	var affected := {}
	var samples: Array = []
	var x0 := maxi(floori(pos.x - r), 0)
	var x1 := mini(ceili(pos.x + r), SIZE - 1)
	var z0 := maxi(floori(pos.z - r), 0)
	var z1 := mini(ceili(pos.z + r), SIZE - 1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x + 0.5 - pos.x, z + 0.5 - pos.z).length()
			var rr := r * (0.85 + 0.3 * _hash2(x * 3 + 1, z * 5 + 7))
			if d > rr:
				continue
			var idx := z * SIZE + x
			var h := int(hmap[idx])
			var k := 1.0 - (d / rr) * (d / rr)
			var target := int(floor(minf(pos.y, float(h)) - depth * k + 0.5))
			target = maxi(target, 1)
			if target >= h:
				continue
			var fl := int(flags[idx])
			if fl & F_LAVA:
				continue
			var patch := n_patch.get_noise_2d(x, z)
			var s := surface_at(x, z, h, h, h, h, h, fl, patch)
			if samples.size() < 64 and _hash2(x, z) < 0.5:
				samples.append([Vector3(x + 0.5, h - 0.5, z + 0.5), top_color(s, x, z, patch)])
			hmap[idx] = target
			flags[idx] = (fl | F_SCORCH) if d < rr * 0.75 else fl
			affected[Vector2i(x / CHUNK, z / CHUNK)] = true
			# 边界柱影响相邻区块的侧面与 AO
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var ax := x + dx
					var az := z + dz
					if ax >= 0 and az >= 0 and ax < SIZE and az < SIZE:
						affected[Vector2i(ax / CHUNK, az / CHUNK)] = true
	if not affected.is_empty():
		craters.append({"pos": pos, "radius": r})
		_map_cache.clear()
		# LOD 高度同步
		for cz in range(z0 / LOD_CELL, z1 / LOD_CELL + 1):
			for cx in range(x0 / LOD_CELL, x1 / LOD_CELL + 1):
				lod_heights[cz * LOD_N + cx] = _lod_cell_height(cx, cz)
	var chunks: Array[Vector2i] = []
	for k in affected:
		chunks.append(k)
	return {"chunks": chunks, "samples": samples}


# ================================================================ 地图

## 俯视彩色地图（px×px），含水深、山体晕渲、道路与熔岩。可供地图 UI 使用。
## 按行多线程生成并缓存（弹坑后失效）。512 像素约 0.2~0.4 秒。
func render_map_image(px: int) -> Image:
	px = clampi(px, 16, SIZE)
	if _map_cache.has(px):
		return (_map_cache[px] as Image).duplicate()
	var rows: Array = []
	rows.resize(px)
	var gid := WorkerThreadPool.add_group_task(func(j: int) -> void:
		rows[j] = _map_row(j, px), px, -1, true, "terrain_map")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	var data := PackedByteArray()
	for j in px:
		data.append_array(rows[j])
	var img := Image.create_from_data(px, px, false, Image.FORMAT_RGB8, data)
	_map_cache[px] = img
	return img.duplicate()


func _map_row(j: int, px: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(px * 3)
	var step := float(SIZE) / px
	var hm := hmap
	var fla := flags
	var z := clampi(int((j + 0.5) * step), 2, SIZE - 3)
	for i in px:
		var x := clampi(int((i + 0.5) * step), 2, SIZE - 3)
		var idx := z * SIZE + x
		var h := int(hm[idx])
		var fl := int(fla[idx])
		var c: Color
		if h < SEA_LEVEL and fl & F_LAVA == 0:
			var depth := clampf(float(SEA_LEVEL - h) / 9.0, 0.0, 1.0)
			c = Color(0.36, 0.62, 0.72).lerp(Color(0.12, 0.26, 0.45), depth)
		elif fl & F_LAVA:
			c = Color(1.0, 0.45, 0.1)
		else:
			var patch := n_patch.get_noise_2d(x, z)
			var s := surface_at(x, z, h, int(hm[idx - 1]), int(hm[idx + 1]), int(hm[idx - SIZE]), int(hm[idx + SIZE]), fl, patch)
			c = top_color(s, x, z, patch)
			# 晕渲：光从西北
			var sx := float(int(hm[idx + 2]) - int(hm[idx - 2]))
			var sz := float(int(hm[idx + SIZE * 2]) - int(hm[idx - SIZE * 2]))
			var shade := clampf(1.0 - (sx + sz) * 0.05, 0.6, 1.3)
			var hk := clampf(0.9 + float(h - SEA_LEVEL) * 0.004, 0.9, 1.15) * shade
			c = Color(c.r * hk, c.g * hk, c.b * hk)
		out[i * 3] = clampi(int(c.r * 255.0), 0, 255)
		out[i * 3 + 1] = clampi(int(c.g * 255.0), 0, 255)
		out[i * 3 + 2] = clampi(int(c.b * 255.0), 0, 255)
	return out
