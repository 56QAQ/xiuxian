extends RefCounted
## 界面截图：角色面板

var ui: UIManager


func frames() -> int:
	return 30


func build(root: Node) -> void:
	UIShotCommon.new_game()
	UIShotCommon.fill_bag()
	var p := GS.player
	p.stage = 5
	p.pill_toxicity = 32.0
	p.karma = 6
	p.kills = 23
	p.realms_cleared = 2
	p.sect = "tianjian"
	p.sect_rank = 1
	p.contribution["tianjian"] = 240
	p.reputation["tianjian"] = 180
	GS.learn_technique("lihuo_jue", false)
	GS.set_main_technique("lihuo_jue")
	GS.recompute()
	UIShotCommon.backdrop(root)
	ui = UIShotCommon.manager(root)


func step(_root: Node, frame: int) -> void:
	if frame == 1:
		ui.open("character")
