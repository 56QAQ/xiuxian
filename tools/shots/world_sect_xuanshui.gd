extends RefCounted
## xuanshui 宗门全景


func frames() -> int:
	return 12


func build(root: Node) -> void:
	WorldShotSect.shoot(root, "xuanshui", 10.5)
