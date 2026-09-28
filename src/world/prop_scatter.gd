class_name PropScatter
extends Node3D
## 植被与道具流式散布：以 64 米地块为单位，围绕焦点加载。
## 工作线程按生物群系确定性地计算实例变换（树、灌木、芦苇、岩石、草、花）与可交互点（灵草、矿脉、可破坏岩石），
## 主线程按预算创建 MultiMeshInstance3D（树木近景/远景两级 LOD，靠 visibility_range 切换）、树干碰撞与节点。

const TILE := 64
const TILES := TerrainGen.SIZE / TILE
const CELL := 6.0

## 可见距离分类 [begin, end]
const VIS := {
	"tree0": [0.0, 120.0], "tree1": [120.0, 460.0], "grass": [0.0, 62.0], "flower": [0.0, 72.0],
	"rock": [0.0, 240.0], "shrub": [0.0, 150.0], "reed": [0.0, 120.0],
}
const TREE_KINDS := ["pine_snow", "pine", "ancient", "broadleaf", "blossom", "bamboo", "willow", "maple", "dead", "crystal"]
## 工作线程读取，使用非只读的 static var（见 TerrainGen 中的说明）
static var ROCK_BY_REGION := PackedStringArray(["rock_gray", "rock_snow", "rock_moss", "rock_gray", "rock_red", "rock_yellow", "rock_gray"])
static var DROCK_BY_REGION := PackedStringArray(["gray", "snow", "moss", "gray", "red", "yellow", "sand"])

var terrain: TerrainGen
var focus: Node3D
var focus_pos := Vector3(512, 30, 512)
## 加载半径（地块）
var view_tiles := 3.7
var max_tasks := 1
var frame_budget_usec := 4000
var destructibles_enabled := true

var _tiles: Dictionary = {}
var _tasks: Dictionary = {}
var _results: Dictionary = {}
var _ready_list: Array[Vector2i] = []
var _wanted: Array[Vector2i] = []
var _mutex := Mutex.new()
var _last_center := Vector2i(-999, -999)
var stats := {"tiles": 0, "gen_ms_total": 0.0, "instances": 0}


func _init(t: TerrainGen = null) -> void:
	terrain = t


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	PropBuilder.warm_up(TREE_KINDS + ["shrub", "shrub_yellow", "reed", "rock_gray", "rock_moss", "rock_snow", "rock_red", "rock_yellow", "pebble", "grass", "grass_dry", "grass_snow", "flower"])
	stats["warm_ms"] = Time.get_ticks_msec() - t0


func _exit_tree() -> void:
	for k in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
	_tasks.clear()


func set_focus(node: Node3D) -> void:
	focus = node


func tile_count() -> int:
	return _tiles.size()


func _process(_delta: float) -> void:
	if terrain == null:
		return
	var tf := Time.get_ticks_usec()
	_step()
	stats["frame_ms_max"] = maxf(float(stats.get("frame_ms_max", 0.0)), (Time.get_ticks_usec() - tf) / 1000.0)


func _step() -> void:
	if focus != null and is_instance_valid(focus) and focus.is_inside_tree():
		focus_pos = focus.global_position
	var center := Vector2i(floori(focus_pos.x / TILE), floori(focus_pos.z / TILE))
	if center != _last_center:
		_last_center = center
		_update_wanted(center)
		_unload_far()
	# 轮询
	var done: Array[Vector2i] = []
	for k: Vector2i in _tasks:
		if WorkerThreadPool.is_task_completed(_tasks[k]):
			done.append(k)
	for k in done:
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
		_tasks.erase(k)
		_ready_list.append(k)
	for k in _wanted:
		if _tasks.size() >= max_tasks:
			break
		if _tiles.has(k) or _tasks.has(k) or _ready_list.has(k):
			continue
		_tasks[k] = WorkerThreadPool.add_task(_task.bind(k), true, "props")
	var t0 := Time.get_ticks_usec()
	while not _ready_list.is_empty():
		var k: Vector2i = _ready_list.pop_front()
		_mutex.lock()
		var data: Dictionary = _results.get(k, {})
		_results.erase(k)
		_mutex.unlock()
		if data.is_empty() or _tile_dist(k) > view_tiles + 1.0:
			continue
		var ta := Time.get_ticks_usec()
		_apply(k, data)
		stats["apply_ms_max"] = maxf(float(stats.get("apply_ms_max", 0.0)), (Time.get_ticks_usec() - ta) / 1000.0)
		if Time.get_ticks_usec() - t0 > frame_budget_usec:
			break


