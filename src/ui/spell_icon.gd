class_name SpellIcon
extends Control
## 法诀图标（国风）：五行色水墨晕染的圆形法盘 + 金色双环 + 以毛笔笔触绘成的符形
## （飞弹/爆发/天降/突进/护体/增益/回春/领域/召唤/光束）+ 右下角五行小印。

const KIND_NAMES := {
	"projectile": "飞弹", "nova": "爆发", "strike": "天降", "dash": "突进", "shield": "护体",
	"buff": "增益", "heal": "回春", "field": "领域", "summon": "召唤", "beam": "光束",
}

var spell_id: String = "":
	set(v):
		spell_id = v
		queue_redraw()
var dimmed: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(44, 44)
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _draw() -> void:
	draw_spell(self, Rect2(Vector2.ZERO, size), spell_id, 0.4 if dimmed else 1.0)


static func draw_spell(ci: CanvasItem, rect: Rect2, sid: String, alpha: float = 1.0) -> void:
	var sp := DB.spell(sid)
	if sp.is_empty():
		return
	var rid := ci.get_canvas_item()
	var e := str(sp.get("element", "none"))
	var c := Elem.color_of(e) if Elem.is_valid(e) else Color(0.72, 0.66, 0.9)
	var ctr := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.5 - 1.0
	# 法盘：深色底 + 五行色水墨晕 + 中心柔光
	ci.draw_circle(ctr, r, Color(0.04, 0.035, 0.03, 0.96 * alpha))
	var wash := InkArt.tex("ink_wash")
	InkArt.rect_tex(rid, wash, Rect2(ctr - Vector2(r, r) * 1.02, Vector2(r, r) * 2.04), Color(c.r * 0.7, c.g * 0.7, c.b * 0.7, 0.7 * alpha))
	var glow := UITheme.icon("dot")
	ci.draw_texture_rect(glow, Rect2(ctr - Vector2(r, r) * 0.8, Vector2(r, r) * 1.6), false, Color(c.r, c.g, c.b, 0.4 * alpha))
	# 金色双环
	ci.draw_arc(ctr, r - 0.8, 0, TAU, 40, Color(0.92, 0.76, 0.44, 0.95 * alpha), 1.6, true)
	ci.draw_arc(ctr, r - 3.6, 0, TAU, 40, Color(c.r, c.g, c.b, 0.45 * alpha), 1.0, true)
	var fg := Color(1.0, 0.97, 0.9, alpha)
	var k := r / 20.0
	var w := maxf(4.2 * k, 2.4)
	var P := func(x: float, y: float) -> Vector2: return ctr + Vector2(x, y) * k
	match str(sp.get("kind", "")):
		"projectile":
			var n := mini(int(sp.get("params", {}).get("count", 1)), 3)
			for i in n:
				var oy := (i - (n - 1) * 0.5) * 7.0
				InkArt.brush(rid, P.call(-11, oy + 5), P.call(7, oy - 3), w, fg, "brush_thin")
				ci.draw_colored_polygon(PackedVector2Array([P.call(12, oy - 5.5), P.call(4, oy - 6.5), P.call(7.5, oy + 0.5)]), fg)
		"nova":
			for i in 8:
				var a := TAU * i / 8.0 + 0.2
				var d := Vector2(cos(a), sin(a))
				InkArt.brush(rid, ctr + d * 5.0 * k, ctr + d * 14.0 * k, w * 0.8, fg, "brush_thin")
			ci.draw_circle(ctr, 3.8 * k, fg)
		"strike":
			InkArt.brush(rid, P.call(3, -14), P.call(-4, -1), w, fg, "brush_thin")
			InkArt.brush(rid, P.call(-4, -1), P.call(4, 0), w * 0.9, fg, "brush_thin")
			InkArt.brush(rid, P.call(4, 0), P.call(-3, 13), w, fg, "brush_thin")
			InkArt.brush(rid, P.call(-11, 14), P.call(11, 14), w * 0.8, Color(fg.r, fg.g, fg.b, fg.a * 0.8), "brush_thin")
		"dash":
			for i in 3:
				var y := (i - 1) * 6.5
				InkArt.brush(rid, P.call(-13 + i * 2, y), P.call(5, y), w * (0.7 + 0.15 * i), Color(fg.r, fg.g, fg.b, fg.a * (0.55 + i * 0.22)), "brush_thin")
			ci.draw_colored_polygon(PackedVector2Array([P.call(13, 0), P.call(4, -8), P.call(4, 8)]), fg)
		"shield":
			var pts := [P.call(0, -13), P.call(10, -8), P.call(8, 5), P.call(0, 13), P.call(-8, 5), P.call(-10, -8), P.call(0, -13)]
			for i in pts.size() - 1:
				InkArt.brush(rid, pts[i], pts[i + 1], w * 0.8, fg, "brush_thin")
			InkArt.brush(rid, P.call(0, -8), P.call(0, 8), w * 0.7, fg, "brush_thin")
		"buff":
			for i in 2:
				var y2 := i * 8.0 - 2.0
				InkArt.brush(rid, P.call(-9, y2 + 5), P.call(0, y2 - 4), w * 0.85, fg, "brush_thin")
				InkArt.brush(rid, P.call(0, y2 - 4), P.call(9, y2 + 5), w * 0.85, fg, "brush_thin")
		"heal":
			InkArt.brush(rid, P.call(0, -12), P.call(0, 12), w * 1.3, fg, "brush_thin")
			InkArt.brush(rid, P.call(-12, 0), P.call(12, 0), w * 1.3, fg, "brush_thin")
		"field":
			InkArt.brush_arc(rid, P.call(0, 5), 11.0 * k, PI, TAU, w * 0.8, fg, "brush_thin", 0.0, 1.0, 16)
			InkArt.brush_arc(rid, P.call(0, 5), 6.0 * k, PI, TAU, w * 0.7, fg, "brush_thin", 0.0, 1.0, 12)
			InkArt.brush(rid, P.call(-14, 5), P.call(14, 5), w * 0.8, fg, "brush_thin")
		"summon":
			for i in 3:
				var a2 := -PI * 0.5 + TAU * i / 3.0
				var d2 := Vector2(cos(a2), sin(a2))
				var p := ctr + d2 * 8.0 * k
				InkArt.brush(rid, p - d2 * 5.5 * k, p + d2 * 6.0 * k, w * 0.85, fg, "brush_thin")
			ci.draw_arc(ctr, 12.5 * k, 0, TAU, 24, Color(fg.r, fg.g, fg.b, fg.a * 0.5), 1.0, true)
		"beam":
			InkArt.brush(rid, P.call(-12, 7), P.call(13, -6), w * 1.8, fg, "brush_stroke")
			ci.draw_circle(P.call(-12, 7), 3.8 * k, fg)
		_:
			ci.draw_circle(ctr, 5.0 * k, fg)
	# 五行小印
	if r >= 14.0 and Elem.is_valid(e):
		var ss := r * 0.62
		InkArt.seal(rid, ctr + Vector2(r * 0.7, r * 0.7), ss, InkArt.elem_glyph(e), Color(c.darkened(0.35).r, c.darkened(0.35).g, c.darkened(0.35).b, alpha), Color(1, 0.96, 0.88, alpha), false, -0.08)
