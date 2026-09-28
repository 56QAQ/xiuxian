class_name HumanoidActor
extends CharacterBody3D
## 人形角色：玩家与修士 NPC 共用。控制器（PlayerController / CultivatorAI）每帧写入意图，
## 本类负责 AC4 式机动（疾行、瞬步、飞行、御空）、近战连段与突进、灵气弹、法诀、受击与死亡。

signal died(actor: HumanoidActor, killer: Node3D)
signal yielded(actor: HumanoidActor, winner: Node3D)

const GRAVITY := 24.0
const JUMP_VELOCITY := 9.0
const QB_SPEED := 32.0
const QB_TIME := 0.24
const QB_COST := 16.0
const QB_COOLDOWN := 0.3
const BOOST_DRAIN := 8.0
const AIR_BOOST_DRAIN := 11.0
const ASCEND_DRAIN := 14.0
const HOVER_DRAIN := 2.5
const BOLT_COST := 4.0
const BOLT_INTERVAL := 0.15
const BOLT_SPEED := 72.0
const CHARGE_START := 0.28
const CHARGE_FULL := 1.1
const BODY_RADIUS := 0.35
const BODY_HEIGHT := 1.72

var combatant: Combatant
var rig: CharacterRig
var controller: Node
var pd: PlayerData
var appearance: Dictionary = {}
var weapon_kind: String = "fist"
var weapon_element: String = Elem.NONE
var bolt_element: String = Elem.NONE
var is_player: bool = false
var trail: WeaponTrail
var nameplate: Nameplate

# ---------------------------------------------------------------- 意图（控制器写入）
var in_move: Vector3 = Vector3.ZERO
var in_face: Vector3 = Vector3.ZERO
var in_aim: Vector3 = Vector3.ZERO
var in_jump: bool = false
var in_jump_held: bool = false
var in_descend: bool = false
var in_boost: bool = false
var in_qb: bool = false
var in_melee: bool = false
var in_bolt: bool = false
var in_bolt_held: bool = false
var in_spell: int = -1
var in_burst: bool = false
var burst_cd: float = 0.0
var lock_target: Node3D = null

# ---------------------------------------------------------------- 状态
var boosting: bool = false
var hovering: bool = false
var ascending: bool = false
var grounded: bool = true
var evading: float = 0.0
var action: String = ""
var action_time: float = 0.0
var action_len: float = 0.0
var combo_index: int = -1
var combo_queued: bool = false
var combo_reset: float = 0.0
var step: Dictionary = {}
var _hit_done: bool = false
var qb_timer: float = 0.0
var qb_cd: float = 0.0
var qb_dir: Vector3 = Vector3.ZERO
var knock_t: float = 0.0   ## 受击击退期间降低操控
var bolt_cd: float = 0.0
var charge_t: float = 0.0
var charging: bool = false
var _bolt_was_held: bool = false
var spell_cd: Dictionary = {}
var cast_def: Dictionary = {}
var cast_level: int = 0
var cast_fired: bool = false
var cast_fire_at: float = 0.0
var dash: Dictionary = {}
var lunge: Dictionary = {}
var stagger_t: float = 0.0
var _last_jump_press: float = -10.0
var _air_time: float = 0.0
var _prev_vy: float = 0.0
var _yaw: float = 0.0
var _foot_t: float = 0.0
var channel_t: float = 0.0


func _init() -> void:
	collision_layer = 1 << 2
	collision_mask = 1
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50.0)
	add_to_group("combatants")


## 构建角色。pd: 该角色的 PlayerData；faction: 阵营
func setup(player_data: PlayerData, faction: String, player: bool = false) -> void:
	pd = player_data
	is_player = player
	appearance = pd.appearance
	if player:
		collision_layer = 1 << 1
		add_to_group("player")
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = BODY_RADIUS
	cap.height = BODY_HEIGHT
	shape.shape = cap
	shape.position = Vector3(0, BODY_HEIGHT * 0.5, 0)
	add_child(shape)
	combatant = Combatant.new()
	combatant.name = "Combatant"
	add_child(combatant)
	combatant.display_name = pd.name
	combatant.faction = faction
	var st := GS.stats if player else BuildCalc.compute(pd)
	combatant.setup(st, pd.realm, pd.stage, pd.main_element(), pd)
	combatant.damaged.connect(_on_damaged)
	combatant.died.connect(_on_died)
	combatant.shield_broken.connect(_on_shield_broken)
	combatant.poise_broken.connect(_on_poise_broken)
	combatant.yielded.connect(_on_yielded)
	rebuild_visual()
	trail = WeaponTrail.new()
	add_child(trail)
	trail.rig = rig
	if not player:
		_make_nameplate()