func _tile_dist(k: Vector2i) -> float:
	var c := Vector2(k.x * TILE + TILE * 0.5, k.y * TILE + TILE * 0.5)
	return c.distance_to(Vector2(focus_pos.x, focus_pos.z)) / TILE


func _update_wanted(center: Vector2i) -> void:
	_wanted.clear()
	var r := int(ceil(view_tiles)) + 1
	var list: Array = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := Vector2i(center.x + dx, center.y + dz)
			if k.x < 0 or k.y < 0 or k.x >= TILES or k.y >= TILES:
				continue
			var d := _tile_dist(k)
			if d <= view_tiles:
				list.append([d, k])
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for e in list:
		_wanted.append(e[1])


func _unload_far() -> void:
	var drop: Array[Vector2i] = []
	for k: Vector2i in _tiles:
		if _tile_dist(k) > view_tiles + 1.2:
			drop.append(k)
	for k in drop:
		(_tiles[k] as Node).queue_free()
		_tiles.erase(k)


func _task(k: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	var data := generate_tile(terrain, k.x, k.y)
	data["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	_mutex.lock()
	_results[k] = data
	_mutex.unlock()


## 同步加载焦点周围的全部地块（开局/截图）
func prime() -> void:
	if focus != null and is_instance_valid(focus) and focus.is_inside_tree():
		focus_pos = focus.global_position
	_last_center = Vector2i(floori(focus_pos.x / TILE), floori(focus_pos.z / TILE))
	_update_wanted(_last_center)
	var keys: Array[Vector2i] = []
	for k in _wanted:
		if not _tiles.has(k) and not _tasks.has(k):
			keys.append(k)
	var results: Array = []
	results.resize(keys.size())
	if not keys.is_empty():
		var gid := WorkerThreadPool.add_group_task(func(i: int) -> void:
			results[i] = generate_tile(terrain, keys[i].x, keys[i].y), keys.size(), -1, true, "props_prime")
		WorkerThreadPool.wait_for_group_task_completion(gid)
	for i in keys.size():
		_apply(keys[i], results[i])


# ================================================================ 生成（工作线程，只读地形）

static func _add_inst(mm: Dictionary, key: String, pos: Vector3, yaw: float, s: float) -> void:
	var buf: PackedFloat32Array = mm.get(key, PackedFloat32Array())
	mm[key] = PackedFloat32Array()  # 释放字典中的引用，避免写时复制
	var c := cos(yaw) * s
	var sn := sin(yaw) * s
	buf.append_array([c, 0.0, sn, pos.x, 0.0, s, 0.0, pos.y, -sn, 0.0, c, pos.z])
	mm[key] = buf


static func generate_tile(t: TerrainGen, tx: int, tz: int) -> Dictionary:
	var x0 := tx * TILE
	var z0 := tz * TILE
	var cx := x0 + TILE * 0.5
	var cz := z0 + TILE * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(t.seed_value & 0xffffff, tx, tz))
	var mm := {}
	var trees: Array = []
	var herbs: Array = []
	var ores: Array = []
	var drocks: Array = []
	var hm := t.hmap
	var fl := t.flags
	var S := TerrainGen.SIZE
	var sea := TerrainGen.SEA_LEVEL
	var blocked := TerrainGen.F_NOPROP | TerrainGen.F_LAVA | TerrainGen.F_ROAD | TerrainGen.F_PAVED | TerrainGen.F_FIELD
	var tv := [rng.randi() % 3, rng.randi() % 3]  # 本地块使用的两个变体
	# ---------------- 树（6 米抖动网格）
	var n := int(TILE / CELL)
	for j in n:
		for i in n:
			var wx := x0 + (i + rng.randf_range(0.15, 0.85)) * CELL
			var wz := z0 + (j + rng.randf_range(0.15, 0.85)) * CELL
			var ix := int(wx)
			var iz := int(wz)
			var idx := iz * S + ix
			if fl[idx] & blocked:
				rng.randf()
				continue
			var h := int(hm[idx])
			if h < sea or t.slope_at(ix, iz) >= 3:
				rng.randf()
				continue
			var r := t._region_at(ix, iz)
			var patch := t.n_patch.get_noise_2d(ix, iz)
			var grove := t.n_patch.get_noise_2d(ix * 0.5 + 900.0, iz * 0.5)
			var dens := 0.0
			match r:
				TerrainGen.R_FOREST:
					dens = 0.8
				TerrainGen.R_SNOW:
					dens = 0.38 if h < 58 else 0.05
				TerrainGen.R_PLAINS:
					dens = 0.05 + (0.5 if grove > 0.3 else 0.0)
				TerrainGen.R_LAKE:
					dens = 0.22
				TerrainGen.R_VOLCANIC:
					dens = 0.14
				TerrainGen.R_PLATEAU:
					dens = 0.12
			if rng.randf() > dens:
				continue
			var roll := rng.randf()
			var kind := "broadleaf"
			var near_water := h <= sea + 2
			match r:
				TerrainGen.R_FOREST:
					if grove > 0.38:
						kind = "bamboo"
					elif roll < 0.1 and (i + j) % 3 == 0:
						kind = "ancient"
					elif roll < 0.72:
						kind = "broadleaf"
					elif roll < 0.86:
						kind = "pine"
					elif roll < 0.94:
						kind = "maple"
					else:
						kind = "blossom"
				TerrainGen.R_SNOW:
					kind = "pine_snow" if h >= 27 or roll < 0.3 else "pine"
				TerrainGen.R_PLAINS:
					if near_water:
						kind = "willow"
					elif roll < 0.5:
						kind = "broadleaf"
					elif roll < 0.72:
						kind = "blossom"
					else:
						kind = "pine"
				TerrainGen.R_LAKE:
					if near_water or roll < 0.5:
						kind = "willow"
					elif roll < 0.72:
						kind = "broadleaf"
					elif roll < 0.88:
						kind = "blossom"
					else:
						kind = "bamboo"
				TerrainGen.R_VOLCANIC:
					kind = "dead" if roll < 0.55 else ("crystal" if roll < 0.85 else "maple")
				TerrainGen.R_PLATEAU:
					if roll < 0.4:
						kind = "shrub_yellow"
					elif roll < 0.65:
						kind = "maple"
					elif roll < 0.85:
						kind = "pine"
					else:
						kind = "dead"
				_:
					continue
			var pos := Vector3(wx - cx, float(h), wz - cz)
			var yaw := float(rng.randi() % 4) * PI * 0.5
			var s := rng.randf_range(0.85, 1.15)
			var v: int = tv[rng.randi() % 2] % PropBuilder.variants(kind)
			if kind == "shrub_yellow":
				_add_inst(mm, "%s|%d|0|shrub" % [kind, v], pos, yaw, s)
				continue
			_add_inst(mm, "%s|%d|0|tree0" % [kind, v], pos, yaw, s)
			_add_inst(mm, "%s|%d|1|tree1" % [kind, v], pos, yaw, s)
			var inf := PropBuilder.info(kind)
			trees.append([pos, float(inf["trunk"]) * s, float(inf["height"]) * s])
			# 树下灵草 / 灵芝
			if r == TerrainGen.R_FOREST and rng.randf() < 0.06:
				herbs.append([pos + Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5)), "herb_lingcao" if rng.randf() < 0.8 else "herb_fire_ganoderma"])
			if kind == "crystal" and rng.randf() < 0.25:
				herbs.append([pos + Vector3(2.0, 0, 0.5), "herb_fire_ganoderma"])
	# ---------------- 草、花、灌木、芦苇、碎石
	var samples := 420
	for q in samples:
		var ix := x0 + rng.randi_range(0, TILE - 1)
		var iz := z0 + rng.randi_range(0, TILE - 1)
		var idx := iz * S + ix
		var fx := ix + rng.randf()
		var fz := iz + rng.randf()
		var yaw := rng.randf() * TAU
		var s := rng.randf_range(0.8, 1.3)
		var roll := rng.randf()
		if fl[idx] & (TerrainGen.F_PAVED | TerrainGen.F_ROAD | TerrainGen.F_LAVA | TerrainGen.F_FIELD | TerrainGen.F_NOGRASS):
			continue
		var h := int(hm[idx])
		var r := t._region_at(ix, iz)
		var pos := Vector3(fx - cx, float(h), fz - cz)
		if h < sea:
			if r == TerrainGen.R_LAKE and h == sea - 1 and roll < 0.25:
				_add_inst(mm, "reed|%d|0|reed" % (q % 2), pos, yaw, s)
			continue
		if t.slope_at(ix, iz) >= 2:
			continue
		var patch := t.n_patch.get_noise_2d(ix, iz)
		match r:
			TerrainGen.R_PLAINS, TerrainGen.R_FOREST, TerrainGen.R_LAKE:
				if r == TerrainGen.R_LAKE and h <= sea + 1 and roll < 0.3:
					_add_inst(mm, "reed|%d|0|reed" % (q % 2), pos, yaw, s)
				elif roll < (0.14 if r == TerrainGen.R_PLAINS else 0.07):
					var fv := posmod(int((patch + 1.0) * 3.0) + tv[0], 5)
					_add_inst(mm, "flower|%d|0|flower" % fv, pos, yaw, s)
				elif roll < 0.18 and q % 9 == 0:
					_add_inst(mm, "shrub|%d|0|shrub" % tv[1], pos, float(rng.randi() % 4) * PI * 0.5, s)
				elif roll < 0.9:
					_add_inst(mm, "grass|%d|0|grass" % (q % 3), pos, yaw, s)
			TerrainGen.R_SNOW:
				if h < 30 and roll < 0.5:
					_add_inst(mm, "grass_snow|%d|0|grass" % (q % 2), pos, yaw, s)
				elif roll > 0.97:
					_add_inst(mm, "pebble|%d|0|rock" % (q % 3), pos, yaw, s)
			TerrainGen.R_PLATEAU:
				if roll < 0.35:
					_add_inst(mm, "grass_dry|%d|0|grass" % (q % 2), pos, yaw, s)
				elif roll > 0.97:
					_add_inst(mm, "pebble|%d|0|rock" % (q % 3), pos, yaw, s)
			TerrainGen.R_VOLCANIC:
				if roll > 0.93:
					_add_inst(mm, "pebble|%d|0|rock" % (q % 3), pos, yaw, s * 1.4)
	# ---------------- 岩石
	for q in 10:
		var ix := x0 + rng.randi_range(2, TILE - 3)
		var iz := z0 + rng.randi_range(2, TILE - 3)
		var idx := iz * S + ix
		var roll := rng.randf()
		if fl[idx] & blocked or hm[idx] < sea:
			continue
		var r := t._region_at(ix, iz)
		var pos := Vector3(ix + 0.5 - cx, float(hm[idx]) - 0.5, iz + 0.5 - cz)
		var kind: String = ROCK_BY_REGION[r]
		if r == TerrainGen.R_FOREST and roll < 0.7:
			kind = "rock_moss"
		_add_inst(mm, "%s|%d|0|rock" % [kind, q % 3], pos, float(rng.randi() % 4) * PI * 0.5, rng.randf_range(0.7, 1.4))
	# 可破坏岩石
	for q in 3:
		var ix := x0 + rng.randi_range(4, TILE - 5)
		var iz := z0 + rng.randi_range(4, TILE - 5)
		var idx := iz * S + ix
		if fl[idx] & blocked or hm[idx] < sea or t.slope_at(ix, iz) >= 2 or rng.randf() < 0.35:
			continue
		var r := t._region_at(ix, iz)
		drocks.append([Vector3(ix + 0.5 - cx, float(hm[idx]), iz + 0.5 - cz), rng.randi(), 3 + rng.randi() % 2, DROCK_BY_REGION[r]])
	# 灵草
	for q in 4:
		var ix := x0 + rng.randi_range(2, TILE - 3)
		var iz := z0 + rng.randi_range(2, TILE - 3)
		var idx := iz * S + ix
		if fl[idx] & blocked or hm[idx] < sea or rng.randf() < 0.5:
			continue
		var r := t._region_at(ix, iz)
		var item := "herb_lingcao"
		if r == TerrainGen.R_VOLCANIC:
			item = "herb_fire_ganoderma"
		elif r == TerrainGen.R_SNOW and hm[idx] > 32:
			continue
		herbs.append([Vector3(ix + 0.5 - cx, float(hm[idx]), iz + 0.5 - cz), item])
	# 矿脉
	var ore_r := t._region_at(int(cx), int(cz))
	if ore_r == TerrainGen.R_SNOW or ore_r == TerrainGen.R_PLATEAU or ore_r == TerrainGen.R_VOLCANIC:
		for q in 2:
			var ix := x0 + rng.randi_range(4, TILE - 5)
			var iz := z0 + rng.randi_range(4, TILE - 5)
			var idx := iz * S + ix
			if fl[idx] & blocked or hm[idx] < sea or rng.randf() < 0.4:
				continue
			var gold := rng.randf() < (0.4 if ore_r == TerrainGen.R_SNOW else 0.12)
			ores.append([Vector3(ix + 0.5 - cx, float(hm[idx]), iz + 0.5 - cz), "ore_gengjin" if gold else "ore_iron", q])
	return {"mm": mm, "trees": trees, "herbs": herbs, "ores": ores, "rocks": drocks}


