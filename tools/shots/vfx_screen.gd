extends RefCounted
## 屏幕特效截图：试炼场中玩家高速疾行（速度线）并在截图前一刻受到重击冲击（径向模糊 + 色散）。
## --mode=speed 只看速度线；--mode=kick 只看重击；默认两者都有。

var arena: Node
var mode: String = "both"
var total: int = 70


func frames() -> int:
	return total


func build(root: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.substr(7)
	GS.active = false
	arena = load("res://scenes/dev_arena.tscn").instantiate()
	root.add_child(arena)
	VfxShotClock.fix()


func step(_root: Node, i: int) -> void:
	var p: HumanoidActor = arena.session.player
	if p == null:
		return
	p.controller = null
	p.combatant.invuln = 1.0
	p.combatant.qi = p.combatant.stat("max_qi")
	var cam: CameraRig = arena.session.camera
	# 远离敌人方向高速疾行
	var dir := Vector3(-1, 0, 0.35).normalized()
	if mode != "kick":
		p.in_move = dir
		p.in_boost = true
		cam.yaw = lerp_angle(cam.yaw, atan2(-dir.x, -dir.z), 0.2)
		if i == total - 6:
			p.in_qb = true
	if mode != "speed" and i == total - 1:
		cam.impact_kick(1.0)
		FX.hit(p.global_position + Vector3(0, 1.1, -1.2), Vector3.BACK, "fire", 2.0, true)
		FX.crit_burst(p.global_position + Vector3(0, 1.1, -1.2), "fire")
	for e in arena.enemies:
		if is_instance_valid(e):
			e.controller = null
