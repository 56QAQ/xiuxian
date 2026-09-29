class_name Projectile
extends Node3D
## 弹道：灵气弹与法诀飞弹。逐帧射线检测世界，按线段距离检测角色（带粗细）。
##
## spawn(opts):
##   owner: Node3D, pos, dir, speed, size, range, homing(0~1), target: Node3D,
##   pierce: int, explode: float(爆炸半径), crater: float, info: Dictionary(伤害信息),
##   element, shape("orb"/"blade"/"spike"/"rock"/"leaf"), gravity: float,
##   color（可选，仅表现：覆盖元素色）, vfx_elem（可选，仅表现：如 thunder）
## 表现：发光核心 + 柔光光晕 + 条带尾迹 + 元素粒子；形状（月牙/冰锥/岩块/叶片）各不相同；命中与爆炸按元素区分。

var owner_body: Node3D
var velocity: Vector3
var speed: float = 60.0
var size: float = 0.2
var max_range: float = 80.0
var homing: float = 0.0
var target: Node3D
var pierce: int = 0
var explode: float = 0.0
var crater_r: float = 0.0
var info: Dictionary = {}
var element: String = Elem.NONE
var color: Color = Color.WHITE
var gravity: float = 0.0
var traveled: float = 0.0
var _hit_ids: Dictionary = {}
var _dead: bool = false
var shape: String = "orb"
var vfx_elem: String = "none"
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _body: MeshInstance3D
var _spin: Vector3 = Vector3.ZERO
var _emitters: Array[CPUParticles3D] = []
var _ribbon: VfxRibbon
var _light: OmniLight3D
var _t: float = 0.0
static var _lights_alive: int = 0
const MAX_LIGHTS := 6


static func spawn(opts: Dictionary) -> Projectile:
	var p := Projectile.new()
	p.add_to_group("projectiles")
	p.owner_body = opts.get("owner", null)
	p.speed = float(opts.get("speed", 60.0))
	var dir: Vector3 = (opts.get("dir", Vector3.FORWARD) as Vector3).normalized()
	p.velocity = dir * p.speed
	p.size = float(opts.get("size", 0.2))
	p.max_range = float(opts.get("range", 80.0))
	p.homing = float(opts.get("homing", 0.0))
	p.target = opts.get("target", null)
	p.pierce = int(opts.get("pierce", 0))
	p.explode = float(opts.get("explode", 0.0))
	p.crater_r = float(opts.get("crater", 0.0))
	p.info = opts.get("info", {})
	p.element = str(opts.get("element", p.info.get("element", Elem.NONE)))
	p.vfx_elem = str(opts.get("vfx_elem", p.element))
	if not VfxLib.is_elem(p.vfx_elem):
		p.vfx_elem = "none"
	p.color = opts.get("color", VfxLib.main_color(p.vfx_elem))
	p.gravity = float(opts.get("gravity", 0.0))
	var root := FX.root()
	root.add_child(p)
	p.global_position = opts.get("pos", Vector3.ZERO)
	p._build_visual(str(opts.get("shape", "orb")))
	return p


