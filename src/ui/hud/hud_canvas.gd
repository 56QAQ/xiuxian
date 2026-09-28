class_name HUDCanvas
extends Control
## HUD 环下层：八卦锁定环与悬牌、角落信息（名号/境界/修为/灵石、时辰）、卷轴目标、交互提示、打坐、
## 符纸法诀栏（HUDSpellBar）、罗盘雷达（HUDRadar）。

const OUTLINE := Color(0.04, 0.03, 0.02, 0.85)
const PAPER := Color(0.96, 0.93, 0.85)
const GOLD := Color(1.0, 0.85, 0.5)

var hud: CombatHUD


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _draw() -> void:
	if hud == null or not hud.has_actor():
		return
	var ci := get_canvas_item()
	var vs := get_viewport_rect().size
	var s := vs.y / 1080.0
	_draw_lock(ci, vs, s)
	HUDSpellBar.draw(ci, hud, vs, s)
	_draw_info(ci, vs, s)
	_draw_objective(ci, vs, s)
	_draw_prompt(ci, vs, s)
	_draw_meditation(ci, vs, s)
	if hud.cam != null:
		HUDRadar.draw(ci, hud, vs, s)


# ================================================================ 锁定：八卦环 + 悬牌
func _draw_lock(ci: RID, vs: Vector2, s: float) -> void:
	var a := hud.actor
	var tgt := a.lock_target
	if tgt == null or not is_instance_valid(tgt) or hud.cam == null:
		return
	var tc := CombatUtil.combatant_of(tgt)
	if tc == null:
		return
	var camera := hud.cam.camera
	var head := tgt.global_position + Vector3.UP * 1.0
	var hostile := a.combatant.is_hostile_to(tc)
	var col := Color(0.95, 0.28, 0.18) if hostile else Color(0.6, 0.92, 0.8)
	var fd := UITheme.font_display()
	if camera.is_position_behind(head):
		var p := Vector2(vs.x * 0.5, vs.y - 150.0 * s)
		InkArt.text(ci, fd, p, "目标在身后", int(24 * s), col, 1, OUTLINE, int(4 * s))
		InkArt.brush(ci, p + Vector2(-60, 14) * s, p + Vector2(60, 14) * s, 10.0 * s, Color(col.r, col.g, col.b, 0.6), "brush_thin")
		return
	var sp := camera.unproject_position(head)
	var d := camera.global_position.distance_to(head)
	var rad := clampf(700.0 / maxf(d, 1.0), 30.0, 92.0) * s
	var rot := hud.t * 0.5
	# 八卦环：细金圈 + 旋转的八卦 + 四向墨钩
	InkArt.arc_band(ci, sp, rad * 0.98, rad * 0.98 + 1.4 * s, 0.0, TAU, Color(col.r, col.g, col.b, 0.55), 48)
	InkArt.arc_band(ci, sp, rad * 0.8, rad * 0.8 + 1.0 * s, 0.0, TAU, Color(col.r, col.g, col.b, 0.25), 48)
	var tl := clampf(rad * 0.24, 8.0 * s, 16.0 * s)
	for k in 8:
		var ang := rot + k * TAU / 8.0 - PI * 0.5
		var p2 := sp + Vector2(cos(ang), sin(ang)) * (rad + tl * 0.55)
		InkArt.trigram(ci, p2, ang, k, tl, 2.6 * s, tl * 0.3, Color(0.03, 0.02, 0.02, 0.5))
		InkArt.trigram(ci, p2, ang, k, tl * 0.9, 1.6 * s, tl * 0.3, Color(col.r, col.g, col.b, 0.9))
	for i in 4:
		var ang2 := -rot * 0.6 + i * PI * 0.5 + PI * 0.25
		var dir := Vector2(cos(ang2), sin(ang2))
		InkArt.brush(ci, sp + dir * rad * 1.5, sp + dir * rad * 1.08, 7.0 * s, Color(col.r, col.g, col.b, 0.85), "brush_thin")
	# 悬牌
	var name_fs := int(24 * s)
	var nm := tc.display_name
	var realm := DB.realm_name(tc.realm, tc.stage)
	var fb := UITheme.font_title()
	var nw := fd.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs).x
	var sub := "%s · %d丈" % [realm, int(d / 3.3)]
	var subw := fb.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s)).x
	var pw := maxf(maxf(nw, subw) + 64.0 * s, 170.0 * s)
	var ph := 62.0 * s
	var pr := Rect2(Vector2(sp.x - pw * 0.5, sp.y - rad * 1.5 - ph - 30.0 * s), Vector2(pw, ph))
	# 避让中央玉璧：与环簇重叠时悬到环的上方
	var cc := hud.cluster_center()
	var keep_r := (CombatHUD.RING_R + 96.0) * s
	var nearest := Vector2(clampf(cc.x, pr.position.x, pr.end.x), clampf(cc.y, pr.position.y, pr.end.y))
	if nearest.distance_to(cc) < keep_r:
		pr.position.y = minf(pr.position.y, cc.y - keep_r - ph)
	pr.position.y = maxf(pr.position.y, 60.0 * s)
	# 挂绳
	var hook := Vector2(pr.get_center().x, pr.position.y - 16.0 * s)
	var cord := Color(0.85, 0.7, 0.4, 0.75)
	RenderingServer.canvas_item_add_line(ci, hook, pr.position + Vector2(pw * 0.2, 0), cord, 1.3 * s, true)
	RenderingServer.canvas_item_add_line(ci, hook, pr.position + Vector2(pw * 0.8, 0), cord, 1.3 * s, true)
	RenderingServer.canvas_item_add_circle(ci, hook, 3.0 * s, Color(0.95, 0.8, 0.45))
	InkArt.plaque(ci, pr, 7.0 * s, Color(0.12, 0.08, 0.06, 0.9), Color(0.05, 0.035, 0.03, 0.9), Color(0.85, 0.68, 0.38, 0.9), 1.3 * s)
	InkArt.tile(ci, pr.grow(-2.0 * s), InkArt.tex("paper_fiber"), Color(1, 0.9, 0.7, 0.05), 0.5)
	InkArt.outline(ci, InkArt.chamfer_points(pr.grow(-3.5 * s), 5.0 * s), Color(0.85, 0.68, 0.38, 0.3), 1.0)
	# 印章 + 名字 + 境界
	var seal_sz := 30.0 * s
	var seal_c := pr.position + Vector2(10.0 * s + seal_sz * 0.5, 7.0 * s + seal_sz * 0.5)
	InkArt.seal(ci, seal_c, seal_sz, InkArt.realm_glyph(tc.realm), Color(0.74, 0.12, 0.08) if hostile else Color(0.16, 0.48, 0.38), PAPER, false, -0.06, fd)
	var name_col := Color(1.0, 0.72, 0.62) if hostile else PAPER
	var tx := seal_c.x + seal_sz * 0.5 + 8.0 * s
	InkArt.text(ci, fd, Vector2(tx, pr.position.y + 26.0 * s), nm, name_fs, name_col, 0, OUTLINE, int(3 * s))
	InkArt.text(ci, fb, Vector2(tx, pr.position.y + 42.0 * s), sub, int(13 * s), Color(0.95, 0.85, 0.65, 0.85), 0, OUTLINE, 2)
	# 生命笔触条 + 护体金线
	var bx0 := pr.position.x + 10.0 * s
	var bx1 := pr.end.x - 10.0 * s
	var by := pr.end.y - 10.0 * s
	var bw := bx1 - bx0
	InkArt.brush_part(ci, Vector2(bx0, by), Vector2(bx1, by), 9.0 * s, Color(0, 0, 0, 0.55), 0.0, 1.0, "brush_thin")
	var hr := clampf(tc.hp_ratio(), 0.0, 1.0)
	if hr > 0.0:
		InkArt.brush_part(ci, Vector2(bx0, by), Vector2(bx0 + bw * hr, by), 9.0 * s, Color(0.86, 0.16, 0.1) if hostile else Color(0.35, 0.8, 0.55), 0.0, lerpf(0.55, 1.0, hr), "brush_thin")
	var msh := tc.stat("max_shield")
	if msh > 0.5 and tc.shield > 0.5:
		var sr := clampf(tc.shield / msh, 0.0, 1.0)
		RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(bx0, by + 5.0 * s), Vector2(bw * sr, 2.0 * s)), Color(1.0, 0.85, 0.48, 0.95))
	# 目标状态印章
	var ids: Array = tc.statuses.keys()
	if not ids.is_empty():
		HUDCluster.draw_status_row(ci, fd, Vector2(pr.get_center().x, pr.end.y + 16.0 * s), 20.0 * s, 4.0 * s, tc.statuses, ids, s)


