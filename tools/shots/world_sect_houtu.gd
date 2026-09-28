extends RefCounted
## houtu 宗门全景


func frames() -> int:
	return 12


func build(root: Node) -> void:
	WorldShotSect.shoot(root, "houtu", 10.5)
