class_name ItemIcon
extends Control
## 物品图标：按物品定义的 icon 种类程序化绘制像素风图标（每格 16 像素，最近邻放大 4 倍后线性缩放），
## 铺满占格 w×h。颜色取 icon_color / 兵器 visual / 法衣配色 / 五行 / 品阶。
## 静态 texture_for(id, grade) 带缓存，GridView、装备槽、商店、配方等共用。
##
## icon 种类：sword saber spear fist robe armor pendant ring pill herb flower fruit ore crystal core
##            stone scroll talisman bag seed hide bone key disc

const PX := 16
const UPSCALE := 4

## 显示的物品
@export var item_id: String = "":
	set(v):
		item_id = v
		queue_redraw()
var grade: int = -1
var count: int = 0
## 绘制品阶底框
var show_frame: bool = true
## 按占格旋转 90°
var rotated: bool = false

static var _cache: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(48, 48)


static func make(id: String, px_size: float = 48.0, g: int = -1, n: int = 0) -> ItemIcon:
	var ic := ItemIcon.new()
	ic.item_id = id
	ic.grade = g
	ic.count = n
	var s := size_of(id)
	var cell := px_size / maxf(s.x, s.y)
	ic.custom_minimum_size = Vector2(maxf(s.x * cell, px_size * 0.5), maxf(s.y * cell, px_size * 0.5))
	if s.x != s.y:
		ic.custom_minimum_size = Vector2(px_size, px_size)
	return ic


static func size_of(id: String) -> Vector2i:
	var s: Array = DB.item(id).get("size", [1, 1])
	return Vector2i(int(s[0]), int(s[1]))


func _draw() -> void:
	if item_id == "":
		return
	var d := DB.item(item_id)
	var g := grade if grade >= 0 else int(d.get("grade", 0))
	var r := Rect2(Vector2.ZERO, size)
	if show_frame:
		draw_cell_bg(self, r, g, false)
	draw_icon(self, r.grow(-3), item_id, g, rotated)
	if count > 1:
		draw_count(self, r, count)


## 在 rect 内按原始比例居中绘制物品图标（rot：顺时针旋转 90°）
static func draw_icon(ci: CanvasItem, rect: Rect2, id: String, g: int = -1, rot: bool = false, alpha: float = 1.0) -> void:
	var tex := texture_for(id, g)
	if tex == null:
		return
	var ts := Vector2(tex.get_width(), tex.get_height())
	var box := Vector2(rect.size.y, rect.size.x) if rot else rect.size
	var k := minf(box.x / ts.x, box.y / ts.y)
	var ds := ts * k
	var center := rect.get_center()
	if rot:
		ci.draw_set_transform(center, PI * 0.5, Vector2.ONE)
		ci.draw_texture_rect(tex, Rect2(-ds * 0.5, ds), false, Color(1, 1, 1, alpha))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		ci.draw_texture_rect(tex, Rect2(center - ds * 0.5, ds), false, Color(1, 1, 1, alpha))


## 物品格底色：品阶色渐变 + 细边
static func draw_cell_bg(ci: CanvasItem, rect: Rect2, g: int, hovered: bool, alpha: float = 1.0) -> void:
	var gc := Grade.color_of(g)
	var top := Color(gc.r * 0.22, gc.g * 0.22, gc.b * 0.22, 0.85 * alpha)
	var bot := Color(gc.r * 0.08 + 0.02, gc.g * 0.08 + 0.02, gc.b * 0.08 + 0.03, 0.9 * alpha)
	if hovered:
		top = top.lightened(0.12)
	var pts := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	ci.draw_polygon(pts, PackedColorArray([top, top, bot, bot]))
	var bc := Color(gc.r, gc.g, gc.b, (0.75 if hovered else 0.5) * alpha)
	ci.draw_rect(rect.grow(-0.5), bc, false, 1.5 if g >= 2 else 1.0)
	if g >= 3:
		# 高品阶：角点亮饰
		var s := 5.0
		for c in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			var dir: Vector2 = (rect.get_center() - c).sign()
			ci.draw_line(c + dir, c + dir + Vector2(dir.x * s, 0), gc, 2.0)
			ci.draw_line(c + dir, c + dir + Vector2(0, dir.y * s), gc, 2.0)


static func draw_count(ci: CanvasItem, rect: Rect2, n: int, fs: int = 15) -> void:
	var f := UITheme.font_regular()
	var t := str(n)
	var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var p := Vector2(rect.end.x - ts.x - 4, rect.end.y - 4)
	ci.draw_string_outline(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
	ci.draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.95, 0.85))


# ================================================================ 生成纹理

static func texture_for(id: String, g: int = -1) -> Texture2D:
	var d := DB.item(id)
	if d.is_empty():
		return null
	var gg := g if g >= 0 else int(d.get("grade", 0))
	var key := "%s:%d" % [id, gg]
	if _cache.has(key):
		return _cache[key]
	var tex := render(d, gg)
	_cache[key] = tex
	return tex


static func clear_cache() -> void:
	_cache.clear()


## 绘制图像（未放大）。长宽比与占格一致；横向物品先按竖向绘制再旋转。
static func render_image(d: Dictionary, g: int) -> Image:
	var s: Array = d.get("size", [1, 1])
	var w := int(s[0]) * PX
	var h := int(s[1]) * PX
	var landscape := w > h
	var cv := Canvas.new(h if landscape else w, w if landscape else h)
	_paint(cv, str(d.get("icon", "")), d, g)
	if landscape:
		cv.img.rotate_90(CLOCKWISE)
	return cv.img


