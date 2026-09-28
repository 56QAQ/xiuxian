class_name HUDCluster
extends Control
## 中央簇（玉璧之上）：八卦护体、生命/灵力数值、韧性细弧、准星、竖排速度与高度、推进墨丝、御空、
## 状态印章（带时长刻度）、蓄力/搜索进度、受击方向墨痕、笔触命中标记与“斩”印。

const GOLD_LIT := Color(1.0, 0.85, 0.48)
const GOLD_DIM := Color(0.72, 0.62, 0.45, 0.3)
const HP_TEXT := Color(1.0, 0.62, 0.5)
const QI_TEXT := Color(0.6, 0.88, 1.0)
const PAPER := Color(0.96, 0.93, 0.85)
const OUTLINE := Color(0.05, 0.03, 0.02, 0.85)

var hud: CombatHUD


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _draw() -> void:
	if hud == null or not hud.has_actor():
		return
	var ci := get_canvas_item()
	var s := hud.ui_scale()
	var c := hud.cluster_center()
	var a := hud.actor
	var cb := a.combatant
	var r := CombatHUD.RING_R * s
	var fd := UITheme.font_display()
	_draw_trigrams(ci, c, r, s, cb)
	_draw_poise(ci, c, r, s, cb)
	_draw_values(ci, fd, c, r, s, cb)
	_draw_motion(ci, fd, c, r, s, a)
	_draw_statuses(ci, fd, Vector2(c.x, c.y + r + 60.0 * s), s, cb)
	_draw_progress(ci, fd, c, s, a)
	_draw_dmg_dirs(ci, c, r, s)
	var cx := c - hud.drift * s * 0.6
	_draw_crosshair(ci, cx, s)
	_draw_hits(ci, fd, cx, s)


# ---------------------------------------------------------------- 八卦护体
func _draw_trigrams(ci: RID, c: Vector2, r: float, s: float, cb: Combatant) -> void:
	var rt := r + (CombatHUD.BAND_W * 0.5 + 16.0) * s
	var has_shield := cb.stat("max_shield") > 0.5
	var sh := clampf(hud.shown_shield, 0.0, 1.0) * 8.0 if has_shield else 0.0
	var glow := UITheme.icon("dot")
	var flash := hud.shield_flash
	for k in 8:
		var ang := -PI * 0.5 + k * TAU / 8.0
		var dir := Vector2(cos(ang), sin(ang))
		var lit := clampf(sh - k, 0.0, 1.0)
		var p := c + dir * (rt + flash * 10.0 * s)
		if lit > 0.02:
			var gs := 30.0 * s
			RenderingServer.canvas_item_add_texture_rect(ci, Rect2(p - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), glow.get_rid(), false, Color(1.0, 0.75, 0.3, 0.32 * lit))
		# 暗底（被熄灭的卦仍可辨）
		InkArt.trigram(ci, p, ang, k, 22.0 * s, 4.6 * s, 5.6 * s, Color(0.05, 0.03, 0.02, 0.4 + 0.25 * lit))
		var col := GOLD_DIM.lerp(GOLD_LIT, lit)
		if flash > 0.0:
			col = col.lerp(Color(1.0, 0.97, 0.9, 1.0 - flash * 0.3), flash)
		InkArt.trigram(ci, p, ang, k, 20.0 * s, 3.0 * s, 5.6 * s, col)
	# 环带上下两处金饰（生命与灵力弧之间的空隙）
	for side: float in [-1.0, 1.0]:
		var gp := c + Vector2(0, side * r)
		InkArt.diamond(ci, gp, 6.0 * s, Color(0.1, 0.07, 0.03, 0.6))
		InkArt.diamond(ci, gp, 4.6 * s, Color(1.0, 0.84, 0.46, 0.95))
		InkArt.diamond(ci, gp, 1.8 * s, Color(0.75, 0.12, 0.08, 1.0))
		for sx: float in [-1.0, 1.0]:
			RenderingServer.canvas_item_add_line(ci, gp + Vector2(sx * 7.0 * s, 0), gp + Vector2(sx * 13.0 * s, 0), Color(1.0, 0.84, 0.46, 0.8), 1.2 * s, true)
	# 卦间小点
	for k in 8:
		var ang2 := -PI * 0.5 + (k + 0.5) * TAU / 8.0
		InkArt.diamond(ci, c + Vector2(cos(ang2), sin(ang2)) * rt, 1.8 * s, Color(0.95, 0.82, 0.5, 0.35))


