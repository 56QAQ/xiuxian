extends RefCounted
## qingmu 宗门全景


func frames() -> int:
	return 12


func build(root: Node) -> void:
	WorldShotSect.shoot(root, "qingmu", 10.5)
