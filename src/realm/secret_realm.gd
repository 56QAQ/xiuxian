extends Node3D
## 秘境（搜打撤）：程序生成的主题区域，散布容器、妖兽与寻宝修士；限时崩塌；撤离阵撤离。
## 入口参数：GS.realm_request = {realm_id, seed, return_pos?}

## 主题：top 地表三色（sRGB）、surf 对应的地表类型（TerrainGen.S_*，决定方块纹理）、edge 边缘峭壁地表、
## side/deep 碎屑色、sun 太阳色、sun_pitch 太阳仰角、amp 起伏、props 装饰物、water/lava 水位/岩浆位、
## pal 大气调色板（字段见 Atmosphere.DAY）、fx 环境粒子权重（AmbientFX）、snow 全局积雪
const THEMES := {
	"forest": {"top": [Color(0.33, 0.58, 0.27), Color(0.40, 0.63, 0.30), Color(0.28, 0.50, 0.25)], "side": Color(0.45, 0.33, 0.22), "deep": Color(0.4, 0.38, 0.36),
		"surf": [TerrainGen.S_GRASS, TerrainGen.S_WETGRASS, TerrainGen.S_FOREST], "edge": TerrainGen.S_STONE, "shore": TerrainGen.S_SAND,
		"sun": Color(1.0, 0.93, 0.78), "sun_pitch": -48.0, "amp": 7.0, "props": ["tree", "tree", "bush", "rock"], "water": 2.5,
		"pal": {"zenith": Color(0.32, 0.56, 0.74), "horizon": Color(0.74, 0.86, 0.80), "haze": Color(0.80, 0.90, 0.82), "glow": Color(1.0, 0.9, 0.66),
			"ambient": Color(0.46, 0.58, 0.52), "amb_e": 0.62, "fog": Color(0.62, 0.78, 0.66), "fog_d": 0.8, "fog_end": 210.0,
			"vol": Color(0.85, 0.95, 0.85), "vol_d": 0.012, "ink": Color(0.30, 0.46, 0.40), "mist": Color(0.74, 0.86, 0.78),
			"cloud_l": Color(1.0, 1.0, 0.95), "cloud_s": Color(0.66, 0.76, 0.72), "sun": Color(1.0, 0.93, 0.78), "sun_e": 1.5, "exposure": 1.0, "cloud": 0.4},
		"fx": {"motes": 0.9, "petals": 0.35, "fireflies": 0.3, "leaves": 0.3}, "snow": 0.0},
	"ruins": {"top": [Color(0.58, 0.58, 0.54), Color(0.40, 0.50, 0.34), Color(0.56, 0.56, 0.52)], "side": Color(0.5, 0.48, 0.45), "deep": Color(0.38, 0.37, 0.36),
		"surf": [TerrainGen.S_PAVED, TerrainGen.S_GRASS, TerrainGen.S_GRAVEL], "edge": TerrainGen.S_STONE, "shore": TerrainGen.S_GRAVEL,
		"sun": Color(0.95, 0.9, 0.85), "sun_pitch": -40.0, "amp": 4.0, "props": ["pillar", "wall", "rock", "tree"], "water": -10.0,
		"pal": {"zenith": Color(0.40, 0.44, 0.56), "horizon": Color(0.70, 0.70, 0.76), "haze": Color(0.74, 0.74, 0.80), "glow": Color(0.95, 0.85, 0.75),
			"ambient": Color(0.50, 0.52, 0.60), "amb_e": 0.64, "fog": Color(0.62, 0.62, 0.70), "fog_d": 0.82, "fog_end": 190.0,
			"vol": Color(0.8, 0.8, 0.9), "vol_d": 0.012, "ink": Color(0.34, 0.36, 0.46), "mist": Color(0.70, 0.70, 0.78),
			"cloud_l": Color(0.9, 0.9, 0.95), "cloud_s": Color(0.56, 0.58, 0.68), "sun": Color(0.95, 0.9, 0.85), "sun_e": 1.2, "exposure": 1.05, "cloud": 0.62},
		"fx": {"motes": 1.0, "dust": 0.35}, "snow": 0.0},
	"volcano": {"top": [Color(0.24, 0.21, 0.21), Color(0.52, 0.26, 0.18), Color(0.16, 0.13, 0.16)], "side": Color(0.32, 0.22, 0.18), "deep": Color(0.2, 0.16, 0.15),
		"surf": [TerrainGen.S_ASH, TerrainGen.S_REDROCK, TerrainGen.S_OBSIDIAN], "edge": TerrainGen.S_REDROCK, "shore": TerrainGen.S_BLACKSAND,
		"sun": Color(1.0, 0.66, 0.45), "sun_pitch": -35.0, "amp": 9.0, "props": ["crystal", "rock", "rock", "deadtree"], "lava": 3.0, "water": -10.0,
		"pal": {"zenith": Color(0.22, 0.10, 0.10), "horizon": Color(0.62, 0.30, 0.20), "haze": Color(0.70, 0.38, 0.26), "glow": Color(1.0, 0.5, 0.25),
			"ambient": Color(0.46, 0.30, 0.28), "amb_e": 0.55, "fog": Color(0.45, 0.24, 0.18), "fog_d": 0.86, "fog_end": 180.0,
			"vol": Color(1.0, 0.55, 0.35), "vol_d": 0.014, "ink": Color(0.16, 0.08, 0.08), "mist": Color(0.55, 0.28, 0.20),
			"cloud_l": Color(0.75, 0.40, 0.30), "cloud_s": Color(0.25, 0.12, 0.12), "sun": Color(1.0, 0.66, 0.45), "sun_e": 1.2, "exposure": 1.05, "cloud": 0.6},
		"fx": {"embers": 1.0, "ash": 1.0, "motes": 0.2}, "snow": 0.0},
	"ice": {"top": [Color(0.93, 0.95, 1.0), Color(0.86, 0.90, 0.97), Color(0.72, 0.84, 0.95)], "side": Color(0.6, 0.75, 0.9), "deep": Color(0.5, 0.6, 0.75),
		"surf": [TerrainGen.S_SNOW, TerrainGen.S_SNOW, TerrainGen.S_ICE], "edge": TerrainGen.S_SNOWROCK, "shore": TerrainGen.S_ICE,
		"sun": Color(0.92, 0.96, 1.0), "sun_pitch": -38.0, "amp": 8.0, "props": ["icespike", "pine", "rock"], "water": 2.0,
		"pal": {"zenith": Color(0.46, 0.62, 0.82), "horizon": Color(0.80, 0.88, 0.96), "haze": Color(0.88, 0.93, 0.98), "glow": Color(0.95, 0.95, 1.0),
			"ambient": Color(0.62, 0.72, 0.86), "amb_e": 0.7, "fog": Color(0.80, 0.87, 0.95), "fog_d": 0.84, "fog_end": 190.0,
			"vol": Color(0.9, 0.95, 1.0), "vol_d": 0.012, "ink": Color(0.50, 0.60, 0.74), "mist": Color(0.84, 0.90, 0.97),
			"cloud_l": Color(1.0, 1.0, 1.0), "cloud_s": Color(0.72, 0.80, 0.90), "sun": Color(0.92, 0.96, 1.0), "sun_e": 1.35, "exposure": 0.92, "cloud": 0.55},
		"fx": {"snow": 0.8, "motes": 0.5}, "snow": 0.7},
	"water": {"top": [Color(0.38, 0.62, 0.38), Color(0.84, 0.78, 0.58), Color(0.34, 0.56, 0.35)], "side": Color(0.6, 0.55, 0.45), "deep": Color(0.45, 0.45, 0.42),
		"surf": [TerrainGen.S_WETGRASS, TerrainGen.S_SAND, TerrainGen.S_GRASS], "edge": TerrainGen.S_STONE, "shore": TerrainGen.S_SAND,
		"sun": Color(1.0, 0.95, 0.86), "sun_pitch": -45.0, "amp": 6.0, "props": ["tree", "rock", "bush", "willow"], "water": 5.5,
		"pal": {"zenith": Color(0.30, 0.52, 0.78), "horizon": Color(0.72, 0.84, 0.90), "haze": Color(0.80, 0.90, 0.94), "glow": Color(1.0, 0.92, 0.78),
			"ambient": Color(0.48, 0.62, 0.70), "amb_e": 0.62, "fog": Color(0.66, 0.80, 0.86), "fog_d": 0.8, "fog_end": 220.0,
			"vol": Color(0.85, 0.95, 1.0), "vol_d": 0.012, "ink": Color(0.34, 0.50, 0.58), "mist": Color(0.78, 0.88, 0.92),
			"cloud_l": Color(1.0, 1.0, 0.98), "cloud_s": Color(0.66, 0.76, 0.84), "sun": Color(1.0, 0.95, 0.86), "sun_e": 1.5, "exposure": 0.98, "cloud": 0.45},
		"fx": {"motes": 0.8, "fireflies": 0.45, "petals": 0.3}, "snow": 0.0},
	"battlefield": {"top": [Color(0.42, 0.35, 0.28), Color(0.36, 0.31, 0.27), Color(0.47, 0.40, 0.31)], "side": Color(0.35, 0.28, 0.22), "deep": Color(0.28, 0.24, 0.2),
		"surf": [TerrainGen.S_SCORCH, TerrainGen.S_MUD, TerrainGen.S_GRAVEL], "edge": TerrainGen.S_REDROCK, "shore": TerrainGen.S_MUD,
		"sun": Color(1.0, 0.66, 0.40), "sun_pitch": -22.0, "amp": 5.0, "props": ["deadtree", "rock", "wall", "pillar"], "water": -10.0,
		"pal": {"zenith": Color(0.34, 0.30, 0.36), "horizon": Color(0.86, 0.60, 0.42), "haze": Color(0.88, 0.66, 0.48), "glow": Color(1.0, 0.6, 0.3),
			"ambient": Color(0.52, 0.44, 0.42), "amb_e": 0.56, "fog": Color(0.66, 0.50, 0.40), "fog_d": 0.86, "fog_end": 230.0,
			"vol": Color(1.0, 0.8, 0.6), "vol_d": 0.012, "ink": Color(0.26, 0.20, 0.20), "mist": Color(0.74, 0.56, 0.44),
			"cloud_l": Color(1.0, 0.72, 0.5), "cloud_s": Color(0.40, 0.30, 0.32), "sun": Color(1.0, 0.66, 0.40), "sun_e": 1.3, "exposure": 1.0, "cloud": 0.5},
		"fx": {"ash": 0.6, "embers": 0.3, "dust": 0.5, "motes": 0.3}, "snow": 0.0},
}

