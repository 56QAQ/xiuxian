class_name DamageNumbers
extends Node3D
## 伤害跳字：监听 Events.hit_landed，在命中点生成上浮渐隐的 Label3D。

const MAX_LABELS := 48

var _font: Font


func _ready() -> void:
	_font = load("res://assets/fonts/XianKai-Medium.ttf")
	Events.hit_landed.connect(_on_hit)


func _on_hit(h: Dictionary) -> void:
	if not Settings.show_damage_numbers:
		return
	var amount := float(h.get("amount", 0.0))
	if amount < 0.5:
		return
	var cam := get_viewport().get_camera_3d()
	var pos: Vector3 = h.get("pos", Vector3.ZERO)
	if cam != null and cam.global_position.distance_to(pos) > 60.0:
		return
	if get_child_count() >= MAX_LABELS:
		get_child(0).queue_free()
	var l := Label3D.new()
	l.font = _font
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0009
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.85)
	var crit: bool = h.get("crit", false)
	var kind := str(h.get("kind", ""))
	var col := Color(1, 1, 1)
	var e := str(h.get("element", Elem.NONE))
	if Elem.is_valid(e) and kind != "melee":
		col = Elem.color_of(e).lightened(0.25)
	if h.get("shield", false):
		col = Color(0.75, 0.9, 1.0)
	if crit:
		col = Color(1.0, 0.85, 0.2)
	if CombatUtil.is_player(h.get("target", null)):
		col = Color(1.0, 0.35, 0.3)
	l.modulate = col
	l.font_size = 64 if crit else (34 if kind == "dot" else 46)
	l.text = ("暴 " if crit else "") + str(int(round(amount)))
	add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), randf_range(0.0, 0.3), randf_range(-0.3, 0.3))
	var tw := l.create_tween()
	tw.set_parallel(true)
	var rise := 1.1 if not crit else 1.5
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, rise, 0), 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if crit:
		l.scale = Vector3.ONE * 1.6
		tw.tween_property(l, "scale", Vector3.ONE, 0.18)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)
