class_name Projectile
extends Node3D
## 弹道：灵气弹与法诀飞弹。逐帧射线检测世界，按线段距离检测角色（带粗细）。
##
## spawn(opts):
##   owner: Node3D, pos, dir, speed, size, range, homing(0~1), target: Node3D,
##   pierce: int, explode: float(爆炸半径), crater: float, info: Dictionary(伤害信息),
##   element, shape("orb"/"blade"/"spike"/"rock"), gravity: float

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
var _core: MeshInstance3D
var _trail: CPUParticles3D


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
	p.color = Elem.color_of(p.element) if Elem.is_valid(p.element) else Color(0.75, 0.9, 1.0)
	p.gravity = float(opts.get("gravity", 0.0))
	var root := FX.root()
	root.add_child(p)
	p.global_position = opts.get("pos", Vector3.ZERO)
	p._build_visual(str(opts.get("shape", "orb")))
	return p


func _build_visual(shape: String) -> void:
	_core = MeshInstance3D.new()
	_core.mesh = FX.cube_mesh()
	_core.material_override = FX.glow_mat(color.lightened(0.3))
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match shape:
		"blade":
			_core.scale = Vector3(size * 2.6, size * 0.35, size * 1.2)
		"spike":
			_core.scale = Vector3(size * 0.5, size * 0.5, size * 3.5)
		"rock":
			_core.material_override = FX.solid_mat(color.darkened(0.3))
			_core.scale = Vector3.ONE * size * 1.6
		_:
			_core.scale = Vector3.ONE * size * 1.4
	add_child(_core)
	var inner := MeshInstance3D.new()
	inner.mesh = FX.cube_mesh()
	inner.material_override = FX.glow_mat(Color(1, 1, 1, 0.9))
	inner.scale = Vector3.ONE * 0.55
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.add_child(inner)
	_trail = CPUParticles3D.new()
	_trail.amount = 20 if size > 0.3 else 12
	_trail.lifetime = 0.3
	_trail.mesh = FX.cube_mesh()
	_trail.material_override = FX.glow_mat(color)
	_trail.scale_amount_min = size * 0.25
	_trail.scale_amount_max = size * 0.7
	_trail.spread = 25.0
	_trail.gravity = Vector3.ZERO
	_trail.initial_velocity_max = 1.5
	_trail.color_ramp = FX._fade_gradient(color)
	_trail.local_coords = false
	add_child(_trail)
	if size >= 0.45:
		var l := OmniLight3D.new()
		l.light_color = color
		l.light_energy = 1.5
		l.omni_range = 4.0 + size * 4.0
		add_child(l)
	_orient()


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
	FX.burst(point, color, 10, 5.0, 0.08, 0.35)
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
		FX.shock_sphere(point, explode, color, 0.3)
		FX.burst(point, color, 26, 9.0, 0.14, 0.7)
		FX.flash_light(point, color, 5.0, explode * 3.0, 0.25)
		Audio.play_at("explosion", point)
		if crater_r > 0.0:
			CombatUtil.crater(point, crater_r)
		if CombatUtil.is_player(ob) or (ob != null and ob.global_position.distance_to(point) < 20.0):
			CombatUtil.shake(0.25)
	elif do_fx:
		FX.burst(point + normal * 0.1, color, 8, 4.0, 0.07, 0.3)
		Audio.play_at("bolt_hit", point, -8.0)
	# 拖尾粒子留存片刻
	if _core != null:
		_core.visible = false
	for c in get_children():
		if c is OmniLight3D:
			c.queue_free()
	if _trail != null:
		_trail.emitting = false
	var t := get_tree().create_timer(0.35, false)
	t.timeout.connect(queue_free)
