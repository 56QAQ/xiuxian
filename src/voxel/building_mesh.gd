class_name BuildingMesh
extends RefCounted
## 盒子累加器：把大量彩色长方体合并成一个 ArrayMesh（共享 voxel.gdshader 材质，顶点色 sRGB，alpha<1 自发光），
## 并收集碰撞盒。支持以 90° 倍数旋转的局部坐标栈（push/pop），便于朝向不同的建筑部件复用。
## 面着色：侧面底部略暗、底面更暗（廉价的伪 AO），并对每个盒子做轻微的颜色抖动。

const SIDE_BOTTOM := 0.84
const BOTTOM := 0.62

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
## 碰撞盒（本网格坐标系下的 AABB）
var col_boxes: Array[AABB] = []
## 斜坡碰撞（楼梯）：[Transform3D, Vector3 尺寸]
var col_ramps: Array = []
## 每个盒子的颜色抖动幅度
var jitter := 0.035
var _stack: Array[Transform3D] = []
var _xf := Transform3D.IDENTITY
var _rng := RandomNumberGenerator.new()


func _init(seed_v: int = 1) -> void:
	_rng.seed = seed_v


## 进入局部坐标：原点 origin（相对当前坐标），绕 Y 旋转 quarter×90°
func push(origin: Vector3, quarter: int = 0) -> void:
	_stack.append(_xf)
	var b := Basis(Vector3.UP, quarter * PI * 0.5)
	# 消除浮点误差，保证轴对齐
	for i in 3:
		b[i] = b[i].round()
	_xf = _xf * Transform3D(b, origin)


func pop() -> void:
	_xf = _stack.pop_back()


func quad_count() -> int:
	return verts.size() / 4


## 长方体 [a, b]（当前局部坐标）。collide=true 时加入碰撞。no_bottom 省略底面。
## top（alpha>0 时）为顶面单独颜色。
func box(a: Vector3, b: Vector3, c: Color, collide: bool = false, no_bottom: bool = false, top: Color = Color(0, 0, 0, 0)) -> void:
	var p0 := _xf * a
	var p1 := _xf * b
	var lo := Vector3(minf(p0.x, p1.x), minf(p0.y, p1.y), minf(p0.z, p1.z))
	var hi := Vector3(maxf(p0.x, p1.x), maxf(p0.y, p1.y), maxf(p0.z, p1.z))
	if hi.x - lo.x < 0.001 or hi.y - lo.y < 0.001 or hi.z - lo.z < 0.001:
		return
	if jitter > 0.0:
		var k := 1.0 + _rng.randf_range(-jitter, jitter)
		c = Color(c.r * k, c.g * k, c.b * k, c.a)
		if top.a > 0.0:
			top = Color(top.r * k, top.g * k, top.b * k, top.a)
	_add_box(lo, hi, c, no_bottom, top if top.a > 0.0 else c)
	if collide:
		col_boxes.append(AABB(lo, hi - lo))


## 斜坡碰撞：从 a（底部前沿中心，局部）升到 b（顶部后沿中心），宽 width
func ramp(a: Vector3, b: Vector3, width: float) -> void:
	var pa := _xf * a
	var pb := _xf * b
	var d := pb - pa
	var flat := Vector3(d.x, 0, d.z)
	var length := d.length()
	if length < 0.01 or flat.length() < 0.01:
		return
	var fwd := d / length
	var side := Vector3.UP.cross(flat.normalized()).normalized()
	var up := fwd.cross(side).normalized()
	if up.y < 0.0:
		up = -up
		side = -side
	var basis := Basis(side, up, fwd)
	var center := (pa + pb) * 0.5 - up * 0.25
	col_ramps.append([Transform3D(basis, center), Vector3(width, 0.5, length)])


## 以中心与尺寸指定的长方体
func box_c(center: Vector3, size: Vector3, c: Color, collide: bool = false) -> void:
	box(center - size * 0.5, center + size * 0.5, c, collide)


## 只加碰撞（不渲染）
func collider(a: Vector3, b: Vector3) -> void:
	var p0 := _xf * a
	var p1 := _xf * b
	var lo := Vector3(minf(p0.x, p1.x), minf(p0.y, p1.y), minf(p0.z, p1.z))
	var hi := Vector3(maxf(p0.x, p1.x), maxf(p0.y, p1.y), maxf(p0.z, p1.z))
	col_boxes.append(AABB(lo, hi - lo))


func _add_box(lo: Vector3, hi: Vector3, c: Color, no_bottom: bool, ct: Color) -> void:
	var cb := Color(c.r * SIDE_BOTTOM, c.g * SIDE_BOTTOM, c.b * SIDE_BOTTOM, c.a)
	var cd := Color(c.r * BOTTOM, c.g * BOTTOM, c.b * BOTTOM, c.a)
	# +X
	_quad(Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3.RIGHT, cb, cb, c, c)
	# -X
	_quad(Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3.LEFT, cb, c, c, cb)
	# +Y
	_quad(Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3.UP, ct, ct, ct, ct)
	# -Y
	if not no_bottom:
		_quad(Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3.DOWN, cd, cd, cd, cd)
	# +Z
	_quad(Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3.BACK, cb, c, c, cb)
	# -Z
	_quad(Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3.FORWARD, cb, cb, c, c)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	var i := verts.size()
	verts.append(a)
	verts.append(b)
	verts.append(c)
	verts.append(d)
	normals.append(n)
	normals.append(n)
	normals.append(n)
	normals.append(n)
	colors.append(ca)
	colors.append(cb)
	colors.append(cc)
	colors.append(cd)
	indices.append(i)
	indices.append(i + 1)
	indices.append(i + 2)
	indices.append(i)
	indices.append(i + 2)
	indices.append(i + 3)


## 合并另一个累加器（例如在线程中分别构建）
func merge(other: BuildingMesh) -> void:
	var base := verts.size()
	verts.append_array(other.verts)
	normals.append_array(other.normals)
	colors.append_array(other.colors)
	for i in other.indices:
		indices.append(i + base)
	col_boxes.append_array(other.col_boxes)
	col_ramps.append_array(other.col_ramps)


func build_arrays() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func build_mesh(mat: Material = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, build_arrays())
	mesh.surface_set_material(0, mat if mat != null else VoxelMesher.material())
	return mesh


func build_instance() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = build_mesh()
	return mi


## 生成静态碰撞体（默认 world 层）：碰撞盒 + 楼梯斜坡
func build_body(layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	for bx in col_boxes:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = bx.size
		cs.shape = shape
		cs.position = bx.get_center()
		body.add_child(cs)
	for r in col_ramps:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = r[1]
		cs.shape = shape
		cs.transform = r[0]
		body.add_child(cs)
	return body
