class_name CraftPanel
extends UIWindow
## 生产面板。args: {"profession": "alchemy" | "forging" | "talisman" | "formation" | "herbalism", "title"?: String}
## 左侧配方列表（按技艺筛选），右侧配方详情：材料持有/需求、等级要求、耗时、成功率、制作与结果记录。

const PROF_GLYPH := {"alchemy": "丹", "forging": "器", "talisman": "符", "formation": "阵", "herbalism": "植"}

var _prof: String = "alchemy"
var _selected: String = ""
var _head: HBoxContainer
var _list: VBoxContainer
var _detail: VBoxContainer
var _log: RichTextLabel
var _log_lines: PackedStringArray = []
var _group: ButtonGroup


func _init() -> void:
	super()


func _build() -> void:
	_prof = str(args.get("profession", "alchemy"))
	set_title(str(args.get("title", PlayerData.PROFESSION_NAMES.get(_prof, "生产"))))
	_head = UITheme.hbox(12)
	add(_head)
	var row := UITheme.hbox(18)
	add(row)
	var lp := PanelContainer.new()
	lp.theme_type_variation = "InsetPanel"
	_list = UITheme.vbox(6)
	var sc := UITheme.scroll(_list)
	sc.custom_minimum_size = Vector2(330, 520)
	lp.add_child(sc)
	row.add_child(lp)
	var right := UITheme.vbox(10)
	right.custom_minimum_size.x = 540
	var dp := PanelContainer.new()
	dp.theme_type_variation = "CardPanel"
	_detail = UITheme.vbox(8)
	dp.add_child(_detail)
	right.add_child(dp)
	right.add_child(UITheme.header("记录"))
	var logp := PanelContainer.new()
	logp.theme_type_variation = "InsetPanel"
	_log = UITheme.rich("", false)
	_log.custom_minimum_size = Vector2(520, 110)
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 15)
	logp.add_child(_log)
	right.add_child(logp)
	row.add_child(right)
	var rs := Crafting.recipes_for(_prof)
	if not rs.is_empty():
		_selected = str(rs[0]["id"])


func refresh() -> void:
	if _list == null:
		return
	var p := GS.player
	var st := GS.stats
	# 技艺信息
	UIWindow.clear_children(_head)
	var lv := p.profession_level(_prof)
	var bonus := int(st.get(_prof, 0.0))
	var glyph := UITheme.label(str(PROF_GLYPH.get(_prof, "艺")), 34, UITheme.GOLD_BRIGHT)
	glyph.add_theme_font_override("font", UITheme.font_title())
	_head.add_child(glyph)
	var hv := UITheme.vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(UITheme.label("%s · %d 级%s" % [PlayerData.PROFESSION_NAMES.get(_prof, _prof), lv, ("（天赋 +%d）" % bonus) if bonus > 0 else ""], 20, UITheme.TEXT))
	var xp := float(p.professions.get(_prof, {}).get("xp", 0.0))
	var need := Crafting.xp_needed(lv)
	var bar := UITheme.progress(xp, need, "ExpBar", 10)
	hv.add_child(bar)
	_head.add_child(hv)
	var stones := UITheme.label("灵石 %s" % UITheme.num(p.spirit_stones), 17, UITheme.GOLD_BRIGHT)
	_head.add_child(stones)
	# 配方列表
	UIWindow.clear_children(_list)
	_group = ButtonGroup.new()
	var rs := Crafting.recipes_for(_prof)
	if rs.is_empty():
		_list.add_child(UITheme.label("尚无此道配方。", 17, UITheme.TEXT_FAINT))
	for r in rs:
		_list.add_child(_recipe_button(r))
	_refresh_detail()


func _recipe_button(r: Dictionary) -> Control:
	var rid := str(r["id"])
	var b := Button.new()
	b.theme_type_variation = "ListButton"
	b.toggle_mode = true
	b.button_group = _group
	b.button_pressed = rid == _selected
	b.custom_minimum_size = Vector2(300, 60)
	b.focus_mode = Control.FOCUS_NONE
	UITheme.hook_sounds(b)
	b.pressed.connect(func() -> void:
		_selected = rid
		_refresh_detail())
	var chk := Crafting.can_craft(GS.player, GS.stats, r)
	var h := UITheme.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	var out_id := str(r["output"][0])
	var ic := ItemIcon.new()
	ic.item_id = out_id
	ic.custom_minimum_size = Vector2(44, 44)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var v := UITheme.vbox(0)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := int(DB.item(out_id).get("grade", 0))
	v.add_child(UITheme.label(str(r.get("name", rid)), 18, Grade.color_of(g).lerp(UITheme.TEXT, 0.3) if chk["ok"] else UITheme.TEXT_DIM))
	var lvl_ok := Crafting.effective_level(GS.player, GS.stats, _prof) >= int(r.get("level", 0))
	v.add_child(UITheme.label("需 %d 级 · %s" % [int(r.get("level", 0)), "可制作" if chk["ok"] else ("材料不足" if lvl_ok else "等级不足")], 13, UITheme.GOOD if chk["ok"] else (UITheme.TEXT_FAINT if lvl_ok else UITheme.BAD)))
	h.add_child(v)
	b.add_child(h)
	return b


