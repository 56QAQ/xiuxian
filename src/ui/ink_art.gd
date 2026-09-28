class_name InkArt
extends RefCounted
## 国风界面绘制工具（HUD 与面板共用）：宣纸/笔触/祥云/印章纹理、八卦、委角牌匾、回纹、竖排书法。
## 纹理由 tools/gen_ui_textures.py 生成于 assets/textures/ui/。
## 所有函数以 CanvasItem 的 RID 为目标（StyleBox._draw 与 Control._draw 通用：ci = get_canvas_item()）。

const TEX_DIR := "res://assets/textures/ui/"

## 先天八卦：自上（乾）顺时针；每卦三爻自内（初爻）向外，1 = 阳爻（实线），0 = 阴爻（断线）
const TRIGRAMS := [[1, 1, 1], [0, 1, 1], [0, 1, 0], [0, 0, 1], [0, 0, 0], [1, 0, 0], [1, 0, 1], [1, 1, 0]]
const TRIGRAM_NAMES := ["乾", "巽", "坎", "艮", "坤", "震", "离", "兑"]

## 常用墨色
const INK := Color(0.06, 0.05, 0.045)
const CINNABAR := Color(0.78, 0.16, 0.1)
const CINNABAR_DARK := Color(0.45, 0.07, 0.05)
const PAPER := Color(0.95, 0.9, 0.78)
const GOLD := Color(0.9, 0.74, 0.42)
const JADE := Color(0.42, 0.8, 0.64)
const AZURE := Color(0.32, 0.72, 1.0)

static var _tex: Dictionary = {}


static func tex(tex_name: String) -> Texture2D:
	if not _tex.has(tex_name):
		var p := TEX_DIR + tex_name + ".png"
		_tex[tex_name] = load(p) if ResourceLoader.exists(p) else null
	return _tex[tex_name]


# ================================================================ 平铺与笔触

## 手动平铺（不依赖纹理重复模式）：按 scale 缩放的纹理铺满 rect，offset 为纹理空间偏移
static func tile(ci: RID, rect: Rect2, t: Texture2D, color: Color, scale: float = 1.0, offset: Vector2 = Vector2.ZERO) -> void:
	if t == null or rect.size.x <= 0.5 or rect.size.y <= 0.5 or color.a <= 0.0:
		return
	var ts := Vector2(t.get_width(), t.get_height()) * scale
	var rid := t.get_rid()
	var o := Vector2(fposmod(offset.x, ts.x), fposmod(offset.y, ts.y))
	var y := rect.position.y - o.y
	while y < rect.end.y:
		var x := rect.position.x - o.x
		while x < rect.end.x:
			var cell := Rect2(Vector2(x, y), ts)
			var dst := cell.intersection(rect)
			if dst.size.x > 0.0 and dst.size.y > 0.0:
				var src := Rect2((dst.position - cell.position) / scale, dst.size / scale)
				RenderingServer.canvas_item_add_texture_rect_region(ci, dst, rid, src, color, false, true)
			x += ts.x
		y += ts.y


## 纹理贴在任意四边形上（p0 左上 p1 右上 p2 右下 p3 左下），可水平/垂直翻转
static func quad(ci: RID, t: Texture2D, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color: Color, flip_h: bool = false, flip_v: bool = false) -> void:
	if t == null:
		return
	var u0 := 1.0 if flip_h else 0.0
	var u1 := 1.0 - u0
	var v0 := 1.0 if flip_v else 0.0
	var v1 := 1.0 - v0
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([p0, p1, p2, p3]), PackedColorArray([color, color, color, color]),
		PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]), t.get_rid())


## 纹理贴在矩形上（可翻转）
static func rect_tex(ci: RID, t: Texture2D, r: Rect2, color: Color, flip_h: bool = false, flip_v: bool = false) -> void:
	quad(ci, t, r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), color, flip_h, flip_v)


## 一笔横画：从 a 到 b 的毛笔笔触（起笔在 a，收笔飞白在 b）
static func brush(ci: RID, a: Vector2, b: Vector2, width: float, color: Color, tex_name: String = "brush_stroke", flip_v: bool = false) -> void:
	var d := b - a
	if d.length() < 0.5:
		return
	var n := Vector2(-d.y, d.x).normalized() * width * 0.5
	quad(ci, tex(tex_name), a - n, b - n, b + n, a + n, color, false, flip_v)


