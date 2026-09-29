class_name VfxSpells
## 法诀表现：施法法阵与手印、符箓、爆炸、爆发（nova）、天降（预警/陨落/落地）、闪电、光柱、
## 领域、光束、召唤物、护体/增益/回复。只负责表现，不涉及任何伤害逻辑。


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## 延迟执行（受时间缩放影响，随场景暂停）
static func later(t: float, c: Callable) -> void:
	var tree := _tree()
	if tree == null:
		return
	if t <= 0.0:
		c.call()
		return
	tree.create_timer(t, false).timeout.connect(c)


static func _ground(pos: Vector3, up: float = 2.0, down: float = 6.0) -> Vector3:
	var hit := CombatUtil.ray_world(pos + Vector3.UP * up, pos + Vector3.DOWN * down)
	return hit["position"] if not hit.is_empty() else Vector3.INF


# ================================================================ 施法

## 起手：脚下法阵 + 双手手印光 + 聚灵光点
static func cast_begin(actor: Node3D, def: Dictionary) -> void:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	if not FX._visible(actor.global_position, 80.0):
		return
	var e := VfxLib.spell_elem(def)
	var c := VfxLib.spell_color(def)
	var kind := str(def.get("kind", ""))
	var ct := float(def.get("cast_time", 0.15))
	var r := 1.05
	if kind in ["shield", "buff", "heal", "summon"]:
		r = 1.35
	elif kind in ["strike", "field", "nova"]:
		r = 1.25
	FX.magic_circle(actor.global_position, r, e, ct + 0.65, {"follow": actor, "reveal": maxf(ct, 0.12) + 0.1, "spin": 2.2, "alpha": 0.9, "color": c})
	var rig: Node3D = actor.get("rig")
	if rig != null and rig is CharacterRig:
		for hb in ["hand_r", "hand_l"]:
			var bone := (rig as CharacterRig).bone(hb)
			if bone != null:
				hand_seal(bone, c, ct + 0.25)
		var hr := (rig as CharacterRig).bone("hand_r")
		if hr != null:
			VfxParticles.burst("mote", hr.global_position, c, 8, {"shape": "shell", "shape_r": 0.55, "speed": 0.0, "radial": Vector2(-9, -6), "grav": Vector3.ZERO, "life": 0.45, "size": 0.6})


