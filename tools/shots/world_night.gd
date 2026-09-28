extends RefCounted
## 夜晚的青云坊市：灯笼与月光（戌时）


func frames() -> int:
	return 12


func build(root: Node) -> void:
	var ow := WorldShot.make_overworld(root, 21.0)
	var cam_pos := WorldShot.poi_point(ow, "town", Vector2(-40, 22), 16.0)
	var target := WorldShot.poi_point(ow, "town", Vector2(8, -4), 1.0)
	WorldShot.place_camera(ow, cam_pos, target, 62.0)
	WorldShot.prime(ow, 6)