## 截取笔触的一段（u0..u1，0 = 起笔 1 = 收笔）画在 a→b 上，用于进度条
static func brush_part(ci: RID, a: Vector2, b: Vector2, width: float, color: Color, u0: float, u1: float, tex_name: String = "brush_stroke") -> void:
	var d := b - a
	if d.length() < 0.5:
		return
	var n := Vector2(-d.y, d.x).normalized() * width * 0.5
	var t := tex(tex_name)
	if t == null:
		return
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([a - n, b - n, b + n, a + n]), PackedColorArray([color, color, color, color]),
		PackedVector2Array([Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)]), t.get_rid())


## 沿圆弧的笔触（a0→a1 弧度，屏幕坐标系：0 = 右，PI/2 = 下）。u 沿弧从 u0 到 u1。
static func brush_arc(ci: RID, center: Vector2, radius: float, a0: float, a1: float, width: float, color: Color,
		tex_name: String = "brush_stroke", u0: float = 0.0, u1: float = 1.0, segs: int = 32) -> void:
	var t := tex(tex_name)
	if t == null or absf(a1 - a0) < 0.001:
		return
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var r_in := radius - width * 0.5
	var r_out := radius + width * 0.5
	for i in segs + 1:
		var f := float(i) / segs
		var a := lerpf(a0, a1, f)
		var dir := Vector2(cos(a), sin(a))
		var u := lerpf(u0, u1, f)
		pts.append(center + dir * r_out)
		pts.append(center + dir * r_in)
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
		cols.append(color)
		cols.append(color)
		if i > 0:
			var k := i * 2
			idx.append_array([k - 2, k - 1, k, k - 1, k + 1, k])
	RenderingServer.canvas_item_add_triangle_array(ci, idx, pts, cols, uvs, PackedInt32Array(), PackedFloat32Array(), t.get_rid())


## 纯色圆环扇段（不带纹理），用于细线与发光
static func arc_band(ci: RID, center: Vector2, r_in: float, r_out: float, a0: float, a1: float, color: Color, segs: int = 24) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in segs + 1:
		var a := lerpf(a0, a1, float(i) / segs)
		var dir := Vector2(cos(a), sin(a))
		pts.append(center + dir * r_out)
		pts.append(center + dir * r_in)
		cols.append(color)
		cols.append(color)
		if i > 0:
			var k := i * 2
			idx.append_array([k - 2, k - 1, k, k - 1, k + 1, k])
	RenderingServer.canvas_item_add_triangle_array(ci, idx, pts, cols)


# ================================================================ 印章、八卦、祥云

## 印章：残边印泥 + 白文（glyph 1 字居中；2 字竖排；4 字按右起竖读 2×2）
static func seal(ci: RID, center: Vector2, size: float, glyph: String, body: Color = CINNABAR, ink: Color = PAPER,
		round_seal: bool = false, angle: float = 0.0, font: Font = null) -> void:
	var t := tex("seal_round" if round_seal else "seal_square")
	var h := size * 0.5
	var rot := Transform2D(angle, Vector2.ZERO)
	var p0 := center + rot * Vector2(-h, -h)
	var p1 := center + rot * Vector2(h, -h)
	var p2 := center + rot * Vector2(h, h)
	var p3 := center + rot * Vector2(-h, h)
	quad(ci, t, p0, p1, p2, p3, body)
	if glyph == "":
		return
	var f := font if font != null else UITheme.font_display()
	var chars := glyph.length()
	if absf(angle) > 0.001:
		RenderingServer.canvas_item_add_set_transform(ci, Transform2D(angle, center))
		_seal_glyphs(ci, f, Vector2.ZERO, size, glyph, chars, ink)
		RenderingServer.canvas_item_add_set_transform(ci, Transform2D.IDENTITY)
	else:
		_seal_glyphs(ci, f, center, size, glyph, chars, ink)