# ================================================================ 角落信息
func _draw_info(ci: RID, vs: Vector2, s: float) -> void:
	var p := GS.player
	if p == null:
		return
	var fd := UITheme.font_display()
	var fb := UITheme.font_title()
	var x := 34.0 * s
	var y := vs.y - 104.0 * s
	# 墨晕底
	InkArt.rect_tex(ci, InkArt.tex("ink_wash"), Rect2(Vector2(-60.0 * s, y - 70.0 * s), Vector2(420.0 * s, 210.0 * s)), Color(0.02, 0.02, 0.03, 0.45))
	# 境界印 + 名号
	var seal_sz := 40.0 * s
	InkArt.seal(ci, Vector2(x + seal_sz * 0.5, y - 12.0 * s), seal_sz, InkArt.realm_glyph(p.realm), Color(0.75, 0.13, 0.08), PAPER, false, -0.05, fd)
	var nx := x + seal_sz + 12.0 * s
	InkArt.text(ci, fd, Vector2(nx, y), p.name, int(32 * s), PAPER, 0, OUTLINE, int(4 * s))
	InkArt.text(ci, fb, Vector2(nx, y + 24.0 * s), DB.realm_name(p.realm, p.stage), int(17 * s), GOLD, 0, OUTLINE, int(3 * s))
	# 修为笔触
	var need := Cultivation.exp_needed(p)
	var ratio := clampf(p.cult_exp / maxf(need, 1.0), 0.0, 1.0)
	var neck := Cultivation.at_bottleneck(p)
	var b0 := Vector2(x, y + 42.0 * s)
	var bl := 250.0 * s
	InkArt.brush_part(ci, b0, b0 + Vector2(bl, 0), 8.0 * s, Color(0, 0, 0, 0.5), 0.0, 1.0, "brush_thin")
	if ratio > 0.0:
		InkArt.brush_part(ci, b0, b0 + Vector2(bl * ratio, 0), 8.0 * s, Color(1.0, 0.5, 0.3) if neck else Color(0.98, 0.8, 0.42), 0.0, lerpf(0.5, 1.0, ratio), "brush_thin")
	if neck:
		InkArt.text(ci, fb, b0 + Vector2(bl + 8.0 * s, 5.0 * s), "瓶颈", int(13 * s), Color(1.0, 0.55, 0.4), 0, OUTLINE, 2)
	# 灵石
	var sy := y + 68.0 * s
	InkArt.diamond(ci, Vector2(x + 6.0 * s, sy - 5.0 * s), 6.0 * s, Color(0.55, 0.85, 1.0, 0.95))
	InkArt.diamond(ci, Vector2(x + 6.0 * s, sy - 5.0 * s), 2.6 * s, Color(0.95, 1.0, 1.0, 0.9))
	InkArt.text(ci, fb, Vector2(x + 18.0 * s, sy), "灵石 %s" % UITheme.num(p.spirit_stones), int(15 * s), Color(0.72, 0.9, 1.0), 0, OUTLINE, 2)
	# 左上：时辰
	var dt := GS.date_text()
	var dw := InkArt.text(ci, fd, Vector2(34.0 * s, 44.0 * s), dt, int(22 * s), Color(0.97, 0.93, 0.84, 0.92), 0, OUTLINE, int(4 * s))
	InkArt.cloud_band(ci, Rect2(Vector2(40.0 * s + dw, 26.0 * s), Vector2(64.0 * s, 16.0 * s)), Color(0.95, 0.8, 0.5, 0.7), true)