## 手印：挂在手骨上的柔光（随手移动）
static func hand_seal(bone: Node3D, color: Color, time: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = VfxLib.quad()
	mi.material_override = VfxLib.particle_mat("glow")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bone.add_child(mi)
	mi.scale = Vector3.ONE * 0.42
	mi.set_instance_shader_parameter("tint", color)
	mi.set_instance_shader_parameter("fade", 0.0)
	var tw := mi.create_tween()
	tw.tween_property(mi, "instance_shader_parameters/fade", 1.0, 0.07)
	tw.tween_interval(maxf(time - 0.3, 0.05))
	tw.tween_property(mi, "instance_shader_parameters/fade", 0.0, 0.22)
	tw.tween_callback(mi.queue_free)
	var fl := MeshInstance3D.new()
	fl.mesh = VfxLib.quad()
	fl.material_override = VfxLib.particle_mat("flare")
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bone.add_child(fl)
	fl.scale = Vector3.ONE * 0.5
	fl.set_instance_shader_parameter("tint", color.lerp(Color.WHITE, 0.4))
	fl.set_instance_shader_parameter("fade", 1.0)
	var tw2 := fl.create_tween()
	tw2.tween_property(fl, "instance_shader_parameters/fade", 0.0, minf(time, 0.35))
	tw2.tween_callback(fl.queue_free)


## 出手：掌前竖立的小法阵 + 闪光 + 沿方向的光线
static func cast_release(origin: Vector3, dir: Vector3, def: Dictionary) -> void:
	if not FX._visible(origin, 80.0):
		return
	var e := VfxLib.spell_elem(def)
	var c := VfxLib.spell_color(def)
	var d := dir.normalized() if dir.length_squared() > 0.01 else Vector3.FORWARD
	FX.magic_circle(origin + d * 0.25, 0.5, e, 0.4, {"normal": d, "reveal": 0.1, "spin": 6.0, "glyph": -1, "color": c, "fade_out": 0.2})
	FX.sprite(origin, "flare", c.lerp(Color.WHITE, 0.3), 0.9, 0.12, 1.4)
	VfxParticles.burst("streak", origin, VfxLib.core_color(e), 6, {"dir": d, "spread": 14.0, "speed": 0.7})


## 符箓：符纸飞散并自燃成火星
static func talisman(actor: Node3D, elem: String) -> void:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var e := elem if VfxLib.is_elem(elem) else "none"
	var chest := actor.global_position + Vector3.UP * 1.25
	var fwd: Vector3 = actor.call("forward") if actor.has_method("forward") else Vector3.FORWARD
	VfxParticles.burst("paper", chest + fwd * 0.3, Color.WHITE, 7, {"dir": (fwd + Vector3.UP * 0.6).normalized(), "spread": 55.0})
	# 主符：向前飞出、悬停、燃尽
	var m := FX.mgr()
	if m == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = VfxLib.quad_tall()
	mi.material_override = VfxLib.particle_mat("paper")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add(mi)
	mi.position = chest + fwd * 0.2
	mi.scale = Vector3.ONE * 0.55
	mi.set_instance_shader_parameter("fade", 1.0)
	var dest := chest + fwd * 0.9 + Vector3.UP * 0.25
	var tw := mi.create_tween()
	tw.tween_property(mi, "position", dest, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(0.12)
	tw.tween_callback(func() -> void:
		FX.flash(dest, VfxLib.main_color(e), 0.9, 0.16)
		VfxParticles.burst("ember", dest, Color(1, 0.75, 0.35), 14, {"spread": 180.0, "speed": 0.8})
		FX.cam_ring(dest, 0.7, VfxLib.main_color(e), 0.22, 0.2))
	tw.tween_property(mi, "instance_shader_parameters/fade", 0.0, 0.12)
	tw.tween_callback(mi.queue_free)


# ================================================================ 爆炸

static func explosion(pos: Vector3, radius: float, elem: String, opts: Dictionary = {}) -> void:
	if not FX._visible(pos, 160.0):
		return
	var e := elem if VfxLib.is_elem(elem) else "none"
	var p := VfxLib.pal(e)
	var main: Color = p["main"]
	var core: Color = p["core"]
	var molten := bool(opts.get("molten", false))
	# 镜头贴近爆炸中心时缩小表现，避免满屏遮挡（可读性优先）
	var cd := FX.cam_pos(pos + Vector3(0, 0, 100)).distance_to(pos)
	var prox := clampf((cd - 1.5) / (radius * 1.6 + 5.0), 0.35, 1.0)
	var r := maxf(radius, 0.5) * lerpf(0.6, 1.0, prox)
	var gp := _ground(pos, 0.6, r * 0.7 + 1.0)
	var on_ground := gp != Vector3.INF
	FX.flash(pos, main, minf(r * 0.8, 4.5), 0.2)
	FX.flash_light(pos + Vector3.UP * 0.6, main, 6.0, r * 3.5, 0.4)
	if on_ground:
		var ring_style := {"fire": 2, "water": 1, "earth": 3}.get(e, 0) as int
		FX.shock_ring(gp + Vector3.UP * 0.12, r * 1.35, main, 0.5, 0.25, Vector3.UP, ring_style)
	var n := clampi(int((8 + r * 4) * prox), 5, 40)
	match e:
		"fire":
			# 火球核心：迅速膨胀的橙色火团
			FX.sprite(pos, "glow", Color(1.0, 0.5, 0.15), r * 0.9, 0.4, 2.2, 0.9)
			VfxParticles.burst("flame", pos, Color.WHITE, n, {"spread": 180.0, "speed": 1.4 + r * 0.45, "size": 1.2 + r * 0.3, "life": 1.0, "shape": "sphere", "shape_r": r * 0.25})
			VfxParticles.burst("ember", pos, Color(1, 0.8, 0.4), n, {"spread": 180.0, "speed": 1.5 + r * 0.2})
			VfxParticles.burst("smoke", pos + Vector3.UP * 0.4, Color(0.22, 0.18, 0.16), clampi(int(4 + r * 1.5), 4, 16), {"spread": 60.0, "speed": 1.2, "size": 1.0 + r * 0.25, "life": 1.3, "shape": "sphere", "shape_r": r * 0.35})
			FX.heat(pos, r * 2.2, 0.9)
			if on_ground:
				FX.ground_decal(gp, r * 0.95, "scorch", 8.0, Color(1.0, 0.4, 0.1), 1.6)
		"earth":
			VfxParticles.burst("debris", pos, Color(0.5, 0.42, 0.32), n, {"spread": 70.0, "speed": 1.1 + r * 0.12, "size": 1.0 + r * 0.15})
			VfxParticles.burst("dust", (gp if on_ground else pos) + Vector3.UP * 0.2, Color(0.72, 0.62, 0.46), clampi(int(5 + r * 2), 5, 20), {"shape": "ring", "shape_r": r * 0.3, "speed": 0.9 + r * 0.15, "size": 1.0 + r * 0.15})
			if molten:
				VfxParticles.burst("ember", pos, Color(1, 0.7, 0.3), n, {"spread": 180.0, "speed": 1.6})
				VfxParticles.burst("flame", pos, Color.WHITE, n / 2, {"spread": 180.0, "speed": 1.5 + r * 0.3, "size": 0.8 + r * 0.2})
			if on_ground:
				FX.ground_decal(gp, r * 0.9, "crack", 8.0, Color(1.0, 0.45, 0.1) if molten else main, 2.0 if molten else 0.6)
		"water":
			VfxParticles.burst("droplet", pos, Color(0.7, 0.9, 1.0), n * 2, {"dir": Vector3.UP, "spread": 70.0, "speed": 1.0 + r * 0.15})
			VfxParticles.burst("mist", pos, Color(0.85, 0.95, 1.0), clampi(int(4 + r * 1.5), 4, 14), {"shape": "ring", "shape_r": r * 0.25, "speed": 0.8 + r * 0.2, "size": 0.9 + r * 0.2})
			VfxParticles.burst("ice", pos, Color(0.8, 0.95, 1.0), n / 2, {"spread": 180.0, "speed": 1.0 + r * 0.1})
			if on_ground:
				FX.ground_decal(gp, r * 0.9, "frost", 6.0, main, 0.8)
		"wood":
			VfxParticles.burst("leaf", pos, Color(0.5, 0.95, 0.45), n, {"speed": 1.2 + r * 0.2, "size": 1.1})
			VfxParticles.burst("pollen", pos, main, n, {"speed": 2.5 + r * 0.4, "shape": "sphere", "shape_r": r * 0.3})
		"metal":
			VfxParticles.burst("spark", pos, Color(1.0, 0.95, 0.7), n * 2, {"spread": 180.0, "speed": 1.3 + r * 0.15})
			VfxParticles.burst("streak", pos, core, n / 2, {"spread": 180.0, "speed": 0.9})
			if on_ground:
				FX.ground_decal(gp, r * 0.7, "crack", 6.0, main, 1.0)
		"thunder":
			VfxParticles.burst("spark", pos, Color(0.85, 0.8, 1.0), n * 2, {"spread": 180.0, "speed": 1.6})
			if on_ground:
				FX.ground_decal(gp, r * 0.8, "scorch", 6.0, main, 1.2)
		_:
			VfxParticles.burst("mote", pos, main, n, {"spread": 180.0, "speed": 2.0 + r * 0.4, "shape": "sphere", "shape_r": r * 0.2})
			VfxParticles.burst("glow", pos, main, n / 2, {"spread": 180.0, "speed": 1.0 + r * 0.2, "size": 1.2})


# ================================================================ 爆发（nova）

## visual：ring / blade / frost / flame / quake
static func nova(pos: Vector3, radius: float, elem: String, visual: String, color: Color = Color(0, 0, 0, 0)) -> void:
	if not FX._visible(pos, 150.0):
		return
	var e := elem if VfxLib.is_elem(elem) else "none"
	var c := color if color.a > 0.0 else VfxLib.main_color(e)
	var gp := _ground(pos, 1.0, 3.0)
	var base := gp if gp != Vector3.INF else pos + Vector3.DOWN * 0.5
	var r := radius
	# 共通：闪光 + 两层地面冲击环 + 脚下法阵一闪
	FX.flash(pos + Vector3.UP * 0.4, c, minf(r * 0.45, 3.0), 0.16)
	FX.shock_ring(base + Vector3.UP * 0.15, r * 1.05, c, 0.45, 0.3, Vector3.UP, {"flame": 2, "frost": 1, "quake": 3}.get(visual, 0))
	FX.shock_ring(base + Vector3.UP * 0.2, r * 1.3, c, 0.6, 0.08)
	FX.magic_circle(base, r * 0.55, e, 0.7, {"reveal": 0.0, "spin": 4.0, "alpha": 0.7, "fade_in": 0.02, "fade_out": 0.5, "color": c})
	FX.flash_light(pos + Vector3.UP, c, 5.0, r * 2.5, 0.35)
	match visual:
		"blade":
			_blade_ring(pos + Vector3.UP * 0.6, r, c)
			VfxParticles.burst("spark", pos + Vector3.UP * 0.8, Color(1.0, 0.95, 0.75), 28, {"spread": 180.0, "flat": 0.6, "speed": 1.6})
		"frost":
			_ice_ring(base, r, c)
			VfxParticles.burst("mist", base + Vector3.UP * 0.3, Color(0.85, 0.95, 1.0), 14, {"shape": "ring", "shape_r": 0.6, "speed": 1.2 + r * 0.25, "size": 1.3})
			FX.ground_decal(base, r * 0.95, "frost", 7.0, c, 0.6)
		"flame":
			# 火环：贴地向外奔涌的火焰（径向加速度推动）
			VfxParticles.burst("flame", base + Vector3.UP * 0.35, Color.WHITE, 40, {"shape": "ring", "shape_r": 0.6, "dir": Vector3.UP, "spread": 20.0, "speed": 0.4, "size": 1.4, "life": 0.85, "grav": Vector3(0, 1.5, 0), "radial": Vector2(r * 9.0, r * 12.0), "damp": Vector2(0.5, 1.0)})
			VfxParticles.burst("ember", base + Vector3.UP * 0.5, Color(1, 0.8, 0.4), 30, {"spread": 90.0, "speed": 1.6 + r * 0.2})
			VfxParticles.burst("smoke", base + Vector3.UP * 0.6, Color(0.2, 0.16, 0.14), 10, {"shape": "ring", "shape_r": r * 0.5, "size": 1.5, "life": 1.4})
			FX.ground_decal(base, r * 0.9, "scorch", 8.0, Color(1.0, 0.4, 0.1), 1.6)
		"quake":
			FX.ground_decal(base, r * 0.95, "crack", 8.0, c, 1.2)
			_rock_ring(base, r)
			VfxParticles.burst("dust", base + Vector3.UP * 0.2, Color(0.72, 0.62, 0.46), 20, {"shape": "ring", "shape_r": 0.8, "speed": 1.3 + r * 0.2, "size": 1.4})
		_:
			VfxParticles.burst("mote", pos, c, 24, {"spread": 180.0, "flat": 0.5, "speed": 2.5 + r * 0.5})
			VfxParticles.burst("dust", base + Vector3.UP * 0.2, Color(0.8, 0.78, 0.72), 12, {"shape": "ring", "shape_r": 0.6, "speed": 1.2 + r * 0.2})


## 剑气纵横：一圈向外飞旋的月牙剑气
static func _blade_ring(center: Vector3, radius: float, c: Color) -> void:
	var m := FX.mgr()
	if m == null:
		return
	var n := 12
	var off := randf() * TAU
	for i in n:
		var a := off + TAU * i / n
		var dir := Vector3(sin(a), 0, cos(a))
		var mi := MeshInstance3D.new()
		mi.mesh = VfxLib.crescent()
		mi.material_override = VfxLib.slash_mat(0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.add(mi)
		mi.position = center + dir * 0.6 + Vector3.UP * randf_range(-0.3, 0.4)
		mi.basis = FX._basis_fwd(dir).rotated(dir, randf_range(-0.5, 0.5)).scaled(Vector3.ONE * 1.9)
		mi.set_instance_shader_parameter("tint", c)
		mi.set_instance_shader_parameter("prog", 0.0)
		var t := 0.34
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "position", center + dir * radius * 0.95 + Vector3.UP * randf_range(-0.2, 0.5), t).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(mi, "instance_shader_parameters/prog", 1.0, t).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mi.queue_free)


## 冰魄寒潮：一圈破地而出的冰锥，片刻后碎裂
static func _ice_ring(base: Vector3, radius: float, c: Color) -> void:
	var m := FX.mgr()
	if m == null:
		return
	var n := clampi(int(radius * 2.0), 8, 16)
	for i in n:
		var a := TAU * i / n + randf_range(-0.15, 0.15)
		var d := radius * randf_range(0.45, 0.85)
		var p := base + Vector3(sin(a) * d, 0, cos(a) * d)
		var g := _ground(p, 2.0, 4.0)
		if g != Vector3.INF:
			p = g
		var outward := Vector3(sin(a), 0, cos(a))
		var up := (Vector3.UP + outward * randf_range(0.3, 0.7)).normalized()
		var len := randf_range(1.3, 2.4) * clampf(radius / 6.0, 0.6, 1.3)
		ice_spike(p, up, len, c, 0.05 + d / radius * 0.12, 0.9)


## 单根冰锥：从地面刺出（delay 后），保持 hold 秒后碎裂
static func ice_spike(pos: Vector3, up: Vector3, length: float, c: Color, delay: float, hold: float) -> MeshInstance3D:
	var m := FX.mgr()
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = VfxLib.spike()
	mi.material_override = VfxLib.ice_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add(mi)
	# 尖端沿 up：网格尖端在 -Z，令 -Z = up
	var b := FX._basis_fwd(up)
	mi.basis = b
	mi.scale = Vector3(length * 1.6, length * 1.6, 0.01)
	mi.position = pos + up * length * 0.2
	mi.set_instance_shader_parameter("tint", c.lerp(Color(0.7, 0.9, 1.0), 0.5))
	mi.set_instance_shader_parameter("prog", 0.0)
	var tw := mi.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(mi, "scale", Vector3(length * 1.6, length * 1.6, length), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(hold)
	tw.tween_callback(func() -> void:
		VfxParticles.burst("ice", pos + up * length * 0.5, Color(0.85, 0.95, 1.0), 6, {"spread": 180.0, "speed": 0.7}))
	tw.tween_property(mi, "instance_shader_parameters/prog", 1.0, 0.18)
	tw.tween_callback(mi.queue_free)
	return mi


## 地裂术：一圈破土而出的岩块
static func _rock_ring(base: Vector3, radius: float) -> void:
	var n := clampi(int(radius * 1.6), 6, 14)
	for i in n:
		var a := TAU * i / n + randf_range(-0.2, 0.2)
		var d := radius * randf_range(0.35, 0.8)
		var p := base + Vector3(sin(a) * d, 0, cos(a) * d)
		var g := _ground(p, 2.0, 4.0)
		if g != Vector3.INF:
			p = g
		rock_spike(p, Vector3(sin(a), 0, cos(a)), randf_range(0.8, 1.6), 0.03 + d / radius * 0.15, 0.7)


## 岩刺：从地面顶出后缓缓沉回
static func rock_spike(pos: Vector3, outward: Vector3, size: float, delay: float, hold: float) -> void:
	var m := FX.mgr()
	if m == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = VfxLib.rock(randi() % 4)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	m.add(mi)
	var tilt := Basis(outward.cross(Vector3.UP).normalized() if outward.length() > 0.1 else Vector3.RIGHT, -randf_range(0.2, 0.5)) * Basis(Vector3.UP, randf() * TAU)
	var sc := Vector3(size * 0.9, size * 2.0, size * 0.9)
	mi.transform = Transform3D(FX.scale_local(tilt, sc), pos + Vector3.DOWN * size * 1.2)
	var up_pos := pos + Vector3.UP * size * 0.35
	var tw := mi.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(mi, "position", up_pos, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(func() -> void:
		VfxParticles.burst("debris", pos + Vector3.UP * 0.3, Color(0.5, 0.43, 0.34), 5, {"size": 0.8}))
	tw.tween_interval(hold)
	tw.tween_property(mi, "position", pos + Vector3.DOWN * size * 1.3, 0.45).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


# ================================================================ 天降（strike）

## 预警法阵（替代旧的平面圆盘）：由内向外绘出，径向填充表示落下时间
static func strike_telegraph(pos: Vector3, radius: float, elem: String, t: float, visual: String, color: Color) -> void:
	FX.magic_circle(pos, radius, elem, t + 0.3, {"ground": true, "fill": t, "reveal": minf(0.45, t * 0.6), "spin": 1.2, "color": color, "alpha": 1.0})
	if visual == "lightning":
		VfxParticles.burst("spark", pos + Vector3.UP * 0.3, Color(0.85, 0.8, 1.0), 8, {"shape": "ring", "shape_r": radius * 0.8, "dir": Vector3.UP, "spread": 20.0, "speed": 0.4, "life": maxf(t, 0.3)})
	elif visual == "pillar" and elem == "water":
		VfxParticles.burst("droplet", pos + Vector3.UP * 0.1, Color(0.7, 0.9, 1.0), 16, {"shape": "ring", "shape_r": radius * 0.9, "dir": Vector3.UP, "spread": 10.0, "speed": 0.8})


## 天降之物：陨星（火）/ 飞剑（金）/ 山岳（土）
static func strike_fall(pos: Vector3, radius: float, elem: String, t: float) -> void:
	var from := pos + Vector3(randf_range(-6, 6), 30, randf_range(-6, 6))
	if elem == "metal":
		from = pos + Vector3(randf_range(-2, 2), 26, randf_range(-2, 2))
	meteor(from, pos, elem, t, clampf(radius / 3.0, 0.7, 3.5))


## 落地表现
static func strike_land(pos: Vector3, radius: float, elem: String, visual: String, color: Color) -> void:
	match visual:
		"lightning":
			var top := pos + Vector3(randf_range(-3, 3), 38, randf_range(-3, 3))
			lightning(top, pos, color, 0.55, 0.32)
			lightning(top + Vector3(randf_range(-4, 4), -6, randf_range(-4, 4)), pos + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), color, 0.25, 0.22)
			FX.flash(pos + Vector3.UP * 0.8, color, radius * 1.3, 0.2)
			FX.flash_light(pos + Vector3.UP * 3.0, color.lerp(Color.WHITE, 0.5), 9.0, radius * 6.0, 0.3)
			FX.shock_ring(pos + Vector3.UP * 0.12, radius * 1.3, color, 0.4, 0.14)
			VfxParticles.burst("spark", pos + Vector3.UP * 0.2, Color(0.9, 0.85, 1.0), 26, {"dir": Vector3.UP, "spread": 80.0, "speed": 1.4})
			FX.ground_decal(pos, radius * 0.8, "scorch", 7.0, color, 1.6)
		"meteor":
			explosion(pos + Vector3.UP * 0.3, radius, elem, {"molten": elem == "earth"})
			if elem == "earth":
				_rock_ring(pos, radius * 0.9)
		_:
			if elem == "water":
				water_prison(pos, radius, color)
			elif elem == "earth":
				for i in 4:
					var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).limit_length(1.0) * radius * 0.6
					rock_spike(pos + off, off.normalized() if off.length() > 0.1 else Vector3.FORWARD, randf_range(0.9, 1.5), i * 0.03, 0.55)
				FX.ground_decal(pos, radius * 0.9, "crack", 6.0, color, 0.8)
				VfxParticles.burst("dust", pos + Vector3.UP * 0.2, Color(0.72, 0.62, 0.46), 12, {"shape": "ring", "shape_r": 0.5, "speed": 1.2})
				FX.shock_ring(pos + Vector3.UP * 0.12, radius * 1.2, color, 0.4, 0.2, Vector3.UP, 3)
			else:
				light_column(pos, radius * 0.7, 9.0, color, 0.8, 0)
				explosion(pos + Vector3.UP * 0.5, radius * 0.8, elem)


## 水牢：旋转升起的水柱 + 水环 + 飞溅
static func water_prison(pos: Vector3, radius: float, c: Color) -> void:
	light_column(pos, radius * 0.75, 6.5, c, 1.3, 1)
	light_column(pos, radius * 0.5, 7.5, Color(0.85, 0.97, 1.0), 1.1, 1)
	var m := FX.mgr()
	if m != null:
		for i in 3:
			var ring := MeshInstance3D.new()
			ring.mesh = VfxLib.torus()
			ring.material_override = VfxLib.energy_mat(1)
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.add(ring)
			ring.position = pos + Vector3.UP * (0.4 + i * 1.6)
			var rr := radius * (0.85 - i * 0.1)
			ring.scale = Vector3(rr, 1.2, rr)
			ring.set_instance_shader_parameter("tint", c)
			ring.set_instance_shader_parameter("alpha", 1.0)
			var tw := ring.create_tween()
			tw.set_parallel(true)
			tw.tween_property(ring, "position:y", ring.position.y + 2.0, 1.2)
			tw.tween_property(ring, "rotation:y", TAU * (1.5 if i % 2 == 0 else -1.5), 1.2)
			tw.tween_property(ring, "instance_shader_parameters/alpha", 0.0, 0.5).set_delay(0.7)
			tw.chain().tween_callback(ring.queue_free)
	VfxParticles.burst("droplet", pos + Vector3.UP * 0.2, Color(0.75, 0.92, 1.0), 40, {"shape": "ring", "shape_r": radius * 0.7, "dir": Vector3.UP, "spread": 25.0, "speed": 1.6})
	VfxParticles.burst("mist", pos + Vector3.UP * 0.3, Color(0.85, 0.95, 1.0), 12, {"shape": "ring", "shape_r": radius * 0.8, "speed": 0.8, "size": 1.3})
	FX.shock_ring(pos + Vector3.UP * 0.1, radius * 1.3, c, 0.6, 0.12, Vector3.UP, 1)
	FX.flash_light(pos + Vector3.UP * 2.0, c, 4.0, radius * 3.0, 0.8)


## 光柱 / 水柱：style 0 灵光，1 水流，2 天光，3 火焰
static func light_column(pos: Vector3, radius: float, height: float, color: Color, time: float, style: int = 0, alpha: float = 1.0) -> void:
	var m := FX.mgr()
	if m == null or not m.visible_at(pos, 200.0):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = VfxLib.tube()
	mi.material_override = VfxLib.energy_mat(style)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add(mi)
	mi.position = pos + Vector3.UP * height * 0.5
	mi.scale = Vector3(radius * 0.25, height, radius * 0.25)
	mi.set_instance_shader_parameter("tint", color)
	mi.set_instance_shader_parameter("alpha", 0.0)
	mi.set_instance_shader_parameter("prog", 0.0)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, height, radius), time * 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(mi, "instance_shader_parameters/alpha", alpha, time * 0.1)
	tw.tween_property(mi, "instance_shader_parameters/prog", 1.0, time * 0.4).set_delay(time * 0.6)
	tw.chain().tween_callback(mi.queue_free)
	FX.shock_ring(pos + Vector3.UP * 0.1, radius * 1.6, color, minf(time * 0.6, 0.6), 0.16)