# ---------------------------------------------------------------- 韧性（内侧底部细弧）
func _draw_poise(ci: RID, c: Vector2, r: float, s: float, cb: Combatant) -> void:
	var pr := clampf(cb.poise / maxf(cb.stat("poise"), 1.0), 0.0, 1.0)
	if pr >= 0.999:
		return
	var rp := r - (CombatHUD.BAND_W * 0.5 + 7.0) * s
	var a0 := deg_to_rad(62.0)
	var a1 := deg_to_rad(118.0)
	InkArt.arc_band(ci, c, rp - 1.2 * s, rp + 1.2 * s, a0, a1, Color(0, 0, 0, 0.35), 20)
	var mid := (a0 + a1) * 0.5
	var half := (a1 - a0) * 0.5 * pr
	var col := Color(0.98, 0.8, 0.45, 0.9) if pr > 0.3 else Color(1.0, 0.45, 0.3, 0.6 + 0.4 * sin(hud.t * 14.0))
	InkArt.arc_band(ci, c, rp - 1.0 * s, rp + 1.0 * s, mid - half, mid + half, col, 20)


# ---------------------------------------------------------------- 数值
func _draw_values(ci: RID, fd: Font, c: Vector2, r: float, s: float, cb: Combatant) -> void:
	var rv := r + 34.0 * s
	var hp_col := HP_TEXT
	if cb.hp_ratio() < 0.35:
		hp_col = HP_TEXT.lerp(Color(1.0, 0.3, 0.22), 0.5 + 0.5 * sin(hud.t * 7.0))
	var hp_p := c + Vector2(cos(deg_to_rad(114.0)), sin(deg_to_rad(114.0))) * rv
	InkArt.text(ci, fd, hp_p + Vector2(0, 8.0 * s), str(int(ceil(cb.hp))), int(28 * s), hp_col, 2, OUTLINE, int(5 * s))
	var burn := cb.has_status("qi_burnout")
	var qcol := QI_TEXT if not burn else Color(1.0, 0.42, 0.36, 0.6 + 0.4 * sin(hud.t * 18.0))
	var qi_p := c + Vector2(cos(deg_to_rad(66.0)), sin(deg_to_rad(66.0))) * rv
	InkArt.text(ci, fd, qi_p + Vector2(0, 8.0 * s), str(int(cb.qi)), int(28 * s), qcol, 0, OUTLINE, int(5 * s))
	# 小字标签
	var fb := UITheme.font_title()
	InkArt.text(ci, fb, hp_p + Vector2(0, 26.0 * s), "气血", int(13 * s), Color(1.0, 0.8, 0.72, 0.75), 2, OUTLINE, int(3 * s))
	InkArt.text(ci, fb, qi_p + Vector2(0, 26.0 * s), "灵力", int(13 * s), Color(0.8, 0.93, 1.0, 0.75), 0, OUTLINE, int(3 * s))
	if cb.shield > 0.5:
		var top := c + Vector2(0, -r - 44.0 * s)
		InkArt.text(ci, fd, top, str(int(cb.shield)), int(20 * s), GOLD_LIT, 1, OUTLINE, int(4 * s))


