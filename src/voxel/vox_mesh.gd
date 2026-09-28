class_name VoxMesh
## VoxCanvas → ArrayMesh 的快速网格化（隐藏面剔除 + 逐顶点 AO + 二维贪心合并）。
## 顶点色 rgb = sRGB 颜色 × AO，alpha = 体素属性字节 / 255（材质 << 4 | 发光等级），由 voxel_char.gdshader 解读。
##
## 部件系统（角色/兵器/妖兽共用）：
##   VoxMesh.begin_batch() … VoxMesh.part(key, maker) … VoxMesh.end_batch()
##   part() 立即返回占位网格 [LOD0, LOD1]（ArrayMesh 对象，可直接赋给 MeshInstance3D）；
##   end_batch() 把缓存未命中的部件分发到 WorkerThreadPool（高优先级）并行生成（maker 在工作线程中调用，
##   必须只读取预先算好的数据与 static var），再在主线程填充占位网格。
##   async=true 时 end_batch() 不等待，返回任务句柄；VoxMesh.poll() / is_done() 在主线程完成填充。
##   LOD1 = 画布 2× 降采样后网格化（体素边长 ×2）。
## 另有静态网格缓存（按部件参数键），相同部件（NPC 人群、同种妖兽）几乎零开销。

## 工作线程中不能读 const 数组（Godot 4.4），以下表都用 static var
static var AO_CURVE: PackedFloat32Array = PackedFloat32Array([0.50, 0.68, 0.85, 1.0])
static var _NV: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
static var _UV: Array[Vector3i] = [Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0)]
static var _VV: Array[Vector3i] = [Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0)]
## 主合并方向：±X/±Z 面沿 Y（发丝、布褶多为竖向），±Y 面沿 X；true = 沿 u
static var _ALONG_U: Array[bool] = [false, true, true, false, true, false]

const CACHE_MAX := 900
static var _cache: Dictionary = {}
static var cache_hits: int = 0
static var cache_misses: int = 0
static var threaded: bool = true
## 调试：记录每个部件的耗时（毫秒）{key: [绘制, LOD0 网格, LOD1]}
static var profile: bool = false
static var profile_log: Dictionary = {}

static var _material: ShaderMaterial
static var _batch_depth: int = 0
static var _batch_async: bool = false
static var _batch_jobs: Array = []
static var _batch_wait: Array = []      ## 本批次用到的、尚未完成的异步任务
static var _groups: Array = []          ## 进行中的异步任务 {gid, jobs, done}
static var _key_group: Dictionary = {}  ## 进行中的部件键 → 任务
static var _last_poll: int = -1


## 角色共享材质（voxel_char.gdshader）
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://assets/shaders/voxel_char.gdshader")
	return _material


# ================================================================ 直接网格化（同步、无缓存）

## 把若干画布合并为一个网格（同一骨骼上的部件合并可减少绘制调用）
static func build(canvases: Array, vs: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_set_surface(mesh, mesh_arrays(canvases, vs))
	return mesh


static func build_one(cv: VoxCanvas, vs: float) -> ArrayMesh:
	return build([cv], vs)


## 旧接口：key 相同直接返回已有网格；否则调用 maker（返回 ArrayMesh）
static func cached(key: String, maker: Callable) -> ArrayMesh:
	if _cache.has(key):
		cache_hits += 1
		var v: Variant = _cache[key]
		return v[0] if v is Array else v
	cache_misses += 1
	var m: ArrayMesh = maker.call()
	_store(key, m)
	return m


static func clear_cache() -> void:
	# 进行中的异步任务先完成（其占位网格仍被角色引用）
	for g in _groups.duplicate():
		_finish(g)
	_cache.clear()


static func _store(key: String, v: Variant) -> void:
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	_cache[key] = v


static func _set_surface(mesh: ArrayMesh, arrays: Array) -> void:
	if arrays.is_empty():
		return
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())


# ================================================================ 部件批处理

static func begin_batch(async: bool = false) -> void:
	if _batch_depth == 0:
		_batch_async = async
		_batch_jobs = []
		_batch_wait = []
	_batch_depth += 1


