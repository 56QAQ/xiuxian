extends RefCounted
## 界面截图：修炼面板（闭关记录 + 瓶颈突破）

var ui: UIManager


func frames() -> int:
	return 30


func build(root: Node) -> void:
	UIShotCommon.new_game()
	UIShotCommon.fill_bag()
	var p := GS.player
	p.stage = 8
	p.cult_exp = Cultivation.exp_needed(p) - 300.0
	GS.recompute()
	UIShotCommon.backdrop(root)
	ui = UIShotCommon.manager(root)


func step(_root: Node, frame: int) -> void:
	if frame == 1:
		var w: CultivationPanel = ui.open("cultivation", {"location": "home"})
		w._do_seclude(24.0, "闭关一日")
		w._do_seclude(168.0, "闭关七日")
		for e in GS.player.bag.entries:
			if e["item"].id == "pill_heal_small":
				w._on_pill(GS.player.bag, e)
				break
