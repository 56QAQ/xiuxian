class_name CultivationPanel
extends UIWindow
## 修炼面板：境界与修为进度、修炼速率、闭关（1日/7日/1月/1年）、突破（可选服用破境丹）、服丹/炼化投放槽。
## args: {"location": "home" | "sect" | "vein" | "wild" | "realm"}（默认 GS.location）

const LOCATION_NAMES := {"wild": "野外", "home": "洞府", "sect": "宗门闭关室", "vein": "灵脉", "realm": "秘境"}
const SECLUSION := [["闭关一日", 24.0], ["闭关七日", 168.0], ["闭关一月", 720.0], ["闭关一年", 8640.0]]
const LOG_MAX := 30

var _location: String = "wild"
var _realm_title: Label
var _realm_desc: Label
var _stages: StageDots
var _bar: ProgressBar
var _bar_text: Label
var _rate: VBoxContainer
var _life: Label
var _seclude_btns: Array[Button] = []
var _bt_box: VBoxContainer
var _pill_pick: OptionButton
var _chance: Label
var _bt_button: Button
var _log: RichTextLabel
var _log_lines: PackedStringArray = []
var _busy: bool = false
var _pill_choices: Array = []


func _init() -> void:
	super()
	window_title = "修炼"


func _build() -> void:
	_location = str(args.get("location", GS.location))
	custom_minimum_size = Vector2(980, 0)
	# 境界头
	var head := UITheme.vbox(4)
	_realm_title = UITheme.title("", 36)
	_realm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_realm_title)
	_stages = StageDots.new()
	_stages.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	head.add_child(_stages)
	_realm_desc = UITheme.label("", 15, UITheme.TEXT_DIM)
	_realm_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_realm_desc)
	var bar_box := Control.new()
	bar_box.custom_minimum_size = Vector2(0, 26)
	_bar = UITheme.progress(0, 1, "ExpBar", 26)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_box.add_child(_bar)
	_bar_text = UITheme.label("", 16, UITheme.TEXT)
	_bar_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_text.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.02, 0.85))
	_bar_text.add_theme_constant_override("outline_size", 3)
	bar_box.add_child(_bar_text)
	head.add_child(bar_box)
	add(head)
	var row := UITheme.hbox(18)
	add(row)
	# 左：修炼与闭关
	var left := UITheme.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(UITheme.header("吐纳"))
	var info := PanelContainer.new()
	info.theme_type_variation = "InsetPanel"
	_rate = UITheme.vbox(3)
	info.add_child(_rate)
	left.add_child(info)
	_life = UITheme.label("", 16, UITheme.WARN)
	left.add_child(_life)
	left.add_child(UITheme.header("闭关"))
	var sg := GridContainer.new()
	sg.columns = 2
	sg.add_theme_constant_override("h_separation", 10)
	sg.add_theme_constant_override("v_separation", 10)
	for s in SECLUSION:
		var b := UITheme.button(str(s[0]), "JadeButton", _on_seclude.bind(float(s[1]), str(s[0])))
		b.custom_minimum_size = Vector2(200, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sg.add_child(b)
		_seclude_btns.append(b)
	left.add_child(sg)
	left.add_child(UITheme.header("心得"))
	var lp := PanelContainer.new()
	lp.theme_type_variation = "InsetPanel"
	_log = UITheme.rich("", false)
	_log.custom_minimum_size = Vector2(420, 128)
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 15)
	lp.add_child(_log)
	left.add_child(lp)
	row.add_child(left)
	# 右：突破 / 服丹 / 炼化
	var right := UITheme.vbox(10)
	right.custom_minimum_size.x = 420
	right.add_child(UITheme.header("破境"))
	var bp := PanelContainer.new()
	bp.theme_type_variation = "CardPanel"
	_bt_box = UITheme.vbox(8)
	bp.add_child(_bt_box)
	right.add_child(bp)
	right.add_child(UITheme.header("服丹 · 炼化"))
	var slots := UITheme.hbox(12)
	var pill := ItemDropSlot.new()
	pill.title = "服丹"
	pill.glyph = "丹"
	pill.hint = "拖入丹药 · 或单击选择"
	pill.accept = func(it: ItemInstance) -> bool: return ItemActions.use_kind(it) == "field"
	pill.on_item = _on_pill
	pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots.add_child(pill)
	var ref := ItemDropSlot.new()
	ref.title = "炼化"
	ref.glyph = "炉"
	ref.hint = "拖入灵物 · 或单击选择"
	ref.accent = UITheme.CINNABAR
	ref.accept = func(it: ItemInstance) -> bool: return ItemActions.can_refine(it)
	ref.on_item = _on_refine
	ref.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots.add_child(ref)
	right.add_child(slots)
	var open_bag := UITheme.button("打开储物袋", "", func() -> void:
		var w := ui().open("inventory", {"offset": Vector2(0, 0)})
		if w != null:
			w.position.x = maxf(position.x - w.size.x - 12.0, 8.0))
	open_bag.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(open_bag)
	row.add_child(right)
	_add_log(UITheme.bb("静坐调息，灵气如丝……", UITheme.TEXT_DIM))


