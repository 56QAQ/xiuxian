extends Node
## 核心系统测试：数据完整性、背包、属性计算、修炼、存档、体素。

var runner: Node


func _ok(c: bool, m: String) -> void:
	runner.check(c, m)


func test_db_loads_without_errors() -> void:
	_ok(DB.errors().is_empty(), "DB 加载错误: %s" % str(DB.errors()))
	_ok(DB.realm_count() >= 3, "至少 3 个大境界")
	_ok(DB.sects.size() == 5, "五大宗门")


func test_data_references() -> void:
	var bad: Array[String] = []
	var need_item := func(id: String, where: String) -> void:
		if not DB.items.has(id):
			bad.append("%s 引用了不存在的物品 %s" % [where, id])
	for bid in DB.backgrounds:
		var bg: Dictionary = DB.backgrounds[bid]
		need_item.call(str(bg.get("bag", "bag_basic")), "出身 " + bid)
		for e in bg.get("items", []):
			need_item.call(str(e[0]), "出身 " + bid)
		for s in bg.get("equip", {}):
			need_item.call(str(bg["equip"][s]), "出身 " + bid)
		for t in bg.get("techniques", []):
			if not DB.techniques.has(t):
				bad.append("出身 %s 功法 %s" % [bid, t])
		for s in bg.get("spells", []):
			if not DB.spells.has(s):
				bad.append("出身 %s 法诀 %s" % [bid, s])
	for sid in DB.sects:
		var s: Dictionary = DB.sects[sid]
		for t in s.get("techniques", []):
			if not DB.techniques.has(t["id"]):
				bad.append("宗门 %s 功法 %s" % [sid, t["id"]])
		for t in s.get("spells", []):
			if not DB.spells.has(t["id"]):
				bad.append("宗门 %s 法诀 %s" % [sid, t["id"]])
		for t in s.get("shop", []):
			need_item.call(str(t["item"]), "宗门商店 " + sid)
		for m in s.get("mission_pool", []):
			if not DB.missions.has(m):
				bad.append("宗门 %s 任务 %s" % [sid, m])
	for lid in DB.loot_tables:
		for e in DB.loot_tables[lid].get("entries", []):
			need_item.call(str(e["item"]), "掉落表 " + lid)
	for rid in DB.recipes:
		var r: Dictionary = DB.recipes[rid]
		for e in r.get("inputs", []):
			need_item.call(str(e[0]), "配方 " + rid)
		need_item.call(str(r["output"][0]), "配方 " + rid)
	for eid in DB.enemies:
		var e: Dictionary = DB.enemies[eid]
		for d in e.get("drops", []):
			need_item.call(str(d["item"]), "敌人 " + eid)
		for w in e.get("weapons", []):
			need_item.call(str(w), "敌人 " + eid)
		for s in e.get("spells", []):
			if not DB.spells.has(s):
				bad.append("敌人 %s 法诀 %s" % [eid, s])
	for sid in DB.spells:
		var sp: Dictionary = DB.spells[sid]
		if sp.has("status") and not DB.statuses.has(sp["status"]["id"]):
			bad.append("法诀 %s 状态 %s" % [sid, sp["status"]["id"]])
		if sp.has("anim") and not AnimLib.has_clip(str(sp["anim"])):
			bad.append("法诀 %s 动作 %s" % [sid, sp["anim"]])
	for mid in DB.movesets:
		for step in DB.movesets[mid]["combo"]:
			if not AnimLib.has_clip(str(step["clip"])):
				bad.append("招式 %s 动作 %s" % [mid, step["clip"]])
	for rid in DB.secret_realms:
		var sr: Dictionary = DB.secret_realms[rid]
		for e in sr.get("enemies", []):
			if not DB.enemies.has(e["id"]):
				bad.append("秘境 %s 敌人 %s" % [rid, e["id"]])
		for t in sr["containers"]["types"]:
			if not DB.loot_tables.has(t["table"]):
				bad.append("秘境 %s 掉落表 %s" % [rid, t["table"]])
	for iid in DB.items:
		var it: Dictionary = DB.items[iid]
		if it.has("teaches"):
			var tt: Dictionary = it["teaches"]
			if tt.has("technique") and not DB.techniques.has(tt["technique"]):
				bad.append("玉简 %s" % iid)
			if tt.has("spell") and not DB.spells.has(tt["spell"]):
				bad.append("玉简 %s" % iid)
		if it.get("use", {}).get("effect", "") == "cast" and not DB.spells.has(it["use"]["spell"]):
			bad.append("符箓 %s" % iid)
	_ok(bad.is_empty(), "数据引用错误:\n" + "\n".join(bad))


