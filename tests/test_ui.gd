extends Node
## 界面层测试：捏人点数与灵根分配、背包拖放模型逻辑、生产、物品操作、UIManager 行为、所有面板实例化/释放。

var runner: Node


func _ok(c: bool, m: String) -> void:
	runner.check(c, m)


func _eq(a: Variant, b: Variant, m: String) -> void:
	runner.check_eq(a, b, m)


func _new_game(bg: String = "rogue") -> void:
	GS.new_game({"name": "测试", "gender": "female", "roots": {"fire": 60, "wood": 40}, "background": bg, "seed": 99, "talents": []})


# ================================================================ 捏人

func test_creator_point_budget() -> void:
	var attrs := {"con": 5, "int": 5, "spi": 5, "agi": 5, "luk": 5}
	var two := {"fire": 60, "wood": 40}
	_eq(CreatorLogic.spent(attrs, [], two), 3, "双灵根花费 3")
	_eq(CreatorLogic.remaining(attrs, [], two), 9, "剩余 9")
	attrs["con"] = 8
	_eq(CreatorLogic.attr_cost(attrs), 3, "根骨 8 花 3 点")
	attrs["luk"] = 3
	_eq(CreatorLogic.attr_cost(attrs), 1, "气运 3 返还 2 点")
	_eq(CreatorLogic.remaining(attrs, [], two), 8, "剩余 8")
	_eq(CreatorLogic.talent_cost(["sword_bone", "lone_star"]), 0, "天生剑骨 3 + 天煞孤星 -3")
	_eq(CreatorLogic.root_cost({"fire": 100}), 6, "天灵根 6 点")
	_eq(CreatorLogic.root_cost({"metal": 20, "wood": 20, "water": 20, "fire": 20, "earth": 20}), -2, "五行杂灵根返还 2 点")
	_eq(CreatorLogic.remaining({"con": 5, "int": 5, "spi": 5, "agi": 5, "luk": 5}, [], {"metal": 20, "wood": 20, "water": 20, "fire": 20, "earth": 20}), 14, "杂灵根剩余 14")
	# 上下限
	_ok(not CreatorLogic.can_raise({"con": 10}, "con", 5), "属性上限 10")
	_ok(not CreatorLogic.can_raise({"con": 5}, "con", 0), "无点数不能加")
	_ok(not CreatorLogic.can_lower({"con": 1}, "con"), "属性下限 1")
	_ok(CreatorLogic.can_lower({"con": 5}, "con"), "可降低")
	# 天赋可选性
	_ok(CreatorLogic.can_toggle_talent([], "lone_star", 0), "缺陷总可选")
	_ok(not CreatorLogic.can_toggle_talent([], "sword_bone", 2), "点数不足不可选")
	_ok(CreatorLogic.can_toggle_talent(["sword_bone"], "sword_bone", -5), "已选总可取消")
	# 校验
	var base := {"con": 5, "int": 5, "spi": 5, "agi": 5, "luk": 5}
	_eq(CreatorLogic.validate("甲", base, [], two, "rogue", ""), "", "合法创建")
	_ok(CreatorLogic.validate("", base, [], two, "rogue", "") != "", "空名不可")
	var over := {"con": 10, "int": 10, "spi": 5, "agi": 5, "luk": 5}
	_ok(CreatorLogic.validate("甲", over, [], two, "rogue", "") != "", "超支不可确认")
	_ok(CreatorLogic.validate("甲", base, [], two, "servant", "") != "", "宗门杂役须选宗门")
	_eq(CreatorLogic.validate("甲", base, [], two, "servant", "tianjian"), "", "杂役选定宗门")
	_ok(CreatorLogic.validate("甲", base, [], {"fire": 60, "wood": 30}, "rogue", "") != "", "灵根合计须 100")


