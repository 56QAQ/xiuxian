class_name HUDSpellBar
extends RefCounted
## 法诀栏：每个槽位是一张符纸——朱砂双框、五行圆印（金木水火土）、法诀名、灵力消耗；
## 冷却时水墨自上而下晕染并显示余秒；灵力不足时符纸黯淡、朱框闪烁。最右为葫芦形丹药快捷栏（Q）。

const W := 58.0
const H := 80.0
const GAP := 10.0
const OUTLINE := Color(0.04, 0.03, 0.02, 0.85)


static func draw(ci: RID, hud: CombatHUD, vs: Vector2, s: float) -> void:
	var a := hud.actor
	var pd := a.pd
	if pd == null:
		return
	var n := BuildCalc.spell_slot_count(pd)
	var w := W * s
	var h := H * s
	var gap := GAP * s
	var total := n * w + (n - 1) * gap + gap * 2.5 + w
	var x := (vs.x - total) * 0.5
	var y := vs.y - h - 22.0 * s
	# 底衬墨痕
	InkArt.brush(ci, Vector2(x - 40.0 * s, y + h * 0.62), Vector2(x + total + 50.0 * s, y + h * 0.62), h * 0.9, Color(0.02, 0.02, 0.03, 0.42))
	var fd := UITheme.font_display()
	var fb := UITheme.font_title()
	for i in n:
		var id: String = pd.spell_slots[i] if i < pd.spell_slots.size() else ""
		var r := Rect2(Vector2(x, y), Vector2(w, h))
		if id == "":
			_empty(ci, r, s, i, fb)
		else:
			_talisman(ci, r, s, i, id, a, hud, fd, fb)
		x += w + gap
	x += gap * 1.5
	_gourd(ci, Rect2(Vector2(x, y), Vector2(w, h)), s, a, fd, fb)


static func _empty(ci: RID, r: Rect2, s: float, i: int, fb: Font) -> void:
	var col := Color(0.9, 0.8, 0.6, 0.28)
	RenderingServer.canvas_item_add_rect(ci, r, Color(0.02, 0.02, 0.02, 0.25))
	# 虚线框
	var dash := 6.0 * s
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for k in 4:
		var p0: Vector2 = pts[k]
		var p1: Vector2 = pts[(k + 1) % 4]
		var ln := p0.distance_to(p1)
		var dir := (p1 - p0) / ln
		var dd := 0.0
		while dd < ln:
			RenderingServer.canvas_item_add_line(ci, p0 + dir * dd, p0 + dir * minf(dd + dash, ln), col, 1.0 * s)
			dd += dash * 2.0
	InkArt.text(ci, fb, r.position + Vector2(6.0 * s, 17.0 * s), str(i + 1), int(14 * s), Color(1, 0.95, 0.85, 0.5), 0, OUTLINE, 2)


static func _talisman(ci: RID, r: Rect2, s: float, i: int, id: String, a: HumanoidActor, hud: CombatHUD, fd: Font, fb: Font) -> void:
	var def := DB.spell(id)
	var e := str(def.get("element", ""))
	var ecol := Elem.color_of(e) if Elem.is_valid(e) else Color(0.7, 0.62, 0.9)
	var qi_cost := float(def.get("qi", 0))
	var no_qi := a.combatant.qi < qi_cost
	var cd := a.spell_cooldown(id)
	var maxcd := maxf(float(def.get("cd", 1.0)), 0.01)
	var red := Color(0.72, 0.1, 0.06, 0.95)
	if no_qi:
		red = Color(0.95, 0.2, 0.15, 0.55 + 0.45 * sin(hud.t * 9.0))
	draw_paper(ci, r, s, i, no_qi, red)
	# 五行圆印
	var sc := Vector2(r.get_center().x, r.position.y + 29.0 * s)
	InkArt.seal(ci, sc, 34.0 * s, InkArt.elem_glyph(e), ecol.darkened(0.25), Color(1.0, 0.97, 0.9), true, 0.0, fd)
	# 法诀名（朱砂书法）
	var nm := str(def.get("name", id))
	InkArt.text(ci, fd, Vector2(r.get_center().x, r.end.y - 11.0 * s), nm.substr(0, 2), int(19 * s), Color(0.55, 0.06, 0.04), 1, Color(0, 0, 0, 0), 0)
	# 键位
	InkArt.text(ci, fb, r.position + Vector2(7.0 * s, 16.0 * s), str(i + 1), int(13 * s), Color(0.3, 0.16, 0.08, 0.9), 0, Color(0, 0, 0, 0), 0)
	# 灵力消耗：右上青色小珠
	var qc := r.position + Vector2(r.size.x - 9.0 * s, 10.0 * s)
	RenderingServer.canvas_item_add_circle(ci, qc, 8.5 * s, Color(0.06, 0.22, 0.45, 0.95) if not no_qi else Color(0.5, 0.1, 0.08, 0.95))
	InkArt.text(ci, fb, qc + Vector2(0, 4.0 * s), str(int(qi_cost)), int(11 * s), Color(0.85, 0.95, 1.0), 1, Color(0, 0, 0, 0), 0)
	# 冷却：水墨自上而下晕染
	if cd > 0.0:
		var f := clampf(cd / maxcd, 0.0, 1.0)
		var ih := r.size.y * f
		if ih > 1.0:
			var ir := Rect2(r.position, Vector2(r.size.x, ih))
			RenderingServer.canvas_item_add_rect(ci, ir, Color(0.05, 0.04, 0.05, 0.72))
			# 墨边（参差）
			InkArt.brush(ci, Vector2(r.position.x - 2.0 * s, r.position.y + ih), Vector2(r.end.x + 2.0 * s, r.position.y + ih), 10.0 * s, Color(0.05, 0.04, 0.05, 0.72), "brush_thin")
		InkArt.text(ci, fd, Vector2(r.get_center().x, r.get_center().y + 12.0 * s), ("%.1f" % cd) if cd < 10.0 else str(int(cd)), int(28 * s), Color(1.0, 0.97, 0.9), 1, OUTLINE, int(4 * s))


