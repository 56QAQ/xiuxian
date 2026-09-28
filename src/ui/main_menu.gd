extends Control
## 主菜单（占位，UI 模块将替换）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	add_child(box)
	var title := Label.new()
	title.text = "问道长生"
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)
	var b := Button.new()
	b.text = "新的仙途"
	b.pressed.connect(Scenes.goto_creator)
	box.add_child(b)