var def: Dictionary = {}
var theme: Dictionary = {}
var rng := RandomNumberGenerator.new()
var size: int = 140
var terrain: HeightfieldTerrain
var session: GameSession
var extracts: Array[ExtractionPoint] = []
var time_left: float = 600.0
var elapsed: float = 0.0
var ended: bool = false
var spawn_pos: Vector3
var _warned: Dictionary = {}
var _half_open: bool = false
## 测试模式下不切换场景
var test_mode: bool = false


func _ready() -> void:
	if not GS.active:
		GS.new_game({"name": "寻宝人", "roots": {"wood": 50, "metal": 50}, "background": "rogue", "seed": 3})
	var req := GS.realm_request
	var rid := str(req.get("realm_id", "herb_valley"))
	if not DB.secret_realms.has(rid):
		rid = DB.secret_realms.keys()[0]
	def = DB.secret_realms[rid]
	rng.seed = int(req.get("seed", randi()))
	theme = THEMES.get(str(def.get("theme", "forest")), THEMES["forest"])
	size = clampi(int(def.get("size", 140)), 80, 220)
	time_left = float(def.get("time_limit", 600))
	GS.in_realm = true
	GS.location = "realm"
	_build_env()
	_build_terrain()
	_place_props()
	_place_containers()
	_place_extracts()
	session = GameSession.new()
	session.name = "Session"
	add_child(session)
	session.start(self, spawn_pos)
	session.player_died.connect(_on_player_died)
	_spawn_enemies()
	_spawn_boss()
	_spawn_rivals()
	_inject_mission_items()
	Events.actor_died.connect(_on_actor_died)
	Events.inventory_changed.connect(_convert_stones)
	Events.notify.emit("踏入秘境「%s」" % def.get("name", ""), "realm")
	Events.notify.emit("寻找宝物，在秘境崩塌前前往撤离阵（绿色光柱）", "info")
	session.set_music("music_realm")


