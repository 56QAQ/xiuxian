extends Control
## 捏人（scenes/character_creator.tscn）：外貌 · 灵根 · 天赋 · 出身 · 姓名，实时 3D 预览与属性预估。
## 确认后 GS.new_game(creation) → Scenes.goto_overworld()。规则计算见 CreatorLogic。

const TABS := ["外貌", "灵根", "天赋", "出身", "姓名"]
const WEAPON_PREVIEWS := [["出身兵刃", "bg"], ["徒手", ""], ["精铁剑", "sword_iron"], ["青锋剑", "sword_green"], ["厚背刀", "saber_iron"], ["红缨枪", "spear_iron"], ["烈焰旗枪", "flag_spear_fire"]]
const MARK_COLORS := ["#e02040", "#f06020", "#f0c040", "#3080f0", "#40c0a0", "#c040c0", "#1a1a22", "#f0f0f4"]
const BROWS := [{"id": 0, "name": "平眉"}, {"id": 1, "name": "剑眉"}, {"id": 2, "name": "柳叶眉"}]
const ELEM_STATUS_TEXT := {
	"metal": "流血：持续伤害，目标高速移动时伤害翻倍",
	"wood": "中毒：降低目标攻击、防御与移速",
	"water": "束缚：减速，满层后定身",
	"fire": "灼烧：持续伤害并抑制护盾回复",
	"earth": "震慑：大幅削减韧性，更易打出硬直",
}
const ELEM_STRENGTH := {"metal": "暴击", "wood": "回复", "water": "灵力", "fire": "攻击", "earth": "护盾减伤"}

# ---- 角色数据
var appearance: Dictionary = {}
var roots: Dictionary = {"fire": 60, "wood": 40}
var attributes: Dictionary = {"con": 5, "int": 5, "spi": 5, "agi": 5, "luk": 5}
var talents: Array = []
var background: String = "rogue"
var sect: String = ""
var char_name: String = ""
var weapon_preview: String = "bg"

var rng := RandomNumberGenerator.new()
var ui: UIManager

# ---- 界面引用
var _preview: RigPreview
var _tab_buttons: Array[Button] = []
var _page_host: ScrollContainer
var _current_tab: int = 0
var _points_seal: PointsSeal
var _points_detail: Label
var _summary: VBoxContainer
var _name_title: Label
var _confirm: Button
var _error: Label
# 灵根页
var _root_sliders: Dictionary = {}
var _root_values: Dictionary = {}
var _root_chart: PentagonChart
var _root_card: VBoxContainer
var _root_passives: VBoxContainer
var _updating_roots: bool = false
# 天赋页
var _attr_rows: Dictionary = {}
var _talent_buttons: Dictionary = {}
# 姓名页
var _name_edit: LineEdit
var _bio: RichTextLabel


func _ready() -> void:
	rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	appearance = CharacterBuilder.DEFAULT_APPEARANCE.duplicate(true)
	char_name = CreatorLogic.random_name(str(appearance["gender"]), rng)
	_build()
	_show_tab(0)
	_update_preview(true)
	_update_summary()


# ================================================================ 布局

