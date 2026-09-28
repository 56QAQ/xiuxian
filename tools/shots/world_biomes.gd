extends RefCounted
## 生物群系地面视角（2×2 拼图）：北方雪峰与天剑宗、东方古林灵木、西方赤岩火山、西南黄土台地石林
## 相机位置由 WorldShot.find_viewpoint 自动搜索（视线无遮挡、顺光）。

## [目标 POI, 目标局部坐标, 目标离地高度, 搜索距离, 相机离地高度]
var _views: Array = [
	["sect_tianjian", Vector2(0, 10), 10.0, [105.0, 130.0], 12.0],
	["landmark_ancient_tree", Vector2(0, 0), 14.0, [22.0, 26.0], 2.5],
	["landmark_volcano", Vector2(0, 0), 20.0, [150.0, 190.0], 6.0],
	["landmark_stone_forest", Vector2(0, 0), 8.0, [70.0, 95.0], 5.0],
]
var _hour := 10.5


func frames() -> int:
	return 14


func build(root: Node) -> void:
	var ow := WorldShot.make_overworld(root, _hour)
	var t: TerrainGen = ow.get("terrain")
	var st: TerrainStreamer = ow.get("streamer")
	var props: PropScatter = ow.get("props")
	var main_cam: Camera3D = ow.get("player")
	st.focus = null
	props.focus = null
	var grid := GridContainer.new()
	grid.columns = 2
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(grid)
	var holes: Array[Vector4] = []
	var i := 0
	for v in _views:
		var tp := TerrainGen.local_to_world2(t.find_poi(v[0]), v[1])
		var target := Vector3(tp.x, t.get_ground_y(tp.x, tp.y) + float(v[2]), tp.y)
		var cam_pos := WorldShot.find_viewpoint(t, target, v[3], float(v[4]), _hour)
		# 同步加载该处的区块与道具
		st.focus_pos = cam_pos
		st.prime(6)
		props.focus_pos = cam_pos
		props.prime()
		if i > 0:
			holes.append(Vector4(cam_pos.x, cam_pos.z, 6 * TerrainGen.CHUNK - 8.0, 0.0))
		var svc := SubViewportContainer.new()
		svc.stretch = true
		svc.custom_minimum_size = Vector2(798, 448)
		svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var sv := SubViewport.new()
		sv.msaa_3d = Viewport.MSAA_2X
		svc.add_child(sv)
		grid.add_child(svc)
		var cam := Camera3D.new()
		cam.fov = 62.0
		cam.far = 4000.0
		sv.add_child(cam)
		cam.global_position = cam_pos
		cam.look_at(target)
		if i == 0:
			main_cam.global_position = cam_pos
		i += 1
	# 停止流式加载/卸载，保留全部已加载区域
	st.extra_holes = holes
	st.focus_pos = main_cam.global_position
	props.set_process(false)
	st.set_process(false)
	st.call("_update_hole")