## 重新生成外观（换装后调用）
func rebuild_visual() -> void:
	if rig != null:
		rig.queue_free()
	var w := pd.equipped("weapon")
	var ev := {}
	weapon_kind = pd.weapon_kind()
	weapon_element = Elem.NONE
	if w != null:
		ev["weapon"] = w.def().get("weapon", {}).get("visual", {"kind": weapon_kind})
		weapon_element = w.element()
	var armor := pd.equipped("armor")
	# 凡品法衣不覆盖捏人时选择的服饰外观；灵品以上的法衣/战甲才改变外观
	if armor != null and armor.get_grade() >= 1 and armor.def().get("equip", {}).has("visual"):
		ev["outfit"] = armor.def()["equip"]["visual"]
	rig = CharacterBuilder.build(appearance, ev)
	rig.stance = weapon_kind
	add_child(rig)
	rig.anim_event.connect(_on_anim_event)
	if trail != null:
		trail.rig = rig
	var tech := DB.technique(pd.main_technique)
	bolt_element = str(tech.get("element", Elem.NONE))
	if not Elem.is_valid(bolt_element):
		bolt_element = pd.main_element()


func refresh_stats() -> void:
	combatant.refresh_stats(GS.stats if is_player else BuildCalc.compute(pd))


func _make_nameplate() -> void:
	nameplate = Nameplate.new()
	nameplate.name = "Nameplate"
	add_child(nameplate)
	nameplate.setup(combatant, 2.25)


func update_nameplate() -> void:
	if nameplate != null:
		nameplate.refresh()


# ================================================================ 查询

func forward() -> Vector3:
	return -global_basis.z


func aim_point() -> Vector3:
	if lock_target != null and is_instance_valid(lock_target):
		return lock_target.global_position + Vector3.UP
	if in_aim != Vector3.ZERO:
		return in_aim
	return global_position + Vector3.UP + forward() * 30.0


func cast_origin() -> Vector3:
	var h := rig.bone("hand_r") if rig != null else null
	if h != null:
		return h.global_position + forward() * 0.3
	return global_position + Vector3.UP * 1.3 + forward() * 0.6


func can_act() -> bool:
	return combatant.alive and action not in ["stagger", "dead", "meditate", "channel"]


func is_busy() -> bool:
	return action != ""


# ================================================================ 主循环

func _physics_process(delta: float) -> void:
	if combatant == null:
		return
	if controller != null and combatant.alive and controller.has_method("update_intents"):
		controller.call("update_intents", self, delta)
	_timers(delta)
	if combatant.alive:
		_actions(delta)
	_move(delta)
	_face(delta)
	_update_rig()
	in_jump = false
	in_qb = false
	in_melee = false
	in_bolt = false
	in_spell = -1
	in_burst = false


func _timers(delta: float) -> void:
	qb_timer = maxf(qb_timer - delta, 0.0)
	qb_cd = maxf(qb_cd - delta, 0.0)
	evading = maxf(evading - delta, 0.0)
	bolt_cd = maxf(bolt_cd - delta, 0.0)
	combo_reset = maxf(combo_reset - delta, 0.0)
	burst_cd = maxf(burst_cd - delta, 0.0)
	for k in spell_cd.keys():
		spell_cd[k] = float(spell_cd[k]) - delta
		if spell_cd[k] <= 0.0:
			spell_cd.erase(k)
	if action != "":
		action_time += delta


# ================================================================ 行动

func _actions(delta: float) -> void:
	match action:
		"melee":
			if combo_queued and action_time >= action_len * float(step.get("cancel", 0.6)):
				_next_combo()
			elif action_time >= action_len:
				_end_action()
				combo_reset = 0.4
		"cast":
			if not cast_fired and action_time >= cast_fire_at:
				_fire_spell()
			if action_time >= maxf(action_len * 0.75, cast_fire_at + 0.15):
				_end_action()
		"stagger":
			stagger_t -= delta
			if stagger_t <= 0.0:
				_end_action()
		"lunge":
			_lunge_update(delta)
		"dash":
			_dash_update(delta)
		"channel":
			channel_t -= delta
			if channel_t <= 0.0:
				_end_action()
		"meditate":
			if in_move.length() > 0.2 or in_jump or in_melee or in_bolt:
				stop_meditate()
	# 输入 → 行动
	if not can_act():
		charging = false
		return
	if in_qb:
		quick_boost()
	if in_melee:
		try_melee()
	if in_spell >= 0:
		try_cast(in_spell)
	if in_burst:
		try_burst()
	_bolt_logic(delta)


