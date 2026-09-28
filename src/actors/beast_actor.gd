class_name BeastActor
extends CharacterBody3D
## 妖兽：数据来自 enemies.json（kind=beast）。模型由 BeastBuilder 生成（若不可用则使用简易方块模型）。
## 攻击类型：bite（近咬）、pounce（扑击）、charge（冲撞）、slam（范围砸地）、spit（吐息弹道）、howl（咆哮增益）。

signal died(actor: BeastActor, killer: Node3D)

const GRAVITY := 24.0

var combatant: Combatant
var rig: Node3D
var enemy_id: String = ""
var def: Dictionary = {}
var ai: BeastAI
var nameplate: Nameplate
var size: float = 1.0
var speed: float = 8.0
var action: String = ""
var action_t: float = 0.0
var attack_def: Dictionary = {}
var _hit_done: bool = false
var _hit_at: float = 0.3
var attack_cd: Dictionary = {}
var lock_target: Node3D = null
var evading: float = 0.0
var in_move: Vector3 = Vector3.ZERO
var want_run: bool = false
var knock_t: float = 0.0
var _charge_hit: Dictionary = {}
var _yaw: float = 0.0


func _init() -> void:
	collision_layer = 1 << 2
	collision_mask = 1
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(55.0)
	add_to_group("combatants")
	add_to_group("beasts")


func setup(id: String, level_bonus: int = 0) -> void:
	enemy_id = id
	def = DB.enemy(id)
	size = float(def.get("size", 1.0))
	speed = float(def.get("speed", 8.0))
	var realm := int(def.get("realm", 0))
	var stage := int(def.get("stage", 0)) + level_bonus
	var stages := (DB.realm(realm).get("stages", []) as Array).size()
	stage = clampi(stage, 0, stages - 1)
	var base := BuildCalc.realm_base(realm, stage)
	var st := Stats.resolve(base, {})
	for k in def.get("mult", {}):
		st[k] = float(st.get(k, 0.0)) * float(def["mult"][k])
	st["shield_regen"] = float(st["max_shield"]) * 0.2
	st["qi_regen"] = 0.0
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45 * size
	cap.height = maxf(1.1 * size, cap.radius * 2.0 + 0.1)
	shape.shape = cap
	shape.position = Vector3(0, cap.height * 0.5, 0)
	add_child(shape)
	combatant = Combatant.new()
	combatant.name = "Combatant"
	add_child(combatant)
	combatant.display_name = str(def.get("name", id))
	combatant.faction = "beast"
	combatant.setup(st, realm, stage, str(def.get("element", Elem.NONE)))
	combatant.died.connect(_on_died)
	nameplate = Nameplate.new()
	nameplate.name = "Nameplate"
	add_child(nameplate)
	nameplate.setup(combatant, 1.3 * size + 0.6, "首领" if def.get("boss", false) else "")
	combatant.poise_broken.connect(func() -> void: _stagger(0.8))
	_build_rig()


func _build_rig() -> void:
	var colors: Array = def.get("colors", ["#888888", "#555555", "#dddddd"])
	var model := str(def.get("model", "wolf"))
	if ResourceLoader.exists("res://src/voxel/beast_builder.gd"):
		var bb: Variant = load("res://src/voxel/beast_builder.gd")
		rig = bb.call("build_async", model, colors, size)
	if rig == null:
		rig = _fallback_rig(model, colors)
	add_child(rig)
	if rig.has_signal("anim_event"):
		rig.connect("anim_event", _on_anim_event)


func _fallback_rig(model: String, colors: Array) -> Node3D:
	var r := CharacterRig.new()
	var c1 := CharacterBuilder.col(colors[0] if colors.size() > 0 else "#888888")
	var c2 := CharacterBuilder.col(colors[1] if colors.size() > 1 else "#555555")
	var body := Node3D.new()
	body.name = "hips"
	r.add_child(body)
	var g := VoxelGrid.new(8, 7, 16)
	g.fill_box(Vector3i(0, 2, 0), Vector3i(7, 6, 15), c1)
	g.fill_box(Vector3i(1, 0, 1), Vector3i(2, 2, 2), c2)
	g.fill_box(Vector3i(5, 0, 1), Vector3i(6, 2, 2), c2)
	g.fill_box(Vector3i(1, 0, 13), Vector3i(2, 2, 14), c2)
	g.fill_box(Vector3i(5, 0, 13), Vector3i(6, 2, 14), c2)
	g.fill_box(Vector3i(2, 4, -1), Vector3i(5, 7, 1), c1)
	body.add_child(VoxelMesher.build_instance(g, 0.08 * size, Vector3(-4, 0, -8) * 0.08 * size))
	r.setup()
	return r


