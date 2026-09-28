class_name VfxMotion
## 身法与生死表现：瞬步爆环与残影、突进、落地扬尘、起跳、护盾破碎、死亡灵气消散、突破天劫光柱、小境界提升。


static func _chest(actor: Node3D) -> Vector3:
	return actor.global_position + Vector3.UP * 1.0


## 瞬步：垂直于方向的爆环、向后喷射的流光、原地残影、地面扬尘
static func quick_boost(actor: Node3D, dir: Vector3, color: Color) -> void:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var chest := _chest(actor)
	if not FX._visible(chest, 90.0):
		return
	var d := dir.normalized() if dir.length_squared() > 0.01 else -actor.global_basis.z
	FX.shock_ring(chest - d * 0.35, 1.05, color, 0.26, 0.24, d, 0, 0.3)
	FX.shock_ring(chest - d * 0.9, 0.7, color.lerp(Color.WHITE, 0.4), 0.2, 0.3, d, 0, 0.3)
	VfxParticles.burst("streak", chest, color.lerp(Color.WHITE, 0.45), 14, {"dir": -d, "spread": 16.0, "shape": "sphere", "shape_r": 0.35})
	FX.sprite(chest - d * 0.3, "glow", color, 1.6, 0.18, 1.3, 0.6)
	var rig: Node3D = actor.get("rig")
	if rig != null:
		afterimage(rig, color, 0.34)
	if actor.get("grounded") == true:
		VfxParticles.burst("dust", actor.global_position + Vector3.UP * 0.15, Color(0.8, 0.76, 0.68), 6, {"dir": (-d + Vector3.UP * 0.3).normalized(), "spread": 35.0, "speed": 0.9})


## 冲刺类法诀起手（锐金斩、赤焰遁、踏浪步）
static func dash_start(actor: Node3D, dir: Vector3, color: Color) -> void:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var chest := _chest(actor)
	FX.shock_ring(chest, 1.5, color, 0.3, 0.22, dir, 0, 0.3)
	FX.flash(chest, color, 1.2, 0.14)
	VfxParticles.burst("streak", chest, color.lerp(Color.WHITE, 0.4), 16, {"dir": -dir, "spread": 20.0})
	var rig: Node3D = actor.get("rig")
	if rig != null:
		afterimage(rig, color, 0.4)


## 近战锁定突进
static func lunge_start(actor: Node3D, dir: Vector3, color: Color) -> void:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var chest := _chest(actor)
	FX.shock_ring(chest - dir * 0.2, 0.9, color, 0.22, 0.26, dir, 0, 0.3)
	VfxParticles.burst("streak", chest, color.lerp(Color.WHITE, 0.5), 8, {"dir": -dir, "spread": 14.0})
	var rig: Node3D = actor.get("rig")
	if rig != null:
		afterimage(rig, color, 0.26)


## 落地：strength 0~1（按下落速度）
static func land(pos: Vector3, strength: float) -> void:
	var s := clampf(strength, 0.2, 1.5)
	VfxParticles.burst("dust", pos + Vector3.UP * 0.12, Color(0.8, 0.76, 0.68), int(4 + s * 8), {"shape": "ring", "shape_r": 0.3, "speed": 0.7 + s * 0.5, "size": 0.7 + s * 0.4})
	if s > 0.6:
		FX.shock_ring(pos + Vector3.UP * 0.08, 1.2 + s, Color(0.9, 0.87, 0.8), 0.35, 0.25, Vector3.UP, 3)


static func jump(pos: Vector3) -> void:
	VfxParticles.burst("dust", pos + Vector3.UP * 0.1, Color(0.82, 0.78, 0.7), 5, {"shape": "ring", "shape_r": 0.25, "speed": 0.6, "size": 0.6})


## 残影：复制角色当前姿势的体素网格，以灵光材质渐隐
static func afterimage(rig: Node3D, color: Color, life: float = 0.35) -> void:
	var m := FX.mgr()
	if m == null or rig == null or not is_instance_valid(rig) or not rig.is_inside_tree():
		return
	if not m.visible_at(rig.global_position, 40.0):
		return
	var meshes: Array = rig.get("meshes") if rig.get("meshes") != null else []
	if meshes.is_empty():
		return
	var ghost := Node3D.new()
	m.add(ghost)
	var mat := VfxLib.ghost_mat().duplicate() as ShaderMaterial
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("fade", 0.7)
	for src in meshes:
		var mi := src as MeshInstance3D
		if mi == null or not is_instance_valid(mi) or not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var g := MeshInstance3D.new()
		g.mesh = mi.mesh
		g.material_override = mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(g)
		g.transform = mi.global_transform
	var tw := ghost.create_tween()
	tw.tween_property(mat, "shader_parameter/fade", 0.0, life).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(ghost.queue_free)
	m.register_ghost(ghost)


## 护盾破碎：碎光片四散 + 闪光 + 环
static func shield_break(pos: Vector3, color: Color) -> void:
	FX.flash(pos, color, 1.6, 0.16)
	FX.cam_ring(pos, 1.6, color, 0.3, 0.14)
	VfxParticles.burst("glass", pos, color.lerp(Color.WHITE, 0.3), 22, {"shape": "shell", "shape_r": 0.8, "spread": 180.0})
	VfxParticles.burst("spark", pos, color, 14, {"spread": 180.0, "speed": 1.2})


