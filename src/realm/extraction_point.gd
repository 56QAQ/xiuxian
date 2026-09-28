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
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 1.4
	cm.height = 30.0
	_beam.mesh = cm
	var m := FX.glow_mat(col).duplicate() as StandardMaterial3D
	m.albedo_color = Color(col.r, col.g, col.b, 0.18 if active else 0.05)
	_beam.material_override = m
	_beam.position.y = 15.0
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
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
		_beam.scale = Vector3.ONE * (1.0 + _t / hold_time * 1.5)
		if _t >= hold_time:
			set_physics_process(false)
			Events.search_progress.emit(-1.0)
			Audio.play("extract")
			extracted.emit()
	elif _t > 0.0:
		_t = 0.0
		_beam.scale = Vector3.ONE
		Events.search_progress.emit(-1.0)
		Events.interaction_prompt.emit("")
