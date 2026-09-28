class_name Nameplate
extends Node3D
## 头顶名牌（修士与妖兽）：书法名字 + 左侧境界小印（炼/筑/丹/婴/神）+ 下方境界小字；敌对者名字与印为朱砂色。
## 固定屏幕尺寸；仅在一定距离内显示（渐隐）；被玩家锁定时隐去（改由 HUD 锁定悬牌显示）。
## 由角色在生成时挂载（setup），境界/立场变化时调用 refresh()。

const SHOW_NEAR := 26.0     ## 此距离内完全显示
const SHOW_FAR := 36.0      ## 超过此距离隐藏
const PX := 0.00082         ## 固定尺寸下每“字号像素”的世界单位
const NAME_FS := 40
const SUB_FS := 24
const SEAL_PX := 46.0       ## 印章边长（字号像素）

var combatant: Combatant
var subtitle: String = ""
var label: Label3D           ## 名字
var sub_label: Label3D       ## 境界 / 称号
var seal: Sprite3D
var seal_glyph: Label3D

var _player: Node3D = null
var _check_t: float = 0.0
var _alpha: float = 0.0
var _target_alpha: float = 0.0


func setup(c: Combatant, height: float, sub: String = "") -> void:
	combatant = c
	subtitle = sub
	position = Vector3(0, height, 0)
	var fd := UITheme.font_display()
	var fb := UITheme.font_title()
	label = _make_label(fd, NAME_FS, 10)
	sub_label = _make_label(fb, SUB_FS, 7)
	sub_label.offset = Vector2(0, -NAME_FS * 0.95)
	seal = Sprite3D.new()
	seal.texture = InkArt.tex("seal_square")
	seal.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	seal.fixed_size = true
	seal.pixel_size = PX * SEAL_PX / 128.0
	seal.no_depth_test = false
	seal.shaded = false
	seal.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	seal.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	seal.render_priority = 1
	add_child(seal)
	seal_glyph = _make_label(fd, 30, 0)
	seal_glyph.render_priority = 3
	add_child(label)
	add_child(sub_label)
	add_child(seal_glyph)
	refresh()
	_set_alpha(0.0)


func _make_label(f: Font, fs: int, outline: int) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font = f
	l.font_size = fs
	l.pixel_size = PX
	l.fixed_size = true
	l.outline_size = outline
	l.outline_modulate = Color(0.04, 0.03, 0.02, 0.9)
	l.no_depth_test = false
	l.render_priority = 2
	l.outline_render_priority = 1
	return l


func refresh() -> void:
	if combatant == null or label == null:
		return
	var line2 := DB.realm_name(combatant.realm, combatant.stage)
	if subtitle != "":
		line2 = subtitle + " · " + line2
	label.text = combatant.display_name
	sub_label.text = line2
	var hostile := false
	if is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D
		var pc := CombatUtil.combatant_of(_player)
		hostile = pc != null and combatant.is_hostile_to(pc)
	var name_col := Color(1.0, 0.6, 0.5) if hostile else Color(0.97, 0.94, 0.86)
	var sub_col := Color(1.0, 0.78, 0.68) if hostile else Color(0.95, 0.84, 0.6)
	var seal_col := Color(0.8, 0.13, 0.08)
	if not hostile:
		seal_col = Color(0.55, 0.33, 0.12) if combatant.faction == "beast" else Color(0.16, 0.5, 0.4)
	label.modulate = name_col
	sub_label.modulate = sub_col
	seal.modulate = seal_col
	seal_glyph.text = InkArt.realm_glyph(combatant.realm)
	seal_glyph.modulate = Color(1.0, 0.96, 0.88)
	# 印章放在名字左侧：按名字宽度计算偏移（字号像素）
	var fd := label.font
	var nw := fd.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FS).x if fd != null else NAME_FS * 2.0
	var sx := -nw * 0.5 - SEAL_PX * 0.62
	seal.offset = Vector2(sx, 0.0) * (128.0 / SEAL_PX)
	seal_glyph.offset = Vector2(sx, 1.0)
	_apply_alpha()


func _process(delta: float) -> void:
	if combatant == null or label == null:
		return
	# 被锁定时立即隐去（悬牌接替），不等渐隐
	if _is_locked():
		if _alpha > 0.0:
			_set_alpha(0.0)
		_target_alpha = 0.0
		return
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.12
		_target_alpha = _visibility()
	var k := 1.0 - exp(-10.0 * delta)
	var a := lerpf(_alpha, _target_alpha, k)
	if absf(a - _alpha) > 0.002 or (_target_alpha == 0.0 and _alpha != 0.0):
		_set_alpha(a if absf(a - _target_alpha) > 0.01 else _target_alpha)


func _visibility() -> float:
	if not combatant.alive:
		return 0.0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return 1.0
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _is_locked():
		return 0.0
	var d := cam.global_position.distance_to(global_position)
	return 1.0 - smoothstep(SHOW_NEAR, SHOW_FAR, d)


## 被玩家锁定：由 HUD 悬牌显示名号，头顶名牌隐去以免重复
func _is_locked() -> bool:
	if _player == null or not is_instance_valid(_player):
		if not is_inside_tree():
			return false
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player is HumanoidActor and (_player as HumanoidActor).lock_target == get_parent()


func _set_alpha(a: float) -> void:
	_alpha = a
	_apply_alpha()


func _apply_alpha() -> void:
	var on := _alpha > 0.01
	for n: Node3D in [label, sub_label, seal, seal_glyph]:
		if n != null:
			n.visible = on
	if not on:
		return
	label.modulate.a = _alpha
	sub_label.modulate.a = _alpha * 0.9
	seal.modulate.a = _alpha * 0.95
	seal_glyph.modulate.a = _alpha
	label.outline_modulate.a = 0.9 * _alpha
	sub_label.outline_modulate.a = 0.8 * _alpha
