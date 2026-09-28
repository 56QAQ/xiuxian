extends RefCounted
## 界面截图：储物袋（纸娃娃、长兵器竖放/横放、本命空间、宣纸提示框、拖动中旋转预览）。
## 参数 --variant=loot 显示秘境容器（左侧第二网格）；--variant=plain 不显示提示框与拖动演示。

var ui: UIManager
var variant: String = ""
var inv: InventoryPanel


func frames() -> int:
	return 26


func build(root: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--variant="):
			variant = a.substr(10)
	UIShotCommon.new_game()
	UIShotCommon.fill_bag()
	UIShotCommon.backdrop(root)
	ui = UIShotCommon.manager(root)


func step(_root: Node, frame: int) -> void:
	if frame == 1:
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
			inv = ui.open("inventory", {"other": box, "other_title": "修士遗骸", "other_hint": "搜索完成。拖入储物袋拾取，或点击“全部拾取”。"})
		else:
			inv = ui.open("inventory")
	if frame == 12 and variant != "plain" and inv != null:
		_demo_tooltip()
		_demo_drag()


## 在旗枪旁显示宣纸提示框（与悬停时相同的控件）
func _demo_tooltip() -> void:
	var bag_view: GridView = inv.get("_bag_view")
	var e: Dictionary = GS.player.bag.entries[0]
	var tip := PanelContainer.new()
	tip.add_theme_stylebox_override("panel", UITheme.get_theme().get_stylebox("panel", "TooltipPanel"))
	tip.add_child(ItemTooltip.build(e["item"], "右键：更多操作 · 拖动中 R 旋转"))
	ui.add_child(tip)
	var r := bag_view.entry_rect(e)
	tip.position = bag_view.global_position + r.position + Vector2(r.size.x + 10, 10)


## 拖动演示：旋转后的红缨枪悬停在储物袋上方，显示放置预览
func _demo_drag() -> void:
	var secure_view: GridView = inv.get("_secure_view")
	var bag_view: GridView = inv.get("_bag_view")
	var it := ItemInstance.create("spear_iron")
	var data := InvOps.make_drag(it, GS.player.secure, {}, "", true, secure_view)
	var ghost := ItemDragGhost.create(data, bag_view.cell)
	ui.add_child(ghost)
	var target := Vector2(4.6, 5.5) * bag_view.cell
	ghost.position = bag_view.global_position + target
	bag_view.set("_preview", {"ok": true, "x": 2, "y": 5, "rect": Rect2(Vector2(2, 5) * bag_view.cell, Vector2(5, 1) * bag_view.cell), "stack": false})
	bag_view.queue_redraw()
	GridView.drag_data = {}
