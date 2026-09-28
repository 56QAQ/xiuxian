extends RefCounted
## 秘境实战截图：玩家传送到最近的妖兽附近并交战。--realm=<id>

var realm: Node
var target: Node3D


func frames() -> int:
	return 200


func build(root: Node) -> void:
	GS.active = false
	var rid := "herb_valley"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--realm="):
			rid = a.substr(8)
	GS.new_game({"name": "赵灵儿", "roots": {"fire": 60, "metal": 40}, "background": "clan", "seed": 11})
	GS.player.equipment["weapon"] = ItemInstance.create("flag_spear_fire")
	GS.player.equipment["armor"] = ItemInstance.create("armor_crimson")
	GS.learn_spell("fireball", false)
	GS.set_spell_slot(1, "fireball")
	GS.recompute()
	GS.realm_request = {"realm_id": rid, "seed": 5150}
	realm = load("res://scenes/secret_realm.tscn").instantiate()
	realm.test_mode = true
	root.add_child(realm)


func step(_root: Node, i: int) -> void:
	var p: HumanoidActor = realm.session.player
	if p == null or not p.combatant.alive:
		return
	p.combatant.invuln = 0.5
	if i == 3:
		var best: Node3D = null
		for b in realm.get_tree().get_nodes_in_group("beasts"):
			if best == null or (b as Node3D).global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position):
				best = b
		target = best
		if target != null:
			p.global_position = target.global_position + Vector3(6, 2, 6)
	if target == null or not is_instance_valid(target):
		target = CombatUtil.nearest_hostile(p, 60.0)
		if target == null:
			return
	p.lock_target = target
	var to := target.global_position - p.global_position
	to.y = 0
	p.in_move = to.normalized() if to.length() > 3.0 else Vector3.ZERO
	if i % 10 == 0:
		p.in_melee = true
	if i == 120:
		p.in_spell = 1
	var cam: CameraRig = realm.session.camera
	cam.yaw = lerp_angle(cam.yaw, atan2(-to.x, -to.z) + 0.35, 0.15)
	cam.pitch = -12.0