func test_creator_root_distribution() -> void:
	var r := CreatorLogic.set_root({"fire": 60, "wood": 40}, "fire", 75)
	_eq(r, {"wood": 25, "fire": 75}, "双灵根调整")
	r = CreatorLogic.set_root({"metal": 30, "water": 30, "fire": 40}, "fire", 99)
	_eq(int(r["fire"]), 90, "三灵根单系上限 90")
	_eq(int(r["metal"]) + int(r["water"]), 10, "其余各 5")
	r = CreatorLogic.set_root({"metal": 20, "water": 30, "fire": 50}, "fire", 60)
	_eq(int(r["metal"]) + int(r["water"]) + int(r["fire"]), 100, "合计 100")
	_ok(int(r["water"]) > int(r["metal"]), "按原比例分配")
	r = CreatorLogic.toggle_root({"fire": 100}, "water")
	_eq(r, {"water": 50, "fire": 50}, "新增灵根均分")
	r = CreatorLogic.toggle_root({"fire": 50, "water": 30, "wood": 20}, "water")
	_eq(int(r.get("fire", 0)) + int(r.get("wood", 0)), 100, "移除后合计 100")
	_ok(not r.has("water"), "已移除")
	_ok(int(r["fire"]) > int(r["wood"]), "保持比例")
	r = CreatorLogic.toggle_root({"fire": 100}, "fire")
	_eq(r, {"fire": 100}, "至少保留一系")
	var five := {"metal": 100}
	for e in ["wood", "water", "fire", "earth"]:
		five = CreatorLogic.toggle_root(five, e)
	_eq(CreatorLogic.root_count(five), 5, "五系")
	_ok(CreatorLogic.roots_valid(five), "五系有效")
	var rng := RandomNumberGenerator.new()
	for i in 40:
		rng.seed = i
		var rr := CreatorLogic.random_roots(rng)
		_ok(CreatorLogic.roots_valid(rr), "随机灵根有效 %s" % str(rr))
		var b := CreatorLogic.random_build(rr, rng)
		_ok(CreatorLogic.remaining(b["attributes"], b["talents"], rr) >= 0, "随机构筑不超支")
		for a in PlayerData.ATTRS:
			var v := int(b["attributes"][a])
			_ok(v >= 1 and v <= 10, "随机属性范围")
	_eq(CreatorLogic.normalize({"fire": 3, "wood": 1}).values().reduce(func(acc: int, x: int) -> int: return acc + x, 0), 100, "规范化合计 100")
	_ok(CreatorLogic.random_name("male", rng).length() >= 2, "随机姓名")
	var ap := CreatorLogic.random_appearance(rng)
	_ok(ap.has("hair_style") and ap.has("outfit_colors"), "随机外貌字段")


func test_creator_start_game_with_sect() -> void:
	CharacterCreatorScript().start_game({"name": "杂役", "gender": "male", "roots": {"metal": 100}, "background": "servant", "sect": "tianjian", "attributes": {"con": 5, "int": 5, "spi": 5, "agi": 5, "luk": 5}, "talents": []})
	_eq(GS.player.sect, "tianjian", "杂役入宗")
	_ok(GS.player.contribution.has("tianjian") and GS.player.reputation.has("tianjian"), "贡献/声望记录")


func CharacterCreatorScript() -> GDScript:
	return load("res://src/ui/character_creator.gd")


# ================================================================ 背包拖放

