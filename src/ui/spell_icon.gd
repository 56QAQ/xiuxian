class_name SpellIcon
extends Control
## 法诀图标：元素色宝珠 + 按法诀类型绘制的符形（飞弹/爆发/天降/突进/护体/增益/回春/领域/召唤/光束）。

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


func _draw() -> void:
	draw_spell(self, Rect2(Vector2.ZERO, size), spell_id, 0.4 if dimmed else 1.0)


static func draw_spell(ci: CanvasItem, rect: Rect2, sid: String, alpha: float = 1.0) -> void:
	var sp := DB.spell(sid)
	if sp.is_empty():
		return
	var e := str(sp.get("element", "none"))
	var c := Elem.color_of(e)
	var ctr := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.5 - 1.0
	# 底：暗色圆 + 元素光晕
	ci.draw_circle(ctr, r, Color(c.r * 0.16, c.g * 0.16, c.b * 0.16, 0.95 * alpha))
	var glow := UITheme.icon("dot")
	ci.draw_texture_rect(glow, Rect2(ctr - Vector2(r, r) * 0.95, Vector2(r, r) * 1.9), false, Color(c.r, c.g, c.b, 0.55 * alpha))
	ci.draw_arc(ctr, r, 0, TAU, 32, Color(c.r, c.g, c.b, 0.9 * alpha), 2.0, true)
	ci.draw_arc(ctr, r - 4.0, 0, TAU, 32, Color(c.r, c.g, c.b, 0.25 * alpha), 1.0, true)
	var fg := c.lightened(0.55)
	fg.a = alpha
	var k := r / 20.0
	var w := maxf(2.0 * k, 1.5)
	match str(sp.get("kind", "")):
		"projectile":
			var n := int(sp.get("params", {}).get("count", 1))
			for i in mini(n, 3):
				var oy := (i - (mini(n, 3) - 1) * 0.5) * 7.0 * k
				ci.draw_line(ctr + Vector2(-10 * k, oy + 4 * k), ctr + Vector2(8 * k, oy - 4 * k), fg, w, true)
				ci.draw_colored_polygon(PackedVector2Array([ctr + Vector2(11 * k, oy - 5.5 * k), ctr + Vector2(4 * k, oy - 6 * k), ctr + Vector2(8 * k, oy)]), fg)
		"nova":
			for i in 8:
				var a := TAU * i / 8.0
				ci.draw_line(ctr + Vector2(cos(a), sin(a)) * 5 * k, ctr + Vector2(cos(a), sin(a)) * 13 * k, fg, w, true)
			ci.draw_circle(ctr, 3.5 * k, fg)
		"strike":
			ci.draw_polyline(PackedVector2Array([ctr + Vector2(2 * k, -13 * k), ctr + Vector2(-4 * k, -1 * k), ctr + Vector2(3 * k, 0), ctr + Vector2(-2 * k, 12 * k)]), fg, w, true)
			ci.draw_line(ctr + Vector2(-9 * k, 13 * k), ctr + Vector2(9 * k, 13 * k), fg, w, true)
		"dash":
			for i in 3:
				var y := (i - 1) * 6.0 * k
				ci.draw_line(ctr + Vector2(-12 * k + i * 2 * k, y), ctr + Vector2(4 * k, y), Color(fg.r, fg.g, fg.b, fg.a * (0.5 + i * 0.25)), w, true)
			ci.draw_colored_polygon(PackedVector2Array([ctr + Vector2(12 * k, 0), ctr + Vector2(4 * k, -8 * k), ctr + Vector2(4 * k, 8 * k)]), fg)
		"shield":
			var pts := PackedVector2Array([ctr + Vector2(0, -12 * k), ctr + Vector2(10 * k, -7 * k), ctr + Vector2(8 * k, 5 * k), ctr + Vector2(0, 12 * k), ctr + Vector2(-8 * k, 5 * k), ctr + Vector2(-10 * k, -7 * k), ctr + Vector2(0, -12 * k)])
			ci.draw_polyline(pts, fg, w, true)
			ci.draw_line(ctr + Vector2(0, -8 * k), ctr + Vector2(0, 8 * k), fg, w * 0.7, true)
		"buff":
			for i in 2:
				var y2 := (i * 8.0 - 2.0) * k
				ci.draw_polyline(PackedVector2Array([ctr + Vector2(-8 * k, y2 + 5 * k), ctr + Vector2(0, y2 - 3 * k), ctr + Vector2(8 * k, y2 + 5 * k)]), fg, w, true)
		"heal":
			ci.draw_line(ctr + Vector2(0, -10 * k), ctr + Vector2(0, 10 * k), fg, w * 1.6, true)
			ci.draw_line(ctr + Vector2(-10 * k, 0), ctr + Vector2(10 * k, 0), fg, w * 1.6, true)
		"field":
			ci.draw_arc(ctr + Vector2(0, 4 * k), 11 * k, PI, TAU, 16, fg, w, true)
			ci.draw_arc(ctr + Vector2(0, 4 * k), 6 * k, PI, TAU, 12, fg, w, true)
			ci.draw_line(ctr + Vector2(-13 * k, 4 * k), ctr + Vector2(13 * k, 4 * k), fg, w, true)
		"summon":
			for i in 3:
				var a2 := -PI * 0.5 + TAU * i / 3.0
				var p := ctr + Vector2(cos(a2), sin(a2)) * 8 * k
				ci.draw_line(p - Vector2(cos(a2), sin(a2)) * 5 * k, p + Vector2(cos(a2), sin(a2)) * 5 * k, fg, w, true)
			ci.draw_arc(ctr, 12 * k, 0, TAU, 24, Color(fg.r, fg.g, fg.b, fg.a * 0.5), 1.0, true)
		"beam":
			ci.draw_line(ctr + Vector2(-12 * k, 6 * k), ctr + Vector2(12 * k, -6 * k), fg, w * 2.2, true)
			ci.draw_circle(ctr + Vector2(-12 * k, 6 * k), 3.5 * k, fg)
		_:
			ci.draw_circle(ctr, 5 * k, fg)