func _exit_tree() -> void:
	GS.in_realm = false
	Events.hud_objective.emit("")
	BlockTex.reset_env()


# ================================================================ 环境

func _build_env() -> void:
	var env := WorldEnvironment.new()
	var e := Atmosphere.make_environment()
	var pal: Dictionary = theme["pal"]
	# 秘境较小：天空远山低一些，雾在边缘峭壁外收拢
	var sky_mat := e.sky.sky_material as ShaderMaterial
	sky_mat.set_shader_parameter("mountain_scale", 0.8)
	sky_mat.set_shader_parameter("cloud_time", rng.randf() * 500.0)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	Atmosphere.setup_sun(sun, 90.0)
	sun.rotation_degrees = Vector3(float(theme.get("sun_pitch", -45.0)), rng.randf_range(0, 360), 0)
	add_child(sun)
	Atmosphere.apply(e, sky_mat, sun, pal)
	# 方块材质环境：关闭大地图的海拔积雪，水位、全局积雪按主题
	var water := float(theme.get("water", -10.0))
	BlockTex.set_env({"snow_params": Vector4(999.0, 1000.0, 360.0, 250.0), "snow_global": float(theme.get("snow", 0.0)),
		"water_level": water + 0.6 if water > 0.0 else -100.0, "night_glow": 0.0})
	# 环境粒子（灵气光点、萤火、雪、余烬……）
	var fx := AmbientFX.new()
	add_child(fx)
	fx.setup_static(theme.get("fx", {"motes": 0.8}))


