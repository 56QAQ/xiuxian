class_name UIShotCommon
## 界面截图公用：新游戏样例数据、背景场景、UIManager。


## 新游戏（红发双马尾狐耳 · 火木双灵根 · 世家子弟）
static func new_game() -> void:
	GS.new_game({
		"name": "赵灵儿", "gender": "female",
		"appearance": {"hair_style": "twin_tails", "ears": "fox", "outfit": "robe"},
		"roots": {"fire": 60, "wood": 40},
		"attributes": {"con": 6, "int": 7, "spi": 5, "agi": 6, "luk": 4},
		"talents": ["sword_bone", "photographic"],
		"background": "clan", "seed": 7,
	})


## 背景：远景水墨风（用于界面截图，避免纯色）
static func backdrop(root: Node) -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	root.add_child(layer)
	var bg := InkBackdrop.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.dim = 0.35
	layer.add_child(bg)


static func manager(root: Node) -> UIManager:
	var ui := UIManager.new()
	root.add_child(ui)
	return ui


## 样例物品：包括竖放/横放的长兵器
static func fill_bag() -> void:
	var p := GS.player
	var bag := p.bag
	bag.clear()
	var put := func(id: String, n: int, x: int, y: int, rot: bool, grade: int) -> void:
		var it := ItemInstance.create(id, n)
		it.grade = grade
		if not bag.place(it, x, y, rot):
			bag.add(it)
	put.call("flag_spear_fire", 1, 0, 0, false, -1)
	put.call("sword_green", 1, 1, 0, false, -1)
	put.call("armor_crimson", 1, 2, 0, false, -1)
	put.call("pill_zhuji", 1, 4, 0, false, -1)
	put.call("pill_exp_small", 6, 5, 0, false, -1)
	put.call("pill_heal_small", 12, 4, 1, false, -1)
	put.call("pill_qi_small", 7, 5, 1, false, -1)
	put.call("treasure_snow_lotus", 1, 6, 0, false, -1)
	put.call("herb_lingcao", 8, 4, 2, false, -1)
	put.call("herb_fire_ganoderma", 3, 5, 2, false, -1)
	put.call("ring_crit", 1, 6, 2, false, 4)
	put.call("manual_gengjin", 1, 7, 2, false, -1)
	put.call("talisman_fireball", 9, 6, 3, false, -1)
	put.call("ore_gengjin", 2, 5, 3, false, -1)
	put.call("saber_iron", 1, 1, 4, true, -1)
	put.call("beast_core_1", 4, 6, 4, false, -1)
	put.call("treasure_sun_fruit", 2, 7, 4, false, -1)
	put.call("spirit_stone_mid", 5, 6, 5, false, -1)
	put.call("manual_fireball", 1, 0, 5, true, -1)
	p.secure.clear()
	p.secure.place(ItemInstance.create("pill_jiejin", 1), 0, 0, false)
	p.secure.place(ItemInstance.create("jade_pendant", 1), 1, 0, false)
	p.secure.place(ItemInstance.create("herb_lingcao", 3), 0, 1, true)
	p.spirit_stones = 1280
	p.quick_item = "pill_heal_small"
	GS.recompute()
