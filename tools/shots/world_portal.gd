extends RefCounted
## 秘境入口：发光石门与旋涡传送面（黄昏）


func frames() -> int:
	return 12


func build(root: Node) -> void:
	var ow := WorldShot.make_overworld(root, 17.7)
	var cam_pos := WorldShot.poi_point(ow, "portal_0", Vector2(-6, -16), 3.5)
	var target := WorldShot.poi_point(ow, "portal_0", Vector2(0, 0), 4.0)
	WorldShot.place_camera(ow, cam_pos, target, 60.0)
	WorldShot.prime(ow, 6)
