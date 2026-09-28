class_name WeaponBuilder
## 体素兵器生成。握把在原点，刃沿本地 -Z。返回的节点带 meta "tip_length"（米）。
## visual 字段：kind(sword/saber/spear/fist), length(体素), blade(颜色), guard(颜色), grip(颜色), glow(元素或空)

const VOXEL := 0.025


static func build(visual: Dictionary) -> Node3D:
	var kind := str(visual.get("kind", "sword"))
	var root := Node3D.new()
	root.name = "Weapon"
	if kind == "fist":
		root.set_meta("tip_length", 0.1)
		return root
	var blade := CharacterBuilder.col(visual.get("blade", "#d8dde6"))
	var guard := CharacterBuilder.col(visual.get("guard", "#c89a30"))
	var grip := CharacterBuilder.col(visual.get("grip", "#4a2a1a"))
	var length := int(visual.get("length", 36 if kind != "spear" else 80))
	var g: VoxelGrid
	var origin: Vector3
	match kind:
		"spear":
			g = VoxelGrid.new(3, 3, length + 8)
			g.fill_box(Vector3i(1, 1, 0), Vector3i(1, 1, length - 1), grip)
			g.fill_box(Vector3i(0, 0, length - 10), Vector3i(2, 2, length - 9), guard)
			for i in 8:
				var w := 1 if i < 6 else 0
				g.fill_box(Vector3i(1 - w, 1, length - 8 + i), Vector3i(1 + w, 1, length - 8 + i), blade)
			g.fill_box(Vector3i(1, 1, length), Vector3i(1, 1, length + 7), blade)
			origin = Vector3(-1.5, -1.5, -22)
			root.set_meta("tip_length", (length + 8 - 22) * VOXEL)
		_:
			var bw := 3 if kind == "saber" else 2
			g = VoxelGrid.new(7, 3, length + 10)
			g.fill_box(Vector3i(3, 1, 0), Vector3i(3, 1, 7), grip)
			g.fill_box(Vector3i(0, 0, 8), Vector3i(6, 2, 9), guard)
			for z in range(10, length + 10):
				var taper := 0 if z < length + 6 else 1
				g.fill_box(Vector3i(3 - bw / 2 + taper, 1, z), Vector3i(3 + (bw - 1) / 2 + (1 if kind == "saber" else 0) - taper, 1, z), blade)
			g.fill_box(Vector3i(3, 1, 10), Vector3i(3, 1, length + 6), blade.lightened(0.25))
			origin = Vector3(-3.5, -1.5, -4)
			root.set_meta("tip_length", (length + 6) * VOXEL)
	var mi := VoxelMesher.build_instance(g, VOXEL, origin * VOXEL)
	# 网格在 +Z 方向生成，翻转为 -Z
	mi.rotation = Vector3(0, PI, 0)
	mi.position = Vector3.ZERO
	root.add_child(mi)
	return root
