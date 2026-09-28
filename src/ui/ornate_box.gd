class_name OrnateBox
extends StyleBox
## 国风样式框：漆色渐变底（可委角）+ 宣纸纤维/斑驳 + 玉纹 + 水墨晕染与远山水印 + 金边与内衬线 +
## 回纹带 + 角饰（回纹角 / 小角钩 / 菱形角点 / 祥云）+ 柔和阴影；也可整块画成一笔墨痕（brush）。
## 通过 UITheme 创建并放入全局主题；也可单独 new() 后设置属性使用。属性均导出，duplicate() 可完整复制。

## 底色（上 → 下渐变）
@export var bg_top: Color = Color(0.1, 0.092, 0.085, 0.95)
@export var bg_bottom: Color = Color(0.045, 0.05, 0.066, 0.95)
## 外边框
@export var border_color: Color = Color(0.78, 0.62, 0.36, 0.85)
@export var border_width: float = 1.0
## 内衬线（距边框 inner_inset 像素的细线）
@export var inner_line_color: Color = Color(0.78, 0.62, 0.36, 0.0)
@export var inner_inset: float = 5.0
## 角饰：0 无 · 1 回纹角 · 2 小角钩 · 3 菱形角点 · 4 祥云角
@export var ornament: int = 0
@export var ornament_color: Color = Color(0.93, 0.78, 0.47)
@export var corner_len: float = 14.0
## 委角（切角）尺寸，0 为直角
@export var chamfer: float = 0.0
## 顶部高光条（模拟漆面反光），0 表示不画
@export var top_glow: float = 0.0
## 左侧强调条（如选中卡片），宽度 0 表示不画
@export var accent_width: float = 0.0
@export var accent_color: Color = Color(0.38, 0.8, 0.64)
## 水墨晕染（窗口底纹）与右下角远山水印的强度，0 表示不画
@export var wash: float = 0.0
@export var watermark: float = 0.0
## 宣纸纤维与斑驳（叠加色的 alpha 即强度）
@export var paper_color: Color = Color(1.0, 0.92, 0.78, 0.0)
@export var mottle_color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var paper_scale: float = 0.5
## 玉纹叠加强度（玉牌按钮）
@export var jade: float = 0.0
## 回纹带（上下边内侧）颜色，alpha 0 不画
@export var hui_color: Color = Color(0.9, 0.74, 0.45, 0.0)
## 整块画成一笔墨痕：>0 时以 brush_color 绘制笔触纹理代替矩形底
@export var brush: float = 0.0
@export var brush_color: Color = Color(0.02, 0.02, 0.03, 0.8)
@export var brush_flip: bool = false
## 笔触截取到 u（0..1）：<1 时收笔的飞白更少，适合承载文字
@export var brush_u1: float = 1.0
## 阴影
@export var shadow_size: float = 0.0
@export var shadow_color: Color = Color(0, 0, 0, 0.5)
@export var shadow_offset: Vector2 = Vector2(0, 4)

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
		_shadow_box.set_corner_radius_all(int(chamfer * 0.6))
		_shadow_box.draw(ci, rect)
	if brush > 0.0:
		_draw_brush_bg(ci, rect)
	elif bg_top.a > 0.0 or bg_bottom.a > 0.0:
		if chamfer > 0.0:
			InkArt.plaque(ci, rect, chamfer, bg_top, bg_bottom)
		else:
			var pts := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
			RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([bg_top, bg_top, bg_bottom, bg_bottom]))
	var inner := rect.grow(-chamfer * 0.3) if chamfer > 0.0 else rect
	if jade > 0.0:
		InkArt.tile(ci, inner, InkArt.tex("jade"), Color(1, 1, 1, jade), 0.6, rect.position * 0.37)
	if paper_color.a > 0.0:
		InkArt.tile(ci, inner, InkArt.tex("paper_fiber"), paper_color, paper_scale, rect.position * 0.61)
	if mottle_color.a > 0.0:
		InkArt.tile(ci, inner, InkArt.tex("paper_mottle"), mottle_color, paper_scale * 1.2, rect.position * 0.29 + Vector2(137, 59))
	if wash > 0.0:
		_draw_wash(ci, rect)
	if watermark > 0.0 and rect.size.x > 200.0 and rect.size.y > 160.0:
		_draw_watermark(ci, rect)
	if top_glow > 0.0:
		var gh := minf(rect.size.y * 0.45, 40.0)
		var g_top := Color(1.0, 0.92, 0.75, 0.06 * top_glow)
		var g_bot := Color(1.0, 0.92, 0.75, 0.0)
		var gr := rect.grow(-chamfer * 0.5) if chamfer > 0.0 else rect
		var gp := PackedVector2Array([gr.position, Vector2(gr.end.x, gr.position.y), Vector2(gr.end.x, gr.position.y + gh), Vector2(gr.position.x, gr.position.y + gh)])
		RenderingServer.canvas_item_add_polygon(ci, gp, PackedColorArray([g_top, g_top, g_bot, g_bot]))
	if accent_width > 0.0:
		RenderingServer.canvas_item_add_rect(ci, Rect2(rect.position + Vector2(0, chamfer), Vector2(accent_width, rect.size.y - chamfer * 2.0)), accent_color)
	# 外边框
	if border_width > 0.0 and border_color.a > 0.0:
		if chamfer > 0.0:
			InkArt.outline(ci, InkArt.chamfer_points(rect.grow(-border_width * 0.5), chamfer), border_color, border_width)
		else:
			_frame(ci, rect, border_width, border_color)
	# 内衬线
	if inner_line_color.a > 0.0 and rect.size.x > inner_inset * 4.0 and rect.size.y > inner_inset * 4.0:
		if chamfer > 0.0:
			InkArt.outline(ci, InkArt.chamfer_points(rect.grow(-inner_inset), maxf(chamfer - inner_inset * 0.4, 2.0)), inner_line_color, 1.0)
		else:
			_frame(ci, rect.grow(-inner_inset), 1.0, inner_line_color)
	if hui_color.a > 0.0 and rect.size.x > 160.0:
		var unit := 14.0
		var inset := inner_inset + 4.0
		InkArt.hui_band_h(ci, rect.position.x + corner_len * 3.0, rect.end.x - corner_len * 3.0, rect.position.y + inset, unit, hui_color, 1.0)
		InkArt.hui_band_h(ci, rect.position.x + corner_len * 3.0, rect.end.x - corner_len * 3.0, rect.end.y - inset - unit * 0.62, unit, hui_color, 1.0)
	match ornament:
		1:
			_corners_lattice(ci, rect)
		2:
			_corners_hook(ci, rect)
		3:
			_corners_diamond(ci, rect)
		4:
			InkArt.cloud_corners(ci, rect, corner_len * 4.0, ornament_color, 2.0)