## 死亡：灵气自体内逸散，化作上升的光点（灵气消散）
static func death(actor: Node3D, elem: String) -> void:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var p := actor.global_position
	if not FX._visible(p, 90.0):
		return
	var e := elem if VfxLib.is_elem(elem) else "none"
	var c := VfxLib.main_color("none").lerp(VfxLib.main_color(e), 0.35)
	VfxParticles.burst("mote", p + Vector3.UP * 0.9, c, 26, {"shape": "box", "shape_r": 0.35, "shape_h": 0.7, "dir": Vector3.UP, "spread": 25.0, "speed": 1.0, "grav": Vector3(0, 1.3, 0), "life": 1.8, "expl": 0.5})
	VfxSpells.light_column(p, 0.45, 3.5, c, 1.3, 2, 0.6)
	FX.shock_ring(p + Vector3.UP * 0.1, 1.6, c, 0.6, 0.12)


## 尸身消散：持续 time 秒的上升灵光（配合角色溶解）
static func dissolve(actor: Node3D, time: float) -> void:
	var m := FX.mgr()
	if m == null or actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	if not m.visible_at(actor.global_position, 80.0):
		return
	var p := VfxParticles.make("mote", 30, m, Color(0.75, 0.9, 1.0))
	p.position = actor.global_position + Vector3.UP * 0.5
	VfxParticles.set_shape(p, "box", 0.45, 0.5)
	p.direction = Vector3.UP
	p.spread = 20.0
	p.gravity = Vector3(0, 1.2, 0)
	p.lifetime = 1.6
	var tw := p.create_tween()
	tw.tween_interval(time)
	tw.tween_callback(func() -> void: p.emitting = false)
	tw.tween_interval(2.0)
	tw.tween_callback(p.queue_free)


## 突破大境界：天降光柱 + 天劫雷霆 + 巨型法阵 + 灵气倒灌
static func breakthrough(actor: Node3D) -> void:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var p := actor.global_position
	var gold := Color(1.0, 0.88, 0.55)
	var thunder := VfxLib.main_color("thunder")
	FX.beam_strip(p + Vector3.UP * 80.0, p, gold, 5.0, 3.2, 4, 1.0)
	FX.beam_strip(p + Vector3.UP * 80.0, p, Color(1, 0.97, 0.9), 1.6, 1.6, 0, 1.0)
	FX.magic_circle(p, 4.5, "none", 3.6, {"ground": true, "reveal": 0.8, "spin": 1.2, "glyph": 7, "color": gold, "alpha": 1.0})
	FX.magic_circle(p + Vector3.UP * 3.2, 2.2, "none", 3.0, {"reveal": 0.6, "spin": -2.0, "glyph": 5, "color": gold, "alpha": 0.8})
	FX.flash(p + Vector3.UP * 1.2, gold, 4.0, 0.4)
	FX.flash_light(p + Vector3.UP * 3.0, gold, 8.0, 18.0, 2.5)
	VfxParticles.burst("mote", p + Vector3.UP * 0.2, gold, 60, {"shape": "ring", "shape_r": 4.0, "dir": Vector3.UP, "spread": 10.0, "speed": 2.0, "grav": Vector3(0, 1.0, 0), "radial": Vector2(-3, -2), "life": 2.2, "expl": 0.4})
	# 延迟回调只捕获弱引用：角色提前释放时不会访问已释放对象
	var wr: WeakRef = weakref(actor)
	var is_pl := CombatUtil.is_player(actor)
	for i in 4:
		var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(2.5, 5.5)
		var target := p + off if i < 3 else p
		VfxSpells.later(0.25 + i * 0.45, func() -> void:
			if wr.get_ref() == null:
				return
			VfxSpells.lightning(target + Vector3(randf_range(-4, 4), 45, randf_range(-4, 4)), target, thunder, 0.6, 0.35)
			FX.flash(target + Vector3.UP * 0.5, thunder, 2.5, 0.2)
			FX.shock_ring(target + Vector3.UP * 0.1, 3.0, thunder, 0.45, 0.14)
			FX.flash_light(target + Vector3.UP * 4.0, Color(0.85, 0.8, 1.0), 10.0, 20.0, 0.25)
			if is_pl:
				CombatUtil.shake(0.35)
			Audio.play_at("thunder", target, -4.0))
	VfxSpells.later(2.1, func() -> void:
		var act := wr.get_ref() as Node3D
		if act == null or not act.is_inside_tree():
			return
		FX.shock_ring(act.global_position + Vector3.UP * 0.2, 9.0, gold, 0.8, 0.1)
		FX.cam_ring(act.global_position + Vector3.UP * 1.0, 3.0, gold, 0.5, 0.1)
		VfxParticles.burst("mote", act.global_position + Vector3.UP * 1.0, gold, 40, {"spread": 180.0, "speed": 4.0, "life": 1.5}))


## 小境界提升：法阵 + 螺旋上升的灵光 + 淡光柱
static func level_up(actor: Node3D) -> void:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var p := actor.global_position
	var c := Color(0.75, 0.9, 1.0)
	FX.magic_circle(p, 1.8, "none", 1.8, {"follow": actor, "reveal": 0.4, "spin": 2.0, "color": c})
	VfxSpells.light_column(p, 0.8, 4.5, c, 1.4, 2, 0.8)
	VfxParticles.burst("glow", p + Vector3.UP * 0.1, c, 24, {"shape": "ring", "shape_r": 0.9, "dir": Vector3.UP, "spread": 5.0, "speed": 0.6, "grav": Vector3(0, 2.0, 0), "life": 2.0, "size": 0.45, "expl": 0.3, "tang": Vector2(5, 7), "damp": Vector2.ZERO})
	FX.shock_ring(p + Vector3.UP * 0.1, 2.6, c, 0.6, 0.14)