## 一张黄符纸：投影 + 纵向渐变纸色 + 纤维与斑驳 + 朱砂双框（dim：灰纸）
static func draw_paper(ci: RID, r: Rect2, s: float, seed_i: int, dim: bool = false, red: Color = Color(0.72, 0.1, 0.06, 0.95)) -> void:
	RenderingServer.canvas_item_add_rect(ci, Rect2(r.position + Vector2(2.0, 3.0) * s, r.size), Color(0, 0, 0, 0.35))
	var top := Color(0.93, 0.82, 0.52)
	var bot := Color(0.82, 0.66, 0.36)
	if dim:
		top = Color(0.55, 0.52, 0.48)
		bot = Color(0.42, 0.4, 0.38)
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bot, bot]))
	InkArt.tile(ci, r, InkArt.tex("paper_fiber"), Color(0.45, 0.28, 0.1, 0.22), 0.35, Vector2(seed_i * 97.0, seed_i * 53.0))
	InkArt.tile(ci, r, InkArt.tex("paper_mottle"), Color(0.5, 0.3, 0.1, 0.16), 0.3, Vector2(seed_i * 131.0, 17.0))
	_frame(ci, r.grow(-3.0 * s), red, 1.6 * s)
	_frame(ci, r.grow(-5.5 * s), Color(red.r, red.g, red.b, red.a * 0.6), 0.8 * s)


static func _frame(ci: RID, r: Rect2, col: Color, w: float) -> void:
	RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(r.size.x, w)), col)
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.position.x, r.end.y - w), Vector2(r.size.x, w)), col)
	RenderingServer.canvas_item_add_rect(ci, Rect2(r.position, Vector2(w, r.size.y)), col)
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.end.x - w, r.position.y), Vector2(w, r.size.y)), col)


## 葫芦：漆色葫芦剪影 + 红绳，下方药名与数量
static func _gourd(ci: RID, r: Rect2, s: float, a: HumanoidActor, fd: Font, fb: Font) -> void:
	var qid := GS.player.quick_item if a.is_player and GS.player != null else ""
	var cnt := GS.player.bag.count_of(qid) if qid != "" else 0
	var has := qid != "" and cnt > 0
	var cx := r.get_center().x
	var top := Color(0.62, 0.36, 0.14) if has else Color(0.3, 0.26, 0.22)
	var bot := Color(0.34, 0.16, 0.06) if has else Color(0.18, 0.16, 0.14)
	var gold := Color(0.95, 0.78, 0.42) if has else Color(0.6, 0.55, 0.45)
	var small_c := Vector2(cx, r.position.y + 21.0 * s)
	var big_c := Vector2(cx, r.position.y + 45.0 * s)
	var rs := 10.5 * s
	var rb := 16.5 * s
	# 描边（先画略大的深色）
	RenderingServer.canvas_item_add_circle(ci, big_c + Vector2(0, 1.5 * s), rb + 2.0 * s, Color(0, 0, 0, 0.45))
	RenderingServer.canvas_item_add_circle(ci, big_c, rb + 1.2 * s, gold)
	RenderingServer.canvas_item_add_circle(ci, small_c, rs + 1.2 * s, gold)
	RenderingServer.canvas_item_add_circle(ci, big_c, rb, bot)
	RenderingServer.canvas_item_add_circle(ci, small_c, rs, bot)
	RenderingServer.canvas_item_add_circle(ci, big_c + Vector2(-4.0, -5.0) * s, rb * 0.6, top)
	RenderingServer.canvas_item_add_circle(ci, small_c + Vector2(-2.5, -3.0) * s, rs * 0.55, top)
	# 腰绳与塞子
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(cx - 7.0 * s, small_c.y + rs - 3.0 * s), Vector2(14.0 * s, 3.5 * s)), Color(0.8, 0.14, 0.1))
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(cx - 3.0 * s, small_c.y - rs - 6.0 * s), Vector2(6.0 * s, 7.0 * s)), Color(0.45, 0.3, 0.16))
	RenderingServer.canvas_item_add_line(ci, Vector2(cx + 6.0 * s, small_c.y + rs - 1.0 * s), Vector2(cx + 13.0 * s, small_c.y + rs + 12.0 * s), Color(0.8, 0.14, 0.1), 2.0 * s)
	RenderingServer.canvas_item_add_circle(ci, big_c + Vector2(-6.0, -8.0) * s, 3.0 * s, Color(1, 0.9, 0.7, 0.35))
	InkArt.text(ci, fb, r.position + Vector2(2.0 * s, 16.0 * s), "Q", int(14 * s), Color(1, 0.95, 0.85, 0.85), 0, OUTLINE, 2)
	if qid != "":
		var nm := str(DB.item(qid).get("name", ""))
		InkArt.text(ci, fd, Vector2(cx, r.end.y + 4.0 * s), nm.substr(0, 3), int(16 * s), Color(0.98, 0.9, 0.7) if has else Color(0.6, 0.58, 0.55), 1, OUTLINE, 3)
		InkArt.text(ci, fd, big_c + Vector2(0, 8.0 * s), "%d" % cnt, int(20 * s), Color(1.0, 0.96, 0.88), 1, OUTLINE, 3)