func test_inventory_grid() -> void:
	var g := InventoryGrid.new(4, 4)
	var sword := ItemInstance.create("sword_iron")  # 1x4
	_ok(g.place(sword, 0, 0, false), "竖放长剑")
	_ok(not g.can_place(ItemInstance.create("ore_iron"), 0, 0, false), "重叠不可放")
	var ore := ItemInstance.create("ore_iron")  # 2x2
	_ok(g.add(ore) == 0, "自动放入矿石")
	var herbs := ItemInstance.create("herb_lingcao", 7)
	_ok(g.add(herbs) == 0, "放入灵草")
	_ok(g.add(ItemInstance.create("herb_lingcao", 5)) == 0, "堆叠灵草")
	runner.check_eq(g.count_of("herb_lingcao"), 12, "灵草总数")
	_ok(g.take("herb_lingcao", 11), "取出 11")
	runner.check_eq(g.count_of("herb_lingcao"), 1, "剩余灵草")
	_ok(not g.take("herb_lingcao", 5), "数量不足不可取")
	var d := g.to_dict()
	var g2 := InventoryGrid.from_dict(JSON.parse_string(JSON.stringify(d)))
	runner.check_eq(g2.entries.size(), g.entries.size(), "序列化条目数")
	runner.check_eq(g2.count_of("herb_lingcao"), 1, "序列化后数量")
	var rot := InventoryGrid.new(4, 1)
	_ok(rot.add(ItemInstance.create("sword_iron")) == 0, "1x4 物品在 4x1 背包中自动旋转")


func _creation(roots: Dictionary) -> Dictionary:
	return {"name": "测试", "gender": "female", "roots": roots, "background": "rogue", "seed": 42, "talents": ["sword_bone"]}


func test_build_calc_roots() -> void:
	GS.new_game(_creation({"fire": 100}))
	var single := GS.stats.duplicate()
	var p1 := GS.player
	GS.new_game(_creation({"metal": 20, "wood": 20, "water": 20, "fire": 20, "earth": 20}))
	var five := GS.stats.duplicate()
	_ok(single["attack"] > five["attack"], "天灵根火攻击更高")
	_ok(single["cult_speed"] > five["cult_speed"] * 2.5, "天灵根修炼更快")
	_ok(BuildCalc.elem_power(p1, "fire") > 1.5, "天灵根本系威力")
	_ok(BuildCalc.elem_power(GS.player, "water") >= 0.9, "杂灵根五行轮转")
	_ok(single["sword_dmg"] > 0.19, "天赋生效")
	_ok(five["max_hp"] > 0 and five["max_qi"] > 0, "资源为正")


func test_cultivation_flow() -> void:
	GS.new_game(_creation({"fire": 60, "water": 40}))
	var p := GS.player
	runner.check_eq(p.realm, 0, "初始炼气")
	Cultivation.add_exp(p, 260.0)
	runner.check_eq(p.stage, 2, "小境界自动提升两层")
	Cultivation.add_exp(p, 1e7)
	_ok(Cultivation.at_bottleneck(p), "炼气九层圆满瓶颈")
	runner.check_eq(p.stage, 8, "停在九层")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var res := Cultivation.attempt_breakthrough(p, GS.stats, 1.0, rng)
	_ok(res["ok"], "高加成突破成功")
	runner.check_eq(p.realm, 1, "进入筑基")
	_ok(BuildCalc.has_perk(p, "hover"), "筑基解锁御空")


func test_save_roundtrip() -> void:
	GS.new_game(_creation({"metal": 50, "earth": 50}))
	GS.give_item("pill_exp_small", 3, false)
	GS.player.cult_exp = 42.0
	GS.advance_time(30.0)
	var d := GS.to_dict()
	var json := JSON.stringify(d)
	var parsed: Dictionary = JSON.parse_string(json)
	GS.from_dict(parsed)
	runner.check_eq(GS.player.name, "测试", "名字")
	runner.check_eq(GS.player.roots.get("metal"), 50, "灵根")
	runner.check_eq(GS.player.bag.count_of("pill_exp_small"), 3, "物品")
	runner.check_eq(GS.player.equipped("weapon").id, "sword_iron", "装备")
	_ok(absf(GS.hours() - 38.0) < 0.01, "时间")
	_ok(GS.player.spells.has("qi_palm"), "法诀")


func test_voxel_mesher() -> void:
	var g := VoxelGrid.new(3, 3, 3)
	g.set_color(1, 1, 1, Color.RED)
	var m := VoxelMesher.build(g, 1.0)
	runner.check_eq(m.get_surface_count(), 1, "单体素一个表面")
	var arrays := m.surface_get_arrays(0)
	runner.check_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 24, "6 面 24 顶点")
	g.set_color(2, 1, 1, Color.BLUE)
	arrays = VoxelMesher.build(g, 1.0).surface_get_arrays(0)
	runner.check_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 40, "相邻面剔除")
	var c := Color(0.3, 0.6, 0.9, 1.0)
	var back := VoxelGrid.decode(VoxelGrid.encode(c))
	_ok(back.is_equal_approx(Color(c.r, c.g, c.b, 1.0)) or back.r8 == c.r8, "颜色编码往返")


func test_character_rig_bones() -> void:
	var rig := CharacterBuilder.build({}, {"weapon": DB.item("sword_iron")["weapon"]["visual"]})
	add_child(rig)
	for b in CharacterRig.BONES:
		_ok(rig.bone(b) != null, "骨骼 %s" % b)
	_ok(rig.meshes.size() > 10, "网格数量")
	var dur := rig.play("sword_1")
	_ok(dur > 0.1, "播放剪辑")
	rig._process(0.1)
	rig._process(0.1)
	rig.queue_free()
