extends RefCounted
## 发型展示：全部发型（CharacterBuilder.HAIR_STYLES）× 女（前排）/ 男（后排），侧后方视角便于观察发束。
## 额外参数：--view=front|side|back（默认 side）


func _arg(k: String, def: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return def


func frames() -> int:
	return 45


func build(root: Node) -> void:
	var styles := CharacterBuilder.HAIR_STYLES
	var n := styles.size()
	var sp := 1.15
	ArtStudio.setup(root, Vector3(0.3, 4.4, 7.4), Vector3(0.3, 0.6, -1.6), 44.0)
	var view := _arg("view", "side")
	var yaw := 180.0 + (20.0 if view == "front" else (180.0 if view == "back" else 140.0))
	var hair := [["#c8201e", "#ff5a40"], ["#1a1a22", "#50506a"], ["#e8c060", "#fff0a0"], ["#8a4a2a", "#c07a4a"],
		["#f0f0f4", "#c8d4ff"], ["#6a2a8a", "#a060d0"], ["#e070a0", "#ffc0d8"], ["#3a5ad0", "#80a8ff"]]
	var palettes := [["#b3201c", "#3b2618", "#e2b23c"], ["#e8ecf4", "#4a5a78", "#d8b050"], ["#5ab86a", "#2a4a30", "#e0d8a0"], ["#3a6ad0", "#1a2a50", "#c8e0ff"],
		["#c09040", "#6a4a2a", "#e8dcc0"], ["#f0e8f8", "#9070c0", "#f0c0e0"], ["#e8a0b0", "#6a2a3a", "#fff0f4"], ["#2a6a5a", "#0a2a24", "#e0c060"]]
	for g in 2:
		for i in n:
			var app := {
				"gender": "female" if g == 0 else "male", "hair_style": styles[i],
				"hair_color": hair[i % hair.size()][0], "hair_color2": hair[i % hair.size()][1],
				"ears": "fox" if (g == 0 and i == 0) else "human",
				"outfit": ["armor", "robe", "martial"][(i + g) % 3], "outfit_colors": palettes[(i + g * 2) % palettes.size()],
			}
			var rig := CharacterBuilder.build(app)
			rig.position = Vector3(-sp * (n - 1) * 0.5 + i * sp + 0.55 * g, 0, -3.2 * g)
			rig.rotation_degrees.y = yaw
			rig.stance = "none"
			root.add_child(rig)