# ================================================================ 卷轴目标
func _draw_objective(ci: RID, vs: Vector2, s: float) -> void:
	if hud.objective == "":
		return
	var fb := UITheme.font_title()
	var fs := int(19 * s)
	var tw := fb.get_string_size(hud.objective, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := tw + 70.0 * s
	var h := 38.0 * s
	var r := Rect2(Vector2((vs.x - w) * 0.5, 16.0 * s), Vector2(w, h))
	draw_scroll(ci, r, s)
	InkArt.text(ci, fb, Vector2(vs.x * 0.5, r.position.y + h * 0.5 + fs * 0.36), hud.objective, fs, Color(0.2, 0.12, 0.07), 1, Color(0, 0, 0, 0), 0)


## 横卷轴：宣纸卷面 + 两端木轴金帽
static func draw_scroll(ci: RID, r: Rect2, s: float) -> void:
	var paper_top := Color(0.95, 0.9, 0.77, 0.95)
	var paper_bot := Color(0.86, 0.78, 0.6, 0.95)
	RenderingServer.canvas_item_add_rect(ci, Rect2(r.position + Vector2(0, 3.0 * s), r.size), Color(0, 0, 0, 0.25))
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([paper_top, paper_top, paper_bot, paper_bot]))
	InkArt.tile(ci, r, InkArt.tex("paper_fiber"), Color(0.45, 0.32, 0.18, 0.18), 0.5)
	InkArt.tile(ci, r, InkArt.tex("paper_mottle"), Color(0.55, 0.4, 0.2, 0.1), 0.6)
	# 上下细边（装裱）
	var edge := Color(0.55, 0.16, 0.1, 0.8)
	RenderingServer.canvas_item_add_rect(ci, Rect2(r.position + Vector2(0, 3.0 * s), Vector2(r.size.x, 1.2 * s)), edge)
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(r.position.x, r.end.y - 4.2 * s), Vector2(r.size.x, 1.2 * s)), edge)
	# 木轴
	for side: float in [0.0, 1.0]:
		var x := r.position.x + side * r.size.x
		var rw := 9.0 * s
		var rr := Rect2(Vector2(x - rw * 0.5, r.position.y - 5.0 * s), Vector2(rw, r.size.y + 10.0 * s))
		var wood_a := Color(0.36, 0.2, 0.1)
		var wood_b := Color(0.14, 0.07, 0.04)
		RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]),
			PackedColorArray([wood_b, wood_a, wood_a, wood_b]))
		var cap := Color(0.95, 0.78, 0.4)
		RenderingServer.canvas_item_add_rect(ci, Rect2(rr.position - Vector2(1.5 * s, 3.0 * s), Vector2(rw + 3.0 * s, 4.0 * s)), cap)
		RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2(rr.position.x - 1.5 * s, rr.end.y - 1.0 * s), Vector2(rw + 3.0 * s, 4.0 * s)), cap)


