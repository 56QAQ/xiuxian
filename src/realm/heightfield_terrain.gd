class_name HeightfieldTerrain
extends StaticBody3D
## 方块高度场地形（秘境用）：按列生成方块网格（分块），HeightMapShape3D 碰撞，支持炸坑。
## 列 (x, z) 占据世界 [x, x+1] × [z, z+1]，顶面高度为整数 heights[x + z*w]。
## 网格与大地图共用 TerrainGen.mesh_columns（方块纹理层、逐顶点 AO、侧面分层合并）与方块材质：
## 每列有地表类型（TerrainGen.S_*，决定顶/侧/表土/岩层纹理）与顶面颜色。

const CHUNK := 16

var w: int = 0
var d: int = 0
var heights: PackedFloat32Array
var top_colors: PackedColorArray
## 每列地表类型（TerrainGen.S_*）；为空时全部视为 default_surface
var surfaces: PackedByteArray
var default_surface: int = TerrainGen.S_GRASS
## 兼容旧接口（碎屑颜色）
var side_color: Color = Color(0.45, 0.36, 0.28)
var deep_color: Color = Color(0.38, 0.36, 0.34)
var _chunks: Dictionary = {}   ## Vector2i -> MeshInstance3D
var _shape: HeightMapShape3D
var _cs: CollisionShape3D
var _mat: Material


func _ready() -> void:
	add_to_group("terrain")
	collision_layer = 1
	collision_mask = 0


## tops：每列顶面颜色（sRGB，alpha<1 自发光）；surf：每列地表类型（可省略）
func setup(width: int, depth: int, h: PackedFloat32Array, tops: PackedColorArray, surf: PackedByteArray = PackedByteArray(), mat: Material = null) -> void:
	w = width
	d = depth
	heights = h
	top_colors = tops
	surfaces = surf
	if surfaces.size() != w * d:
		surfaces = PackedByteArray()
		surfaces.resize(w * d)
		surfaces.fill(default_surface)
	_mat = mat if mat != null else BlockTex.material("terrain")
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


## 高度图（L8，像素值 = 列高），供水面着色器计算水深
func height_image() -> Image:
	var data := PackedByteArray()
	data.resize(w * d)
	for i in w * d:
		data[i] = clampi(int(heights[i]), 0, 255)
	return Image.create_from_data(w, d, false, Image.FORMAT_L8, data)


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
	var x0 := c.x * CHUNK
	var z0 := c.y * CHUNK
	var nx := mini(CHUNK, w - x0)
	var nz := mini(CHUNK, d - z0)
	var bw := nx + 2
	var lh := PackedInt32Array()
	lh.resize(bw * (nz + 2))
	for lz in nz + 2:
		for lx in bw:
			var hh := _h(x0 + lx - 1, z0 + lz - 1)
			# 边界外视为深坑：侧面向下延伸 12 格即止
			lh[lz * bw + lx] = int(hh) if hh > -1.0 else maxi(int(_h(clampi(x0 + lx - 1, 0, w - 1), clampi(z0 + lz - 1, 0, d - 1))) - 12, 0)
	var surf := PackedByteArray()
	surf.resize(nx * nz)
	var topc := PackedColorArray()
	topc.resize(nx * nz)
	for lz in nz:
		for lx in nx:
			var i := (z0 + lz) * w + x0 + lx
			surf[lz * nx + lx] = surfaces[i]
			topc[lz * nx + lx] = top_colors[i]
	var arrays := TerrainGen.mesh_columns(nx, nz, lh, 1.0, Vector3(x0, 0, z0), surf, topc, x0, z0)
	var mi: MeshInstance3D = _chunks.get(c, null)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.material_override = _mat
		add_child(mi)
		_chunks[c] = mi
	if arrays.is_empty():
		mi.mesh = null
		return
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = m


## 炸坑：半径内的列向下压低（碗形），地表变为焦土，重建受影响的分块与碰撞
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
				var i := x + z * w
				heights[i] = maxf(floorf(target), 0.0)
				var tc := top_colors[i]
				top_colors[i] = Color(tc.r, tc.g, tc.b, 1.0).darkened(0.35).lerp(side_color, 0.5)
				if dist < radius * 0.75 and surfaces[i] != TerrainGen.S_LAVA:
					surfaces[i] = TerrainGen.S_SCORCH
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
