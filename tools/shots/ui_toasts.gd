extends RefCounted
## 界面截图：提示流、境界横幅、暂停菜单与设置面板（叠加于角色影棚场景之上）

var ui: UIManager


func frames() -> int:
	return 40


func build(root: Node) -> void:
	GS.new_game({"name": "赵灵儿", "roots": {"fire": 60, "wood": 40}, "background": "rogue", "seed": 7})
	ShotStudio.setup(root, Vector3(0, 1.3, 4.6), Vector3(0, 0.9, 0), 38.0)
	for i in 3:
		var rig := CharacterBuilder.build({"hair_style": ["twin_tails", "ponytail", "bun"][i]})
		rig.position = Vector3(-1.4 + i * 1.4, 0, 0)
		rig.rotation_degrees.y = 180.0 + (i - 1) * 25.0
		root.add_child(rig)
	ui = UIManager.new()
	root.add_child(ui)


func step(_root: Node, frame: int) -> void:
	match frame:
		28:
			Events.notify.emit("获得 回春丹 ×3", "loot")
			Events.notify.emit("习得法诀【火球术】", "good")
			Events.notify.emit("储物袋已满，玄铁×2 送回洞府", "warn")
			Events.notify.emit("突破失败，经脉受损……", "bad")
			Events.notify.emit("天元3721年1月2日 辰时", "info")
		29:
			Events.notify.emit("突破成功！踏入筑基初期", "realm")
		1:
			ui.open("pause")
		3:
			ui.open("settings", {"offset": Vector2(330, 0)})
