extends Control
## 捏人界面（占位，UI 模块将替换）


func _ready() -> void:
	GS.new_game({"name": "无名", "roots": {"fire": 100}})
	Scenes.goto_overworld()
