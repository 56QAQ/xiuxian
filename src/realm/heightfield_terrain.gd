class_name HeightfieldTerrain
extends StaticBody3D
## 方块高度场地形（秘境用）：按列生成方块网格（分块），HeightMapShape3D 碰撞，支持炸坑。
## 列 (x, z) 占据世界 [x, x+1] × [z, z+1]，顶面高度为整数 heights[x + z*w]。

const CHUNK := 16

var w: int = 0
var d: int = 0
var heights: PackedFloat32Array
var top_colors: PackedColorArray
var side_color: Color = Color(0.45, 0.36, 0.28)
var deep_color: Color = Color(0.38, 0.36, 0.34)
var _chunks: Dictionary = {}   ## Vector2i -> MeshInstance3D
var _shape: HeightMapShape3D
var _cs: CollisionShape3D


func _ready() -> void:
	add_to_group("terrain")
	collision_layer = 1
	collision_mask = 0


func setup(width: int, depth: int, h: PackedFloat32Array, tops: PackedColorArray) -> void:
	w = width
	d = depth
	heights = h
	top_colors = tops
	_shape = HeightMapShape3D.new()
	_shape.map_width = w
	_shape.map_depth = d
	_cs = CollisionShape3D.new()
	_cs.shape = _shape
	_cs.position = Vector3(w * 0.5, 0, d * 0.5)
	add_child(_cs)
	_update_collision()
	for cz in range(0, (d + CHUNK - 1) / CHUNK):
		for cx in range(0, (w + CHUNK - 1) / CHUNK):
			_build_chunk(Vector2i(cx, cz))


func height_at(x: float, z: float) -> float:
	var ix := clampi(int(floor(x)), 0, w - 1)
	var iz := clampi(int(floor(z)), 0, d - 1)
	return heights[ix + iz * w]


func _h(x: int, z: int) -> float:
	if x < 0 or z < 0 or x >= w or z >= d:
		return -4.0
	return heights[x + z * w]


func _update_collision() -> void:
	var data := PackedFloat32Array()
	data.resize(w * d)
	for i in w * d:
		data[i] = heights[i]
	_shape.map_data = data


func _build_chunk(c: Vector2i) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var x0 := c.x * CHUNK
	var z0 := c.y * CHUNK
	for z in range(z0, mini(z0 + CHUNK, d)):
		for x in range(x0, mini(x0 + CHUNK, w)):
			var h := heights[x + z * w]
			var top := top_colors[x + z * w]
			# AO：周围更高的列使顶面变暗
			var occl := 0
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _h(x + o.x, z + o.y) > h:
					occl += 1
			var tc := top.darkened(0.08 * occl)
			_quad(verts, normals, colors, Vector3(x, h, z), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3.UP, tc)
			# 侧面
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nh := _h(x + dir.x, z + dir.y)
				if nh >= h:
					continue
				var y := h
				var bottom := maxf(nh, h - 12.0)
				while y > bottom:
					var yb := maxf(y - 1.0, bottom)
					var depth := h - y
					var sc := side_color if depth < 1.0 else deep_color
					sc = sc.darkened(clampf(depth * 0.04, 0.0, 0.3))
					if depth < 0.5:
						sc = top.lerp(side_color, 0.35)
					_side(verts, normals, colors, x, z, dir, y, yb, sc)
					y = yb
	var mi: MeshInstance3D = _chunks.get(c, null)
	if mi == null:
		mi = MeshInstance3D.new()
		add_child(mi)
		_chunks[c] = mi
	if verts.is_empty():
		mi.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(0, VoxelMesher.material())
	mi.mesh = m


func _quad(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, p: Vector3, u: Vector3, w2: Vector3, normal: Vector3, col: Color) -> void:
	# 顺时针正面（u×w2 = -normal 时）
	var a := p
	var b := p + u
	var cc := p + u + w2
	var dd := p + w2
	if u.cross(w2).dot(normal) > 0.0:
		var t := b
		b = dd
		dd = t
	v.append_array([a, b, cc, a, cc, dd])
	for i in 6:
		n.append(normal)
		c.append(col)


func _side(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, x: int, z: int, dir: Vector2i, ytop: float, ybot: float, col: Color) -> void:
	var normal := Vector3(dir.x, 0, dir.y)
	var p: Vector3
	var u: Vector3
	if dir.x == 1:
		p = Vector3(x + 1, ybot, z)
		u = Vector3(0, 0, 1)
	elif dir.x == -1:
		p = Vector3(x, ybot, z)
		u = Vector3(0, 0, 1)
	elif dir.y == 1:
		p = Vector3(x, ybot, z + 1)
		u = Vector3(1, 0, 0)
	else:
		p = Vector3(x, ybot, z)
		u = Vector3(1, 0, 0)
	_quad(v, n, c, p, u, Vector3(0, ytop - ybot, 0), normal, col)


## 炸坑：半径内的列向下压低（碗形），重建受影响的分块与碰撞
func carve_crater(pos: Vector3, radius: float) -> void:
	var lp := to_local(pos)
	var changed := {}
	var r := int(ceil(radius))
	var any := false
	for z in range(int(lp.z) - r, int(lp.z) + r + 1):
		for x in range(int(lp.x) - r, int(lp.x) + r + 1):
			if x < 1 or z < 1 or x >= w - 1 or z >= d - 1:
				continue
			var dist := Vector2(x + 0.5 - lp.x, z + 0.5 - lp.z).length()
			if dist > radius:
				continue
			var depth := floorf((1.0 - dist / radius) * radius * 0.6 + 0.5)
			var target := minf(heights[x + z * w], lp.y - depth)
			if target < heights[x + z * w] - 0.5:
				heights[x + z * w] = maxf(floorf(target), 0.0)
				top_colors[x + z * w] = top_colors[x + z * w].darkened(0.35).lerp(side_color, 0.5)
				changed[Vector2i(x / CHUNK, z / CHUNK)] = true
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					changed[Vector2i((x + o.x) / CHUNK, (z + o.y) / CHUNK)] = true
				any = true
	if not any:
		return
	for c in changed:
		if _chunks.has(c):
			_build_chunk(c)
	_update_collision()
	FX.burst(pos, side_color, 22, 9.0, 0.28, 1.0, false, 18.0)
	FX.dust(pos, 16)
	Audio.play_at("rock_break", pos)
