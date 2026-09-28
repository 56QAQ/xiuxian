extends RefCounted
## 天剑宗（北方雪峰）：山门外高处俯瞰宗门全景


func frames() -> int:
	return 12


func build(root: Node) -> void:
	WorldShotSect.shoot(root, "tianjian", 10.5)