func _build() -> void:
	var bg := InkBackdrop.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.dim = 0.25
	bg.drift = 3.0
	add_child(bg)
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 18)
	add_child(root)
	var col := UITheme.vbox(12)
	root.add_child(col)
	# 顶栏
	var top := UITheme.hbox(14)
	var title := UITheme.title("塑造道身", 34)
	top.add_child(title)
	var sub := UITheme.label("问道长生 · 创建角色", 16, UITheme.TEXT_DIM)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(sub)
	top.add_child(UITheme.spacer(0, 0, true))
	var dice := UITheme.button("随机全部", "", randomize_all)
	dice.icon = UITheme.icon("dice")
	top.add_child(dice)
	top.add_child(UITheme.button("返回", "", _back))
	col.add_child(top)
	var main := UITheme.hbox(18)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(main)
	# 左：页签
	var left := PanelContainer.new()
	left.theme_type_variation = "WindowPanel"
	left.custom_minimum_size.x = 600
	var lv := UITheme.vbox(8)
	left.add_child(lv)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.theme_type_variation = "TabButton"
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.hook_sounds(b)
		b.pressed.connect(_show_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	lv.add_child(tabs)
	lv.add_child(UITheme.separator())
	_page_host = ScrollContainer.new()
	_page_host.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(_page_host)
	main.add_child(left)
	# 中：预览
	var center := UITheme.vbox(8)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview = RigPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(300, 400)
	_preview.yaw = -20.0
	center.add_child(_preview)
	var ctl := UITheme.hbox(8)
	ctl.alignment = BoxContainer.ALIGNMENT_CENTER
	var fg := ButtonGroup.new()
	for f in [["全身", "full"], ["半身", "upper"], ["面容", "bust"]]:
		var fb := UITheme.chip(str(f[0]), f[1] == "full", fg)
		fb.pressed.connect(_preview.set_framing.bind(str(f[1])))
		ctl.add_child(fb)
	ctl.add_child(UITheme.spacer(0, 12))
	var wopt := OptionButton.new()
	for i in WEAPON_PREVIEWS.size():
		wopt.add_item("持械：" + str(WEAPON_PREVIEWS[i][0]), i)
	wopt.item_selected.connect(func(i: int) -> void:
		weapon_preview = str(WEAPON_PREVIEWS[i][1])
		_update_preview(false))
	ctl.add_child(wopt)
	ctl.add_child(UITheme.button("随机外貌", "", func() -> void:
		appearance = CreatorLogic.random_appearance(rng, str(appearance.get("gender", "")))
		_after_appearance_reset()))
	center.add_child(ctl)
	var hint := UITheme.label("拖动旋转 · 滚轮缩放", 14, UITheme.TEXT_FAINT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(hint)
	main.add_child(center)
	# 右：总览
	var right := PanelContainer.new()
	right.theme_type_variation = "WindowPanel"
	right.custom_minimum_size.x = 350
	var rv := UITheme.vbox(8)
	right.add_child(rv)
	_name_title = UITheme.title(char_name, 30)
	_name_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_name_title)
	var ph := UITheme.hbox(12)
	ph.alignment = BoxContainer.ALIGNMENT_CENTER
	_points_seal = PointsSeal.new()
	ph.add_child(_points_seal)
	_points_detail = UITheme.label("", 15, UITheme.TEXT_DIM)
	ph.add_child(_points_detail)
	rv.add_child(ph)
	rv.add_child(UITheme.separator())
	_summary = UITheme.vbox(3)
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(_summary)
	_error = UITheme.label("", 15, UITheme.WARN)
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size.x = 300
	rv.add_child(_error)
	_confirm = UITheme.button("踏入仙途", "PrimaryButton", _on_confirm)
	_confirm.custom_minimum_size.y = 58
	_confirm.add_theme_font_size_override("font_size", 26)
	rv.add_child(_confirm)
	main.add_child(right)
	ui = UIManager.new()
	ui.hotkeys_enabled = false
	ui.pause_menu_enabled = false
	add_child(ui)


func _show_tab(i: int) -> void:
	_current_tab = i
	for j in _tab_buttons.size():
		_tab_buttons[j].set_pressed_no_signal(j == i)
	for c in _page_host.get_children():
		_page_host.remove_child(c)
		c.queue_free()
	var page: Control
	match i:
		0:
			page = _page_appearance()
		1:
			page = _page_roots()
		2:
			page = _page_talents()
		3:
			page = _page_background()
		_:
			page = _page_name()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := UITheme.margin(page, 4, 4, 14, 10)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_host.add_child(m)
	_page_host.scroll_vertical = 0
	if i == 4 and _name_edit != null:
		_name_edit.grab_focus.call_deferred()


# ================================================================ 小部件

func _row(label_text: String, c: Control) -> HBoxContainer:
	var h := UITheme.hbox(10)
	var l := UITheme.label(label_text, 17, UITheme.TEXT_DIM)
	l.custom_minimum_size.x = 76
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(c)
	return h


func _chips(options: Array, current: Variant, on_pick: Callable) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	var g := ButtonGroup.new()
	for o in options:
		var b := UITheme.chip(str(o["name"]), o["id"] == current, g)
		b.pressed.connect(on_pick.bind(o["id"]))
		f.add_child(b)
	return f


func _swatches(colors: Array, current: String, on_pick: Callable) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 5)
	f.add_theme_constant_override("v_separation", 5)
	var g := ButtonGroup.new()
	g.allow_unpress = true
	var found := false
	for c in colors:
		var sw := Swatch.new()
		sw.color = Color.html(str(c))
		sw.button_group = g
		sw.button_pressed = str(c).to_lower() == current.to_lower()
		found = found or sw.button_pressed
		sw.pressed.connect(on_pick.bind(str(c)))
		f.add_child(sw)
	var cp := ColorPickerButton.new()
	cp.theme_type_variation = "SwatchButton"
	cp.custom_minimum_size = Vector2(46, 28)
	cp.edit_alpha = false
	cp.color = Color.html(current) if current.begins_with("#") else Color.WHITE
	cp.tooltip_text = "自定义颜色" + ("（当前为自定义）" if not found else "")
	cp.color_changed.connect(func(c2: Color) -> void:
		for s in f.get_children():
			if s is Swatch:
				(s as Swatch).set_pressed_no_signal(false)
		on_pick.call("#" + c2.to_html(false)))
	var cl := UITheme.label("调色", 14, UITheme.TEXT_FAINT)
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	f.add_child(cl)
	f.add_child(cp)
	return f


func _slider(lo: float, hi: float, step: float, value: float, on_change: Callable, fmt: String = "%.2f") -> HBoxContainer:
	var h := UITheme.hbox(10)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := UITheme.label(fmt % value, 16, UITheme.GOLD_BRIGHT)
	v.custom_minimum_size.x = 52
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(nv: float) -> void:
		v.text = fmt % nv
		on_change.call(nv))
	h.add_child(s)
	h.add_child(v)
	return h


func _set_app(key: String, value: Variant) -> void:
	appearance[key] = value
	_update_preview(false)


# ================================================================ 外貌

