class_name OrnateBox
extends StyleBox
## 水墨金边样式框：纵向渐变底色 + 细金边 + 内衬线 + 回纹角饰 + 柔和阴影。
## 通过 UITheme 创建并放入全局主题；也可单独 new() 后设置属性使用。

## 底色（上 → 下渐变）
var bg_top: Color = Color(0.1, 0.092, 0.085, 0.95)
var bg_bottom: Color = Color(0.045, 0.05, 0.066, 0.95)
## 外边框
var border_color: Color = Color(0.78, 0.62, 0.36, 0.85)
var border_width: float = 1.0
## 内衬线（距边框 inner_inset 像素的细线）
var inner_line_color: Color = Color(0.78, 0.62, 0.36, 0.0)
var inner_inset: float = 5.0
## 角饰：0 无 · 1 回纹角（窗口） · 2 小角钩（按钮、卡片） · 3 菱形角点
var ornament: int = 0
var ornament_color: Color = Color(0.93, 0.78, 0.47)
var corner_len: float = 14.0
## 顶部高光条（模拟宣纸反光），0 表示不画
var top_glow: float = 0.0
## 左侧强调条（如选中卡片），宽度 0 表示不画
var accent_width: float = 0.0
var accent_color: Color = Color(0.38, 0.8, 0.64)
## 水墨晕染（窗口底纹）与右下角远山水印的强度，0 表示不画
var wash: float = 0.0
var watermark: float = 0.0
## 阴影
var shadow_size: float = 0.0
var shadow_color: Color = Color(0, 0, 0, 0.5)
var shadow_offset: Vector2 = Vector2(0, 4)

var _shadow_box: StyleBoxFlat


func _init() -> void:
	content_margin_left = 10.0
	content_margin_right = 10.0
	content_margin_top = 8.0
	content_margin_bottom = 8.0


func set_margins(l: float, t: float, r: float, b: float) -> OrnateBox:
	content_margin_left = l
	content_margin_top = t
	content_margin_right = r
	content_margin_bottom = b
	return self


func set_all_margins(m: float) -> OrnateBox:
	return set_margins(m, m, m, m)


func _draw(ci: RID, rect: Rect2) -> void:
	if shadow_size > 0.0:
		if _shadow_box == null:
			_shadow_box = StyleBoxFlat.new()
			_shadow_box.bg_color = Color(0, 0, 0, 0)
			_shadow_box.draw_center = false
		_shadow_box.shadow_color = shadow_color
		_shadow_box.shadow_size = int(shadow_size)
		_shadow_box.shadow_offset = shadow_offset
		_shadow_box.draw(ci, rect)
	# 渐变底
	var pts := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var cols := PackedColorArray([bg_top, bg_top, bg_bottom, bg_bottom])
	if bg_top.a > 0.0 or bg_bottom.a > 0.0:
		RenderingServer.canvas_item_add_polygon(ci, pts, cols)
	if wash > 0.0:
		_draw_wash(ci, rect)
	if watermark > 0.0 and rect.size.x > 200.0 and rect.size.y > 160.0:
		_draw_watermark(ci, rect)
	if top_glow > 0.0:
		var gh := minf(rect.size.y * 0.45, 40.0)
		var g_top := Color(1.0, 0.92, 0.75, 0.06 * top_glow)
		var g_bot := Color(1.0, 0.92, 0.75, 0.0)
		var gp := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.position.y + gh), Vector2(rect.position.x, rect.position.y + gh)])
		RenderingServer.canvas_item_add_polygon(ci, gp, PackedColorArray([g_top, g_top, g_bot, g_bot]))
	if accent_width > 0.0:
		RenderingServer.canvas_item_add_rect(ci, Rect2(rect.position, Vector2(accent_width, rect.size.y)), accent_color)
	# 外边框
	if border_width > 0.0 and border_color.a > 0.0:
		_frame(ci, rect, border_width, border_color)
	# 内衬线
	if inner_line_color.a > 0.0 and rect.size.x > inner_inset * 4.0 and rect.size.y > inner_inset * 4.0:
		_frame(ci, rect.grow(-inner_inset), 1.0, inner_line_color)
	match ornament:
		1:
			_corners_lattice(ci, rect)
		2:
			_corners_hook(ci, rect)
		3:
			_corners_diamond(ci, rect)


## 几团柔和的墨晕（位置随尺寸确定，保持稳定）
func _draw_wash(ci: RID, rect: Rect2) -> void:
	var tex := UITheme.icon("dot")
	if tex == null:
		return
	var rid := tex.get_rid()
	var spots := [
		[Vector2(0.18, 0.2), Vector2(0.7, 0.55), Color(0.55, 0.4, 0.25, 0.07)],
		[Vector2(0.85, 0.35), Vector2(0.6, 0.7), Color(0.3, 0.38, 0.6, 0.06)],
		[Vector2(0.3, 0.9), Vector2(0.9, 0.5), Color(0.0, 0.0, 0.0, 0.18)],
	]
	for sp in spots:
		var c: Vector2 = rect.position + rect.size * (sp[0] as Vector2)
		var sz: Vector2 = rect.size * (sp[1] as Vector2)
		var col: Color = sp[2]
		col.a *= wash
		RenderingServer.canvas_item_add_texture_rect(ci, Rect2(c - sz * 0.5, sz), rid, false, col)


