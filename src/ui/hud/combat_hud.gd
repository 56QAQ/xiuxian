class_name CombatHUD
extends CanvasLayer
## AC4 式战斗 HUD：生命/灵力/护体/状态集中在屏幕中央圆环附近，并随角色运动漂移。
## 另含：锁定框与目标信息、法诀栏、命中标记、受击方向、交互提示、搜索进度、打坐信息、低血量暗角。

var actor: HumanoidActor
var cam: CameraRig
var canvas: HUDCanvas


func _ready() -> void:
	layer = 10
	canvas = HUDCanvas.new()
	canvas.hud = self
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)


func bind(a: HumanoidActor, c: CameraRig) -> void:
	actor = a
	cam = c
	canvas.actor = a
	canvas.cam = c


class HUDCanvas:
	extends Control

	const C_HP := Color(0.42, 0.92, 0.55)
	const C_HP_LOW := Color(1.0, 0.3, 0.25)
	const C_QI := Color(0.35, 0.78, 1.0)
	const C_SHIELD := Color(1.0, 0.9, 0.55)
	const C_TRACK := Color(1, 1, 1, 0.12)
	const C_TEXT := Color(0.92, 0.95, 1.0, 0.92)
	const C_GOLD := Color(0.95, 0.8, 0.4)

	var hud: CombatHUD
	var actor: HumanoidActor
	var cam: CameraRig
	var font: Font
	var font_b: Font
	var drift: Vector2 = Vector2.ZERO
	var _prev_yaw: float = 0.0
	var hit_t: float = 0.0
	var hit_crit: bool = false
	var kill_t: float = 0.0
	var dmg_dirs: Array[Dictionary] = []   ## {angle, t}
	var prompt: String = ""
	var objective: String = ""
	var search_p: float = -1.0
	var shown_hp: float = 1.0
	var shown_shield: float = 1.0
	var _t: float = 0.0
	var _vignette: TextureRect

	func _ready() -> void:
		font = load("res://assets/fonts/XianKai-Regular.ttf")
		font_b = load("res://assets/fonts/XianKai-Medium.ttf")
		Events.hit_landed.connect(_on_hit)
		Events.interaction_prompt.connect(func(t: String) -> void: prompt = t)
		Events.search_progress.connect(func(p: float) -> void: search_p = p)
		Events.hud_objective.connect(func(t: String) -> void: objective = t)
		_vignette = TextureRect.new()
		var gt := GradientTexture2D.new()
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0))
		g.set_color(1, Color(1, 1, 1, 1))
		g.add_point(0.55, Color(0, 0, 0, 0))
		gt.gradient = g
		gt.width = 256
		gt.height = 256
		_vignette.texture = gt
		_vignette.stretch_mode = TextureRect.STRETCH_SCALE
		_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
		_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vignette.modulate = Color(0.8, 0.05, 0.05, 0.0)
		add_child(_vignette)

	func _on_hit(h: Dictionary) -> void:
		if actor == null or not is_instance_valid(actor):
			return
		if h.get("source") == actor and str(h.get("kind", "")) != "dot":
			hit_t = 0.16
			hit_crit = h.get("crit", false)
			if h.get("killed", false):
				kill_t = 0.4
		if h.get("target") == actor and cam != null:
			var src: Node3D = h.get("source")
			if src != null and is_instance_valid(src):
				var to := src.global_position - actor.global_position
				var ang := atan2(to.x, to.z)
				var rel := wrapf(ang - cam.yaw + PI, -PI, PI)
				dmg_dirs.append({"angle": rel, "t": 1.0})
				if dmg_dirs.size() > 6:
					dmg_dirs.pop_front()

	func _process(delta: float) -> void:
		_t += delta
		hit_t = maxf(hit_t - delta, 0.0)
		kill_t = maxf(kill_t - delta, 0.0)
		for d in dmg_dirs:
			d["t"] = float(d["t"]) - delta
		dmg_dirs = dmg_dirs.filter(func(d: Dictionary) -> bool: return float(d["t"]) > 0.0)
		if actor != null and is_instance_valid(actor) and cam != null:
			var v := actor.velocity
			var cb := cam.camera.global_basis
			var sv := Vector2(v.dot(cb.x), -v.dot(cb.y))
			var yaw_rate := wrapf(cam.yaw - _prev_yaw, -PI, PI) / maxf(delta, 0.001)
			_prev_yaw = cam.yaw
			var k := 3.2 * Settings.hud_drift
			var want := (-sv * k + Vector2(yaw_rate * 18.0, 0.0) * Settings.hud_drift).limit_length(80.0)
			drift = drift.lerp(want, 1.0 - exp(-5.0 * delta))
			var c := actor.combatant
			shown_hp = lerpf(shown_hp, c.hp_ratio(), 1.0 - exp(-8.0 * delta))
			shown_shield = lerpf(shown_shield, c.shield / maxf(c.stat("max_shield"), 1.0), 1.0 - exp(-10.0 * delta))
			var low := clampf((0.35 - c.hp_ratio()) / 0.35, 0.0, 1.0)
			_vignette.modulate.a = low * (0.55 + 0.15 * sin(_t * 6.0))
		queue_redraw()

	func _draw() -> void:
		if actor == null or not is_instance_valid(actor):
			return
		var vs := get_viewport_rect().size
		var s := vs.y / 1080.0
		var center := vs * 0.5 + drift * s
		_draw_cluster(center, s)
		_draw_lock(s)
		_draw_spellbar(vs, s)
		_draw_info(vs, s)
		_draw_prompt(vs, s)
		_draw_radar(vs, s)

	# ------------------------------------------------------------ 中央环
	func _draw_cluster(c: Vector2, s: float) -> void:
		var cb := actor.combatant
		var r := 118.0 * s
		var w := 7.0 * s
		# 准星
		var cc := Color(1, 1, 1, 0.75)
		draw_circle(c - drift * s * 0.6, 2.0 * s, cc)
		var cx := c - drift * s * 0.6
		for i in 4:
			var a := i * PI / 2.0 + PI / 4.0
			var d := Vector2(cos(a), sin(a))
			draw_line(cx + d * 9.0 * s, cx + d * 16.0 * s, cc, 1.5 * s, true)
		draw_arc(c, 62.0 * s, 0.0, TAU, 64, Color(1, 1, 1, 0.08), 1.0 * s, true)
		# 生命（左弧，自下而上）
		var hp_col := C_HP.lerp(C_HP_LOW, clampf(1.0 - cb.hp_ratio() * 2.0, 0.0, 1.0))
		var a0 := deg_to_rad(108.0)
		var span := deg_to_rad(144.0)
		draw_arc(c, r, a0, a0 + span, 48, C_TRACK, w, true)
		draw_arc(c, r, a0, a0 + span * clampf(shown_hp, 0.0, 1.0), 48, Color(1, 1, 1, 0.5), w, true)
		draw_arc(c, r, a0, a0 + span * clampf(cb.hp_ratio(), 0.0, 1.0), 48, hp_col, w, true)
		# 灵力（右弧，自下而上）
		var q0 := deg_to_rad(72.0)
		var burn := cb.has_status("qi_burnout")
		var qcol := C_QI if not burn else Color(1.0, 0.35, 0.3, 0.6 + 0.4 * sin(_t * 18.0))
		draw_arc(c, r, q0 - span, q0, 48, C_TRACK, w, true)
		var qr := clampf(cb.qi / maxf(cb.stat("max_qi"), 1.0), 0.0, 1.0)
		draw_arc(c, r, q0 - span * qr, q0, 48, qcol, w, true)
		# 护体（外环分段）
		var sr := r + 13.0 * s
		var segs := 28
		var sh := clampf(shown_shield, 0.0, 1.0)
		for i in segs:
			var t0 := -PI / 2.0 + TAU * i / segs + 0.02
			var t1 := -PI / 2.0 + TAU * (i + 1) / segs - 0.02
			var on := float(i) / segs < sh
			draw_arc(c, sr, t0, t1, 4, C_SHIELD if on else Color(1, 1, 1, 0.07), 3.0 * s, true)
		# 韧性（内弧，底部）
		var pr := clampf(cb.poise / maxf(cb.stat("poise"), 1.0), 0.0, 1.0)
		if pr < 0.999:
			draw_arc(c, r - 12.0 * s, deg_to_rad(60.0), deg_to_rad(60.0) + deg_to_rad(60.0) * pr, 16, Color(0.95, 0.75, 0.4, 0.8), 3.0 * s, true)
		# 数值
		_text(c + Vector2(-r - 16.0 * s, r * 0.72), "%d" % int(cb.hp), 17 * s, hp_col, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(c + Vector2(r + 16.0 * s, r * 0.72), "%d" % int(cb.qi), 17 * s, qcol, HORIZONTAL_ALIGNMENT_LEFT)
		if cb.shield > 0.5:
			_text(c + Vector2(0, -sr - 10.0 * s), "%d" % int(cb.shield), 14 * s, C_SHIELD, HORIZONTAL_ALIGNMENT_CENTER)
		# 速度 / 高度
		var spd := actor.velocity.length()
		_text(c + Vector2(-r * 0.78, -r * 0.82), "速 %.1f" % spd, 13 * s, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_RIGHT)
		_text(c + Vector2(r * 0.78, -r * 0.82), "高 %.1f" % actor.global_position.y, 13 * s, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_LEFT)
		# 推进 / 御空
		if actor.boosting or actor.qb_timer > 0.0:
			var col := Color(0.8, 0.95, 1.0, 0.8)
			_text(c + Vector2(-r - 42.0 * s, 4.0 * s), "《", 22 * s, col, HORIZONTAL_ALIGNMENT_RIGHT)
			_text(c + Vector2(r + 42.0 * s, 4.0 * s), "》", 22 * s, col, HORIZONTAL_ALIGNMENT_LEFT)
		if actor.hovering:
			_text(c + Vector2(0, -r - 34.0 * s), "御 空", 15 * s, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		if burn:
			_text(c + Vector2(0, r + 50.0 * s), "灵 力 枯 竭", 16 * s, Color(1, 0.4, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
		# 蓄力
		var ch := actor.charge_ratio()
		if actor.charging:
			draw_arc(c, 40.0 * s, -PI / 2.0, -PI / 2.0 + TAU * ch, 40, C_QI.lightened(0.3), 3.0 * s, true)
		# 搜索进度
		if search_p >= 0.0:
			draw_arc(c, 50.0 * s, 0.0, TAU, 48, Color(0, 0, 0, 0.4), 6.0 * s, true)
			draw_arc(c, 50.0 * s, -PI / 2.0, -PI / 2.0 + TAU * clampf(search_p, 0.0, 1.0), 48, C_GOLD, 6.0 * s, true)
			_text(c + Vector2(0, 80.0 * s), "搜索中……", 15 * s, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		# 命中标记
		if hit_t > 0.0 or kill_t > 0.0:
			var hc := Color(1, 0.85, 0.3) if hit_crit else Color(1, 1, 1)
			if kill_t > 0.0:
				hc = Color(1, 0.3, 0.25)
			var hs := (14.0 if kill_t <= 0.0 else 20.0) * s
			for i in 4:
				var a := i * PI / 2.0 + PI / 4.0
				var d := Vector2(cos(a), sin(a))
				draw_line(cx + d * hs * 0.6, cx + d * hs * 1.4, hc, 2.5 * s, true)
		# 受击方向
		for d in dmg_dirs:
			var a := float(d["angle"]) - PI / 2.0
			draw_arc(c, r + 30.0 * s, a - 0.25, a + 0.25, 10, Color(1, 0.2, 0.15, float(d["t"]) * 0.9), 6.0 * s, true)
		# 状态
		_draw_statuses(c + Vector2(0, r + 26.0 * s), s)

	func _draw_statuses(p: Vector2, s: float) -> void:
		var st := actor.combatant.statuses
		if st.is_empty():
			return
		var ids := st.keys()
		var size := 24.0 * s
		var gap := 4.0 * s
		var total := ids.size() * size + (ids.size() - 1) * gap
		var x := p.x - total * 0.5
		for id in ids:
			var def := DB.status(id)
			var col := Color.html(str(def.get("color", "#ffffff")))
			var rect := Rect2(Vector2(x, p.y), Vector2(size, size))
			draw_rect(rect, Color(0, 0, 0, 0.55))
			draw_rect(rect, col, false, 1.5 * s)
			var nm := str(def.get("name", id))
			_text(rect.get_center() + Vector2(0, 6.0 * s), nm.substr(0, 1), 15 * s, col, HORIZONTAL_ALIGNMENT_CENTER)
			var stacks := float(st[id]["stacks"])
			if stacks > 1.0:
				_text(rect.position + Vector2(size + 1.0, size), str(int(stacks)), 11 * s, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT)
			var dur := float(def.get("duration", 1.0))
			var rem := clampf(float(st[id]["time"]) / maxf(dur, 0.1), 0.0, 1.0)
			draw_rect(Rect2(rect.position + Vector2(0, size + 2.0 * s), Vector2(size * rem, 2.0 * s)), col)
			x += size + gap

	# ------------------------------------------------------------ 锁定
	func _draw_lock(s: float) -> void:
		var t := actor.lock_target
		if t == null or not is_instance_valid(t) or cam == null:
			return
		var tc := CombatUtil.combatant_of(t)
		if tc == null:
			return
		var camera := cam.camera
		var head := t.global_position + Vector3.UP * 1.0
		var hostile := actor.combatant.is_hostile_to(tc)
		var col := Color(1, 0.35, 0.3) if hostile else Color(0.9, 0.95, 1.0)
		var vs := get_viewport_rect().size
		if camera.is_position_behind(head):
			_text(Vector2(vs.x * 0.5, vs.y - 40.0 * s), "▼ 目标在身后", 16 * s, col, HORIZONTAL_ALIGNMENT_CENTER)
			return
		var sp := camera.unproject_position(head)
		var d := camera.global_position.distance_to(head)
		var box := clampf(900.0 / maxf(d, 1.0), 26.0, 110.0) * s
		var br := Rect2(sp - Vector2(box, box * 1.3) * 0.5, Vector2(box, box * 1.3))
		var l := box * 0.28
		var pts := [br.position, Vector2(br.end.x, br.position.y), br.end, Vector2(br.position.x, br.end.y)]
		var dirs := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
		for i in 4:
			var pp: Vector2 = pts[i]
			var dd: Vector2 = dirs[i]
			draw_line(pp, pp + Vector2(dd.x * l, 0), col, 2.0 * s, true)
			draw_line(pp, pp + Vector2(0, dd.y * l), col, 2.0 * s, true)
		var name_p := Vector2(br.get_center().x, br.position.y - 30.0 * s)
		_text(name_p, tc.display_name, 17 * s, col, HORIZONTAL_ALIGNMENT_CENTER)
		_text(name_p + Vector2(0, 17.0 * s), "%s · %dm" % [DB.realm_name(tc.realm, tc.stage), int(d)], 12 * s, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
		var bw := maxf(box * 1.6, 110.0 * s)
		var bp := Vector2(br.get_center().x - bw * 0.5, br.end.y + 8.0 * s)
		draw_rect(Rect2(bp, Vector2(bw, 5.0 * s)), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(bp, Vector2(bw * tc.hp_ratio(), 5.0 * s)), C_HP.lerp(C_HP_LOW, 1.0 - tc.hp_ratio()))
		if tc.stat("max_shield") > 0.0:
			draw_rect(Rect2(bp + Vector2(0, 7.0 * s), Vector2(bw * clampf(tc.shield / tc.stat("max_shield"), 0.0, 1.0), 3.0 * s)), C_SHIELD)
		# 目标状态
		var x := bp.x
		for id in tc.statuses:
			var col2 := Color.html(str(DB.status(id).get("color", "#ffffff")))
			draw_rect(Rect2(Vector2(x, bp.y + 13.0 * s), Vector2(12.0 * s, 12.0 * s)), col2)
			x += 14.0 * s

	# ------------------------------------------------------------ 法诀栏
	func _draw_spellbar(vs: Vector2, s: float) -> void:
		var pd := actor.pd
		var n := BuildCalc.spell_slot_count(pd)
		var size := 58.0 * s
		var gap := 8.0 * s
		var total := n * size + (n - 1) * gap + size + gap * 3.0
		var x := (vs.x - total) * 0.5
		var y := vs.y - size - 26.0 * s
		for i in n:
			var id: String = pd.spell_slots[i] if i < pd.spell_slots.size() else ""
			var rect := Rect2(Vector2(x, y), Vector2(size, size))
			draw_rect(rect, Color(0.04, 0.05, 0.08, 0.7))
			if id != "":
				var def := DB.spell(id)
				var e := str(def.get("element", ""))
				var col := Elem.color_of(e) if Elem.is_valid(e) else Color(0.8, 0.9, 1.0)
				var nm := str(def.get("name", id))
				_text(rect.get_center() + Vector2(0, 2.0 * s), nm.substr(0, 2), 19 * s, col, HORIZONTAL_ALIGNMENT_CENTER)
				_text(rect.get_center() + Vector2(0, 21.0 * s), nm.substr(2, 2), 12 * s, col.darkened(0.1), HORIZONTAL_ALIGNMENT_CENTER)
				var cd := actor.spell_cooldown(id)
				var maxcd := float(def.get("cd", 1.0))
				if cd > 0.0:
					_pie(rect.get_center(), size * 0.5, cd / maxf(maxcd, 0.01), Color(0, 0, 0, 0.6))
					_text(rect.get_center() + Vector2(0, 7.0 * s), "%.1f" % cd, 18 * s, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
				var no_qi := actor.combatant.qi < float(def.get("qi", 0))
				draw_rect(rect, Color(1, 0.3, 0.3, 0.9) if no_qi else col, false, 2.0 * s)
				_text(rect.position + Vector2(size - 3.0 * s, size - 4.0 * s), str(int(def.get("qi", 0))), 11 * s, C_QI, HORIZONTAL_ALIGNMENT_RIGHT)
			else:
				draw_rect(rect, Color(1, 1, 1, 0.15), false, 1.0 * s)
			_text(rect.position + Vector2(4.0 * s, 14.0 * s), str(i + 1), 12 * s, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
			x += size + gap
		# 丹药
		x += gap * 2.0
		var qrect := Rect2(Vector2(x, y), Vector2(size, size))
		draw_rect(qrect, Color(0.04, 0.05, 0.08, 0.7))
		draw_rect(qrect, C_GOLD.darkened(0.2), false, 2.0 * s)
		var qid := GS.player.quick_item if actor.is_player else ""
		if qid != "":
			var cnt := GS.player.bag.count_of(qid)
			var nm2 := str(DB.item(qid).get("name", ""))
			_text(qrect.get_center() + Vector2(0, 6.0 * s), nm2.substr(0, 2), 17 * s, Color(0.7, 1.0, 0.7) if cnt > 0 else Color(0.5, 0.5, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
			_text(qrect.position + Vector2(size - 3.0 * s, size - 4.0 * s), "×%d" % cnt, 12 * s, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT)
		_text(qrect.position + Vector2(4.0 * s, 14.0 * s), "Q", 12 * s, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT)

	func _pie(c: Vector2, r: float, frac: float, col: Color) -> void:
		if frac <= 0.0:
			return
		var pts := PackedVector2Array([c])
		var n := 24
		for i in n + 1:
			var a := -PI / 2.0 + TAU * frac * float(i) / n
			pts.append(c + Vector2(cos(a), sin(a)) * r * 1.42)
		var clip := PackedVector2Array()
		for p in pts:
			clip.append(Vector2(clampf(p.x, c.x - r, c.x + r), clampf(p.y, c.y - r, c.y + r)))
		draw_colored_polygon(clip, col)

	# ------------------------------------------------------------ 角落信息
	func _draw_info(vs: Vector2, s: float) -> void:
		var p := GS.player
		var x := 28.0 * s
		var y := vs.y - 92.0 * s
		_text(Vector2(x, y), p.name, 22 * s, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, font_b)
		_text(Vector2(x, y + 24.0 * s), DB.realm_name(p.realm, p.stage), 16 * s, C_GOLD, HORIZONTAL_ALIGNMENT_LEFT)
		var need := Cultivation.exp_needed(p)
		var ratio := clampf(p.cult_exp / maxf(need, 1.0), 0.0, 1.0)
		var bar := Rect2(Vector2(x, y + 34.0 * s), Vector2(220.0 * s, 4.0 * s))
		draw_rect(bar, Color(1, 1, 1, 0.12))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), C_GOLD if not Cultivation.at_bottleneck(p) else Color(1, 0.5, 0.3))
		_text(Vector2(x, y + 56.0 * s), "灵石 %d" % p.spirit_stones, 14 * s, Color(0.65, 0.88, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
		# 左上：时间
		_text(Vector2(28.0 * s, 36.0 * s), GS.date_text(), 16 * s, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		if objective != "":
			var ow := font.get_string_size(objective, HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * s)).x + 40.0 * s
			var orect := Rect2(Vector2((vs.x - ow) * 0.5, 14.0 * s), Vector2(ow, 34.0 * s))
			draw_rect(orect, Color(0.03, 0.04, 0.06, 0.65))
			draw_rect(orect, C_GOLD.darkened(0.3), false, 1.0)
			_text(Vector2(vs.x * 0.5, 38.0 * s), objective, 18 * s, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
		if actor.action == "meditate":
			var rate := Cultivation.rate_per_hour(p, GS.stats, GS.location)
			_text(Vector2(vs.x * 0.5, vs.y * 0.5 - 170.0 * s), "吐纳修炼中 · 修为 +%.1f / 时辰" % (rate * 2.0), 20 * s, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER, font_b)

	func _draw_prompt(vs: Vector2, s: float) -> void:
		if prompt == "":
			return
		var p := Vector2(vs.x * 0.5, vs.y - 118.0 * s)
		var w := font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * s)).x + 28.0 * s
		draw_rect(Rect2(p - Vector2(w * 0.5, 20.0 * s), Vector2(w, 30.0 * s)), Color(0.03, 0.04, 0.06, 0.7))
		draw_rect(Rect2(p - Vector2(w * 0.5, 20.0 * s), Vector2(w, 30.0 * s)), C_GOLD.darkened(0.3), false, 1.0)
		_text(p + Vector2(0, 2.0 * s), prompt, 18 * s, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)

	# ------------------------------------------------------------ 雷达
	func _draw_radar(vs: Vector2, s: float) -> void:
		if cam == null:
			return
		var rr := 92.0 * s
		var c := Vector2(vs.x - rr - 26.0 * s, rr + 26.0 * s)
		var world_r := 80.0
		draw_circle(c, rr, Color(0.03, 0.05, 0.07, 0.55))
		draw_arc(c, rr, 0.0, TAU, 64, Color(0.95, 0.8, 0.4, 0.5), 1.5 * s, true)
		draw_arc(c, rr * 0.5, 0.0, TAU, 48, Color(1, 1, 1, 0.08), 1.0, true)
		var yaw := cam.yaw
		var origin := actor.global_position
		var to_screen := func(p: Vector3, clamp_edge: bool) -> Vector2:
			var d := p - origin
			var v := Vector2(d.x, d.z).rotated(yaw) / world_r * rr
			if v.length() > rr:
				if not clamp_edge:
					return Vector2.INF
				v = v.normalized() * (rr - 4.0 * s)
			return c + v
		# 撤离点 / 天材地宝
		for n in get_tree().get_nodes_in_group("extraction_point"):
			var ep := n as Node3D
			var sp: Vector2 = to_screen.call(ep.global_position, true)
			var active: bool = ep.get("active") == true
			var col := Color(0.4, 1.0, 0.75) if active else Color(0.6, 0.6, 0.65)
			draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -6) * s, sp + Vector2(6, 0) * s, sp + Vector2(0, 6) * s, sp + Vector2(-6, 0) * s]), col)
		for n in get_tree().get_nodes_in_group("interactable"):
			if n is TreasureSite:
				var sp2: Vector2 = to_screen.call((n as Node3D).global_position, true)
				draw_circle(sp2, 5.0 * s, Color(0.85, 0.5, 1.0))
		for n in get_tree().get_nodes_in_group("loot_container"):
			var lc := n as LootContainer
			if lc == null or (lc.searched and lc.grid.entries.is_empty()):
				continue
			var sp3: Vector2 = to_screen.call(lc.global_position, false)
			if sp3 != Vector2.INF:
				draw_rect(Rect2(sp3 - Vector2(2.5, 2.5) * s, Vector2(5, 5) * s), Color(0.95, 0.8, 0.35, 0.5 if lc.searched else 0.9))
		# 角色
		var me := actor.combatant
		for b in CombatUtil.bodies():
			var body := b as Node3D
			if body == actor or body == null:
				continue
			var bc := CombatUtil.combatant_of(body)
			if bc == null or not bc.alive:
				continue
			var sp4: Vector2 = to_screen.call(body.global_position, false)
			if sp4 == Vector2.INF:
				continue
			var col2 := Color(0.95, 0.95, 1.0)
			if me.is_hostile_to(bc):
				col2 = Color(1.0, 0.3, 0.25)
			elif bc.faction == "beast":
				col2 = Color(1.0, 0.65, 0.2)
			draw_circle(sp4, (4.0 if body != actor.lock_target else 6.0) * s, col2)
		# 玩家箭头（镜头朝上）
		var fwd := actor.forward()
		var ang := atan2(fwd.x, -fwd.z) + yaw
		var tip := Vector2(sin(ang), -cos(ang))
		var side := Vector2(-tip.y, tip.x)
		draw_colored_polygon(PackedVector2Array([c + tip * 9.0 * s, c - tip * 5.0 * s + side * 5.0 * s, c - tip * 5.0 * s - side * 5.0 * s]), Color(1, 0.9, 0.5))

	func _text(pos: Vector2, t: String, size: float, col: Color, align: HorizontalAlignment, f: Font = null) -> void:
		var fnt := f if f != null else font
		var fs := int(maxf(size, 8.0))
		var w := fnt.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := pos.x
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			x -= w * 0.5
		elif align == HORIZONTAL_ALIGNMENT_RIGHT:
			x -= w
		draw_string_outline(fnt, Vector2(x, pos.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(int(fs / 6.0), 2), Color(0, 0, 0, 0.7 * col.a))
		draw_string(fnt, Vector2(x, pos.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