func _end_action() -> void:
	if action == "melee" or action == "lunge" or action == "dash":
		trail.stop()
	action = ""
	action_time = 0.0
	step = {}


# ---------------------------------------------------------------- 近战

func try_melee() -> void:
	var ms := DB.moveset(weapon_kind)
	if ms.is_empty():
		return
	if action == "melee":
		combo_queued = true
		return
	if action != "":
		return
	var combo: Array = ms["combo"]
	var idx := 0
	if combo_reset > 0.0 and combo_index >= 0:
		idx = (combo_index + 1) % combo.size()
	_begin_step(idx, true)


func _next_combo() -> void:
	var ms := DB.moveset(weapon_kind)
	var combo: Array = ms["combo"]
	_begin_step((combo_index + 1) % combo.size(), true)


func _begin_step(idx: int, allow_lunge: bool) -> void:
	var ms := DB.moveset(weapon_kind)
	var combo: Array = ms["combo"]
	var s: Dictionary = combo[idx]
	combo_index = idx
	combo_queued = false
	var tgt := _melee_target(float(ms.get("lunge_range", 12.0)))
	if allow_lunge and tgt != null and s.get("lunge", false):
		var d := _flat_dist(tgt)
		if d > float(s["range"]) * 0.85:
			lunge = {"target": tgt, "speed": float(ms.get("lunge_speed", 34.0)), "t": 0.0, "max_t": d / float(ms.get("lunge_speed", 34.0)) + 0.2, "idx": idx}
			action = "lunge"
			action_time = 0.0
			step = s
			evading = 0.15
			Audio.play_at("quick_boost", global_position, -4.0)
			FX.ring(global_position + Vector3.UP * 0.9, 1.2, _elem_color(), 0.25, 0.15, forward())
			return
	_start_swing(s)


func _start_swing(s: Dictionary) -> void:
	step = s
	action = "melee"
	action_time = 0.0
	_hit_done = false
	var spd := 1.0
	action_len = rig.play(str(s["clip"]), spd)
	trail.start(_elem_color().lightened(0.35))
	Audio.play_at("swing_heavy" if s.get("heavy", false) else "swing_light", global_position, -2.0)
	_impulse(forward() * (3.5 if not s.get("heavy", false) else 5.0), 0.1)
	# 近距离时面向目标
	var tgt := _melee_target(6.0)
	if tgt != null:
		var to := tgt.global_position - global_position
		to.y = 0.0
		if to.length() > 0.1:
			_yaw = atan2(-to.x, -to.z)
			rotation.y = _yaw


func _lunge_update(delta: float) -> void:
	var tgt: Node3D = lunge.get("target", null)
	lunge["t"] = float(lunge["t"]) + delta
	if tgt == null or not is_instance_valid(tgt) or float(lunge["t"]) > float(lunge["max_t"]):
		_start_swing(step)
		return
	var to := tgt.global_position - global_position
	var flat := Vector3(to.x, 0, to.z)
	if flat.length() <= float(step["range"]) * 0.7:
		velocity = Vector3.ZERO
		_start_swing(step)
		return
	var dir := to.normalized()
	velocity = dir * float(lunge["speed"])
	_yaw = atan2(-flat.x, -flat.z)
	rotation.y = _yaw


func _melee_target(max_range: float) -> Node3D:
	if lock_target != null and is_instance_valid(lock_target) and CombatUtil.combatant_of(lock_target) != null and CombatUtil.combatant_of(lock_target).alive:
		if global_position.distance_to(lock_target.global_position) <= max_range:
			return lock_target
		return null
	# 软锁定：前方锥形内最近的敌人
	var best: Node3D = null
	var bd := minf(max_range, 7.0)
	for b in CombatUtil.bodies():
		var body := b as Node3D
		if body == self or body == null or not CombatUtil.can_damage(self, body):
			continue
		var to := body.global_position - global_position
		var d := to.length()
		if d > bd:
			continue
		var fl := Vector3(to.x, 0, to.z)
		var face := forward() if in_move.length() < 0.1 else in_move.normalized()
		if fl.length() > 0.5 and rad_to_deg(face.angle_to(fl)) > 60.0:
			continue
		bd = d
		best = body
	return best