func _page_appearance() -> Control:
	var ap: Dictionary = DB.appearance
	var v := UITheme.vbox(10)
	v.add_child(UITheme.header("身形", 19))
	v.add_child(_row("性别", _chips([{"id": "female", "name": "女"}, {"id": "male", "name": "男"}], appearance.get("gender", "female"), func(g: Variant) -> void:
		appearance["gender"] = g
		if g == "male":
			appearance["chest"] = 0.0
		_update_preview(false)
		_show_tab.call_deferred(0))))
	v.add_child(_row("身高", _slider(0.9, 1.1, 0.01, float(appearance.get("height", 1.0)), func(x: float) -> void: _set_app("height", x))))
	v.add_child(_row("体型", _slider(0.0, 1.0, 0.01, float(appearance.get("build", 0.4)), func(x: float) -> void: _set_app("build", x))))
	v.add_child(_row("头身比", _slider(0.9, 1.15, 0.01, float(appearance.get("head_scale", 1.0)), func(x: float) -> void: _set_app("head_scale", x))))
	if str(appearance.get("gender", "female")) == "female":
		v.add_child(_row("胸围", _slider(0.0, 1.0, 0.01, float(appearance.get("chest", 0.5)), func(x: float) -> void: _set_app("chest", x))))
	v.add_child(UITheme.header("发", 19))
	v.add_child(_row("发型", _chips(ap.get("hair_styles", []), appearance.get("hair_style", ""), func(id: Variant) -> void: _set_app("hair_style", id))))
	v.add_child(_row("发色", _swatches(ap.get("hair_colors", []), str(appearance.get("hair_color", "")), func(c: String) -> void:
		appearance["hair_color2"] = "#" + Color.html(c).lightened(0.25).to_html(false)
		_set_app("hair_color", c))))
	v.add_child(_row("挑染", _swatches(ap.get("hair_colors", []), str(appearance.get("hair_color2", "")), func(c: String) -> void: _set_app("hair_color2", c))))
	v.add_child(UITheme.header("面容", 19))
	v.add_child(_row("眼型", _chips(ap.get("eye_styles", []), appearance.get("eye_style", ""), func(id: Variant) -> void: _set_app("eye_style", id))))
	v.add_child(_row("瞳色", _swatches(ap.get("eye_colors", []), str(appearance.get("eye_color", "")), func(c: String) -> void: _set_app("eye_color", c))))
	v.add_child(_row("眉形", _chips(BROWS, int(appearance.get("brow_style", 0)), func(id: Variant) -> void: _set_app("brow_style", id))))
	v.add_child(_row("肤色", _swatches(ap.get("skin_colors", []), str(appearance.get("skin", "")), func(c: String) -> void: _set_app("skin", c))))
	v.add_child(_row("花钿", _chips(ap.get("marks", []), appearance.get("mark", "none"), func(id: Variant) -> void: _set_app("mark", id))))
	v.add_child(_row("钿色", _swatches(MARK_COLORS, str(appearance.get("mark_color", "")), func(c: String) -> void: _set_app("mark_color", c))))
	v.add_child(UITheme.header("异相", 19))
	v.add_child(_row("耳", _chips(ap.get("ears", []), appearance.get("ears", "human"), func(id: Variant) -> void: _set_app("ears", id))))
	v.add_child(_row("耳色", _swatches(ap.get("hair_colors", []), str(appearance.get("ear_color", "")), func(c: String) -> void: _set_app("ear_color", c))))
	v.add_child(_row("尾", _chips(ap.get("tails", []), appearance.get("tail", "none"), func(id: Variant) -> void: _set_app("tail", id))))
	v.add_child(_row("角", _chips(ap.get("horns", []), appearance.get("horns", "none"), func(id: Variant) -> void: _set_app("horns", id))))
	v.add_child(UITheme.header("服饰", 19))
	v.add_child(_row("款式", _chips(ap.get("outfits", []), appearance.get("outfit", "robe"), func(id: Variant) -> void: _set_app("outfit", id))))
	v.add_child(_row("配色", _palette_presets(ap.get("outfit_palettes", []))))
	var cur: Array = appearance.get("outfit_colors", ["#ffffff", "#888888", "#e0b040"])
	var custom := UITheme.hbox(12)
	for i in 3:
		var cp := ColorPickerButton.new()
		cp.theme_type_variation = "SwatchButton"
		cp.custom_minimum_size = Vector2(54, 30)
		cp.edit_alpha = false
		cp.color = Color.html(str(cur[i])) if i < cur.size() else Color.WHITE
		cp.color_changed.connect(_on_outfit_color.bind(i))
		var box := UITheme.hbox(4)
		box.add_child(UITheme.label(["主色", "副色", "饰边"][i], 15, UITheme.TEXT_FAINT))
		box.add_child(cp)
		custom.add_child(box)
	v.add_child(_row("自定", custom))
	return v


func _palette_presets(palettes: Array) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	var g := ButtonGroup.new()
	var cur: Array = appearance.get("outfit_colors", [])
	for pal in palettes:
		var b := PaletteButton.new()
		b.colors = pal
		b.button_group = g
		b.button_pressed = str(pal) == str(cur)
		b.pressed.connect(func() -> void:
			_set_app("outfit_colors", (pal as Array).duplicate())
			_show_tab.call_deferred(0))
		f.add_child(b)
	return f


func _on_outfit_color(c: Color, i: int) -> void:
	var cur: Array = (appearance.get("outfit_colors", ["#ffffff", "#888888", "#e0b040"]) as Array).duplicate()
	while cur.size() < 3:
		cur.append("#888888")
	cur[i] = "#" + c.to_html(false)
	_set_app("outfit_colors", cur)


func _after_appearance_reset() -> void:
	_update_preview(false)
	if _current_tab == 0:
		_show_tab(0)
	_update_summary()


# ================================================================ 灵根

func _page_roots() -> Control:
	_root_sliders.clear()
	_root_values.clear()
	var v := UITheme.vbox(10)
	v.add_child(UITheme.wrap_label("选择 1~5 系灵根并分配占比（每系至少 5%）。灵根越纯，修炼越快、单系越强；灵根越杂，越能借相生共鸣交织五行。", 16, UITheme.TEXT_DIM))
	var toggles := UITheme.hbox(8)
	for e in Elem.LIST:
		var b := ElemToggle.new()
		b.element = e
		b.button_pressed = int(roots.get(e, 0)) > 0
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.hook_sounds(b)
		b.pressed.connect(_on_root_toggle.bind(e))
		toggles.add_child(b)
	v.add_child(toggles)
	var body := UITheme.hbox(14)
	var sl := UITheme.vbox(8)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for e in Elem.LIST:
		if int(roots.get(e, 0)) <= 0:
			continue
		var row := UITheme.hbox(8)
		var gl := UITheme.label(Elem.name_of(e), 22, Elem.color_of(e))
		gl.add_theme_font_override("font", UITheme.font_title())
		row.add_child(gl)
		var s := HSlider.new()
		s.min_value = CreatorLogic.ROOT_MIN
		s.max_value = 100
		s.step = 1
		s.value = int(roots[e])
		s.editable = CreatorLogic.root_count(roots) > 1
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := UITheme.flat(Elem.color_of(e).darkened(0.25), Color(0, 0, 0, 0), 0, 2)
		fill.content_margin_top = 3
		fill.content_margin_bottom = 3
		s.add_theme_stylebox_override("grabber_area", fill)
		s.add_theme_stylebox_override("grabber_area_highlight", fill)
		s.value_changed.connect(_on_root_slider.bind(e))
		row.add_child(s)
		var vl := UITheme.label("%d%%" % int(roots[e]), 18, UITheme.TEXT)
		vl.custom_minimum_size.x = 48
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(vl)
		_root_sliders[e] = s
		_root_values[e] = vl
		sl.add_child(row)
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	_root_card = UITheme.vbox(3)
	card.add_child(_root_card)
	sl.add_child(card)
	body.add_child(sl)
	_root_chart = PentagonChart.new()
	_root_chart.custom_minimum_size = Vector2(250, 250)
	_root_chart.values = roots
	body.add_child(_root_chart)
	v.add_child(body)
	v.add_child(UITheme.header("灵根被动", 18))
	_root_passives = UITheme.vbox(6)
	v.add_child(_root_passives)
	_refresh_root_info()
	return v


