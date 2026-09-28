extends RefCounted
## 界面截图：提示流（各类 kind 配色）与境界突破横幅，叠加在暂停菜单 + 设置面板之上。
## 参数 --variant=plain 只显示提示流与横幅。

var ui: UIManager
var variant: String = ""


func frames() -> int:
	return 40


func build(root: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--variant="):
			variant = a.substr(10)
	UIShotCommon.new_game()
	UIShotCommon.backdrop(root)
	ui = UIShotCommon.manager(root)


func step(_root: Node, frame: int) -> void:
	match frame:
		1:
			if variant != "plain":
				ui.open("pause")
		3:
			if variant != "plain":
				ui.open("settings", {"offset": Vector2(330, 0)})
		20:
			Events.notify.emit("突破成功！踏入筑基初期", "realm")
		28:
			Events.notify.emit("获得 回春丹 ×3", "loot")
			Events.notify.emit("习得法诀【火球术】", "good")
			Events.notify.emit("储物袋已满，玄铁×2 送回洞府", "warn")
			Events.notify.emit("突破失败，经脉受损……", "bad")
			Events.notify.emit("天元3721年1月2日 辰时 · 你在洞府中醒来", "info")
