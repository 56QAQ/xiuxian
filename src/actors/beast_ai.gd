class_name BeastAI
extends RefCounted
## 妖兽行为：巡游 → 发现 → 追击 → 按距离选择招式；脱离领地太远会返回。

var home: Vector3
var target: Node3D = null
var aggro: float = 24.0
var leash: float = 70.0
var _wander_to: Vector3 = Vector3.INF
var _idle: float = 0.0
var _think: float = 0.0
var _circle: float = 1.0


func alert(src: Node3D) -> void:
	if src != null and is_instance_valid(src):
		target = src


func update(b: BeastActor, delta: float) -> void:
	b.in_move = Vector3.ZERO
	b.want_run = false
	_think -= delta
	if _think <= 0.0:
		_think = randf_range(0.25, 0.5)
		_retarget(b)
	if target == null:
		b.lock_target = null
		_wander(b, delta)
		return
	b.lock_target = target
	var to := target.global_position - b.global_position
	var flat := Vector3(to.x, 0, to.z)
	var d := flat.length()
	if b.global_position.distance_to(home) > leash:
		target = null
		return
	# 选择招式
	var attacks: Array = b.def.get("attacks", [])
	var best: Dictionary = {}
	for a in attacks:
		if not b.can_attack(a):
			continue
		var r := float(a.get("range", 2.2)) * maxf(b.size, 0.8)
		if a.get("leap", false) or a.get("charge", false):
			if d > 4.0 and d < r and absf(to.y) < 4.0:
				best = a
				break
		elif a.has("projectile"):
			if d > 5.0 and d < r and randf() < 0.3:
				best = a
				break
		elif str(a.get("name", "")) == "howl":
			if randf() < 0.1:
				best = a
				break
		elif d <= r + 0.3:
			best = a
	if not best.is_empty():
		b.start_attack(best)
		return
	if b.action != "":
		return
	# 追击，近身时绕行
	var dir := flat.normalized() if d > 0.01 else b.forward()
	if d > 2.4 * b.size:
		b.in_move = (dir + dir.cross(Vector3.UP) * _circle * 0.3).normalized()
		b.want_run = true
	else:
		b.in_move = dir.cross(Vector3.UP) * _circle * 0.5
	if randf() < 0.01:
		_circle = -_circle


func _retarget(b: BeastActor) -> void:
	if target != null:
		var tc := CombatUtil.combatant_of(target)
		if not is_instance_valid(target) or tc == null or not tc.alive or target.global_position.distance_to(b.global_position) > aggro * 2.5:
			target = null
	if target == null:
		var t := CombatUtil.nearest_hostile(b, aggro)
		if t != null and not t.is_in_group("beasts"):
			target = t
			Audio.play_at("beast_growl", b.global_position, -6.0)


func _wander(b: BeastActor, delta: float) -> void:
	_idle -= delta
	if _wander_to == Vector3.INF or b.global_position.distance_to(_wander_to) < 1.5:
		if _idle > 0.0:
			return
		_idle = randf_range(2.0, 5.0)
		var ang := randf() * TAU
		_wander_to = home + Vector3(cos(ang), 0, sin(ang)) * randf_range(3.0, 12.0)
		return
	var to := _wander_to - b.global_position
	to.y = 0.0
	b.in_move = to.normalized()
