extends RefCounted
## 通用大地图取景：相对某 POI 的局部坐标放置相机（便于近景/人眼高度检查材质与氛围）。
## 参数：--poi=<id>（默认 town）--cam=x,dy,z（局部坐标，dy 为离平台高度）--at=x,dy,z --hour=时 --fov=度 --radius=区块半径
##       --world=1 时 cam/at 为世界坐标（y 为离地高度）

var cam_l := Vector3(-20, 2.0, -30)
var at_l := Vector3(0, 2.0, 0)
var poi := "town"
var hour := 10.0
var fov := 62.0
var radius := 6
var world := false
var vol := true


func frames() -> int:
	return 14


func _v3(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func build(root: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--poi="):
			poi = a.substr(6)
		elif a.begins_with("--cam="):
			cam_l = _v3(a.substr(6))
		elif a.begins_with("--at="):
			at_l = _v3(a.substr(5))
		elif a.begins_with("--hour="):
			hour = float(a.substr(7))
		elif a.begins_with("--fov="):
			fov = float(a.substr(6))
		elif a.begins_with("--radius="):
			radius = int(a.substr(9))
		elif a.begins_with("--world="):
			world = a.substr(8) == "1"
		elif a.begins_with("--vol="):
			vol = a.substr(6) == "1"
	var ow := WorldShot.make_overworld(root, hour)
	var cam: Vector3
	var at: Vector3
	if world:
		var t: TerrainGen = ow.get("terrain")
		cam = Vector3(cam_l.x, t.get_height(cam_l.x, cam_l.z) + cam_l.y, cam_l.z)
		at = Vector3(at_l.x, t.get_height(at_l.x, at_l.z) + at_l.y, at_l.z)
	else:
		cam = WorldShot.poi_point(ow, poi, Vector2(cam_l.x, cam_l.z), cam_l.y)
		at = WorldShot.poi_point(ow, poi, Vector2(at_l.x, at_l.z), at_l.y)
	WorldShot.place_camera(ow, cam, at, fov)
	if not vol:
		(ow.get("day_night") as DayNight).env.volumetric_fog_enabled = false
	for a in OS.get_cmdline_user_args():
		if a == "--debug_ssr":
			(ow.get("water") as WaterPlane).material.set_shader_parameter("debug_ssr", true)
	WorldShot.prime(ow, radius)
