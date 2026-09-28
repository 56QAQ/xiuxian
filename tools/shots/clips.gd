extends RefCounted
## 动作剪辑检查：一排角色分别定格在不同剪辑的关键帧。
## --clips=sword_1@0.12,sword_2@0.13  （剪辑名@时间），默认展示剑法四段 + 施法。

var specs: Array = []


func frames() -> int:
	return 12


func build(root: Node) -> void:
	var arg := "sword_1@0.0,sword_1@0.14,sword_2@0.13,sword_3@0.12,sword_4@0.18,sword_4@0.3,cast_forward@0.14,cast_up@0.2"
	var kind := "sword"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			arg = a.substr(8)
		if a.begins_with("--weapon="):
			kind = a.substr(9)
	for s in arg.split(","):
		var parts := s.split("@")
		specs.append([parts[0], float(parts[1]) if parts.size() > 1 else 0.1])
	var n := specs.size()
	ShotStudio.setup(root, Vector3(0, 1.6, 3.2 + n * 0.55), Vector3(0, 0.9, 0), 42.0)
	var wid: String = {"sword": "sword_green", "saber": "saber_iron", "spear": "flag_spear_fire", "fist": "fist_wraps"}.get(kind, "sword_green")
	var visual: Dictionary = DB.item(wid)["weapon"]["visual"]
	for i in n:
		var rig := CharacterBuilder.build({}, {"weapon": visual})
		rig.position = Vector3((i - (n - 1) * 0.5) * 1.25, 0, 0)
		rig.rotation_degrees.y = 180.0 + 35.0
		root.add_child(rig)
		var label := Label3D.new()
		label.text = "%s @%.2f" % [specs[i][0], specs[i][1]]
		label.font = load("res://assets/fonts/XianKai-Regular.ttf")
		label.font_size = 28
		label.pixel_size = 0.004
		label.position = rig.position + Vector3(0, 2.3, 0)
		root.add_child(label)
		rig.play(specs[i][0])
		var t := 0.0
		while t < float(specs[i][1]):
			rig._process(1.0 / 60.0)
			t += 1.0 / 60.0
		rig.set_process(false)
