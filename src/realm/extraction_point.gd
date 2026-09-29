class_name ExtractionPoint
extends Node3D
## 撤离阵：玩家站在阵中持续 hold_time 秒即撤离。部分阵法需要支付灵石激活。

signal extracted

var radius: float = 3.0
var hold_time: float = 8.0
var cost: int = 0
var active: bool = true
var label: String = "撤离阵"
var _t: float = 0.0
var _ring: MeshInstance3D
var _beam: MeshInstance3D
var _light: OmniLight3D
var _circle: MeshInstance3D
var _motes: CPUParticles3D
var _spin: float = 0.0
var _player: Node3D
var interact_radius: float = 3.5


func _ready() -> void:
	add_to_group("extraction_point")
	if not active:
		add_to_group("interactable")
	_build()


func _build() -> void:
	var col := Color(0.4, 0.95, 0.8) if active else Color(0.7, 0.7, 0.75)
	var g := VoxelGrid.new(14, 2, 14)
	for z in 14:
		for x in 14:
			var d := Vector2(x - 6.5, z - 6.5).length()
			if d < 7.0:
				g.set_color(x, 0, z, Color(0.55, 0.55, 0.58))
			if d > 5.4 and d < 6.6 or (absf(x - 6.5) < 0.6 or absf(z - 6.5) < 0.6) and d < 6.6:
				g.set_color(x, 1, z, VoxelGrid.glow(col, 0.8))
	add_child(VoxelMesher.build_instance(g, 0.45, Vector3(-3.15, -0.2, -3.15)))
	# 光柱：柔和天光圆柱；地面传送阵法阵（撤离读条时加速旋转、变亮）
	_beam = MeshInstance3D.new()
	_beam.mesh = VfxLib.cone_tube()
	_beam.material_override = VfxLib.energy_mat(2)
	_beam.set_instance_shader_parameter("tint", col)
	_beam.set_instance_shader_parameter("alpha", 0.8 if active else 0.2)
	_beam.position.y = 15.0
	_beam.scale = Vector3(1.4, 30.0, 1.4)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_beam.set_meta("base_scale", _beam.scale)
	_circle = MeshInstance3D.new()
	_circle.mesh = VfxLib.plane()
	_circle.material_override = VfxLib.circle_mat()
	_circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_circle)
	_circle.position = Vector3(0, 0.32, 0)
	_circle.scale = Vector3(radius * 2.1, 1, radius * 2.1)
	_circle.set_instance_shader_parameter("tint", col)
	_circle.set_instance_shader_parameter("alpha", 0.75 if active else 0.2)
	_circle.set_instance_shader_parameter("glyph", 5.0)
	if active:
		_motes = VfxParticles.make("mote", 16, self, col)
		_motes.position = Vector3(0, 0.4, 0)
		VfxParticles.set_shape(_motes, "ring", radius * 0.9)
		_motes.direction = Vector3.UP
		_motes.gravity = Vector3(0, 1.5, 0)
		_motes.lifetime = 2.0
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.light_energy = 1.5 if active else 0.3
	_light.omni_range = 8.0
	_light.position.y = 1.5
	add_child(_light)


func interact_prompt() -> String:
	return "以 %d 灵石激活%s" % [cost, label]


func can_interact(_a: Node3D) -> bool:
	return not active


func interact(_a: Node3D) -> void:
	if active:
		return
	if not GS.spend_stones(cost):
		Events.notify.emit("灵石不足", "warn")
		return
	activate()


func activate() -> void:
	active = true
	remove_from_group("interactable")
	for c in get_children():
		c.queue_free()
	_build()
	Audio.play_at("portal", global_position)
	Events.notify.emit("%s已激活" % label, "good")


func _physics_process(delta: float) -> void:
	if not active:
		return
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree() or _player.is_queued_for_deletion():
		_player = null
		for n in get_tree().get_nodes_in_group("player"):
			if not n.is_queued_for_deletion():
				_player = n as Node3D
		return
	var c := CombatUtil.combatant_of(_player)
	var inside := c != null and c.alive and Vector2(_player.global_position.x - global_position.x, _player.global_position.z - global_position.z).length() < radius and absf(_player.global_position.y - global_position.y) < 4.0
	if inside:
		if _t == 0.0:
			Audio.play_at("portal", global_position, -4.0)
		_t += delta
		Events.search_progress.emit(_t / hold_time)
		Events.interaction_prompt.emit("撤离中…… %.1f" % maxf(hold_time - _t, 0.0))
		var bs: Vector3 = _beam.get_meta("base_scale", Vector3.ONE)
		_beam.scale = Vector3(bs.x * (1.0 + _t / hold_time * 1.5), bs.y, bs.z * (1.0 + _t / hold_time * 1.5))
		if _t >= hold_time:
			set_physics_process(false)
			Events.search_progress.emit(-1.0)
			Audio.play("extract")
			extracted.emit()
	elif _t > 0.0:
		_t = 0.0
		_beam.scale = _beam.get_meta("base_scale", Vector3.ONE)
		Events.search_progress.emit(-1.0)
		Events.interaction_prompt.emit("")


## 表现：法阵旋转（撤离读条时加速、变亮）
func _process(delta: float) -> void:
	if _circle == null or not is_instance_valid(_circle):
		return
	var f := clampf(_t / maxf(hold_time, 0.1), 0.0, 1.0) if active else 0.0
	_spin += delta * (0.4 + f * 4.0)
	_circle.set_instance_shader_parameter("spin", _spin)
	if active:
		_circle.set_instance_shader_parameter("alpha", 0.75 + f * 0.6)
