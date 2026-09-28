extends RefCounted
## 发型展示：六种发型 × 女（前排）/ 男（后排），侧后方视角便于观察发束。
## 额外参数：--view=front|side|back（默认 side）


func _arg(k: String, def: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return def


func frames() -> int:
	return 45


func build(root: Node) -> void:
	ArtStudio.setup(root, Vector3(0.35, 4.6, 6.4), Vector3(0.35, 0.55, -1.6), 44.0)
	var view := _arg("view", "side")
	var yaw := 180.0 + (20.0 if view == "front" else (180.0 if view == "back" else 140.0))
	var styles := CharacterBuilder.HAIR_STYLES
	var hair := [["#c8201e", "#ff5a40"], ["#1a1a22", "#50506a"], ["#e8c060", "#fff0a0"], ["#8a4a2a", "#c07a4a"], ["#f0f0f4", "#c8d4ff"], ["#6a2a8a", "#a060d0"]]
	var palettes := [["#b3201c", "#3b2618", "#e2b23c"], ["#e8ecf4", "#4a5a78", "#d8b050"], ["#5ab86a", "#2a4a30", "#e0d8a0"], ["#3a6ad0", "#1a2a50", "#c8e0ff"], ["#c09040", "#6a4a2a", "#e8dcc0"], ["#f0e8f8", "#9070c0", "#f0c0e0"]]
	for g in 2:
		for i in styles.size():
			var app := {
				"gender": "female" if g == 0 else "male", "hair_style": styles[i],
				"hair_color": hair[i][0], "hair_color2": hair[i][1],
				"ears": "fox" if (g == 0 and i == 0) else "human",
				"outfit": ["armor", "robe", "martial"][(i + g) % 3], "outfit_colors": palettes[(i + g * 2) % palettes.size()],
			}
			var rig := CharacterBuilder.build(app)
			rig.position = Vector3(-3.3 + i * 1.4 + 0.7 * g, 0, -3.2 * g)
			rig.rotation_degrees.y = yaw
			rig.stance = "none"
			root.add_child(rig)