static func render(d: Dictionary, g: int) -> ImageTexture:
	var img := render_image(d, g)
	img.resize(img.get_width() * UPSCALE, img.get_height() * UPSCALE, Image.INTERPOLATE_NEAREST)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _col(v: Variant, fallback: Color) -> Color:
	if v is String and (v as String).begins_with("#"):
		return Color.html(v)
	return fallback


static func _elem_col(d: Dictionary, fallback: Color) -> Color:
	var e := str(d.get("element", ""))
	return Elem.color_of(e) if Elem.is_valid(e) else fallback


static func _paint(cv: Canvas, kind: String, d: Dictionary, g: int) -> void:
	var gc := Grade.color_of(g)
	match kind:
		"sword":
			_sword(cv, d, false)
		"saber":
			_sword(cv, d, true)
		"spear":
			_spear(cv, d)
		"fist":
			_fist(cv, d)
		"robe":
			_robe(cv, d, false)
		"armor":
			_robe(cv, d, true)
		"pendant":
			_pendant(cv, d)
		"ring":
			_ring(cv, d)
		"pill":
			_pill(cv, d)
		"herb":
			_herb(cv, d)
		"flower":
			_flower(cv, d)
		"fruit":
			_fruit(cv, d)
		"ore":
			_ore(cv, d)
		"crystal":
			_crystal(cv, d)
		"core":
			_core(cv, d)
		"stone":
			_stone(cv, d)
		"scroll":
			_scroll(cv, d)
		"talisman":
			_talisman(cv, d)
		"bag":
			_bag(cv, d, gc)
		"seed":
			_seed(cv, d)
		"hide":
			_hide(cv, d)
		"bone":
			_bone(cv, d)
		"key":
			_key(cv, d)
		"disc":
			_disc(cv, d)
		_:
			_default(cv, gc)


# ---------------------------------------------------------------- 兵刃

static func _sword(cv: Canvas, d: Dictionary, saber: bool) -> void:
	var vis: Dictionary = d.get("weapon", {}).get("visual", {})
	var blade := _col(vis.get("blade", ""), Color(0.82, 0.84, 0.88))
	var guard := _col(vis.get("guard", ""), Color(0.78, 0.6, 0.25))
	var grip := _col(vis.get("grip", ""), Color(0.3, 0.2, 0.12))
	var glow := str(vis.get("glow", ""))
	if Elem.is_valid(glow):
		blade = blade.lerp(Elem.color_of(glow), 0.25)
	var W := cv.w
	var H := cv.h
	var cx := W / 2
	var guard_y := int(H * 0.68)
	var grip_end := H - 5
	# 刃
	for y in range(1, guard_y):
		var t := float(y) / guard_y
		var x0: int
		var x1: int
		if saber:
			var bow := int(round(1.6 * sin(t * PI)))
			x0 = cx - 2
			x1 = cx + 2 + bow
			if y < 6:
				x0 = cx - 2 + (6 - y) / 2 + bow
		else:
			x0 = cx - 2
			x1 = cx + 1
			if y < 4:
				x0 = cx - 1 - (1 if y >= 2 else 0)
				x1 = cx + (0 if y >= 2 else -1) + (1 if y >= 3 else 0)
		cv.hline(x0, x1, y, blade)
		cv.px(x0, y, blade.lightened(0.35))
		cv.px(x1, y, blade.darkened(0.35))
		if not saber and y > 4:
			cv.px(cx - 1, y, blade.lightened(0.5))
		elif saber and y > 4:
			cv.px(x0 + 1, y, blade.lightened(0.2))
	if Elem.is_valid(glow):
		for y in range(6, guard_y - 2, 5):
			cv.px(cx - 1, y, Elem.color_of(glow).lightened(0.4))
	# 护手
	if saber:
		cv.ellipse(cx - 0.5, guard_y + 1.0, 4.2, 2.0, guard)
	else:
		cv.rect(cx - 6, guard_y, cx + 5, guard_y + 2, guard)
		cv.px(cx - 7, guard_y - 1, guard)
		cv.px(cx + 6, guard_y - 1, guard)
		cv.hline(cx - 6, cx + 5, guard_y, guard.lightened(0.3))
	var gem := _elem_col(d, Color(0.9, 0.2, 0.2))
	cv.rect(cx - 1, guard_y, cx, guard_y + 1, gem)
	# 握把（缠绳）
	for y in range(guard_y + 3, grip_end):
		cv.hline(cx - 2, cx + 1, y, grip if (y / 2) % 2 == 0 else grip.lightened(0.18))
	# 剑首
	cv.rect(cx - 2, grip_end, cx + 1, grip_end + 2, guard)
	cv.hline(cx - 3, cx + 2, grip_end + 1, guard)
	if saber:
		cv.ring(cx - 0.5, grip_end + 2.5, 2.6, 1.2, guard)
	cv.outline(blade.darkened(0.8))


