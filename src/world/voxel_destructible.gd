class_name VoxelDestructible
extends StaticBody3D
## 可破坏体素物体（world 层 1 + destructible 层 7）。持有一个 VoxelGrid（体素边长约 0.125~0.3 米）。
## apply_damage_at(point, radius, power)：剔除半径内的体素（参差边缘），喷出对象池碎块（debris 层 5），
## 重建网格与碰撞（三角网格），再从底层锚定体素做连通性洪泛——失去支撑的孤岛整体变成下落的刚体碎块。
## 未受损时共享模板网格/碰撞（DestructibleFactory 缓存），首次受损才生成自己的网格。

signal destroyed_voxels(count: int)

const LAYER_WORLD := 1
const LAYER_DESTRUCTIBLE := 1 << 6
const MAX_FALLING := 12
const MIN_ISLAND := 5

static var _falling_live := 0

var grid: VoxelGrid
var voxel_size := 0.25
## 体素 (0,0,0) 最小角在本地坐标中的位置
var origin := Vector3.ZERO
## y <= anchor_y 的体素视为与地面相连
var anchor_y := 0
var template_key := ""
var mesh_instance: MeshInstance3D
var col_shape: CollisionShape3D
var total_removed := 0
var _count := -1
var _mesh: ArrayMesh
var _shape: Shape3D


func setup(g: VoxelGrid, vs: float, org: Vector3, mesh: ArrayMesh = null, shape: Shape3D = null, key: String = "") -> VoxelDestructible:
	grid = g
	voxel_size = vs
	origin = org
	_mesh = mesh
	_shape = shape
	template_key = key
	return self


func _ready() -> void:
	collision_layer = LAYER_WORLD | LAYER_DESTRUCTIBLE
	collision_mask = 0
	add_to_group("destructible")
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	add_child(mesh_instance)
	col_shape = CollisionShape3D.new()
	col_shape.name = "Shape"
	add_child(col_shape)
	if _mesh == null:
		_rebuild()
	else:
		mesh_instance.mesh = _mesh
		col_shape.shape = _shape if _shape != null else _mesh.create_trimesh_shape()


func voxel_count() -> int:
	if _count < 0:
		_count = grid.count_solid() if grid else 0
	return _count


## 世界坐标 → 网格坐标（连续）
func world_to_grid(p: Vector3) -> Vector3:
	return (to_local(p) - origin) / voxel_size


