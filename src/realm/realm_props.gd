class_name RealmProps
## 秘境装饰物（方块材质体素）：树、松、柳、灌木、岩石、石柱、断墙、晶簇、枯树、冰锥。带简单碰撞。
## 体素为 MatGrid（树皮/叶/石/冰等纹理层），BlockMesher 网格化；同类同变体的网格会被缓存复用。

const VS := 0.25
const K = preload("res://src/world/block_tex.gd")
static var _cache: Dictionary = {}


static func build(kind: String, rng: RandomNumberGenerator) -> Node3D:
	var variant := rng.randi() % 3
	var key := "%s_%d" % [kind, variant]
	var mesh: ArrayMesh = _cache.get(key, null)
	var col_size := Vector3.ZERO
	var r2 := RandomNumberGenerator.new()
	r2.seed = hash(key)
	var g: VoxelGrid = null
	var vs := VS
	match kind:
		"tree", "pine":
			if mesh == null:
				g = _tree(r2, kind == "pine")
			col_size = Vector3(0.6, 3.0, 0.6)
		"willow":
			if mesh == null:
				mesh = PropBuilder.mesh("willow", variant % PropBuilder.variants("willow"))
			col_size = Vector3(0.6, 3.0, 0.6)
		"deadtree":
			if mesh == null:
				g = _dead_tree(r2)
			col_size = Vector3(0.5, 2.5, 0.5)
		"bush":
			if mesh == null:
				var mg := MatGrid.new(8, 5, 8)
				mg.kind = K.K_LEAF
				mg.fill_ellipsoid(Vector3(4, 2, 4), Vector3(3.8, 2.6, 3.8), Color(0.25, 0.48, 0.22))
				_speckle(mg, r2, Color(0.33, 0.58, 0.29), 0.3)
				g = mg
		"rock":
			if mesh == null:
				var mg := MatGrid.new(10, 7, 9)
				mg.kind = K.K_ROCK
				mg.fill_ellipsoid(Vector3(5, 2, 4.5), Vector3(4.8, 3.5 + variant, 4.2), Color(0.5, 0.49, 0.47))
				_speckle(mg, r2, Color(0.43, 0.42, 0.41), 0.35)
				# 顶部苔藓
				for z in mg.sz:
					for x in mg.sx:
						for y in range(mg.sy - 1, -1, -1):
							if mg.is_solid(x, y, z):
								if y >= 3 and r2.randf() < 0.6:
									mg.kind = K.K_MOSS
									mg.set_color(x, y, z, Color(0.34, 0.48, 0.26))
								break
				g = mg
			col_size = Vector3(2.2, 1.4, 2.0)
		"pillar":
			if mesh == null:
				var mg := MatGrid.new(6, 24 - variant * 5, 6)
				mg.kind = K.K_STONE_SMOOTH
				mg.fill_box(Vector3i(0, 0, 0), Vector3i(5, mg.sy - 1, 5), Color(0.66, 0.64, 0.6))
				mg.kind = K.K_CARVED
				mg.fill_box(Vector3i(0, 0, 0), Vector3i(5, 1, 5), Color(0.55, 0.53, 0.5))
				mg.kind = K.K_MOSSY
				_speckle(mg, r2, Color(0.4, 0.55, 0.35), 0.12)
				for i in 6:
					mg.clear_box(Vector3i(r2.randi_range(0, 5), mg.sy - 1 - r2.randi_range(0, 3), r2.randi_range(0, 5)), Vector3i(r2.randi_range(0, 5), mg.sy - 1, r2.randi_range(0, 5)))
				g = mg
			col_size = Vector3(1.5, (24 - variant * 5) * VS, 1.5)
		"wall":
			if mesh == null:
				var mg := MatGrid.new(20, 10, 3)
				mg.kind = K.K_BRICK
				mg.fill_box(Vector3i(0, 0, 0), Vector3i(19, 9, 2), Color(0.62, 0.6, 0.56))
				for x in 20:
					var top := 9 - int(absf(sin(x * 0.7 + variant)) * 5.0)
					mg.clear_box(Vector3i(x, top, 0), Vector3i(x, 9, 2))
				mg.kind = K.K_MOSSY
				_speckle(mg, r2, Color(0.52, 0.5, 0.47), 0.2)
				g = mg
			col_size = Vector3(5.0, 2.0, 0.75)
		"crystal":
			if mesh == null:
				var mg := MatGrid.new(8, 12, 8)
				mg.kind = K.K_CRYSTAL
				for i in 4:
					var cx := r2.randi_range(2, 5)
					var cz := r2.randi_range(2, 5)
					var hgt := r2.randi_range(5, 11)
					for y in hgt:
						mg.set_color(cx, y, cz, VoxelGrid.glow(Color(1.0, 0.35, 0.2), 0.7))
						if y < hgt - 2:
							mg.set_color(cx + 1, y, cz, VoxelGrid.glow(Color(0.9, 0.25, 0.15), 0.5))
				g = mg
			col_size = Vector3(1.0, 2.0, 1.0)
		"icespike":
			if mesh == null:
				var mg := MatGrid.new(6, 16, 6)
				mg.kind = K.K_ICE
				for y in 16:
					var r := 3.0 * (1.0 - y / 16.0)
					mg.fill_cylinder_y(3, 3, r, y, y, Color(0.7, 0.85, 1.0).lerp(Color(0.95, 0.98, 1.0), y / 16.0))
				g = mg
			col_size = Vector3(1.0, 3.5, 1.0)
		_:
			return null
	if mesh == null:
		mesh = BlockMesher.build(g, vs, Vector3(-g.sx * vs * 0.5, 0, -g.sz * vs * 0.5))
		_cache[key] = mesh
	elif not _cache.has(key):
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


