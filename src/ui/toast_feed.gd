class_name ToastFeed
extends Control
## 提示流：左侧逐条滑入的小提示；kind == "realm" 时显示居中书法横幅（境界突破等）。

const MAX_TOASTS := 7
const GLYPHS := {"info": "◇", "good": "◆", "warn": "▲", "bad": "■", "loot": "★", "realm": "◆"}

var _list: VBoxContainer
var _banner_queue: Array[String] = []
var _banner_busy: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", 6)
	_list.position = Vector2(26, 190)
	_list.custom_minimum_size = Vector2(440, 0)
	add_child(_list)


func push(text: String, kind: String = "info") -> void:
	if kind == "realm":
		_banner_queue.append(text)
		if not _banner_busy:
			_next_banner()
		return
	if _list == null:
		return
	while _list.get_child_count() >= MAX_TOASTS:
		var old := _list.get_child(0)
		_list.remove_child(old)
		old.queue_free()
	var col := UITheme.kind_color(kind)
	var wrap := MarginContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_theme_constant_override("margin_left", -30)
	var p := PanelContainer.new()
	p.theme_type_variation = "ToastPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := (UITheme.get_theme().get_stylebox("panel", "ToastPanel") as OrnateBox).duplicate() as OrnateBox
	sb.accent_color = col
	sb.bg_top = Color(col.r * 0.16, col.g * 0.16, col.b * 0.16, 0.9)
	sb.border_color = Color(col.r, col.g, col.b, 0.35)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := UITheme.label(str(GLYPHS.get(kind, "◇")), 14, col)
	h.add_child(g)
	var l := UITheme.label(text, 18, col.lerp(UITheme.TEXT, 0.35))
	if text.length() > 24:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 400
	h.add_child(l)
	p.add_child(h)
	wrap.add_child(p)
	wrap.modulate.a = 0.0
	_list.add_child(wrap)
	var life := 3.4 + text.length() * 0.04
	var tw := wrap.create_tween()
	tw.set_parallel(true)
	tw.tween_property(wrap, "modulate:a", 1.0, 0.18)
	tw.tween_method(func(v: float) -> void: wrap.add_theme_constant_override("margin_left", int(v)), -30.0, 0.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(life)
	tw.chain().tween_property(wrap, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(wrap.queue_free)


func _next_banner() -> void:
	if _banner_queue.is_empty():
		_banner_busy = false
		return
	_banner_busy = true
	var text: String = _banner_queue.pop_front()
	Audio.play("realm_up")
	var b := RealmBanner.new()
	b.text = text
	add_child(b)
	b.finished.connect(_next_banner)


## 居中书法横幅：墨痕铺开 → 金字浮现 → 停留 → 淡出
class RealmBanner extends Control:
	signal finished

	var text: String = ""
	var reveal: float = 0.0
	var _label: Label
	var _sub: Label
	var _seed: int = 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_seed = randi()

	func _ready() -> void:
		_label = Label.new()
		_label.text = text
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_override("font", UITheme.font_title())
		var fs := 60 if text.length() <= 14 else 44
		_label.add_theme_font_size_override("font_size", fs)
		_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		_label.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.02, 0.95))
		_label.add_theme_constant_override("outline_size", 10)
		_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		_label.add_theme_constant_override("shadow_offset_y", 4)
		_label.set_anchors_preset(Control.PRESET_CENTER)
		_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_label.grow_vertical = Control.GROW_DIRECTION_BOTH
		_label.position.y -= 90
		_label.modulate.a = 0.0
		add_child(_label)
		var tw := create_tween()
		tw.tween_property(self, "reveal", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_label, "modulate:a", 1.0, 0.5).set_delay(0.15)
		tw.tween_interval(2.6)
		tw.tween_property(self, "modulate:a", 0.0, 0.6)
		tw.tween_callback(func() -> void:
			finished.emit()
			queue_free())

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5 + Vector2(0, -90)
		var half_w := minf(size.x * 0.42, 560.0) * reveal
		var hh := 58.0
		if half_w < 24.0 or size.x < 64.0:
			return
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed
		# 墨痕：上下边缘参差的横带
		var top := PackedVector2Array()
		var bot := PackedVector2Array()
		var n := 40
		for i in n + 1:
			var f := float(i) / n
			var x := c.x - half_w + f * half_w * 2.0
			var taper := maxf(sin(f * PI) ** 0.35, 0.12)
			top.append(Vector2(x, c.y - hh * taper - absf(rng.randf_range(-4, 4))))
			bot.append(Vector2(x, c.y + hh * taper * 0.85 + absf(rng.randf_range(-5, 5))))
		var poly := top.duplicate()
		bot.reverse()
		poly.append_array(bot)
		var ink := Color(0.02, 0.02, 0.03, 0.78)
		draw_colored_polygon(poly, ink)
		# 金线
		var gold := Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.85)
		draw_line(Vector2(c.x - half_w * 0.9, c.y - hh - 8), Vector2(c.x + half_w * 0.9, c.y - hh - 8), gold, 1.5)
		draw_line(Vector2(c.x - half_w * 0.9, c.y + hh + 4), Vector2(c.x + half_w * 0.9, c.y + hh + 4), gold, 1.5)
		for s: float in [-1.0, 1.0]:
			var p := Vector2(c.x + s * half_w * 0.9, c.y - hh - 8)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 0), p + Vector2(0, 5), p + Vector2(-5, 0)]), gold)
			var q := Vector2(c.x + s * half_w * 0.9, c.y + hh + 4)
			draw_colored_polygon(PackedVector2Array([q + Vector2(0, -5), q + Vector2(5, 0), q + Vector2(0, 5), q + Vector2(-5, 0)]), gold)
		# 光晕
		var glow := UITheme.icon("dot")
		draw_texture_rect(glow, Rect2(c - Vector2(half_w, hh * 1.6), Vector2(half_w * 2.0, hh * 3.2)), false, Color(1.0, 0.8, 0.4, 0.12 * reveal))
