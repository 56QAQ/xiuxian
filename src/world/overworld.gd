extends Node3D
## 大地图场景（scenes/overworld.tscn 的根节点脚本）。
## 构建：昼夜环境 + 水面 + 地形流式加载 + POI（宗门/坊市/洞府/秘境入口/地标）+ 植被道具 + 可破坏物。
## 时间：1 现实分钟 = 1 时辰（GS.advance_time(delta * 2 / 60)，每约 0.3 秒批量推进一次）。
## 对外：terrain（TerrainGen）、get_spawn_position()、set_focus(node)、_spawn_player()（调试自由相机，
## 将由玩家模块替换）。GS 未开局时使用默认种子，可单独运行。

const HOURS_PER_SECOND := 2.0 / 60.0
const TIME_FLUSH_HOURS := 0.01

var terrain: TerrainGen
var streamer: TerrainStreamer
var props: PropScatter
var pois_root: Node3D
var day_night: DayNight
var water: WaterPlane
var player: Node3D
## 加载耗时（毫秒）
var load_ms := 0.0
var _pending_hours := 0.0
var _focus: Node3D


func _ready() -> void:
	var t0 := Time.get_ticks_usec()
	if not GS.active and not GS.world.has("hours"):
		GS.world["hours"] = 8.0
	terrain = TerrainGen.shared()
	water = WaterPlane.new()
	water.name = "Water"
	add_child(water)
	day_night = DayNight.new()
	day_night.name = "DayNight"
	day_night.water = water
	day_night.hour = GS.hour_of_day()
	add_child(day_night)
	streamer = TerrainStreamer.new(terrain)
	streamer.name = "Terrain"
	add_child(streamer)
	var t1 := Time.get_ticks_usec()
	_build_pois()
	var poi_ms := (Time.get_ticks_usec() - t1) / 1000.0
	props = PropScatter.new(terrain)
	props.name = "Props"
	add_child(props)
	var tw := Time.get_ticks_usec()
	DestructibleFactory.warm_up()
	var warm_d := (Time.get_ticks_usec() - tw) / 1000.0
	_spawn_player()
	t1 = Time.get_ticks_usec()
	streamer.prime(3)
	var prime_ms := (Time.get_ticks_usec() - t1) / 1000.0
	load_ms = (Time.get_ticks_usec() - t0) / 1000.0
	print("[大地图] 加载 %.0f ms（地形生成 %.0f，建筑 %.0f，道具预热 %d，可破坏物预热 %.0f，首批区块 %.0f）" % [load_ms, terrain.gen_ms, poi_ms, int(props.stats.get("warm_ms", 0)), warm_d, prime_ms])


func _process(delta: float) -> void:
	_pending_hours += delta * HOURS_PER_SECOND
	if _pending_hours >= TIME_FLUSH_HOURS:
		GS.advance_time(_pending_hours)
		_pending_hours = 0.0
	day_night.set_hour(GS.hour_of_day() + _pending_hours)


func _exit_tree() -> void:
	if _focus != null and is_instance_valid(_focus) and _focus.is_inside_tree():
		GS.overworld_position = _focus.global_position


## 出生点：GS.overworld_position（有效时）否则洞府门前
func get_spawn_position() -> Vector3:
	var p := GS.overworld_position
	if p != Vector3.INF and p.x >= 0.0 and p.z >= 0.0 and p.x < TerrainGen.SIZE and p.z < TerrainGen.SIZE:
		return Vector3(p.x, maxf(p.y, terrain.get_height(p.x, p.z) + 0.1), p.z)
	var home := terrain.find_poi("home")
	var sp := TerrainGen.local_to_world2(home, Vector2(0, -4))
	return Vector3(sp.x, float(home["height"]) + 0.05, sp.y)


## 设置流式加载焦点（玩家或相机）
func set_focus(node: Node3D) -> void:
	_focus = node
	if streamer:
		streamer.set_focus(node)
	if props:
		props.set_focus(node)


## 同步加载焦点周围的道具地块（截图/测试用）
func prime_props() -> void:
	if props:
		props.prime()


## 建造全部 POI（宗门、坊市、洞府、秘境入口、地标）
func _build_pois() -> void:
	pois_root = Node3D.new()
	pois_root.name = "POIs"
	add_child(pois_root)
	for p in terrain.pois:
		var n := BuildingLayouts.build_poi(p, terrain)
		if n != null:
			pois_root.add_child(n)


## 某 POI 的标记点节点（建筑已生成时）
func get_marker(poi_id: String, marker_name: String) -> Marker3D:
	for c in pois_root.get_children():
		if c.get_meta("poi_id", "") == poi_id:
			return c.get_node_or_null(marker_name) as Marker3D
	return null


## 生成玩家。当前为调试自由飞行相机（玩家模块会替换此方法）。
func _spawn_player() -> void:
	var cam := FreeCam.new()
	cam.name = "FreeCam"
	add_child(cam)
	var sp := get_spawn_position()
	var home := terrain.find_poi("home")
	var f: Vector3 = home["facing"]
	cam.global_position = sp + Vector3(0, 2.5, 0) + f * 6.0
	cam.look_at(sp + f * 40.0 + Vector3(0, 1.0, 0))
	cam.sync_angles()
	player = cam
	set_focus(cam)