static func _spear(cv: Canvas, d: Dictionary) -> void:
	var vis: Dictionary = d.get("weapon", {}).get("visual", {})
	var blade := _col(vis.get("blade", ""), Color(0.85, 0.87, 0.9))
	var guard := _col(vis.get("guard", ""), Color(0.8, 0.15, 0.12))
	var grip := _col(vis.get("grip", ""), Color(0.4, 0.22, 0.12))
	var flag := _col(vis.get("flag", ""), Color(0, 0, 0, 0))
	var W := cv.w
	var H := cv.h
	var cx := W / 2
	var head_end := int(H * 0.2)
	# 枪杆
	for y in range(head_end + 2, H - 1):
		cv.hline(cx - 1, cx, y, grip)
		cv.px(cx - 1, y, grip.lightened(0.25))
	cv.rect(cx - 1, H - 3, cx, H - 1, guard.darkened(0.2))
	# 枪头（叶形）
	for y in range(0, head_end):
		var t := float(y) / head_end
		var half := int(round(sin(minf(t * 1.25, 1.0) * PI * 0.5) * 3.0 * (1.0 - maxf(t - 0.8, 0.0) * 3.0)))
		cv.hline(cx - 1 - half, cx + half, y, blade)
		cv.px(cx - 1 - half, y, blade.lightened(0.3))
		cv.px(cx + half, y, blade.darkened(0.3))
		if y > 1:
			cv.px(cx - 1, y, blade.lightened(0.5))
	# 枪缨
	cv.rect(cx - 2, head_end, cx + 1, head_end + 1, Color(0.85, 0.7, 0.3))
	var tassel := guard if guard.r > guard.g else Color(0.85, 0.12, 0.1)
	for i in 9:
		var x := cx - 4 + i
		var len_t := 6 + (i * 7) % 4
		cv.vline(x, head_end + 2, head_end + 1 + len_t, tassel if i % 2 == 0 else tassel.darkened(0.2))
	# 旗
	if flag.a > 0.0:
		var fy0 := head_end + 12
		var fy1 := fy0 + int(H * 0.28)
		for y in range(fy0, fy1):
			var wave := int(round(sin(float(y - fy0) * 0.5) * 1.0))
			cv.hline(cx + 1, W - 2 + wave, y, flag)
			cv.px(W - 2 + wave, y, Color(0.95, 0.75, 0.3))
		cv.hline(cx + 1, W - 2, fy0, Color(0.95, 0.75, 0.3))
		cv.hline(cx + 1, W - 2, fy1 - 1, Color(0.95, 0.75, 0.3))
		cv.rect(cx + 4, fy0 + 4, cx + 5, fy1 - 5, Color(0.98, 0.85, 0.4))
	cv.outline(grip.darkened(0.75))


static func _fist(cv: Canvas, d: Dictionary) -> void:
	var cloth := _col(d.get("icon_color", ""), Color(0.86, 0.8, 0.66))
	cv.rect(4, 4, 11, 12, cloth)
	for x in [4, 6, 8, 10]:
		cv.rect(x, 2, x + 1, 4, cloth.lightened(0.1))
	cv.rect(2, 7, 4, 11, cloth.darkened(0.1))
	for y in [6, 9, 12]:
		cv.hline(4, 11, y, cloth.darkened(0.3))
	cv.rect(5, 13, 10, 14, Color(0.6, 0.2, 0.15))
	cv.shade()
	cv.outline(cloth.darkened(0.8))


# ---------------------------------------------------------------- 法衣

static func _robe(cv: Canvas, d: Dictionary, armor: bool) -> void:
	var vis: Dictionary = d.get("equip", {}).get("visual", {})
	var cols: Array = vis.get("outfit_colors", [])
	var c1 := _col(cols[0] if cols.size() > 0 else d.get("icon_color", ""), Color(0.55, 0.55, 0.5))
	var c2 := _col(cols[1] if cols.size() > 1 else "", c1.darkened(0.4))
	var c3 := _col(cols[2] if cols.size() > 2 else "", Color(0.85, 0.7, 0.35))
	var W := float(cv.w)
	var H := float(cv.h)
	var sx := W / 32.0
	var sy := H / 48.0
	var P := func(x: float, y: float) -> Vector2: return Vector2(x * sx, y * sy)
	# 袖
	cv.poly(PackedVector2Array([P.call(9, 5), P.call(1, 20), P.call(2, 27), P.call(7, 27), P.call(11, 13)]), c1)
	cv.poly(PackedVector2Array([P.call(23, 5), P.call(31, 20), P.call(30, 27), P.call(25, 27), P.call(21, 13)]), c1)
	cv.poly(PackedVector2Array([P.call(1, 24), P.call(2, 27), P.call(7, 27), P.call(7.5, 24)]), c3)
	cv.poly(PackedVector2Array([P.call(31, 24), P.call(30, 27), P.call(25, 27), P.call(24.5, 24)]), c3)
	# 身
	cv.poly(PackedVector2Array([P.call(9, 4), P.call(23, 4), P.call(24, 22), P.call(28, 46), P.call(4, 46), P.call(8, 22)]), c1)
	if armor:
		# 甲片：横纹
		for y in range(int(8 * sy), int(22 * sy), maxi(int(3 * sy), 2)):
			cv.hline(int(9 * sx), int(23 * sx), y, c1.darkened(0.3))
		cv.poly(PackedVector2Array([P.call(6, 25), P.call(15.5, 25), P.call(15.5, 44), P.call(5, 44)]), c1.darkened(0.08))
		cv.poly(PackedVector2Array([P.call(16.5, 25), P.call(26, 25), P.call(27, 44), P.call(16.5, 44)]), c1.darkened(0.08))
		for y in range(int(28 * sy), int(44 * sy), maxi(int(4 * sy), 2)):
			cv.hline(int(6 * sx), int(26 * sx), y, c2)
		# 护肩
		cv.ellipse(8 * sx, 7 * sy, 5.5 * sx, 3.5 * sy, c3)
		cv.ellipse(24 * sx, 7 * sy, 5.5 * sx, 3.5 * sy, c3)
		cv.ellipse(16 * sx, 14 * sy, 3.0 * sx, 3.0 * sy, c3.lightened(0.2))
	else:
		# 交领
		cv.thick_line(P.call(11, 4), P.call(18, 17), 1.2 * sx, c3)
		cv.thick_line(P.call(21, 4), P.call(16, 11), 1.0 * sx, c2)
		cv.hline(int(5 * sx), int(27 * sx), int(44 * sy), c3)
		cv.hline(int(5 * sx), int(27 * sx), int(45 * sy), c3)
		cv.vline(int(16 * sx), int(24 * sy), int(44 * sy), c1.darkened(0.2))
	# 腰带
	cv.rect(int(8 * sx), int(21 * sy), int(24 * sx), int(23.5 * sy), c2)
	cv.hline(int(8 * sx), int(24 * sx), int(21 * sy), c3)
	cv.rect(int(15 * sx), int(21 * sy), int(17 * sx), int(23.5 * sy), c3)
	cv.shade(0.18, 0.25)
	cv.outline(c1.darkened(0.8))


