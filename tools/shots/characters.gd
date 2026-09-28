extends RefCounted
## 角色展示：默认外貌（参考图：红发双马尾、狐耳、金红战甲、旗枪），正面 / 3/4 / 侧面 / 背面


func frames() -> int:
	return 45


func build(root: Node) -> void:
	ArtStudio.setup(root, Vector3(0, 1.25, 6.4), Vector3(0, 0.95, 0), 32.0)
	var visual: Dictionary = DB.item("flag_spear_fire")["weapon"]["visual"]
	var angles := [0.0, 40.0, 100.0, 180.0]
	for i in angles.size():
		var rig := CharacterBuilder.build({}, {"weapon": visual})
		rig.position = Vector3(-2.4 + i * 1.6, 0, 0)
		rig.rotation_degrees.y = 180.0 + angles[i]
		root.add_child(rig)