func _build_visual(shp: String) -> void:
	shape = shp
	var e := vfx_elem
	if shape == "orb" and e == "earth":
		shape = "rock"
	var core_c := VfxLib.core_color(e).lerp(color, 0.15)
	var big := size >= 0.45
	var lite := VfxLib.is_lite()
	match shape:
		"blade":
			_body = _mesh(VfxLib.crescent(), VfxLib.slash_mat(int(VfxLib.pal(e)["slash"])))
			_body.scale = Vector3.ONE * size * 2.8
			_body.rotation.z = randf_range(-0.45, 0.45)
			_body.set_instance_shader_parameter("tint", color)
			_body.set_instance_shader_parameter("prog", 0.12)
			_halo = _sprite("glow_soft", color, minf(size * 4.0, 3.0), 0.6)
		"spike":
			if e == "metal" or e == "none" or e == "thunder":
				_body = _mesh(VfxLib.quad(), VfxLib.particle_mat("spark"))
				_body.basis = FX.scale_local(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(size * 1.2, size * 1.1, 1.0))
				_body.set_instance_shader_parameter("tint", core_c)
			else:
				_body = _mesh(VfxLib.spike(), VfxLib.ice_mat() if e == "water" else VfxSpells._thorn_mat())
				_body.scale = Vector3(size * 2.2, size * 2.2, size * 4.5)
				_body.set_instance_shader_parameter("tint", color)
			_core = _sprite("glow", core_c, size * 2.0)
			_halo = _sprite("glow_soft", color, minf(size * 4.5, 3.0), 0.55)
		"rock":
			var molten := explode > 0.0 or str(info.get("status", {}).get("id", "")) == "burn"
			_body = _mesh(VfxLib.rock(randi() % 4, molten), null)
			_body.scale = Vector3.ONE * size * 1.35
			_spin = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
			if molten:
				_halo = _sprite("glow", Color(1.0, 0.5, 0.15), minf(size * 4.0, 4.0), 0.8)
		"leaf":
			_body = _mesh(VfxLib.leaf_mesh(), null)
			_body.scale = Vector3.ONE * clampf(size * 4.5, 0.8, 2.0)
			_body.rotation_degrees = Vector3(0, 0, 90)
			_halo = _sprite("glow_soft", color, minf(size * 4.0, 2.0), 0.5)
		_:
			_core = _sprite("glow", core_c, size * 2.6)
			_halo = _sprite("glow_soft", color, minf(size * 6.0, 4.5), 0.75)
			if big:
				var fl := _sprite("flare", color.lerp(Color.WHITE, 0.3), size * 3.0, 0.6)
				fl.set_meta("flare", true)
	# 尾迹条带
	var profile := "fire" if e == "fire" else ("bolt" if e == "thunder" else "center")
	var rw := size * (1.7 if shape != "rock" else 1.2)
	if e == "fire":
		rw = size * 1.3
	_ribbon = VfxRibbon.create(self, color, rw, 0.08 + size * 0.14, profile)
	if _ribbon != null:
		_ribbon.taper = 0.0
		_ribbon.min_step = maxf(size * 0.4, 0.08)
		if shape == "rock" and e == "earth" and explode <= 0.0:
			_ribbon.alpha = 0.45
	# 元素粒子（小灵气弹不带粒子，降低开销）
	if size >= 0.2 and not lite:
		var n := clampi(int(size * 26.0), 6, 26)
		match e:
			"fire":
				var f := _emit("flame", n, Color.WHITE)
				f.scale_amount_min = size * 1.1
				f.scale_amount_max = size * 2.0
				VfxParticles.set_shape(f, "sphere", size * 0.5)
				_emit("ember", n / 2, Color(1, 0.8, 0.4))
				if big:
					var sm := _emit("smoke", n / 3, Color(0.25, 0.2, 0.18))
					sm.scale_amount_max = size * 3.0
					FX.heat(global_position, size * 4.0, 0.0, self)
			"water":
				var dr := _emit("droplet", n / 2, Color(0.75, 0.92, 1.0))
				dr.gravity = Vector3(0, -6, 0)
				var ms := _emit("mist", maxi(n / 4, 3), Color(0.85, 0.95, 1.0))
				ms.scale_amount_max = size * 3.0
			"wood":
				_emit("leaf", maxi(n / 3, 3), Color(0.5, 0.95, 0.45))
				_emit("pollen", n / 2, color)
			"earth":
				if shape == "rock" and (explode > 0.0 or str(info.get("status", {}).get("id", "")) == "burn"):
					var f2 := _emit("flame", n, Color.WHITE)
					f2.scale_amount_min = size * 0.8
					f2.scale_amount_max = size * 1.6
					var sm2 := _emit("smoke", n / 3, Color(0.22, 0.18, 0.16))
					sm2.scale_amount_max = size * 3.0
				else:
					var d := _emit("dust", maxi(n / 4, 3), Color(0.72, 0.62, 0.46))
					d.scale_amount_max = size * 2.0
			"metal", "thunder":
				var sp := _emit("spark", n / 2, VfxLib.core_color(e))
				sp.gravity = Vector3.ZERO
				sp.initial_velocity_max = 1.5
			_:
				var mo := _emit("mote", n / 2, color)
				mo.scale_amount_max = size * 0.8
	if big and _lights_alive < MAX_LIGHTS and not lite:
		_light = OmniLight3D.new()
		_light.light_color = color
		_light.light_energy = 1.6
		_light.omni_range = 3.5 + size * 4.0
		add_child(_light)
		_lights_alive += 1
	_orient()