func refresh() -> void:
	if _busy or _realm_title == null:
		return
	var p := GS.player
	var st := GS.stats
	var r := DB.realm(p.realm)
	_realm_title.text = DB.realm_name(p.realm, p.stage)
	_realm_desc.text = str(r.get("desc", ""))
	_stages.count = (r.get("stages", []) as Array).size()
	_stages.current = p.stage
	_stages.queue_redraw()
	var need := Cultivation.exp_needed(p)
	_bar.max_value = maxf(need, 1.0)
	_bar.value = minf(p.cult_exp, need)
	var bottleneck := Cultivation.at_bottleneck(p)
	_bar_text.text = "修为 %s / %s%s" % [UITheme.num(p.cult_exp), UITheme.num(need), "  · 瓶颈" if bottleneck else ""]
	# 速率
	UIWindow.clear_children(_rate)
	var rate := Cultivation.rate_per_hour(p, st, _location)
	var lm := float(Cultivation.LOCATION_MULT.get(_location, 1.0))
	_rate.add_child(UITheme.kv_row("修炼之地", "%s（×%.1f）" % [LOCATION_NAMES.get(_location, _location), lm], UITheme.TEXT))
	var main_name := str(DB.technique(p.main_technique).get("name", "无（吐纳减半）")) if p.main_technique != "" else "无（吐纳减半）"
	_rate.add_child(UITheme.kv_row("主修功法", main_name, UITheme.TEXT if p.main_technique != "" else UITheme.WARN))
	_rate.add_child(UITheme.kv_row("修炼速度", "×%.2f" % float(st.get("cult_speed", 1.0)), UITheme.TEXT))
	_rate.add_child(UITheme.kv_row("每时辰修为", "%s" % UITheme.num(rate * 2.0), UITheme.GOLD_BRIGHT))
	if not bottleneck and need < INF:
		var left := need - p.cult_exp
		_rate.add_child(UITheme.kv_row("距下一层", "约 %s" % UITheme.hours_text(left / maxf(rate, 0.001)), UITheme.TEXT_DIM))
	for i in _seclude_btns.size():
		var hrs: float = SECLUSION[i][1]
		_seclude_btns[i].tooltip_text = "预计修为 +%s（%s）" % [UITheme.num(rate * hrs), UITheme.hours_text(hrs)]
	# 寿元
	var life := Cultivation.lifespan_years(p)
	var remain := life - p.age_years()
	_life.text = "寿元 %d / %d 载%s" % [p.age_years(), life, "  —— 大限将至，速求破境！" if remain < 15 else ""]
	_life.add_theme_color_override("font_color", UITheme.BAD if remain < 15 else UITheme.TEXT_DIM)
	_refresh_breakthrough()


