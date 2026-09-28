class_name RealmProps
## 秘境装饰物（体素）：树、灌木、岩石、石柱、断墙、晶簇、枯树、冰锥。带简单碰撞。
## 同类同变体的网格会被缓存复用。

const VS := 0.25
static var _cache: Dictionary = {}


static func build(kind: String, rng: RandomNumberGenerator) -> Node3D:
	var variant := rng.randi() % 3
	var key := "%s_%d" % [kind, variant]
	var mesh: ArrayMesh = _cache.get(key, null)
	var col_size := Vector3.ZERO
	var r2 := RandomNumberGenerator.new()
	r2.seed = hash(key)
	var g: VoxelGrid
	match kind:
		"tree", "pine":
			g = _tree(r2, kind == "pine")
			col_size = Vector3(0.6, 3.0, 0.6)
		"deadtree":
			g = _dead_tree(r2)
			col_size = Vector3(0.5, 2.5, 0.5)
		"bush":
			g = VoxelGrid.new(8, 5, 8)
			g.fill_ellipsoid(Vector3(4, 2, 4), Vector3(3.8, 2.6, 3.8), Color(0.25, 0.5, 0.22))
			_speckle(g, r2, Color(0.35, 0.62, 0.3), 0.3)
		"rock":
			g = VoxelGrid.new(10, 7, 9)
			g.fill_ellipsoid(Vector3(5, 2, 4.5), Vector3(4.8, 3.5 + variant, 4.2), Color(0.5, 0.49, 0.47))
			_speckle(g, r2, Color(0.42, 0.41, 0.4), 0.35)
			col_size = Vector3(2.2, 1.4, 2.0)
		"pillar":
			g = VoxelGrid.new(6, 24 - variant * 5, 6)
			g.fill_box(Vector3i(0, 0, 0), Vector3i(5, g.sy - 1, 5), Color(0.66, 0.64, 0.6))
			g.fill_box(Vector3i(0, 0, 0), Vector3i(5, 1, 5), Color(0.55, 0.53, 0.5))
			_speckle(g, r2, Color(0.4, 0.55, 0.35), 0.12)
			for i in 6:
				g.clear_box(Vector3i(r2.randi_range(0, 5), g.sy - 1 - r2.randi_range(0, 3), r2.randi_range(0, 5)), Vector3i(r2.randi_range(0, 5), g.sy - 1, r2.randi_range(0, 5)))
			col_size = Vector3(1.5, g.sy * VS, 1.5)
		"wall":
			g = VoxelGrid.new(20, 10, 3)
			g.fill_box(Vector3i(0, 0, 0), Vector3i(19, 9, 2), Color(0.62, 0.6, 0.56))
			for x in 20:
				var top := 9 - int(absf(sin(x * 0.7 + variant)) * 5.0)
				g.clear_box(Vector3i(x, top, 0), Vector3i(x, 9, 2))
			_speckle(g, r2, Color(0.52, 0.5, 0.47), 0.3)
			col_size = Vector3(5.0, 2.0, 0.75)
		"crystal":
			g = VoxelGrid.new(8, 12, 8)
			for i in 4:
				var cx := r2.randi_range(2, 5)
				var cz := r2.randi_range(2, 5)
				var hgt := r2.randi_range(5, 11)
				for y in hgt:
					g.set_color(cx, y, cz, VoxelGrid.glow(Color(1.0, 0.35, 0.2), 0.7))
					if y < hgt - 2:
						g.set_color(cx + 1, y, cz, VoxelGrid.glow(Color(0.9, 0.25, 0.15), 0.5))
			col_size = Vector3(1.0, 2.0, 1.0)
		"icespike":
			g = VoxelGrid.new(6, 16, 6)
			for y in 16:
				var r := 3.0 * (1.0 - y / 16.0)
				g.fill_cylinder_y(3, 3, r, y, y, Color(0.7, 0.85, 1.0).lerp(Color(0.95, 0.98, 1.0), y / 16.0))
			col_size = Vector3(1.0, 3.5, 1.0)
		_:
			return null
	if mesh == null:
		mesh = VoxelMesher.build(g, VS, Vector3(-g.sx * VS * 0.5, 0, -g.sz * VS * 0.5))
		_cache[key] = mesh
	var root: Node3D
	if col_size != Vector3.ZERO:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = col_size
		cs.shape = bs
		cs.position = Vector3(0, col_size.y * 0.5, 0)
		body.add_child(cs)
		root = body
	else:
		root = Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	return root


static func _speckle(g: VoxelGrid, rng: RandomNumberGenerator, c: Color, p: float) -> void:
	var v := VoxelGrid.encode(c)
	for i in g.data.size():
		if g.data[i] != 0 and rng.randf() < p:
			g.data[i] = v


static func _tree(rng: RandomNumberGenerator, pine: bool) -> VoxelGrid:
	var g := VoxelGrid.new(18, 28, 18)
	var trunk := Color(0.4, 0.28, 0.18)
	var th := rng.randi_range(10, 14)
	g.fill_box(Vector3i(8, 0, 8), Vector3i(9, th, 9), trunk)
	if pine:
		for i in 5:
			var y := th - 4 + i * 3
			var r := 6.5 - i * 1.2
			g.fill_cylinder_y(9, 9, r, y, y + 1, Color(0.18, 0.38, 0.28).lerp(Color(0.85, 0.9, 0.95), 0.25 if i % 2 == 0 else 0.0))
		g.fill_box(Vector3i(8, th, 8), Vector3i(9, th + 12, 9), Color(0.2, 0.4, 0.3))
	else:
		var leaf := Color(0.28, 0.55, 0.25)
		for i in 5:
			var c := Vector3(9 + rng.randf_range(-3, 3), th + rng.randf_range(0, 6), 9 + rng.randf_range(-3, 3))
			g.fill_ellipsoid(c, Vector3(rng.randf_range(3, 5), rng.randf_range(2.5, 4), rng.randf_range(3, 5)), leaf)
		_speckle(g, rng, Color(0.36, 0.64, 0.3), 0.18)
		g.fill_box(Vector3i(8, 0, 8), Vector3i(9, th, 9), trunk)
	return g


static func _dead_tree(rng: RandomNumberGenerator) -> VoxelGrid:
	var g := VoxelGrid.new(14, 22, 14)
	var c := Color(0.25, 0.2, 0.17)
	g.fill_box(Vector3i(6, 0, 6), Vector3i(7, 14, 7), c)
	for i in 4:
		var a := Vector3(6.5, rng.randi_range(7, 14), 6.5)
		var b := a + Vector3(rng.randf_range(-6, 6), rng.randf_range(2, 6), rng.randf_range(-6, 6))
		g.fill_line(a, b, 0.5, c)
	return g