# ---------------------------------------------------------------- 佩饰

static func _pendant(cv: Canvas, d: Dictionary) -> void:
	var jade := _col(d.get("icon_color", ""), Color(0.5, 0.85, 0.62))
	var e := str(d.get("element", ""))
	if not d.has("icon_color") and Elem.is_valid(e):
		jade = jade.lerp(Elem.color_of(e), 0.35)
	cv.vline(8, 0, 3, Color(0.8, 0.15, 0.12))
	cv.vline(7, 0, 2, Color(0.8, 0.15, 0.12))
	cv.rect(6, 3, 9, 4, Color(0.9, 0.25, 0.18))
	cv.ring(7.5, 9.5, 5.6, 1.8, jade)
	cv.px(5, 7, jade.lightened(0.45))
	cv.px(6, 6, jade.lightened(0.45))
	cv.px(9, 13, jade.darkened(0.25))
	cv.px(11, 11, jade.darkened(0.25))
	cv.outline(jade.darkened(0.75))


static func _ring(cv: Canvas, d: Dictionary) -> void:
	var band := _col(d.get("icon_color", ""), Color(0.92, 0.76, 0.35))
	var gem := _elem_col(d, Color(0.9, 0.2, 0.3))
	cv.ring(7.5, 9.5, 5.4, 3.4, band)
	cv.px(3, 8, band.lightened(0.4))
	cv.px(4, 6, band.lightened(0.4))
	cv.disc(7.5, 4.5, 2.6, gem)
	cv.px(6, 3, gem.lightened(0.6))
	cv.rect(5, 6, 10, 6, band.darkened(0.15))
	cv.outline(band.darkened(0.8))


# ---------------------------------------------------------------- 丹药 / 灵物

static func _pill(cv: Canvas, d: Dictionary) -> void:
	var c := _col(d.get("icon_color", ""), Color(0.9, 0.7, 0.3))
	# 光晕
	for y in cv.h:
		for x in cv.w:
			var dd := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(8, 8))
			if dd > 5.5 and dd < 7.8:
				cv.px(x, y, Color(c.r, c.g, c.b, 0.22 * (7.8 - dd) / 2.3))
	cv.disc(8, 8, 5.2, c)
	cv.disc(8.7, 8.7, 3.6, c.darkened(0.12))
	cv.disc(7.5, 7.5, 3.4, c)
	cv.rect(5, 5, 6, 5, c.lightened(0.6))
	cv.px(5, 6, c.lightened(0.45))
	cv.px(10, 11, c.darkened(0.35))
	cv.px(11, 10, c.darkened(0.35))
	cv.outline(c.darkened(0.75), true)


static func _herb(cv: Canvas, d: Dictionary) -> void:
	var leaf := _col(d.get("icon_color", ""), Color(0.4, 0.78, 0.4))
	var H := cv.h
	var stem := leaf.darkened(0.35)
	for y in range(3, H - 3):
		var x := 8 + int(round(sin(y * 0.25) * 0.8))
		cv.px(x, y, stem)
	var ly := 5
	var side := -1
	while ly < H - 6:
		var cx := 8 + side * 3.2
		cv.ellipse(cx, ly + 1.5, 3.0, 1.6, leaf)
		cv.px(int(cx) + side, ly + 1, leaf.lightened(0.3))
		side = -side
		ly += 4
	cv.ellipse(8, 3, 1.6, 2.6, leaf.lightened(0.1))
	cv.px(9, 1, Color(0.75, 0.95, 1.0))
	cv.px(10, 2, Color(0.55, 0.85, 1.0))
	# 根
	cv.hline(6, 10, H - 3, Color(0.55, 0.38, 0.22))
	cv.px(5, H - 2, Color(0.55, 0.38, 0.22))
	cv.px(11, H - 2, Color(0.55, 0.38, 0.22))
	cv.px(8, H - 2, Color(0.55, 0.38, 0.22))
	cv.outline(leaf.darkened(0.8))