# ---------------------------------------------------------------- 速度 / 高度 / 推进 / 御空
func _draw_motion(ci: RID, fd: Font, c: Vector2, r: float, s: float, a: HumanoidActor) -> void:
	var fb := UITheme.font_title()
	var col := Color(0.97, 0.94, 0.86, 0.78)
	# 速度 / 高度：左右两侧竖排（AC 式左右刻度的位置）
	var rv := r + 62.0 * s
	var lp := c + Vector2(cos(deg_to_rad(198.0)), sin(deg_to_rad(198.0))) * rv
	var rp := c + Vector2(cos(deg_to_rad(-18.0)), sin(deg_to_rad(-18.0))) * rv
	_vlabel(ci, fd, fb, lp + Vector2(0, -22.0 * s), "速", "%.0f" % a.velocity.length(), s, col)
	_vlabel(ci, fd, fb, rp + Vector2(0, -22.0 * s), "高", "%.0f" % a.global_position.y, s, col)
	if a.boosting or a.qb_timer > 0.0:
		for side: float in [-1.0, 1.0]:
			for i in 3:
				var ph := fposmod(hud.t * 2.6 + i * 0.33, 1.0)
				var y := c.y + (float(i) - 1.0) * 16.0 * s
				var x0 := c.x + side * (r + (30.0 + ph * 40.0) * s)
				var x1 := x0 + side * (46.0 - i * 8.0) * s
				InkArt.brush(ci, Vector2(x0, y), Vector2(x1, y), (6.0 - i) * s, Color(0.85, 0.95, 1.0, 0.55 * (1.0 - ph)), "brush_thin")
	if a.hovering:
		var hp := c + Vector2(0, -r - 72.0 * s)
		var w := InkArt.text(ci, fd, hp, "御空", int(24 * s), GOLD_LIT, 1, OUTLINE, int(4 * s))
		var bw := 44.0 * s
		InkArt.cloud_band(ci, Rect2(Vector2(hp.x - w * 0.5 - bw - 4.0 * s, hp.y - 18.0 * s), Vector2(bw, bw * 0.25)), Color(1.0, 0.86, 0.5, 0.8), false)
		InkArt.cloud_band(ci, Rect2(Vector2(hp.x + w * 0.5 + 4.0 * s, hp.y - 18.0 * s), Vector2(bw, bw * 0.25)), Color(1.0, 0.86, 0.5, 0.8), true)


## 竖排小标签：书法单字 + 下方数字
func _vlabel(ci: RID, fd: Font, fb: Font, top: Vector2, glyph: String, value: String, s: float, col: Color) -> void:
	InkArt.vtext(ci, fd, top, glyph, int(17 * s), col, 0.0, OUTLINE, int(3 * s))
	InkArt.text(ci, fb, top + Vector2(0, 34.0 * s), value, int(13 * s), col, 1, OUTLINE, int(3 * s))


# ---------------------------------------------------------------- 状态印章
func _draw_statuses(ci: RID, fd: Font, p: Vector2, s: float, cb: Combatant) -> void:
	var st := cb.statuses
	var ids: Array = []
	for id in st.keys():
		if id != "qi_burnout":
			ids.append(id)
	var burn := cb.has_status("qi_burnout")
	if burn:
		var bp := p + Vector2(0, (54.0 if not ids.is_empty() else 14.0) * s)
		InkArt.brush(ci, bp + Vector2(-86.0 * s, -8.0 * s), bp + Vector2(86.0 * s, -8.0 * s), 34.0 * s, Color(0.04, 0.04, 0.07, 0.7))
		InkArt.text(ci, fd, bp, "灵力枯竭", int(24 * s), Color(1.0, 0.42, 0.36, 0.75 + 0.25 * sin(hud.t * 12.0)), 1, OUTLINE, int(4 * s))
	if ids.is_empty():
		return
	draw_status_row(ci, fd, p, 30.0 * s, 7.0 * s, st, ids, s)


