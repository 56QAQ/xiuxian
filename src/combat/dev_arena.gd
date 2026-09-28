extends Node3D
## 试炼场：平坦场地 + 若干修士，用于调试战斗手感（scenes/dev_arena.tscn）。
## 也被截图脚本与冒烟测试复用。

var session: GameSession
var enemies: Array[HumanoidActor] = []


func _ready() -> void:
	if not GS.active:
		GS.new_game({"name": "试剑者", "roots": {"fire": 60, "metal": 40}, "background": "clan", "seed": 7})
		GS.learn_spell("fireball", false)
		GS.learn_spell("gengjin_jianqi", false)
		GS.learn_spell("earth_shield", false)
		GS.learn_spell("flame_rain", false)
		GS.set_spell_slot(0, "gengjin_jianqi")
		GS.set_spell_slot(1, "fireball")
		GS.set_spell_slot(2, "earth_shield")
		GS.set_spell_slot(3, "flame_rain")
	build_arena(self)
	session = GameSession.new()
	session.name = "Session"
	add_child(session)
	session.start(self, Vector3(0, 0.5, 8))
	spawn_enemies(3)
	session.player_died.connect(func() -> void:
		await get_tree().create_timer(2.5).timeout
		if is_inside_tree() and get_tree().current_scene == self:
			get_tree().reload_current_scene())


func spawn_enemies(n: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var tpl := DB.enemy("xuesha_disciple")
	for i in n:
		var pd := ActorFactory.make_cultivator_pd(tpl, rng, {"realm": 0, "stage": 3 + i})
		var e := ActorFactory.spawn_cultivator(self, pd, Vector3(-6 + i * 6, 0.5, -10), "xuesha", ["aggressive", "balanced", "cautious"][i % 3], false)
		enemies.append(e)


static func build_arena(root: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.35, 0.55, 0.85)
	sm.sky_horizon_color = Color(0.78, 0.84, 0.9)
	sm.ground_horizon_color = Color(0.7, 0.72, 0.7)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.fog_enabled = true
	e.fog_density = 0.004
	e.fog_light_color = Color(0.75, 0.82, 0.9)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 40, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	root.add_child(sun)
	# 地面：体素方块拼成的石台
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(160, 2, 160)
	cs.shape = bs
	cs.position = Vector3(0, -1, 0)
	ground.add_child(cs)
	var g := VoxelGrid.new(80, 1, 80)
	for z in 80:
		for x in 80:
			var n := sin(x * 0.7) * cos(z * 0.5) * 0.03 + ((x + z) % 2) * 0.02
			var c := Color(0.55 + n, 0.56 + n, 0.52 + n)
			if (x / 8 + z / 8) % 2 == 0:
				c = c.darkened(0.06)
			g.set_color(x, 0, z, c)
	var mi := VoxelMesher.build_instance(g, 2.0, Vector3(-80, -2, -80))
	ground.add_child(mi)
	root.add_child(ground)
	# 石柱
	for i in 8:
		var ang := TAU * i / 8.0
		var pillar := StaticBody3D.new()
		pillar.collision_layer = 1
		var pcs := CollisionShape3D.new()
		var pb := BoxShape3D.new()
		pb.size = Vector3(1.6, 6, 1.6)
		pcs.shape = pb
		pcs.position = Vector3(0, 3, 0)
		pillar.add_child(pcs)
		var pg := VoxelGrid.new(4, 15, 4)
		pg.fill_box(Vector3i(0, 0, 0), Vector3i(3, 14, 3), Color(0.72, 0.7, 0.66))
		pg.fill_box(Vector3i(0, 13, 0), Vector3i(3, 14, 3), Color(0.8, 0.2, 0.15))
		pillar.add_child(VoxelMesher.build_instance(pg, 0.4, Vector3(-0.8, 0, -0.8)))
		root.add_child(pillar)
		pillar.position = Vector3(cos(ang) * 30.0, 0, sin(ang) * 30.0)