## 请求部件：返回 [LOD0 网格, LOD1 网格]。maker 返回 VoxCanvas 或 VoxCanvas 数组。
## 不在批处理中时立即同步生成。
static func part(key: String, maker: Callable, vs: float) -> Array:
	if _cache.has(key):
		var v: Variant = _cache[key]
		if v is Array:
			cache_hits += 1
			if _key_group.has(key):
				var g: Dictionary = _key_group[key]
				if _batch_depth > 0:
					if not _batch_wait.has(g):
						_batch_wait.append(g)
				else:
					_finish(g)
			return v
	cache_misses += 1
	var job := {"key": key, "maker": maker, "vs": vs, "m0": ArrayMesh.new(), "m1": ArrayMesh.new()}
	var pair: Array = [job["m0"], job["m1"]]
	_store(key, pair)
	if _batch_depth > 0:
		_batch_jobs.append(job)
	else:
		_run_job(job)
		_fill(job)
	return pair


## 结束批处理。同步：生成全部缺失部件后返回 null；异步：返回任务列表（交给 is_done() 轮询），无任务时返回 []
static func end_batch() -> Variant:
	_batch_depth -= 1
	if _batch_depth > 0:
		return null
	_batch_depth = 0
	var jobs := _batch_jobs
	var wait := _batch_wait
	_batch_jobs = []
	_batch_wait = []
	if _batch_async:
		var recs: Array = wait.duplicate()
		if not jobs.is_empty():
			var g := _dispatch(jobs)
			recs.append(g)
		return recs
	# 同步：先完成依赖的异步任务，再并行生成本批次
	for g in wait:
		_finish(g)
	if jobs.is_empty():
		return null
	if not threaded or jobs.size() == 1:
		for j in jobs:
			_run_job(j)
	else:
		var list: Array = jobs
		var gid := WorkerThreadPool.add_group_task(func(i: int) -> void: VoxMesh._run_job(list[i]), list.size(), -1, true, "vox_parts")
		WorkerThreadPool.wait_for_group_task_completion(gid)
	for j in jobs:
		_fill(j)
	return null


static func _dispatch(jobs: Array) -> Dictionary:
	var list: Array = jobs
	var g := {"jobs": list, "done": false, "gid": -1}
	if threaded:
		g["gid"] = WorkerThreadPool.add_group_task(func(i: int) -> void: VoxMesh._run_job(list[i]), list.size(), -1, true, "vox_parts_async")
	else:
		for j in list:
			_run_job(j)
	for j in list:
		_key_group[str(j["key"])] = g
	_groups.append(g)
	return g


## 主线程：检查异步任务，完成的填充网格（每帧最多一次）
static func poll() -> void:
	var f := Engine.get_process_frames()
	if f == _last_poll:
		return
	_last_poll = f
	for g in _groups.duplicate():
		if int(g["gid"]) < 0 or WorkerThreadPool.is_group_task_completed(int(g["gid"])):
			_finish(g)


## 任务列表（end_batch 异步返回值）是否全部完成
static func is_done(recs: Array) -> bool:
	poll()
	for g in recs:
		if not bool((g as Dictionary)["done"]):
			return false
	return true


## 等待任务完成（阻塞）
static func finish_all(recs: Array) -> void:
	for g in recs:
		_finish(g)


static func _finish(g: Dictionary) -> void:
	if g["done"]:
		return
	if int(g["gid"]) >= 0:
		WorkerThreadPool.wait_for_group_task_completion(int(g["gid"]))
	for j in g["jobs"]:
		_fill(j)
		if _key_group.get(str(j["key"])) == g:
			_key_group.erase(str(j["key"]))
	g["done"] = true
	_groups.erase(g)


