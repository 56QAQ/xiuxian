extends Node3D
## 秘境（搜打撤）：程序生成的主题区域，散布容器、妖兽与寻宝修士；限时崩塌；撤离阵撤离。
## 入口参数：GS.realm_request = {realm_id, seed, return_pos?}

const THEMES := {
	"forest": {"top": [Color(0.33, 0.6, 0.26), Color(0.4, 0.66, 0.3), Color(0.28, 0.52, 0.24)], "side": Color(0.45, 0.33, 0.22), "deep": Color(0.4, 0.38, 0.36),
		"sky": Color(0.55, 0.75, 0.6), "fog": Color(0.6, 0.78, 0.62), "sun": Color(1.0, 0.95, 0.85), "amp": 7.0, "props": ["tree", "tree", "bush", "rock"], "water": 2.5},
	"ruins": {"top": [Color(0.55, 0.56, 0.5), Color(0.42, 0.52, 0.36), Color(0.6, 0.6, 0.56)], "side": Color(0.5, 0.48, 0.45), "deep": Color(0.38, 0.37, 0.36),
		"sky": Color(0.62, 0.62, 0.7), "fog": Color(0.62, 0.62, 0.68), "sun": Color(0.95, 0.9, 0.85), "amp": 4.0, "props": ["pillar", "wall", "rock", "tree"], "water": -10.0},
	"volcano": {"top": [Color(0.22, 0.2, 0.2), Color(0.3, 0.24, 0.22), Color(0.18, 0.16, 0.16)], "side": Color(0.32, 0.22, 0.18), "deep": Color(0.2, 0.16, 0.15),
		"sky": Color(0.5, 0.25, 0.2), "fog": Color(0.55, 0.3, 0.22), "sun": Color(1.0, 0.7, 0.5), "amp": 9.0, "props": ["crystal", "rock", "rock", "deadtree"], "lava": 3.0, "water": -10.0},
	"ice": {"top": [Color(0.92, 0.95, 1.0), Color(0.85, 0.9, 0.98), Color(0.75, 0.85, 0.95)], "side": Color(0.6, 0.75, 0.9), "deep": Color(0.5, 0.6, 0.75),
		"sky": Color(0.7, 0.8, 0.95), "fog": Color(0.82, 0.88, 0.96), "sun": Color(0.9, 0.95, 1.0), "amp": 8.0, "props": ["icespike", "pine", "rock"], "water": 2.0},
	"water": {"top": [Color(0.4, 0.66, 0.4), Color(0.85, 0.8, 0.6), Color(0.35, 0.58, 0.36)], "side": Color(0.6, 0.55, 0.45), "deep": Color(0.45, 0.45, 0.42),
		"sky": Color(0.55, 0.72, 0.9), "fog": Color(0.6, 0.75, 0.88), "sun": Color(1.0, 0.97, 0.9), "amp": 6.0, "props": ["tree", "rock", "bush"], "water": 5.5},
	"battlefield": {"top": [Color(0.4, 0.34, 0.28), Color(0.35, 0.3, 0.27), Color(0.45, 0.38, 0.3)], "side": Color(0.35, 0.28, 0.22), "deep": Color(0.28, 0.24, 0.2),
		"sky": Color(0.55, 0.45, 0.4), "fog": Color(0.55, 0.48, 0.42), "sun": Color(1.0, 0.85, 0.7), "amp": 5.0, "props": ["deadtree", "rock", "wall", "pillar"], "water": -10.0},
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
	_spawn_rivals()
	Events.actor_died.connect(_on_actor_died)
	Events.inventory_changed.connect(_convert_stones)
	Events.notify.emit("踏入秘境「%s」" % def.get("name", ""), "realm")
	Events.notify.emit("寻找宝物，在秘境崩塌前前往撤离阵（绿色光柱）", "info")
	if Audio.has_method("play_music"):
		Audio.call("play_music", "music_realm")


func _exit_tree() -> void:
	GS.in_realm = false
	Events.hud_objective.emit("")


# ================================================================ 环境

func _build_env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	var sc: Color = theme["sky"]
	sm.sky_top_color = sc.darkened(0.3)
	sm.sky_horizon_color = sc.lightened(0.2)
	sm.ground_bottom_color = sc.darkened(0.5)
	sm.ground_horizon_color = sc
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.fog_enabled = true
	e.fog_light_color = theme["fog"]
	e.fog_density = 0.012
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, rng.randf_range(0, 360), 0)
	sun.light_color = theme["sun"]
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	# 飘散的灵气光点
	var motes := CPUParticles3D.new()
	motes.amount = 160
	motes.lifetime = 8.0
	motes.mesh = FX.cube_mesh()
	motes.material_override = FX.glow_mat(Color(0.8, 1.0, 0.9, 0.8))
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(size * 0.5, 10, size * 0.5)
	motes.gravity = Vector3(0, 0.15, 0)
	motes.scale_amount_min = 0.04
	motes.scale_amount_max = 0.09
	motes.direction = Vector3.UP
	motes.initial_velocity_max = 0.4
	motes.position = Vector3(size * 0.5, 14, size * 0.5)
	motes.preprocess = 8.0
	add_child(motes)


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
			if cn > 0.25:
				col = palette[1]
			elif cn < -0.3:
				col = palette[2]
			col = col.lightened(cn * 0.05)
			if hv <= water:
				col = Color(0.78, 0.74, 0.58)
			if hv <= lava:
				col = VoxelGrid.glow(Color(1.0, 0.45, 0.1), 0.9)
			if e > 0.5:
				col = (theme["side"] as Color).lerp(col, 0.4)
			tops[x + z * size] = col
	terrain = HeightfieldTerrain.new()
	terrain.name = "Terrain"
	terrain.side_color = theme["side"]
	terrain.deep_color = theme["deep"]
	add_child(terrain)
	terrain.setup(size, size, h, tops)
	# 水面
	if water > 0.0:
		var wm := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(size, size)
		wm.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.45, 0.65, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.1
		mat.metallic_specular = 0.8
		wm.material_override = mat
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
	var mins := int(maxf(time_left, 0.0)) / 60
	var secs := int(maxf(time_left, 0.0)) % 60
	var obj := "%s · 崩塌 %02d:%02d · 储物袋价值 %d" % [def.get("name", ""), mins, secs, GS.player.bag.total_value()]
	Events.hud_objective.emit(obj)
	if time_left <= 0.0:
		_collapse()


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
