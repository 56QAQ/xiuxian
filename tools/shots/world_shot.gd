class_name WorldShot
## 大地图镜头脚本公用：创建 Overworld、摆放相机、同步加载区块与道具。


static func make_overworld(root: Node, hour: float) -> Node3D:
	GS.world["hours"] = hour
	var ow: Node3D = load("res://src/world/overworld.gd").new()
	ow.name = "Overworld"
	root.add_child(ow)
	return ow


static func place_camera(ow: Node3D, pos: Vector3, target: Vector3, fov: float = 60.0) -> Camera3D:
	var cam: Camera3D = ow.get("player")
	cam.global_position = pos
	cam.look_at(target)
	cam.fov = fov
	if cam.has_method("sync_angles"):
		cam.call("sync_angles")
	return cam


## 同步加载相机周围的区块（与道具）
static func prime(ow: Node3D, radius: int = 7) -> void:
	var st: TerrainStreamer = ow.get("streamer")
	st.prime(radius)
	if ow.has_method("prime_props"):
		ow.call("prime_props")


## 某 POI 的局部坐标 → 世界坐标（y 为平台高度 + dy）
static func poi_point(ow: Node3D, poi_id: String, local: Vector2, dy: float = 0.0) -> Vector3:
	var t: TerrainGen = ow.get("terrain")
	var p := t.find_poi(poi_id)
	var w := TerrainGen.local_to_world2(p, local)
	return Vector3(w.x, float(p.get("height", t.get_ground_y(w.x, w.y))) + dy, w.y)