func _refresh_breakthrough() -> void:
	var p := GS.player
	UIWindow.clear_children(_bt_box)
	_pill_pick = null
	_bt_button = null
	var next := DB.realm(p.realm + 1)
	if Cultivation.is_peak_realm(p):
		_bt_box.add_child(UITheme.wrap_label("你已臻至此界巅峰，前路唯有飞升。", 17, UITheme.GOLD_BRIGHT))
		return
	var next_name := str(next.get("name", ""))
	var title := UITheme.label("下一境界：" + next_name, 20, UITheme.GOLD_BRIGHT)
	_bt_box.add_child(title)
	for k in next.get("perk_text", {}):
		_bt_box.add_child(UITheme.wrap_label(str(next["perk_text"][k]), 15, UITheme.TEXT_DIM))
	_bt_box.add_child(UITheme.kv_row("寿元", "%d → %d 载" % [Cultivation.lifespan_years(p), int(next.get("lifespan", 0))], UITheme.TEXT))
	if not Cultivation.at_bottleneck(p):
		var stages: Array = DB.realm(p.realm).get("stages", [])
		_bt_box.add_child(UITheme.wrap_label("须修至%s%s圆满，方可冲击%s。" % [DB.realm(p.realm).get("name", ""), stages.back() if not stages.is_empty() else "", next_name], 16, UITheme.TEXT_DIM))
		return
	_bt_box.add_child(UITheme.label("修为圆满，瓶颈已至！", 18, UITheme.WARN))
	# 破境丹
	_pill_choices = [[null, null, 0.0]]
	_pill_pick = OptionButton.new()
	_pill_pick.add_item("不服丹药", 0)
	for g in [p.bag, p.secure]:
		var grid: InventoryGrid = g
		for e in grid.entries:
			var it: ItemInstance = e["item"]
			var use: Dictionary = it.def().get("use", {})
			if str(use.get("effect", "")) == "breakthrough" and int(use.get("realm", -1)) == p.realm:
				_pill_choices.append([grid, e, float(use.get("bonus", 0.0))])
				_pill_pick.add_item("%s（成功率 +%d%%）×%d" % [it.display_name(), int(float(use.get("bonus", 0.0)) * 100.0), it.count], _pill_choices.size() - 1)
	if _pill_choices.size() > 1:
		_pill_pick.select(1)
	_pill_pick.item_selected.connect(func(_i: int) -> void: _update_chance())
	var pr := UITheme.hbox(8)
	pr.add_child(UITheme.label("辅助丹药", 16, UITheme.TEXT_DIM))
	_pill_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pr.add_child(_pill_pick)
	_bt_box.add_child(pr)
	var rec := str(DB.realm(p.realm).get("breakthrough", {}).get("pill", ""))
	if _pill_choices.size() <= 1 and rec != "":
		_bt_box.add_child(UITheme.wrap_label("推荐丹药：%s（储物袋中没有）" % DB.item(rec).get("name", rec), 14, UITheme.TEXT_FAINT))
	_chance = UITheme.label("", 20, UITheme.TEXT)
	_bt_box.add_child(_chance)
	_bt_button = UITheme.button("冲击%s" % next_name, "PrimaryButton", _on_breakthrough)
	_bt_button.custom_minimum_size.y = 50
	_bt_box.add_child(_bt_button)
	_update_chance()


func _bonus() -> float:
	if _pill_pick == null:
		return 0.0
	var idx := _pill_pick.get_selected_id()
	if idx <= 0 or idx >= _pill_choices.size():
		return 0.0
	return float(_pill_choices[idx][2])


func _update_chance() -> void:
	if _chance == null:
		return
	var c := Cultivation.breakthrough_chance(GS.player, GS.stats, _bonus())
	_chance.text = "成功率 %d%%" % int(round(c * 100.0))
	_chance.add_theme_color_override("font_color", UITheme.GOOD if c >= 0.6 else (UITheme.WARN if c >= 0.35 else UITheme.BAD))


# ================================================================ 操作

func _add_log(bbcode: String) -> void:
	_log_lines.append("[color=#8a8070]%s[/color]  %s" % [GS.date_text().substr(2), bbcode] if GS.active else bbcode)
	while _log_lines.size() > LOG_MAX:
		_log_lines.remove_at(0)
	if _log != null:
		_log.text = "\n".join(_log_lines)


func _on_seclude(hours: float, label: String) -> void:
	var p := GS.player
	var life := Cultivation.lifespan_years(p)
	var years := hours / (GS.HOURS_PER_DAY * GS.DAYS_PER_MONTH * GS.MONTHS_PER_YEAR)
	if float(p.age_years()) + years >= float(life) - 1.0:
		ui().confirm("寿元将尽，此番闭关恐有坐化之危。仍要闭关吗？", func() -> void: _do_seclude(hours, label), "大限将至", "闭关")
		return
	if Cultivation.at_bottleneck(p):
		ui().confirm("修为已至瓶颈，闭关无法再增修为（可调养伤势、消解丹毒）。仍要闭关吗？", func() -> void: _do_seclude(hours, label), "瓶颈", "闭关")
		return
	_do_seclude(hours, label)


