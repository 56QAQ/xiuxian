extends RefCounted
## 界面截图：其余面板。--panel=sect（宗门·人脉，默认）| pause | saves | settings | confirm | number | map_sect
## 用于检查统一的国风样式（标题印章、祥云角、笔触页签、委角按钮、宣纸对话框）。

var ui: UIManager
var panel := "sect"


func frames() -> int:
	return 26


func build(root: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--panel="):
			panel = a.substr(8)
	UIShotCommon.new_game()
	UIShotCommon.fill_bag()
	GS.player.sect = "tianjian"
	GS.player.contribution["tianjian"] = 320
	GS.player.reputation["tianjian"] = 180
	GS.recompute()
	UIShotCommon.backdrop(root)
	ui = UIShotCommon.manager(root)
	if not UIManager.has_panel("sect"):
		UIManager.register_panel("sect", SectPanel.create)


func step(_root: Node, frame: int) -> void:
	if frame != 1:
		return
	match panel:
		"sect":
			ui.open("sect")
		"pause":
			ui.open("pause")
		"saves":
			ui.open("saves", {"mode": "save"})
		"settings":
			ui.open("settings")
		"confirm":
			ui.open("inventory")
			ui.confirm("确定要丢弃【烈焰旗枪】吗？此物将永久消失。", func() -> void: pass, "丢弃法器", "丢弃", "且慢")
		"number":
			ui.open("inventory")
			ui.ask_number("拆分 · 回春丹", 1, 12, 6, func(_v: int) -> void: pass, "拖动或输入数量")