func _build_terrain() -> void:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = 0.018
	n.fractal_octaves = 4
	var n2 := FastNoiseLite.new()
	n2.seed = rng.randi()
	n2.frequency = 0.08
	var amp := float(theme.get("amp", 6.0))
	var h := PackedFloat32Array()
	var tops := PackedColorArray()
	h.resize(size * size)
	tops.resize(size * size)
	var palette: Array = theme["top"]
	var surf_t: Array = theme["surf"]
	var surf := PackedByteArray()
	surf.resize(size * size)
	var water := float(theme.get("water", -10.0))
	var lava := float(theme.get("lava", -10.0))
	for z in size:
		for x in size:
			var edge := minf(minf(x, z), minf(size - 1 - x, size - 1 - z))
			var e := clampf(1.0 - edge / 12.0, 0.0, 1.0)
			var v := 6.0 + n.get_noise_2d(x, z) * amp + n2.get_noise_2d(x, z) * 1.2 + e * e * 22.0
			var hv := maxf(round(v), 1.0)
			h[x + z * size] = hv
			var cn := n2.get_noise_2d(x * 3.1, z * 3.1)
			var col: Color = palette[0]
			var st: int = surf_t[0]
			if cn > 0.25:
				col = palette[1]
				st = surf_t[1]
			elif cn < -0.3:
				col = palette[2]
				st = surf_t[2]
			col = col.lightened(cn * 0.05)
			# 方块级明暗抖动，避免大面积纯色
			var jitter := (float((x * 73856093) ^ (z * 19349663)) / 2147483647.0)
			col = col.lightened(fposmod(jitter * 13.0, 1.0) * 0.06 - 0.03)
			if hv <= water:
				st = int(theme.get("shore", TerrainGen.S_SAND))
				col = (TerrainGen.SURF[st][0] as Color).lerp(col, 0.25)
			if hv <= lava:
				col = VoxelGrid.glow(Color(1.0, 0.45, 0.1), 0.9)
				st = TerrainGen.S_LAVA
			if e > 0.5:
				st = int(theme.get("edge", TerrainGen.S_STONE))
				col = (TerrainGen.SURF[st][0] as Color).lerp(col, 0.3)
			tops[x + z * size] = col
			surf[x + z * size] = st
	terrain = HeightfieldTerrain.new()
	terrain.name = "Terrain"
	terrain.side_color = theme["side"]
	terrain.deep_color = theme["deep"]
	add_child(terrain)
	terrain.setup(size, size, h, tops, surf)
	# 水面（与大地图同一水面着色器，水深取自地形高度图）
	if water > 0.0:
		var wm := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(size, size)
		wm.mesh = pm
		var mat := ShaderMaterial.new()
		mat.shader = load("res://assets/shaders/water.gdshader")
		mat.set_shader_parameter("use_height_tex", true)
		mat.set_shader_parameter("height_tex", ImageTexture.create_from_image(terrain.height_image()))
		mat.set_shader_parameter("height_rect", Vector4(0, 0, size, size))
		mat.set_shader_parameter("water_level", water + 0.6)
		mat.set_shader_parameter("absorption", 0.5)
		if str(def.get("theme", "")) == "ice":
			mat.set_shader_parameter("shallow_color", Color(0.62, 0.84, 0.92))
			mat.set_shader_parameter("deep_color", Color(0.10, 0.26, 0.40))
		wm.material_override = mat
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wm.position = Vector3(size * 0.5, water + 0.6, size * 0.5)
		add_child(wm)
	# 边界：看不见的墙
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	for i in 4:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(size + 4, 120, 2) if i < 2 else Vector3(2, 120, size + 4)
		cs.shape = bs
		cs.position = [Vector3(size * 0.5, 60, -1), Vector3(size * 0.5, 60, size + 1), Vector3(-1, 60, size * 0.5), Vector3(size + 1, 60, size * 0.5)][i]
		wall.add_child(cs)
	add_child(wall)
	spawn_pos = _ground(Vector3(size * 0.5 + rng.randf_range(-15, 15), 0, 18))


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.z) + 0.05, p.z)


