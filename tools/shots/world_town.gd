extends RefCounted
## 青云坊市：主街、摊位、客栈、告示牌与中心广场（傍晚前的暖光）


func frames() -> int:
	return 12


func build(root: Node) -> void:
	var ow := WorldShot.make_overworld(root, 15.5)
	var cam_pos := WorldShot.poi_point(ow, "town", Vector2(-46, 30), 24.0)
	var target := WorldShot.poi_point(ow, "town", Vector2(6, -4), 2.0)
	WorldShot.place_camera(ow, cam_pos, target, 60.0)
	WorldShot.prime(ow, 7)
