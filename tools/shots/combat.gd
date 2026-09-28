extends RefCounted
## 战斗截图：试炼场中玩家自动出招，截取交战画面（含 HUD）。

var arena: Node


func frames() -> int:
	return 170


func build(root: Node) -> void:
	GS.active = false
	arena = load("res://scenes/dev_arena.tscn").instantiate()
	root.add_child(arena)


func step(_root: Node, i: int) -> void:
	var player: HumanoidActor = arena.session.player
	if player == null or not player.combatant.alive:
		return
	var tgt := CombatUtil.nearest_hostile(player, 80.0)
	player.lock_target = tgt
	if tgt == null:
		return
	var to := tgt.global_position - player.global_position
	to.y = 0
	player.in_move = to.normalized() if to.length() > 2.5 else Vector3.ZERO
	player.in_boost = to.length() > 10.0
	if i % 9 == 0:
		player.in_melee = true
	if i == 60:
		player.in_spell = 1
	if i == 140:
		player.in_spell = 0
	var cam: CameraRig = arena.session.camera
	cam.yaw = lerp_angle(cam.yaw, atan2(-to.x, -to.z) + 0.5, 0.1)
