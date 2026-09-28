class_name BrushLine
extends Control
## 横向笔触线：起笔饱满、收笔飞白，用于小节标题后的延伸线与分隔。可水平翻转（自右向左收笔）。

@export var color: Color = Color(0.84, 0.68, 0.4, 0.55)
@export var thickness: float = 7.0
@export var flip: bool = false
@export var tex_name: String = "brush_thin"


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(24, 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _draw() -> void:
	var y := size.y * 0.5
	var a := Vector2(0, y)
	var b := Vector2(size.x, y)
	if flip:
		var t := a
		a = b
		b = t
	InkArt.brush(get_canvas_item(), a, b, thickness, color, tex_name)