static func _seal_glyphs(ci: RID, f: Font, c: Vector2, size: float, glyph: String, chars: int, ink: Color) -> void:
	if chars <= 1:
		glyph_centered(ci, f, c, glyph, int(size * 0.62), ink)
	elif chars == 2:
		var fs := int(size * 0.38)
		glyph_centered(ci, f, c + Vector2(0, -size * 0.19), glyph.substr(0, 1), fs, ink)
		glyph_centered(ci, f, c + Vector2(0, size * 0.19), glyph.substr(1, 1), fs, ink)
	else:
		var fs2 := int(size * 0.36)
		var q := size * 0.19
		# 右列先读：0 右上 1 右下 2 左上 3 左下
		glyph_centered(ci, f, c + Vector2(q, -q), glyph.substr(0, 1), fs2, ink)
		glyph_centered(ci, f, c + Vector2(q, q), glyph.substr(1, 1), fs2, ink)
		glyph_centered(ci, f, c + Vector2(-q, -q), glyph.substr(2, 1), fs2, ink)
		glyph_centered(ci, f, c + Vector2(-q, q), glyph.substr(3, 1), fs2, ink)


## 单字按字形框居中（中文字形的视觉中心约在 ascent 的 0.36 处）
static func glyph_centered(ci: RID, f: Font, c: Vector2, g: String, fs: int, col: Color) -> void:
	var w := f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := f.get_ascent(fs)
	var desc := f.get_descent(fs)
	f.draw_string(ci, Vector2(c.x - w * 0.5, c.y + (asc - desc) * 0.5 - fs * 0.04), g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## 一个卦象：radial 为自中心向外的方向角（弧度），三爻沿切向排布，初爻在内
static func trigram(ci: RID, center: Vector2, radial: float, idx: int, length: float, bar_w: float, gap: float, color: Color) -> void:
	var lines: Array = TRIGRAMS[posmod(idx, 8)]
	var rad := Vector2(cos(radial), sin(radial))
	var tang := Vector2(-rad.y, rad.x)
	for j in 3:
		var c := center + rad * (float(j) - 1.0) * gap
		var half := length * 0.5
		if int(lines[j]) == 1:
			_bar(ci, c - tang * half, c + tang * half, bar_w, color)
		else:
			var g := length * 0.14
			_bar(ci, c - tang * half, c - tang * g, bar_w, color)
			_bar(ci, c + tang * g, c + tang * half, bar_w, color)


static func _bar(ci: RID, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * w * 0.5
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([a - n, b - n, b + n, a + n]), PackedColorArray([col, col, col, col]))


## 四角祥云（纹理为左上角版本，其余角翻转）
static func cloud_corners(ci: RID, rect: Rect2, size: float, color: Color, inset: float = 0.0) -> void:
	var t := tex("cloud_corner")
	if t == null or rect.size.x < size * 1.2 or rect.size.y < size * 1.2:
		return
	var r := rect.grow(-inset)
	rect_tex(ci, t, Rect2(r.position, Vector2(size, size)), color)
	rect_tex(ci, t, Rect2(Vector2(r.end.x - size, r.position.y), Vector2(size, size)), color, true)
	rect_tex(ci, t, Rect2(Vector2(r.position.x, r.end.y - size), Vector2(size, size)), color, false, true)
	rect_tex(ci, t, Rect2(r.end - Vector2(size, size), Vector2(size, size)), color, true, true)


## 横向祥云纹带（云头朝内）：左侧 [尾———云] 右侧镜像
static func cloud_band(ci: RID, rect: Rect2, color: Color, mirror: bool) -> void:
	rect_tex(ci, tex("cloud_band"), rect, color, mirror)


# ================================================================ 形状

## 委角（切角）矩形的顶点
static func chamfer_points(r: Rect2, c: float) -> PackedVector2Array:
	c = minf(c, minf(r.size.x, r.size.y) * 0.45)
	return PackedVector2Array([
		r.position + Vector2(c, 0), Vector2(r.end.x - c, r.position.y), Vector2(r.end.x, r.position.y + c),
		Vector2(r.end.x, r.end.y - c), Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y),
		Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c),
	])


