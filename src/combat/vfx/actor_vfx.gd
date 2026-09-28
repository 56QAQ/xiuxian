class_name ActorVfx
extends Node3D
## 角色持续特效组件（挂在 HumanoidActor / BeastActor 下，meta "vfx"）。每帧读取角色状态驱动表现，不修改任何玩法数据：
##   疾行灵气尾流、瞬步残影、升空/御空足下法阵、灵气弹蓄力光球、起跳扬尘；
##   护体灵光泡（护盾法诀常驻、受击涟漪、破碎）；
##   状态：流血滴落、中毒毒雾、束缚水环（定身 = 冰枷）、灼烧火焰、感电电弧、灵力枯竭、石肤、增益光环、回春；硬直星环；
##   玩家：小境界提升、突破大境界。
## 远离镜头（> NEAR 米）时不生成持续特效。

const STATUS_DT := 0.15
const NEAR := 55.0
const BUFF_IDS := ["swift", "fury", "keen", "qi_surge", "focus", "frenzy", "stone_skin"]

var actor: Node3D
var humanoid: HumanoidActor
var combatant: Combatant
var height: float = 1.75
var body_r: float = 0.4
var is_player: bool = false
var _clock: float = 0.0
var _near: bool = true
var _status_t: float = 0.0
var _fx: Dictionary = {}          ## 状态 key -> Array[Node]
var _fx_color: Dictionary = {}    ## 状态 key -> Color（光环颜色变化时重建）
var _tick: Dictionary = {}        ## 周期性小特效计时
# 身法
var _wake: Array = []
var _wake_fx: CPUParticles3D
var _ghost_t: float = 0.0
var _foot: MeshInstance3D
var _foot_fx: CPUParticles3D
var _foot_mode: String = ""
var _was_grounded: bool = true
# 蓄力
var _charge_core: MeshInstance3D
var _charge_halo: MeshInstance3D
var _charge_fx: CPUParticles3D
var _charge_ring_t: float = 0.0
# 硬直
var _stun: Node3D
# 护盾
var _shield: MeshInstance3D
var _shield_mat: ShaderMaterial
var _shield_until: float = -1.0
var _shield_strength: float = 0.0
var _shield_target: float = 0.0
var _shield_flash: float = 0.0
var _hits: Array[Vector4] = []
var _hit_idx: int = 0
# 石肤
var _tinted: bool = false
# 境界
var _last_realm: int = -1
var _last_stage: int = -1


static func attach(a: Node3D) -> ActorVfx:
	if a == null:
		return null
	if a.has_meta("vfx"):
		var old = a.get_meta("vfx")
		if old != null and is_instance_valid(old):
			return old
	var v := ActorVfx.new()
	v.name = "Vfx"
	v.actor = a
	a.add_child(v)
	a.set_meta("vfx", v)
	return v


func _ready() -> void:
	humanoid = actor as HumanoidActor
	combatant = actor.get("combatant") as Combatant
	if humanoid == null:
		var s = actor.get("size")
		var sz := float(s) if s != null else 1.0
		height = 1.2 * sz + 0.2
		body_r = 0.55 * sz
	is_player = actor.is_in_group("player")
	for i in 4:
		_hits.append(Vector4(0, 1, 0, -1))
	if is_player and GS.player != null:
		_last_realm = GS.player.realm
		_last_stage = GS.player.stage
		Events.realm_changed.connect(_on_realm_changed)


func _exit_tree() -> void:
	if Events.realm_changed.is_connected(_on_realm_changed):
		Events.realm_changed.disconnect(_on_realm_changed)


