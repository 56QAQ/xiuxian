class_name InkSeal
extends Control
## 印章控件：残边印泥 + 白文书法（1 字居中、2 字竖排、4 字右起 2×2）。用于窗口标题、提示流、卡片角标等。

@export var glyph: String = "":
	set(v):
		glyph = v
		queue_redraw()
@export var body: Color = Color(0.76, 0.14, 0.09):
	set(v):
		body = v
		queue_redraw()
@export var ink: Color = Color(0.98, 0.95, 0.88)
@export var round_seal: bool = false
@export var angle: float = -0.06


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(28, 28)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


static func make(g: String, px: float = 28.0, col: Color = Color(0.76, 0.14, 0.09), rnd: bool = false) -> InkSeal:
	var s := InkSeal.new()
	s.glyph = g
	s.body = col
	s.round_seal = rnd
	s.custom_minimum_size = Vector2(px, px)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return s


func _draw() -> void:
	var sz := minf(size.x, size.y)
	InkArt.seal(get_canvas_item(), size * 0.5, sz, glyph, body, ink, round_seal, angle)
