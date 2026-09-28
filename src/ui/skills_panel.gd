class_name SkillsPanel
extends UIWindow
## 功法与法诀：主修/辅修设置（五行、品阶、修炼倍率、属性、熟练度），
## 法诀详情与快捷槽（4 槽，金丹 5 槽；拖动或“装入”按钮设置），相生共鸣。

const TECH_LV := ["入门", "小成", "大成", "圆满"]
const CN_NUM := ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

var _tech_slots: HBoxContainer
var _tech_list: VBoxContainer
var _hotbar: HBoxContainer
var _resonance: RichTextLabel
var _spell_list: VBoxContainer


func _init() -> void:
	super()
	window_title = "功法 · 法诀"


func _build() -> void:
	var row := UITheme.hbox(22)
	add(row)
	# 功法
	var left := UITheme.vbox(10)
	left.custom_minimum_size.x = 560
	left.add_child(UITheme.header("功法"))
	_tech_slots = UITheme.hbox(10)
	left.add_child(_tech_slots)
	var tp := PanelContainer.new()
	tp.theme_type_variation = "InsetPanel"
	_tech_list = UITheme.vbox(8)
	var ts := UITheme.scroll(_tech_list)
	ts.custom_minimum_size = Vector2(540, 470)
	tp.add_child(ts)
	left.add_child(tp)
	row.add_child(left)
	# 法诀
	var right := UITheme.vbox(10)
	right.custom_minimum_size.x = 600
	right.add_child(UITheme.header("法诀"))
	_hotbar = UITheme.hbox(10)
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(_hotbar)
	_resonance = UITheme.rich("")
	_resonance.custom_minimum_size.x = 580
	right.add_child(_resonance)
	var sp := PanelContainer.new()
	sp.theme_type_variation = "InsetPanel"
	_spell_list = UITheme.vbox(8)
	var ss := UITheme.scroll(_spell_list)
	ss.custom_minimum_size = Vector2(580, 400)
	sp.add_child(ss)
	right.add_child(sp)
	row.add_child(right)
	var hint := UITheme.label("拖动法诀到快捷槽 · 右键快捷槽卸下 · 快捷槽之间拖动可互换", 14, UITheme.TEXT_FAINT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add(hint)


func refresh() -> void:
	if _tech_list == null:
		return
	var p := GS.player
	# 功法槽
	UIWindow.clear_children(_tech_slots)
	_tech_slots.add_child(_tech_slot_card("主修", p.main_technique))
	for i in 2:
		_tech_slots.add_child(_tech_slot_card("辅修" + CN_NUM[i], str(p.aux_techniques[i]) if i < p.aux_techniques.size() else ""))
	UIWindow.clear_children(_tech_list)
	if p.techniques.is_empty():
		_tech_list.add_child(UITheme.label("尚未习得任何功法。", 17, UITheme.TEXT_FAINT))
	for tid in p.techniques:
		_tech_list.add_child(_tech_card(str(tid)))
	# 快捷槽
	UIWindow.clear_children(_hotbar)
	var n := BuildCalc.spell_slot_count(p)
	for i in 5:
		var slot := SpellSlot.new()
		slot.index = i
		slot.locked = i >= n
		slot.spell_id = str(p.spell_slots[i]) if i < p.spell_slots.size() and i < n else ""
		_hotbar.add_child(slot)
	_resonance.text = _resonance_text(p)
	UIWindow.clear_children(_spell_list)
	if p.spells.is_empty():
		_spell_list.add_child(UITheme.label("尚未习得任何法诀。", 17, UITheme.TEXT_FAINT))
	for sid in p.spells:
		_spell_list.add_child(_spell_card(str(sid)))


# ================================================================ 功法

func _tech_slot_card(label: String, tid: String) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "CardSelected" if tid != "" else "CardPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UITheme.vbox(2)
	v.add_child(UITheme.label(label, 14, UITheme.TEXT_DIM))
	if tid == "":
		v.add_child(UITheme.label("— 空 —", 18, UITheme.TEXT_FAINT))
	else:
		var t := DB.technique(tid)
		var g := int(t.get("grade", 0))
		v.add_child(UITheme.label("《%s》" % t.get("name", tid), 19, Grade.color_of(g).lerp(UITheme.TEXT, 0.25)))
		v.add_child(UITheme.label("%s · %s" % [TECH_LV[clampi(GS.player.technique_level(tid), 0, 3)], _elem_name(str(t.get("element", "none")))], 14, UITheme.TEXT_DIM))
	card.add_child(v)
	return card


func _tech_card(tid: String) -> Control:
	var p := GS.player
	var t := DB.technique(tid)
	var g := int(t.get("grade", 0))
	var e := str(t.get("element", "none"))
	var is_main := p.main_technique == tid
	var aux_idx := p.aux_techniques.find(tid)
	var card := PanelContainer.new()
	card.theme_type_variation = "CardSelected" if is_main or aux_idx >= 0 else "CardPanel"
	var h := UITheme.hbox(12)
	card.add_child(h)
	var seal := ElemSeal.new()
	seal.element = e
	h.add_child(seal)
	var v := UITheme.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := UITheme.hbox(10)
	top.add_child(UITheme.label("《%s》" % t.get("name", tid), 20, Grade.color_of(g).lerp(UITheme.TEXT, 0.2)))
	top.add_child(UITheme.label(Grade.art_name(g), 14, Grade.color_of(g)))
	var slot_t := "主修功法" if str(t.get("slot", "main")) == "main" else "辅修功法"
	slot_t += " · 可修至" + str(DB.realm(int(t.get("max_realm", 0))).get("name", ""))
	top.add_child(UITheme.label(slot_t, 14, UITheme.TEXT_DIM))
	if is_main:
		top.add_child(UITheme.label("【主修中】", 14, UITheme.JADE))
	elif aux_idx >= 0:
		top.add_child(UITheme.label("【辅修%s】" % CN_NUM[aux_idx], 14, UITheme.JADE))
	v.add_child(top)
	var lv := p.technique_level(tid)
	var xp := float(p.techniques[tid].get("xp", 0.0))
	var need := 200.0 * pow(3.0, lv)
	var lr := UITheme.hbox(8)
	lr.add_child(UITheme.label(TECH_LV[clampi(lv, 0, 3)], 16, UITheme.GOLD_BRIGHT))
	var bar := UITheme.progress(xp if lv < 3 else need, need, "ExpBar", 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lr.add_child(bar)
	lr.add_child(UITheme.label("效果 +%d%%" % (lv * 25), 14, UITheme.TEXT_DIM))
	v.add_child(lr)
	var parts: PackedStringArray = []
	if t.has("cult_mult"):
		parts.append(UITheme.bb("修炼 ×%.2f" % float(t["cult_mult"]), UITheme.GOLD_BRIGHT))
	var scale := 1.0 + 0.25 * lv
	var stats: Dictionary = t.get("stats", {})
	for k in stats:
		parts.append(UITheme.bb(Stats.format_mod(k, float(stats[k]) * scale), UITheme.GOOD))
	var r := UITheme.rich("  ".join(parts))
	r.add_theme_font_size_override("normal_font_size", 15)
	v.add_child(r)
	var desc := UITheme.wrap_label(str(t.get("desc", "")), 14, UITheme.TEXT_DIM)
	v.add_child(desc)
	h.add_child(v)
	var btns := UITheme.vbox(6)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if str(t.get("slot", "main")) == "main":
		var b := UITheme.button("主修中" if is_main else "设为主修", "ChipButton", func() -> void:
			GS.set_main_technique("" if is_main else tid))
		b.toggle_mode = true
		b.button_pressed = is_main
		btns.add_child(b)
	else:
		for i in 2:
			var on := aux_idx == i
			var b2 := UITheme.button(("卸下辅修%s" if on else "辅修%s") % CN_NUM[i], "ChipButton", _set_aux.bind(i, "" if on else tid))
			b2.toggle_mode = true
			b2.button_pressed = on
			btns.add_child(b2)
	h.add_child(btns)
	card.tooltip_text = str(t.get("desc", ""))
	return card


func _set_aux(i: int, tid: String) -> void:
	GS.set_aux_technique(i, tid)


static func _elem_name(e: String) -> String:
	return Elem.name_of(e) + "系" if Elem.is_valid(e) else "无属性"


# ================================================================ 法诀

func _spell_card(sid: String) -> Control:
	var p := GS.player
	var sp := DB.spell(sid)
	var g := int(sp.get("grade", 0))
	var e := str(sp.get("element", "none"))
	var card := SpellCard.new()
	card.spell_id = sid
	card.theme_type_variation = "CardSelected" if p.spell_slots.has(sid) else "CardPanel"
	var h := UITheme.hbox(12)
	card.add_child(h)
	var ic := SpellIcon.new()
	ic.spell_id = sid
	ic.custom_minimum_size = Vector2(52, 52)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var v := UITheme.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := UITheme.hbox(10)
	top.add_child(UITheme.label("【%s】" % sp.get("name", sid), 20, Grade.color_of(g).lerp(UITheme.TEXT, 0.2)))
	top.add_child(UITheme.label(_elem_name(e), 14, Elem.color_of(e)))
	top.add_child(UITheme.label(str(SpellIcon.KIND_NAMES.get(str(sp.get("kind", "")), "")), 14, UITheme.TEXT_DIM))
	top.add_child(UITheme.label(Grade.art_name(g), 14, Grade.color_of(g)))
	v.add_child(top)
	var lv := p.spell_level(sid)
	var xp := float(p.spells[sid].get("xp", 0.0))
	var need := 20.0 * pow(1.8, lv)
	var lr := UITheme.hbox(8)
	lr.add_child(UITheme.label("第%s重" % CN_NUM[clampi(lv, 0, 9)], 15, UITheme.GOLD_BRIGHT))
	var bar := UITheme.progress(xp, need, "ExpBar", 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lr.add_child(bar)
	var power := float(sp.get("power", 0.0)) * BuildCalc.elem_power(p, e)
	lr.add_child(UITheme.label("灵力 %d · 冷却 %s秒 · 威力 %d%%" % [int(sp.get("qi", 0)), _num(float(sp.get("cd", 0.0))), int(round(power * 100.0))], 14, UITheme.TEXT_DIM))
	v.add_child(lr)
	v.add_child(UITheme.wrap_label(str(sp.get("desc", "")), 15, UITheme.TEXT))
	var st: Dictionary = sp.get("status", {})
	if not st.is_empty():
		var s_name := str(DB.status(str(st.get("id", ""))).get("name", st.get("id", "")))
		v.add_child(UITheme.label("命中附加：%s ×%d（%d%%）" % [s_name, int(st.get("stacks", 1)), int(float(st.get("chance", 1.0)) * 100.0)], 14, Elem.color_of(e).lerp(UITheme.TEXT, 0.4)))
	h.add_child(v)
	var btns := UITheme.vbox(4)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btns.add_child(UITheme.label("装入", 13, UITheme.TEXT_FAINT))
	var grid := GridContainer.new()
	grid.columns = BuildCalc.spell_slot_count(p)
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var n := BuildCalc.spell_slot_count(p)
	for i in n:
		var on: bool = i < p.spell_slots.size() and p.spell_slots[i] == sid
		var b := UITheme.button(str(i + 1), "ChipButton", _assign.bind(i, "" if on else sid))
		b.toggle_mode = true
		b.button_pressed = on
		b.custom_minimum_size = Vector2(30, 30)
		b.add_theme_constant_override("h_separation", 0)
		grid.add_child(b)
	btns.add_child(grid)
	h.add_child(btns)
	return card


func _assign(i: int, sid: String) -> void:
	GS.set_spell_slot(i, sid)


static func _num(v: float) -> String:
	return str(int(v)) if absf(v - roundf(v)) < 0.01 else "%.1f" % v


func _resonance_text(p: PlayerData) -> String:
	var elems: Array[String] = []
	for sid in p.spell_slots:
		if sid == "":
			continue
		var e := str(DB.spell(sid).get("element", ""))
		if Elem.is_valid(e) and not elems.has(e):
			elems.append(e)
	var pairs := BuildCalc.resonance_pairs(p)
	var chains: PackedStringArray = []
	for a in elems:
		var b: String = Elem.GENERATES[a]
		if elems.has(b):
			chains.append("%s生%s" % [UITheme.elem_bb(a), UITheme.elem_bb(b)])
	var per := 0.16 if p.root_count() == 5 else 0.08
	if pairs <= 0:
		return UITheme.bb("◇ 相生共鸣：未激活 —— 同时装配相生两系（金生水、水生木、木生火、火生土、土生金）的法诀即可引动。", UITheme.TEXT_DIM)
	return "%s %s  %s" % [UITheme.bb("◆ 相生共鸣 ×%d：" % pairs, UITheme.GOLD_BRIGHT), "、".join(chains),
		UITheme.bb("法诀伤害 +%d%% · 状态触发 +%d%%" % [int(per * pairs * 100.0), pairs * 5], UITheme.GOOD)]


## 功法元素印
class ElemSeal extends Control:
	var element: String = "none"

	func _init() -> void:
		custom_minimum_size = Vector2(48, 48)

	func _draw() -> void:
		var c := Elem.color_of(element)
		var valid := Elem.is_valid(element)
		var t := Elem.name_of(element) if valid else "道"
		var body := c.darkened(0.3) if valid else Color(0.24, 0.22, 0.2)
		InkArt.seal(get_canvas_item(), size * 0.5, minf(size.x, size.y) - 6.0, t, body, Color(1.0, 0.96, 0.88), false, -0.05)


## 可拖动的法诀卡片
class SpellCard extends PanelContainer:
	var spell_id: String = ""

	func _get_drag_data(_at: Vector2) -> Variant:
		var ic := SpellIcon.new()
		ic.spell_id = spell_id
		ic.custom_minimum_size = Vector2(56, 56)
		ic.size = Vector2(56, 56)
		ic.position = Vector2(-28, -28)
		var holder := Control.new()
		holder.add_child(ic)
		set_drag_preview(holder)
		return {"kind": "spell", "id": spell_id}


## 快捷槽（拖入法诀；槽间拖动互换；右键卸下）
class SpellSlot extends Control:
	var index: int = 0
	var spell_id: String = ""
	var locked: bool = false
	var _hl: int = 0

	func _init() -> void:
		custom_minimum_size = Vector2(96, 104)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _get_tooltip(_at: Vector2) -> String:
		if locked:
			return "金丹期开启第五法诀槽"
		if spell_id == "":
			return "空槽：拖入法诀"
		var sp := DB.spell(spell_id)
		return "【%s】\n%s\n灵力 %d · 冷却 %s 秒\n右键卸下" % [sp.get("name", ""), sp.get("desc", ""), int(sp.get("qi", 0)), str(sp.get("cd", 0))]

	func _draw() -> void:
		# 符纸槽：与战斗 HUD 法诀栏一致
		var ci := get_canvas_item()
		var r := Rect2(Vector2(6, 2), Vector2(size.x - 12, size.y - 4))
		if locked:
			HUDSpellBar.draw_paper(ci, r, 1.0, index, true, Color(0.3, 0.28, 0.26, 0.8))
		elif spell_id == "":
			HUDSpellBar.draw_paper(ci, r, 1.0, index, false, Color(0.72, 0.1, 0.06, 0.5))
			draw_rect(r, Color(0, 0, 0, 0.25))
		else:
			HUDSpellBar.draw_paper(ci, r, 1.0, index)
		if _hl != 0:
			var col := Color(0.4, 0.95, 0.6) if _hl > 0 else Color(1.0, 0.35, 0.3)
			draw_rect(r.grow(1), col, false, 2.0)
		if spell_id != "":
			var ic := Rect2(Vector2(r.get_center().x - 30, r.position.y + 12), Vector2(60, 60))
			SpellIcon.draw_spell(self, ic, spell_id)
		var f := UITheme.font_display()
		var key := str(index + 1)
		draw_string(f, r.position + Vector2(8, 20), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.3, 0.15, 0.07) if not locked else Color(0.2, 0.2, 0.2))
		var name_t := "封印" if locked else (str(DB.spell(spell_id).get("name", "")) if spell_id != "" else "空")
		var ts := f.get_string_size(name_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		draw_string(f, Vector2((size.x - ts.x) * 0.5, r.end.y - 9), name_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.55, 0.06, 0.04) if spell_id != "" else Color(0.35, 0.22, 0.14, 0.7))
		if locked:
			InkArt.seal(ci, r.get_center() + Vector2(0, -8), 44.0, "锁", Color(0.3, 0.28, 0.26, 0.9), Color(0.75, 0.72, 0.66), false, -0.1)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_DRAG_END:
			_hl = 0
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and spell_id != "":
			GS.set_spell_slot(index, "")
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		if locked or spell_id == "":
			return null
		var ic := SpellIcon.new()
		ic.spell_id = spell_id
		ic.size = Vector2(56, 56)
		ic.position = Vector2(-28, -28)
		var holder := Control.new()
		holder.add_child(ic)
		set_drag_preview(holder)
		return {"kind": "spell", "id": spell_id, "from_slot": index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		var ok: bool = not locked and data is Dictionary and data.get("kind", "") == "spell"
		_hl = 1 if ok else -1
		queue_redraw()
		return ok

	func _drop_data(_at: Vector2, data: Variant) -> void:
		var sid: String = data["id"]
		var from := int(data.get("from_slot", -1))
		var old := spell_id
		GS.set_spell_slot(index, sid)
		if from >= 0 and from != index and old != "":
			GS.set_spell_slot(from, old)
		Audio.play("ui_equip")
