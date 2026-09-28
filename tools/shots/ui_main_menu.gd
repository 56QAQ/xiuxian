extends RefCounted
## 界面截图：主菜单（水墨远山 + 浮空仙岛 + 花瓣）。
## 参数：--hover=N 让第 N 个菜单项呈悬停态；--with-save 临时写入 5 号存档以显示“继续仙途”（截图前删除）；
##       --saves 同时打开读档面板。

const TEMP_SLOT := 5

var menu: Control
var with_save: bool = false
var show_saves: bool = false
var hover: int = 0


func frames() -> int:
	return 60


func build(root: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hover="):
			hover = int(a.substr(8))
		elif a == "--with-save":
			with_save = true
		elif a == "--saves":
			show_saves = true
			with_save = true
	if with_save and not SaveManager.has_save(TEMP_SLOT):
		UIShotCommon.new_game()
		GS.player.stage = 3
		SaveManager.save_game(TEMP_SLOT)
	else:
		with_save = false
	menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)


func step(_root: Node, frame: int) -> void:
	if frame == 50:
		var entries: Array = menu.get("_entries")
		if hover >= 0 and hover < entries.size():
			entries[hover].call("_set_hover", 1.0)
	if frame == 30 and show_saves:
		(menu.get("ui") as UIManager).open("saves", {"mode": "load"})
	if frame == 56 and with_save:
		SaveManager.delete_slot(TEMP_SLOT)