static func _flower(cv: Canvas, d: Dictionary) -> void:
	var c := _col(d.get("icon_color", ""), Color(0.95, 0.55, 0.7))
	var W := float(cv.w)
	var H := float(cv.h)
	var k := W / 16.0
	var cx := W * 0.5
	var cy := H * 0.52
	# 茎叶
	cv.thick_line(Vector2(cx, cy + 2 * k), Vector2(cx, H - 1), 0.7 * k, Color(0.3, 0.6, 0.3))
	cv.ellipse(cx - 3 * k, H - 3.5 * k, 2.6 * k, 1.2 * k, Color(0.35, 0.7, 0.35))
	cv.ellipse(cx + 3 * k, H - 4.5 * k, 2.6 * k, 1.2 * k, Color(0.3, 0.62, 0.3))
	# 莲瓣：外层
	for i in 5:
		var a := -PI * 0.5 + (i - 2) * 0.62
		var tip := Vector2(cx, cy) + Vector2(cos(a), sin(a)) * 6.2 * k
		var side := Vector2(-sin(a), cos(a)) * 2.1 * k
		var base := Vector2(cx, cy + 1.5 * k)
		cv.poly(PackedVector2Array([base + side, tip, base - side, base + Vector2(0, 1.5 * k)]), c.darkened(0.12) if i % 2 else c)
	# 内层
	for i in 3:
		var a2 := -PI * 0.5 + (i - 1) * 0.5
		var tip2 := Vector2(cx, cy) + Vector2(cos(a2), sin(a2)) * 4.4 * k
		var side2 := Vector2(-sin(a2), cos(a2)) * 1.6 * k
		cv.poly(PackedVector2Array([Vector2(cx, cy + k) + side2, tip2, Vector2(cx, cy + k) - side2]), c.lightened(0.25))
	cv.disc(cx, cy + 0.5 * k, 1.3 * k, Color(1.0, 0.85, 0.35))
	cv.outline(c.darkened(0.75))


static func _fruit(cv: Canvas, d: Dictionary) -> void:
	var c := _col(d.get("icon_color", ""), Color(0.95, 0.3, 0.2))
	cv.disc(7.5, 9.5, 5.3, c)
	cv.disc(8.5, 10.5, 3.5, c.darkened(0.12))
	cv.disc(7.2, 9.2, 3.4, c)
	cv.rect(4, 7, 5, 8, c.lightened(0.5))
	cv.vline(8, 2, 4, Color(0.45, 0.3, 0.15))
	cv.ellipse(10.5, 3, 2.4, 1.2, Color(0.35, 0.72, 0.3))
	cv.outline(c.darkened(0.78))


static func _ore(cv: Canvas, d: Dictionary) -> void:
	var rock := _col(d.get("icon_color", ""), Color(0.42, 0.4, 0.42))
	var fleck := _elem_col(d, Color(0.85, 0.85, 0.9))
	var W := float(cv.w)
	var H := float(cv.h)
	var k := W / 16.0
	var pts := PackedVector2Array()
	var n := 9
	for i in n:
		var a := TAU * i / n
		var r := (5.8 + ((i * 37) % 5) * 0.45) * k
		pts.append(Vector2(W * 0.5, H * 0.55) + Vector2(cos(a), sin(a) * 0.8) * r)
	cv.poly(pts, rock)
	cv.poly(PackedVector2Array([pts[5], pts[6], Vector2(W * 0.5, H * 0.5), pts[4]]), rock.lightened(0.18))
	cv.poly(PackedVector2Array([pts[0], pts[1], Vector2(W * 0.55, H * 0.6)]), rock.darkened(0.2))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in int(7 * k):
		var p := Vector2(rng.randf_range(0.25, 0.75) * W, rng.randf_range(0.3, 0.8) * H)
		if cv.alpha(int(p.x), int(p.y)) > 0.5:
			cv.px(int(p.x), int(p.y), fleck)
			cv.px(int(p.x) + 1, int(p.y), fleck.darkened(0.3))
	cv.shade(0.15, 0.25)
	cv.outline(rock.darkened(0.7))


static func _crystal(cv: Canvas, d: Dictionary) -> void:
	var c := _col(d.get("icon_color", ""), _elem_col(d, Color(0.6, 0.8, 1.0)))
	var H := float(cv.h)
	var W := float(cv.w)
	var base := H - 2.0
	var prisms := [[W * 0.5, H * 0.08, 2.6], [W * 0.26, H * 0.36, 2.0], [W * 0.74, H * 0.3, 2.1]]
	for pr in prisms:
		var x: float = pr[0]
		var top: float = pr[1]
		var hw: float = pr[2]
		var shoulder := top + hw * 1.6
		cv.poly(PackedVector2Array([Vector2(x, top), Vector2(x + hw, shoulder), Vector2(x + hw, base), Vector2(x - hw, base), Vector2(x - hw, shoulder)]), c)
		cv.poly(PackedVector2Array([Vector2(x, top), Vector2(x, base), Vector2(x - hw, base), Vector2(x - hw, shoulder)]), c.lightened(0.3))
		cv.vline(int(x + hw) - 1, int(shoulder), int(base) - 1, c.darkened(0.25))
	cv.rect(1, int(H) - 3, int(W) - 2, int(H) - 2, Color(0.45, 0.4, 0.38))
	cv.outline(c.darkened(0.75))