# ================================================================ 交互提示
func _draw_prompt(ci: RID, vs: Vector2, s: float) -> void:
	if hud.prompt == "":
		return
	var fb := UITheme.font_title()
	var fs := int(20 * s)
	var p := Vector2(vs.x * 0.5, vs.y - 158.0 * s)
	var w := fb.get_string_size(hud.prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var half := w * 0.5 + 46.0 * s
	InkArt.brush(ci, Vector2(p.x - half, p.y - 7.0 * s), Vector2(p.x + half, p.y - 7.0 * s), 40.0 * s, Color(0.03, 0.025, 0.02, 0.78))
	InkArt.diamond(ci, Vector2(p.x - w * 0.5 - 16.0 * s, p.y - 7.0 * s), 4.0 * s, GOLD)
	InkArt.diamond(ci, Vector2(p.x + w * 0.5 + 16.0 * s, p.y - 7.0 * s), 4.0 * s, GOLD)
	InkArt.text(ci, fb, p, hud.prompt, fs, PAPER, 1, OUTLINE, 2)


# ================================================================ 打坐
func _draw_meditation(ci: RID, vs: Vector2, s: float) -> void:
	var a := hud.actor
	if a.action != "meditate":
		return
	var p := GS.player
	var rate := Cultivation.rate_per_hour(p, GS.stats, GS.location)
	var fd := UITheme.font_display()
	var fb := UITheme.font_title()
	var c := Vector2(vs.x * 0.5, vs.y * 0.5 - 200.0 * s)
	var w := InkArt.text(ci, fd, c, "吐纳修炼", int(40 * s), GOLD, 1, OUTLINE, int(5 * s))
	var bw := 90.0 * s
	var breath := 0.6 + 0.4 * sin(hud.t * 1.6)
	InkArt.cloud_band(ci, Rect2(Vector2(c.x - w * 0.5 - bw - 10.0 * s, c.y - 22.0 * s), Vector2(bw, bw * 0.25)), Color(1.0, 0.86, 0.5, breath), false)
	InkArt.cloud_band(ci, Rect2(Vector2(c.x + w * 0.5 + 10.0 * s, c.y - 22.0 * s), Vector2(bw, bw * 0.25)), Color(1.0, 0.86, 0.5, breath), true)
	InkArt.text(ci, fb, c + Vector2(0, 32.0 * s), "修为 +%.1f / 时辰" % (rate * 2.0), int(18 * s), PAPER, 1, OUTLINE, 3)
