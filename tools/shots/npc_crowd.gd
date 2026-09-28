extends RefCounted
## NPC 人群：12 个 CharacterBuilder.random_appearance() 生成的修士（随机兵器），两排站立。
## 额外参数：--seed=数字


func _arg(k: String, def: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return def


func frames() -> int:
	return 40


func build(root: Node) -> void:
	ArtStudio.setup(root, Vector3(0, 2.0, 7.6), Vector3(0, 0.95, -0.9), 36.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_arg("seed", "20240917"))
	var weapons := ["", "sword_iron", "sword_green", "saber_iron", "spear_iron", "fist_wraps", ""]
	var t0 := Time.get_ticks_usec()
	for i in 12:
		var a := CharacterBuilder.random_appearance(rng)
		var eq := {}
		var wid: String = weapons[rng.randi_range(0, weapons.size() - 1)]
		if wid != "":
			eq["weapon"] = DB.item(wid)["weapon"]["visual"]
		var rig := CharacterBuilder.build(a, eq)
		if wid == "":
			rig.stance = "none"
		var row := i / 6
		var col := i % 6
		rig.position = Vector3(-3.4 + col * 1.36 + row * 0.68, 0, -row * 1.9)
		rig.rotation_degrees.y = 180.0 + rng.randf_range(-35.0, 35.0)
		root.add_child(rig)
	print("12 个 NPC 生成用时 %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
