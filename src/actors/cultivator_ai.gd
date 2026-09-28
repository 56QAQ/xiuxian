class_name CultivatorAI
extends Node
## 修士 NPC 的大脑：闲逛 / 交谈 / 战斗（近战突进、游走射击、施法、瞬步闪避、服药、逃跑）。
## 与玩家使用完全相同的 HumanoidActor，只是意图来自这里。

signal state_changed(state: String)

var actor: HumanoidActor
var state: String = "wander"
var home: Vector3 = Vector3.ZERO
var wander_radius: float = 10.0
var target: Node3D = null
## aggressive / balanced / cautious
var personality: String = "balanced"
## 0~1 反应与决策水平（随境界提升）
var skill: float = 0.5
var aggro_range: float = 28.0
var leash: float = 90.0
var heal_pills: int = 2
## 为真时不会主动寻敌（路人、同门），但被攻击或有私仇时会还手
var passive: bool = true
## 跟随对象（同伴 / 护送）
var follow: Node3D = null

var _think_t: float = 0.0
var _wander_to: Vector3 = Vector3.INF
var _idle_t: float = 0.0
var _strafe: float = 1.0
var _strafe_t: float = 0.0
var _melee_style: bool = true
var _prefer: float = 3.0
var _spell_t: float = 2.0
var _dodge_cd: float = 0.0
var _attack_t: float = 0.0
var _charge_hold: float = 0.0
var _talk_face: Node3D = null


func setup(a: HumanoidActor, pers: String = "balanced") -> void:
	actor = a
	personality = pers
	home = a.global_position if a.is_inside_tree() else Vector3.ZERO
	skill = clampf(0.35 + a.pd.realm * 0.2 + a.pd.stage * 0.02 + randf_range(-0.1, 0.1), 0.2, 0.95)
	_melee_style = a.weapon_kind != "fist" or randf() < 0.5
	if personality == "cautious":
		_melee_style = randf() < 0.3
	_prefer = 2.5 if _melee_style else randf_range(11.0, 17.0)
	_strafe = 1.0 if randf() < 0.5 else -1.0


func set_state(s: String) -> void:
	if s != state:
		state = s
		state_changed.emit(s)


## 进入交谈（面向某人站定）
func talk_to(who: Node3D) -> void:
	_talk_face = who
	set_state("talk")


func end_talk() -> void:
	_talk_face = null
	set_state("wander")


func engage(t: Node3D) -> void:
	target = t
	set_state("combat")


func update_intents(a: HumanoidActor, delta: float) -> void:
	actor = a
	a.in_move = Vector3.ZERO
	a.in_boost = false
	a.in_jump_held = false
	a.in_descend = false
	a.in_bolt_held = false
	a.in_face = Vector3.ZERO
	_dodge_cd = maxf(_dodge_cd - delta, 0.0)
	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = randf_range(0.2, 0.4)
		_think()
	match state:
		"wander":
			_wander(delta)
		"talk":
			if _talk_face != null and is_instance_valid(_talk_face):
				a.in_face = _talk_face.global_position - a.global_position
		"follow":
			_follow(delta)
		"combat":
			_combat(delta)
		"flee":
			_flee(delta)
		"idle":
			pass


func _think() -> void:
	var c := actor.combatant
	if not c.alive:
		return
	if state == "talk":
		return
	if state == "combat":
		var tc := CombatUtil.combatant_of(target)
		if target == null or not is_instance_valid(target) or tc == null or not tc.alive or not c.is_hostile_to(tc):
			target = null
			actor.lock_target = null
			set_state("follow" if follow != null else "wander")
		elif actor.global_position.distance_to(home) > leash and follow == null:
			target = null
			actor.lock_target = null
			set_state("wander")
		return
	if state == "flee":
		return
	# 寻敌：主动型寻找所有敌对单位，被动型只理会对自己有私仇者
	var best: Node3D = null
	var bd := aggro_range
	for b in CombatUtil.bodies():
		var body := b as Node3D
		if body == actor or body == null:
			continue
		var bc := CombatUtil.combatant_of(body)
		if bc == null or not bc.alive or not c.is_hostile_to(bc):
			continue
		if passive and not c.grudges.has(bc.get_instance_id()) and not bc.grudges.has(c.get_instance_id()) and bc.faction != "beast" and c.nonlethal_vs != bc:
			continue
		var d := body.global_position.distance_to(actor.global_position)
		if d < bd:
			bd = d
			best = body
	if best != null:
		engage(best)