## 分叉闪电（静态条带，闪烁后消失）
static func lightning(from: Vector3, to: Vector3, color: Color, width: float = 0.3, time: float = 0.25, branches: bool = true) -> void:
	var m := FX.mgr()
	if m == null or not m.visible_at(to, 200.0):
		return
	var pts := _jagged(from, to, 5, 0.22)
	_bolt_mesh(pts, color, width, time)
	if branches:
		var nb := 2 + randi() % 3
		for b in nb:
			var idx := randi_range(int(pts.size() * 0.15), int(pts.size() * 0.7))
			var start := pts[idx]
			var main_dir := (to - from).normalized()
			var side := Vector3(randf_range(-1, 1), randf_range(-0.3, 0.2), randf_range(-1, 1)).normalized()
			var blen := from.distance_to(to) * randf_range(0.12, 0.3)
			var end := start + (main_dir * 0.6 + side * 0.8).normalized() * blen
			_bolt_mesh(_jagged(start, end, 3, 0.3), color, width * 0.45, time * 0.8)


static func _jagged(from: Vector3, to: Vector3, levels: int, rough: float) -> PackedVector3Array:
	var pts := PackedVector3Array([from, to])
	var disp := from.distance_to(to) * rough
	for l in levels:
		var np := PackedVector3Array()
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			np.append(a)
			var mid := (a + b) * 0.5
			var d := (b - a).normalized()
			var perp := d.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))).normalized()
			np.append(mid + perp * randf_range(-disp, disp))
		np.append(pts[pts.size() - 1])
		pts = np
		disp *= 0.5
	return pts


