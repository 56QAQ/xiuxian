extends RefCounted
## 兵器展示：剑 / 刀 / 枪 / 旗枪 / 拳套，不同品相（detail）与元素发光（glow）。刃尖朝上排列。


func frames() -> int:
	return 30


func build(root: Node) -> void:
	ArtStudio.setup(root, Vector3(0, 1.2, 4.6), Vector3(0.1, 1.15, 0), 40.0)
	var list: Array = [
		DB.item("sword_iron")["weapon"]["visual"],
		{"kind": "sword", "length": 38, "blade": "#e8f0ff", "guard": "#e0b040", "grip": "#2a1a3a", "glow": "fire", "detail": 2},
		DB.item("sword_green")["weapon"]["visual"],
		DB.item("saber_iron")["weapon"]["visual"],
		{"kind": "saber", "length": 36, "blade": "#d8e0f0", "guard": "#3a5ad0", "grip": "#1a1a2a", "glow": "water", "detail": 2},
		DB.item("spear_iron")["weapon"]["visual"],
		{"kind": "spear", "length": 84, "blade": "#f0f4ff", "guard": "#e0b040", "grip": "#2a2a30", "glow": "metal", "detail": 2},
		DB.item("flag_spear_fire")["weapon"]["visual"],
	]
	var x := -2.3
	for v in list:
		var w := WeaponBuilder.build(v)
		var kind := str(v.get("kind", ""))
		# 刃朝上：本地 -Z → 世界 +Y
		w.rotation_degrees = Vector3(90, 90, 0)
		if v.has("flag"):
			# 旗面朝向镜头右侧展开
			w.rotation_degrees = Vector3(90, -90, 0)
		w.position = Vector3(x, 0.3 if kind != "spear" else 0.62, 0)
		root.add_child(w)
		x += 0.52 if kind != "spear" else 0.7
	# 拳套：缠布（左右）+ 金属（带发光）
	var fists: Array = [DB.item("fist_wraps")["weapon"]["visual"], {"kind": "fist", "guard": "#c0c4cc", "grip": "#3a2a20", "glow": "earth", "detail": 2}]
	for i in fists.size():
		for hand in ["r", "l"]:
			var g := WeaponBuilder.build(fists[i], hand)
			g.position = Vector3(-0.2 + i * 0.75 + (0.0 if hand == "r" else 0.3), 0.2, 1.0)
			g.rotation_degrees = Vector3(0, 160 if hand == "r" else 200, 0)
			root.add_child(g)