func _wander(delta: float) -> void:
	_idle_t -= delta
	if _wander_to == Vector3.INF or actor.global_position.distance_to(_wander_to) < 1.2:
		if _idle_t > 0.0:
			return
		_idle_t = randf_range(2.0, 6.0)
		var ang := randf() * TAU
		_wander_to = home + Vector3(cos(ang), 0, sin(ang)) * randf_range(2.0, wander_radius)
		return
	var to := _wander_to - actor.global_position
	to.y = 0.0
	actor.in_move = to.normalized() * 0.45
	if actor.is_on_wall() and actor.is_on_floor():
		actor.in_jump = true


func _follow(_delta: float) -> void:
	if follow == null or not is_instance_valid(follow):
		set_state("wander")
		return
	var to := follow.global_position - actor.global_position
	var d := Vector3(to.x, 0, to.z).length()
	if d > 4.0:
		actor.in_move = Vector3(to.x, 0, to.z).normalized()
		actor.in_boost = d > 14.0 and actor.combatant.qi > actor.combatant.stat("max_qi") * 0.3
	if to.y > 3.0:
		actor.in_jump_held = true


func _flee(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		set_state("wander")
		return
	var away := actor.global_position - target.global_position
	away.y = 0.0
	if away.length() > 60.0:
		target = null
		actor.lock_target = null
		home = actor.global_position
		set_state("wander")
		return
	actor.in_move = away.normalized()
	actor.in_boost = actor.combatant.qi > 10.0
	actor.lock_target = null
	if randf() < 0.02:
		actor.in_qb = true


func _combat(delta: float) -> void:
	var a := actor
	var c := a.combatant
	if target == null or not is_instance_valid(target):
		return
	a.lock_target = target
	var tc := CombatUtil.combatant_of(target)
	var to := target.global_position - a.global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	var dir := flat.normalized() if dist > 0.01 else a.forward()
	var qi_r := c.qi / maxf(c.stat("max_qi"), 1.0)
	var hp_r := c.hp_ratio()
	# 服药
	if hp_r < 0.35 and heal_pills > 0 and randf() < 0.02:
		if CombatItems.use(a, "pill_heal_small"):
			heal_pills -= 1
	# 逃跑
	var flee_at: float = {"aggressive": 0.08, "balanced": 0.18, "cautious": 0.32}.get(personality, 0.18)
	if hp_r < flee_at and c.nonlethal_vs == null and tc != null and tc.hp_ratio() > hp_r * 1.5:
		set_state("flee")
		return
	# 闪避
	if _dodge_cd <= 0.0 and qi_r > 0.2:
		if _incoming_projectile() or (target.get("action") in ["lunge", "melee", "dash"] and dist < 6.0):
			if randf() < skill * 0.55:
				var side := dir.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0)
				a.in_move = (side + (-dir * 0.4 if not _melee_style else Vector3.ZERO)).normalized()
				a.in_qb = true
				_dodge_cd = randf_range(1.2, 2.5) / maxf(skill, 0.3)
				return
			_dodge_cd = 0.6
	# 追击高空目标
	if to.y > 3.5 and qi_r > 0.25:
		a.in_jump_held = true
		if not a.grounded and to.y > 1.0:
			a.in_jump_held = true
	elif to.y < -3.0 and not a.grounded:
		a.in_descend = true
	# 移动
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.2, 3.0)
		if randf() < 0.4:
			_strafe = -_strafe
	var tangent := dir.cross(Vector3.UP) * _strafe
	if _melee_style:
		if dist > 3.2:
			a.in_move = (dir + tangent * 0.25).normalized()
			a.in_boost = dist > 9.0 and qi_r > 0.35
		else:
			a.in_move = tangent * 0.35
		# 攻击：进入突进范围即出手，连段中持续输入
		_attack_t -= delta
		var lunge_r := float(DB.moveset(a.weapon_kind).get("lunge_range", 10.0))
		if _attack_t <= 0.0 and dist < lunge_r * 0.9:
			a.in_melee = true
			_attack_t = randf_range(0.12, 0.35) if a.action == "melee" else randf_range(0.3, 1.1) / maxf(skill, 0.3)
		# 远一些时偶尔射灵气弹
		if dist > lunge_r and randf() < 0.03 and qi_r > 0.4:
			a.in_bolt = true
	else:
		var err := dist - _prefer
		var radial := dir * clampf(err / 4.0, -1.0, 1.0)
		a.in_move = (radial + tangent).normalized()
		a.in_boost = absf(err) > 6.0 and qi_r > 0.45
		if dist < 5.0 and randf() < 0.05:
			a.in_qb = true
			a.in_move = (-dir + tangent).normalized()
		# 射击：连射与蓄力
		_attack_t -= delta
		if _charge_hold > 0.0:
			_charge_hold -= delta
			a.in_bolt_held = true
		elif _attack_t <= 0.0 and qi_r > 0.25:
			if randf() < 0.18 * skill:
				_charge_hold = randf_range(0.6, 1.2)
				a.in_bolt = true
				a.in_bolt_held = true
			else:
				a.in_bolt = true
			_attack_t = randf_range(0.25, 0.6)
		if dist < 3.0 and randf() < 0.1:
			a.in_melee = true
	# 法诀
	_spell_t -= delta
	if _spell_t <= 0.0:
		_spell_t = randf_range(1.5, 4.0) / maxf(skill, 0.3)
		var slot := _pick_spell(dist, hp_r, qi_r)
		if slot >= 0:
			a.in_spell = slot
	# 翻越障碍
	if a.is_on_wall() and a.grounded:
		a.in_jump = true


