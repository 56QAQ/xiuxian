extends RefCounted
## 渲染统计：在坊市（地面视角）与宗门俯瞰处打印绘制调用、图元与可见物体数（截图为最后一处）。
## 用法：tools/shot.sh <godot> world_perf out.png

var _ow: Node3D
var _views: Array = []
var _i := 0


func frames() -> int:
	return 40


func build(root: Node) -> void:
	_ow = WorldShot.make_overworld(root, 10.0)
	var t: TerrainGen = _ow.get("terrain")
	_views = [
		["坊市街道（地面）", WorldShot.poi_point(_ow, "town", Vector2(-30, 0), 1.8), WorldShot.poi_point(_ow, "town", Vector2(40, 0), 2.0)],
		["青木谷（俯瞰）", WorldShot.poi_point(_ow, "sect_qingmu", Vector2(30, -90), 45.0), WorldShot.poi_point(_ow, "sect_qingmu", Vector2(0, 0), 0.0)],
	]
	var v: Array = _views[0]
	WorldShot.place_camera(_ow, v[1], v[2], 70.0)
	WorldShot.prime(_ow, 7)


func step(_root: Node, frame: int) -> void:
	if frame == 15 or frame == 38:
		var v: Array = _views[_i]
		var st: TerrainStreamer = _ow.get("streamer")
		var pr: PropScatter = _ow.get("props")
		print("[%s] 绘制调用 %d，图元 %d，可见物体 %d；区块 %d，道具地块 %d，道具实例 %d" % [v[0],
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			st.loaded_count(), pr.tile_count(), int(pr.stats.get("instances", 0))])
		_i += 1
		if _i < _views.size():
			var n: Array = _views[_i]
			WorldShot.place_camera(_ow, n[1], n[2], 60.0)
			WorldShot.prime(_ow, 7)
