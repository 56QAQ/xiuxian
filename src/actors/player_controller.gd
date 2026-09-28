class_name PlayerController
extends Node
## 玩家输入 → HumanoidActor 意图。另负责：锁定、交互、快捷丹药、打坐修炼、属性同步。

const MEDITATE_HOURS_PER_SEC := 0.5
const INTERACT_RADIUS := 3.0

var actor: HumanoidActor
var cam: CameraRig
var interact_target: Node3D = null
var _med_accum: float = 0.0
var _med_flush: float = 0.0
var _prompt: String = ""


func _ready() -> void:
	Events.player_changed.connect(_on_player_changed)
	Events.inventory_changed.connect(_on_inventory_changed)


func _ui_blocking() -> bool:
	var ui := get_tree().get_first_node_in_group("ui_manager")
	return ui != null and ui.has_method("is_blocking") and bool(ui.call("is_blocking"))


func update_intents(a: HumanoidActor, delta: float) -> void:
	actor = a
	# 打坐在打开界面时也继续进行
	if a.action == "meditate":
		_meditate_tick(delta)
	var blocked := _ui_blocking() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if blocked:
		a.in_move = Vector3.ZERO
		a.in_boost = false
		a.in_jump_held = false
		a.in_descend = false
		a.in_bolt_held = false
		_set_prompt("")
		return
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3.ZERO
	if cam != null:
		dir = cam.right_flat() * v.x - cam.forward_flat() * v.y
	a.in_move = dir.limit_length(1.0)
	a.in_boost = Input.is_action_pressed("boost")
	a.in_jump = Input.is_action_just_pressed("jump")
	a.in_jump_held = Input.is_action_pressed("jump")
	a.in_descend = Input.is_action_pressed("descend")
	a.in_qb = Input.is_action_just_pressed("quick_boost")
	a.in_melee = Input.is_action_just_pressed("melee")
	a.in_bolt = Input.is_action_just_pressed("bolt")
	a.in_bolt_held = Input.is_action_pressed("bolt")
	for i in 5:
		if Input.is_action_just_pressed("spell_%d" % (i + 1)):
			a.in_spell = i
	a.in_burst = Input.is_action_just_pressed("burst")
	if cam != null:
		a.in_aim = cam.aim_point([a.get_rid()])
		# 瞄准/施法时身体朝向镜头方向
		if a.in_bolt_held or a.charging:
			a.in_face = cam.forward_flat()
		else:
			a.in_face = Vector3.ZERO
	if Input.is_action_just_pressed("lock_on"):
		_toggle_lock(Input.is_key_pressed(KEY_TAB))
	_validate_lock()
	if Input.is_action_just_pressed("use_item"):
		use_quick_item()
	if Input.is_action_just_pressed("meditate"):
		_toggle_meditate()
	_update_interact()
	if Input.is_action_just_pressed("interact") and interact_target != null and is_instance_valid(interact_target):
		interact_target.call("interact", a)


# ================================================================ 锁定

func _toggle_lock(cycle: bool) -> void:
	if actor.lock_target != null and not cycle:
		actor.lock_target = null
		Events.lock_target_changed.emit(null)
		return
	var best := _find_lock(actor.lock_target if cycle else null)
	actor.lock_target = best
	Events.lock_target_changed.emit(best)
	if best != null:
		Audio.play("ui_click", -10.0)


func _find_lock(exclude: Node3D) -> Node3D:
	if cam == null:
		return null
	var camera := cam.camera
	var vp := camera.get_viewport().get_visible_rect().size
	var center := vp * 0.5
	var best: Node3D = null
	var best_score := INF
	var max_range := actor.combatant.stat("lock_range")
	for b in CombatUtil.bodies():
		var body := b as Node3D
		if body == actor or body == null or body == exclude:
			continue
		var c := CombatUtil.combatant_of(body)
		if c == null or not c.alive:
			continue
		var p := body.global_position + Vector3.UP
		var d := p.distance_to(actor.global_position)
		if d > max_range or camera.is_position_behind(p):
			continue
		var sp := camera.unproject_position(p)
		var off := sp.distance_to(center) / vp.y
		if off > 0.6:
			continue
		var hostile_bias := 0.0 if actor.combatant.is_hostile_to(c) else 0.35
		var score := off + d / max_range * 0.5 + hostile_bias
		if score < best_score:
			best_score = score
			best = body
	return best