func _mesh(m: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	if mat != null:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _sprite(mat: String, c: Color, s: float, fade: float = 1.0) -> MeshInstance3D:
	var mi := _mesh(VfxLib.quad(), VfxLib.particle_mat(mat))
	mi.scale = Vector3.ONE * s
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("fade", fade)
	return mi


func _emit(preset: String, amount: int, c: Color) -> CPUParticles3D:
	var p := VfxParticles.make(preset, amount, self, c)
	p.direction = Vector3(0, 0, 1)
	_emitters.append(p)
	return p


func _exit_tree() -> void:
	if _light != null:
		_lights_alive = maxi(_lights_alive - 1, 0)
		_light = null


func _orient() -> void:
	if velocity.length_squared() > 0.01:
		var up := Vector3.UP if absf(velocity.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		look_at(global_position + velocity, up)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	# 追踪：目标瞬步闪避时丢失锁定
	if homing > 0.0 and target != null and is_instance_valid(target):
		var tc := CombatUtil.combatant_of(target)
		var evading = target.get("evading")
		if tc != null and tc.alive and not (evading is float and evading > 0.0):
			var want := (target.global_position + Vector3.UP * 0.95 - global_position).normalized() * speed
			velocity = velocity.lerp(want, clampf(homing * 6.0 * delta, 0.0, 1.0)).normalized() * speed
		else:
			target = null
	velocity.y -= gravity * delta
	_t += delta
	if _body != null and _spin != Vector3.ZERO:
		_body.rotation += _spin * delta
	if _halo != null:
		_halo.scale = Vector3.ONE * minf(size * (6.0 if shape == "orb" else 4.0), 4.5) * (1.0 + 0.1 * sin(_t * 30.0))
	var from := global_position
	var to := from + velocity * delta
	var step := from.distance_to(to)
	# 角色命中（线段距离）
	for b in CombatUtil.bodies():
		var body := b as Node3D
		if body == null or body == owner_body or _hit_ids.has(body.get_instance_id()):
			continue
		if not CombatUtil.can_damage(owner_body if is_instance_valid(owner_body) else null, body):
			continue
		var c1 := body.global_position + Vector3.UP * 0.5
		var c2 := body.global_position + Vector3.UP * 1.4
		var d := minf(CombatUtil.dist_point_segment(c1, from, to), CombatUtil.dist_point_segment(c2, from, to))
		if d <= 0.45 + size:
			_hit_body(body, body.global_position + Vector3.UP * 1.0)
			if _dead:
				return
	# 世界命中
	var hit := CombatUtil.ray_world(from, to + velocity.normalized() * size)
	if not hit.is_empty():
		global_position = hit["position"]
		var col = hit.get("collider")
		if col != null and col.has_method("apply_damage_at"):
			col.call("apply_damage_at", hit["position"], maxf(size * 2.0, explode * 0.5), float(info.get("mult", 1.0)) * 10.0)
		_impact(hit["position"], hit.get("normal", Vector3.UP))
		return
	global_position = to
	traveled += step
	_orient()
	if traveled >= max_range:
		_impact(global_position, -velocity.normalized())


func _hit_body(body: Node3D, point: Vector3) -> void:
	_hit_ids[body.get_instance_id()] = true
	var i := info.duplicate()
	i["point"] = point
	i["dir"] = velocity.normalized()
	if explode <= 0.0 and is_instance_valid(owner_body):
		CombatUtil.hit(owner_body, body, i)
	elif explode <= 0.0:
		CombatUtil.hit(null, body, i)
	if explode <= 0.0:
		FX.impact(point, -velocity.normalized(), vfx_elem, size)
	Audio.play_at("bolt_hit", point, -4.0)
	if explode > 0.0:
		_impact(point, -velocity.normalized())
		return
	if pierce <= 0:
		_impact(point, -velocity.normalized(), false)
	else:
		pierce -= 1


func _impact(point: Vector3, normal: Vector3, do_fx: bool = true) -> void:
	if _dead:
		return
	_dead = true
	if explode > 0.0:
		var ob: Node3D = owner_body if is_instance_valid(owner_body) else null
		var i := info.duplicate()
		CombatUtil.aoe(ob, point, explode, i)
		CombatUtil.damage_destructibles(point, explode * 0.6, float(info.get("mult", 1.0)) * 20.0)
		FX.explosion(point, explode, vfx_elem, {"molten": shape == "rock" or str(info.get("status", {}).get("id", "")) == "burn"})
		Audio.play_at("explosion", point)
		if crater_r > 0.0:
			CombatUtil.crater(point, crater_r)
		if CombatUtil.is_player(ob) or (ob != null and ob.global_position.distance_to(point) < 20.0):
			CombatUtil.shake(0.25)
	elif do_fx:
		FX.impact(point + normal * 0.1, normal, vfx_elem, size)
		Audio.play_at("bolt_hit", point, -8.0)
	# 拖尾粒子与条带留存片刻后释放
	for n in [_core, _halo, _body]:
		if n != null:
			n.visible = false
	for c in get_children():
		if c is MeshInstance3D and c.has_meta("flare"):
			c.visible = false
	if _light != null:
		_light.queue_free()
		_lights_alive = maxi(_lights_alive - 1, 0)
		_light = null
	for e in _emitters:
		e.emitting = false
	if _ribbon != null and is_instance_valid(_ribbon):
		_ribbon.stop()
	var keep := 0.35
	for e in _emitters:
		keep = maxf(keep, e.lifetime)
	var t := get_tree().create_timer(keep, false)
	t.timeout.connect(queue_free)