func _melee_hit() -> void:
	if step.is_empty():
		return
	var rng := float(step.get("range", 2.8))
	var arc := float(step.get("arc", 120.0))
	var origin := global_position + Vector3.UP * 1.0
	var fwd := forward()
	var heavy: bool = step.get("heavy", false)
	var any := false
	for b in CombatUtil.bodies():
		var body := b as Node3D
		if body == self or body == null or not CombatUtil.can_damage(self, body):
			continue
		var to := body.global_position + Vector3.UP * 0.9 - origin
		if absf(to.y) > 2.2:
			continue
		var flat := Vector3(to.x, 0, to.z)
		if flat.length() > rng + BODY_RADIUS + 0.2:
			continue
		if flat.length() > 0.8 and rad_to_deg(fwd.angle_to(flat)) > arc * 0.5:
			continue
		var info := {
			"kind": "melee", "mult": float(step.get("dmg", 1.0)), "weapon": weapon_kind,
			"element": weapon_element if Elem.is_valid(weapon_element) else Elem.NONE,
			"poise": float(step.get("poise", 15.0)), "knock": float(step.get("knock", 2.0)),
			"launch": float(step.get("launch", 0.0)), "heavy": heavy,
			"dir": flat.normalized() if flat.length() > 0.05 else fwd,
			"point": body.global_position + Vector3.UP * 1.1,
		}
		if Elem.is_valid(weapon_element) and randf() < 0.25:
			info["status"] = {"id": Elem.STATUS[weapon_element], "stacks": 1 if weapon_element != Elem.WATER else 12, "chance": 1.0}
		var res := CombatUtil.hit(self, body, info)
		if not res.is_empty():
			any = true
			var col := _elem_color()
			FX.burst(info["point"], col.lightened(0.3), 14 if heavy else 8, 7.0, 0.08, 0.35)
			Audio.play_at("hit_shield" if res.get("shield_damage", 0.0) > 0.0 and res.get("hp_damage", 0.0) <= 0.0 else "hit_flesh", info["point"])
			if res.get("crit", false):
				Audio.play_at("crit", info["point"], -2.0)
	# 场景破坏
	CombatUtil.damage_destructibles(origin + fwd * rng * 0.6, 0.6 + (0.6 if heavy else 0.0), float(step.get("dmg", 1.0)) * (22.0 if heavy else 12.0))


func _on_anim_event(ev: String) -> void:
	match ev:
		"hit":
			if action == "melee" and not _hit_done:
				_hit_done = true
				_melee_hit()
			elif action == "cast" and not cast_fired:
				_fire_spell()
		"cast":
			if action == "cast" and not cast_fired:
				_fire_spell()


# ---------------------------------------------------------------- 灵气弹

func _bolt_logic(delta: float) -> void:
	if action not in ["", "cast"] and not (action == "melee" and action_time > action_len * 0.5):
		_bolt_was_held = in_bolt_held
		charging = false
		return
	if in_bolt and bolt_cd <= 0.0:
		fire_bolt(1.0)
		charge_t = 0.0
	if in_bolt_held:
		charge_t += delta
		if charge_t >= CHARGE_START and not charging:
			charging = true
			rig.play("charge")
			Audio.play_at("bolt_charge", global_position, -6.0)
		if charging and randf() < 0.3:
			FX.sparkle(_bolt_origin(), Elem.color_of(bolt_element) if Elem.is_valid(bolt_element) else Color(0.8, 0.9, 1), 2)
	elif _bolt_was_held and charging:
		var f := clampf((charge_t - CHARGE_START) / (CHARGE_FULL - CHARGE_START), 0.0, 1.0)
		rig.stop_action()
		fire_bolt(1.0 + f * 1.6)
		charging = false
		charge_t = 0.0
	else:
		charging = false
	_bolt_was_held = in_bolt_held


func charge_ratio() -> float:
	if not charging:
		return 0.0
	return clampf((charge_t - CHARGE_START) / (CHARGE_FULL - CHARGE_START), 0.0, 1.0)


func _bolt_origin() -> Vector3:
	var h := rig.bone("hand_l") if rig != null else null
	if h != null:
		return h.global_position + forward() * 0.25
	return global_position + Vector3.UP * 1.3


