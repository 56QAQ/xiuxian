class_name FX
## 一次性战斗特效（体素方块粒子、冲击环、光柱、闪光）。全部自动销毁。
## 使用 CPUParticles3D 以兼容 Forward+ 与 Compatibility 渲染器。

static var _mats: Dictionary = {}
static var _cube: BoxMesh
static var _ring: TorusMesh
static var _cyl: CylinderMesh
static var _sphere: SphereMesh
static var budget_particles: int = 0   ## 每帧粒子节点预算，防止大乱斗时卡顿


static func root() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.current_scene if tree.current_scene != null else tree.root


## 发光（加色、无光照）材质，按颜色缓存
static func glow_mat(c: Color, additive: bool = true) -> StandardMaterial3D:
	var key := "%s|%s" % [c.to_html(), additive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_mats[key] = m
	return m


## 实体（有光照）的碎屑材质
static func solid_mat(c: Color) -> StandardMaterial3D:
	var key := "solid|" + c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	_mats[key] = m
	return m


static func cube_mesh() -> BoxMesh:
	if _cube == null:
		_cube = BoxMesh.new()
		_cube.size = Vector3.ONE
	return _cube


static func _fade_gradient(c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.6, Color(1, 1, 1, 0.8))
	return g


static func _auto_free(n: Node, t: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	tree.create_timer(t, false).timeout.connect(func() -> void:
		if is_instance_valid(n):
			n.queue_free())


## 体素碎块迸溅
static func burst(pos: Vector3, color: Color, amount: int = 16, speed: float = 6.0, size: float = 0.09, life: float = 0.55, glow: bool = true, gravity: float = 9.0) -> void:
	var r := root()
	if r == null or amount <= 0:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.randomness = 0.4
	p.mesh = cube_mesh()
	p.material_override = glow_mat(color) if glow else solid_mat(color)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.4
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.color = color
	p.color_ramp = _fade_gradient(color)
	r.add_child(p)
	p.global_position = pos
	p.emitting = true
	_auto_free(p, life + 0.3)


## 地面扬尘
static func dust(pos: Vector3, amount: int = 10, color: Color = Color(0.78, 0.74, 0.66)) -> void:
	burst(pos, color, amount, 3.5, 0.14, 0.7, false, 2.0)


## 冲击环（水平扩散）
static func ring(pos: Vector3, radius: float, color: Color, time: float = 0.35, thickness: float = 0.15, up: Vector3 = Vector3.UP) -> void:
	var r := root()
	if r == null:
		return
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.0 - thickness
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 6
	mi.mesh = tm
	var m := glow_mat(color).duplicate() as StandardMaterial3D
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(mi)
	mi.global_position = pos
	if not up.is_equal_approx(Vector3.UP):
		mi.look_at(pos + up, Vector3.RIGHT if absf(up.dot(Vector3.UP)) > 0.9 else Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	mi.scale = Vector3.ONE * 0.1
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, radius * 0.5, radius), time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, time)
	_auto_free(mi, time + 0.05)


## 球形冲击波
static func shock_sphere(pos: Vector3, radius: float, color: Color, time: float = 0.3) -> void:
	var r := root()
	if r == null:
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 16
	sm.rings = 8
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	var m := glow_mat(color).duplicate() as StandardMaterial3D
	m.albedo_color = Color(color.r, color.g, color.b, 0.6)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, time)
	_auto_free(mi, time + 0.05)


## 短暂点光源
static func flash_light(pos: Vector3, color: Color, energy: float = 4.0, light_range: float = 7.0, time: float = 0.2) -> void:
	var r := root()
	if r == null:
		return
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	r.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time)
	_auto_free(l, time + 0.05)


## 光柱（水牢、天降等）
static func pillar(pos: Vector3, radius: float, height: float, color: Color, time: float = 0.6) -> void:
	var r := root()
	if r == null:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.8
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	var m := glow_mat(color).duplicate() as StandardMaterial3D
	m.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(mi)
	mi.global_position = pos + Vector3.UP * height * 0.5
	mi.scale = Vector3(0.2, 1.0, 0.2)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, time * 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(time * 0.5)
	tw.tween_property(m, "albedo_color:a", 0.0, time * 0.3)
	_auto_free(mi, time + 0.05)


## 预警圈（法术落点提示）
static func telegraph(pos: Vector3, radius: float, color: Color, time: float) -> void:
	var r := root()
	if r == null:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.05
	cm.radial_segments = 24
	mi.mesh = cm
	var m := glow_mat(color).duplicate() as StandardMaterial3D
	m.albedo_color = Color(color.r, color.g, color.b, 0.25)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.08
	mi.scale = Vector3(radius, 1.0, radius)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.55, time)
	_auto_free(mi, time + 0.02)
	ring(pos + Vector3.UP * 0.1, radius, color, time, 0.06)


## 两点之间的光束/闪电
static func beam(from: Vector3, to: Vector3, color: Color, width: float = 0.2, time: float = 0.15, jagged: bool = false) -> void:
	var r := root()
	if r == null:
		return
	var holder := Node3D.new()
	r.add_child(holder)
	var pts: Array[Vector3] = [from]
	if jagged:
		var n := 6
		for i in range(1, n):
			var p := from.lerp(to, float(i) / n)
			p += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * from.distance_to(to) * 0.05
			pts.append(p)
	pts.append(to)
	var m := glow_mat(color).duplicate() as StandardMaterial3D
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width, width, a.distance_to(b))
		mi.mesh = bm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		mi.global_position = (a + b) * 0.5
		if a.distance_to(b) > 0.01:
			mi.look_at(b, Vector3.UP if absf((b - a).normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
	var tw := holder.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, time)
	_auto_free(holder, time + 0.05)


## 陨星/流火：从天而降的发光方块
static func meteor(from: Vector3, to: Vector3, color: Color, time: float) -> void:
	var r := root()
	if r == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = cube_mesh()
	mi.material_override = glow_mat(color)
	mi.scale = Vector3.ONE * 0.9
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(mi)
	mi.global_position = from
	var trail := CPUParticles3D.new()
	trail.amount = 24
	trail.lifetime = 0.4
	trail.mesh = cube_mesh()
	trail.material_override = glow_mat(color)
	trail.scale_amount_min = 0.15
	trail.scale_amount_max = 0.35
	trail.spread = 20.0
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_max = 1.0
	trail.color_ramp = _fade_gradient(color)
	trail.local_coords = false
	mi.add_child(trail)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "global_position", to, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(mi, "rotation", Vector3(6, 4, 2), time)
	_auto_free(mi, time + 0.02)


## 施法时手中聚光
static func sparkle(pos: Vector3, color: Color, amount: int = 8) -> void:
	burst(pos, color, amount, 2.0, 0.05, 0.4, true, -1.0)