# ================================================================ 循环

func _physics_process(delta: float) -> void:
	if combatant == null:
		return
	evading = maxf(evading - delta, 0.0)
	for k in attack_cd.keys():
		attack_cd[k] = float(attack_cd[k]) - delta
	if combatant.alive and ai != null:
		ai.update(self, delta)
	if action != "":
		action_t += delta
		_update_action(delta)
	var v := velocity
	var h := Vector3(v.x, 0, v.z)
	var st := combatant.stats
	var mv := float(st.get("move_speed", 6.5)) / 6.5
	var target_h := in_move * speed * mv * (1.0 if want_run else 0.45)
	if not combatant.alive or action in ["stagger", "dead", "bite", "slam", "spit", "howl"] or combatant.is_rooted():
		target_h = Vector3.ZERO
	var accel := 40.0 if knock_t <= 0.0 else 8.0
	knock_t = maxf(knock_t - delta, 0.0)
	if action not in ["pounce", "charge"]:
		h = h.move_toward(target_h, accel * delta)
	if is_on_floor():
		v.y = minf(v.y, 0.0)
	else:
		v.y -= GRAVITY * delta
	velocity = Vector3(h.x, v.y, h.z)
	move_and_slide()
	# 朝向
	if combatant.alive and action not in ["dead"]:
		var want := Vector3.ZERO
		if lock_target != null and is_instance_valid(lock_target) and action in ["", "bite", "slam", "spit", "howl"]:
			want = lock_target.global_position - global_position
		elif h.length() > 0.5:
			want = h
		want.y = 0.0
		if want.length() > 0.05:
			_yaw = lerp_angle(rotation.y, atan2(-want.x, -want.z), 1.0 - exp(-10.0 * delta))
			rotation.y = _yaw
	if rig is CharacterRig:
		var local := global_basis.inverse() * velocity
		(rig as CharacterRig).set_locomotion(local, is_on_floor(), false, false)


func forward() -> Vector3:
	return -global_basis.z


func has_clip(clip: String) -> bool:
	if rig == null:
		return false
	if rig is BeastRig:
		var br := rig as BeastRig
		return BeastRig.has_beast_clip(br.body, clip) or (br.body == "humanoid" and AnimLib.has_clip(clip)) or BeastRig.ALIASES.has(clip)
	return AnimLib.has_clip(clip)


## 攻击剪辑的出手时间（秒）
func _clip_hit_time(clip: String, fallback: float) -> float:
	if rig is BeastRig:
		var br := rig as BeastRig
		var cname := str(BeastRig.ALIASES.get(clip, clip))
		var t := BeastRig.hit_time(br.body, cname)
		if t < 0.0 and br.body == "humanoid":
			var c := AnimLib.get_clip(cname)
			for ev in c.get("events", []):
				if str(ev.get("name", "")) == "hit":
					t = float(ev.get("t", 0.0))
		if t >= 0.0:
			return t
	return fallback


# ================================================================ 攻击

func can_attack(a: Dictionary) -> bool:
	return action == "" and float(attack_cd.get(a["name"], 0.0)) <= 0.0 and combatant.alive and not combatant.is_rooted()