func fire_bolt(charge: float) -> void:
	var cost := BOLT_COST * (1.0 + (charge - 1.0) * 2.2)
	if not combatant.spend_qi(cost):
		if is_player:
			Audio.play("error", -8.0)
		return
	combatant.qi_block = 0.25
	bolt_cd = BOLT_INTERVAL
	var origin := _bolt_origin()
	var aim: Vector3
	var tgt: Node3D = lock_target if lock_target != null and is_instance_valid(lock_target) else null
	if tgt != null:
		aim = CombatUtil.lead_point(origin, tgt, BOLT_SPEED)
	else:
		aim = aim_point()
	var info := {"kind": "bolt", "mult": 0.33 * pow(charge, 1.6), "element": bolt_element, "poise": 3.0 * charge * charge, "knock": 1.0 * charge}
	if Elem.is_valid(bolt_element) and randf() < 0.15 * charge:
		info["status"] = {"id": Elem.STATUS[bolt_element], "stacks": 1 if bolt_element != Elem.WATER else 10, "chance": 1.0}
	Projectile.spawn({
		"owner": self, "pos": origin, "dir": (aim - origin).normalized(), "speed": BOLT_SPEED,
		"size": 0.14 * pow(charge, 1.3), "range": 90.0, "homing": 0.3 if tgt != null else 0.0, "target": tgt,
		"pierce": 1 if charge > 2.0 else 0, "explode": 2.2 if charge > 2.4 else 0.0,
		"info": info, "element": bolt_element,
	})
	if action == "":
		rig.play("bolt")
	Audio.play_at("bolt_fire", origin, -6.0 if charge < 1.5 else 0.0)


# ---------------------------------------------------------------- 法诀

func try_cast(slot: int) -> bool:
	if slot < 0 or slot >= pd.spell_slots.size():
		return false
	var id: String = pd.spell_slots[slot]
	if id == "":
		return false
	return cast_spell(id)


func cast_spell(id: String, free_cast: bool = false) -> bool:
	var def := DB.spell(id)
	if def.is_empty() or action not in ["", "melee"]:
		return false
	if action == "melee" and action_time < action_len * float(step.get("cancel", 0.6)):
		return false
	if spell_cd.has(id) and not free_cast:
		if is_player:
			Audio.play("error", -8.0)
		return false
	if not free_cast and not combatant.spend_qi(float(def.get("qi", 10))):
		if is_player:
			Events.notify.emit("灵力不足", "warn")
			Audio.play("error", -6.0)
		return false
	if not free_cast:
		spell_cd[id] = float(def.get("cd", 3.0)) * (1.0 - combatant.stat("cdr"))
	combatant.qi_block = 0.3
	trail.stop()
	cast_def = def
	cast_level = pd.spell_level(id) if pd != null else 0
	cast_fired = false
	action = "cast"
	action_time = 0.0
	var anim := str(def.get("anim", "cast_forward"))
	action_len = rig.play(anim) if AnimLib.has_clip(anim) else 0.4
	cast_fire_at = maxf(float(def.get("cast_time", 0.15)), 0.05)
	if str(def.get("kind", "")) == "dash":
		cast_fire_at = 0.02
	# 施法时面向目标
	if lock_target != null and is_instance_valid(lock_target):
		var to := lock_target.global_position - global_position
		_yaw = atan2(-to.x, -to.z)
		rotation.y = _yaw
	FX.sparkle(cast_origin(), SpellRuntime.color_of(def), 12)
	Audio.play_at("cast", global_position, -6.0)
	if is_player:
		GS.add_spell_xp(id, 1.0)
	return true


func _fire_spell() -> void:
	if cast_fired or cast_def.is_empty():
		return
	cast_fired = true
	SpellRuntime.execute(self, cast_def, cast_level)


func spell_cooldown(id: String) -> float:
	return float(spell_cd.get(id, 0.0))


## 冲刺类法诀（锐金斩）
func start_dash(dir: Vector3, distance: float, speed: float, width: float, info: Dictionary, color: Color) -> void:
	dash = {"dir": dir.normalized(), "left": distance, "speed": speed, "width": width, "info": info, "hit": {}, "color": color}
	action = "dash"
	action_time = 0.0
	evading = distance / speed + 0.1
	trail.start(color)
	FX.ring(global_position + Vector3.UP, 1.5, color, 0.25, 0.2, dir)


