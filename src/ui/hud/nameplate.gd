class_name Nameplate
extends Node3D
## 头顶名牌（修士与妖兽）：名字、境界、敌我着色。由角色在生成时挂载，调用 refresh() 更新。
## 表现（样式、显示距离）归 HUD/界面模块负责。

var combatant: Combatant
var subtitle: String = ""
var label: Label3D


func setup(c: Combatant, height: float, sub: String = "") -> void:
	combatant = c
	subtitle = sub
	position = Vector3(0, height, 0)
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font = load("res://assets/fonts/XianKai-Medium.ttf")
	label.font_size = 40
	label.pixel_size = 0.005
	label.outline_size = 8
	label.no_depth_test = false
	add_child(label)
	refresh()


func refresh() -> void:
	if combatant == null or label == null:
		return
	var line2 := DB.realm_name(combatant.realm, combatant.stage)
	if subtitle != "":
		line2 = subtitle + " · " + line2
	label.text = "%s\n%s" % [combatant.display_name, line2]
	var player := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	var pc := CombatUtil.combatant_of(player)
	if pc != null and combatant.is_hostile_to(pc):
		label.modulate = Color(1.0, 0.45, 0.4)
	else:
		label.modulate = Color(0.92, 0.95, 1.0)
