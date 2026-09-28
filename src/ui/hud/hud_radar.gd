class_name HUDRadar
extends RefCounted
## 罗盘雷达：盘面（二十四向刻度、先天八卦，乾位朝南）随镜头转动；外圈书“北东南西”；
## 天池中磁针指北；敌踪为朱砂印点，妖兽赭石墨点，中立修士为墨点，锁定目标加方印；
## 撤离阵为玉色菱形，天材地宝为紫点，未搜容器为金色小方块。

const WORLD_R := 80.0
const OUTLINE := Color(0.04, 0.03, 0.02, 0.85)


static func draw(ci: RID, hud: CombatHUD, vs: Vector2, s: float) -> void:
	var actor := hud.actor
	var rr := 100.0 * s
	var c := Vector2(vs.x - rr - 36.0 * s, rr + 34.0 * s)
	var yaw := hud.cam.yaw
	var origin := actor.global_position
	# 盘面随镜头旋转：盘面顶部（乾）指向世界南（+Z）
	var south := Vector2(0, 1).rotated(yaw)
	var face_rot := south.angle() + PI * 0.5
	var shadow := UITheme.icon("dot")
	RenderingServer.canvas_item_add_texture_rect(ci, Rect2(c - Vector2(rr, rr) * 1.25, Vector2(rr, rr) * 2.5), shadow.get_rid(), false, Color(0, 0, 0, 0.45))
	RenderingServer.canvas_item_add_set_transform(ci, Transform2D(face_rot, c))
	InkArt.rect_tex(ci, InkArt.tex("compass"), Rect2(-Vector2(rr, rr), Vector2(rr, rr) * 2.0), Color(1, 1, 1, 0.94))
	RenderingServer.canvas_item_add_set_transform(ci, Transform2D.IDENTITY)
	# 方位字（不随盘面旋转，保持正立）
	var fd := UITheme.font_display()
	var dirs := [["北", Vector2(0, -1)], ["东", Vector2(1, 0)], ["南", Vector2(0, 1)], ["西", Vector2(-1, 0)]]
	for dd in dirs:
		var wv: Vector2 = dd[1]
		var sp := wv.rotated(yaw)
		var p := c + sp * (rr + 14.0 * s)
		if dd[0] == "北":
			InkArt.seal(ci, p, 22.0 * s, "北", Color(0.78, 0.12, 0.08), Color(1, 0.96, 0.88), false, 0.0, fd)
		else:
			var fs := int(18 * s)
			var gw := fd.get_string_size(str(dd[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var base := Vector2(p.x - gw * 0.5, p.y + (fd.get_ascent(fs) - fd.get_descent(fs)) * 0.5 - fs * 0.04)
			fd.draw_string_outline(ci, base, str(dd[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(int(4 * s), 2), Color(0.04, 0.03, 0.02, 0.9))
			fd.draw_string(ci, base, str(dd[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.98, 0.86, 0.55))
	var inner := rr * 0.8
	var to_screen := func(pos: Vector3, clamp_edge: bool) -> Vector2:
		var d := pos - origin
		var v := Vector2(d.x, d.z).rotated(yaw) / WORLD_R * inner
		if v.length() > inner:
			if not clamp_edge:
				return Vector2.INF
			v = v.normalized() * (inner - 3.0 * s)
		return c + v
	# 磁针（天池内，指北）
	var north := Vector2(0, -1).rotated(yaw)
	var nlen := rr * 0.2
	var side := Vector2(-north.y, north.x) * 3.0 * s
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([c + north * nlen, c + side, c - side]), PackedColorArray([Color(0.9, 0.15, 0.1)]))
	RenderingServer.canvas_item_add_polygon(ci, PackedVector2Array([c - north * nlen, c - side, c + side]), PackedColorArray([Color(0.1, 0.1, 0.12)]))
	RenderingServer.canvas_item_add_circle(ci, c, 2.2 * s, Color(0.95, 0.8, 0.45))
	var tree := hud.canvas.get_tree()
	# 撤离阵
	for n in tree.get_nodes_in_group("extraction_point"):
		var ep := n as Node3D
		var sp2: Vector2 = to_screen.call(ep.global_position, true)
		var active: bool = ep.get("active") == true
		var col := Color(0.45, 1.0, 0.78) if active else Color(0.6, 0.62, 0.62)
		if active:
			RenderingServer.canvas_item_add_texture_rect(ci, Rect2(sp2 - Vector2(12, 12) * s, Vector2(24, 24) * s), shadow.get_rid(), false, Color(0.4, 1.0, 0.75, 0.5 + 0.3 * sin(hud.t * 4.0)))
		InkArt.diamond(ci, sp2, 7.0 * s, Color(0.02, 0.05, 0.04, 0.8))
		InkArt.diamond(ci, sp2, 5.2 * s, col)
	# 天材地宝
	for n in tree.get_nodes_in_group("interactable"):
		if n is TreasureSite:
			var sp3: Vector2 = to_screen.call((n as Node3D).global_position, true)
			RenderingServer.canvas_item_add_circle(ci, sp3, 6.0 * s, Color(0.1, 0.02, 0.12, 0.8))
			RenderingServer.canvas_item_add_circle(ci, sp3, 4.5 * s, Color(0.85, 0.5, 1.0))
	# 容器
	for n in tree.get_nodes_in_group("loot_container"):
		var lc := n as LootContainer
		if lc == null or (lc.searched and lc.grid.entries.is_empty()):
			continue
		var sp4: Vector2 = to_screen.call(lc.global_position, false)
		if sp4 != Vector2.INF:
			var k := 3.0 * s
			RenderingServer.canvas_item_add_rect(ci, Rect2(sp4 - Vector2(k, k) - Vector2(1, 1) * s, Vector2(k, k) * 2.0 + Vector2(2, 2) * s), Color(0.05, 0.03, 0.01, 0.7))
			RenderingServer.canvas_item_add_rect(ci, Rect2(sp4 - Vector2(k, k), Vector2(k, k) * 2.0), Color(0.98, 0.8, 0.35, 0.55 if lc.searched else 0.95))
	# 修士与妖兽
	var me := actor.combatant
	for b in CombatUtil.bodies():
		var body := b as Node3D
		if body == actor or body == null:
			continue
		var bc := CombatUtil.combatant_of(body)
		if bc == null or not bc.alive:
			continue
		var sp5: Vector2 = to_screen.call(body.global_position, false)
		if sp5 == Vector2.INF:
			continue
		var locked := body == actor.lock_target
		if me.is_hostile_to(bc):
			var sz := (9.0 if not locked else 13.0) * s
			InkArt.seal(ci, sp5, sz, "", Color(0.85, 0.14, 0.08), Color.WHITE, false, 0.785)
		elif bc.faction == "beast":
			RenderingServer.canvas_item_add_circle(ci, sp5, 4.6 * s, Color(0.1, 0.05, 0.02, 0.8))
			RenderingServer.canvas_item_add_circle(ci, sp5, 3.4 * s, Color(0.85, 0.52, 0.2))
		else:
			RenderingServer.canvas_item_add_circle(ci, sp5, 4.4 * s, Color(0.95, 0.9, 0.8, 0.85))
			RenderingServer.canvas_item_add_circle(ci, sp5, 3.0 * s, Color(0.08, 0.07, 0.07))
		if locked:
			InkArt.arc_band(ci, sp5, 9.0 * s, 10.4 * s, 0.0, TAU, Color(1.0, 0.85, 0.5, 0.9), 20)
	# 自身：金色箭头（朝向）
	var fwd := actor.forward()
	var ang := atan2(fwd.x, -fwd.z) + yaw
	var tip := Vector2(sin(ang), -cos(ang))
	var sd := Vector2(-tip.y, tip.x)
	var pts := PackedVector2Array([c + tip * 11.0 * s, c - tip * 6.0 * s + sd * 6.5 * s, c - tip * 2.5 * s, c - tip * 6.0 * s - sd * 6.5 * s])
	var shadow_pts := PackedVector2Array()
	for q in pts:
		shadow_pts.append(c + (q - c) * 1.35)
	RenderingServer.canvas_item_add_polygon(ci, shadow_pts, PackedColorArray([Color(0.05, 0.03, 0.01, 0.8)]))
	RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([Color(1.0, 0.88, 0.5)]))