func start_attack(a: Dictionary) -> void:
	attack_def = a
	action = str(a["name"])
	action_t = 0.0
	_hit_done = false
	_charge_hit = {}
	attack_cd[a["name"]] = float(a.get("cd", 2.0))
	_hit_at = _clip_hit_time(action, 0.32) + 0.03
	var dur := 0.7
	if rig is CharacterRig and has_clip(action):
		var d := (rig as CharacterRig).play(action)
		if d > 0.0:
			dur = d
	match action:
		"pounce":
			if lock_target != null and is_instance_valid(lock_target):
				var to := lock_target.global_position - global_position
				var flat := Vector3(to.x, 0, to.z)
				var t := clampf(flat.length() / 16.0, 0.35, 0.8)
				velocity = flat / t
				velocity.y = GRAVITY * t * 0.5 + to.y / t
				_hit_at = t
			Audio.play_at("beast_growl", global_position, -2.0)
		"charge":
			velocity = forward() * speed * 2.6
			_hit_at = 99.0
			Audio.play_at("beast_growl", global_position)
		"howl":
			var buff: Dictionary = a.get("buff", {"status": "fury", "stacks": 1, "duration": 8.0, "radius": 20.0})
			var sid := str(buff.get("status", "fury"))
			var radius := float(buff.get("radius", 20.0))
			for b in get_tree().get_nodes_in_group("beasts"):
				if (b as Node3D).global_position.distance_to(global_position) < radius:
					var bc := CombatUtil.combatant_of(b)
					if bc != null and bc.alive:
						bc.apply_status(sid, float(buff.get("stacks", 1)), combatant)
						if bc.statuses.has(sid):
							bc.statuses[sid]["time"] = float(buff.get("duration", 8.0))
			Audio.play_at("beast_growl", global_position, 2.0)
			FX.ring(global_position + Vector3.UP * 0.5, 6.0, Color(1, 0.5, 0.3), 0.6)
		_:
			Audio.play_at("beast_bite" if action == "bite" else "beast_growl", global_position, -4.0)
	set_meta("attack_len", maxf(dur, _hit_at + 0.3))


func _update_action(delta: float) -> void:
	var total := float(get_meta("attack_len", 0.8))
	match action:
		"stagger":
			if action_t >= float(get_meta("stagger_t", 0.6)):
				action = ""
			return
		"dead":
			return
		"charge":
			velocity.x = forward().x * speed * 2.6
			velocity.z = forward().z * speed * 2.6
			for b in CombatUtil.targets_in_radius(self, global_position + Vector3.UP * 0.7, 1.4 * size):
				if not _charge_hit.has(b.get_instance_id()):
					_charge_hit[b.get_instance_id()] = true
					_deal(b, float(attack_def.get("dmg", 1.5)), 9.0, 40.0)
			if action_t > 1.1 or is_on_wall():
				action = ""
				velocity = Vector3.ZERO
			return
	if not _hit_done and action_t >= _hit_at:
		_do_hit()
	if action_t >= total:
		action = ""


func _on_anim_event(ev: String) -> void:
	if ev == "hit" and not _hit_done and action not in ["charge", "pounce", ""]:
		_do_hit()


func _do_hit() -> void:
	_hit_done = true
	var a := attack_def
	var dmg := float(a.get("dmg", 1.0))
	if a.has("projectile") and lock_target != null and is_instance_valid(lock_target):
		var pr: Dictionary = a["projectile"]
		var origin := global_position + Vector3.UP * 0.8 * size + forward() * 0.8 * size
		var aim := CombatUtil.lead_point(origin, lock_target, float(pr.get("speed", 30.0)))
		var info := {"kind": "spell", "mult": dmg, "element": str(pr.get("element", Elem.NONE)), "poise": 10.0, "knock": 2.0}
		if a.has("status"):
			info["status"] = a["status"]
		Projectile.spawn({"owner": self, "pos": origin, "dir": (aim - origin).normalized(), "speed": float(pr.get("speed", 30.0)),
			"size": float(pr.get("size", 0.4)), "range": float(a.get("range", 30.0)) * 1.3, "homing": 0.15, "target": lock_target,
			"shape": "rock" if pr.get("element", "") == Elem.EARTH else "orb", "info": info, "element": str(pr.get("element", Elem.NONE))})
		return
	if a.has("aoe"):
		var r := float(a["aoe"])
		CombatUtil.aoe(self, global_position + forward() * 1.0 * size + Vector3.UP * 0.5, r, {"kind": "melee", "mult": dmg, "poise": 35.0, "knock": 7.0, "element": str(def.get("element", Elem.NONE))})
		FX.ring(global_position + forward() * size, r, Color(0.8, 0.7, 0.55), 0.35, 0.25)
		FX.dust(global_position + forward() * size, 22)
		CombatUtil.damage_destructibles(global_position + forward() * size, r * 0.5, dmg * 20.0)
		Audio.play_at("earth_quake", global_position)
		return
	var reach := float(a.get("range", 2.2)) * maxf(size, 0.8)
	for b in CombatUtil.targets_in_radius(self, global_position + Vector3.UP * 0.8 + forward() * reach * 0.5, reach * 0.7):
		_deal(b, dmg, 3.0 if action != "pounce" else 6.0, 18.0)