func _refresh_detail() -> void:
	UIWindow.clear_children(_detail)
	var r: Dictionary = DB.recipes.get(_selected, {})
	if r.is_empty():
		_detail.add_child(UITheme.label("选择一个配方。", 17, UITheme.TEXT_FAINT))
		return
	var p := GS.player
	var out_id := str(r["output"][0])
	var out_n := int(r["output"][1])
	var top := UITheme.hbox(14)
	var big := ItemIcon.new()
	big.item_id = out_id
	big.custom_minimum_size = Vector2(80, 80)
	top.add_child(big)
	var tv := UITheme.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var it := ItemInstance.create(out_id, out_n)
	tv.add_child(UITheme.label("%s ×%d" % [it.display_name(), out_n], 24, it.color().lerp(UITheme.TEXT, 0.15)))
	tv.add_child(UITheme.label("%s · %s" % [Grade.name_of(it.get_grade()), ItemInstance._type_name(it.type())], 15, UITheme.TEXT_DIM))
	tv.add_child(UITheme.wrap_label(str(r.get("desc", it.def().get("desc", ""))), 15, UITheme.TEXT))
	top.add_child(tv)
	_detail.add_child(top)
	_detail.add_child(UITheme.header("材料", 18))
	for inp in r.get("inputs", []):
		var id := str(inp[0])
		var need := int(inp[1])
		var have := Crafting.have_count(p, id)
		var row := UITheme.hbox(10)
		var ic := ItemIcon.new()
		ic.item_id = id
		ic.custom_minimum_size = Vector2(36, 36)
		row.add_child(ic)
		var nl := UITheme.label(str(DB.item(id).get("name", id)), 17, UITheme.TEXT)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nl)
		row.add_child(UITheme.label("%s / %d" % [UITheme.num(have), need], 17, UITheme.GOOD if have >= need else UITheme.BAD))
		_detail.add_child(row)
	_detail.add_child(UITheme.separator(false))
	var lv_need := int(r.get("level", 0))
	var eff := Crafting.effective_level(p, GS.stats, _prof)
	_detail.add_child(UITheme.kv_row("技艺要求", "%s %d 级（当前 %d）" % [PlayerData.PROFESSION_NAMES.get(_prof, _prof), lv_need, eff], UITheme.GOOD if eff >= lv_need else UITheme.BAD))
	_detail.add_child(UITheme.kv_row("耗时", UITheme.hours_text(float(r.get("time", 1))), UITheme.TEXT))
	var c := Crafting.success_chance(p, GS.stats, r)
	_detail.add_child(UITheme.kv_row("成功率", "%d%%" % int(round(c * 100.0)), UITheme.GOOD if c >= 0.6 else (UITheme.WARN if c >= 0.35 else UITheme.BAD)))
	var chk := Crafting.can_craft(p, GS.stats, r)
	var btns := UITheme.hbox(10)
	btns.alignment = BoxContainer.ALIGNMENT_END
	if not chk["ok"]:
		var why := UITheme.label(str(chk["reason"]), 15, UITheme.WARN)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btns.add_child(why)
	var many := UITheme.button("批量", "", _craft_many)
	many.disabled = not chk["ok"]
	btns.add_child(many)
	var go := UITheme.button("开炉" if _prof == "alchemy" else "制作", "PrimaryButton", _craft.bind(1))
	go.disabled = not chk["ok"]
	go.custom_minimum_size.x = 140
	btns.add_child(go)
	_detail.add_child(btns)


func _craft(times: int) -> void:
	var ok_n := 0
	var fail_n := 0
	for i in times:
		var res := Crafting.craft(_selected)
		if not res["ok"]:
			if i == 0:
				Events.notify.emit(str(res["text"]), "warn")
			break
		if res["success"]:
			ok_n += 1
		else:
			fail_n += 1
		_log_line(UITheme.bb(str(res["text"]), UITheme.GOOD if res["success"] else UITheme.BAD))
	if times > 1 and ok_n + fail_n > 0:
		_log_line(UITheme.bb("批量完成：成功 %d，失败 %d。" % [ok_n, fail_n], UITheme.GOLD_BRIGHT))
	if ok_n > 0:
		Audio.play("craft_ok")
		Events.notify.emit("制作完成：成功 %d 次" % ok_n, "good")
	elif fail_n > 0:
		Audio.play("craft_fail")
		Events.notify.emit("制作失败", "bad")
	queue_refresh()


func _craft_many() -> void:
	var r: Dictionary = DB.recipes.get(_selected, {})
	var mx := 1
	while mx < 50 and Crafting.missing_inputs(GS.player, r, mx + 1).is_empty():
		mx += 1
	ui().ask_number("批量制作", 1, mx, mx, func(n: int) -> void: _craft(n), "材料足够制作 %d 次。每次耗时%s。" % [mx, UITheme.hours_text(float(r.get("time", 1)))])


func _log_line(bb: String) -> void:
	_log_lines.append(bb)
	while _log_lines.size() > 30:
		_log_lines.remove_at(0)
	_log.text = "\n".join(_log_lines)