func _random_point(margin: float = 16.0, avoid: Array[Vector3] = [], min_dist: float = 5.0) -> Vector3:
	for i in 40:
		var p := Vector3(rng.randf_range(margin, size - margin), 0, rng.randf_range(margin, size - margin))
		var ok := true
		for a in avoid:
			if Vector2(a.x - p.x, a.z - p.z).length() < min_dist:
				ok = false
				break
		if ok:
			return _ground(p)
	return _ground(Vector3(size * 0.5, 0, size * 0.5))


# ================================================================ 布置

func _place_props() -> void:
	var kinds: Array = theme["props"]
	var count := int(size * size / 90.0)
	var used: Array[Vector3] = [spawn_pos]
	for i in count:
		var p := _random_point(10.0, used, 3.0)
		if p.y <= float(theme.get("water", -10.0)) + 0.5:
			continue
		var kind: String = kinds[rng.randi() % kinds.size()]
		var node := RealmProps.build(kind, rng)
		if node == null:
			continue
		add_child(node)
		node.global_position = p
		node.rotation.y = rng.randf() * TAU
		if i % 3 == 0:
			used.append(p)


func _place_containers() -> void:
	var cdef: Dictionary = def.get("containers", {})
	var cr: Array = cdef.get("count", [18, 24])
	var n := rng.randi_range(int(cr[0]), int(cr[1]))
	var types: Array = cdef.get("types", [])
	var total := 0.0
	for t in types:
		total += float(t.get("w", 1.0))
	var used: Array[Vector3] = [spawn_pos]
	for i in n:
		var r := rng.randf() * total
		var pick: Dictionary = types[0]
		for t in types:
			r -= float(t.get("w", 1.0))
			if r <= 0.0:
				pick = t
				break
		var p := _random_point(14.0, used, 7.0)
		used.append(p)
		LootContainer.create(self, p, str(pick["type"]), str(pick["table"]), float(pick.get("time", 3.0)), rng)


func _place_extracts() -> void:
	var n := clampi(int(def.get("extracts", 2)), 1, 3)
	var cands: Array[Vector3] = []
	for i in 12:
		cands.append(_random_point(18.0))
	cands.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(spawn_pos) > b.distance_to(spawn_pos))
	var chosen: Array[Vector3] = []
	for c in cands:
		var ok := true
		for o in chosen:
			if o.distance_to(c) < size * 0.35:
				ok = false
		if ok:
			chosen.append(c)
		if chosen.size() >= n:
			break
	for i in chosen.size():
		var ep := ExtractionPoint.new()
		match i:
			0:
				ep.label = "固定撤离阵"
			1:
				ep.label = "灵石传送阵"
				ep.active = false
				ep.cost = 50 + 50 * GS.player.realm
			2:
				ep.label = "限时撤离阵"
				ep.active = false
				ep.cost = 99999
				ep.set_meta("timed", true)
		add_child(ep)
		ep.global_position = chosen[i]
		ep.extracted.connect(_on_extracted)
		extracts.append(ep)