## 状态印章一行（锁定悬牌下也用）：buff 青玉、debuff 朱砂、控制 靛墨；下方刻度为剩余时长
static func draw_status_row(ci: RID, fd: Font, p: Vector2, size: float, gap: float, st: Dictionary, ids: Array, s: float) -> void:
	var total := ids.size() * size + (ids.size() - 1) * gap
	var x := p.x - total * 0.5 + size * 0.5
	for id in ids:
		var def := DB.status(id)
		var ty := str(def.get("type", "debuff"))
		var body := Color(0.72, 0.13, 0.08)
		if ty == "buff":
			body = Color(0.16, 0.5, 0.4)
		elif ty == "control" or ty == "gauge":
			body = Color(0.22, 0.24, 0.45)
		var ang := (float(absi(hash(str(id))) % 7) - 3.0) * 0.035
		InkArt.seal(ci, Vector2(x, p.y), size, status_glyph(str(id)), body, Color(0.98, 0.95, 0.88), false, ang, fd)
		var e: Dictionary = st[id]
		var stacks := float(e.get("stacks", 1.0))
		if stacks > 1.0 and ty != "gauge":
			InkArt.text(ci, fd, Vector2(x + size * 0.56, p.y + size * 0.52), str(int(stacks)), int(size * 0.55), Color(1, 0.96, 0.85), 2, OUTLINE, maxi(int(3 * s), 2))
		elif ty == "gauge":
			InkArt.text(ci, fd, Vector2(x + size * 0.6, p.y + size * 0.52), str(int(stacks)), int(size * 0.45), Color(0.8, 0.9, 1.0), 2, OUTLINE, maxi(int(3 * s), 2))
		# 时长刻度（5 格）
		var dur := float(def.get("duration", 1.0))
		if dur < 999.0:
			var rem := clampf(float(e.get("time", 0.0)) / maxf(dur, 0.1), 0.0, 1.0)
			var n_on := int(ceil(rem * 5.0 - 0.001))
			var tw := size * 0.14
			var tx := x - size * 0.5 + size * 0.07
			for i in 5:
				var tc := Color(1.0, 0.92, 0.75, 0.9) if i < n_on else Color(0, 0, 0, 0.35)
				RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(tx + i * size * 0.18, p.y + size * 0.62), Vector2(tw, 2.2 * s)), tc)
		x += size + gap


## 状态印字：取最能区分的一字（“中毒”取“毒”而非“中”）
const STATUS_GLYPHS := {
	"bleed": "血", "poison": "毒", "bind": "缚", "burn": "灼", "stagger": "震", "rooted": "定", "slow": "滞",
	"armor_break": "破", "shock": "雷", "weaken": "虚", "regen": "春", "stone_skin": "石", "swift": "疾",
	"fury": "狂", "keen": "锐", "qi_surge": "涌", "focus": "凝", "frenzy": "兽", "qi_burnout": "竭", "injured": "伤",
}


static func status_glyph(id: String) -> String:
	if STATUS_GLYPHS.has(id):
		return STATUS_GLYPHS[id]
	return str(DB.status(id).get("name", id)).substr(0, 1)


# ---------------------------------------------------------------- 蓄力 / 搜索
func _draw_progress(ci: RID, fd: Font, c: Vector2, s: float, a: HumanoidActor) -> void:
	if a.charging:
		var ch := clampf(a.charge_ratio(), 0.0, 1.0)
		InkArt.arc_band(ci, c, 42.0 * s, 45.0 * s, 0.0, TAU, Color(0, 0, 0, 0.3), 48)
		if ch > 0.01:
			InkArt.brush_arc(ci, c, 43.5 * s, -PI * 0.5, -PI * 0.5 + TAU * ch, 9.0 * s, Color(0.55, 0.88, 1.0, 0.95), "brush_thin", 0.0, 1.0, 40)
	if hud.search_p >= 0.0:
		var sp := clampf(hud.search_p, 0.0, 1.0)
		InkArt.arc_band(ci, c, 52.0 * s, 58.0 * s, 0.0, TAU, Color(0, 0, 0, 0.35), 48)
		if sp > 0.01:
			InkArt.brush_arc(ci, c, 55.0 * s, -PI * 0.5, -PI * 0.5 + TAU * sp, 12.0 * s, Color(1.0, 0.84, 0.46, 0.95), "brush_stroke", 0.0, 0.8, 48)
		InkArt.text(ci, fd, c + Vector2(0, 92.0 * s), "搜 寻 中", int(22 * s), Color(1.0, 0.88, 0.6), 1, OUTLINE, int(4 * s))


