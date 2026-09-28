extends RefCounted
## 大地图高空鸟瞰：午后从西南高空俯瞰全图（台地、湖泽、坊市、赤岩火山、古林与北方雪峰）


func frames() -> int:
	return 12


func build(root: Node) -> void:
	var ow := WorldShot.make_overworld(root, 15.0)
	WorldShot.place_camera(ow, Vector3(140, 178, 1010), Vector3(560, 18, 430), 62.0)
	WorldShot.prime(ow, 7)
