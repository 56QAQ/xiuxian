extends Node
## 系统测试：NPC 名册、好感、门派与任务、掉落、秘境流程。

var runner: Node


func _ok(c: bool, m: String) -> void:
	runner.check(c, m)


func _new_game() -> void:
	GS.new_game({"name": "测试", "roots": {"metal": 60, "water": 40}, "background": "rogue", "seed": 1234})


func test_npc_roster() -> void:
	_new_game()
	var npcs := NpcSystem.npcs()
	_ok(npcs.size() >= 30, "生成了足够的 NPC（%d）" % npcs.size())
	for sid in DB.sects:
		_ok(NpcSystem.by_role(sid, "sect_master") != "", "%s 有掌门" % sid)
		_ok(NpcSystem.by_role(sid, "sect_teacher") != "", "%s 有传功长老" % sid)
	var id: String = npcs.keys()[0]
	var pd := NpcSystem.pd_of(id)
	_ok(pd != null and pd.name != "", "NPC 数据可反序列化")
	NpcSystem.change_favor(id, 45.0)
	_ok(NpcSystem.get_npc(id)["bond"] == "friend", "好感 45 成为好友")
	var line := NpcSystem.gift(id, ItemInstance.create("pill_exp_small", 2))
	_ok(line != "", "赠礼有回应")
	_ok(int(NpcSystem.get_npc(id)["favor"]) > 45, "赠礼增加好感")
	# 离线模拟不报错
	GS.advance_time(24.0 * 40.0)
	_ok(GS.day_index() >= 40, "时间推进")
	# 存档往返保留 NPC
	var d: Dictionary = JSON.parse_string(JSON.stringify(GS.to_dict()))
	GS.from_dict(d)
	NpcSystem.clear_cache()
	_ok(NpcSystem.npcs().size() == npcs.size(), "NPC 名册存档往返")


func test_sect_flow() -> void:
	_new_game()
	_ok(SectSystem.join_block_reason("tianjian") == "", "金灵根可入天剑宗")
	_ok(SectSystem.join_block_reason("qingmu") != "", "无木灵根不可入青木谷")
	_ok(SectSystem.join("tianjian"), "加入天剑宗")
	_ok(GS.player.sect == "tianjian", "门派已设置")
	var board := SectSystem.board("tianjian")
	_ok(board.size() > 0, "任务堂有任务")
	var m: Dictionary = {}
	for attempt in 10:
		for x in board:
			if int(x.get("min_rank", 0)) == 0:
				m = x
				break
		if not m.is_empty():
			break
		GS.advance_time(24.0 * SectSystem.MISSION_REFRESH_DAYS)
		board = SectSystem.board("tianjian")
	_ok(not m.is_empty(), "有可接的任务")
	if m.is_empty():
		return
	_ok(SectSystem.accept(m), "接取任务")
	if m["type"] == "kill":
		for i in int(m["count"]):
			SectSystem.on_enemy_killed(str(m["target"]))
	elif m["type"] == "spar":
		SectSystem.on_spar_won()
	else:
		GS.player.bag.add(ItemInstance.create(str(m["item"]), int(m["count"])))
	_ok(SectSystem.can_turn_in(m), "任务可交付")
	var c0 := SectSystem.contribution()
	_ok(SectSystem.turn_in(m), "交付任务")
	_ok(SectSystem.contribution() > c0, "获得贡献")
	# 晋升
	SectSystem.add_reputation("tianjian", 150)
	_ok(GS.player.sect_rank >= 1, "声望足够晋升外门弟子")
	var lib := SectSystem.library_entries("tianjian")
	_ok(not lib.is_empty(), "藏经阁有条目")
	GS.player.contribution["tianjian"] = 999
	for e in lib:
		if not e["locked"] and not e["learned"]:
			_ok(SectSystem.learn_entry(e), "学习 %s" % e["id"])
			break


func test_loot_roller() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var total := 0
	for tid in DB.loot_tables:
		var items := LootRoller.roll(tid, rng, 5.0, 0.3)
		total += items.size()
		for it in items:
			_ok(not it.def().is_empty(), "掉落物有效 %s" % it.id)
	_ok(total > 0, "掉落表产出物品")