# ---------------------------------------------------------------- 受击方向
func _draw_dmg_dirs(ci: RID, c: Vector2, r: float, s: float) -> void:
	for d in hud.dmg_dirs:
		var a := float(d["angle"]) - PI * 0.5
		var al := clampf(float(d["t"]), 0.0, 1.0)
		var col := Color(0.8, 0.08, 0.05, al * 0.9)
		var rr := r + 52.0 * s
		InkArt.brush_arc(ci, c, rr, a, a + 0.34, 16.0 * s, col, "brush_stroke", 0.05, 1.0, 12)
		InkArt.brush_arc(ci, c, rr, a, a - 0.34, 16.0 * s, col, "brush_stroke", 0.05, 1.0, 12)


# ---------------------------------------------------------------- 准星与命中
func _draw_crosshair(ci: RID, cx: Vector2, s: float) -> void:
	var ink := Color(0.03, 0.02, 0.02, 0.55)
	var col := Color(0.98, 0.95, 0.88, 0.85)
	RenderingServer.canvas_item_add_circle(ci, cx, 2.8 * s, ink)
	RenderingServer.canvas_item_add_circle(ci, cx, 1.7 * s, col)
	for i in 4:
		var ang := i * PI * 0.5
		var d := Vector2(cos(ang), sin(ang))
		RenderingServer.canvas_item_add_line(ci, cx + d * 8.0 * s, cx + d * 15.0 * s, ink, 3.2 * s, true)
		RenderingServer.canvas_item_add_line(ci, cx + d * 8.5 * s, cx + d * 14.5 * s, col, 1.6 * s, true)


func _draw_hits(ci: RID, fd: Font, cx: Vector2, s: float) -> void:
	if hud.hit_t > 0.0 or hud.kill_t > 0.6:
		var f := clampf(hud.hit_t / 0.2, 0.0, 1.0)
		var col := Color(0.98, 0.96, 0.9, 0.95)
		if hud.hit_crit:
			col = Color(1.0, 0.8, 0.3, 0.98)
		if hud.kill_t > 0.0:
			col = Color(0.95, 0.2, 0.12, 1.0)
			f = maxf(f, 1.0)
		var sc := 1.0 + f * 0.35
		for i in 4:
			var ang := PI * 0.25 + i * PI * 0.5
			var d := Vector2(cos(ang), sin(ang))
			var outer := cx + d * 30.0 * s * sc
			var inner := cx + d * 12.0 * s * sc
			InkArt.brush(ci, outer, inner, 7.5 * s, Color(0.02, 0.01, 0.01, col.a * 0.6), "brush_thin")
			InkArt.brush(ci, outer, inner, 5.5 * s, col, "brush_thin")
	if hud.kill_t > 0.0:
		var k := hud.kill_t
		var pop := clampf((k - 0.7) / 0.2, 0.0, 1.0)
		var al := clampf(k / 0.35, 0.0, 1.0)
		var size := 52.0 * s * (1.0 + pop * 0.8)
		var p := cx + Vector2(46.0, -40.0) * s
		InkArt.seal(ci, p, size, "斩", Color(0.8, 0.1, 0.06, 0.95 * al), Color(1.0, 0.96, 0.88, al), false, -0.14, fd)
