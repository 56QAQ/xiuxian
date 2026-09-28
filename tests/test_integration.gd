extends Node
## 集成测试：新游戏 → 大地图（玩家、NPC、交互点、地图、宗门）→ 存档往返。

var runner: Node


func _ok(c: bool, m: String) -> void:
	runner.check(c, m)


func test_overworld_session() -> void:
	HitStop.enabled = false
	GS.new_game({"name": "云游子", "gender": "male", "roots": {"metal": 70, "earth": 30}, "background": "rogue", "seed": 20250917})
	var ow: Node3D = load("res://scenes/overworld.tscn").instantiate()
	get_tree().root.add_child(ow)
	await get_tree().process_frame
	var gp: OverworldGameplay = ow.get_node_or_null("Gameplay")
	_ok(gp != null, "玩法层已创建")
	if gp == null:
		ow.queue_free()
		return
	var player := gp.player
	_ok(player != null and player.is_in_group("player"), "玩家已生成")
	for i in 90:
		await get_tree().physics_frame
	var ground := TerrainGen.shared().get_height(player.global_position.x, player.global_position.z)
	_ok(player.global_position.y > ground - 1.5, "玩家站在地面上（y=%.1f 地面=%.1f）" % [player.global_position.y, ground])
	var inter := get_tree().get_nodes_in_group("interactable").size()
	_ok(inter >= 8, "交互点数量 %d" % inter)
	_ok(GS.location == "home", "出生于洞府附近（%s）" % GS.location)
	# 前往天剑宗山门，宗门 NPC 应当出现
	var sect := WorldMap.sect("tianjian")
	_ok(not sect.is_empty(), "天剑宗 POI")
	var gate: Vector3 = sect["pos"]
	player.global_position = gate + Vector3(0, 3, 0)
	for i in 150:
		player.combatant.invuln = 1.0
		await get_tree().physics_frame
	var master_id := NpcSystem.by_role("tianjian", "sect_master")
	_ok(gp._npc_actors.has(master_id), "掌门已在宗门中出现")
	# 地图参数
	var args := gp._map_args()
	_ok(args["image"] is Image and (args["pois"] as Array).size() >= 10, "地图参数")
	var ui := UIManager.find(get_tree())
	_ok(ui != null, "UI 管理器存在")
	if ui != null:
		ui.open("map")
		await get_tree().process_frame
		_ok(ui.is_open("map"), "地图面板打开")
		ui.open("sect")
		await get_tree().process_frame
		_ok(ui.is_open("sect"), "宗门面板打开")
		ui.close_all()
	# 存档往返
	var d: Dictionary = JSON.parse_string(JSON.stringify(GS.to_dict()))
	_ok(d.has("world") and (d["world"]["npcs"] as Dictionary).size() > 30, "存档包含世界")
	ow.queue_free()
	HitStop.enabled = true
	HitStop.reset()
	await get_tree().process_frame
	await get_tree().process_frame
