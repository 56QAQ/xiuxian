extends RefCounted
## 界面截图：炼丹

var ui: UIManager


func frames() -> int:
	return 28


func build(root: Node) -> void:
	UIShotCommon.new_game()
	UIShotCommon.fill_bag()
	GS.player.professions["alchemy"] = {"lv": 2, "xp": 40.0}
	GS.give_item("beast_core_1", 2, false)
	GS.recompute()
	UIShotCommon.backdrop(root)
	ui = UIShotCommon.manager(root)


func step(_root: Node, frame: int) -> void:
	if frame == 1:
		var w: CraftPanel = ui.open("craft", {"profession": "alchemy", "title": "丹房"})
		w._craft(2)