func _do_seclude(hours: float, label: String) -> void:
	var p := GS.player
	_busy = true
	var chunk := 24.0 if hours <= 24.0 * 30.0 else 24.0 * 30.0
	var remain := hours
	var spent := 0.0
	var gained := 0.0
	var before := DB.realm_name(p.realm, p.stage)
	var events: PackedStringArray = []
	var life := Cultivation.lifespan_years(p)
	var main := p.main_technique
	while remain > 0.0:
		var h := minf(chunk, remain)
		var rate := Cultivation.rate_per_hour(p, GS.stats, _location)
		var gain := rate * h
		# 顿悟 / 心魔
		var roll := GS.rng.randf()
		var days := h / 24.0
		if roll < 0.012 * days:
			gain *= 1.6
			events.append(UITheme.bb("灵光乍现，顿悟！", UITheme.GOLD_BRIGHT))
		elif roll < 0.012 * days + (0.004 + p.pill_toxicity * 0.0002) * days:
			p.injury_days = maxf(p.injury_days, 10.0)
			gain *= 0.5
			events.append(UITheme.bb("心魔侵扰，气血翻涌，受了内伤。", UITheme.BAD))
		if not Cultivation.at_bottleneck(p):
			var exp_before := _total_exp(p)
			Cultivation.add_exp(p, gain, "seclusion")
			gained += _total_exp(p) - exp_before
		if main != "":
			GS.add_technique_xp(main, h)
		GS.advance_time(h)
		remain -= h
		spent += h
		if p.age_years() >= life:
			events.append(UITheme.bb("寿元耗尽……", UITheme.BAD))
			break
		if Cultivation.at_bottleneck(p) and hours > 24.0:
			events.append(UITheme.bb("修为圆满，提前出关。", UITheme.JADE))
			break
	_busy = false
	var after := DB.realm_name(p.realm, p.stage)
	var line := "%s（实历%s）：修为 +%s" % [label, UITheme.hours_text(spent), UITheme.num(gained)]
	if after != before:
		line += "，" + UITheme.bb("精进至 " + after, UITheme.GOLD_BRIGHT)
	_add_log(line)
	for e in events:
		_add_log(e)
	Audio.play("meditate_end")
	GS.recompute()
	refresh()


## 以“累计修为”衡量增量（跨小境界）
static func _total_exp(p: PlayerData) -> float:
	var r := DB.realm(p.realm)
	var arr: Array = r.get("exp", [])
	var t := 0.0
	for i in mini(p.stage, arr.size()):
		t += float(arr[i])
	return t + p.cult_exp + p.realm * 1e9


func _on_breakthrough() -> void:
	var p := GS.player
	var bonus := _bonus()
	var c := Cultivation.breakthrough_chance(p, GS.stats, bonus)
	var pick: Array = []
	if _pill_pick != null and _pill_pick.get_selected_id() > 0:
		pick = _pill_choices[_pill_pick.get_selected_id()]
	var pill_txt := ""
	if not pick.is_empty():
		pill_txt = "服下%s，" % (pick[1]["item"] as ItemInstance).display_name()
	var go := func() -> void:
		if not pick.is_empty():
			ItemActions.consume(pick[0], pick[1], 1)
		var res := Cultivation.attempt_breakthrough(p, GS.stats, bonus, GS.rng)
		GS.recompute()
		Events.inventory_changed.emit()
		_add_log(UITheme.bb(str(res["text"]), UITheme.GOLD_BRIGHT if res["ok"] else UITheme.BAD))
		Audio.play("breakthrough_ok" if res["ok"] else "breakthrough_fail")
	ui().confirm("%s冲击瓶颈，成功率 %d%%。\n失败将跌落三成修为并身受内伤。" % [pill_txt, int(round(c * 100.0))], go, "冲击瓶颈", "突破")


func _on_pill(grid: InventoryGrid, entry: Dictionary) -> void:
	var res := ItemActions.use(grid, entry)
	ItemActions.report(res)
	_add_log(UITheme.bb(str(res["text"]), UITheme.TEXT if res["ok"] else UITheme.WARN))


func _on_refine(grid: InventoryGrid, entry: Dictionary) -> void:
	var it: ItemInstance = entry["item"]
	var go := func(n: int) -> void:
		var res := ItemActions.refine(grid, entry, n)
		ItemActions.report(res)
		_add_log(UITheme.bb(str(res["text"]), UITheme.TEXT if res["ok"] else UITheme.WARN))
	if it.count > 1:
		ui().ask_number("炼化 %s" % it.display_name(), 1, it.count, it.count, go, "每炼化一枚耗时一个时辰（最多一日）。")
	else:
		go.call(1)


## 小境界刻度
class StageDots extends Control:
	var count: int = 9
	var current: int = 0

	func _init() -> void:
		custom_minimum_size = Vector2(360, 18)

	func _draw() -> void:
		if count <= 0:
			return
		var gap := size.x / count
		var y := size.y * 0.5
		draw_line(Vector2(gap * 0.5, y), Vector2(size.x - gap * 0.5, y), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.3), 1.0)
		for i in count:
			var p := Vector2(gap * (i + 0.5), y)
			var r := 5.0 if i == current else 4.0
			var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
			if i < current:
				draw_colored_polygon(pts, UITheme.GOLD)
			elif i == current:
				draw_colored_polygon(pts, UITheme.GOLD_BRIGHT)
				draw_arc(p, r + 3.0, 0, TAU, 16, Color(UITheme.GOLD_BRIGHT.r, UITheme.GOLD_BRIGHT.g, UITheme.GOLD_BRIGHT.b, 0.5), 1.0)
			else:
				pts.append(pts[0])
				draw_polyline(pts, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.45), 1.0)