func _deal(b: Node3D, dmg: float, knock: float, poise: float) -> void:
	var info := {"kind": "melee", "mult": dmg, "poise": poise, "knock": knock, "element": str(def.get("element", Elem.NONE))}
	if attack_def.has("status"):
		info["status"] = attack_def["status"]
	var res := CombatUtil.hit(self, b, info)
	if not res.is_empty():
		FX.burst(b.global_position + Vector3.UP, Color(0.9, 0.2, 0.2), 10, 5.0, 0.07, 0.35)
		Audio.play_at("hit_flesh", b.global_position)


# ================================================================ 受击 / 死亡

func on_hit(info: Dictionary, res: Dictionary) -> void:
	if rig is CharacterRig:
		(rig as CharacterRig).flash(0.9 if not info.get("no_react", false) else 0.3)
	if info.get("no_react", false) or res.get("killed", false):
		return
	var dir: Vector3 = info.get("dir", -forward())
	velocity += dir * float(info.get("knock", 0.0)) * 0.8 / maxf(size, 0.6)
	knock_t = 0.2
	if float(info.get("launch", 0.0)) > 0.0:
		velocity.y = float(info["launch"]) / maxf(size, 1.0)
	if ai != null and info.get("source") != null:
		var src: Combatant = info["source"]
		if is_instance_valid(src):
			ai.alert(src.body())
	if randf() < 0.5:
		Audio.play_at("beast_hurt", global_position, -4.0)
	if action == "" and rig is CharacterRig and randf() < 0.5 and has_clip("hit_front"):
		(rig as CharacterRig).play("hit_front")


func _stagger(t: float) -> void:
	if not combatant.alive:
		return
	action = "stagger"
	action_t = 0.0
	set_meta("stagger_t", t)
	if rig is CharacterRig and has_clip("stagger"):
		(rig as CharacterRig).play("stagger")


func _on_died(killer: Combatant) -> void:
	action = "dead"
	if nameplate != null:
		nameplate.visible = false
	collision_layer = 0
	if rig is CharacterRig and has_clip("death"):
		(rig as CharacterRig).play("death")
	elif rig != null:
		var tw0 := create_tween()
		tw0.tween_property(rig, "rotation:z", PI / 2.0, 0.5)
	Audio.play_at("beast_hurt", global_position)
	var kb: Node3D = killer.body() if killer != null else null
	died.emit(self, kb)
	# 掉落
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var items: Array[ItemInstance] = []
	for d in def.get("drops", []):
		var chance := float(d.get("chance", 0.5)) * (1.0 + float(GS.stats.get("loot_bonus", 0.0)))
		if rng.randf() < chance:
			var nr: Array = d.get("n", [1, 1])
			items.append(ItemInstance.create(str(d["item"]), rng.randi_range(int(nr[0]), int(nr[1]))))
	if not items.is_empty():
		var c := LootContainer.create(get_parent(), global_position, "beast", "", 0.8, rng, items)
		c.title = "%s遗骸" % combatant.display_name
		c.reveal_after(1.0)
	var tw := create_tween()
	tw.tween_interval(6.0)
	if rig is CharacterRig:
		tw.tween_method(func(v: float) -> void: (rig as CharacterRig).set_dissolve(v), 0.0, 1.0, 1.2)
	tw.tween_callback(queue_free)
