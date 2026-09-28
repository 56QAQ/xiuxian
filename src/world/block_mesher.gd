class_name BlockMesher
## 体素网格 → 方块材质网格（block.gdshader）：隐藏面剔除 + 逐顶点 AO（烘焙进顶点色）+ 材质层 UV。
## MatGrid 的体素种类决定每个面的纹理层（顶/侧/底）；普通 VoxelGrid 用 default_kind。
## UV.y 为风摆幅度：叶类整体微颤（越高越大），草类随顶点高度摇摆（根部不动）。

const AO_CURVE := [0.52, 0.70, 0.86, 1.0]

# 6 个面：法线 n、切向 u、v（与 VoxelMesher 相同，u×v = -n 使三角形为顺时针正面）
static var _fn: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
static var _fu: Array[Vector3i] = [Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0)]
static var _fv: Array[Vector3i] = [Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0)]
static var _ft := PackedInt32Array([1, 1, 0, 2, 1, 1])  # 面 → 顶(0)/侧(1)/底(2)
static var _ao_curve := PackedFloat32Array(AO_CURVE)


## grid: 体素；vs: 体素边长（米）；origin: 体素 (0,0,0) 最小角的位置；wind: 风摆倍率（0 关闭）
static func build(grid: VoxelGrid, vs: float, origin: Vector3 = Vector3.ZERO, ao: bool = true, wind: float = 1.0,
		default_kind: int = 0, mat: Material = null) -> ArrayMesh:
	var arrays := build_arrays(grid, vs, origin, ao, wind, default_kind)
	var mesh := ArrayMesh.new()
	if arrays.is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat if mat != null else BlockTex.material("static"))
	return mesh


static func build_arrays(grid: VoxelGrid, vs: float, origin: Vector3 = Vector3.ZERO, ao: bool = true, wind: float = 1.0, default_kind: int = 0) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var sx := grid.sx
	var sy := grid.sy
	var sz := grid.sz
	var data := grid.data
	var mats := PackedByteArray()
	var has_mat := grid is MatGrid
	if has_mat:
		mats = (grid as MatGrid).mat
	var top_y := origin.y + sy * vs
	var aoc := _ao_curve
	# 每种方块的三面纹理层与风摆类型（本地缓存）
	var nk := BlockTex.kind_count()
	var lay := PackedInt32Array()
	lay.resize(nk * 3)
	var kw := PackedByteArray()
	kw.resize(nk)
	for k in nk:
		for f in 3:
			lay[k * 3 + f] = BlockTex.face_layer(k, f)
		kw[k] = BlockTex.kind_wind(k)
	for z in sz:
		for y in sy:
			for x in sx:
				var idx := x + sx * (y + sy * z)
				var raw := data[idx]
				if raw == 0:
					continue
				var col := VoxelGrid.decode(raw)
				var kind := int(mats[idx]) if has_mat else default_kind
				var wt := int(kw[kind]) if wind > 0.0 else 0
				for f in 6:
					var n: Vector3i = _fn[f]
					var nx := x + n.x
					var ny := y + n.y
					var nz := z + n.z
					if nx >= 0 and ny >= 0 and nz >= 0 and nx < sx and ny < sy and nz < sz and data[nx + sx * (ny + sy * nz)] != 0:
						continue
					var u: Vector3i = _fu[f]
					var v: Vector3i = _fv[f]
					var p := Vector3i(x, y, z)
					if n.x > 0 or n.y > 0 or n.z > 0:
						p += n
					var a0 := 3
					var a1 := 3
					var a2 := 3
					var a3 := 3
					if ao:
						a0 = _ao(data, sx, sy, sz, nx, ny, nz, -u, -v)
						a1 = _ao(data, sx, sy, sz, nx, ny, nz, u, -v)
						a2 = _ao(data, sx, sy, sz, nx, ny, nz, u, v)
						a3 = _ao(data, sx, sy, sz, nx, ny, nz, -u, v)
					var base := verts.size()
					var pf := Vector3(p) * vs + origin
					var uf := Vector3(u) * vs
					var vf := Vector3(v) * vs
					var q0 := pf
					var q1 := pf + uf
					var q2 := pf + uf + vf
					var q3 := pf + vf
					verts.append(q0)
					verts.append(q1)
					verts.append(q2)
					verts.append(q3)
					var nf := Vector3(n)
					normals.append(nf)
					normals.append(nf)
					normals.append(nf)
					normals.append(nf)
					colors.append(_shade(col, aoc[a0]))
					colors.append(_shade(col, aoc[a1]))
					colors.append(_shade(col, aoc[a2]))
					colors.append(_shade(col, aoc[a3]))
					var layer := float(lay[kind * 3 + _ft[f]])
					if wt == 0:
						var uv0 := Vector2(layer, 0.0)
						uvs.append(uv0)
						uvs.append(uv0)
						uvs.append(uv0)
						uvs.append(uv0)
					elif wt == 1:
						# 叶：整体微颤，越高越大
						var amp := (0.022 + 0.03 * clampf(q0.y / maxf(top_y, 0.5), 0.0, 1.0)) * wind
						var uvl := Vector2(layer, amp)
						uvs.append(uvl)
						uvs.append(uvl)
						uvs.append(uvl)
						uvs.append(uvl)
					else:
						# 草：根部不动，顶端摆动
						for q in [q0, q1, q2, q3]:
							var t := clampf((q as Vector3).y / maxf(top_y, 0.2), 0.0, 1.0)
							uvs.append(Vector2(layer, 0.16 * t * t * wind))
					if a0 + a2 >= a1 + a3:
						indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
					else:
						indices.append_array([base + 1, base + 2, base + 3, base + 1, base + 3, base])
	if verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


static func _solid(data: PackedInt32Array, sx: int, sy: int, sz: int, x: int, y: int, z: int) -> bool:
	if x < 0 or y < 0 or z < 0 or x >= sx or y >= sy or z >= sz:
		return false
	return data[x + sx * (y + sy * z)] != 0


static func _ao(data: PackedInt32Array, sx: int, sy: int, sz: int, x: int, y: int, z: int, du: Vector3i, dv: Vector3i) -> int:
	var s1 := 1 if _solid(data, sx, sy, sz, x + du.x, y + du.y, z + du.z) else 0
	var s2 := 1 if _solid(data, sx, sy, sz, x + dv.x, y + dv.y, z + dv.z) else 0
	if s1 == 1 and s2 == 1:
		return 0
	var c := 1 if _solid(data, sx, sy, sz, x + du.x + dv.x, y + du.y + dv.y, z + du.z + dv.z) else 0
	return 3 - (s1 + s2 + c)


static func _shade(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)
