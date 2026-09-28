extends RefCounted
## 洞府石室内部：蒲团玉台、丹炉、储物箱、书架、灵晶


func frames() -> int:
	return 10


func build(root: Node) -> void:
	var ow := WorldShot.make_overworld(root, 11.0)
	var cam_pos := WorldShot.poi_point(ow, "home", Vector2(1.5, 4.0), 2.6)
	var target := WorldShot.poi_point(ow, "home", Vector2(-0.5, 12.5), 0.8)
	WorldShot.place_camera(ow, cam_pos, target, 70.0)
	WorldShot.prime(ow, 3)
