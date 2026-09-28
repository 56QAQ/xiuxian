extends RefCounted
## 界面截图：主菜单（水墨远山 + 浮空仙岛 + 花瓣）。参数 --hover=N 让第 N 个菜单项呈悬停态。

var menu: Control


func frames() -> int:
	return 60


func build(root: Node) -> void:
	menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)


func step(_root: Node, frame: int) -> void:
	if frame == 50:
		var idx := 0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--hover="):
				idx = int(a.substr(8))
		var entries: Array = menu.get("_entries")
		if idx >= 0 and idx < entries.size():
			entries[idx].call("_set_hover", 1.0)