func _process(delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		queue_free()
		return
	_clock += delta
	var alive := combatant != null and combatant.alive
	var m := VfxManager.get_mgr()
	_near = m == null or m.visible_at(actor.global_position, NEAR)
	if humanoid != null and humanoid.rig != null:
		_boost(alive)
		_quick_boost(delta, alive)
		_feet(alive)
		_charge(delta, alive)
		_jump(alive)
	_status_t -= delta
	if _status_t <= 0.0:
		_status_t = STATUS_DT
		_statuses(alive)
	_status_tick(delta)
	_stagger(delta, alive)
	_shield_tick(delta)


func _move_color() -> Color:
	var e := humanoid.bolt_element if humanoid != null else Elem.NONE
	return VfxLib.main_color(e if VfxLib.is_elem(e) else "none").lerp(Color.WHITE, 0.2)


func _rig() -> CharacterRig:
	var r = actor.get("rig")
	return r as CharacterRig if r != null and is_instance_valid(r) else null


## 延迟释放（粒子自然消散）
static func _retire(n: Node, after: float = 1.5) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n is CPUParticles3D:
		(n as CPUParticles3D).emitting = false
		after = (n as CPUParticles3D).lifetime + 0.1
	if n is VfxRibbon:
		(n as VfxRibbon).stop()
		return
	var tw := n.create_tween()
	tw.tween_interval(after)
	tw.tween_callback(n.queue_free)


# ================================================================ 身法

func _boost(alive: bool) -> void:
	var on := alive and _near and humanoid.boosting
	if on and _wake.is_empty():
		var c := _move_color()
		var rig := humanoid.rig
		var specs := [["shin_l", Vector3(0, -0.3, 0.06), 0.28], ["shin_r", Vector3(0, -0.3, 0.06), 0.28], ["spine", Vector3(0, 0.3, 0.2), 0.6]]
		for s in specs:
			var b := rig.bone(s[0])
			var r := VfxRibbon.create(b if b != null else actor, c, s[2], 0.24, "wake", s[1] if b != null else Vector3(0, 1.0, 0.2))
			if r != null:
				r.taper = 0.0
				_wake.append(r)
		_wake_fx = VfxParticles.make("streak", 14, self, c.lerp(Color.WHITE, 0.35))
		_wake_fx.position = Vector3(0, 1.05, 0.2)
		_wake_fx.direction = Vector3(0, 0.15, 1)
		_wake_fx.spread = 14.0
		_wake_fx.initial_velocity_min = 3.0
		_wake_fx.initial_velocity_max = 6.0
		_wake_fx.lifetime = 0.3
		VfxParticles.set_shape(_wake_fx, "sphere", 0.28)
	elif not on and not _wake.is_empty():
		for r in _wake:
			if is_instance_valid(r):
				(r as VfxRibbon).stop()
		_wake.clear()
		_retire(_wake_fx)
		_wake_fx = null


func _quick_boost(delta: float, alive: bool) -> void:
	# 拖尾残影只给玩家（NPC 仅在瞬步起点留一个残影，控制绘制开销）
	if alive and _near and is_player and humanoid.qb_timer > 0.0:
		_ghost_t -= delta
		if _ghost_t <= 0.0 and humanoid.qb_timer < HumanoidActor.QB_TIME - 0.04:
			_ghost_t = 0.11
			FX.afterimage(humanoid.rig, _move_color(), 0.24)
	else:
		_ghost_t = 0.0


func _feet(alive: bool) -> void:
	var mode := ""
	if alive and _near:
		if humanoid.ascending:
			mode = "ascend"
		elif humanoid.hovering:
			mode = "hover"
	if mode != _foot_mode:
		_foot_mode = mode
		if mode == "":
			if _foot != null and is_instance_valid(_foot):
				var tw := _foot.create_tween()
				tw.tween_property(_foot, "instance_shader_parameters/alpha", 0.0, 0.25)
				tw.tween_callback(_foot.queue_free)
			_foot = null
			_retire(_foot_fx)
			_foot_fx = null
		else:
			var c := _move_color()
			if _foot == null:
				_foot = MeshInstance3D.new()
				_foot.mesh = VfxLib.plane()
				_foot.material_override = VfxLib.circle_mat()
				_foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(_foot)
				_foot.position = Vector3(0, 0.04, 0)
				_foot.scale = Vector3(1.8, 1, 1.8)
				_foot.set_instance_shader_parameter("tint", c)
				_foot.set_instance_shader_parameter("glyph", float(VfxLib.pal(humanoid.bolt_element)["glyph"]) if VfxLib.is_elem(humanoid.bolt_element) else 5.0)
				_foot.set_instance_shader_parameter("reveal", 0.0)
				_foot.set_instance_shader_parameter("alpha", 0.0)
				var tw2 := _foot.create_tween()
				tw2.set_parallel(true)
				tw2.tween_property(_foot, "instance_shader_parameters/reveal", 1.0, 0.25)
				tw2.tween_property(_foot, "instance_shader_parameters/alpha", 1.0, 0.15)
			if _foot_fx == null:
				_foot_fx = VfxParticles.make("mote", 18, self, c)
				_foot_fx.position = Vector3(0, 0.05, 0)
				VfxParticles.set_shape(_foot_fx, "ring", 0.6)
				_foot_fx.direction = Vector3.DOWN
				_foot_fx.spread = 20.0
				_foot_fx.damping_min = 0.0
				_foot_fx.damping_max = 0.0
				_foot_fx.initial_velocity_min = 0.3
				_foot_fx.initial_velocity_max = 0.8
				_foot_fx.lifetime = 0.9
			var ascend := mode == "ascend"
			_foot_fx.gravity = Vector3(0, -3.0 if ascend else -0.8, 0)
			_foot_fx.tangential_accel_min = 6.0 if ascend else 2.0
			_foot_fx.tangential_accel_max = 8.0 if ascend else 3.0
			_foot_fx.amount = 18 if ascend else 8
	if _foot != null and is_instance_valid(_foot):
		_foot.set_instance_shader_parameter("spin", _clock * (4.0 if _foot_mode == "ascend" else 1.2))
		var s := 1.8 if _foot_mode == "ascend" else 1.5
		_foot.scale = Vector3(s, 1, s)


func _jump(alive: bool) -> void:
	var g := humanoid.grounded
	if alive and _near and _was_grounded and not g and humanoid.velocity.y > 4.0:
		FX.jump(actor.global_position)
	_was_grounded = g


func _charge(delta: float, alive: bool) -> void:
	var on := alive and _near and humanoid.charging
	if not on:
		if _charge_core != null:
			for n in [_charge_core, _charge_halo]:
				if is_instance_valid(n):
					n.queue_free()
			_retire(_charge_fx)
			_charge_core = null
			_charge_halo = null
			_charge_fx = null
		return
	var e := humanoid.bolt_element if VfxLib.is_elem(humanoid.bolt_element) else "none"
	var c := VfxLib.main_color(e)
	if _charge_core == null:
		_charge_core = _sprite("glow", VfxLib.core_color(e), 0.2)
		_charge_halo = _sprite("flare", c, 0.6)
		_charge_fx = VfxParticles.make("mote", 14, self, c)
		VfxParticles.set_shape(_charge_fx, "shell", 0.75)
		_charge_fx.initial_velocity_min = 0.0
		_charge_fx.initial_velocity_max = 0.0
		_charge_fx.radial_accel_min = -10.0
		_charge_fx.radial_accel_max = -7.0
		_charge_fx.gravity = Vector3.ZERO
		_charge_fx.lifetime = 0.45
		_charge_fx.scale_amount_min = 0.08
		_charge_fx.scale_amount_max = 0.16
	var ratio := humanoid.charge_ratio()
	var rig := humanoid.rig
	var hl := rig.bone("hand_l")
	var pos := (hl.global_position if hl != null else actor.global_position + Vector3.UP * 1.3) + humanoid.forward() * 0.25
	var pulse := 1.0 + 0.12 * sin(_clock * 22.0)
	_charge_core.global_position = pos
	_charge_core.scale = Vector3.ONE * (0.22 + ratio * 0.55) * pulse
	_charge_halo.global_position = pos
	_charge_halo.scale = Vector3.ONE * (0.5 + ratio * 1.5) * pulse
	_charge_halo.set_instance_shader_parameter("fade", 0.45 + ratio * 0.55)
	_charge_fx.global_position = pos
	if ratio >= 1.0:
		_charge_ring_t -= delta
		if _charge_ring_t <= 0.0:
			_charge_ring_t = 0.35
			FX.cam_ring(pos, 0.7, c, 0.25, 0.25)


func _sprite(mat: String, c: Color, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = VfxLib.quad()
	mi.material_override = VfxLib.particle_mat(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.top_level = true
	mi.scale = Vector3.ONE * size
	mi.set_instance_shader_parameter("tint", c)
	return mi


# ================================================================ 状态

func _statuses(alive: bool) -> void:
	var want := {}
	var colors := {}
	if alive and _near and combatant != null:
		for id in combatant.statuses:
			var sid := str(id)
			var stacks := float((combatant.statuses[id] as Dictionary).get("stacks", 1.0))
			match sid:
				"bleed", "poison", "burn", "shock", "qi_burnout", "stone_skin", "bind", "rooted", "regen":
					want[sid] = stacks
			if BUFF_IDS.has(sid) and not want.has("aura"):
				want["aura"] = 1.0
				colors["aura"] = Color.html(str(DB.status(sid).get("color", "#a0e0ff")))
		if want.has("rooted"):
			want.erase("bind")
	# 移除不再需要的
	for k in _fx.keys():
		if not want.has(k) or (colors.has(k) and _fx_color.get(k, Color.BLACK) != colors[k]):
			_remove_status(k)
	# 新增
	for k in want:
		if not _fx.has(k):
			_fx[k] = _create_status(k, float(want[k]), colors.get(k, Color.WHITE))
			_fx_color[k] = colors.get(k, Color.WHITE)
		elif k == "bind":
			_update_bind(float(want[k]))


func _emitter(preset: String, amount: int, c: Color, y: float, shape: String, r: float, h: float = 0.0) -> CPUParticles3D:
	var p := VfxParticles.make(preset, amount, self, c)
	p.position = Vector3(0, y, 0)
	VfxParticles.set_shape(p, shape, r, h)
	return p


func _create_status(k: String, stacks: float, c: Color) -> Array:
	var out: Array = []
	var hs := height / 1.75
	match k:
		"bleed":
			var p := _emitter("blood", clampi(int(8 + stacks * 2), 8, 28), Color(0.85, 0.06, 0.05), height * 0.62, "tube", body_r * 0.95, 0.55 * hs)
			p.direction = Vector3(0, 0.3, 0)
			p.spread = 70.0
			p.initial_velocity_min = 0.8
			p.initial_velocity_max = 2.2
			p.scale_amount_min = 0.07
			p.scale_amount_max = 0.11
			out.append(p)
		"poison":
			var p1 := _emitter("smoke", 8, Color(0.4, 0.72, 0.18), height * 0.5, "tube", body_r * 1.0, 1.0 * hs)
			p1.scale_amount_min = 0.45 * hs
			p1.scale_amount_max = 0.8 * hs
			p1.initial_velocity_max = 0.6
			out.append(p1)
			var b := _emitter("pollen", 10, Color(0.62, 0.95, 0.25), height * 0.5, "tube", body_r * 1.1, 1.0 * hs)
			b.scale_amount_min = 0.08
			b.scale_amount_max = 0.14
			out.append(b)
		"burn":
			var f := _emitter("flame", 16, Color.WHITE, height * 0.42, "tube", body_r * 0.95, 1.0 * hs)
			f.scale_amount_min = 0.5 * hs
			f.scale_amount_max = 0.9 * hs
			out.append(f)
			var em := _emitter("ember", 10, Color(1, 0.8, 0.4), height * 0.5, "tube", body_r, 1.0 * hs)
			em.scale_amount_min = 0.03
			em.scale_amount_max = 0.05
			out.append(em)
			var sm := _emitter("smoke", 4, Color(0.2, 0.17, 0.15), height * 0.85, "tube", body_r * 0.6, 0.3)
			sm.scale_amount_max = 0.9 * hs
			out.append(sm)
		"shock":
			var s := _emitter("spark", 10, Color(0.82, 0.72, 1.0), height * 0.55, "shell", body_r * 1.4)
			s.gravity = Vector3.ZERO
			s.initial_velocity_min = 0.5
			s.initial_velocity_max = 2.0
			s.lifetime = 0.25
			s.scale_amount_min = 0.05
			s.scale_amount_max = 0.08
			out.append(s)
		"regen":
			var g := _emitter("glow", 12, Color(0.5, 1.0, 0.55), 0.1, "ring", body_r * 1.4)
			g.direction = Vector3.UP
			g.spread = 5.0
			g.initial_velocity_min = 0.3
			g.initial_velocity_max = 0.6
			g.gravity = Vector3(0, 1.4, 0)
			g.tangential_accel_min = 4.0
			g.tangential_accel_max = 6.0
			g.damping_min = 0.0
			g.damping_max = 0.0
			g.lifetime = 1.4
			g.scale_amount_min = 0.12
			g.scale_amount_max = 0.2
			out.append(g)
		"aura":
			var a := _emitter("streak", 18, c.lerp(Color.WHITE, 0.2), 0.05, "ring", body_r * 1.3)
			a.direction = Vector3.UP
			a.spread = 4.0
			a.initial_velocity_min = 1.0
			a.initial_velocity_max = 2.6
			a.gravity = Vector3(0, 1.5, 0)
			a.damping_min = 0.0
			a.damping_max = 0.0
			a.lifetime = 0.7
			a.scale_amount_min = 0.06
			a.scale_amount_max = 0.1
			out.append(a)
			var mo := _emitter("mote", 8, c, height * 0.5, "tube", body_r * 1.2, 1.0 * hs)
			out.append(mo)
			var disc := MeshInstance3D.new()
			disc.mesh = VfxLib.plane()
			disc.material_override = VfxLib.particle_mat("flat_glow")
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(disc)
			disc.position = Vector3(0, 0.05, 0)
			disc.scale = Vector3.ONE * body_r * 5.0
			disc.set_instance_shader_parameter("tint", c)
			disc.set_instance_shader_parameter("fade", 0.55)
			out.append(disc)
		"stone_skin":
			var rig := _rig()
			if rig != null:
				rig.set_tint(Color(0.82, 0.72, 0.58), 0.6)
				_tinted = true
		"bind":
			_build_bind(out, stacks)
		"rooted":
			_build_ice_shackles(out)
	return out


func _build_bind(out: Array, stacks: float) -> void:
	var hs := height / 1.75
	for i in 3:
		var ring := MeshInstance3D.new()
		ring.mesh = VfxLib.torus()
		ring.material_override = VfxLib.energy_mat(1)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		ring.position = Vector3(0, (0.22 + i * 0.42) * hs, 0)
		var rr := body_r * (1.25 - i * 0.08)
		ring.scale = Vector3(rr, 0.9, rr)
		ring.rotation = Vector3(randf_range(-0.15, 0.15), randf() * TAU, randf_range(-0.15, 0.15))
		ring.set_instance_shader_parameter("tint", Color(0.4, 0.75, 1.0))
		ring.set_instance_shader_parameter("alpha", 0.0)
		ring.set_meta("ring", i)
		out.append(ring)
	var d := _emitter("droplet", 5, Color(0.7, 0.9, 1.0), height * 0.4, "box", body_r * 0.8, 0.4 * hs)
	d.direction = Vector3.DOWN
	d.initial_velocity_min = 0.2
	d.initial_velocity_max = 0.8
	out.append(d)
	_fx["bind"] = out
	_update_bind(stacks)


func _update_bind(stacks: float) -> void:
	var f := clampf(stacks / 100.0, 0.0, 1.0)
	for n in _fx.get("bind", []):
		if n is MeshInstance3D and is_instance_valid(n) and (n as Node).has_meta("ring"):
			var i := int((n as Node).get_meta("ring"))
			var vis := clampf(f * 3.0 - i, 0.0, 1.0)
			(n as MeshInstance3D).set_instance_shader_parameter("alpha", vis * 1.3)


func _build_ice_shackles(out: Array) -> void:
	var hs := height / 1.75
	var n := 8
	for i in n:
		var a := TAU * i / n + randf_range(-0.2, 0.2)
		var outward := Vector3(sin(a), 0, cos(a))
		var mi := MeshInstance3D.new()
		mi.mesh = VfxLib.spike()
		mi.material_override = VfxLib.ice_mat()
		add_child(mi)
		var up := (Vector3.UP * 1.4 + outward * randf_range(0.3, 0.8)).normalized()
		var length := randf_range(0.55, 0.95) * hs
		var b := FX._basis_fwd(up)
		mi.basis = b
		mi.scale = Vector3(length * 1.5, length * 1.5, 0.02)
		mi.position = outward * body_r * 0.9
		mi.set_instance_shader_parameter("tint", Color(0.6, 0.85, 1.0))
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "scale", Vector3(length * 1.5, length * 1.5, length), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(mi, "position", outward * body_r * 0.9 + up * length * 0.2, 0.12)
		out.append(mi)
	for i in 2:
		var ring := MeshInstance3D.new()
		ring.mesh = VfxLib.torus()
		ring.material_override = VfxLib.ice_mat()
		add_child(ring)
		ring.position = Vector3(0, (0.18 + i * 0.3) * hs, 0)
		var rr := body_r * (1.0 - i * 0.1)
		ring.scale = Vector3(rr, 2.0, rr)
		ring.set_instance_shader_parameter("tint", Color(0.7, 0.9, 1.0))
		out.append(ring)
	var mist := _emitter("mist", 5, Color(0.85, 0.95, 1.0), 0.2, "ring", body_r)
	mist.scale_amount_max = 0.8
	out.append(mist)
	var decal := FX.ground_decal(actor.global_position, 1.0, "frost", 2.0, Color(0.5, 0.8, 1.0), 0.8)
	if decal != null:
		out.append(decal)
	FX.shock_ring(actor.global_position + Vector3.UP * 0.1, 1.4, Color(0.6, 0.85, 1.0), 0.35, 0.2)
	VfxParticles.burst("ice", actor.global_position + Vector3.UP * 0.3, Color(0.85, 0.95, 1.0), 8, {"spread": 60.0, "speed": 0.6})


func _remove_status(k: String) -> void:
	var nodes: Array = _fx.get(k, [])
	_fx.erase(k)
	_fx_color.erase(k)
	if k == "stone_skin" and _tinted:
		var rig := _rig()
		if rig != null:
			rig.set_tint(Color.WHITE, 0.0)
		_tinted = false
	if k == "rooted" and is_inside_tree() and combatant != null and combatant.alive:
		VfxParticles.burst("ice", actor.global_position + Vector3.UP * 0.5, Color(0.85, 0.95, 1.0), 14, {"spread": 180.0, "speed": 0.8})
		VfxParticles.burst("glass", actor.global_position + Vector3.UP * 0.6, Color(0.7, 0.9, 1.0), 8)
	for n in nodes:
		if not is_instance_valid(n):
			continue
		if n is CPUParticles3D:
			_retire(n)
		elif k == "bind" and n is MeshInstance3D:
			var tw := (n as Node).create_tween()
			tw.tween_property(n, "instance_shader_parameters/alpha", 0.0, 0.25)
			tw.tween_callback((n as Node).queue_free)
		elif k == "rooted" and n is MeshInstance3D and (n as MeshInstance3D).get_parent() == self:
			(n as Node).queue_free()
		elif n.get_parent() == self:
			(n as Node).queue_free()


## 周期性小特效：感电电弧、灵力枯竭喷烟、石肤闪光、束缚水环旋转
func _status_tick(delta: float) -> void:
	if _fx.is_empty():
		return
	for k in ["shock", "qi_burnout", "stone_skin"]:
		if not _fx.has(k):
			continue
		var t := float(_tick.get(k, 0.0)) - delta
		if t <= 0.0:
			var center := actor.global_position + Vector3.UP * height * 0.55
			match k:
				"shock":
					t = randf_range(0.15, 0.3)
					var a := center + Vector3(randf_range(-1, 1), randf_range(-0.8, 0.8), randf_range(-1, 1)) * body_r * 1.3
					var b := center + Vector3(randf_range(-1, 1), randf_range(-0.8, 0.8), randf_range(-1, 1)) * body_r * 1.3
					VfxSpells.lightning(a, b, Color(0.8, 0.7, 1.0), 0.09, 0.12, false)
					VfxParticles.burst("spark", a, Color(0.85, 0.78, 1.0), 4, {"speed": 0.5, "life": 0.4})
				"qi_burnout":
					t = randf_range(0.25, 0.55)
					var back := center - (actor.global_basis.z * -1.0) * 0.25
					VfxParticles.burst("smoke", back, Color(0.45, 0.48, 0.58), 2, {"size": 0.45, "speed": 0.6, "life": 0.7})
					VfxParticles.burst("spark", back, Color(0.6, 0.7, 0.9), 4, {"speed": 0.4, "life": 0.5})
				"stone_skin":
					t = randf_range(0.35, 0.7)
					var gp := center + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * Vector3(body_r, height * 0.4, body_r)
					FX.sprite(gp, "flare", Color(1.0, 0.9, 0.6), 0.35, 0.22, 1.2)
		_tick[k] = t
	if _fx.has("bind"):
		for n in _fx["bind"]:
			if n is MeshInstance3D and is_instance_valid(n) and (n as Node).has_meta("ring"):
				(n as Node3D).rotate_y(delta * (2.0 + int((n as Node).get_meta("ring")) * 0.7))


func _stagger(delta: float, alive: bool) -> void:
	var on := alive and _near and str(actor.get("action")) == "stagger"
	if on and _stun == null:
		_stun = Node3D.new()
		add_child(_stun)
		_stun.position = Vector3(0, height + 0.3, 0)
		for i in 5:
			var mi := MeshInstance3D.new()
			mi.mesh = VfxLib.quad()
			mi.material_override = VfxLib.particle_mat("mote")
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_stun.add_child(mi)
			var a := TAU * i / 5.0
			mi.position = Vector3(cos(a), 0, sin(a)) * 0.32 * height / 1.75
			mi.scale = Vector3.ONE * 0.28
			mi.set_instance_shader_parameter("tint", Color(1.0, 0.88, 0.45))
	elif not on and _stun != null:
		_stun.queue_free()
		_stun = null
	if _stun != null:
		_stun.rotate_y(delta * 5.0)


# ================================================================ 护体灵光

func _ensure_shield(c: Color) -> void:
	if _shield != null and is_instance_valid(_shield):
		if c.a > 0.0:
			_shield_mat.set_shader_parameter("tint", c)
		return
	_shield = MeshInstance3D.new()
	_shield.mesh = VfxLib.sphere()
	_shield_mat = VfxLib.new_shield_mat()
	_shield_mat.set_shader_parameter("tint", c if c.a > 0.0 else Color(1.0, 0.88, 0.55))
	_shield_mat.set_shader_parameter("strength", 0.0)
	_shield.material_override = _shield_mat
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shield)
	_shield.position = Vector3(0, height * 0.52, 0)
	_shield.scale = Vector3(body_r * 2.0, height * 0.62, body_r * 2.0)
	_shield_strength = 0.0


## 护体法诀：常驻显示 duration 秒
func show_shield(c: Color, duration: float) -> void:
	_ensure_shield(c)
	_shield_until = _clock + duration
	_shield_target = 1.0
	_shield_flash = 0.8


## 护盾受击：在命中方向产生涟漪
func shield_hit(world_pos: Vector3) -> void:
	if not _near:
		return
	_ensure_shield(Color(0, 0, 0, 0))
	var center := _shield.global_position
	var d := _shield.global_basis.inverse() * (world_pos - center)
	if d.length_squared() < 1e-4:
		d = Vector3.FORWARD
	_hits[_hit_idx] = Vector4(d.normalized().x, d.normalized().y, d.normalized().z, 0.0)
	_hit_idx = (_hit_idx + 1) % 4
	_shield_flash = maxf(_shield_flash, 0.06)
	_shield_until = maxf(_shield_until, _clock + 0.6)


## 护盾被击破
func break_shield(c: Color) -> void:
	var center := actor.global_position + Vector3.UP * height * 0.52
	FX.shield_break(center, c)
	if _shield != null and is_instance_valid(_shield):
		_shield.queue_free()
	_shield = null
	_shield_until = -1.0


func _shield_tick(delta: float) -> void:
	if _shield == null or not is_instance_valid(_shield):
		_shield = null
		return
	var any_hit := false
	for i in 4:
		var h := _hits[i]
		if h.w >= 0.0:
			h.w += delta
			if h.w > 1.2:
				h.w = -1.0
			else:
				any_hit = true
			_hits[i] = h
	_shield_flash = maxf(_shield_flash - delta * 3.0, 0.0)
	var target := _shield_target if _clock < _shield_until else 0.0
	if combatant != null and not combatant.alive:
		target = 0.0
	_shield_strength = move_toward(_shield_strength, target, delta * 4.0)
	if _clock >= _shield_until and not any_hit and _shield_flash <= 0.0 and _shield_strength <= 0.01:
		_shield.queue_free()
		_shield = null
		_shield_target = 0.0
		return
	_shield_mat.set_shader_parameter("strength", _shield_strength)
	_shield_mat.set_shader_parameter("flash", _shield_flash)
	_shield_mat.set_shader_parameter("hits", _hits)


# ================================================================ 境界

func _on_realm_changed(_r: int, _s: int) -> void:
	if GS.player == null or not is_inside_tree():
		return
	var p := GS.player
	if p.realm > _last_realm:
		FX.breakthrough(actor)
	elif p.stage > _last_stage:
		FX.level_up(actor)
	_last_realm = p.realm
	_last_stage = p.stage


## 统计：本组件当前的持续特效节点数
func active_count() -> int:
	var n := _wake.size()
	for k in _fx:
		n += (_fx[k] as Array).size()
	return n + (1 if _shield != null else 0) + (1 if _foot != null else 0) + (3 if _charge_core != null else 0)
