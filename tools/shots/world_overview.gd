extends RefCounted
## 大地图高空鸟瞰：从坊市南侧高空俯瞰全图（雪峰、古林、湖泽、赤岩、台地）


func frames() -> int:
	return 12


func build(root: Node) -> void:
	var ow := WorldShot.make_overworld(root, 10.0)
	WorldShot.place_camera(ow, Vector3(512, 190, 1060), Vector3(512, 30, 520), 62.0)
	WorldShot.prime(ow, 7)
