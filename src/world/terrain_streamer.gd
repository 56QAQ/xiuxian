class_name TerrainStreamer
extends Node3D
## 地形区块流式加载：围绕焦点（focus）按距离优先加载 32×32 米区块。
## 网格数组在 WorkerThreadPool（高优先级任务，低优先级在 4 核机器上只有 1 个线程）中生成，
## 主线程每帧按时间预算创建节点（MeshInstance3D + StaticBody3D/HeightMapShape3D，world 层）。
## 另有全图远景 LOD（8 米格，16 块），在已完整加载的近景圆内由着色器丢弃片元。
## 监听 TerrainGen.changed（弹坑）：立即更新碰撞，异步重建网格，喷出碎块。

signal chunk_loaded(key: Vector2i)

const LAYER_WORLD := 1

## 视距（区块半径）
var view_chunks := 7
## 同时进行的工作线程任务数（与道具散布合计不超过 CPU 核数 - 1，避免主线程被抢占）
var max_tasks := maxi(OS.get_processor_count() - 2, 1)
## 每帧创建节点的时间预算（微秒）
var frame_budget_usec := 5000
var terrain: TerrainGen
var focus: Node3D
var focus_pos := Vector3(512, 30, 512)

var _chunks: Dictionary = {}      # Vector2i -> {"mesh": MeshInstance3D, "body": StaticBody3D, "shape": HeightMapShape3D}
var _tasks: Dictionary = {}       # Vector2i -> task id
var _results: Dictionary = {}     # Vector2i -> Dictionary（工作线程写入，_mutex 保护）
var _ready_list: Array[Vector2i] = []
var _dirty: Dictionary = {}       # 需要重建的已加载区块
var _mutex := Mutex.new()
var _near_mat: ShaderMaterial
var _lod_mat: ShaderMaterial
var _lod_root: Node3D
var _lod_tiles: Dictionary = {}   # Vector2i -> MeshInstance3D
var _lod_dirty: Dictionary = {}
var _last_center := Vector2i(-999, -999)
var _wanted: Array[Vector2i] = []
var _hole_radius := 0.0
## 额外的 LOD 丢弃圆（截图等多处同时加载时使用）：Vector4(x, z, 半径, 0)
var extra_holes: Array[Vector4] = []
## 统计
var stats := {"built": 0, "build_ms_total": 0.0, "apply_ms_max": 0.0}


func _init(t: TerrainGen = null) -> void:
	terrain = t


func _ready() -> void:
	var sh: Shader = load("res://assets/shaders/terrain.gdshader")
	_near_mat = ShaderMaterial.new()
	_near_mat.shader = sh
	_lod_mat = ShaderMaterial.new()
	_lod_mat.shader = sh
	_lod_mat.set_shader_parameter("block_size", float(TerrainGen.LOD_CELL))
	_lod_mat.set_shader_parameter("detail_distance", 0.0)
	_lod_mat.set_shader_parameter("variation", 0.05)
	_lod_mat.set_shader_parameter("texel_variation", 0.0)
	_lod_mat.set_shader_parameter("edge_strength", 0.0)
	_lod_root = Node3D.new()
	_lod_root.name = "LOD"
	add_child(_lod_root)
	if terrain != null:
		if not terrain.changed.is_connected(_on_terrain_changed):
			terrain.changed.connect(_on_terrain_changed)
		_build_lod_all()


func _exit_tree() -> void:
	# 等待未完成的任务，避免回调访问已释放对象
	for key in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
	_tasks.clear()
	if terrain != null and terrain.changed.is_connected(_on_terrain_changed):
		terrain.changed.disconnect(_on_terrain_changed)


func set_focus(node: Node3D) -> void:
	focus = node
	if focus != null and focus.is_inside_tree():
		focus_pos = focus.global_position


func is_chunk_loaded(key: Vector2i) -> bool:
	return _chunks.has(key)


func loaded_count() -> int:
	return _chunks.size()


func pending_count() -> int:
	return _tasks.size() + _ready_list.size() + _dirty.size()


# ================================================================ LOD

func _build_lod_all() -> void:
	var n := TerrainGen.LOD_TILES
	var results: Array = []
	results.resize(n * n)
	var gid := WorkerThreadPool.add_group_task(func(i: int) -> void:
		results[i] = terrain.build_lod_arrays(i % n, i / n), n * n, -1, true, "terrain_lod")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	for i in n * n:
		_set_lod_tile(Vector2i(i % n, i / n), results[i])


func _set_lod_tile(key: Vector2i, arrays: Array) -> void:
	var mi: MeshInstance3D = _lod_tiles.get(key)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "LOD_%d_%d" % [key.x, key.y]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _lod_mat
		_lod_root.add_child(mi)
		_lod_tiles[key] = mi
	var mesh := ArrayMesh.new()
	if not arrays.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = mesh


