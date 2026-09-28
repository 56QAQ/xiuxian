extends Node
## 端到端流程检查（真实场景切换）：
##   godot --headless --path . res://tools/playthrough.tscn
## 新游戏 → 大地图 → 存档/读档 → 秘境入口 → 秘境 → 撤离 → 回到大地图 → 死亡复活。
## 退出码 0 表示全部步骤通过。

var _fails: Array[String] = []
var is_driver: bool = false


func _ready() -> void:
	if not is_driver:
		# 本节点是当前场景，会在切换场景时被释放；把流程交给挂在 root 下的驱动节点
		var d: Node = (get_script() as GDScript).new()
		d.is_driver = true
		d.name = "PlaythroughDriver"
		get_tree().root.call_deferred("add_child", d)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_run()


func _check(c: bool, msg: String) -> void:
	print(("  ✓ " if c else "  ✗ ") + msg)
	if not c:
		_fails.append(msg)


func _wait_scene(file: String, timeout: float = 30.0) -> Node:
	var t := 0.0
	while t < timeout:
		var cs := get_tree().current_scene
		if cs != null and cs.scene_file_path == file and cs.is_node_ready():
			return cs
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	HitStop.enabled = false
	var tree := get_tree()
	print("[1] 新游戏 → 大地图")
	GS.new_game({"name": "流程测试", "roots": {"water": 55, "wood": 45}, "background": "rogue", "seed": 4242})
	Scenes.goto_overworld()
	var ow := await _wait_scene(Scenes.OVERWORLD)
	_check(ow != null, "大地图加载")
	if ow == null:
		return _finish()
	await _frames(60)
	var gp: OverworldGameplay = ow.get_node_or_null("Gameplay")
	_check(gp != null and gp.player != null, "玩家在大地图")
	# 打坐一会儿
	gp.player.start_meditate()
	var exp0 := GS.player.cult_exp
	var h0 := GS.hours()
	await _frames(90)
	gp.controller_flush()
	_check(GS.player.cult_exp > exp0 or GS.player.stage > 0, "打坐获得修为")
	_check(GS.hours() > h0, "时间流逝")
	gp.player.stop_meditate()
	print("[2] 存档 / 读档")
	_check(SaveManager.save_game(5), "存档")
	var name0 := GS.player.name
	GS.player.name = "被改掉"
	_check(SaveManager.load_game(5), "读档")
	_check(GS.player.name == name0, "读档恢复数据")
	SaveManager.delete_slot(5)
	print("[3] 进入秘境")
	var portal := WorldMap.find("portal_0")
	_check(not portal.is_empty(), "秘境入口存在")
	GS.player.spirit_stones = 500
	gp._enter_realm(str(portal.get("realm_id", "herb_valley")), 0, portal["pos"])
	var realm := await _wait_scene(Scenes.SECRET_REALM)
	_check(realm != null, "秘境加载")
	if realm == null:
		return _finish()
	await _frames(30)
	_check(GS.in_realm, "处于秘境中")
	var player: HumanoidActor = realm.session.player
	GS.player.bag.add(ItemInstance.create("herb_lingcao", 2))
	var ep: ExtractionPoint = realm.extracts[0]
	var t := 0.0
	while tree.current_scene == realm and t < 20.0:
		player.global_position = ep.global_position + Vector3.UP * 0.3
		player.velocity = Vector3.ZERO
		player.combatant.invuln = 1.0
		await tree.physics_frame
		t += 1.0 / 60.0
	print("[4] 撤离 → 回到大地图")
	ow = await _wait_scene(Scenes.OVERWORLD)
	_check(ow != null, "撤离后回到大地图")
	_check(GS.player.realms_cleared == 1, "记录撤离")
	_check(GS.player.bag.count_of("herb_lingcao") >= 2, "带出的物品保留")
	if ow == null:
		return _finish()
	await _frames(60)
	gp = ow.get_node_or_null("Gameplay")
	var ret: Vector3 = portal["pos"]
	_check(gp != null and gp.player.global_position.distance_to(ret) < 30.0, "回到秘境入口附近")
	print("[5] 死亡与复活")
	gp.player.combatant.kill()
	await tree.create_timer(4.0).timeout
	await _frames(10)
	_check(gp.player != null and is_instance_valid(gp.player) and gp.player.combatant.alive, "在洞府复活")
	_check(GS.player.injury_days > 0.0, "复活后带伤")
	_finish()


func _finish() -> void:
	HitStop.enabled = true
	print("\n流程检查：%s" % ("全部通过" if _fails.is_empty() else "失败 %d 项" % _fails.size()))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)
