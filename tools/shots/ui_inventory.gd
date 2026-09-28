extends RefCounted
## 界面截图：储物袋（纸娃娃、长兵器竖放/横放、本命空间）。
## 参数 --variant=loot 显示秘境容器（左侧第二网格）。

var ui: UIManager


func frames() -> int:
	return 24


func build(root: Node) -> void:
	UIShotCommon.new_game()
	UIShotCommon.fill_bag()
	UIShotCommon.backdrop(root)
	ui = UIShotCommon.manager(root)


func step(_root: Node, frame: int) -> void:
	if frame != 1:
		return
	var variant := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--variant="):
			variant = a.substr(10)
	if variant == "loot":
		var box := InventoryGrid.new(6, 5)
		var s := ItemInstance.create("sword_iron")
		s.grade = 2
		s.affixes = [{"k": "crit_rate", "v": 0.04}]
		box.place(s, 0, 0, false)
		box.place(ItemInstance.create("wolf_pelt", 2), 1, 0, false)
		box.place(ItemInstance.create("bag_rare"), 3, 0, false)
		box.place(ItemInstance.create("spear_iron"), 0, 4, true)
		box.place(ItemInstance.create("beast_core_1", 3), 1, 2, false)
		box.place(ItemInstance.create("robe_silk"), 4, 1, false)
		box.place(ItemInstance.create("pill_injury", 2), 2, 2, false)
		box.place(ItemInstance.create("pill_detox", 1), 2, 3, false)
		box.place(ItemInstance.create("fist_wraps"), 3, 2, false)
		ui.open("inventory", {"other": box, "other_title": "修士遗骸", "other_hint": "搜索完成。拖入储物袋拾取，或点击“全部拾取”。"})
	else:
		ui.open("inventory")