func test_grid_drag_logic() -> void:
	var a := InventoryGrid.new(4, 4)
	var sword := ItemInstance.create("sword_iron")  # 1×4
	_ok(a.place(sword, 0, 0, false), "竖放")
	var e: Dictionary = a.entries[0]
	_ok(InvOps.move(a, e, a, 3, 0, false), "同网格移动")
	_eq(int(e["x"]), 3, "新位置 x")
	_ok(not InvOps.move(a, e, a, 3, 1, false), "越界不可")
	_ok(InvOps.move(a, e, a, 0, 2, true), "旋转后横放")
	_eq(InventoryGrid.footprint(sword, true), Vector2i(4, 1), "旋转占格")
	# 跨网格
	var b := InventoryGrid.new(3, 3)
	_ok(not InvOps.can_move(a, e, b, 0, 0, false), "3×3 放不下 1×4")
	_ok(not InvOps.can_move(a, e, b, 0, 0, true), "3×3 放不下 4×1")
	var c := InventoryGrid.new(4, 2)
	_ok(InvOps.move(a, e, c, 0, 1, true), "跨网格旋转放入")
	_eq(a.entries.size(), 0, "源网格已移除")
	_eq(c.entries.size(), 1, "目标网格已放入")
	# 光标居中锚点并夹紧
	_eq(InvOps.anchor_cell(c, sword, true, Vector2(3.9, 0.5)), Vector2i(0, 0), "锚点夹紧到网格内")
	_eq(InvOps.anchor_cell(InventoryGrid.new(6, 6), ItemInstance.create("ore_iron"), false, Vector2(3.2, 3.2)), Vector2i(2, 2), "2×2 以光标为中心")
	# 堆叠
	var h1 := ItemInstance.create("herb_lingcao", 7)
	var h2 := ItemInstance.create("herb_lingcao", 5)
	var g := InventoryGrid.new(4, 4)
	g.place(h1, 0, 0, false)
	var other := InventoryGrid.new(2, 2)
	other.place(h2, 0, 0, false)
	var src_e: Dictionary = other.entries[0]
	_ok(InvOps.drop(other, src_e, g, 2, 2, false, Vector2i(0, 1)), "拖到同类上合并")
	_eq(h1.count, 10, "堆满 10")
	_eq(h2.count, 2, "剩余 2 留在原处")
	_eq(other.entries.size(), 1, "源条目仍在")
	# 快速转移（部分）
	var tiny := InventoryGrid.new(1, 1)
	tiny.place(ItemInstance.create("pill_heal_small", 19), 0, 0, false)
	var bag := InventoryGrid.new(1, 1)
	bag.place(ItemInstance.create("pill_heal_small", 15), 0, 0, false)
	_ok(InvOps.quick_move(bag, bag.entries[0], tiny), "部分转移")
	_eq(tiny.count_of("pill_heal_small"), 20, "目标堆满")
	_eq(bag.count_of("pill_heal_small"), 14, "剩余留在原网格")
	# 拆分
	var sg := InventoryGrid.new(3, 3)
	sg.place(ItemInstance.create("pill_qi_small", 8), 0, 0, false)
	_ok(InvOps.split(sg, sg.entries[0], 3), "拆分")
	_eq(sg.entries.size(), 2, "两堆")
	_eq(sg.count_of("pill_qi_small"), 8, "总数不变")
	# 整理
	var sort_g := InventoryGrid.new(5, 5)
	sort_g.add(ItemInstance.create("pill_heal_small", 3))
	sort_g.add(ItemInstance.create("sword_iron"))
	sort_g.add(ItemInstance.create("ore_iron", 2))
	var before := sort_g.used_cells()
	_ok(InvOps.sort_grid(sort_g), "整理成功")
	_eq(sort_g.used_cells(), before, "整理不丢物品")


func test_equip_model() -> void:
	var p := PlayerData.new()
	var g := InventoryGrid.new(6, 5)
	p.bag = g
	var s1 := ItemInstance.create("sword_iron")
	var s2 := ItemInstance.create("sword_green")
	p.equipment["weapon"] = s1
	g.place(s2, 2, 0, false)
	_ok(not InvOps.slot_accepts("armor", s2), "剑不能进法衣槽")
	_ok(InvOps.equip_to(p, g, g.entries[0], "weapon"), "装备青锋剑")
	_eq(p.equipped("weapon"), s2, "已装备")
	_eq(g.entries.size(), 1, "旧剑回到背包")
	_eq(int(g.entries[0]["x"]), 2, "旧剑放回原位")
	_ok(InvOps.unequip_to(p, "weapon", g, 5, 0, false), "卸下到指定格")
	_ok(p.equipped("weapon") == null, "兵刃槽已空")
	var ring := ItemInstance.create("ring_crit")
	p.equipment["accessory1"] = ring
	_ok(InvOps.swap_slots(p, "accessory1", "accessory2"), "佩饰换槽")
	_eq(p.equipped("accessory2"), ring, "移到佩饰二")
	_ok(not InvOps.unequip_to(p, "bag", g, 0, 0, false), "储物袋不可卸下")


# ================================================================ 物品操作与生产

