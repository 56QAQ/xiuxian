extends RefCounted
## 建筑部件展示：殿堂（重檐）、塔、亭、牌坊、院墙、店铺、摊位（影棚地面 + 真实日光天空）


func frames() -> int:
	return 10


func build(root: Node) -> void:
	var dn := DayNight.new()
	dn.hour = 9.5
	root.add_child(dn)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.6, 0.35)
	ground.material_override = gm
	root.add_child(ground)
	var p := BuildingBuilder.pal_with({})
	var m := BuildingMesh.new(3)
	BuildingBuilder.hall(m, 0, 0, 20, 11, 1.5, 4.5, p, {"double": true})
	BuildingBuilder.pagoda(m, -24, 6, 7, 5, p)
	BuildingBuilder.pavilion(m, 22, 4, 5, 3.5, p)
	BuildingBuilder.paifang(m, 0, -22, 14, 8, p)
	BuildingBuilder.wall(m, Vector2(-40, -26), Vector2(-12, -26), 3.5, p)
	BuildingBuilder.shop(m, 26, -16, 8, 9, p, Color(0.2, 0.3, 0.5), 1)
	BuildingBuilder.stall(m, 14, -24, 3, Color(0.8, 0.25, 0.2), p, 2)
	BuildingBuilder.cauldron(m, -10, -12, 1.0, p)
	BuildingBuilder.giant_sword(m, -18, -16, 9, p)
	BuildingBuilder.notice_board(m, 8, -14, 3, p)
	var mi := m.build_instance()
	root.add_child(mi)
	print("建筑面数: ", m.quad_count())
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(18, 16, -52)
	cam.look_at(Vector3(0, 5, 0))
	cam.fov = 55