func _spawn_enemies() -> void:
	var groups: Array = def.get("enemy_groups", [5, 8])
	var n := rng.randi_range(int(groups[0]), int(groups[1]))
	var pool: Array = def.get("enemies", [])
	var total := 0.0
	for e in pool:
		total += float(e.get("w", 1.0))
	for i in n:
		var r := rng.randf() * total
		var eid := str(pool[0]["id"]) if not pool.is_empty() else "wolf_grey"
		for e in pool:
			r -= float(e.get("w", 1.0))
			if r <= 0.0:
				eid = str(e["id"])
				break
		var ed := DB.enemy(eid)
		if ed.is_empty():
			continue
		var center := Vector3.ZERO
		for t in 20:
			center = _random_point(16.0)
			if center.distance_to(spawn_pos) > 40.0:
				break
		var pack: Array = ed.get("pack", [1, 1])
		for j in rng.randi_range(int(pack[0]), int(pack[1])):
			var off := Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
			var p := _ground(center + off)
			if str(ed.get("kind", "beast")) == "beast":
				ActorFactory.spawn_beast(self, eid, p + Vector3.UP * 0.3)
			else:
				_spawn_cultivator(eid, p, true)


## 秘境首领：守在离入口最远的祭坛附近
func _spawn_boss() -> void:
	var bid := str(def.get("boss", ""))
	if bid == "" or DB.enemy(bid).is_empty():
		return
	var best := spawn_pos
	for n in get_tree().get_nodes_in_group("loot_container"):
		var lc := n as LootContainer
		if lc.kind == "altar" and lc.global_position.distance_to(spawn_pos) > best.distance_to(spawn_pos):
			best = lc.global_position
	if best == spawn_pos:
		best = _random_point(20.0)
		for i in 10:
			var c := _random_point(20.0)
			if c.distance_to(spawn_pos) > best.distance_to(spawn_pos):
				best = c
	var b := ActorFactory.spawn_beast(self, bid, _ground(best + Vector3(4, 0, 4)) + Vector3.UP * 0.5)
	b.ai.aggro = 18.0
	b.ai.leash = 40.0
	b.set_meta("boss", true)
	if b.nameplate != null:
		b.nameplate.subtitle = "首领"
		b.nameplate.refresh()


## 已接的“秘境寻物”任务：把任务物品藏进某个容器
func _inject_mission_items() -> void:
	var containers := get_tree().get_nodes_in_group("loot_container")
	if containers.is_empty():
		return
	for m in SectSystem.accepted():
		if str(m.get("type", "")) != "realm_item" or m.get("done", false):
			continue
		var need := int(m.get("count", 1)) - GS.player.bag.count_of(str(m.get("item", "")))
		if need <= 0:
			continue
		var lc: LootContainer = containers[rng.randi() % containers.size()]
		lc.grid.add(ItemInstance.create(str(m["item"]), need))
		lc.best_grade = maxi(lc.best_grade, 2)


func _spawn_rivals() -> void:
	var rr: Array = def.get("rivals", [1, 3])
	var ids: Array = def.get("rival_ids", ["rogue_cultivator"])
	for i in rng.randi_range(int(rr[0]), int(rr[1])):
		var tid := str(ids[rng.randi() % ids.size()])
		var p := _random_point(18.0)
		if p.distance_to(spawn_pos) < 35.0:
			p = _random_point(18.0)
		_spawn_cultivator(tid, p, false)


func _spawn_cultivator(tid: String, p: Vector3, aggressive: bool) -> void:
	var tpl := DB.enemy(tid)
	if tpl.is_empty():
		return
	var over := {}
	var pr := GS.player.realm
	if int(tpl.get("realm", 0)) < pr:
		over["realm"] = pr
		over["stage"] = [0, 3]
	var pd := ActorFactory.make_cultivator_pd(tpl, rng, over)
	pd.bag = InventoryGrid.new(6, 5)
	for it in LootRoller.roll("corpse_t0" if DB.loot_tables.has("corpse_t0") else DB.loot_tables.keys()[0], rng):
		pd.bag.add(it)
	pd.spirit_stones = rng.randi_range(10, 80)
	var faction := str(tpl.get("faction", "neutral"))
	if faction == "none" or faction == "":
		faction = "neutral"
	var pers: String = str(tpl.get("ai", "balanced"))
	if pers not in ["aggressive", "balanced", "cautious"]:
		pers = "balanced"
	var a := ActorFactory.spawn_cultivator(self, pd, p + Vector3.UP * 0.2, faction, pers, not aggressive)
	a.set_meta("template_id", tid)
	var ai: CultivatorAI = a.controller
	ai.looter = true
	ai.hostile_chance = {"aggressive": 0.85, "balanced": 0.4, "cautious": 0.1}.get(pers, 0.4)
	ai.set_state("loot")
	ai.aggro_range = 22.0