static func _core(cv: Canvas, d: Dictionary) -> void:
	var c := _col(d.get("icon_color", ""), _elem_col(d, Color(0.75, 0.45, 0.95)))
	for y in cv.h:
		for x in cv.w:
			var dd := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(8, 8))
			if dd > 5.0 and dd < 8.0:
				cv.px(x, y, Color(c.r, c.g, c.b, 0.3 * (8.0 - dd) / 3.0))
	cv.disc(8, 8, 5.0, c.darkened(0.3))
	for i in 14:
		var a := i * 0.55
		var r := 0.6 + i * 0.28
		var p := Vector2(8, 8) + Vector2(cos(a), sin(a)) * r
		cv.px(int(p.x), int(p.y), c.lightened(0.35))
	cv.disc(8, 8, 1.4, Color(1, 1, 0.9))
	cv.px(5, 5, c.lightened(0.6))
	cv.outline(c.darkened(0.8), true)


static func _stone(cv: Canvas, d: Dictionary) -> void:
	var c := _col(d.get("icon_color", ""), Color(0.6, 0.88, 1.0))
	var pts := PackedVector2Array([Vector2(8, 1.5), Vector2(13, 5), Vector2(13, 11), Vector2(8, 14.5), Vector2(3, 11), Vector2(3, 5)])
	cv.poly(pts, c)
	cv.poly(PackedVector2Array([Vector2(8, 1.5), Vector2(8, 8), Vector2(3, 11), Vector2(3, 5)]), c.lightened(0.28))
	cv.poly(PackedVector2Array([Vector2(8, 8), Vector2(13, 11), Vector2(8, 14.5), Vector2(3, 11)]), c.darkened(0.2))
	cv.px(5, 5, Color(1, 1, 1, 0.9))
	cv.px(6, 4, Color(1, 1, 1, 0.7))
	cv.outline(c.darkened(0.75))


# ---------------------------------------------------------------- 典籍 / 符箓 / 杂物

static func _scroll(cv: Canvas, d: Dictionary) -> void:
	var e := str(d.get("element", ""))
	var jade := Color(0.55, 0.82, 0.68)
	if Elem.is_valid(e):
		jade = jade.lerp(Elem.color_of(e), 0.35)
	jade = _col(d.get("icon_color", ""), jade)
	var H := cv.h
	cv.rect(3, 3, 12, H - 4, jade)
	cv.hline(4, 11, 2, jade)
	cv.hline(4, 11, H - 3, jade)
	cv.vline(3, 3, H - 4, jade.lightened(0.3))
	cv.vline(12, 3, H - 4, jade.darkened(0.25))
	# 刻纹
	for y in range(6, H - 6, 3):
		cv.hline(5, 10 - (y % 2), y, jade.darkened(0.3))
	cv.rect(6, 4, 9, 5, jade.lightened(0.35))
	# 红绳
	cv.hline(2, 13, H / 2, Color(0.8, 0.16, 0.14))
	cv.px(13, H / 2 + 1, Color(0.8, 0.16, 0.14))
	cv.vline(14, H / 2 + 1, H / 2 + 5, Color(0.8, 0.16, 0.14))
	cv.outline(jade.darkened(0.8))


static func _talisman(cv: Canvas, d: Dictionary) -> void:
	var paper := _col(d.get("icon_color", ""), Color(0.96, 0.84, 0.4))
	var ink := Color(0.78, 0.12, 0.1)
	var H := cv.h
	cv.rect(4, 1, 11, H - 2, paper)
	cv.vline(4, 1, H - 2, paper.lightened(0.2))
	cv.vline(11, 1, H - 2, paper.darkened(0.2))
	cv.rect(6, 2, 9, 4, ink)
	cv.rect(7, 3, 8, 3, paper)
	cv.vline(7, 6, H - 4, ink)
	cv.hline(5, 10, 8, ink)
	cv.px(9, 10, ink)
	cv.px(6, 11, ink)
	cv.hline(6, 9, H - 4, ink)
	var e := str(d.get("element", ""))
	if Elem.is_valid(e):
		cv.px(8, 6, Elem.color_of(e))
	cv.outline(paper.darkened(0.8))


