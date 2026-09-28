class_name VoxMesh
## VoxCanvas → ArrayMesh 的快速网格化（隐藏面剔除 + 逐顶点 AO，结果与 VoxelMesher 一致）。
## 画布自带 1 格空边，内层循环无需任何边界检查；使用共享体素材质（VoxelMesher.material()）。
## 另带静态网格缓存（按部件参数键），用于捏人预览/NPC 人群重复部件。

const AO_CURVE := [0.52, 0.70, 0.86, 1.0]
## 面：法线 n、切向 u、v（与 VoxelMesher.FACES 相同，保证绕序正确）
const _N := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const _U := [Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0)]
const _V := [Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0)]

const CACHE_MAX := 600
static var _cache: Dictionary = {}
static var cache_hits: int = 0
static var cache_misses: int = 0


## 把若干画布合并为一个网格（同一骨骼上的部件合并可减少绘制调用）
static func build(canvases: Array, vs: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for cv in canvases:
		_mesh_canvas(cv as VoxCanvas, vs, verts, normals, colors, indices)
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, VoxelMesher.material())
	return mesh


static func build_one(cv: VoxCanvas, vs: float) -> ArrayMesh:
	return build([cv], vs)


## 缓存：key 相同直接返回已有网格；否则调用 maker（返回 ArrayMesh）
static func cached(key: String, maker: Callable) -> ArrayMesh:
	if _cache.has(key):
		cache_hits += 1
		return _cache[key]
	cache_misses += 1
	var m: ArrayMesh = maker.call()
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	_cache[key] = m
	return m


static func clear_cache() -> void:
	_cache.clear()


static func _mesh_canvas(cv: VoxCanvas, vs: float, verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array) -> void:
	var d := cv.data
	var sx := cv.sx
	var sy := cv.sy
	var sz := cv.sz
	var sxy := cv.sxy
	# 填充索引 (1,1,1) 对应局部体素 lo
	var origin := (Vector3(cv.lo) - Vector3.ONE + cv.shift) * vs
	var nof := PackedInt32Array()
	var uof := PackedInt32Array()
	var vof := PackedInt32Array()
	var nvec: Array[Vector3] = []
	var pofs: Array[Vector3] = []
	var uvec: Array[Vector3] = []
	var vvec: Array[Vector3] = []
	for f in 6:
		var n: Vector3i = _N[f]
		var u: Vector3i = _U[f]
		var v: Vector3i = _V[f]
		nof.append(n.x + n.y * sx + n.z * sxy)
		uof.append(u.x + u.y * sx + u.z * sxy)
		vof.append(v.x + v.y * sx + v.z * sxy)
		nvec.append(Vector3(n))
		pofs.append(Vector3(maxi(n.x, 0), maxi(n.y, 0), maxi(n.z, 0)) * vs)
		uvec.append(Vector3(u) * vs)
		vvec.append(Vector3(v) * vs)
	var k0: float = AO_CURVE[0]
	var k1: float = AO_CURVE[1]
	var k2: float = AO_CURVE[2]
	for z in range(1, sz - 1):
		for y in range(1, sy - 1):
			var row := y * sx + z * sxy
			for x in range(1, sx - 1):
				var i := row + x
				var raw := d[i]
				if raw == 0:
					continue
				# 完全被包围的内部体素直接跳过
				if d[i + 1] != 0 and d[i - 1] != 0 and d[i + sx] != 0 and d[i - sx] != 0 and d[i + sxy] != 0 and d[i - sxy] != 0:
					continue
				var col := Color.hex(raw & 0xFFFFFFFF)
				# 四个 AO 等级的明暗色（每个体素只算一次）
				var shaded: Array[Color] = [Color(col.r * k0, col.g * k0, col.b * k0, col.a), Color(col.r * k1, col.g * k1, col.b * k1, col.a), Color(col.r * k2, col.g * k2, col.b * k2, col.a), col]
				var pmin := origin + Vector3(x, y, z) * vs
				for f in 6:
					var ni := i + nof[f]
					if d[ni] != 0:
						continue
					var uo := uof[f]
					var vo := vof[f]
					var su_p := 1 if d[ni + uo] != 0 else 0
					var su_n := 1 if d[ni - uo] != 0 else 0
					var sv_p := 1 if d[ni + vo] != 0 else 0
					var sv_n := 1 if d[ni - vo] != 0 else 0
					var a0 := 0 if (su_n + sv_n) == 2 else 3 - (su_n + sv_n + (1 if d[ni - uo - vo] != 0 else 0))
					var a1 := 0 if (su_p + sv_n) == 2 else 3 - (su_p + sv_n + (1 if d[ni + uo - vo] != 0 else 0))
					var a2 := 0 if (su_p + sv_p) == 2 else 3 - (su_p + sv_p + (1 if d[ni + uo + vo] != 0 else 0))
					var a3 := 0 if (su_n + sv_p) == 2 else 3 - (su_n + sv_p + (1 if d[ni - uo + vo] != 0 else 0))
					var base := verts.size()
					var pf: Vector3 = pmin + pofs[f]
					var uf: Vector3 = uvec[f]
					var vf: Vector3 = vvec[f]
					verts.append(pf)
					verts.append(pf + uf)
					verts.append(pf + uf + vf)
					verts.append(pf + vf)
					var nf: Vector3 = nvec[f]
					normals.append(nf)
					normals.append(nf)
					normals.append(nf)
					normals.append(nf)
					colors.append(shaded[a0])
					colors.append(shaded[a1])
					colors.append(shaded[a2])
					colors.append(shaded[a3])
					if a0 + a2 >= a1 + a3:
						indices.append(base)
						indices.append(base + 1)
						indices.append(base + 2)
						indices.append(base)
						indices.append(base + 2)
						indices.append(base + 3)
					else:
						indices.append(base + 1)
						indices.append(base + 2)
						indices.append(base + 3)
						indices.append(base + 1)
						indices.append(base + 3)
						indices.append(base)
