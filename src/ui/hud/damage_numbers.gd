class_name DamageNumbers
extends Node3D
## 伤害跳字（书法数字）：监听 Events.hit_landed，把命中点投影到屏幕，在 HUD 之下的画布层绘制。
## 普通伤害为白底墨边书法数字；五行法术带元素色；暴击为朱红大字 + 墨溅 + “暴”印；
## 玩家受伤为暗红；护体吸收为淡金；治疗为玉绿“+N”（hit_landed kind == "heal"、show_heal()，
## 或检测到玩家生命在一帧内明显回升时）。

const MAX_LABELS := 48
const LIFE := 0.95

var _layer: CanvasLayer
var _view: _NumberView
var _items: Array[Dictionary] = []


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 9
	add_child(_layer)
	_view = _NumberView.new()
	_view.owner_numbers = self
	_layer.add_child(_view)
	Events.hit_landed.connect(_on_hit)


func _on_hit(h: Dictionary) -> void:
	if not Settings.show_damage_numbers:
		return
	var amount := float(h.get("amount", 0.0))
	if amount < 0.5:
		return
	var pos: Vector3 = h.get("pos", Vector3.ZERO)
	var kind := str(h.get("kind", ""))
	if kind == "heal":
		show_heal(pos, amount)
		return
	var crit: bool = h.get("crit", false)
	var col := Color(0.98, 0.96, 0.9)
	var e := str(h.get("element", Elem.NONE))
	if Elem.is_valid(e) and kind != "melee":
		col = Elem.color_of(e).lightened(0.35)
	var style := "normal"
	if h.get("shield", false):
		col = Color(1.0, 0.9, 0.62)
		style = "shield"
	if crit:
		col = Color(1.0, 0.3, 0.18)
		style = "crit"
	if CombatUtil.is_player(h.get("target", null)):
		col = Color(0.92, 0.22, 0.16)
		style = "hurt" if not crit else "crit"
	var size := 50.0 if crit else (26.0 if kind == "dot" else 36.0)
	_spawn(pos, str(int(round(amount))), col, size, style)


## 治疗跳字（玉绿）
func show_heal(pos: Vector3, amount: float) -> void:
	if not Settings.show_damage_numbers or amount < 0.5:
		return
	_spawn(pos, "+%d" % int(round(amount)), Color(0.5, 0.96, 0.66), 34.0, "heal")


func _spawn(pos: Vector3, text: String, col: Color, size: float, style: String) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_to(pos) > 60.0:
		return
	if _items.size() >= MAX_LABELS:
		_items.pop_front()
	var jitter := Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.3), randf_range(-0.3, 0.3))
	_items.append({"pos": pos + jitter, "text": text, "col": col, "size": size, "style": style, "t": 0.0,
		"rot": randf_range(-0.5, 0.5), "dx": randf_range(-18.0, 18.0)})


func active_count() -> int:
	return _items.size()


func _process(delta: float) -> void:
	for it in _items:
		it["t"] = float(it["t"]) + delta
	_items = _items.filter(func(it: Dictionary) -> bool: return float(it["t"]) < LIFE)
	_view.queue_redraw()


## 画布：投影并绘制所有跳字
class _NumberView extends Control:
	var owner_numbers: DamageNumbers

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _draw() -> void:
		if owner_numbers == null:
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var ci := get_canvas_item()
		var s := get_viewport_rect().size.y / 1080.0
		var fd := UITheme.font_display()
		var splash := InkArt.tex("ink_splash")
		for it in owner_numbers._items:
			var pos: Vector3 = it["pos"]
			if cam.is_position_behind(pos):
				continue
			var t := float(it["t"])
			var f := t / DamageNumbers.LIFE
			var sp := cam.unproject_position(pos)
			var rise := (1.0 - pow(1.0 - minf(t / 0.6, 1.0), 3.0)) * 64.0 * s
			var style := str(it["style"])
			sp += Vector2(float(it["dx"]) * s * f, -rise - (10.0 * s if style == "crit" else 0.0))
			var alpha := 1.0 - clampf((t - 0.6) / 0.35, 0.0, 1.0)
			var pop := 1.0
			if style == "crit":
				pop = 1.0 + 0.9 * clampf(1.0 - t / 0.16, 0.0, 1.0)
			elif t < 0.08:
				pop = 1.0 + (1.0 - t / 0.08) * 0.35
			var fs := int(float(it["size"]) * s * pop)
			var col: Color = it["col"]
			col.a = alpha
			var ink := Color(0.04, 0.02, 0.02, 0.9 * alpha)
			var text := str(it["text"])
			if style == "crit":
				var ss := fs * 2.3
				RenderingServer.canvas_item_add_set_transform(ci, Transform2D(float(it["rot"]), sp + Vector2(0, -fs * 0.3)))
				InkArt.rect_tex(ci, splash, Rect2(-Vector2(ss, ss) * 0.5, Vector2(ss, ss)), Color(0.05, 0.02, 0.02, 0.62 * alpha))
				RenderingServer.canvas_item_add_set_transform(ci, Transform2D.IDENTITY)
				var w := fd.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				InkArt.seal(ci, sp + Vector2(-w * 0.5 - fs * 0.42, -fs * 0.32), fs * 0.62, "暴", Color(0.82, 0.1, 0.06, alpha), Color(1, 0.95, 0.85, alpha), false, -0.18, fd)
				InkArt.text(ci, fd, sp, text, fs, col, 1, ink, maxi(int(fs / 7.0), 3))
			elif style == "heal":
				InkArt.text(ci, fd, sp, text, fs, col, 1, Color(0.02, 0.1, 0.05, 0.9 * alpha), maxi(int(fs / 7.0), 3))
			else:
				InkArt.text(ci, fd, sp, text, fs, col, 1, ink, maxi(int(fs / 7.0), 3))
