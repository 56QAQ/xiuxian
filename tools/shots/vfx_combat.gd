extends RefCounted
## 实战特效截图：试炼场（真实镜头与 HUD），按固定时间线编排一次斗法并定格：
## 玩家近战连段（剑气月牙、命中火花）、对手护体灵光与受击涟漪、灼烧状态、玩家施放流火天降（预警法阵 + 下落陨星）、
## 对手施放火球。--moment=<帧> 可改变定格时刻，--scene=realm 在秘境地形中进行。

var arena: Node
var total: int = 100
var player: HumanoidActor
var foes: Array[HumanoidActor] = []


func frames() -> int:
	return total


func build(root: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--moment="):
			total = int(a.substr(9))
	GS.active = false
	arena = load("res://scenes/dev_arena.tscn").instantiate()
	root.add_child(arena)
	for id in ["gengjin_jianqi", "fireball", "flame_rain", "frost_nova"]:
		GS.learn_spell(id, false)
	GS.set_spell_slot(0, "gengjin_jianqi")
	GS.set_spell_slot(1, "fireball")
	GS.set_spell_slot(2, "flame_rain")
	GS.set_spell_slot(3, "frost_nova")
	VfxShotClock.fix()


func _setup() -> void:
	player = arena.session.player
	player.controller = null
	player.global_position = Vector3(0, 0.1, 6)
	for e in arena.enemies:
		foes.append(e)
		e.controller = null
		var ai: Node = e.get_node_or_null("AI")
		if ai != null:
			ai.queue_free()
	# 近处一名持剑对手（被近战）、右后方一名施法者、左后方一名被流火覆盖
	foes[0].global_position = Vector3(0.9, 0.1, 3.2)
	foes[1].global_position = Vector3(5.5, 0.1, -3.5)
	foes[2].global_position = Vector3(-4.0, 0.1, -5.0)
	for f in foes:
		f.combatant.invuln = 0.0
		var to := player.global_position - f.global_position
		f.rotation.y = atan2(-to.x, -to.z)
		f.set("_yaw", f.rotation.y)
	player.lock_target = foes[0]


func step(_root: Node, i: int) -> void:
	if i == 1:
		_setup()
	if player == null:
		return
	player.combatant.invuln = 1.0
	player.combatant.qi = player.combatant.stat("max_qi")
	for f in foes:
		if is_instance_valid(f):
			f.in_move = Vector3.ZERO
			f.in_boost = false
			f.combatant.hp = maxf(f.combatant.hp, f.combatant.stat("max_hp") * 0.6)
			f.combatant.qi = f.combatant.stat("max_qi")
	var cam: CameraRig = arena.session.camera
	cam.pitch = -15.0
	match i:
		4:
			foes[0].cast_spell("earth_shield", true)
		6:
			foes[2].combatant.apply_status("burn", 3.0, player.combatant)
			foes[1].combatant.apply_status("poison", 4.0, player.combatant)
		30:
			player.lock_target = foes[2]
			player.cast_spell("flame_rain", true)
		52:
			player.lock_target = foes[0]
		80:
			foes[1].lock_target = player
			foes[1].cast_spell("fireball", true)
		84:
			player.call("_begin_step", 1, false)
