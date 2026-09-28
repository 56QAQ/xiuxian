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


## 试炼场：汉白玉八卦台 + 青石广场 + 朱漆石柱 + 汉白玉栏杆 + 青铜火盆，远处松林、亭与牌坊。
## 碰撞：160×160 地面（顶面 y=0）+ 半径 30 的 8 根石柱（与旧版一致）+ 半径 44 的栏杆（四向留门）。
static func build_arena(root: Node3D) -> void:
	var K := BlockTex
	var env := WorldEnvironment.new()
	var e := Atmosphere.make_environment()
	var sky_mat := e.sky.sky_material as ShaderMaterial
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	Atmosphere.setup_sun(sun, 80.0)
	sun.rotation_degrees = Vector3(-50, 40, 0)
	root.add_child(sun)
	var pal := Atmosphere.DAY.duplicate()
	pal["sun"] = Color(1.0, 0.93, 0.80)
	pal["sun_e"] = 1.55
	pal["fog_end"] = 520.0
	pal["vol_d"] = 0.004
	pal["cloud"] = 0.38
	Atmosphere.apply(e, sky_mat, sun, pal)
	# 斗法读图优先：关闭体积雾（法术强光会把雾照成一片）
	e.volumetric_fog_enabled = false
	BlockTex.set_env({"snow_params": Vector4(999.0, 1000.0, 360.0, 250.0), "snow_global": 0.0, "water_level": -100.0, "night_glow": 0.0})
	# 地面碰撞
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(160, 2, 160)
	cs.shape = bs
	cs.position = Vector3(0, -1, 0)
	ground.add_child(cs)
	root.add_child(ground)
	var m := BuildingMesh.new(2024)
	var stone := Color(0.66, 0.65, 0.62)
	var marble := Color(0.86, 0.85, 0.80)
	var gold := Color(0.85, 0.68, 0.30)
	var lacquer := Color(0.60, 0.14, 0.11)
	var p := BuildingBuilder.pal_with({"stone": stone, "stone2": Color(0.56, 0.55, 0.53)})
	# 草地
	m.kind = K.K_GRASS
	m.box(Vector3(-100, -2, -100), Vector3(100, -0.02, 100), Color(0.40, 0.60, 0.30), false, true, Color(0.40, 0.60, 0.30))
	# 青石广场（高出草地 2 厘米）与外沿台阶
	m.kind = K.K_FLAGSTONE
	m.box(Vector3(-38, -0.6, -38), Vector3(38, 0.0, 38), Color(0.64, 0.63, 0.60), false, true)
	m.kind = K.K_STONE
	m.box(Vector3(-39.5, -0.6, -39.5), Vector3(39.5, -0.3, 39.5), Color(0.58, 0.57, 0.55), false, true)
	# 八卦台：汉白玉圆台（外圈金线、八条辐条、太极）
	var r_out := 11.0
	for z in range(-12, 12):
		for x in range(-12, 12):
			var d := Vector2(x + 0.5, z + 0.5).length()
			if d > r_out + 0.5 or d < 3.0:
				continue
			var c := marble
			var kk := K.K_STONE_SMOOTH
			if absf(d - r_out) < 0.55:
				c = gold
				kk = K.K_GOLD
			m.kind = kk
			m.box(Vector3(x, -0.3, z), Vector3(x + 1, 0.06, z + 1), c, false, true)
	# 太极（0.25 米格）：S 形分界 + 鱼眼
	var tr := 3.2
	for z in range(-14, 14):
		for x in range(-14, 14):
			var q := Vector2((x + 0.5) * 0.25, (z + 0.5) * 0.25)
			var d := q.length()
			if d >= 3.6:
				continue
			var c := marble
			if d < tr:
				var dark := q.x > 0.0
				var d1 := q.distance_to(Vector2(0, -tr * 0.5))
				var d2 := q.distance_to(Vector2(0, tr * 0.5))
				if d1 < tr * 0.5:
					dark = true
				elif d2 < tr * 0.5:
					dark = false
				if d1 < tr * 0.14:
					dark = false
				elif d2 < tr * 0.14:
					dark = true
				c = Color(0.14, 0.15, 0.18) if dark else Color(0.95, 0.94, 0.91)
				m.kind = K.K_STONE_SMOOTH
			else:
				c = gold
				m.kind = K.K_GOLD
			m.box(Vector3(x * 0.25, -0.3, z * 0.25), Vector3(x * 0.25 + 0.25, 0.07, z * 0.25 + 0.25), c, false, true)
	# 八卦辐条与内圈（金线）
	m.kind = K.K_GOLD
	for i in 8:
		var ang := i * TAU / 8.0 + TAU / 16.0
		for k in range(8, 20):
			var q := Vector2(cos(ang), sin(ang)) * (k * 0.5)
			m.box(Vector3(q.x - 0.15, 0.06, q.y - 0.15), Vector3(q.x + 0.15, 0.08, q.y + 0.15), gold)
	for i in 64:
		var ang := i * TAU / 64.0
		var q := Vector2(cos(ang), sin(ang)) * 4.2
		m.box(Vector3(q.x - 0.2, 0.06, q.y - 0.2), Vector3(q.x + 0.2, 0.08, q.y + 0.2), gold)
	# 石柱（位置与碰撞同旧版：半径 30，1.6 × 6 × 1.6）
	for i in 8:
		var ang := TAU * i / 8.0
		var c := Vector3(cos(ang) * 30.0, 0, sin(ang) * 30.0)
		var pillar := StaticBody3D.new()
		pillar.collision_layer = 1
		var pcs := CollisionShape3D.new()
		var pb := BoxShape3D.new()
		pb.size = Vector3(1.6, 6, 1.6)
		pcs.shape = pb
		pcs.position = Vector3(0, 3, 0)
		pillar.add_child(pcs)
		root.add_child(pillar)
		pillar.position = c
		m.kind = K.K_CARVED
		m.box(c + Vector3(-1.1, 0, -1.1), c + Vector3(1.1, 0.9, 1.1), stone)
		m.kind = K.K_STONE_SMOOTH
		m.box(c + Vector3(-0.95, 0.9, -0.95), c + Vector3(0.95, 1.1, 0.95), marble)
		m.kind = K.K_PILLAR
		m.box(c + Vector3(-0.75, 1.1, -0.75), c + Vector3(0.75, 5.4, 0.75), lacquer)
		m.kind = K.K_GOLD
		m.box(c + Vector3(-0.85, 2.6, -0.85), c + Vector3(0.85, 2.8, 0.85), gold)
		m.box(c + Vector3(-0.9, 5.4, -0.9), c + Vector3(0.9, 5.7, 0.9), gold)
		m.kind = K.K_STONE_SMOOTH
		m.box(c + Vector3(-1.0, 5.7, -1.0), c + Vector3(1.0, 6.0, 1.0), marble)
		BuildingBuilder.lantern(m, c + Vector3(0, 6.9, 0), p, 1.1)
		m.kind = K.K_STONE_SMOOTH
		m.box(c + Vector3(-0.3, 6.0, -0.3), c + Vector3(0.3, 6.9, 0.3), marble)
		# 外侧垂幡
		var out := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-out.z, 0, out.x)
		var bp := c + out * 0.8
		m.kind = K.K_CLOTH
		var a0 := bp - side * 0.45
		var a1 := bp + side * 0.45 + out * 0.06
		m.box(Vector3(minf(a0.x, a1.x), 1.6, minf(a0.z, a1.z)), Vector3(maxf(a0.x, a1.x), 5.0, maxf(a0.z, a1.z)), Color(0.16, 0.22, 0.38))
	# 汉白玉栏杆（八边形，半径 44，四向留门），带碰撞
	var rail := StaticBody3D.new()
	rail.collision_layer = 1
	root.add_child(rail)
	for i in 8:
		var a0 := TAU * i / 8.0 + TAU / 16.0
		var a1 := TAU * (i + 1) / 8.0 + TAU / 16.0
		var p0 := Vector2(cos(a0), sin(a0)) * 44.0
		var p1 := Vector2(cos(a1), sin(a1)) * 44.0
		var segs := 12
		for k in segs:
			var t0 := float(k) / segs
			var t1 := float(k + 1) / segs
			# 每边中段留门（正对四个方向的边）
			if i % 2 == 1 and k >= 5 and k <= 6:
				continue
			var q0 := p0.lerp(p1, t0)
			var q1 := p0.lerp(p1, t1)
			var mid := (q0 + q1) * 0.5
			m.kind = K.K_STONE_SMOOTH
			m.box(Vector3(mid.x - 0.25, 0, mid.y - 0.25), Vector3(mid.x + 0.25, 1.2, mid.y + 0.25), marble)
			m.box(Vector3(mid.x - 0.32, 1.2, mid.y - 0.32), Vector3(mid.x + 0.32, 1.45, mid.y + 0.32), marble.darkened(0.05))
			# 扶手：沿边分段的小盒子
			for j in 4:
				var f := (q0.lerp(q1, (j + 0.5) / 4.0))
				m.box(Vector3(f.x - 0.5, 0.75, f.y - 0.5), Vector3(f.x + 0.5, 0.95, f.y + 0.5), marble.darkened(0.03))
			var rcs := CollisionShape3D.new()
			var rb := BoxShape3D.new()
			var ln := q0.distance_to(q1)
			rb.size = Vector3(ln, 1.2, 0.6)
			rcs.shape = rb
			rcs.position = Vector3(mid.x, 0.6, mid.y)
			rcs.rotation.y = -atan2(q1.y - q0.y, q1.x - q0.x)
			rail.add_child(rcs)
	# 青铜火盆（四角，无碰撞）
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * 17.0, 0, sz * 17.0)
			m.kind = K.K_CARVED
			m.box(c + Vector3(-0.8, 0, -0.8), c + Vector3(0.8, 0.4, 0.8), stone)
			m.kind = K.K_BRONZE
			m.box(c + Vector3(-0.3, 0.4, -0.3), c + Vector3(0.3, 1.5, 0.3), Color(0.34, 0.28, 0.2))
			m.box(c + Vector3(-0.8, 1.5, -0.8), c + Vector3(0.8, 1.95, 0.8), Color(0.40, 0.33, 0.21))
			m.kind = K.K_LAVA
			m.box(c + Vector3(-0.6, 1.95, -0.6), c + Vector3(0.6, 2.2, 0.6), VoxelGrid.glow(Color(1.0, 0.5, 0.15), 1.0))
			var fl := OmniLight3D.new()
			fl.light_color = Color(1.0, 0.6, 0.3)
			fl.light_energy = 1.2
			fl.omni_range = 7.0
			fl.shadow_enabled = false
			root.add_child(fl)
			fl.position = c + Vector3(0, 2.8, 0)
	# 远处：牌坊、亭子
	m.push(Vector3(0, 0, 58), 2)
	BuildingBuilder.paifang(m, 0, 0, 16, 9, p)
	m.pop()
	BuildingBuilder.pavilion(m, -60, 0, 5, 3.5, p, 0.75)
	BuildingBuilder.pavilion(m, 60, 0, 5, 3.5, p, 0.75)
	var mi := m.build_instance()
	mi.name = "ArenaMesh"
	root.add_child(mi)
	# 松林、岩石环绕
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 34:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(54.0, 78.0)
		var q := Vector3(cos(ang) * r, 0, sin(ang) * r)
		if absf(q.x) < 12.0 and q.z > 40.0:
			continue
		var kind := "pine" if rng.randf() < 0.6 else ("blossom" if rng.randf() < 0.4 else "broadleaf")
		var t := PropBuilder.make_tree(kind, rng.randi())
		root.add_child(t)
		t.position = q
		t.rotation.y = float(rng.randi() % 4) * PI * 0.5
	for i in 10:
		var ang := rng.randf() * TAU
		var q := Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(48.0, 70.0)
		var rk := MeshInstance3D.new()
		rk.mesh = PropBuilder.mesh("rock_moss", i)
		root.add_child(rk)
		rk.position = q + Vector3(0, -0.3, 0)
		rk.scale = Vector3.ONE * rng.randf_range(0.9, 1.6)