# ================================================================ 主循环

func _process(_delta: float) -> void:
	if terrain == null:
		return
	var tf := Time.get_ticks_usec()
	_step()
	stats["frame_ms_max"] = maxf(float(stats.get("frame_ms_max", 0.0)), (Time.get_ticks_usec() - tf) / 1000.0)


func _step() -> void:
	if focus != null and is_instance_valid(focus) and focus.is_inside_tree():
		focus_pos = focus.global_position
	var center := Vector2i(floori(focus_pos.x / TerrainGen.CHUNK), floori(focus_pos.z / TerrainGen.CHUNK))
	if center != _last_center:
		_last_center = center
		_update_wanted(center)
		_unload_far(center)
	_poll_tasks()
	_dispatch()
	_apply_ready()
	_update_lod_dirty()
	_update_hole()


func _update_wanted(center: Vector2i) -> void:
	_wanted.clear()
	var r := view_chunks
	var list: Array = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := Vector2i(center.x + dx, center.y + dz)
			if k.x < 0 or k.y < 0 or k.x >= TerrainGen.CHUNKS or k.y >= TerrainGen.CHUNKS:
				continue
			var d := Vector2(dx, dz).length()
			if d > r + 0.5:
				continue
			list.append([d, k])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for e in list:
		_wanted.append(e[1])


func _unload_far(center: Vector2i) -> void:
	var limit := view_chunks + 1.8
	var drop: Array[Vector2i] = []
	for k: Vector2i in _chunks:
		if Vector2(k - center).length() > limit:
			drop.append(k)
	for k in drop:
		var ch: Dictionary = _chunks[k]
		(ch["mesh"] as Node).queue_free()
		(ch["body"] as Node).queue_free()
		_chunks.erase(k)
		_dirty.erase(k)


func _dispatch() -> void:
	# 优先：已加载但需重建的区块（弹坑），其次按距离排序的缺失区块
	for k: Vector2i in _dirty.keys():
		if _tasks.size() >= max_tasks + 1:
			return
		if _tasks.has(k):
			continue
		_dirty.erase(k)
		_start_task(k)
	for k in _wanted:
		if _tasks.size() >= max_tasks:
			return
		if _chunks.has(k) or _tasks.has(k) or _ready_list.has(k):
			continue
		_start_task(k)


func _start_task(k: Vector2i) -> void:
	_tasks[k] = WorkerThreadPool.add_task(_task_build.bind(k), true, "chunk")