# ================================================================ 主线程：创建节点

func _apply(k: Vector2i, data: Dictionary) -> void:
	var tile := Node3D.new()
	tile.name = "Props_%d_%d" % [k.x, k.y]
	add_child(tile)
	tile.position = Vector3(k.x * TILE + TILE * 0.5, 0.0, k.y * TILE + TILE * 0.5)
	var mm: Dictionary = data["mm"]
	var inst := 0
	for key: String in mm:
		var parts := key.split("|")
		var kind := parts[0]
		var v := int(parts[1])
		var lod := int(parts[2])
		var cat := parts[3]
		var buf: PackedFloat32Array = mm[key]
		var count := buf.size() / 12
		if count == 0:
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = PropBuilder.mesh(kind, v, lod)
		multi.instance_count = count
		multi.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = multi
		var vis: Array = VIS[cat]
		mmi.visibility_range_begin = float(vis[0])
		mmi.visibility_range_end = float(vis[1])
		if float(vis[0]) > 0.0:
			mmi.visibility_range_begin_margin = 8.0
		mmi.visibility_range_end_margin = 8.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if cat == "grass" or cat == "flower" or cat == "reed" or cat == "tree1":
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tile.add_child(mmi)
		inst += count
	var trees: Array = data["trees"]
	if not trees.is_empty():
		var body := StaticBody3D.new()
		body.name = "Trunks"
		body.collision_layer = 1
		body.collision_mask = 0
		for tr in trees:
			var r: float = tr[1]
			var h: float = tr[2]
			if r <= 0.0 or h <= 0.0:
				continue
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = r
			cyl.height = h
			cs.shape = cyl
			cs.position = (tr[0] as Vector3) + Vector3(0, h * 0.5, 0)
			body.add_child(cs)
		tile.add_child(body)
	for hb in data["herbs"]:
		var herb := PropBuilder.make_herb(hb[1])
		tile.add_child(herb)
		herb.position = hb[0]
	for o in data["ores"]:
		var ore := PropBuilder.make_ore(o[1], o[2])
		tile.add_child(ore)
		ore.position = o[0]
		ore.rotation.y = float(o[2]) * PI * 0.5
	if destructibles_enabled:
		for rk in data["rocks"]:
			var d := DestructibleFactory.rock(rk[1], float(rk[2]), rk[3])
			tile.add_child(d)
			d.position = rk[0]
			d.rotation.y = float(int(rk[1]) % 4) * PI * 0.5
	_tiles[k] = tile
	stats["tiles"] = int(stats["tiles"]) + 1
	stats["instances"] = int(stats["instances"]) + inst
	stats["gen_ms_total"] = float(stats["gen_ms_total"]) + float(data.get("ms", 0.0))
