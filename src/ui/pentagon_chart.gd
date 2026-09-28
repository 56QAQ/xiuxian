class_name PentagonChart
extends Control
## 五行灵根五边形图：火居上，顺时针 火 → 土 → 金 → 水 → 木（相生环），内有相克五芒星。
## values: {elem: 百分比(0~100)}。

## 顶点顺序（顺时针，从正上方开始）
const ORDER: Array[String] = ["fire", "earth", "metal", "water", "wood"]

var values: Dictionary = {}:
	set(v):
		values = v
		_target = v.duplicate()
		queue_redraw()
## 显示百分比文字
var show_labels: bool = true
## 显示相生箭头与相克星
var show_cycles: bool = true

var _anim: Dictionary = {}
var _target: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(220, 220)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _process(delta: float) -> void:
	var moving := false
	var k := 1.0 - exp(-10.0 * delta)
	for e in ORDER:
		var cur := float(_anim.get(e, 0.0))
		var tgt := float(_target.get(e, 0.0))
		if absf(cur - tgt) > 0.05:
			_anim[e] = lerpf(cur, tgt, k)
			moving = true
		else:
			_anim[e] = tgt
	if moving:
		queue_redraw()


func _vertex(i: int, r: float) -> Vector2:
	var a := -PI * 0.5 + TAU * i / 5.0
	return size * 0.5 + Vector2(cos(a), sin(a)) * r


func _draw() -> void:
	var R := minf(size.x, size.y) * 0.5 - (40.0 if show_labels else 8.0)
	var gold := UITheme.GOLD
	# 网格
	for ring in [1.0, 0.75, 0.5, 0.25]:
		var pts := PackedVector2Array()
		for i in 5:
			pts.append(_vertex(i, R * ring))
		pts.append(pts[0])
		if ring == 1.0:
			draw_colored_polygon(pts, Color(0, 0, 0, 0.35))
		draw_polyline(pts, Color(gold.r, gold.g, gold.b, 0.4 if ring == 1.0 else 0.13), 1.5 if ring == 1.0 else 1.0, true)
	for i in 5:
		draw_line(size * 0.5, _vertex(i, R), Color(gold.r, gold.g, gold.b, 0.12), 1.0, true)
	if show_cycles:
		# 相克五芒星（淡）
		var star := PackedVector2Array()
		for i in 6:
			star.append(_vertex((i * 2) % 5, R * 0.98))
		draw_polyline(star, Color(0.8, 0.3, 0.25, 0.1), 1.0, true)
	# 数值多边形（顶点色渐变）
	var vpts := PackedVector2Array()
	var vcols := PackedColorArray()
	for i in 5:
		var e := ORDER[i]
		var v := clampf(float(_anim.get(e, 0.0)) / 100.0, 0.0, 1.0)
		vpts.append(_vertex(i, R * maxf(v, 0.04)))
		var c := Elem.color_of(e)
		vcols.append(Color(c.r, c.g, c.b, 0.5 if v > 0.0 else 0.08))
	var total := 0.0
	for e in ORDER:
		total += float(_anim.get(e, 0.0))
	if total > 0.5:
		draw_polygon(vpts, vcols)
		var outline := vpts.duplicate()
		outline.append(vpts[0])
		draw_polyline(outline, Color(1.0, 0.92, 0.7, 0.85), 2.0, true)
	for i in 5:
		var e2 := ORDER[i]
		var v2 := float(_anim.get(e2, 0.0))
		if v2 > 0.5:
			draw_circle(vpts[i], 4.5, Elem.color_of(e2))
			draw_arc(vpts[i], 4.5, 0, TAU, 16, Color(0, 0, 0, 0.6), 1.0, true)
	if not show_labels:
		return
	# 顶点标签：元素字 + 百分比
	var f := UITheme.font_title()
	for i in 5:
		var e3 := ORDER[i]
		var c3 := Elem.color_of(e3)
		var p := _vertex(i, R + 17.0)
		var has := float(_target.get(e3, 0.0)) > 0.0
		draw_circle(p, 14.0, Color(c3.r * 0.25, c3.g * 0.25, c3.b * 0.25, 0.95) if has else Color(0.08, 0.08, 0.09, 0.9))
		draw_arc(p, 14.0, 0, TAU, 24, c3 if has else Color(c3.r, c3.g, c3.b, 0.35), 1.5, true)
		var t := Elem.name_of(e3)
		var fs := 18
		var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, p + Vector2(-ts.x * 0.5, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c3.lightened(0.2) if has else Color(0.5, 0.5, 0.5))
		if has:
			var pt := "%d%%" % int(round(float(_target.get(e3, 0.0))))
			var fs2 := 14
			var ts2 := UITheme.font_regular().get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2)
			var off := Vector2(0, 26) if i != 0 else Vector2(26 + ts2.x * 0.5, 4)
			var tp := p + off - Vector2(ts2.x * 0.5, 0)
			draw_string_outline(UITheme.font_regular(), tp, pt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 3, Color(0, 0, 0, 0.8))
			draw_string(UITheme.font_regular(), tp, pt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, UITheme.TEXT)
