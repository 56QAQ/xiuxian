extends RefCounted
## 捏人预览影棚（RigPreview）截图：四种取景并排（全身 / 半身 / 面容 / 脸部特写），深色水墨底。
## 额外参数：--app='{"hair_style":"long"}' 外貌 JSON；--weapon=物品id；--yaw=度


func _arg(k: String, def: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return def


func frames() -> int:
	return 50


func build(root: Node) -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 12)
	layer.add_child(row)
	var app := {}
	var js := _arg("app")
	if js != "":
		var d: Variant = JSON.parse_string(js)
		if d is Dictionary:
			app = d
	var eq := {}
	if _arg("weapon") != "":
		eq["weapon"] = DB.item(_arg("weapon"))["weapon"]["visual"]
	for f in ["full", "upper", "bust", "face"]:
		var rp := RigPreview.new()
		rp.framing = f
		rp.yaw = float(_arg("yaw", "-20"))
		rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rp.set_appearance(CharacterBuilder.appearance_with_defaults(app), eq, true)
		row.add_child(rp)
