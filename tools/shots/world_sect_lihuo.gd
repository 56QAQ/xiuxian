extends RefCounted
## lihuo 宗门全景


func frames() -> int:
	return 12


func build(root: Node) -> void:
	WorldShotSect.shoot(root, "lihuo", 10.5)