## 右下角淡淡的远山剪影
func _draw_watermark(ci: RID, rect: Rect2) -> void:
	var w := minf(rect.size.x * 0.5, 520.0)
	var h := minf(rect.size.y * 0.3, 190.0)
	var base := Vector2(rect.end.x - w - 6.0, rect.end.y - 6.0)
	var profiles := [
		[[0.0, 0.62], [0.12, 0.45], [0.22, 0.58], [0.36, 0.2], [0.46, 0.42], [0.55, 0.3], [0.68, 0.05], [0.8, 0.4], [0.9, 0.3], [1.0, 0.5]],
		[[0.0, 0.85], [0.15, 0.62], [0.3, 0.78], [0.45, 0.5], [0.6, 0.7], [0.75, 0.55], [0.88, 0.72], [1.0, 0.6]],
	]
	var alphas := [0.045, 0.07]
	for i in profiles.size():
		var pts := PackedVector2Array()
		pts.append(base + Vector2(0, 0))
		for pp in profiles[i]:
			pts.append(base + Vector2(float(pp[0]) * w, -h + float(pp[1]) * h))
		pts.append(base + Vector2(w, 0))
		var c := Color(0.75, 0.78, 0.9, alphas[i] * watermark)
		var cols := PackedColorArray()
		for _p in pts:
			cols.append(c)
		RenderingServer.canvas_item_add_polygon(ci, pts, cols)


static func _frame(ci: RID, r: Rect2, w: float, c: Color) -> void:
	RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(r.size.x, w)), c)
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.position.x, r.end.y - w), Vector2(r.size.x, w)), c)
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.position.x, r.position.y + w), Vector2(w, r.size.y - w * 2.0)), c)
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.end.x - w, r.position.y + w), Vector2(w, r.size.y - w * 2.0)), c)


## 在角 corner 处按方向 (sx, sy) 画一个轴对齐矩形（局部坐标 x,y,w,h 均为正向）
static func _crect(ci: RID, corner: Vector2, s: Vector2, x: float, y: float, w: float, h: float, c: Color) -> void:
	var p := corner + Vector2(x * s.x, y * s.y)
	var q := corner + Vector2((x + w) * s.x, (y + h) * s.y)
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(minf(p.x, q.x), minf(p.y, q.y)), (q - p).abs()), c)


static func _diamond(ci: RID, center: Vector2, r: float, c: Color) -> void:
	var pts := PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0), center + Vector2(0, r), center + Vector2(-r, 0)])
	RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([c, c, c, c]))


func _each_corner(rect: Rect2) -> Array:
	return [
		[rect.position, Vector2(1, 1)],
		[Vector2(rect.end.x, rect.position.y), Vector2(-1, 1)],
		[Vector2(rect.position.x, rect.end.y), Vector2(1, -1)],
		[rect.end, Vector2(-1, -1)],
	]


## 回纹角：粗角钩 + 内折线 + 角点菱形
func _corners_lattice(ci: RID, rect: Rect2) -> void:
	var c := corner_len
	var oc := ornament_color
	var dim := Color(oc.r, oc.g, oc.b, oc.a * 0.55)
	for e in _each_corner(rect):
		var p: Vector2 = e[0]
		var s: Vector2 = e[1]
		_crect(ci, p, s, 0, 0, c, 2.0, oc)
		_crect(ci, p, s, 0, 0, 2.0, c, oc)
		_crect(ci, p, s, 5, 5, c * 0.62, 1.0, dim)
		_crect(ci, p, s, 5, 5, 1.0, c * 0.62, dim)
		_crect(ci, p, s, 8, 8, 2.0, 2.0, oc)
		_diamond(ci, p + s * 1.0, 3.2, oc)


## 小角钩：四角各一个短 L
func _corners_hook(ci: RID, rect: Rect2) -> void:
	var c := corner_len
	for e in _each_corner(rect):
		var p: Vector2 = e[0]
		var s: Vector2 = e[1]
		_crect(ci, p, s, 0, 0, c, 1.5, ornament_color)
		_crect(ci, p, s, 0, 0, 1.5, c, ornament_color)


func _corners_diamond(ci: RID, rect: Rect2) -> void:
	for e in _each_corner(rect):
		_diamond(ci, (e[0] as Vector2) + (e[1] as Vector2) * 3.0, 2.5, ornament_color)