func _pick_spell(dist: float, hp_r: float, qi_r: float) -> int:
	var options: Array[int] = []
	for i in actor.pd.spell_slots.size():
		var id: String = actor.pd.spell_slots[i]
		if id == "" or actor.spell_cooldown(id) > 0.0:
			continue
		var def := DB.spell(id)
		if actor.combatant.qi < float(def.get("qi", 10)) + 10.0:
			continue
		var kind := str(def.get("kind", ""))
		var p: Dictionary = def.get("params", {})
		match kind:
			"nova":
				if dist < float(p.get("radius", 5.0)):
					options.append(i)
			"dash":
				if dist < float(p.get("distance", 10.0)) and dist > 3.0:
					options.append(i)
			"shield", "heal":
				if hp_r < 0.6 or actor.combatant.shield <= 0.0:
					options.append(i)
					options.append(i)
			"buff", "summon":
				if randf() < 0.5:
					options.append(i)
			_:
				if dist < float(p.get("range", 40.0)):
					options.append(i)
	if options.is_empty():
		return -1
	return options[randi() % options.size()]


func _incoming_projectile() -> bool:
	for n in get_tree().get_nodes_in_group("projectiles"):
		var p := n as Projectile
		if p == null or p.owner_body == actor or p.owner_body == null:
			continue
		if not is_instance_valid(p.owner_body):
			continue
		var to_me := actor.global_position + Vector3.UP - p.global_position
		if to_me.length() > 14.0:
			continue
		if p.velocity.normalized().dot(to_me.normalized()) > 0.85:
			return true
	return false