func _on_root_toggle(e: String) -> void:
	roots = CreatorLogic.toggle_root(roots, e)
	_show_tab.call_deferred(1)
	_update_summary()


func _on_root_slider(value: float, e: String) -> void:
	if _updating_roots:
		return
	roots = CreatorLogic.set_root(roots, e, int(value))
	_updating_roots = true
	for k in _root_sliders:
		(_root_sliders[k] as HSlider).set_value_no_signal(int(roots.get(k, 0)))
		(_root_values[k] as Label).text = "%d%%" % int(roots.get(k, 0))
	_updating_roots = false
	_root_chart.values = roots
	_refresh_root_info()
	_update_summary()


func _refresh_root_info() -> void:
	if _root_card == null or not is_instance_valid(_root_card):
		return
	UIWindow.clear_children(_root_card)
	var rt := CreatorLogic.root_type(roots)
	var cost := int(rt["cost"])
	var top := UITheme.hbox(10)
	top.add_child(UITheme.label(str(rt["name"]), 22, UITheme.GOLD_BRIGHT))
	var cl := UITheme.label(("消耗 %d 点" % cost) if cost > 0 else (("返还 %d 点" % -cost) if cost < 0 else "不耗点数"), 16, UITheme.BAD if cost > 0 else UITheme.GOOD)
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(cl)
	_root_card.add_child(top)
	_root_card.add_child(UITheme.label("修炼速度 ×%.1f" % float(rt["cult"]), 17, UITheme.TEXT))
	var n := CreatorLogic.root_count(roots)
	var note := ""
	match n:
		1:
			note = "天灵根：单系纯度 +25%%，本系法诀威力 ×%.2f。" % (0.6 + 0.8 + 0.25)
		2:
			note = "双灵根：两系交叉构筑，可引动相生共鸣。"
		5:
			note = "五行轮转：法诀伤害 +10%，冷却缩减 +8%，相生共鸣效果翻倍。"
		_:
			note = "多系灵根：借相生共鸣（金→水→木→火→土→金）弥补修速。"
	_root_card.add_child(UITheme.wrap_label(note, 15, UITheme.TEXT_DIM))
	UIWindow.clear_children(_root_passives)
	for e in Elem.LIST:
		if int(roots.get(e, 0)) <= 0:
			continue
		var h := UITheme.hbox(8)
		var gl := UITheme.label("%s %d%%" % [Elem.name_of(e), int(roots[e])], 17, Elem.color_of(e))
		gl.custom_minimum_size.x = 70
		gl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(gl)
		var tv := UITheme.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UITheme.wrap_label(CreatorLogic.passive_text(roots, e), 15, UITheme.TEXT))
		tv.add_child(UITheme.wrap_label("长于%s · %s · 本系威力 ×%.2f" % [ELEM_STRENGTH[e], ELEM_STATUS_TEXT[e], _elem_power(e)], 14, UITheme.TEXT_DIM))
		h.add_child(tv)
		_root_passives.add_child(h)


func _elem_power(e: String) -> float:
	var p := PlayerData.new()
	p.roots = roots
	return BuildCalc.elem_power(p, e)


# ================================================================ 天赋

func _page_talents() -> Control:
	_attr_rows.clear()
	_talent_buttons.clear()
	var v := UITheme.vbox(10)
	v.add_child(UITheme.header("先天属性", 19))
	v.add_child(UITheme.wrap_label("每项基础 5，范围 1~10。提升 1 点消耗 1 天赋点；低于 5 时每点返还 1 天赋点。", 15, UITheme.TEXT_DIM))
	for a in PlayerData.ATTRS:
		v.add_child(_attr_row(a))
	v.add_child(UITheme.header("天赋", 19))
	v.add_child(UITheme.wrap_label("正面天赋消耗点数；缺陷返还点数（附带代价与些许补偿）。", 15, UITheme.TEXT_DIM))
	var cats: Array[String] = []
	for tid in DB.talents:
		var c := str(DB.talent(tid).get("category", "其他"))
		if not cats.has(c):
			cats.append(c)
	for c in cats:
		var ct := UITheme.label("◇ " + c, 17, UITheme.CINNABAR.lightened(0.2) if c == "缺陷" else UITheme.GOLD)
		v.add_child(ct)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for tid in DB.talents:
			if str(DB.talent(tid).get("category", "其他")) == c:
				grid.add_child(_talent_button(str(tid)))
		v.add_child(grid)
	_refresh_talent_states()
	return v