func _dash_update(delta: float) -> void:
	var move := float(dash["speed"]) * delta
	dash["left"] = float(dash["left"]) - move
	velocity = (dash["dir"] as Vector3) * float(dash["speed"])
	var from := global_position + Vector3.UP
	for b in CombatUtil.bodies():
		var body := b as Node3D
		if body == self or body == null or (dash["hit"] as Dictionary).has(body.get_instance_id()):
			continue
		if not CombatUtil.can_damage(self, body):
			continue
		if (body.global_position + Vector3.UP).distance_to(from) <= float(dash["width"]) + move:
			dash["hit"][body.get_instance_id()] = true
			var info: Dictionary = (dash["info"] as Dictionary).duplicate()
			info["dir"] = dash["dir"]
			info["heavy"] = true
			CombatUtil.hit(self, body, info)
			FX.burst(body.global_position + Vector3.UP, dash["color"], 16, 8.0, 0.1, 0.4)
	if randf() < 0.6:
		FX.burst(global_position + Vector3.UP, dash["color"], 3, 1.0, 0.1, 0.3, true, 0.0)
	if float(dash["left"]) <= 0.0 or is_on_wall():
		velocity = (dash["dir"] as Vector3) * 4.0
		_end_action()


## 金丹爆发：灵力充盈时引爆金丹之力（大范围冲击 + 狂火）
func try_burst() -> bool:
	if not BuildCalc.has_perk(pd, "core_burst") or burst_cd > 0.0 or action in ["stagger", "dead", "dash"]:
		return false
	if combatant.qi < combatant.stat("max_qi") * 0.9:
		if is_player:
			Events.notify.emit("灵力未满，无法引爆金丹", "warn")
		return false
	combatant.qi = 0.0
	burst_cd = 60.0
	var e := pd.main_element()
	var col := Elem.color_of(e)
	rig.play("cast_ground")
	var info := {"kind": "spell", "mult": 3.5, "element": e, "poise": 150.0, "knock": 14.0, "launch": 6.0, "heavy": true}
	CombatUtil.aoe(self, global_position + Vector3.UP, 11.0, info)
	CombatUtil.damage_destructibles(global_position, 6.0, 120.0)
	CombatUtil.crater(global_position + forward() * 3.0, 4.0)
	FX.shock_sphere(global_position + Vector3.UP, 11.0, col, 0.5)
	FX.ring(global_position + Vector3.UP * 0.2, 13.0, col, 0.6, 0.3)
	FX.burst(global_position + Vector3.UP, col, 60, 16.0, 0.2, 1.0)
	FX.flash_light(global_position + Vector3.UP * 2.0, col, 10.0, 25.0, 0.5)
	combatant.apply_status("fury", 1.0, combatant)
	Audio.play_at("explosion", global_position, 4.0)
	Audio.play_at("thunder", global_position)
	if is_player:
		CombatUtil.shake(1.0)
		HitStop.trigger(0.12, 0.05)
		Events.notify.emit("金丹爆发！", "realm")
	return true


func begin_channel(t: float) -> void:
	action = "channel"
	channel_t = t
	action_time = 0.0


# ---------------------------------------------------------------- 机动

func quick_boost() -> void:
	if qb_cd > 0.0 or combatant.is_rooted() or combatant.has_status("qi_burnout") or action in ["stagger", "dead", "dash"]:
		return
	var cost := QB_COST * combatant.stat("qb_cost")
	if not combatant.spend_qi(cost):
		if is_player:
			Audio.play("error", -8.0)
		return
	combatant.qi_block = 0.4
	var dir := in_move
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = -forward()
	qb_dir = dir.normalized()
	qb_timer = QB_TIME
	qb_cd = QB_COOLDOWN
	evading = 0.25
	if action in ["melee", "cast", "lunge"]:
		rig.stop_action()
		_end_action()
	if not grounded and velocity.y < 0.0:
		velocity.y = 0.0
	Audio.play_at("quick_boost", global_position)
	FX.ring(global_position + Vector3.UP * 0.9, 1.4, Color(0.85, 0.95, 1.0), 0.22, 0.12, qb_dir)
	FX.burst(global_position + Vector3.UP * 0.5, Color(0.9, 0.95, 1.0), 10, 5.0, 0.07, 0.3)