func test_item_actions() -> void:
	_new_game()
	var p := GS.player
	p.bag.clear()
	GS.give_item("pill_exp_small", 2, false)
	var e: Dictionary = p.bag.entries[0]
	var exp0 := p.cult_exp + p.stage * 1000.0
	var res := ItemActions.use(p.bag, e)
	_ok(res["ok"], "服用聚气丹")
	_ok(p.cult_exp + p.stage * 1000.0 > exp0, "修为增加")
	_eq(p.bag.count_of("pill_exp_small"), 1, "消耗一枚")
	_ok(p.pill_toxicity > 0.0, "丹毒累积")
	GS.give_item("pill_heal_small", 1, false)
	var heal_e: Dictionary = {}
	for x in p.bag.entries:
		if x["item"].id == "pill_heal_small":
			heal_e = x
	_eq(ItemActions.use_kind(heal_e["item"]), "combat", "回春丹为战斗用")
	_ok(not ItemActions.use(p.bag, heal_e)["ok"], "战斗丹药不在野外生效")
	GS.give_item("manual_fireball", 1, false)
	for x in p.bag.entries:
		if x["item"].id == "manual_fireball":
			_ok(ItemActions.use(p.bag, x)["ok"], "参悟玉简")
			break
	_ok(p.spells.has("fireball"), "习得火球术")
	_eq(p.bag.count_of("manual_fireball"), 0, "玉简消耗")
	GS.give_item("manual_gengjin", 1, false)
	for x in p.bag.entries:
		if x["item"].id == "manual_gengjin":
			var r2 := ItemActions.use(p.bag, x)
			_ok(not r2["ok"], "灵根不符不能参悟庚金诀")
			break
	GS.give_item("beast_core_1", 2, false)
	for x in p.bag.entries:
		if x["item"].id == "beast_core_1":
			var h0 := GS.hours()
			_ok(ItemActions.refine(p.bag, x, 2)["ok"], "炼化妖丹")
			_ok(GS.hours() > h0, "炼化耗时")
			break
	_eq(p.bag.count_of("beast_core_1"), 0, "妖丹已炼化")


func test_crafting() -> void:
	_new_game()
	var p := GS.player
	var r: Dictionary = DB.recipes["r_pill_heal"]
	p.bag.clear()
	_ok(not Crafting.can_craft(p, GS.stats, r)["ok"], "缺材料不可制作")
	GS.give_item("herb_lingcao", 4, false)
	_ok(Crafting.can_craft(p, GS.stats, r)["ok"], "材料足够")
	var c := Crafting.success_chance(p, GS.stats, r)
	_ok(c >= 0.05 and c <= 0.98, "成功率范围")
	var h0 := GS.hours()
	var res := Crafting.craft("r_pill_heal")
	_ok(res["ok"], "开炉")
	_eq(p.bag.count_of("herb_lingcao"), 2, "扣除材料")
	_ok(absf(GS.hours() - h0 - 2.0) < 0.01, "耗时 2 小时")
	_ok(float(p.professions["alchemy"]["xp"]) > 0.0 or p.profession_level("alchemy") > 0, "获得熟练度")
	if res["success"]:
		_ok(p.bag.count_of("pill_heal_small") >= 2, "产出回春丹")
	_ok(not Crafting.can_craft(p, GS.stats, DB.recipes["r_pill_zhuji"])["ok"], "等级不足")
	# 灵石作为材料
	p.spirit_stones = 100
	GS.give_item("herb_fire_ganoderma", 1, false)
	_ok(Crafting.can_craft(p, GS.stats, DB.recipes["r_talisman_fireball"])["ok"], "灵石材料计数")
	Crafting.craft("r_talisman_fireball")
	_eq(p.spirit_stones, 97, "扣除灵石")
	_eq(Crafting.add_xp(p, "forging", Crafting.xp_needed(0) + 1.0), 1, "熟练度升级")


# ================================================================ UIManager 与面板

func _manager() -> UIManager:
	var ui := UIManager.new()
	add_child(ui)
	return ui


func test_ui_manager_blocking() -> void:
	_new_game()
	var ui := _manager()
	await get_tree().process_frame
	_ok(not ui.is_blocking(), "初始不阻塞")
	ui.open("inventory")
	_ok(ui.is_blocking(), "打开面板后阻塞")
	_ok(ui.is_open("inventory"), "已打开")
	ui.toggle("inventory")
	_ok(not ui.is_open("inventory"), "再次切换关闭")
	_ok(not ui.is_blocking(), "关闭后不阻塞")
	ui.open("pause")
	_ok(get_tree().paused, "暂停菜单暂停游戏")
	ui.close_top()
	_ok(not get_tree().paused, "关闭后恢复")
	UIManager.register_panel("test_custom", func(args: Dictionary) -> UIWindow:
		var w := UIWindow.new()
		w.window_title = str(args.get("title", "自定义"))
		return w)
	_ok(UIManager.has_panel("test_custom"), "注册面板")
	Events.open_panel.emit("test_custom", {"title": "宗门"})
	_ok(ui.is_open("test_custom"), "通过 Events.open_panel 打开")
	var d := ui.confirm("确认？", func() -> void: pass)
	_ok(d is ConfirmDialog and ui.top_panel() == d, "确认框在最上层")
	_ok(ui._handle_escape(), "Esc 关闭最上层")
	_ok(not ui.is_open(d.panel_name), "确认框已关闭")
	ui.close_all()
	UIManager.unregister_panel("test_custom")
	Events.notify.emit("测试提示", "good")
	Events.notify.emit("境界突破", "realm")
	await get_tree().process_frame
	ui.queue_free()
	await get_tree().process_frame


