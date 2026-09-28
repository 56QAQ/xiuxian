class_name ToastFeed
extends Control
## 提示流：左侧逐条滑入的墨痕小条（左端小印标明种类：闻/喜/警/危/得）；
## kind == "realm" 时显示居中书法横幅（一笔浓墨铺开 → 金色书法浮现 → 朱印落款）。

const MAX_TOASTS := 7
## 种类印字
const SEALS := {"info": "闻", "good": "喜", "warn": "警", "bad": "危", "loot": "得", "realm": "境"}
## 印泥色
const SEAL_COLORS := {
	"info": Color(0.24, 0.3, 0.42), "good": Color(0.16, 0.48, 0.36), "warn": Color(0.72, 0.46, 0.1),
	"bad": Color(0.76, 0.13, 0.08), "loot": Color(0.7, 0.42, 0.08), "realm": Color(0.76, 0.13, 0.08),
}

var _list: VBoxContainer
var _banner_queue: Array[String] = []
var _banner_busy: bool = false
## 合并连续相同提示
var _last_text: String = ""
var _last_label: Label
var _last_count: int = 1
var _last_time: int = 0


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
		# 只保留最新一条待显示横幅（闭关连升多层时不刷屏）
		_banner_queue = [text]
		if not _banner_busy:
			_next_banner()
		return
	if _list == null:
		return
	var now := Time.get_ticks_msec()
	if text == _last_text and is_instance_valid(_last_label) and now - _last_time < 2500:
		_last_count += 1
		_last_label.text = "%s  ×%d" % [text, _last_count]
		_last_time = now
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
	sb.brush_color = Color(col.r * 0.08 + 0.015, col.g * 0.08 + 0.015, col.b * 0.08 + 0.02, 0.86)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := InkSeal.make(str(SEALS.get(kind, "闻")), 26.0, SEAL_COLORS.get(kind, SEAL_COLORS["info"]))
	g.angle = -0.08
	h.add_child(g)
	var l := UITheme.label(text, 19, col.lerp(UITheme.TEXT, 0.4))
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.015, 0.01, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	if text.length() > 24:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 400
	h.add_child(l)
	_last_text = text
	_last_label = l
	_last_count = 1
	_last_time = now
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


## 居中书法横幅：一笔浓墨自左铺开 → 金色书法浮现（两侧祥云）→ 朱印落款 → 停留 → 淡出
class RealmBanner extends Control:
	signal finished

	var text: String = ""
	var reveal: float = 0.0
	var seal_t: float = 0.0
	var _label: Label

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _ready() -> void:
		_label = Label.new()
		_label.text = text
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_override("font", UITheme.font_display())
		var fs := 66 if text.length() <= 14 else 48
		_label.add_theme_font_size_override("font_size", fs)
		_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		_label.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.02, 0.95))
		_label.add_theme_constant_override("outline_size", 9)
		_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		_label.add_theme_constant_override("shadow_offset_y", 4)
		_label.set_anchors_preset(Control.PRESET_CENTER)
		_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_label.grow_vertical = Control.GROW_DIRECTION_BOTH
		_label.position.y -= 90
		_label.modulate.a = 0.0
		add_child(_label)
		var tw := create_tween()
		tw.tween_property(self, "reveal", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_label, "modulate:a", 1.0, 0.5).set_delay(0.18)
		tw.tween_property(self, "seal_t", 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(2.4)
		tw.tween_property(self, "modulate:a", 0.0, 0.6)
		tw.tween_callback(func() -> void:
			finished.emit()
			queue_free())

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5 + Vector2(0, -90)
		var full_w := minf(size.x * 0.84, 1180.0)
		var w := full_w * reveal
		var hh := 134.0
		if w < 24.0 or size.x < 64.0:
			return
		var ci := get_canvas_item()
		var x0 := c.x - full_w * 0.5
		# 光晕
		var glow := UITheme.icon("dot")
		draw_texture_rect(glow, Rect2(c - Vector2(full_w * 0.45, hh * 0.9), Vector2(full_w * 0.9, hh * 1.8)), false, Color(1.0, 0.75, 0.35, 0.14 * reveal))
		# 浓墨一笔（截取已铺开的部分，笔触自左向右）
		InkArt.brush_part(ci, Vector2(x0, c.y), Vector2(x0 + w, c.y), hh, Color(0.02, 0.018, 0.02, 0.86), 0.0, reveal)
		InkArt.brush_part(ci, Vector2(x0 + 30.0, c.y + 6.0), Vector2(x0 + w * 0.96, c.y + 6.0), hh * 0.55, Color(0.25, 0.04, 0.03, 0.25), 0.05, reveal)
		# 上下金线与祥云
		var gold := Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.8 * reveal)
		var lw := full_w * 0.36
		draw_line(Vector2(c.x - lw, c.y - hh * 0.46), Vector2(c.x + lw, c.y - hh * 0.46), gold, 1.5)
		draw_line(Vector2(c.x - lw, c.y + hh * 0.44), Vector2(c.x + lw, c.y + hh * 0.44), gold, 1.5)
		if _label != null:
			var tw := _label.size.x
			var bw := 120.0
			var cy := c.y - 12.0
			InkArt.cloud_band(ci, Rect2(Vector2(c.x - tw * 0.5 - bw - 18.0, cy - bw * 0.125), Vector2(bw, bw * 0.25)), Color(1.0, 0.84, 0.5, _label.modulate.a * 0.9), false)
			InkArt.cloud_band(ci, Rect2(Vector2(c.x + tw * 0.5 + 18.0, cy - bw * 0.125), Vector2(bw, bw * 0.25)), Color(1.0, 0.84, 0.5, _label.modulate.a * 0.9), true)
			# 朱印落款
			if seal_t > 0.0:
				var sz := 58.0 * (1.0 + (1.0 - seal_t) * 0.6)
				var sp := Vector2(c.x + tw * 0.5 + bw + 52.0, c.y + 18.0)
				InkArt.seal(ci, sp, sz, "问道", Color(0.8, 0.12, 0.08, seal_t), Color(1, 0.95, 0.86, seal_t), false, -0.1)