func _attr_row(a: String) -> Control:
	var h := UITheme.hbox(8)
	var n := UITheme.label(str(PlayerData.ATTR_NAMES[a]), 20, UITheme.TEXT)
	n.add_theme_font_override("font", UITheme.font_title())
	n.custom_minimum_size.x = 50
	n.mouse_filter = Control.MOUSE_FILTER_PASS
	n.tooltip_text = CharacterPanel.attr_tooltip(a)
	h.add_child(n)
	var minus := UITheme.button("－", "ChipButton", _change_attr.bind(a, -1))
	minus.custom_minimum_size = Vector2(36, 32)
	h.add_child(minus)
	var val := UITheme.label("5", 22, UITheme.GOLD_BRIGHT)
	val.custom_minimum_size.x = 30
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(val)
	var plus := UITheme.button("＋", "ChipButton", _change_attr.bind(a, 1))
	plus.custom_minimum_size = Vector2(36, 32)
	h.add_child(plus)
	var pips := CharacterPanel.AttrPips.new()
	pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pips.tooltip_text = n.tooltip_text
	h.add_child(pips)
	var desc := UITheme.label(_attr_blurb(a), 14, UITheme.TEXT_DIM)
	desc.custom_minimum_size.x = 150
	h.add_child(desc)
	_attr_rows[a] = {"val": val, "minus": minus, "plus": plus, "pips": pips}
	return h


static func _attr_blurb(a: String) -> String:
	return {"con": "生命 · 防御 · 突破", "int": "修炼 · 感悟 · 学习", "spi": "灵力 · 法术 · 搜索", "agi": "速度 · 推进 · 暴击", "luk": "掉落品阶 · 奇遇"}.get(a, "")


func _change_attr(a: String, d: int) -> void:
	var remain := CreatorLogic.remaining(attributes, talents, roots)
	if d > 0 and not CreatorLogic.can_raise(attributes, a, remain):
		Audio.play("ui_error")
		return
	if d < 0 and not CreatorLogic.can_lower(attributes, a):
		Audio.play("ui_error")
		return
	attributes[a] = int(attributes[a]) + d
	_refresh_talent_states()
	_update_summary()