func test_all_panels_instantiate() -> void:
	_new_game()
	GS.give_item("pill_zhuji", 1, false)
	GS.player.stage = 8
	GS.player.cult_exp = Cultivation.exp_needed(GS.player)
	GS.recompute()
	var ui := _manager()
	await get_tree().process_frame
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.3, 0.5, 0.3))
	var box := InventoryGrid.new(4, 4)
	box.add(ItemInstance.create("sword_iron"))
	var specs := [
		["inventory", {}],
		["inventory", {"other": box, "other_title": "宝箱"}],
		["character", {}],
		["cultivation", {"location": "home"}],
		["skills", {}],
		["map", {"image": img, "pois": [{"name": "坊市", "type": "town", "pos": Vector3(10, 0, 10)}], "player_pos": Vector3(5, 0, 5), "world_size": 64}],
		["pause", {}],
		["dialogue", {"name": "路人", "title": "散修", "text": "道友请留步。", "options": [{"text": "何事？", "callback": Callable()}]}],
		["shop", {"title": "坊市", "entries": [{"item": "pill_heal_small", "price": 10, "currency": "灵石"}], "sell": true}],
		["craft", {"profession": "alchemy"}],
		["settings", {}],
		["saves", {"mode": "load"}],
	]
	for s in specs:
		var w := ui.open(str(s[0]), s[1])
		_ok(w != null, "打开面板 %s" % s[0])
		await get_tree().process_frame
		if w != null:
			w.refresh()
		ui.close_all()
		await get_tree().process_frame
	var nd := ui.ask_number("数量", 1, 10, 5, func(_v: int) -> void: pass)
	_ok(nd is NumberDialog, "数量框")
	ui.close_all()
	_ok(not get_tree().paused, "未残留暂停")
	ui.queue_free()
	await get_tree().process_frame
	# 场景
	for path in ["res://scenes/main_menu.tscn", "res://scenes/character_creator.tscn"]:
		var sc: Node = load(path).instantiate()
		add_child(sc)
		await get_tree().process_frame
		await get_tree().process_frame
		_ok(sc.is_inside_tree(), "场景 %s" % path)
		sc.queue_free()
		await get_tree().process_frame
	# 捏人：随机 + 生成 creation
	var cr: Node = load("res://scenes/character_creator.tscn").instantiate()
	add_child(cr)
	await get_tree().process_frame
	for i in 5:
		cr.call("_show_tab", i)
		await get_tree().process_frame
	cr.call("randomize_all")
	var c: Dictionary = cr.call("creation")
	_ok(CreatorLogic.roots_valid(c["roots"]), "捏人生成灵根有效")
	_ok(CreatorLogic.remaining(c["attributes"], c["talents"], c["roots"]) >= 0, "随机全部不超支")
	cr.queue_free()
	await get_tree().process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_item_icons_render() -> void:
	var kinds := {}
	for id in DB.items:
		var tex := ItemIcon.texture_for(str(id))
		_ok(tex != null and tex.get_width() > 0, "图标 %s" % id)
		kinds[str(DB.items[id].get("icon", ""))] = true
	for k in ["sword", "saber", "spear", "fist", "robe", "armor", "pendant", "ring", "pill", "herb", "flower", "fruit", "ore", "crystal", "core", "stone", "scroll", "talisman", "bag", "seed", "hide", "bone", "key", "disc"]:
		var img := ItemIcon.render_image({"icon": k, "size": [1, 2], "grade": 2}, 2)
		var solid := 0
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.5:
					solid += 1
		_ok(solid > 20, "图标种类 %s 有内容" % k)