func _move(delta: float) -> void:
	var st := combatant.stats
	var was_grounded := grounded
	grounded = is_on_floor()
	if action == "dead":
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	if action == "lunge" or action == "dash":
		move_and_slide()
		return
	var rooted := combatant.is_rooted()
	var burnout := combatant.has_status("qi_burnout")
	var mscale := 1.0
	match action:
		"melee":
			mscale = 0.12
		"cast", "channel":
			mscale = 0.5
		"stagger", "meditate":
			mscale = 0.0
	if rooted:
		mscale = 0.0
	# 疾行
	var want_boost := in_boost and not burnout and mscale > 0.0 and (in_move.length() > 0.1 or not grounded)
	var was_boosting := boosting
	boosting = false
	if want_boost:
		var drain := (BOOST_DRAIN if grounded else AIR_BOOST_DRAIN) * float(st["boost_cost"]) * delta
		boosting = combatant.drain_qi(drain)
	if boosting and not was_boosting:
		Audio.play_at("boost_start", global_position, -4.0)
		if grounded:
			FX.dust(global_position, 8)
	var speed := float(st["boost_speed"]) if boosting else float(st["move_speed"])
	speed *= mscale
	var target_h := in_move * speed
	var h := Vector3(velocity.x, 0, velocity.z)
	var accel := 70.0 if grounded else 28.0
	if boosting:
		accel = 55.0
	if h.length() > speed + 0.5:
		accel = 22.0 if grounded else 9.0  # 保留高速惯性
	if knock_t > 0.0:
		knock_t -= delta
		accel = 10.0
	h = h.move_toward(target_h, accel * delta)
	if qb_timer > 0.0:
		var f := qb_timer / QB_TIME
		h = qb_dir * lerpf(maxf(speed, 6.0), QB_SPEED, f * f) + h * (1.0 - f) * 0.2
	# 垂直
	var vy := velocity.y
	ascending = false
	var can_fly := mscale > 0.0 and not burnout
	if in_jump:
		var now := Time.get_ticks_msec() / 1000.0
		if not grounded and now - _last_jump_press < 0.32 and BuildCalc.has_perk(pd, "hover"):
			hovering = not hovering
			if is_player:
				Events.notify.emit("御空" if hovering else "解除御空", "info")
		_last_jump_press = now
	if hovering:
		if grounded and not in_jump_held:
			hovering = false
		var tvy := 0.0
		if in_jump_held and can_fly:
			tvy = 8.0
		elif in_descend:
			tvy = -10.0
		vy = move_toward(vy, tvy, 30.0 * delta)
		var hd := HOVER_DRAIN * float(st["flight_cost"]) * delta
		if tvy > 0.0:
			hd += ASCEND_DRAIN * 0.5 * float(st["flight_cost"]) * delta
		if not combatant.drain_qi(hd):
			hovering = false
	elif grounded:
		_air_time = 0.0
		if in_jump and mscale > 0.0:
			vy = JUMP_VELOCITY
			Audio.play_at("jump", global_position, -8.0)
		elif vy < 0.0:
			vy = 0.0
	else:
		_air_time += delta
		if boosting:
			vy = move_toward(vy, 0.0, 26.0 * delta)
		elif in_jump_held and can_fly and _air_time > 0.08:
			if combatant.drain_qi(ASCEND_DRAIN * float(st["flight_cost"]) * delta):
				vy = move_toward(vy, 9.0, 42.0 * delta)
				ascending = true
			else:
				vy -= GRAVITY * delta
		else:
			vy -= GRAVITY * delta
		if in_descend:
			vy = move_toward(vy, -24.0, 60.0 * delta)
	if action == "stagger":
		vy = minf(vy, velocity.y)
	velocity = h + Vector3.UP * vy
	_prev_vy = velocity.y
	move_and_slide()
	# 落地
	if is_on_floor() and not was_grounded and _prev_vy < -11.0:
		Audio.play_at("land", global_position, -4.0)
		FX.dust(global_position, 10)
		if is_player and _prev_vy < -18.0:
			CombatUtil.shake(0.2)
	# 脚步
	if grounded and h.length() > 2.0 and not boosting:
		_foot_t -= delta * h.length() * 0.35
		if _foot_t <= 0.0:
			_foot_t = 1.0
			if is_player:
				Audio.play_at("footstep", global_position, -14.0)
	if boosting and grounded and randf() < 0.3:
		FX.dust(global_position, 2)


func _face(delta: float) -> void:
	if action in ["dead", "lunge", "dash", "meditate"]:
		return
	var want := Vector3.ZERO
	if lock_target != null and is_instance_valid(lock_target):
		want = lock_target.global_position - global_position
	elif in_face != Vector3.ZERO:
		want = in_face
	elif action in ["melee", "cast", "stagger"]:
		return
	elif charging or bolt_cd > 0.0:
		want = aim_point() - global_position
	else:
		var h := Vector3(velocity.x, 0, velocity.z)
		if h.length() > 0.8 and in_move.length() > 0.1:
			want = h
	want.y = 0.0
	if want.length() < 0.05:
		return
	var target_yaw := atan2(-want.x, -want.z)
	var rate := 14.0 if not boosting else 9.0
	if action == "melee":
		rate = 4.0
	_yaw = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-rate * delta))
	rotation.y = _yaw