# ================================================================ 流程

func _process(delta: float) -> void:
	if ended:
		return
	elapsed += delta
	time_left -= delta
	var total := float(def.get("time_limit", 600))
	if not _half_open and time_left < total * 0.5:
		_half_open = true
		for ep in extracts:
			if ep.has_meta("timed"):
				ep.activate()
	for t in [120, 60, 30, 10]:
		if time_left <= t and not _warned.has(t):
			_warned[t] = true
			Events.notify.emit("秘境即将崩塌！剩余 %d 秒" % t, "bad" if t <= 30 else "warn")
			Audio.play("alarm")
	_lava_check(delta)
	var mins := int(maxf(time_left, 0.0)) / 60
	var secs := int(maxf(time_left, 0.0)) % 60
	var obj := "%s · 崩塌 %02d:%02d · 储物袋价值 %d" % [def.get("name", ""), mins, secs, GS.player.bag.total_value()]
	Events.hud_objective.emit(obj)
	if time_left <= 0.0:
		_collapse()


var _lava_t: float = 0.0


## 熔岩：站在岩浆上会被灼烧
func _lava_check(delta: float) -> void:
	var lava := float(theme.get("lava", -10.0))
	if lava < 0.0 or session == null or session.player == null or not is_instance_valid(session.player):
		return
	_lava_t -= delta
	if _lava_t > 0.0:
		return
	_lava_t = 0.4
	for b in CombatUtil.bodies():
		var body := b as Node3D
		var c := CombatUtil.combatant_of(body)
		if c == null or not c.alive:
			continue
		var p := body.global_position
		if terrain.height_at(p.x, p.z) <= lava and p.y < lava + 0.8:
			c.apply_status("burn", 2.0, null)
			c.take_damage({"kind": "env", "flat": c.stat("max_hp") * 0.04, "element": Elem.FIRE, "no_react": true})
			if CombatUtil.is_player(body) and randf() < 0.3:
				Events.notify.emit("脚下岩浆灼人！", "warn")


func _collapse() -> void:
	ended = true
	Events.notify.emit("秘境崩塌，你被空间乱流吞没……", "bad")
	if session.player != null and session.player.combatant.alive:
		session.player.combatant.kill()


func _on_actor_died(actor: Node, killer: Node) -> void:
	CombatRewards.on_actor_died(actor, killer)


func _convert_stones() -> void:
	var n := GS.player.bag.count_of("spirit_stone")
	if n > 0:
		GS.player.bag.take("spirit_stone", n)
		GS.player.spirit_stones += n
		Events.notify.emit("灵石 +%d" % n, "loot")


func _on_extracted() -> void:
	if ended:
		return
	ended = true
	GS.player.realms_cleared += 1
	var value := GS.player.bag.total_value()
	Events.notify.emit("成功撤离！本次收获价值 %d 灵石" % value, "realm")
	GS.in_realm = false
	GS.advance_time(elapsed / 60.0 * 2.0)
	_return_overworld()


func _on_player_died() -> void:
	ended = true
	var lost := GS.player.bag.total_value()
	GS.player.bag.clear()
	GS.player.injury_days = maxf(GS.player.injury_days, 15.0)
	GS.in_realm = false
	Events.notify.emit("身陨秘境……储物袋中价值 %d 灵石的物品尽数遗失" % lost, "bad")
	GS.advance_time(elapsed / 60.0 * 2.0 + 24.0)
	GS.overworld_position = Vector3.INF
	await get_tree().create_timer(3.0).timeout
	_return_overworld()


func _return_overworld() -> void:
	var rp = GS.realm_request.get("return_pos", null)
	if rp is Vector3:
		GS.overworld_position = rp
	GS.recompute()
	if not test_mode:
		Scenes.goto_overworld()