## 随机改色（保持种类为网格当前 kind：MatGrid 的 set_raw 会写入当前种类）
static func _speckle(g: VoxelGrid, rng: RandomNumberGenerator, c: Color, p: float) -> void:
	var v := VoxelGrid.encode(c)
	var mg := g as MatGrid
	for i in g.data.size():
		if g.data[i] != 0 and rng.randf() < p:
			g.data[i] = v
			if mg != null:
				mg.mat[i] = mg.kind


static func _tree(rng: RandomNumberGenerator, pine: bool) -> VoxelGrid:
	var g := MatGrid.new(18, 28, 18)
	var trunk := Color(0.4, 0.28, 0.18)
	var th := rng.randi_range(10, 14)
	g.kind = K.K_BARK
	g.fill_box(Vector3i(8, 0, 8), Vector3i(9, th, 9), trunk)
	if pine:
		for i in 5:
			var y := th - 4 + i * 3
			var r := 6.5 - i * 1.2
			var snowy := i % 2 == 0
			g.kind = K.K_SNOW if snowy else K.K_PINE
			g.fill_cylinder_y(9, 9, r, y, y + 1, Color(0.18, 0.38, 0.28).lerp(Color(0.85, 0.9, 0.95), 0.6 if snowy else 0.0))
		g.kind = K.K_PINE
		g.fill_box(Vector3i(8, th, 8), Vector3i(9, th + 12, 9), Color(0.2, 0.4, 0.3))
	else:
		var leaf := Color(0.28, 0.53, 0.25)
		g.kind = K.K_LEAF
		for i in 5:
			var c := Vector3(9 + rng.randf_range(-3, 3), th + rng.randf_range(0, 6), 9 + rng.randf_range(-3, 3))
			g.fill_ellipsoid(c, Vector3(rng.randf_range(3, 5), rng.randf_range(2.5, 4), rng.randf_range(3, 5)), leaf)
		_speckle(g, rng, Color(0.35, 0.60, 0.3), 0.18)
		g.kind = K.K_BARK
		g.fill_box(Vector3i(8, 0, 8), Vector3i(9, th, 9), trunk)
	return g


static func _dead_tree(rng: RandomNumberGenerator) -> VoxelGrid:
	var g := MatGrid.new(14, 22, 14)
	var c := Color(0.25, 0.2, 0.17)
	g.kind = K.K_BARK
	g.fill_box(Vector3i(6, 0, 6), Vector3i(7, 14, 7), c)
	for i in 4:
		var a := Vector3(6.5, rng.randi_range(7, 14), 6.5)
		var b := a + Vector3(rng.randf_range(-6, 6), rng.randf_range(2, 6), rng.randf_range(-6, 6))
		g.fill_line(a, b, 0.5, c)
	return g
