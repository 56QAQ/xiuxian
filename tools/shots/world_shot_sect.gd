class_name WorldShotSect
## 宗门镜头公用：从山门前方斜上方俯瞰宗门


static func shoot(root: Node, sid: String, hour: float, dist: float = 88.0, height: float = 48.0, side: float = 34.0) -> void:
	var ow := WorldShot.make_overworld(root, hour)
	var poi_id := "sect_" + sid
	var cam_pos := WorldShot.poi_point(ow, poi_id, Vector2(side, -dist), height)
	var target := WorldShot.poi_point(ow, poi_id, Vector2(0, 6), 4.0)
	WorldShot.place_camera(ow, cam_pos, target, 58.0)
	WorldShot.prime(ow, 7)