static func _bag(cv: Canvas, d: Dictionary, gc: Color) -> void:
	var cloth := _col(d.get("icon_color", ""), Color(0.55, 0.38, 0.22).lerp(gc, 0.45))
	var W := float(cv.w)
	var H := float(cv.h)
	var k := W / 16.0
	cv.ellipse(W * 0.5, H * 0.62, 6.2 * k, 5.4 * k, cloth)
	cv.poly(PackedVector2Array([Vector2(W * 0.5 - 2.5 * k, H * 0.36), Vector2(W * 0.5 + 2.5 * k, H * 0.36), Vector2(W * 0.5 + 4 * k, H * 0.18), Vector2(W * 0.5 - 4 * k, H * 0.18)]), cloth.lightened(0.1))
	cv.poly(PackedVector2Array([Vector2(W * 0.5 - 4.5 * k, H * 0.12), Vector2(W * 0.5 + 4.5 * k, H * 0.12), Vector2(W * 0.5 + 3.2 * k, H * 0.22), Vector2(W * 0.5 - 3.2 * k, H * 0.22)]), cloth.lightened(0.2))
	var cord := Color(0.95, 0.75, 0.3)
	cv.thick_line(Vector2(W * 0.5 - 3 * k, H * 0.33), Vector2(W * 0.5 + 3 * k, H * 0.33), 0.6 * k, cord)
	cv.thick_line(Vector2(W * 0.5 + 2.5 * k, H * 0.33), Vector2(W * 0.5 + 4 * k, H * 0.5), 0.5 * k, cord)
	var cx := W * 0.5
	var cy := H * 0.66
	var r := 2.0 * k
	cv.poly(PackedVector2Array([Vector2(cx, cy - r), Vector2(cx + r, cy), Vector2(cx, cy + r), Vector2(cx - r, cy)]), cord)
	cv.shade(0.15, 0.25)
	cv.outline(cloth.darkened(0.78))


static func _seed(cv: Canvas, d: Dictionary) -> void:
	var c := _col(d.get("icon_color", ""), Color(0.72, 0.52, 0.3))
	cv.ellipse(5, 10, 2.4, 3.0, c)
	cv.ellipse(11, 11, 2.4, 2.8, c.darkened(0.1))
	cv.ellipse(8, 5.5, 2.2, 2.6, c.lightened(0.1))
	cv.vline(8, 1, 3, Color(0.4, 0.75, 0.35))
	cv.px(9, 1, Color(0.4, 0.75, 0.35))
	cv.shade()
	cv.outline(c.darkened(0.78))


static func _hide(cv: Canvas, d: Dictionary) -> void:
	var c := _col(d.get("icon_color", ""), Color(0.58, 0.54, 0.5))
	var W := float(cv.w)
	var H := float(cv.h)
	var k := W / 16.0
	cv.poly(PackedVector2Array([
		Vector2(4 * k, 3 * k), Vector2(6 * k, 5 * k), Vector2(10 * k, 5 * k), Vector2(12 * k, 3 * k), Vector2(12.5 * k, 6.5 * k),
		Vector2(14.5 * k, 8 * k), Vector2(12 * k, 10 * k), Vector2(13 * k, 14 * k), Vector2(10 * k, 12.5 * k), Vector2(6 * k, 12.5 * k),
		Vector2(3 * k, 14 * k), Vector2(4 * k, 10 * k), Vector2(1.5 * k, 8 * k), Vector2(3.5 * k, 6.5 * k)]), c)
	for i in 4:
		cv.thick_line(Vector2((5 + i * 2) * k, 6.5 * k), Vector2((5.5 + i * 2) * k, 10.5 * k), 0.4 * k, c.darkened(0.25))
	cv.shade(0.15, 0.2)
	cv.outline(c.darkened(0.75))


static func _bone(cv: Canvas, d: Dictionary) -> void:
	var c := _col(d.get("icon_color", ""), Color(0.92, 0.88, 0.78))
	var W := float(cv.w)
	var H := float(cv.h)
	var a := Vector2(W * 0.28, H * 0.22)
	var b := Vector2(W * 0.72, H * 0.78)
	cv.thick_line(a, b, 1.4 * W / 16.0, c)
	for p in [a, b]:
		var perp := (b - a).normalized().orthogonal() * 1.8 * W / 16.0
		cv.disc(p.x + perp.x, p.y + perp.y, 1.9 * W / 16.0, c)
		cv.disc(p.x - perp.x, p.y - perp.y, 1.9 * W / 16.0, c)
	cv.shade(0.1, 0.25)
	cv.outline(c.darkened(0.7))


static func _key(cv: Canvas, d: Dictionary) -> void:
	var c := _col(d.get("icon_color", ""), Color(0.85, 0.66, 0.3))
	cv.rect(4, 3, 11, 13, c)
	cv.hline(5, 10, 2, c)
	cv.hline(6, 9, 1, c)
	cv.rect(6, 5, 9, 11, c.darkened(0.25))
	cv.vline(7, 6, 10, c.lightened(0.35))
	cv.hline(6, 9, 8, c.lightened(0.35))
	cv.vline(8, 14, 15, Color(0.8, 0.15, 0.12))
	cv.px(7, 15, Color(0.8, 0.15, 0.12))
	cv.px(9, 15, Color(0.8, 0.15, 0.12))
	cv.shade(0.2, 0.2)
	cv.outline(c.darkened(0.78))


static func _disc(cv: Canvas, d: Dictionary) -> void:
	var c := _col(d.get("icon_color", ""), Color(0.72, 0.55, 0.3))
	var W := float(cv.w)
	var k := W / 16.0
	var ctr := Vector2(W * 0.5, float(cv.h) * 0.5)
	cv.disc(ctr.x, ctr.y, 6.8 * k, c)
	cv.ring(ctr.x, ctr.y, 5.0 * k, 4.2 * k, c.darkened(0.35))
	for i in 8:
		var a := TAU * i / 8.0
		var p := ctr + Vector2(cos(a), sin(a)) * 5.9 * k
		cv.px(int(p.x), int(p.y), c.lightened(0.45))
	cv.disc(ctr.x, ctr.y, 2.4 * k, _elem_col(d, Color(0.4, 0.8, 0.7)))
	cv.disc(ctr.x - 0.6 * k, ctr.y - 0.6 * k, 0.8 * k, Color(1, 1, 1, 0.8))
	cv.outline(c.darkened(0.78), true)


