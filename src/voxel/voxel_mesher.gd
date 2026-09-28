class_name VoxelMesher
## 把 VoxelGrid 转为 ArrayMesh：隐藏面剔除 + 逐顶点环境光遮蔽（AO，烘焙进顶点色）。
## 顶点色 alpha 携带发光强度（见 VoxelGrid.glow），由 voxel.gdshader 解读。

const AO_CURVE := [0.52, 0.70, 0.86, 1.0]

## 6 个面：法线 n，切向 u、v（满足 u×v = -n，使三角形为 Godot 的顺时针正面）
const FACES := [
	{"n": Vector3i(1, 0, 0), "u": Vector3i(0, 0, 1), "v": Vector3i(0, 1, 0)},
	{"n": Vector3i(-1, 0, 0), "u": Vector3i(0, 1, 0), "v": Vector3i(0, 0, 1)},
	{"n": Vector3i(0, 1, 0), "u": Vector3i(1, 0, 0), "v": Vector3i(0, 0, 1)},
	{"n": Vector3i(0, -1, 0), "u": Vector3i(0, 0, 1), "v": Vector3i(1, 0, 0)},
	{"n": Vector3i(0, 0, 1), "u": Vector3i(0, 1, 0), "v": Vector3i(1, 0, 0)},
	{"n": Vector3i(0, 0, -1), "u": Vector3i(1, 0, 0), "v": Vector3i(0, 1, 0)},
]

static var _material: ShaderMaterial


## 共享体素材质（所有体素网格共用；受击闪白等通过 instance uniform 控制）
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://assets/shaders/voxel.gdshader")
	return _material


## grid: 体素数据；voxel_size: 体素边长（米）；origin: 体素 (0,0,0) 最小角在网格局部空间的位置
static func build(grid: VoxelGrid, voxel_size: float, origin: Vector3 = Vector3.ZERO, ao: bool = true) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var sx := grid.sx
	var sy := grid.sy
	var sz := grid.sz
	var data := grid.data
	for z in sz:
		for y in sy:
			for x in sx:
				var raw := data[x + sx * (y + sy * z)]
				if raw == 0:
					continue
				var col := VoxelGrid.decode(raw)
				for f in FACES:
					var n: Vector3i = f["n"]
					var nx := x + n.x
					var ny := y + n.y
					var nz := z + n.z
					if nx >= 0 and ny >= 0 and nz >= 0 and nx < sx and ny < sy and nz < sz and data[nx + sx * (ny + sy * nz)] != 0:
						continue
					var u: Vector3i = f["u"]
					var v: Vector3i = f["v"]
					var p := Vector3i(x, y, z)
					if n.x > 0 or n.y > 0 or n.z > 0:
						p += n
					var a0 := 3
					var a1 := 3
					var a2 := 3
					var a3 := 3
					if ao:
						var ax := x + n.x
						var ay := y + n.y
						var az := z + n.z
						a0 = _ao(grid, ax, ay, az, -u, -v)
						a1 = _ao(grid, ax, ay, az, u, -v)
						a2 = _ao(grid, ax, ay, az, u, v)
						a3 = _ao(grid, ax, ay, az, -u, v)
					var base := verts.size()
					var pf := Vector3(p) * voxel_size + origin
					var uf := Vector3(u) * voxel_size
					var vf := Vector3(v) * voxel_size
					verts.append(pf)
					verts.append(pf + uf)
					verts.append(pf + uf + vf)
					verts.append(pf + vf)
					var nf := Vector3(n)
					for i in 4:
						normals.append(nf)
					colors.append(_shade(col, a0))
					colors.append(_shade(col, a1))
					colors.append(_shade(col, a2))
					colors.append(_shade(col, a3))
					if a0 + a2 >= a1 + a3:
						indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
					else:
						indices.append_array([base + 1, base + 2, base + 3, base + 1, base + 3, base])
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
	mesh.surface_set_material(0, material())
	return mesh


## 快捷方法：生成带共享材质的 MeshInstance3D
static func build_instance(grid: VoxelGrid, voxel_size: float, origin: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = build(grid, voxel_size, origin)
	return mi


static func _ao(grid: VoxelGrid, x: int, y: int, z: int, du: Vector3i, dv: Vector3i) -> int:
	var s1 := 1 if grid.is_solid(x + du.x, y + du.y, z + du.z) else 0
	var s2 := 1 if grid.is_solid(x + dv.x, y + dv.y, z + dv.z) else 0
	if s1 == 1 and s2 == 1:
		return 0
	var c := 1 if grid.is_solid(x + du.x + dv.x, y + du.y + dv.y, z + du.z + dv.z) else 0
	return 3 - (s1 + s2 + c)


static func _shade(c: Color, ao_level: int) -> Color:
	var k: float = AO_CURVE[ao_level]
	return Color(c.r * k, c.g * k, c.b * k, c.a)
