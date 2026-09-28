extends RefCounted
## 可破坏物演示：左排为完好（破坏前），右排为同样的物体受击后（碎块飞散、上部失去支撑整体坠落）。

var _targets: Array = []


func frames() -> int:
	return 10


func build(root: Node) -> void:
	var dn := DayNight.new()
	dn.hour = 10.0
	root.add_child(dn)
	# 地面（world 层静态体，碎块可落地）
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(200, 1, 200)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	var gm := MeshInstance3D.new()
	var bm := BuildingMesh.new(1)
	bm.jitter = 0.0
	for i in 12:
		for j in 8:
			bm.box(Vector3(-24 + i * 4, -0.2, -14 + j * 4), Vector3(-20 + i * 4, 0.0, -10 + j * 4), Color(0.62, 0.61, 0.58) if (i + j) % 2 == 0 else Color(0.56, 0.55, 0.52))
	gm.mesh = bm.build_mesh()
	ground.add_child(gm)
	root.add_child(ground)
	for row in 2:
		var z := -3.5 if row == 0 else 3.5
		var items: Array = [
			[DestructibleFactory.pillar(4.5), Vector3(-9, 0, z), Vector3(0, 2.2, 0), 0.7],
			[DestructibleFactory.wall(6.0, 3.0, "brick", 1), Vector3(-3, 0, z), Vector3(0.5, 1.2, 0), 1.0],
			[DestructibleFactory.rock(2, 3.5, "moss"), Vector3(3.5, 0, z), Vector3(0.9, 1.4, -0.4), 1.2],
			[DestructibleFactory.lantern(), Vector3(7.5, 0, z), Vector3(0, 0.8, 0), 0.35],
			[DestructibleFactory.crate(1.2), Vector3(10, 0, z), Vector3(0, 0.6, 0.0), 0.5],
		]
		for it in items:
			var d: VoxelDestructible = it[0]
			root.add_child(d)
			d.global_position = it[1]
			if row == 1:
				_targets.append([d, it[1] + it[2], it[3]])
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0.5, 6.0, 15.5)
	cam.look_at(Vector3(0.5, 1.4, -1.0))
	cam.fov = 58


func step(_root: Node, frame: int) -> void:
	if frame == 3:
		for t in _targets:
			var d: VoxelDestructible = t[0]
			if is_instance_valid(d):
				var before := d.voxel_count()
				var n := d.apply_damage_at(t[1], t[2], 1.5)
				print("%s: %d → 移除 %d，剩余 %d，下落碎块 %d" % [d.name, before, n, d.voxel_count(), VoxelDestructible.falling_live()])