func _task_build(k: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	var data := terrain.build_chunk_arrays(k.x, k.y)
	data["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	_mutex.lock()
	_results[k] = data
	_mutex.unlock()


func _poll_tasks() -> void:
	var done: Array[Vector2i] = []
	for k: Vector2i in _tasks:
		if WorkerThreadPool.is_task_completed(_tasks[k]):
			done.append(k)
	for k in done:
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
		_tasks.erase(k)
		if not _ready_list.has(k):
			_ready_list.append(k)


func _apply_ready() -> void:
	var t0 := Time.get_ticks_usec()
	while not _ready_list.is_empty():
		var k: Vector2i = _ready_list.pop_front()
		_mutex.lock()
		var data: Dictionary = _results.get(k, {})
		_results.erase(k)
		_mutex.unlock()
		if data.is_empty():
			continue
		# 已离开视距的结果丢弃
		if not _chunks.has(k) and Vector2(k - _last_center).length() > view_chunks + 1.8:
			continue
		var ta := Time.get_ticks_usec()
		_apply_chunk(k, data)
		stats["built"] = int(stats["built"]) + 1
		stats["build_ms_total"] = float(stats["build_ms_total"]) + float(data.get("ms", 0.0))
		stats["apply_ms_max"] = maxf(float(stats["apply_ms_max"]), (Time.get_ticks_usec() - ta) / 1000.0)
		chunk_loaded.emit(k)
		if Time.get_ticks_usec() - t0 > frame_budget_usec:
			break


func _apply_chunk(k: Vector2i, data: Dictionary) -> void:
	var ch: Dictionary = _chunks.get(k, {})
	if ch.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%d_%d" % [k.x, k.y]
		mi.material_override = _near_mat
		add_child(mi)
		var body := StaticBody3D.new()
		body.name = "ChunkBody_%d_%d" % [k.x, k.y]
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := HeightMapShape3D.new()
		shape.map_width = 33
		shape.map_depth = 33
		cs.shape = shape
		body.add_child(cs)
		body.position = Vector3(k.x * TerrainGen.CHUNK + 16.5, 0.0, k.y * TerrainGen.CHUNK + 16.5)
		add_child(body)
		ch = {"mesh": mi, "body": body, "shape": shape}
		_chunks[k] = ch
	var mesh := ArrayMesh.new()
	var arrays: Array = data["arrays"]
	if not arrays.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	(ch["mesh"] as MeshInstance3D).mesh = mesh
	(ch["shape"] as HeightMapShape3D).map_data = data["collision"]


## 同步加载焦点周围 radius 个区块半径内的全部区块（开局/截图用，使用全部核心）
func prime(radius: int = -1) -> void:
	if radius < 0:
		radius = view_chunks
	if focus != null and is_instance_valid(focus) and focus.is_inside_tree():
		focus_pos = focus.global_position
	var center := Vector2i(floori(focus_pos.x / TerrainGen.CHUNK), floori(focus_pos.z / TerrainGen.CHUNK))
	_last_center = center
	var saved := view_chunks
	view_chunks = radius
	_update_wanted(center)
	view_chunks = saved
	var keys: Array[Vector2i] = []
	for k in _wanted:
		if not _chunks.has(k) and not _tasks.has(k):
			keys.append(k)
	var results: Array = []
	results.resize(keys.size())
	if not keys.is_empty():
		var gid := WorkerThreadPool.add_group_task(func(i: int) -> void:
			results[i] = terrain.build_chunk_arrays(keys[i].x, keys[i].y), keys.size(), -1, true, "chunk_prime")
		WorkerThreadPool.wait_for_group_task_completion(gid)
	for i in keys.size():
		_apply_chunk(keys[i], results[i])
		chunk_loaded.emit(keys[i])
	_update_wanted(center)
	_update_hole()


# ================================================================ 弹坑 / 修改

func _on_terrain_changed(chunks: Array, samples: Array, pos: Vector3, radius: float) -> void:
	for k in chunks:
		var key: Vector2i = k
		if _chunks.has(key):
			# 碰撞立即更新
			var col := PackedFloat32Array()
			col.resize(33 * 33)
			var x0 := key.x * TerrainGen.CHUNK
			var z0 := key.y * TerrainGen.CHUNK
			for j in 33:
				for i in 33:
					col[j * 33 + i] = float(terrain.get_block_height(mini(x0 + i, TerrainGen.SIZE - 1), mini(z0 + j, TerrainGen.SIZE - 1)))
			(_chunks[key]["shape"] as HeightMapShape3D).map_data = col
			_dirty[key] = true
		_lod_dirty[Vector2i(key.x / 8, key.y / 8)] = true
	if not samples.is_empty() and is_inside_tree():
		var pool := DebrisPool.get_pool(self)
		if pool:
			var pick: Array = []
			var n := clampi(int(radius * 2.0), 4, 14)
			for i in mini(n, samples.size()):
				pick.append(samples[(i * 7) % samples.size()])
			pool.burst(pos, pick, clampf(radius / 4.0, 0.6, 2.0), 0.45)


func _update_lod_dirty() -> void:
	if _lod_dirty.is_empty():
		return
	for k: Vector2i in _lod_dirty:
		_set_lod_tile(k, terrain.build_lod_arrays(k.x, k.y))
	_lod_dirty.clear()


## LOD 丢弃半径：焦点到最近一个“未加载区块”的距离（此圆内全部由近景区块覆盖）
func _update_hole() -> void:
	var r := view_chunks + 2
	var best := 1e9
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := Vector2i(_last_center.x + dx, _last_center.y + dz)
			if k.x < 0 or k.y < 0 or k.x >= TerrainGen.CHUNKS or k.y >= TerrainGen.CHUNKS:
				continue
			if _chunks.has(k):
				continue
			var x0 := float(k.x * TerrainGen.CHUNK)
			var z0 := float(k.y * TerrainGen.CHUNK)
			var cx := clampf(focus_pos.x, x0, x0 + TerrainGen.CHUNK)
			var cz := clampf(focus_pos.z, z0, z0 + TerrainGen.CHUNK)
			var d := Vector2(focus_pos.x - cx, focus_pos.z - cz).length()
			best = minf(best, d)
	if best > 1e8:
		best = (r + 1) * TerrainGen.CHUNK
	_hole_radius = maxf(best - 2.0, 0.0)
	if not extra_holes.is_empty():
		var arr: Array = [Vector4(focus_pos.x, focus_pos.z, _hole_radius, 0.0)]
		for h in extra_holes:
			arr.append(h)
		while arr.size() < 4:
			arr.append(Vector4.ZERO)
		_lod_mat.set_shader_parameter("holes", arr.slice(0, 4))
	else:
		_lod_mat.set_shader_parameter("holes", [Vector4(focus_pos.x, focus_pos.z, _hole_radius, 0.0), Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])