static func _bolt_mesh(pts: PackedVector3Array, color: Color, width: float, time: float) -> void:
	var m := FX.mgr()
	var im := ImmediateMesh.new()
	var cam := FX.cam_pos(pts[0] + Vector3(0, 5, 10))
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := pts.size()
	for i in n:
		var p := pts[i]
		var tan := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		var side := tan.cross(cam - p).normalized()
		var w := width * (1.0 - float(i) / n * 0.4) * 0.5 * 3.0
		im.surface_set_color(color)
		im.surface_set_uv(Vector2(0.1, 0.0))
		im.surface_add_vertex(p - side * w)
		im.surface_set_color(color)
		im.surface_set_uv(Vector2(0.1, 1.0))
		im.surface_add_vertex(p + side * w)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = VfxLib.ribbon_mat("bolt")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add(mi)
	mi.set_instance_shader_parameter("fade", 1.0)
	var tw := mi.create_tween()
	tw.tween_property(mi, "instance_shader_parameters/fade", 0.25, time * 0.25)
	tw.tween_property(mi, "instance_shader_parameters/fade", 1.0, time * 0.15)
	tw.tween_property(mi, "instance_shader_parameters/fade", 0.0, time * 0.6).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


## 陨落物：火（熔岩陨星 + 火尾 + 烟）/ 金（倒插飞剑 + 金光尾迹）/ 土（山岳巨石 + 尘尾）/ 其他（灵光球）
static func meteor(from: Vector3, to: Vector3, elem: String, time: float, size: float = 1.0) -> void:
	var m := FX.mgr()
	if m == null:
		return
	var e := elem if VfxLib.is_elem(elem) else "none"
	var c := VfxLib.main_color(e)
	var holder := Node3D.new()
	m.add(holder)
	holder.position = from
	var dir := (to - from).normalized()
	var body: Node3D
	match e:
		"metal":
			body = VfxLib.sword_node("#fff2c8", 30)
			holder.add_child(body)
			holder.basis = FX._basis_fwd(dir).scaled(Vector3.ONE * clampf(size * 1.4, 1.0, 3.0))
			var r := VfxRibbon.create(holder, c, 0.35 * size, 0.18, "center")
			if r != null:
				r.taper = 0.0
			FX.sprite(from, "glow", c, 1.2, 0.2)
		"earth":
			var mi := MeshInstance3D.new()
			mi.mesh = VfxLib.rock(randi() % 4, false)
			holder.add_child(mi)
			mi.scale = Vector3.ONE * size * 2.6
			body = mi
			var dp := VfxParticles.make("dust", 10, holder, Color(0.7, 0.6, 0.45))
			dp.scale_amount_max = 1.4
			var r2 := VfxRibbon.create(holder, Color(0.9, 0.75, 0.5), size * 1.4, 0.3, "wake")
			if r2 != null:
				r2.taper = 0.1
		"fire":
			var mi2 := MeshInstance3D.new()
			mi2.mesh = VfxLib.rock(randi() % 4, true)
			holder.add_child(mi2)
			mi2.scale = Vector3.ONE * size * 1.3
			body = mi2
			var fl := VfxParticles.make("flame", 24, holder, Color.WHITE)
			fl.scale_amount_min = 0.5 * size
			fl.scale_amount_max = 1.1 * size
			VfxParticles.set_shape(fl, "sphere", 0.35 * size)
			var sm := VfxParticles.make("smoke", 10, holder, Color(0.25, 0.2, 0.18))
			sm.scale_amount_max = 1.6 * size
			VfxParticles.make("ember", 12, holder, Color(1, 0.8, 0.4))
			FX.heat(from, size * 3.0, 0.0, holder)
			# 火尾短而宽（彗尾），避免高速下拉成细长激光
			var r3 := VfxRibbon.create(holder, c, size * 1.4, 0.085, "fire")
			if r3 != null:
				r3.taper = 0.0
			var gl := MeshInstance3D.new()
			gl.mesh = VfxLib.quad()
			gl.material_override = VfxLib.particle_mat("glow")
			holder.add_child(gl)
			gl.scale = Vector3.ONE * size * 3.2
			gl.set_instance_shader_parameter("tint", Color(1.0, 0.55, 0.2))
		_:
			var gl2 := MeshInstance3D.new()
			gl2.mesh = VfxLib.quad()
			gl2.material_override = VfxLib.particle_mat("glow")
			holder.add_child(gl2)
			gl2.scale = Vector3.ONE * size * 2.0
			gl2.set_instance_shader_parameter("tint", c)
			body = gl2
			VfxRibbon.create(holder, c, size * 0.8, 0.3, "center")
	var tw := holder.create_tween()
	tw.set_parallel(true)
	tw.tween_property(holder, "position", to, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if e != "metal" and body != null:
		tw.tween_property(body, "rotation", Vector3(randf_range(3, 7), randf_range(2, 5), randf_range(1, 3)), time)
	tw.chain().tween_callback(func() -> void:
		for ch in holder.get_children():
			if ch is CPUParticles3D:
				(ch as CPUParticles3D).emitting = false
			elif ch is MeshInstance3D and e != "metal":
				(ch as Node3D).visible = false)
	if e == "metal":
		# 飞剑插地后停留片刻再化光消散
		tw.tween_interval(0.5)
		tw.tween_property(holder, "scale", Vector3(0.01, 0.01, 0.01), 0.25)
	else:
		tw.tween_interval(1.2)
	tw.tween_callback(holder.queue_free)


# ================================================================ 领域

## 领域表现：贴地动画圆盘 + 元素粒子 + 元素装饰（木：荆棘；水：冰晶）。返回需要在结束时淡出的节点
static func field_visual(field: Node3D, radius: float, elem: String, color: Color) -> Array[Node]:
	var out: Array[Node] = []
	var e := elem if VfxLib.is_elem(elem) else "none"
	var style := {"wood": 0, "water": 1, "earth": 2, "fire": 3}.get(e, 4) as int
	var disc := MeshInstance3D.new()
	disc.mesh = VfxLib.ground_mesh(field.global_position, radius, 11, randf() * TAU, 0.07)
	disc.material_override = VfxLib.field_mat(style)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	field.add_child(disc)
	disc.set_instance_shader_parameter("tint", color)
	disc.set_instance_shader_parameter("seed", randf())
	disc.set_instance_shader_parameter("alpha", 0.0)
	var tw := disc.create_tween()
	tw.tween_property(disc, "instance_shader_parameters/alpha", 1.0, 0.35)
	out.append(disc)
	var area := maxi(int(radius * radius * 0.6), 6)
	var p: CPUParticles3D
	match e:
		"wood":
			p = VfxParticles.make("leaf", mini(area, 30), field, Color(0.5, 0.95, 0.45))
			p.gravity = Vector3(0, 0.8, 0)
			p.direction = Vector3.UP
			p.spread = 30.0
			p.initial_velocity_min = 0.5
			p.initial_velocity_max = 1.5
			VfxParticles.set_shape(p, "box", radius * 0.8, 0.1)
			out.append(p)
			var p2 := VfxParticles.make("pollen", mini(area, 40), field, color)
			VfxParticles.set_shape(p2, "box", radius * 0.8, 0.5)
			out.append(p2)
			for i in clampi(int(radius * 1.6), 5, 14):
				var a := randf() * TAU
				var d := sqrt(randf()) * radius * 0.85
				out.append(_thorn(field, field.global_position + Vector3(sin(a) * d, 0, cos(a) * d), i * 0.04))
		"water":
			p = VfxParticles.make("mist", mini(area / 2, 24), field, Color(0.85, 0.95, 1.0))
			p.initial_velocity_min = 0.2
			p.initial_velocity_max = 0.6
			VfxParticles.set_shape(p, "box", radius * 0.8, 0.1)
			out.append(p)
			var p3 := VfxParticles.make("mote", mini(area, 40), field, Color(0.8, 0.95, 1.0))
			VfxParticles.set_shape(p3, "box", radius * 0.85, 0.3)
			out.append(p3)
			for i in clampi(int(radius * 1.2), 5, 14):
				var a2 := randf() * TAU
				var d2 := sqrt(randf()) * radius * 0.85
				var sp := field.global_position + Vector3(sin(a2) * d2, 0, cos(a2) * d2)
				var g := _ground(sp, 2.0, 4.0)
				var node := ice_spike(g if g != Vector3.INF else sp, (Vector3.UP + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))).normalized(), randf_range(0.5, 1.1), color, i * 0.03, 60.0)
				if node != null:
					out.append(node)
		"earth":
			p = VfxParticles.make("dust", mini(area / 2, 20), field, Color(0.72, 0.6, 0.42))
			p.tangential_accel_min = 2.0
			p.tangential_accel_max = 4.0
			p.gravity = Vector3(0, 0.3, 0)
			p.initial_velocity_min = 0.2
			p.initial_velocity_max = 0.8
			VfxParticles.set_shape(p, "box", radius * 0.8, 0.1)
			out.append(p)
		"fire":
			p = VfxParticles.make("flame", mini(area, 40), field, Color.WHITE)
			VfxParticles.set_shape(p, "box", radius * 0.8, 0.1)
			out.append(p)
			out.append(VfxParticles.make("ember", mini(area, 30), field, Color(1, 0.8, 0.4)))
			var h := FX.heat(field.global_position, radius * 1.6, 0.0, field)
			if h != null:
				out.append(h)
		_:
			p = VfxParticles.make("mote", mini(area, 30), field, color)
			VfxParticles.set_shape(p, "box", radius * 0.8, 0.2)
			out.append(p)
	FX.shock_ring(field.global_position + Vector3.UP * 0.15, radius, color, 0.45, 0.12)
	return out


