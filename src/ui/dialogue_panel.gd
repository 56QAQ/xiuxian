class_name DialoguePanel
extends UIWindow
## 对话面板（NPC、遭遇共用）。
## args: {"name": String, "title": String, "text": String,
##        "options": [{"text": String, "callback": Callable, "disabled"?: bool, "hint"?: String}],
##        "portrait_appearance"?: Dictionary, "can_close"?: bool（默认 true，Esc 关闭且不触发回调）}
## 打字机效果；单击正文/空格/回车跳过；数字键 1~9 选择选项。选择后先关闭面板再调用回调。

const CHARS_PER_SEC := 42.0

var _text: RichTextLabel
var _opts: VBoxContainer
var _opt_buttons: Array[Button] = []
var _options: Array = []
var _shown: float = 0.0
var _total: int = 0
var _done: bool = false


func _init() -> void:
	super()
	auto_refresh = false
	draggable = false


func _build() -> void:
	esc_closes = bool(args.get("can_close", true))
	closable = esc_closes
	custom_minimum_size = Vector2(1060, 0)
	var row := UITheme.hbox(18)
	add(row)
	# 头像
	var pv := PanelContainer.new()
	pv.theme_type_variation = "PortraitPanel"
	pv.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var app: Dictionary = args.get("portrait_appearance", {})
	if not app.is_empty():
		var rp := RigPreview.new()
		rp.framing = "bust"
		rp.pedestal = false
		rp.allow_zoom = false
		rp.yaw = -12.0
		rp.custom_minimum_size = Vector2(190, 210)
		rp.set_appearance(app, {}, true)
		pv.add_child(rp)
	else:
		var seal := NameSeal.new()
		seal.text = str(args.get("name", "？")).left(1)
		seal.custom_minimum_size = Vector2(190, 210)
		pv.add_child(seal)
	row.add_child(pv)
	# 正文
	var col := UITheme.vbox(8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var plate := UITheme.hbox(12)
	plate.add_child(UITheme.title(str(args.get("name", "")), 28))
	var t := str(args.get("title", ""))
	if t != "":
		var tl := UITheme.label(t, 17, UITheme.TEXT_DIM)
		tl.size_flags_vertical = Control.SIZE_SHRINK_END
		plate.add_child(tl)
	var sep := BrushLine.new()
	sep.color = Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.45)
	sep.thickness = 6.0
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.add_child(sep)
	if closable:
		plate.add_child(UITheme.icon_button("close", "离开（Esc）", close))
	col.add_child(plate)
	_text = UITheme.rich(str(args.get("text", "")), false)
	_text.custom_minimum_size = Vector2(760, 96)
	_text.add_theme_font_size_override("normal_font_size", 20)
	_text.add_theme_constant_override("line_separation", 6)
	_text.visible_characters = 0
	_text.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_finish())
	col.add_child(_text)
	col.add_child(UITheme.separator())
	_opts = UITheme.vbox(6)
	col.add_child(_opts)
	row.add_child(col)
	_options = args.get("options", [])
	if _options.is_empty():
		_options = [{"text": "告辞。", "callback": Callable()}]
	for i in _options.size():
		var o: Dictionary = _options[i]
		var b := Button.new()
		b.theme_type_variation = "ListButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%d．%s" % [i + 1, str(o.get("text", ""))]
		b.disabled = bool(o.get("disabled", false))
		b.add_theme_font_size_override("font_size", 19)
		b.custom_minimum_size.y = 40
		b.focus_mode = Control.FOCUS_NONE
		UITheme.hook_sounds(b)
		b.pressed.connect(_choose.bind(i))
		var hint := str(o.get("hint", ""))
		if hint != "":
			var hl := UITheme.label(hint, 15, UITheme.WARN if b.disabled else UITheme.TEXT_DIM)
			hl.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
			hl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			hl.position.x -= 14
			hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(hl)
			b.tooltip_text = hint
		b.modulate.a = 0.0
		_opts.add_child(b)
		_opt_buttons.append(b)
	_total = _text.get_total_character_count()
	if _total <= 0:
		_finish()


## 贴近屏幕底部
func _recenter() -> void:
	if not is_inside_tree():
		return
	var ps := get_parent_area_size()
	position = Vector2(floorf((ps.x - size.x) * 0.5), floorf(ps.y - size.y - 36.0))
	pivot_offset = size * 0.5


func _process(delta: float) -> void:
	if _done or _text == null:
		return
	_shown += delta * CHARS_PER_SEC
	_text.visible_characters = int(_shown)
	if int(_shown) % 3 == 0:
		Audio.play("ui_type", -18.0, randf_range(0.9, 1.1))
	if _shown >= _total:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_text.visible_characters = -1
	for i in _opt_buttons.size():
		var b := _opt_buttons[i]
		var tw := b.create_tween()
		tw.tween_property(b, "modulate:a", 0.45 if b.disabled else 1.0, 0.18).set_delay(i * 0.05)


func _choose(i: int) -> void:
	if is_closing() or i < 0 or i >= _options.size():
		return
	var o: Dictionary = _options[i]
	if bool(o.get("disabled", false)):
		Audio.play("ui_error")
		return
	var cb: Callable = o.get("callback", Callable())
	close()
	if cb.is_valid():
		cb.call()


func _input(event: InputEvent) -> void:
	if is_closing() or not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	if manager != null and manager.top_panel() != self:
		return
	var k := (event as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_9:
		_finish()
		_choose(k - KEY_1)
		get_viewport().set_input_as_handled()
	elif k >= KEY_KP_1 and k <= KEY_KP_9:
		_finish()
		_choose(k - KEY_KP_1)
		get_viewport().set_input_as_handled()
	elif k in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		if not _done:
			_finish()
		elif _options.size() == 1:
			_choose(0)
		get_viewport().set_input_as_handled()


## 无外貌时的名字印章头像
class NameSeal extends Control:
	var text: String = ""

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.34
		draw_circle(c, r + 10.0, Color(0, 0, 0, 0.35))
		draw_arc(c, r + 10.0, 0, TAU, 48, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.5), 1.5, true)
		var rr := Rect2(c - Vector2(r, r) * 0.78, Vector2(r, r) * 1.56)
		draw_rect(rr, Color(UITheme.CINNABAR.r, UITheme.CINNABAR.g, UITheme.CINNABAR.b, 0.2))
		draw_rect(rr, UITheme.CINNABAR, false, 3.0)
		var f := UITheme.font_title()
		var fs := int(r * 1.05)
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2(c.x - ts.x * 0.5, c.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.CINNABAR.lightened(0.2))
