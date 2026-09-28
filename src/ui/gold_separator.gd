class_name GoldSeparator
extends Control
## 金色分隔线：两端渐隐，中间可带菱形饰点。

@export var ornament: bool = true
@export var fade_left: bool = true
@export var fade_right: bool = true
@export var color: Color = UITheme.GOLD
@export var thickness: float = 1.0


func _init() -> void:
	custom_minimum_size = Vector2(24, 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _draw() -> void:
	var y := roundf(size.y * 0.5)
	var w := size.x
	var c0 := Color(color.r, color.g, color.b, 0.0)
	var c1 := Color(color.r, color.g, color.b, 0.75)
	var mid := w * 0.5
	var l_col := c0 if fade_left else c1
	var r_col := c0 if fade_right else c1
	var pts := PackedVector2Array([Vector2(0, y - thickness * 0.5), Vector2(mid, y - thickness * 0.5), Vector2(mid, y + thickness * 0.5), Vector2(0, y + thickness * 0.5)])
	draw_polygon(pts, PackedColorArray([l_col, c1, c1, l_col]))
	pts = PackedVector2Array([Vector2(mid, y - thickness * 0.5), Vector2(w, y - thickness * 0.5), Vector2(w, y + thickness * 0.5), Vector2(mid, y + thickness * 0.5)])
	draw_polygon(pts, PackedColorArray([c1, r_col, r_col, c1]))
	if ornament:
		var r := 4.0
		var dc := Color(color.r, color.g, color.b, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(mid, y - r), Vector2(mid + r, y), Vector2(mid, y + r), Vector2(mid - r, y)]), dc)
		draw_colored_polygon(PackedVector2Array([Vector2(mid - 12, y - 2), Vector2(mid - 10, y), Vector2(mid - 12, y + 2), Vector2(mid - 14, y)]), dc)
		draw_colored_polygon(PackedVector2Array([Vector2(mid + 12, y - 2), Vector2(mid + 14, y), Vector2(mid + 12, y + 2), Vector2(mid + 10, y)]), dc)
