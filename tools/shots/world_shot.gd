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


## 自动选取观察点：在目标周围环上搜索视线无地形遮挡、位于陆地且尽量顺光的位置。
## 返回相机位置（离地 cam_h 米）。
static func find_viewpoint(t: TerrainGen, target: Vector3, dists: Array = [70.0, 95.0, 120.0], cam_h: float = 8.0, hour: float = 10.5) -> Vector3:
	var sun := DayNight.sun_direction(hour)
	var sun2 := Vector2(sun.x, sun.z).normalized()
	var best := target + Vector3(0, 40, 80)
	var best_score := -INF
	for d in dists:
		for a in 24:
			var ang := a * TAU / 24.0
			var dir := Vector2(cos(ang), sin(ang))
			var p := Vector2(target.x, target.z) + dir * float(d)
			if p.x < 20 or p.y < 20 or p.x > TerrainGen.SIZE - 20 or p.y > TerrainGen.SIZE - 20:
				continue
			if t.is_water(p.x, p.y):
				continue
			var cam := Vector3(p.x, t.get_height(p.x, p.y) + cam_h, p.y)
			var clear := true
			for k in range(1, 40):
				var q := cam.lerp(target, k / 40.0)
				if t.get_height(q.x, q.z) > q.y - 1.5:
					clear = false
					break
			if not clear:
				continue
			var score := dir.dot(sun2) * 30.0 - absf(cam.y - target.y) * 0.3 - float(d) * 0.05
			if score > best_score:
				best_score = score
				best = cam
	return best