## 战斗姿态计时：出手、受击、锁定时刷新；归零后收起架势（放松站姿）
var _combat_t: float = 0.0


func _update_rig() -> void:
	if rig == null:
		return
	if lock_target != null or action in ["melee", "lunge", "cast", "dash", "stagger"] or charging or combatant.since_damage < 1.0:
		_combat_t = 8.0
	else:
		_combat_t = maxf(_combat_t - get_physics_process_delta_time(), 0.0)
	rig.stance = weapon_kind if _combat_t > 0.0 else "none"
	var local := global_basis.inverse() * velocity
	rig.set_locomotion(local, grounded and not hovering, boosting or qb_timer > 0.0, hovering or ascending)


# ================================================================ 受击 / 死亡

func on_hit(info: Dictionary, res: Dictionary) -> void:
	if not combatant.alive and not res.get("killed", false):
		return
	if info.get("no_react", false):
		if not res.get("killed", false):
			rig.flash(0.35, Color(1, 0.8, 0.8))
			return
	rig.flash(0.45 if is_player else 0.85)
	var dir: Vector3 = info.get("dir", -forward())
	var knock := float(info.get("knock", 0.0))
	var resist := clampf(combatant.poise / maxf(combatant.stat("poise"), 1.0), 0.3, 1.0)
	_impulse(dir * knock * (1.3 - resist * 0.6), 0.22)
	var launch := float(info.get("launch", 0.0))
	if launch > 0.0:
		velocity.y = launch
	if res.get("killed", false):
		return
	if action == "meditate":
		stop_meditate()
	if action == "" and not res.get("broke_poise", false):
		rig.play("hit_front")


func _on_damaged(_info: Dictionary, _res: Dictionary) -> void:
	pass


func _on_shield_broken() -> void:
	Audio.play_at("shield_break", global_position)
	FX.shock_sphere(global_position + Vector3.UP, 1.3, Color(1.0, 0.95, 0.7), 0.25)
	FX.burst(global_position + Vector3.UP, Color(1.0, 0.92, 0.6), 18, 7.0, 0.06, 0.5)
	if action in ["", "cast"]:
		_stagger(0.3)


func _on_poise_broken() -> void:
	_stagger(0.75)


func _stagger(t: float) -> void:
	if not combatant.alive or action == "dead":
		return
	if action == "meditate":
		stop_meditate()
	trail.stop()
	action = "stagger"
	stagger_t = t
	action_time = 0.0
	hovering = false
	rig.play("stagger", 0.7 / maxf(t, 0.2))


func _on_died(killer: Combatant) -> void:
	action = "dead"
	boosting = false
	hovering = false
	charging = false
	trail.stop()
	rig.meditating = false
	rig.play("death")
	collision_layer = 0
	Audio.play_at("death", global_position)
	died.emit(self, killer.body() if killer != null else null)
	if nameplate != null:
		nameplate.visible = false
	if not is_player:
		var tw := create_tween()
		tw.tween_interval(20.0)
		tw.tween_method(func(v: float) -> void: rig.set_dissolve(v), 0.0, 1.0, 1.5)
		tw.tween_callback(queue_free)


func _on_yielded(winner: Combatant) -> void:
	_end_action()
	action = "stagger"
	stagger_t = 1.2
	rig.play("salute")
	yielded.emit(self, winner.body() if winner != null else null)


# ================================================================ 打坐

func start_meditate() -> bool:
	if action != "" or not grounded:
		return false
	action = "meditate"
	action_time = 0.0
	rig.meditating = true
	velocity = Vector3.ZERO
	return true


func stop_meditate() -> void:
	if action == "meditate":
		action = ""
	rig.meditating = false


# ================================================================ 工具

## 一次性速度冲量（击退、出招前冲），期间短暂降低操控
func _impulse(v: Vector3, t: float) -> void:
	velocity += v
	knock_t = maxf(knock_t, t)


func _flat_dist(n: Node3D) -> float:
	var d := n.global_position - global_position
	d.y *= 0.5
	return d.length()


func _elem_color() -> Color:
	if Elem.is_valid(weapon_element):
		return Elem.color_of(weapon_element)
	return Color(0.9, 0.95, 1.0)


func is_dead() -> bool:
	return not combatant.alive
