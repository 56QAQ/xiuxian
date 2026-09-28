extends RefCounted
## 界面截图：捏人。参数 --tab=0..4（外貌/灵根/天赋/出身/姓名），默认 0。

var creator: Control


func frames() -> int:
	return 40


func build(root: Node) -> void:
	creator = load("res://scenes/character_creator.tscn").instantiate()
	root.add_child(creator)


func step(_root: Node, frame: int) -> void:
	if frame != 2:
		return
	var tab := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tab="):
			tab = int(a.substr(6))
	creator.set("char_name", "赵灵儿")
	creator.set("appearance", CharacterBuilder.DEFAULT_APPEARANCE.duplicate(true))
	creator.set("roots", {"metal": 25, "water": 15, "fire": 60})
	creator.set("attributes", {"con": 6, "int": 7, "spi": 5, "agi": 6, "luk": 3})
	creator.set("talents", ["sword_bone", "fox_blood", "lone_star"])
	if tab == 3:
		creator.set("background", "servant")
		creator.set("sect", "tianjian")
	creator.call("_show_tab", tab)
	creator.call("_update_preview", true)
	creator.call("_update_summary")
