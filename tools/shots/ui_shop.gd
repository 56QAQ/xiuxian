extends RefCounted
## 界面截图：商店（灵石 + 贡献，出售）

var ui: UIManager


func frames() -> int:
	return 28


func build(root: Node) -> void:
	UIShotCommon.new_game()
	UIShotCommon.fill_bag()
	GS.player.sect = "tianjian"
	GS.player.contribution["tianjian"] = 320
	GS.recompute()
	UIShotCommon.backdrop(root)
	ui = UIShotCommon.manager(root)


func step(_root: Node, frame: int) -> void:
	if frame == 1:
		var entries: Array = []
		for id in ["pill_heal_small", "pill_qi_small", "pill_exp_small", "pill_injury", "talisman_fireball", "manual_fireball", "bag_fine", "robe_silk"]:
			entries.append({"item": id, "price": int(DB.item(id).get("value", 10) * 1.2), "currency": "灵石"})
		var sect := DB.sect("tianjian")
		for s in sect.get("shop", []):
			entries.append({"item": s["item"], "price": int(s["cost"]), "currency": "贡献", "note": "需%s" % sect["ranks"][int(s["rank"])]["name"]})
		ui.open("shop", {"title": "青云坊市 · 百草堂", "entries": entries, "sell": true})