## 荆棘（木领域）：暗绿色木刺从地下钻出
static func _thorn(parent: Node3D, pos: Vector3, delay: float) -> Node3D:
	var g := _ground(pos, 2.0, 4.0)
	if g != Vector3.INF:
		pos = g
	var mi := MeshInstance3D.new()
	mi.mesh = VfxLib.spike()
	mi.material_override = VfxLib.debris_mat()
	parent.add_child(mi)
	var up := (Vector3.UP + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))).normalized()
	var len := randf_range(0.7, 1.3)
	var b := FX._basis_fwd(up)
	mi.global_basis = b
	mi.scale = Vector3(len * 1.3, len * 1.3, 0.01)
	mi.global_position = pos + up * len * 0.25
	mi.material_override = _thorn_mat()
	var tw := mi.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(mi, "scale", Vector3(len * 1.3, len * 1.3, len), 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	return mi


static func _thorn_mat() -> StandardMaterial3D:
	var c := FX._mats
	if c.has("thorn"):
		return c["thorn"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.18, 0.35, 0.12)
	m.roughness = 0.8
	m.emission_enabled = true
	m.emission = Color(0.2, 0.6, 0.15)
	m.emission_energy_multiplier = 0.4
	c["thorn"] = m
	return m


## 领域结束：淡出并释放
static func field_fade(nodes: Array[Node], time: float = 0.5) -> void:
	for n in nodes:
		if not is_instance_valid(n):
			continue
		if n is CPUParticles3D:
			(n as CPUParticles3D).emitting = false
		elif n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var tw := mi.create_tween()
			var sh: Shader = (mi.material_override as ShaderMaterial).shader if mi.material_override is ShaderMaterial else null
			if sh == VfxLib.shader("field"):
				tw.tween_property(mi, "instance_shader_parameters/alpha", 0.0, time)
			elif sh == VfxLib.shader("distort"):
				tw.tween_property(mi, "instance_shader_parameters/fade", 0.0, time)
			elif sh != null:
				tw.tween_property(mi, "instance_shader_parameters/prog", 1.0, time)
			else:
				tw.tween_property(mi, "scale", Vector3(0.01, 0.01, 0.01), time).set_ease(Tween.EASE_IN)
			tw.tween_callback(mi.queue_free)


# ================================================================ 光束

## 光束表现节点：主光束、外层光晕、起点与终点光斑、终点粒子、终点灯光
static func beam_visual(owner: Node3D, elem: String, color: Color, width: float) -> Dictionary:
	var e := elem if VfxLib.is_elem(elem) else "none"
	var style := {"fire": 1, "water": 2, "thunder": 3}.get(e, 0) as int
	var vis := {"elem": e, "color": color, "width": width}
	var core := MeshInstance3D.new()
	core.mesh = VfxLib.beam_strip()
	core.material_override = VfxLib.beam_mat(style)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.top_level = true
	owner.add_child(core)
	core.set_instance_shader_parameter("tint", color)
	core.set_instance_shader_parameter("alpha", 1.0)
	core.set_instance_shader_parameter("seed", randf() * 10.0)
	vis["core"] = core
	var sheath := MeshInstance3D.new()
	sheath.mesh = VfxLib.beam_strip()
	sheath.material_override = VfxLib.beam_mat(2 if style == 2 else 4)
	sheath.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sheath.top_level = true
	owner.add_child(sheath)
	sheath.set_instance_shader_parameter("tint", color)
	sheath.set_instance_shader_parameter("alpha", 0.3)
	sheath.set_instance_shader_parameter("seed", randf() * 10.0)
	vis["sheath"] = sheath
	for k in ["start", "end"]:
		var fl := MeshInstance3D.new()
		fl.mesh = VfxLib.quad()
		fl.material_override = VfxLib.particle_mat("flare")
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fl.top_level = true
		owner.add_child(fl)
		fl.set_instance_shader_parameter("tint", color.lerp(Color.WHITE, 0.3))
		vis[k] = fl
		var gl := MeshInstance3D.new()
		gl.mesh = VfxLib.quad()
		gl.material_override = VfxLib.particle_mat("glow")
		gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fl.add_child(gl)
		gl.scale = Vector3.ONE * 1.6
		gl.set_instance_shader_parameter("tint", color)
		gl.set_instance_shader_parameter("fade", 0.7)
	var preset := {"fire": "flame", "water": "droplet", "wood": "leaf", "earth": "debris", "thunder": "spark", "metal": "spark"}.get(e, "glow") as String
	var ep := VfxParticles.make(preset, 18, owner, color.lerp(Color.WHITE, 0.3) if preset != "flame" else Color.WHITE)
	ep.top_level = true
	ep.spread = 70.0
	vis["particles"] = ep
	if e == "fire":
		var sm := VfxParticles.make("smoke", 8, owner, Color(0.25, 0.2, 0.18))
		sm.top_level = true
		vis["smoke"] = sm
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 2.5
	l.omni_range = 5.0 + width * 3.0
	l.top_level = true
	owner.add_child(l)
	vis["light"] = l
	for k in ["core", "sheath", "start", "end"]:
		(vis[k] as Node3D).visible = false
	return vis


static func beam_update(vis: Dictionary, from: Vector3, to: Vector3, hit_surface: bool, t: float) -> void:
	var w := float(vis["width"])
	for k in ["core", "sheath", "start", "end"]:
		(vis[k] as Node3D).visible = true
	var pulse := 1.0 + 0.12 * sin(t * 38.0)
	var ramp := clampf(t / 0.12, 0.0, 1.0)
	FX.set_beam(vis["core"], from, to, w * 0.9 * pulse * ramp)
	FX.set_beam(vis["sheath"], from, to, w * 1.7 * ramp)
	var fs: MeshInstance3D = vis["start"]
	fs.global_position = from
	fs.scale = Vector3.ONE * w * 1.3 * pulse
	var fe: MeshInstance3D = vis["end"]
	fe.global_position = to
	fe.scale = Vector3.ONE * w * (2.0 if hit_surface else 1.2) * pulse
	var ep: CPUParticles3D = vis["particles"]
	ep.global_position = to
	ep.direction = (from - to).normalized()
	ep.emitting = hit_surface or t < 0.2
	if vis.has("smoke"):
		(vis["smoke"] as CPUParticles3D).global_position = to
		(vis["smoke"] as CPUParticles3D).emitting = hit_surface
	var l: OmniLight3D = vis["light"]
	l.global_position = to + (from - to).normalized() * 0.5
	# 命中地面时周期性留下焦痕
	if hit_surface and fmod(t, 0.35) < 0.02:
		var kind := "frost" if vis["elem"] == "water" else "scorch"
		FX.ground_decal(to, w * 1.2, kind, 3.0, vis["color"], 1.0)


static func beam_end(vis: Dictionary) -> void:
	for k in ["core", "sheath", "start", "end", "particles", "smoke", "light"]:
		if vis.has(k) and is_instance_valid(vis[k]):
			var n: Node = vis[k]
			if n is CPUParticles3D:
				# 粒子节点交给管理器，自然消散后释放
				var cp := n as CPUParticles3D
				cp.emitting = false
				var gp := cp.global_position
				var m := FX.mgr()
				if m != null:
					cp.get_parent().remove_child(cp)
					m.add(cp)
					cp.top_level = false
					cp.position = gp
					var tw := cp.create_tween()
					tw.tween_interval(cp.lifetime + 0.2)
					tw.tween_callback(cp.queue_free)
				else:
					cp.queue_free()
			else:
				n.queue_free()


# ================================================================ 召唤物

## 召唤物外观：金 飞剑 / 木 灵叶 / 火 火鸦 / 土 磐石 / 其他 灵光球；附残影拖尾与元素粒子
static func summon_visual(node: Node3D, elem: String, color: Color) -> void:
	var e := elem if VfxLib.is_elem(elem) else "none"
	match e:
		"metal":
			node.add_child(VfxLib.sword_node(color.lightened(0.5).to_html(false), 28))
			var sp := VfxParticles.make("spark", 6, node, Color(1.0, 0.95, 0.7))
			sp.gravity = Vector3.ZERO
			sp.initial_velocity_min = 0.2
			sp.initial_velocity_max = 0.8
		"wood":
			var mi := MeshInstance3D.new()
			mi.mesh = VfxLib.leaf_mesh()
			node.add_child(mi)
			mi.rotation_degrees = Vector3(0, 0, 90)
			VfxParticles.make("pollen", 8, node, color)
		"fire":
			var mi2 := MeshInstance3D.new()
			mi2.mesh = VfxLib.crow_mesh()
			node.add_child(mi2)
			var fl := VfxParticles.make("flame", 12, node, Color.WHITE)
			fl.scale_amount_min = 0.2
			fl.scale_amount_max = 0.4
			VfxParticles.set_shape(fl, "sphere", 0.2)
			VfxParticles.make("ember", 6, node, Color(1, 0.8, 0.4))
		"earth":
			var mi3 := MeshInstance3D.new()
			mi3.mesh = VfxLib.rock(randi() % 4, false)
			mi3.scale = Vector3.ONE * 0.8
			node.add_child(mi3)
			var d := VfxParticles.make("dust", 4, node, Color(0.72, 0.62, 0.46))
			d.scale_amount_max = 0.5
		_:
			var gl := MeshInstance3D.new()
			gl.mesh = VfxLib.quad()
			gl.material_override = VfxLib.particle_mat("glow")
			node.add_child(gl)
			gl.scale = Vector3.ONE * 0.6
			gl.set_instance_shader_parameter("tint", color)
	var glow := MeshInstance3D.new()
	glow.mesh = VfxLib.quad()
	glow.material_override = VfxLib.particle_mat("glow_soft")
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(glow)
	glow.scale = Vector3.ONE * 1.1
	glow.set_instance_shader_parameter("tint", color)
	glow.set_instance_shader_parameter("fade", 0.55)
	var r := VfxRibbon.create(node, color, 0.22 if e != "earth" else 0.4, 0.3, "fire" if e == "fire" else "center")
	if r != null:
		r.taper = 0.0
	FX.flash(node.global_position if node.is_inside_tree() else Vector3.ZERO, color, 0.8, 0.15)


# ================================================================ 护体 / 增益 / 回复

static func shield_cast(actor: Node3D, color: Color, duration: float) -> void:
	var av := FX.vfx_of(actor)
	if av != null:
		av.show_shield(color, duration)
	var p := actor.global_position
	FX.shock_ring(p + Vector3.UP * 0.1, 1.8, color, 0.45, 0.2)
	FX.cam_ring(p + Vector3.UP * 1.0, 1.3, color, 0.3, 0.12)
	VfxParticles.burst("rune", p + Vector3.UP * 0.2, color, 12, {"shape": "ring", "shape_r": 0.9, "dir": Vector3.UP, "spread": 10.0})


static func buff_cast(actor: Node3D, color: Color) -> void:
	var p := actor.global_position
	FX.shock_ring(p + Vector3.UP * 0.1, 1.9, color, 0.5, 0.18)
	VfxParticles.burst("streak", p + Vector3.UP * 0.1, color.lerp(Color.WHITE, 0.3), 16, {"shape": "ring", "shape_r": 0.55, "dir": Vector3.UP, "spread": 8.0, "speed": 0.35, "life": 1.6})
	VfxParticles.burst("mote", p + Vector3.UP * 0.8, color, 14, {"shape": "sphere", "shape_r": 0.5, "speed": 1.2})
	FX.sprite(p + Vector3.UP * 1.0, "glow", color, 2.2, 0.35, 1.3, 0.6)


## 回复：绿色光点螺旋上升 + 脚下光环
static func heal(actor: Node3D, color: Color) -> void:
	var p := actor.global_position
	VfxParticles.burst("mote", p + Vector3.UP * 0.1, color, 26, {"shape": "ring", "shape_r": 0.7, "dir": Vector3.UP, "spread": 15.0, "speed": 1.2, "grav": Vector3(0, 1.4, 0), "life": 1.4, "expl": 0.35})
	VfxParticles.burst("glow", p + Vector3.UP * 0.1, color, 16, {"shape": "ring", "shape_r": 0.6, "dir": Vector3.UP, "spread": 5.0, "speed": 0.5, "grav": Vector3(0, 1.8, 0), "life": 2.4, "size": 0.5, "expl": 0.2, "tang": Vector2(4, 6), "damp": Vector2.ZERO})
	FX.shock_ring(p + Vector3.UP * 0.1, 1.6, color, 0.6, 0.2)
	FX.sprite(p + Vector3.UP * 1.0, "glow", color, 2.0, 0.4, 1.2, 0.5)