func _talent_button(tid: String) -> Button:
	var t := DB.talent(tid)
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(262, 84)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cost := int(t.get("cost", 0))
	var neg := cost < 0
	var n_box := UITheme.card_box(false)
	var p_box := UITheme.card_box(true)
	if neg:
		p_box.accent_color = UITheme.CINNABAR
		p_box.bg_top = Color(0.3, 0.1, 0.08, 0.8)
		p_box.bg_bottom = Color(0.14, 0.05, 0.04, 0.8)
	var h_box := n_box.duplicate() as OrnateBox
	h_box.border_color = UITheme.GOLD
	var d_box := n_box.duplicate() as OrnateBox
	d_box.bg_top = Color(0.05, 0.05, 0.05, 0.5)
	d_box.bg_bottom = Color(0.05, 0.05, 0.05, 0.5)
	b.add_theme_stylebox_override("normal", n_box)
	b.add_theme_stylebox_override("hover", h_box)
	b.add_theme_stylebox_override("pressed", p_box)
	b.add_theme_stylebox_override("hover_pressed", p_box)
	b.add_theme_stylebox_override("disabled", d_box)
	UITheme.hook_sounds(b)
	var v := UITheme.vbox(2)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_right = -10
	v.offset_top = 8
	v.offset_bottom = -6
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UITheme.hbox(8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := UITheme.label(str(t.get("name", tid)), 18, UITheme.CINNABAR.lightened(0.3) if neg else UITheme.TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	top.add_child(UITheme.label(("返还 %d" % -cost) if neg else ("%d 点" % cost), 15, UITheme.GOOD if neg else UITheme.GOLD_BRIGHT))
	v.add_child(top)
	var d := UITheme.label(str(t.get("desc", "")), 13, UITheme.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 200
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	b.add_child(v)
	var lines: PackedStringArray = [str(t.get("desc", ""))]
	var st: Dictionary = t.get("stats", {})
	for k in st:
		lines.append(Stats.format_mod(k, float(st[k])))
	b.tooltip_text = "\n".join(lines)
	b.pressed.connect(_toggle_talent.bind(tid))
	_talent_buttons[tid] = b
	return b


func _toggle_talent(tid: String) -> void:
	var remain := CreatorLogic.remaining(attributes, talents, roots)
	if talents.has(tid):
		talents.erase(tid)
	elif CreatorLogic.can_toggle_talent(talents, tid, remain):
		talents.append(tid)
	else:
		Audio.play("ui_error")
	_refresh_talent_states()
	_update_summary()


func _refresh_talent_states() -> void:
	var remain := CreatorLogic.remaining(attributes, talents, roots)
	for a in _attr_rows:
		var r: Dictionary = _attr_rows[a]
		if not is_instance_valid(r["val"]):
			continue
		var v := int(attributes[a])
		(r["val"] as Label).text = str(v)
		(r["val"] as Label).add_theme_color_override("font_color", UITheme.GOLD_BRIGHT if v > 5 else (UITheme.BAD if v < 5 else UITheme.TEXT))
		(r["minus"] as Button).disabled = not CreatorLogic.can_lower(attributes, a)
		(r["plus"] as Button).disabled = not CreatorLogic.can_raise(attributes, a, remain)
		(r["pips"] as CharacterPanel.AttrPips).value = v
		(r["pips"] as CharacterPanel.AttrPips).queue_redraw()
	for tid in _talent_buttons:
		var b: Button = _talent_buttons[tid]
		if not is_instance_valid(b):
			continue
		b.set_pressed_no_signal(talents.has(tid))
		b.disabled = not CreatorLogic.can_toggle_talent(talents, tid, remain)


# ================================================================ 出身

func _page_background() -> Control:
	var v := UITheme.vbox(10)
	v.add_child(UITheme.wrap_label("出身决定初始灵石、储物袋、物品与人脉。", 15, UITheme.TEXT_DIM))
	var g := ButtonGroup.new()
	for bid in DB.backgrounds:
		v.add_child(_bg_card(str(bid), g))
	if bool(DB.backgrounds.get(background, {}).get("sect_choice", false)):
		v.add_child(UITheme.header("所在宗门", 19))
		v.add_child(UITheme.wrap_label("宗门杂役起始即为该宗记名弟子。", 15, UITheme.TEXT_DIM))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		var sg := ButtonGroup.new()
		for sid in DB.sects:
			grid.add_child(_sect_card(str(sid), sg))
		v.add_child(grid)
	return v


func _card_button(selected: bool, group: ButtonGroup, min_size: Vector2) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = selected
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n_box := UITheme.card_box(false)
	var h_box := n_box.duplicate() as OrnateBox
	h_box.border_color = UITheme.GOLD
	b.add_theme_stylebox_override("normal", n_box)
	b.add_theme_stylebox_override("hover", h_box)
	b.add_theme_stylebox_override("pressed", UITheme.card_box(true))
	b.add_theme_stylebox_override("hover_pressed", UITheme.card_box(true))
	UITheme.hook_sounds(b)
	return b


func _bg_card(bid: String, g: ButtonGroup) -> Control:
	var bg: Dictionary = DB.backgrounds[bid]
	var b := _card_button(bid == background, g, Vector2(540, 124))
	var v := UITheme.vbox(4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14
	v.offset_right = -12
	v.offset_top = 10
	v.offset_bottom = -8
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UITheme.hbox(10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := UITheme.label(str(bg.get("name", bid)), 22, UITheme.GOLD_BRIGHT)
	nm.add_theme_font_override("font", UITheme.font_title())
	top.add_child(nm)
	var bag_name := str(DB.item(str(bg.get("bag", "bag_basic"))).get("name", ""))
	var meta := UITheme.label("灵石 %d · %s" % [int(bg.get("stones", 0)), bag_name], 15, UITheme.TEXT_DIM)
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(meta)
	v.add_child(top)
	var d := UITheme.label(str(bg.get("desc", "")), 15, UITheme.TEXT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 480
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	var icons := UITheme.hbox(4)
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ids: Array = []
	for s in bg.get("equip", {}):
		ids.append([str(bg["equip"][s]), 1])
	for e in bg.get("items", []):
		ids.append([str(e[0]), int(e[1])])
	for pair in ids:
		var ic := ItemIcon.new()
		ic.item_id = str(pair[0])
		ic.count = int(pair[1])
		ic.custom_minimum_size = Vector2(38, 38)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icons.add_child(ic)
	var extra: PackedStringArray = []
	var stats: Dictionary = bg.get("stats", {})
	for k in stats:
		extra.append(Stats.format_mod(k, float(stats[k])))
	if bool(bg.get("sect_choice", false)):
		extra.append("起始为宗门记名弟子")
	if not extra.is_empty():
		var el := UITheme.label("  " + " · ".join(extra), 14, UITheme.GOOD)
		el.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icons.add_child(el)
	v.add_child(icons)
	b.add_child(v)
	b.pressed.connect(func() -> void:
		background = bid
		if not bool(bg.get("sect_choice", false)):
			sect = ""
		elif sect == "":
			sect = str(DB.sects.keys()[0])
		_show_tab.call_deferred(3)
		_update_preview(false)
		_update_summary())
	return b


func _sect_card(sid: String, g: ButtonGroup) -> Control:
	var s := DB.sect(sid)
	var b := _card_button(sid == sect, g, Vector2(262, 92))
	var c := CharacterBuilder.col(s.get("color", "#ffffff"))
	var v := UITheme.vbox(2)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14
	v.offset_right = -10
	v.offset_top = 8
	v.offset_bottom = -6
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UITheme.hbox(8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(UITheme.label(str(s.get("name", sid)), 20, c.lerp(UITheme.TEXT, 0.25)))
	var e := str(s.get("element", ""))
	top.add_child(UITheme.label("%s · %s" % [Elem.name_of(e), PlayerData.PROFESSION_NAMES.get(str(s.get("profession", "")), "")], 14, Elem.color_of(e)))
	v.add_child(top)
	var m := UITheme.label(str(s.get("motto", "")), 14, UITheme.TEXT_DIM)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(m)
	b.add_child(v)
	b.tooltip_text = str(s.get("desc", ""))
	b.pressed.connect(func() -> void:
		sect = sid
		_update_summary())
	return b


# ================================================================ 姓名

func _page_name() -> Control:
	var v := UITheme.vbox(12)
	v.add_child(UITheme.header("道号", 19))
	var h := UITheme.hbox(10)
	_name_edit = LineEdit.new()
	_name_edit.text = char_name
	_name_edit.placeholder_text = "输入姓名"
	_name_edit.max_length = 12
	_name_edit.add_theme_font_size_override("font_size", 28)
	_name_edit.add_theme_font_override("font", UITheme.font_title())
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(t: String) -> void:
		char_name = t.strip_edges()
		_update_summary())
	h.add_child(_name_edit)
	var dice := UITheme.button("随机", "", func() -> void:
		char_name = CreatorLogic.random_name(str(appearance.get("gender", "female")), rng)
		_name_edit.text = char_name
		_update_summary())
	dice.icon = UITheme.icon("dice")
	h.add_child(dice)
	v.add_child(h)
	var sugg := HFlowContainer.new()
	sugg.add_theme_constant_override("h_separation", 6)
	sugg.add_theme_constant_override("v_separation", 6)
	for i in 8:
		var nm := CreatorLogic.random_name(str(appearance.get("gender", "female")), rng)
		var b := UITheme.button(nm, "ChipButton", func() -> void:
			char_name = nm
			_name_edit.text = nm
			_update_summary())
		sugg.add_child(b)
	v.add_child(UITheme.label("灵感：", 15, UITheme.TEXT_FAINT))
	v.add_child(sugg)
	v.add_child(UITheme.header("小传", 19))
	var bp := PanelContainer.new()
	bp.theme_type_variation = "ParchmentPanel"
	_bio = UITheme.rich("")
	_bio.add_theme_color_override("default_color", UITheme.PARCHMENT_INK)
	_bio.add_theme_font_size_override("normal_font_size", 18)
	bp.add_child(_bio)
	v.add_child(bp)
	_update_bio()
	return v


func _update_bio() -> void:
	if _bio == null or not is_instance_valid(_bio):
		return
	var bg: Dictionary = DB.backgrounds.get(background, {})
	var rt := CreatorLogic.root_type(roots)
	var els: PackedStringArray = []
	for e in roots:
		els.append(Elem.name_of(e))
	var tn: PackedStringArray = []
	for t in talents:
		tn.append(str(DB.talent(str(t)).get("name", t)))
	var who := "她" if str(appearance.get("gender", "female")) == "female" else "他"
	var text := "%s，年方十六，%s出身。" % [char_name if char_name != "" else "无名氏", str(bg.get("name", ""))]
	text += "身怀%s（%s），" % [rt["name"], "".join(els)]
	text += ("生来便有%s之资。" % "、".join(tn)) if not tn.is_empty() else "资质平平，唯有一颗向道之心。"
	if sect != "" and bool(bg.get("sect_choice", false)):
		text += "%s在%s做了多年杂役，终得准许修行。" % [who, DB.sect(sect).get("name", "")]
	text += "\n天元三七二一年春，%s踏上了问道长生之路。" % who
	_bio.text = text


# ================================================================ 预览与总览

func _equip_visual() -> Dictionary:
	var id := weapon_preview
	if id == "bg":
		id = str(DB.backgrounds.get(background, {}).get("equip", {}).get("weapon", ""))
	if id == "":
		return {}
	var vis: Dictionary = DB.item(id).get("weapon", {}).get("visual", {})
	if vis.is_empty() or str(vis.get("kind", "")) == "fist":
		return {}
	return {"weapon": vis}


func _update_preview(immediate: bool) -> void:
	if _preview != null:
		_preview.set_appearance(appearance, _equip_visual(), immediate)


## 临时 PlayerData（仅依赖 DB）用于属性预估
func preview_player() -> PlayerData:
	var p := PlayerData.new()
	p.name = char_name
	p.appearance = appearance
	p.roots = roots.duplicate()
	p.attributes = attributes.duplicate()
	p.talents = talents.duplicate()
	p.background = background
	var bg: Dictionary = DB.backgrounds.get(background, {})
	for slot in bg.get("equip", {}):
		p.equipment[slot] = ItemInstance.create(str(bg["equip"][slot]))
	for tid in bg.get("techniques", []):
		p.techniques[tid] = {"lv": 0, "xp": 0.0}
		if p.main_technique == "":
			p.main_technique = str(tid)
	return p


func _update_summary() -> void:
	if _summary == null:
		return
	_name_title.text = char_name if char_name != "" else "无名"
	var remain := CreatorLogic.remaining(attributes, talents, roots)
	_points_seal.value = remain
	_points_seal.queue_redraw()
	_points_detail.text = "属性 %s\n天赋 %s\n灵根 %s" % [_signed(-CreatorLogic.attr_cost(attributes)), _signed(-CreatorLogic.talent_cost(talents)), _signed(-CreatorLogic.root_cost(roots))]
	var p := preview_player()
	var st := BuildCalc.compute(p)
	UIWindow.clear_children(_summary)
	var rt := CreatorLogic.root_type(roots)
	var els: PackedStringArray = []
	for e in roots:
		els.append("%s%d" % [Elem.name_of(e), int(roots[e])])
	_summary.add_child(UITheme.kv_row("灵根", "%s（%s）" % [rt["name"], " ".join(els)], UITheme.GOLD_BRIGHT, 16))
	_summary.add_child(UITheme.kv_row("修炼速度", "×%.2f · 每时辰 %d" % [float(st["cult_speed"]), int(Cultivation.rate_per_hour(p, st, "wild") * 2.0)], UITheme.TEXT, 16))
	var bg: Dictionary = DB.backgrounds.get(background, {})
	var bgt := str(bg.get("name", ""))
	if sect != "" and bool(bg.get("sect_choice", false)):
		bgt += " · " + str(DB.sect(sect).get("name", ""))
	_summary.add_child(UITheme.kv_row("出身", bgt, UITheme.TEXT, 16))
	_summary.add_child(UITheme.separator(false))
	var keys := ["max_hp", "max_shield", "max_qi", "attack", "defense", "crit_rate", "crit_dmg", "spell_mult", "move_speed", "breakthrough", "insight_gain", "luck"]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	for k in keys:
		var key: String = k
		var l := UITheme.label(Stats.label(key), 15, UITheme.TEXT_DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
		var val := UITheme.label(Stats.format_value(key, float(st.get(key, 0.0))), 15, UITheme.TEXT)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(val)
	_summary.add_child(grid)
	if not talents.is_empty():
		_summary.add_child(UITheme.separator(false))
		var tn: PackedStringArray = []
		for t in talents:
			tn.append(str(DB.talent(str(t)).get("name", t)))
		_summary.add_child(UITheme.wrap_label("天赋：" + "、".join(tn), 15, UITheme.JADE))
	var err := CreatorLogic.validate(char_name, attributes, talents, roots, background, sect)
	_error.text = err
	_confirm.disabled = err != ""
	_update_bio()


static func _signed(v: int) -> String:
	return ("+%d" % v) if v > 0 else str(v)


# ================================================================ 操作

func randomize_all() -> void:
	appearance = CreatorLogic.random_appearance(rng)
	roots = CreatorLogic.random_roots(rng)
	var b := CreatorLogic.random_build(roots, rng)
	attributes = b["attributes"]
	talents = b["talents"]
	var bids := DB.backgrounds.keys()
	background = str(bids[rng.randi() % bids.size()])
	sect = str(DB.sects.keys()[rng.randi() % DB.sects.size()]) if bool(DB.backgrounds[background].get("sect_choice", false)) else ""
	char_name = CreatorLogic.random_name(str(appearance["gender"]), rng)
	_show_tab(_current_tab)
	_update_preview(false)
	_update_summary()
	Audio.play("ui_dice")


## 生成 creation 字典（GS.new_game 参数）
func creation() -> Dictionary:
	var c := {
		"name": char_name.strip_edges(),
		"gender": str(appearance.get("gender", "female")),
		"appearance": appearance.duplicate(true),
		"roots": CreatorLogic.normalize(roots),
		"attributes": attributes.duplicate(),
		"talents": talents.duplicate(),
		"background": background,
	}
	if sect != "" and bool(DB.backgrounds.get(background, {}).get("sect_choice", false)):
		c["sect"] = sect
	return c


func _on_confirm() -> void:
	var err := CreatorLogic.validate(char_name, attributes, talents, roots, background, sect)
	if err != "":
		Events.notify.emit(err, "warn")
		return
	var c := creation()
	start_game(c)
	Audio.play("ui_confirm")
	Scenes.goto_overworld()


## 以 creation 开始新游戏（宗门杂役：设定宗门并建立贡献/声望记录）
static func start_game(c: Dictionary) -> void:
	GS.new_game(c)
	if c.has("sect") and DB.sects.has(str(c["sect"])):
		var sid := str(c["sect"])
		GS.player.sect = sid
		GS.player.sect_rank = 0
		GS.player.contribution[sid] = int(GS.player.contribution.get(sid, 0))
		GS.player.reputation[sid] = int(GS.player.reputation.get(sid, 0))
		GS.recompute()
		Events.sect_changed.emit()


func _back() -> void:
	ui.confirm("放弃当前捏人，返回主菜单？", Scenes.goto_main_menu, "返回")


# ================================================================ 内部控件

## 剩余天赋点印章
class PointsSeal extends Control:
	var value: int = 12

	func _init() -> void:
		custom_minimum_size = Vector2(112, 112)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		var col := UITheme.GOLD_BRIGHT if value > 0 else (UITheme.JADE if value == 0 else UITheme.BAD)
		draw_circle(c, r, Color(0, 0, 0, 0.45))
		draw_arc(c, r, 0, TAU, 48, col, 2.0, true)
		draw_arc(c, r - 5.0, 0, TAU, 48, Color(col.r, col.g, col.b, 0.35), 1.0, true)
		var frac := clampf(float(value) / CreatorLogic.BUDGET, 0.0, 1.0)
		if frac > 0.0:
			draw_arc(c, r - 2.5, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, Color(col.r, col.g, col.b, 0.8), 3.0, true)
		var f := UITheme.font_title()
		var t := str(value)
		var fs := 44
		var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2(c.x - ts.x * 0.5, c.y + 8), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		var sub := "剩余点数"
		var lf := UITheme.font_regular()
		var ss := lf.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		draw_string(lf, Vector2(c.x - ss.x * 0.5, c.y + 30), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)


## 色块按钮
class Swatch extends Button:
	var color: Color = Color.WHITE

	func _init() -> void:
		toggle_mode = true
		theme_type_variation = "SwatchButton"
		custom_minimum_size = Vector2(28, 28)
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		draw_rect(r, color)
		draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), Color(1, 1, 1, 0.12))
		if button_pressed:
			draw_rect(r.grow(1), UITheme.GOLD_BRIGHT, false, 2.0)


## 配色方案按钮（三色条）
class PaletteButton extends Button:
	var colors: Array = []

	func _init() -> void:
		toggle_mode = true
		theme_type_variation = "SwatchButton"
		custom_minimum_size = Vector2(64, 30)
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		var n := colors.size()
		for i in n:
			var w := r.size.x / n
			draw_rect(Rect2(r.position + Vector2(i * w, 0), Vector2(w, r.size.y)), Color.html(str(colors[i])))
		if button_pressed:
			draw_rect(r.grow(1), UITheme.GOLD_BRIGHT, false, 2.0)


## 五行灵根开关
class ElemToggle extends Button:
	var element: String = "fire"

	func _init() -> void:
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(96, 64)
		theme_type_variation = "SwatchButton"

	func _draw() -> void:
		var c := Elem.color_of(element)
		var on := button_pressed
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		var top := Color(c.r * 0.45, c.g * 0.45, c.b * 0.45, 0.95) if on else Color(0.1, 0.1, 0.11, 0.8)
		var bot := Color(c.r * 0.18, c.g * 0.18, c.b * 0.18, 0.95) if on else Color(0.05, 0.05, 0.06, 0.8)
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bot, bot]))
		draw_rect(r, c if on else Color(c.r, c.g, c.b, 0.35), false, 2.0 if on else 1.0)
		if is_hovered():
			draw_rect(r.grow(-3), Color(c.r, c.g, c.b, 0.4), false, 1.0)
		var f := UITheme.font_title()
		var t := Elem.name_of(element)
		var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 30)
		draw_string(f, Vector2((size.x - ts.x) * 0.5, size.y * 0.5 + 8), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, c.lightened(0.3) if on else Color(c.r, c.g, c.b, 0.45))
		var sub := "灵根" if on else "未选"
		var lf := UITheme.font_regular()
		var ss := lf.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		draw_string(lf, Vector2((size.x - ss.x) * 0.5, size.y - 6), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.TEXT_DIM)
