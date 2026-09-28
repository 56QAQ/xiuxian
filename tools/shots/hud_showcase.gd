extends RefCounted
## HUD 截图：试炼场中固定一个战斗瞬间，逐项展示中央玉璧（生命残痕、灵力、八卦护体、韧性、状态印章）、
## 八卦锁定环与悬牌、符纸法诀栏、罗盘、伤害跳字（普通/五行/暴击/治疗）、命中笔触与“斩”印、受击方向。
## 参数：--variant=full（默认）| low（低血量渗墨）| burn（灵力枯竭）| calm（满状态、无目标）
##       --dark（夜色场景，检查暗背景下的可读性）

var arena: Node
var variant := "full"
var dark := false


func frames() -> int:
	return 70


func build(root: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--variant="):
			variant = a.substr(10)
		elif a == "--dark":
			dark = true
	GS.active = false
	arena = load("res://scenes/dev_arena.tscn").instantiate()
	root.add_child(arena)


func step(_root: Node, i: int) -> void:
	var session: GameSession = arena.session
	if session == null or session.player == null:
		return
	var p := session.player
	var c := p.combatant
	c.invuln = 1.0
	if i == 2:
		if dark:
			_darken()
		for e in arena.enemies:
			(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		# 敌人排开在玩家前方
		var slots := [Vector3(-3.5, 0.5, 1.5), Vector3(0.6, 0.5, -1.0), Vector3(4.5, 0.5, 2.0)]
		for k in arena.enemies.size():
			(arena.enemies[k] as Node3D).global_position = slots[k]
			(arena.enemies[k] as Node3D).rotation.y = 0.0
		p.global_position = Vector3(0, 0.5, 8)
		p.rotation.y = 0.0
	if i >= 3:
		p.in_move = Vector3.ZERO
		var cam: CameraRig = session.camera
		cam.yaw = 0.12
		cam.pitch = -10.0
	var tgt: HumanoidActor = arena.enemies[1] if arena.enemies.size() > 1 else null
	if variant != "calm" and tgt != null:
		p.lock_target = tgt
		tgt.combatant.hp = tgt.combatant.stat("max_hp") * 0.62
		tgt.combatant.shield = tgt.combatant.stat("max_shield") * 0.4
	if i == 62 and variant != "calm":
		c.apply_status("burn", 3, null)
		c.apply_status("bleed", 2, null)
		c.apply_status("swift", 1, null)
		c.apply_status("regen", 1, null)
		if tgt != null:
			tgt.combatant.apply_status("poison", 4, null)
			tgt.combatant.apply_status("armor_break", 2, null)
	# 生命：先高后低，制造失血残痕
	var max_hp := c.stat("max_hp")
	if variant == "calm":
		c.hp = max_hp
		c.qi = c.stat("max_qi")
		c.shield = c.stat("max_shield")
	elif variant == "low":
		c.hp = max_hp * (0.62 if i < 60 else 0.18)
		c.qi = c.stat("max_qi") * 0.4
		c.shield = 0.0
	elif variant == "burn":
		c.hp = max_hp * 0.7
		c.qi = c.stat("max_qi") * 0.03
		c.shield = c.stat("max_shield") * 0.25
		if i == 66:
			c.apply_status("qi_burnout", 1, null)
	else:
		c.hp = max_hp * (0.85 if i < 67 else 0.56)
		c.qi = c.stat("max_qi") * 0.64
		c.shield = c.stat("max_shield") * 0.62
		c.poise = c.stat("poise") * 0.55
	if variant == "full" and i >= 50:
		p.boosting = true
	if i == 67 and variant != "calm" and tgt != null:
		var hp_pos := tgt.global_position + Vector3.UP * 1.4
		Events.hit_landed.emit({"pos": hp_pos + Vector3(-0.6, 0.2, 0), "amount": 46.0, "crit": false, "kind": "melee", "element": "none",
			"shield": false, "target": tgt, "source": p, "killed": false, "provoked": false})
		Events.hit_landed.emit({"pos": hp_pos + Vector3(0.7, 0.5, 0), "amount": 88.0, "crit": false, "kind": "spell", "element": "fire",
			"shield": false, "target": tgt, "source": p, "killed": false, "provoked": false})
		var far: HumanoidActor = arena.enemies[2]
		Events.hit_landed.emit({"pos": far.global_position + Vector3.UP * 1.5, "amount": 212.0, "crit": true, "kind": "melee", "element": "none",
			"shield": false, "target": far, "source": p, "killed": variant == "full", "provoked": false})
		Events.hit_landed.emit({"pos": p.global_position + Vector3.UP * 1.2, "amount": 31.0, "crit": false, "kind": "melee", "element": "none",
			"shield": false, "target": p, "source": arena.enemies[0], "killed": false, "provoked": false})
		session.numbers.show_heal(p.global_position + Vector3(0.5, 2.0, 0), 60.0)


func _darken() -> void:
	for n in arena.get_children():
		if n is WorldEnvironment:
			var e: Environment = (n as WorldEnvironment).environment
			var sm := (e.sky.sky_material as ProceduralSkyMaterial)
			sm.sky_top_color = Color(0.02, 0.03, 0.07)
			sm.sky_horizon_color = Color(0.06, 0.07, 0.12)
			sm.ground_horizon_color = Color(0.04, 0.04, 0.06)
			sm.ground_bottom_color = Color(0.01, 0.01, 0.02)
			e.ambient_light_energy = 0.15
			e.fog_light_color = Color(0.05, 0.06, 0.1)
		elif n is DirectionalLight3D:
			(n as DirectionalLight3D).light_energy = 0.12
			(n as DirectionalLight3D).light_color = Color(0.6, 0.7, 1.0)