## 委角牌匾：纵向渐变填充 + 可选描边
static func plaque(ci: RID, r: Rect2, c: float, top: Color, bottom: Color, border: Color = Color(0, 0, 0, 0), border_w: float = 1.0) -> void:
	var pts := chamfer_points(r, c)
	var cols := PackedColorArray()
	for p in pts:
		var f := clampf((p.y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0)
		cols.append(top.lerp(bottom, f))
	RenderingServer.canvas_item_add_polygon(ci, pts, cols)
	if border.a > 0.0 and border_w > 0.0:
		outline(ci, pts, border, border_w)


static func outline(ci: RID, pts: PackedVector2Array, col: Color, w: float) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	RenderingServer.canvas_item_add_polyline(ci, loop, PackedColorArray([col]), w, true)


## 回纹带：沿矩形上下边重复的“回”字形连续纹（unit 为单元宽度）
static func hui_band_h(ci: RID, x0: float, x1: float, y: float, unit: float, col: Color, w: float = 1.0) -> void:
	var n := int(floor((x1 - x0) / unit))
	if n <= 0:
		return
	var start := x0 + ((x1 - x0) - n * unit) * 0.5
	var h := unit * 0.62
	for i in n:
		var x := start + i * unit
		# 一个回纹单元：自左下起，向上、向右、向下、向左内折
		var pts := PackedVector2Array([
			Vector2(x, y + h), Vector2(x, y), Vector2(x + unit * 0.78, y), Vector2(x + unit * 0.78, y + h * 0.78),
			Vector2(x + unit * 0.28, y + h * 0.78), Vector2(x + unit * 0.28, y + h * 0.36), Vector2(x + unit * 0.52, y + h * 0.36),
		])
		RenderingServer.canvas_item_add_polyline(ci, pts, PackedColorArray([col]), w, false)
		RenderingServer.canvas_item_add_line(ci, Vector2(x, y + h), Vector2(x + unit, y + h), col, w)


## 菱形
static func diamond(ci: RID, c: Vector2, r: float, col: Color) -> void:
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), PackedColorArray([col, col, col, col]))


# ================================================================ 文字

## 带描边的横排文字；align 0 左 1 中 2 右；pos.y 为基线
static func text(ci: RID, f: Font, pos: Vector2, s: String, fs: int, col: Color, align: int = 0,
		outline_col: Color = Color(0, 0, 0, 0.7), outline_px: int = -1) -> float:
	fs = maxi(fs, 8)
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := pos.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	var o := outline_px if outline_px >= 0 else maxi(int(fs / 6.0), 2)
	if o > 0 and outline_col.a > 0.0:
		f.draw_string_outline(ci, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, o, Color(outline_col.r, outline_col.g, outline_col.b, outline_col.a * col.a))
	f.draw_string(ci, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return w


## 竖排文字：top 为首字顶部中点；返回总高度
static func vtext(ci: RID, f: Font, top: Vector2, s: String, fs: int, col: Color, spacing: float = 0.0,
		outline_col: Color = Color(0, 0, 0, 0.7), outline_px: int = -1) -> float:
	var y := top.y
	var step := fs * 1.02 + spacing
	for i in s.length():
		var ch := s.substr(i, 1)
		var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := Vector2(top.x - w * 0.5, y + f.get_ascent(fs) * 0.92)
		var o := outline_px if outline_px >= 0 else maxi(int(fs / 6.0), 2)
		if o > 0 and outline_col.a > 0.0:
			f.draw_string_outline(ci, base, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, o, Color(outline_col.r, outline_col.g, outline_col.b, outline_col.a * col.a))
		f.draw_string(ci, base, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		y += step
	return y - top.y


## 五行 → 单字
static func elem_glyph(e: String) -> String:
	match e:
		"metal":
			return "金"
		"wood":
			return "木"
		"water":
			return "水"
		"fire":
			return "火"
		"earth":
			return "土"
	return "玄"


## 境界序号 → 印章字
static func realm_glyph(realm_idx: int) -> String:
	var r := DB.realm(realm_idx)
	var nm := str(r.get("name", "凡人"))
	if nm == "":
		return "凡"
	# 取最能代表境界的一字：炼气→炼 筑基→筑 金丹→丹 元婴→婴 化神→神
	match nm:
		"金丹":
			return "丹"
		"元婴":
			return "婴"
		"化神":
			return "神"
	return nm.substr(0, 1)
