extends RefCounted
## 洞府：山坡上的石室入口、前院药田（上午）


func frames() -> int:
	return 12


func build(root: Node) -> void:
	var ow := WorldShot.make_overworld(root, 9.0)
	var cam_pos := WorldShot.poi_point(ow, "home", Vector2(-16, -30), 13.0)
	var target := WorldShot.poi_point(ow, "home", Vector2(0, 3), 3.0)
	WorldShot.place_camera(ow, cam_pos, target, 60.0)
	WorldShot.prime(ow, 7)