func _validate_lock() -> void:
	var t := actor.lock_target
	if t == null:
		return
	var c := CombatUtil.combatant_of(t)
	if not is_instance_valid(t) or c == null or not c.alive or t.global_position.distance_to(actor.global_position) > actor.combatant.stat("lock_range") * 1.2:
		actor.lock_target = null
		Events.lock_target_changed.emit(null)


# ================================================================ 交互

func _update_interact() -> void:
	var best: Node3D = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("interactable"):
		var node := n as Node3D
		if node == null or not node.is_visible_in_tree():
			continue
		if node.has_method("can_interact") and not bool(node.call("can_interact", actor)):
			continue
		var r := float(node.get("interact_radius")) if node.get("interact_radius") != null else INTERACT_RADIUS
		var d := node.global_position.distance_to(actor.global_position)
		if d > r or d >= bd:
			continue
		best = node
		bd = d
	interact_target = best
	if best != null:
		_set_prompt("[F] " + str(best.call("interact_prompt")))
	elif actor.action == "meditate":
		_set_prompt("[T] 收功")
	else:
		_set_prompt("")


func _set_prompt(t: String) -> void:
	if t != _prompt:
		_prompt = t
		Events.interaction_prompt.emit(t)


# ================================================================ 丹药

func use_quick_item() -> void:
	var id := GS.player.quick_item
	if id == "" or GS.player.bag.count_of(id) <= 0:
		# 自动选择一枚可在战斗中使用的丹药
		id = ""
		for e in GS.player.bag.entries:
			var it: ItemInstance = e["item"]
			if it.def().get("use", {}).get("combat", false):
				id = it.id
				break
		if id == "":
			Events.notify.emit("没有可用的丹药", "warn")
			return
	if CombatItems.use(actor, id):
		GS.player.bag.take(id, 1)
		Events.inventory_changed.emit()


# ================================================================ 打坐

func _toggle_meditate() -> void:
	if actor.action == "meditate":
		actor.stop_meditate()
		_flush_meditation()
		return
	if _in_danger():
		Events.notify.emit("强敌环伺，无法静心打坐", "warn")
		return
	if actor.start_meditate():
		Events.notify.emit("盘膝而坐，运转功法……", "info")


func _in_danger() -> bool:
	if actor.combatant.since_damage < 6.0:
		return true
	return CombatUtil.nearest_hostile(actor, 25.0) != null


func _meditate_tick(delta: float) -> void:
	var h := delta * MEDITATE_HOURS_PER_SEC
	_med_accum += h
	_med_flush += delta
	var c := actor.combatant
	c.heal(c.stat("max_hp") * 0.05 * delta)
	c.restore_qi(c.stat("max_qi") * 0.2 * delta)
	if _med_flush >= 0.5:
		_flush_meditation()


func _flush_meditation() -> void:
	_med_flush = 0.0
	if _med_accum <= 0.0:
		return
	var hours := _med_accum
	_med_accum = 0.0
	var p := GS.player
	var gain := Cultivation.rate_per_hour(p, GS.stats, GS.location) * hours
	var stage_before := p.stage
	Cultivation.add_exp(p, gain, "meditate")
	if p.main_technique != "":
		GS.add_technique_xp(p.main_technique, hours)
	GS.advance_time(hours)
	if p.stage != stage_before:
		FX.shock_sphere(actor.global_position + Vector3.UP, 2.5, Color(0.9, 0.95, 1.0), 0.6)
		Audio.play("levelup")
	if Cultivation.at_bottleneck(p) and actor.action == "meditate":
		actor.stop_meditate()
		Events.notify.emit("修为已至瓶颈，需寻机突破（修炼界面）", "realm")


# ================================================================ 同步

func _on_player_changed() -> void:
	if actor == null or not is_instance_valid(actor):
		return
	actor.combatant.realm = GS.player.realm
	actor.combatant.stage = GS.player.stage
	actor.refresh_stats()


func _on_inventory_changed() -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var w := GS.player.equipped("weapon")
	var a := GS.player.equipped("armor")
	var sig := "%s|%s" % [w.id if w != null else "", a.id if a != null else ""]
	if actor.get_meta("equip_sig", "") != sig:
		actor.set_meta("equip_sig", sig)
		if actor.action == "":
			actor.rebuild_visual()