static func _default(cv: Canvas, gc: Color) -> void:
	var W := float(cv.w)
	var H := float(cv.h)
	var r := minf(W, H) * 0.35
	cv.poly(PackedVector2Array([Vector2(W * 0.5, H * 0.5 - r), Vector2(W * 0.5 + r, H * 0.5), Vector2(W * 0.5, H * 0.5 + r), Vector2(W * 0.5 - r, H * 0.5)]), gc)
	cv.shade()
	cv.outline(gc.darkened(0.75))


# ================================================================ 像素画布

class Canvas:
	var img: Image
	var w: int
	var h: int

	func _init(pw: int, ph: int) -> void:
		w = pw
		h = ph
		img = Image.create(pw, ph, false, Image.FORMAT_RGBA8)

	func px(x: int, y: int, c: Color) -> void:
		if x < 0 or y < 0 or x >= w or y >= h:
			return
		if c.a >= 0.999:
			img.set_pixel(x, y, c)
		else:
			var under := img.get_pixel(x, y)
			img.set_pixel(x, y, under.blend(c) if under.a > 0.0 else c)

	func alpha(x: int, y: int) -> float:
		if x < 0 or y < 0 or x >= w or y >= h:
			return 0.0
		return img.get_pixel(x, y).a

	func rect(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
		for y in range(mini(y0, y1), maxi(y0, y1) + 1):
			for x in range(mini(x0, x1), maxi(x0, x1) + 1):
				px(x, y, c)

	func hline(x0: int, x1: int, y: int, c: Color) -> void:
		for x in range(mini(x0, x1), maxi(x0, x1) + 1):
			px(x, y, c)

	func vline(x: int, y0: int, y1: int, c: Color) -> void:
		for y in range(mini(y0, y1), maxi(y0, y1) + 1):
			px(x, y, c)

	func disc(cx: float, cy: float, r: float, c: Color) -> void:
		ellipse(cx, cy, r, r, c)

	func ellipse(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
		for y in range(int(floor(cy - ry)) - 1, int(ceil(cy + ry)) + 1):
			for x in range(int(floor(cx - rx)) - 1, int(ceil(cx + rx)) + 1):
				var dx := (x + 0.5 - cx) / maxf(rx, 0.01)
				var dy := (y + 0.5 - cy) / maxf(ry, 0.01)
				if dx * dx + dy * dy <= 1.0:
					px(x, y, c)

	func ring(cx: float, cy: float, r_out: float, r_in: float, c: Color) -> void:
		for y in range(int(floor(cy - r_out)) - 1, int(ceil(cy + r_out)) + 1):
			for x in range(int(floor(cx - r_out)) - 1, int(ceil(cx + r_out)) + 1):
				var dd := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(cx, cy))
				if dd <= r_out and dd >= r_in:
					px(x, y, c)

	func thick_line(a: Vector2, b: Vector2, r: float, c: Color) -> void:
		var x0 := int(floor(minf(a.x, b.x) - r)) - 1
		var x1 := int(ceil(maxf(a.x, b.x) + r)) + 1
		var y0 := int(floor(minf(a.y, b.y) - r)) - 1
		var y1 := int(ceil(maxf(a.y, b.y) + r)) + 1
		var ab := b - a
		var len2 := maxf(ab.length_squared(), 0.0001)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var p := Vector2(x + 0.5, y + 0.5)
				var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				if p.distance_to(a + ab * t) <= r:
					px(x, y, c)

	func poly(pts: PackedVector2Array, c: Color) -> void:
		var r := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			r = r.expand(p)
		for y in range(int(floor(r.position.y)), int(ceil(r.end.y)) + 1):
			for x in range(int(floor(r.position.x)), int(ceil(r.end.x)) + 1):
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
					px(x, y, c)

	## 像素风立体感：左上边缘提亮，右下边缘压暗
	func shade(light: float = 0.22, dark: float = 0.28) -> void:
		var src := img.duplicate() as Image
		for y in h:
			for x in w:
				var c := src.get_pixel(x, y)
				if c.a < 0.5:
					continue
				var up := y == 0 or src.get_pixel(x, y - 1).a < 0.5
				var left := x == 0 or src.get_pixel(x - 1, y).a < 0.5
				var down := y == h - 1 or src.get_pixel(x, y + 1).a < 0.5
				var right := x == w - 1 or src.get_pixel(x + 1, y).a < 0.5
				if up or left:
					img.set_pixel(x, y, c.lightened(light))
				elif down or right:
					img.set_pixel(x, y, c.darkened(dark))

	## 描边：与不透明像素相邻的透明像素涂为 c（soft：半透明像素也视为透明）
	func outline(c: Color, soft: bool = false) -> void:
		var src := img.duplicate() as Image
		var th := 0.9 if soft else 0.5
		for y in h:
			for x in w:
				if src.get_pixel(x, y).a >= th:
					continue
				var hit := false
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + o.x
					var ny: int = y + o.y
					if nx >= 0 and ny >= 0 and nx < w and ny < h and src.get_pixel(nx, ny).a >= 0.9:
						hit = true
						break
				if hit:
					img.set_pixel(x, y, c)