## 一笔墨痕作底：左右各出界少许，两端自然收笔
func _draw_brush_bg(ci: RID, rect: Rect2) -> void:
	var t := InkArt.tex("brush_stroke")
	if t == null:
		return
	var over := minf(rect.size.y * 0.6, 26.0)
	var r := Rect2(rect.position - Vector2(over * 0.5, rect.size.y * 0.12), rect.size + Vector2(over * 1.3, rect.size.y * 0.24))
	var col := Color(brush_color.r, brush_color.g, brush_color.b, brush_color.a * brush)
	if brush_u1 < 0.999:
		var y := r.get_center().y
		var a := Vector2(r.position.x, y)
		var b := Vector2(r.end.x, y)
		if brush_flip:
			var tmp := a
			a = b
			b = tmp
		InkArt.brush_part(ci, a, b, r.size.y, col, 0.0, brush_u1)
	else:
		InkArt.rect_tex(ci, t, r, col, brush_flip)


## 几团柔和的墨晕（位置随尺寸确定，保持稳定）
func _draw_wash(ci: RID, rect: Rect2) -> void:
	var tex := InkArt.tex("ink_wash")
	if tex == null:
		return
	var spots := [
		[Vector2(0.16, 0.18), Vector2(0.6, 0.5), Color(0.5, 0.36, 0.22, 0.09), false],
		[Vector2(0.86, 0.3), Vector2(0.55, 0.62), Color(0.26, 0.32, 0.5, 0.07), true],
		[Vector2(0.32, 0.92), Vector2(0.9, 0.5), Color(0.0, 0.0, 0.0, 0.2), false],
	]
	for sp in spots:
		var c: Vector2 = rect.position + rect.size * (sp[0] as Vector2)
		var sz: Vector2 = rect.size * (sp[1] as Vector2)
		var col: Color = sp[2]
		col.a *= wash
		InkArt.rect_tex(ci, tex, Rect2(c - sz * 0.5, sz), col, bool(sp[3]))


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


## 回纹角：粗角钩 + 内折回纹 + 角点菱形
func _corners_lattice(ci: RID, rect: Rect2) -> void:
	var c := corner_len
	var oc := ornament_color
	var dim := Color(oc.r, oc.g, oc.b, oc.a * 0.6)
	for e in _each_corner(rect):
		var p: Vector2 = e[0]
		var s: Vector2 = e[1]
		_crect(ci, p, s, 0, 0, c, 2.0, oc)
		_crect(ci, p, s, 0, 0, 2.0, c, oc)
		# 回字内折
		_crect(ci, p, s, 5, 5, c * 0.7, 1.0, dim)
		_crect(ci, p, s, 5, 5, 1.0, c * 0.7, dim)
		_crect(ci, p, s, 5 + c * 0.7 - 1.0, 5, 1.0, c * 0.35, dim)
		_crect(ci, p, s, 5, 5 + c * 0.7 - 1.0, c * 0.35, 1.0, dim)
		_crect(ci, p, s, 9, 9, 3.0, 3.0, oc)
		_diamond(ci, p + s * 1.0, 3.2, oc)


## 小角钩：四角各一个短 L
func _corners_hook(ci: RID, rect: Rect2) -> void:
	var c := corner_len
	var off := chamfer * 0.5
	for e in _each_corner(rect):
		var p: Vector2 = e[0]
		var s: Vector2 = e[1]
		if chamfer > 0.0:
			# 委角处画一道斜线金边 + 两侧短钩
			var a := p + Vector2(s.x * chamfer, 0)
			var b := p + Vector2(0, s.y * chamfer)
			RenderingServer.canvas_item_add_line(ci, a, b, ornament_color, 1.6, true)
			_crect(ci, p, s, chamfer + 1.0, 0, c * 0.6, 1.5, ornament_color)
			_crect(ci, p, s, 0, chamfer + 1.0, 1.5, c * 0.6, ornament_color)
		else:
			_crect(ci, p, s, off, off, c, 1.5, ornament_color)
			_crect(ci, p, s, off, off, 1.5, c, ornament_color)


func _corners_diamond(ci: RID, rect: Rect2) -> void:
	for e in _each_corner(rect):
		_diamond(ci, (e[0] as Vector2) + (e[1] as Vector2) * 3.0, 2.5, ornament_color)
