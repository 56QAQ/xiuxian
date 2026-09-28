extends RefCounted
## 角色展示：默认外貌（参考图：红发双马尾、狐耳、战甲、旗枪）从多个角度


func frames() -> int:
	return 30


func build(root: Node) -> void:
	ShotStudio.setup(root, Vector3(0, 1.3, 4.6), Vector3(0, 0.9, 0), 38.0)
	var visual: Dictionary = DB.item("flag_spear_fire")["weapon"]["visual"]
	var angles := [0.0, 40.0, 180.0, -90.0]
	for i in angles.size():
		var rig := CharacterBuilder.build({}, {"weapon": visual})
		rig.position = Vector3(-2.1 + i * 1.4, 0, 0)
		rig.rotation_degrees.y = 180.0 + angles[i]
		root.add_child(rig)
