extends RefCounted
## 植被与道具一览：各种树木、灌木、岩石、草花、灵草、矿脉


func frames() -> int:
	return 8


func build(root: Node) -> void:
	var dn := DayNight.new()
	dn.hour = 10.0
	root.add_child(dn)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.6, 0.32)
	ground.material_override = gm
	root.add_child(ground)
	var t0 := Time.get_ticks_msec()
	var kinds := ["ancient", "pine_snow", "pine", "broadleaf", "maple", "blossom", "bamboo", "willow", "dead", "crystal"]
	for i in kinds.size():
		var t := PropBuilder.make_tree(kinds[i], 0)
		t.position = Vector3(-40 + i * 9.0, 0, 0 if i != 0 else 8)
		root.add_child(t)
	var small := ["shrub", "shrub_yellow", "reed", "rock_gray", "rock_moss", "rock_snow", "rock_red", "rock_yellow", "grass", "grass_dry", "flower", "lotus", "pebble"]
	for i in small.size():
		var mi := MeshInstance3D.new()
		mi.mesh = PropBuilder.mesh(small[i], 1)
		mi.position = Vector3(-30 + i * 4.0, 0, -12)
		root.add_child(mi)
	var h1 := PropBuilder.make_herb("herb_lingcao")
	h1.position = Vector3(26, 0, -12)
	root.add_child(h1)
	var h2 := PropBuilder.make_herb("herb_fire_ganoderma")
	h2.position = Vector3(28, 0, -12)
	root.add_child(h2)
	var o1 := PropBuilder.make_ore("ore_iron")
	o1.position = Vector3(31, 0, -12)
	root.add_child(o1)
	var o2 := PropBuilder.make_ore("ore_gengjin")
	o2.position = Vector3(35, 0, -12)
	root.add_child(o2)
	print("道具网格生成 %d ms" % (Time.get_ticks_msec() - t0))
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 13, -46)
	cam.look_at(Vector3(0, 4, 0))
	cam.fov = 62