## 网格体素中心 → 世界坐标
func grid_to_world(x: int, y: int, z: int) -> Vector3:
	return to_global(origin + (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * voxel_size)


static func _hash3(x: int, y: int, z: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0xffff) / 65535.0


## 在 point 处造成破坏：半径 radius（米），power 放大半径与碎块速度。返回移除的体素数。
func apply_damage_at(point: Vector3, radius: float, power: float = 1.0) -> int:
	if grid == null:
		return 0
	var g := world_to_grid(point)
	var r := maxf(radius * clampf(0.8 + 0.2 * power, 0.6, 1.6) / voxel_size, 0.75)
	var lo := Vector3i((g - Vector3.ONE * r * 1.3).floor()).clamp(Vector3i.ZERO, Vector3i(grid.sx - 1, grid.sy - 1, grid.sz - 1))
	var hi := Vector3i((g + Vector3.ONE * r * 1.3).ceil()).clamp(Vector3i.ZERO, Vector3i(grid.sx - 1, grid.sy - 1, grid.sz - 1))
	var removed := PackedInt32Array()
	var removed_col := PackedInt32Array()
	var data := grid.data
	var sx := grid.sx
	var sy := grid.sy
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var idx := x + sx * (y + sy * z)
				var raw := data[idx]
				if raw == 0:
					continue
				var d := (Vector3(x + 0.5, y + 0.5, z + 0.5) - g).length()
				if d < r * (0.7 + 0.6 * _hash3(x, y, z)):
					data[idx] = 0
					removed.append(idx)
					removed_col.append(raw)
	if removed.is_empty():
		return 0
	grid.data = data
	var n := removed.size()
	# 碎块
	var pool := DebrisPool.get_pool(self) if is_inside_tree() else null
	if pool:
		var k := clampi(n / 3, 2, 16)
		var step := maxi(n / k, 1)
		for i in range(0, n, step):
			var idx := removed[i]
			var x := idx % sx
			var y := (idx / sx) % sy
			var z := idx / (sx * sy)
			var wp := grid_to_world(x, y, z)
			var dir := (wp - point)
			dir.y = absf(dir.y) + 0.4
			var vel := dir.normalized() * randf_range(3.0, 6.5) * (0.7 + 0.3 * power) + Vector3(0, randf_range(1.5, 4.0), 0)
			pool.spawn(wp, voxel_size * randf_range(1.0, 1.7), VoxelGrid.decode(removed_col[i]), vel)
	var fell := _detach_islands(point, power)
	total_removed += n
	_count = -1
	_rebuild()
	destroyed_voxels.emit(n + fell)
	if is_inside_tree():
		Audio.play_at("rock_break", point)
	if voxel_count() == 0:
		queue_free()
	return n


## 连通性：从锚定层洪泛，未连通的孤岛整体脱落。返回脱落的体素数。
func _detach_islands(hit: Vector3, power: float) -> int:
	var sx := grid.sx
	var sy := grid.sy
	var sz := grid.sz
	var data := grid.data
	var total := sx * sy * sz
	var mark := PackedByteArray()
	mark.resize(total)
	var queue := PackedInt32Array()
	for z in sz:
		for y in mini(anchor_y + 1, sy):
			for x in sx:
				var idx := x + sx * (y + sy * z)
				if data[idx] != 0:
					mark[idx] = 1
					queue.append(idx)
	_flood(queue, mark, data, 1)
	var fell := 0
	var layer := sx * sy
	for start in total:
		if data[start] == 0 or mark[start] != 0:
			continue
		# 收集一个孤岛
		mark[start] = 2
		var comp := PackedInt32Array([start])
		var head := 0
		while head < comp.size():
			var idx := comp[head]
			head += 1
			var x := idx % sx
			var y := (idx / sx) % sy
			var z := idx / layer
			if x > 0 and data[idx - 1] != 0 and mark[idx - 1] == 0:
				mark[idx - 1] = 2
				comp.append(idx - 1)
			if x < sx - 1 and data[idx + 1] != 0 and mark[idx + 1] == 0:
				mark[idx + 1] = 2
				comp.append(idx + 1)
			if y > 0 and data[idx - sx] != 0 and mark[idx - sx] == 0:
				mark[idx - sx] = 2
				comp.append(idx - sx)
			if y < sy - 1 and data[idx + sx] != 0 and mark[idx + sx] == 0:
				mark[idx + sx] = 2
				comp.append(idx + sx)
			if z > 0 and data[idx - layer] != 0 and mark[idx - layer] == 0:
				mark[idx - layer] = 2
				comp.append(idx - layer)
			if z < sz - 1 and data[idx + layer] != 0 and mark[idx + layer] == 0:
				mark[idx + layer] = 2
				comp.append(idx + layer)
		_spawn_island(comp, hit, power)
		for idx in comp:
			data[idx] = 0
		fell += comp.size()
	grid.data = data
	return fell


func _flood(queue: PackedInt32Array, mark: PackedByteArray, data: PackedInt32Array, tag: int) -> void:
	var sx := grid.sx
	var sy := grid.sy
	var sz := grid.sz
	var layer := sx * sy
	var head := 0
	while head < queue.size():
		var idx := queue[head]
		head += 1
		var x := idx % sx
		var y := (idx / sx) % sy
		var z := idx / layer
		if x > 0 and data[idx - 1] != 0 and mark[idx - 1] == 0:
			mark[idx - 1] = tag
			queue.append(idx - 1)
		if x < sx - 1 and data[idx + 1] != 0 and mark[idx + 1] == 0:
			mark[idx + 1] = tag
			queue.append(idx + 1)
		if y > 0 and data[idx - sx] != 0 and mark[idx - sx] == 0:
			mark[idx - sx] = tag
			queue.append(idx - sx)
		if y < sy - 1 and data[idx + sx] != 0 and mark[idx + sx] == 0:
			mark[idx + sx] = tag
			queue.append(idx + sx)
		if z > 0 and data[idx - layer] != 0 and mark[idx - layer] == 0:
			mark[idx - layer] = tag
			queue.append(idx - layer)
		if z < sz - 1 and data[idx + layer] != 0 and mark[idx + layer] == 0:
			mark[idx + layer] = tag
			queue.append(idx + layer)


func _spawn_island(comp: PackedInt32Array, hit: Vector3, power: float) -> void:
	if not is_inside_tree():
		return
	var sx := grid.sx
	var sy := grid.sy
	var layer := sx * sy
	if comp.size() < MIN_ISLAND or _falling_live >= MAX_FALLING:
		var pool := DebrisPool.get_pool(self)
		if pool:
			for i in mini(comp.size(), 4):
				var idx := comp[i * comp.size() / mini(comp.size(), 4)]
				pool.spawn(grid_to_world(idx % sx, (idx / sx) % sy, idx / layer), voxel_size * 1.4, VoxelGrid.decode(grid.data[idx]), Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1)))
		return
	var lo := Vector3i(sx, sy, grid.sz)
	var hi := Vector3i(-1, -1, -1)
	for idx in comp:
		var p := Vector3i(idx % sx, (idx / sx) % sy, idx / layer)
		lo = Vector3i(mini(lo.x, p.x), mini(lo.y, p.y), mini(lo.z, p.z))
		hi = Vector3i(maxi(hi.x, p.x), maxi(hi.y, p.y), maxi(hi.z, p.z))
	var size := hi - lo + Vector3i.ONE
	var sub := VoxelGrid.new(size.x, size.y, size.z)
	for idx in comp:
		var p := Vector3i(idx % sx, (idx / sx) % sy, idx / layer) - lo
		sub.set_raw(p.x, p.y, p.z, grid.data[idx])
	var half := Vector3(size) * voxel_size * 0.5
	var mesh := VoxelMesher.build(sub, voxel_size, -half)
	var frag := VoxelFragment.new()
	frag.setup(mesh, comp.size(), voxel_size)
	var center_local := origin + (Vector3(lo) * voxel_size) + half
	get_parent().add_child(frag)
	frag.global_transform = Transform3D(global_transform.basis.orthonormalized(), to_global(center_local))
	var away := frag.global_position - hit
	away.y = 0.0
	frag.linear_velocity = away.normalized() * 1.2 * power + Vector3(0, 0.5, 0)
	frag.angular_velocity = Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.3), randf_range(-0.6, 0.6))


static func falling_live() -> int:
	return _falling_live


static func _falling_changed(d: int) -> void:
	_falling_live = maxi(_falling_live + d, 0)


func _rebuild() -> void:
	if grid == null or mesh_instance == null:
		return
	var mesh := BlockMesher.build(grid, voxel_size, origin)
	mesh_instance.mesh = mesh
	if mesh.get_surface_count() > 0:
		col_shape.shape = mesh.create_trimesh_shape()
	else:
		col_shape.shape = null
