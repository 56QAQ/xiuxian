class_name SearchTask
extends Node
## 搜索读条：角色蹲下搜索，移动/受击会打断；神识越高搜索越快。

var container: LootContainer
var actor: Node3D
var t: float = 0.0
var need: float = 3.0
var _hp0: float = 0.0


func _ready() -> void:
	var speed := float(GS.stats.get("search_speed", 1.0)) if CombatUtil.is_player(actor) else 1.0
	need = container.search_time / maxf(speed, 0.2)
	var c := CombatUtil.combatant_of(actor)
	_hp0 = c.hp + c.shield if c != null else 0.0
	var rig: CharacterRig = actor.get("rig")
	if rig != null:
		rig.play("search")
	if actor.get("action") != null:
		actor.set("action", "channel")
		actor.set("channel_t", need + 0.2)
	Audio.play_at("search_tick", actor.global_position, -8.0)


func _process(delta: float) -> void:
	if not is_instance_valid(container) or not is_instance_valid(actor):
		_end(false)
		return
	var c := CombatUtil.combatant_of(actor)
	var moved := false
	var in_move = actor.get("in_move")
	if in_move is Vector3 and (in_move as Vector3).length() > 0.3:
		moved = true
	if c != null and (not c.alive or c.hp + c.shield < _hp0 - 0.5):
		moved = true
	if actor.global_position.distance_to(container.global_position) > container.interact_radius + 1.0:
		moved = true
	if moved:
		Events.notify.emit("搜索被打断", "warn")
		_end(false)
		return
	t += delta
	if int(t * 2.0) != int((t - delta) * 2.0):
		Audio.play_at("search_tick", actor.global_position, -12.0)
	Events.search_progress.emit(t / need)
	if t >= need:
		_end(true)


func _end(ok: bool) -> void:
	Events.search_progress.emit(-1.0)
	var rig: CharacterRig = actor.get("rig") if is_instance_valid(actor) else null
	if rig != null:
		rig.stop_action()
	if is_instance_valid(actor) and actor.get("action") == "channel":
		actor.set("action", "")
	if ok and is_instance_valid(container):
		container.finish_search()
	queue_free()