func test_secret_realm_flow() -> void:
	_new_game()
	HitStop.enabled = false
	GS.realm_request = {"realm_id": "herb_valley", "seed": 77}
	var realm: Node3D = load("res://scenes/secret_realm.tscn").instantiate()
	realm.test_mode = true
	get_tree().root.add_child(realm)
	await get_tree().process_frame
	var containers := get_tree().get_nodes_in_group("loot_container")
	_ok(containers.size() >= 10, "容器数量 %d" % containers.size())
	_ok(realm.extracts.size() >= 1, "撤离点存在")
	_ok(get_tree().get_nodes_in_group("combatants").size() >= 3, "秘境中有敌人与修士")
	var player: HumanoidActor = realm.session.player
	_ok(player != null, "玩家已生成")
	# 搜索一个容器
	var lc: LootContainer = containers[0]
	player.global_position = lc.global_position + Vector3(1.0, 0.5, 0)
	lc.interact(player)
	var need := lc.search_time / float(GS.stats.get("search_speed", 1.0)) + 0.5
	var t := 0.0
	while t < need:
		await get_tree().physics_frame
		player.global_position = lc.global_position + Vector3(1.0, 0.3, 0)
		player.combatant.invuln = 1.0
		t += 1.0 / 60.0
	_ok(lc.searched, "搜索完成")
	# 撤离
	var ep: ExtractionPoint = realm.extracts[0]
	var got := [false]
	ep.extracted.connect(func() -> void: got[0] = true)
	t = 0.0
	while t < ep.hold_time + 8.0 and not got[0]:
		player.global_position = ep.global_position + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		player.combatant.invuln = 1.0
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_ok(got[0], "站在撤离阵中完成撤离")
	_ok(GS.player.realms_cleared == 1, "记录撤离次数")
	realm.queue_free()
	HitStop.enabled = true
	HitStop.reset()
	await get_tree().process_frame


func test_encounters() -> void:
	_new_game()
	HitStop.enabled = false
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var arena_script: GDScript = load("res://src/combat/dev_arena.gd")
	arena_script.build_arena(root)
	var session := GameSession.new()
	root.add_child(session)
	session.start(root, Vector3(0, 0.5, 0))
	var player := session.player
	var dir := EncounterDirector.new()
	dir.world = root
	dir.player = player
	dir.enabled = false
	root.add_child(dir)
	await get_tree().physics_frame
	# 切磋
	dir.trigger("spar")
	var npc: HumanoidActor = null
	for a in dir.active:
		if a is HumanoidActor:
			npc = a
	_ok(npc != null, "切磋者出现")
	if npc != null:
		var id := npc.combatant.npc_id
		EncounterDirector.start_spar(player, npc)
		_ok(npc.combatant.is_hostile_to(player.combatant), "切磋中互为对手")
		var f0 := int(NpcSystem.get_npc(id).get("favor", 0))
		for i in 30:
			npc.combatant.invuln = 0.0
			npc.combatant.take_damage({"source": player.combatant, "kind": "env", "flat": 99999.0})
			if not npc.combatant.nonlethal_vs:
				break
		_ok(npc.combatant.alive, "切磋不会致死")
		_ok(int(NpcSystem.get_npc(id).get("favor", 0)) > f0, "切磋获胜增加好感")
		_ok(not npc.combatant.is_hostile_to(player.combatant), "切磋结束后不再敌对")
	# 劫修
	dir.trigger("robber")
	var robbers: Array[HumanoidActor] = []
	for a in dir.active:
		if a is HumanoidActor and a != npc:
			robbers.append(a)
	_ok(robbers.size() >= 1, "劫修出现")
	dir._robber_fight(robbers)
	_ok(robbers[0].combatant.is_hostile_to(player.combatant), "拒绝后劫修敌对")
	# 天材地宝 / 妖兽 / 救援
	dir.trigger("treasure")
	var sites := 0
	for a in dir.active:
		if a is TreasureSite:
			sites += 1
	_ok(sites == 1, "天材地宝出世")
	dir.trigger("beast_attack")
	dir.trigger("rescue")
	var beasts := get_tree().get_nodes_in_group("beasts").size()
	_ok(beasts >= 2, "妖兽出现（%d）" % beasts)
	for i in 120:
		player.combatant.invuln = 1.0
		await get_tree().physics_frame
	root.queue_free()
	HitStop.enabled = true
	HitStop.reset()
	await get_tree().process_frame
