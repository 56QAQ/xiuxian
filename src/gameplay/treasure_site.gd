class_name TreasureSite
extends Node3D
## 天材地宝出世之地：冲天光柱，靠近后需持续采集；周围修士互相争夺。

var interact_radius: float = 3.0
var contenders: Array[HumanoidActor] = []
var item_id: String = ""
var collect_time: float = 5.0
var taken: bool = false
var _t: float = 0.0
var _collector: Node3D = null
var _beam: MeshInstance3D
var _age: float = 0.0


static func create(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> TreasureSite:
	var s := TreasureSite.new()
	var cands: Array[String] = []
	for id in DB.items:
		var d: Dictionary = DB.items[id]
		if str(d.get("type", "")) == "treasure" and int(d.get("grade", 0)) <= 2 + GS.player.realm:
			cands.append(id)
	s.item_id = cands[rng.randi() % cands.size()] if not cands.is_empty() else "treasure_sun_fruit"
	parent.add_child(s)
	s.global_position = pos
	return s


func _ready() -> void:
	add_to_group("interactable")
	var col := Grade.color_of(int(DB.item(item_id).get("grade", 2)))
	# 冲天光柱（柔和天光圆柱 + 明亮光芯），地面法阵与上升灵光
	_beam = MeshInstance3D.new()
	_beam.mesh = VfxLib.cone_tube()
	_beam.material_override = VfxLib.energy_mat(2)
	_beam.set_instance_shader_parameter("tint", col)
	_beam.set_instance_shader_parameter("alpha", 1.0)
	_beam.scale = Vector3(1.4, 120.0, 1.4)
	_beam.position.y = 60.0
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	var core := MeshInstance3D.new()
	core.mesh = VfxLib.beam_strip()
	core.material_override = VfxLib.beam_mat(4)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.add_child(core)
	core.transform = Transform3D(FX.scale_local(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.5, 0.5, 1.0)), Vector3(0, -0.5, 0))
	core.set_instance_shader_parameter("tint", col.lerp(Color.WHITE, 0.4))
	core.set_instance_shader_parameter("alpha", 0.8)
	core.set_instance_shader_parameter("len", 120.0)
	FX.magic_circle(global_position, 2.6, "none", 240.0, {"follow": self, "reveal": 1.0, "spin": 0.4, "color": col, "alpha": 0.7, "glyph": 5})
	var motes := VfxParticles.make("mote", 24, self, col)
	motes.position = Vector3(0, 0.3, 0)
	VfxParticles.set_shape(motes, "box", 1.8, 0.2)
	motes.direction = Vector3.UP
	motes.gravity = Vector3(0, 1.2, 0)
	motes.lifetime = 2.2
	var g := VoxelGrid.new(6, 8, 6)
	g.fill_box(Vector3i(2, 0, 2), Vector3i(3, 4, 3), Color(0.3, 0.6, 0.3))
	g.fill_ellipsoid(Vector3(3, 6, 3), Vector3(2.5, 2, 2.5), VoxelGrid.glow(col, 0.9))
	add_child(VoxelMesher.build_instance(g, 0.12, Vector3(-0.36, 0, -0.36)))
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 3.0
	l.omni_range = 10.0
	l.position.y = 1.0
	add_child(l)


func interact_prompt() -> String:
	return "采集 %s" % DB.item(item_id).get("name", "")


func can_interact(_a: Node3D) -> bool:
	return not taken


func interact(a: Node3D) -> void:
	if taken or _collector != null:
		return
	_collector = a
	_t = 0.0
	var rig: CharacterRig = a.get("rig")
	if rig != null:
		rig.play("search")
	Events.notify.emit("开始采集，受到攻击会中断！", "info")


func _process(delta: float) -> void:
	_age += delta
	_beam.rotation.y += delta * 0.5
	if taken:
		return
	# 争夺：到场的修士与玩家互相敌对
	var pl := get_tree().get_first_node_in_group("player") as HumanoidActor
	for c in contenders:
		if not is_instance_valid(c) or not c.combatant.alive:
			continue
		if c.global_position.distance_to(global_position) < 25.0:
			for o in contenders:
				if o != c and is_instance_valid(o):
					c.combatant.add_grudge(o.combatant)
			if pl != null and pl.global_position.distance_to(global_position) < 30.0:
				c.combatant.add_grudge(pl.combatant)
			c.update_nameplate()
	if _collector != null:
		if not is_instance_valid(_collector) or _collector.global_position.distance_to(global_position) > interact_radius + 1.0:
			_cancel()
			return
		var cc := CombatUtil.combatant_of(_collector)
		if cc == null or cc.since_damage < 0.1 or not cc.alive:
			_cancel()
			return
		_t += delta
		Events.search_progress.emit(_t / collect_time)
		if _t >= collect_time:
			_finish()
	# 60 秒后若无人采集，宝物遁走
	if _age > 240.0:
		Events.notify.emit("灵光散去，宝物遁入地脉……", "info")
		queue_free()


func _cancel() -> void:
	_collector = null
	_t = 0.0
	Events.search_progress.emit(-1.0)
	Events.notify.emit("采集被打断！", "warn")


func _finish() -> void:
	taken = true
	Events.search_progress.emit(-1.0)
	if CombatUtil.is_player(_collector):
		GS.give_item(item_id, 1)
		Events.notify.emit("夺得天材地宝：%s！" % DB.item(item_id).get("name", ""), "realm")
		Audio.play("levelup")
	var rig: CharacterRig = _collector.get("rig")
	if rig != null:
		rig.stop_action()
	remove_from_group("interactable")
	var tw := create_tween()
	tw.tween_property(_beam, "scale", Vector3(0.01, 120.0, 0.01), 1.0)
	tw.tween_callback(queue_free)