## 工作线程：调用 maker 画布 → 两级 LOD 网格数组
static func _run_job(job: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var r: Variant = (job["maker"] as Callable).call()
	var cvs: Array = r if r is Array else [r]
	var vs: float = job["vs"]
	var t1 := Time.get_ticks_usec()
	job["a0"] = mesh_arrays(cvs, vs)
	var t2 := Time.get_ticks_usec()
	var ds: Array = []
	for cv in cvs:
		if cv != null:
			ds.append((cv as VoxCanvas).downsample(2))
	job["a1"] = mesh_arrays(ds, vs * 2.0)
	job.erase("maker")
	if profile:
		job["prof"] = [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (Time.get_ticks_usec() - t2) / 1000.0]


static func _fill(job: Dictionary) -> void:
	if job.has("filled"):
		return
	job["filled"] = true
	if job.has("prof"):
		profile_log[str(job["key"])] = job["prof"]
	_set_surface(job["m0"], job.get("a0", []))
	_set_surface(job["m1"], job.get("a1", []))
	job.erase("a0")
	job.erase("a1")


# ================================================================ 网格化核心

## 画布数组 → add_surface_from_arrays 所需数组（空网格返回 []）。线程安全。
static func mesh_arrays(canvases: Array, vs: float) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for cv in canvases:
		if cv != null:
			_mesh_canvas(cv as VoxCanvas, vs, verts, normals, colors, indices)
	if verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


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
	var along: Array[bool] = []
	for f in 6:
		var n: Vector3i = _NV[f]
		var u: Vector3i = _UV[f]
		var v: Vector3i = _VV[f]
		nof.append(n.x + n.y * sx + n.z * sxy)
		uof.append(u.x + u.y * sx + u.z * sxy)
		vof.append(v.x + v.y * sx + v.z * sxy)
		nvec.append(Vector3(n))
		pofs.append(Vector3(maxi(n.x, 0), maxi(n.y, 0), maxi(n.z, 0)) * vs)
		uvec.append(Vector3(u) * vs)
		vvec.append(Vector3(v) * vs)
		along.append(_ALONG_U[f])
	var k0: float = AO_CURVE[0]
	var k1: float = AO_CURVE[1]
	var k2: float = AO_CURVE[2]
	var used := PackedByteArray()
	used.resize(d.size())
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
				var um := used[i]
				if um == 63:
					continue
				var col := Color.hex(raw & 0xFFFFFFFF)
				var pmin := origin + Vector3(x, y, z) * vs
				var shaded: Array[Color] = []
				for f in 6:
					var bit := 1 << f
					if um & bit:
						continue
					var nf := nof[f]
					var ni := i + nf
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
					var au: bool = along[f]
					var mo := uo if au else vo       # 主合并方向
					var so := vo if au else uo       # 次合并方向
					var run := 1
					var wid := 1
					var flat := a0 == 3 and a1 == 3 and a2 == 3 and a3 == 3
					if flat:
						# 最常见：四角无遮挡。候选格只需检查 8 个邻格全空
						var j := i + mo
						while d[j] == raw and (used[j] & bit) == 0:
							var nj := j + nf
							if d[nj] != 0 or d[nj + uo] != 0 or d[nj - uo] != 0 or d[nj + vo] != 0 or d[nj - vo] != 0 or d[nj + uo + vo] != 0 or d[nj - uo - vo] != 0 or d[nj + uo - vo] != 0 or d[nj - uo + vo] != 0:
								break
							used[j] = used[j] | bit
							run += 1
							j += mo
						var ls := i + so
						while true:
							var ok := true
							var jj := ls
							for k in run:
								var nj2 := jj + nf
								if d[jj] != raw or (used[jj] & bit) != 0 or d[nj2] != 0 or d[nj2 + uo] != 0 or d[nj2 - uo] != 0 or d[nj2 + vo] != 0 or d[nj2 - vo] != 0 or d[nj2 + uo + vo] != 0 or d[nj2 - uo - vo] != 0 or d[nj2 + uo - vo] != 0 or d[nj2 - uo + vo] != 0:
									ok = false
									break
								jj += mo
							if not ok:
								break
							jj = ls
							for k in run:
								used[jj] = used[jj] | bit
								jj += mo
							wid += 1
							ls += so
					elif (au and a0 == a1 and a3 == a2) or (not au and a0 == a3 and a1 == a2):
						var packed := a0 | (a1 << 2) | (a2 << 4) | (a3 << 6)
						var j := i + mo
						while d[j] == raw and d[j + nf] == 0 and (used[j] & bit) == 0 and _ao_packed(d, j + nf, uo, vo) == packed:
							used[j] = used[j] | bit
							run += 1
							j += mo
						# AO 全平（但有遮挡）时再沿次方向整行扩展
						if a0 == a1 and a1 == a2 and a2 == a3:
							var ls2 := i + so
							while true:
								var ok2 := true
								var jj2 := ls2
								for k in run:
									if d[jj2] != raw or d[jj2 + nf] != 0 or (used[jj2] & bit) != 0 or _ao_packed(d, jj2 + nf, uo, vo) != packed:
										ok2 = false
										break
									jj2 += mo
								if not ok2:
									break
								jj2 = ls2
								for k in run:
									used[jj2] = used[jj2] | bit
									jj2 += mo
								wid += 1
								ls2 += so
					if shaded.is_empty():
						shaded = [Color(col.r * k0, col.g * k0, col.b * k0, col.a), Color(col.r * k1, col.g * k1, col.b * k1, col.a), Color(col.r * k2, col.g * k2, col.b * k2, col.a), col]
					var base := verts.size()
					var pf: Vector3 = pmin + pofs[f]
					var uf: Vector3 = uvec[f]
					var vf: Vector3 = vvec[f]
					if au:
						uf = uf * run
						vf = vf * wid
					else:
						vf = vf * run
						uf = uf * wid
					verts.append(pf)
					verts.append(pf + uf)
					verts.append(pf + uf + vf)
					verts.append(pf + vf)
					var nn: Vector3 = nvec[f]
					normals.append(nn)
					normals.append(nn)
					normals.append(nn)
					normals.append(nn)
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


## 某个面的 4 个角 AO（打包为 8 位），ni 为面外侧的邻格索引
static func _ao_packed(d: PackedInt32Array, ni: int, uo: int, vo: int) -> int:
	var su_p := 1 if d[ni + uo] != 0 else 0
	var su_n := 1 if d[ni - uo] != 0 else 0
	var sv_p := 1 if d[ni + vo] != 0 else 0
	var sv_n := 1 if d[ni - vo] != 0 else 0
	var a0 := 0 if (su_n + sv_n) == 2 else 3 - (su_n + sv_n + (1 if d[ni - uo - vo] != 0 else 0))
	var a1 := 0 if (su_p + sv_n) == 2 else 3 - (su_p + sv_n + (1 if d[ni + uo - vo] != 0 else 0))
	var a2 := 0 if (su_p + sv_p) == 2 else 3 - (su_p + sv_p + (1 if d[ni + uo + vo] != 0 else 0))
	var a3 := 0 if (su_n + sv_p) == 2 else 3 - (su_n + sv_p + (1 if d[ni - uo + vo] != 0 else 0))
	return a0 | (a1 << 2) | (a2 << 4) | (a3 << 6)


## 网格实例工具：为骨骼挂上 LOD0/LOD1 两个 MeshInstance3D（visibility range 切换）。
## lod_dist <= 0 时只挂 LOD0（界面预览）。返回 LOD0 实例。
static var lod_distance: float = 22.0


static func attach(bone: Node3D, pair: Array, mesh_name: String = "Mesh", mirror: bool = false, lod: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = pair[0]
	if mirror:
		mi.scale = Vector3(-1, 1, 1)
	bone.add_child(mi)
	if lod and pair.size() > 1 and pair[1] != null:
		var d := lod_distance
		mi.visibility_range_end = d
		mi.visibility_range_end_margin = 1.5
		var m1 := MeshInstance3D.new()
		m1.name = mesh_name + "_lod1"
		m1.mesh = pair[1]
		m1.visibility_range_begin = d
		m1.visibility_range_begin_margin = 1.5
		m1.set_meta("lod", 1)
		if mirror:
			m1.scale = Vector3(-1, 1, 1)
		bone.add_child(m1)
	return mi
