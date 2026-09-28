class_name CombatUtil
## 战斗通用：寻敌、命中结算（含反馈）、范围伤害、破坏场景。

const GROUP := "combatants"


static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func combatant_of(n: Node) -> Combatant:
	if n == null or not is_instance_valid(n):
		return null
	var c = n.get("combatant")
	return c as Combatant


static func bodies() -> Array[Node]:
	return tree().get_nodes_in_group(GROUP)


static func is_player(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.is_in_group("player")


## 攻击者是否可以伤害目标：敌对，或目标是攻击者主动锁定的对象（袭杀）
static func can_damage(attacker: Node3D, target: Node3D) -> bool:
	if attacker == target:
		return false
	var a := combatant_of(attacker)
	var t := combatant_of(target)
	if t == null or not t.alive:
		return false
	if a == null:
		return true
	if a.is_hostile_to(t):
		return true
	var lock = attacker.get("lock_target")
	return lock != null and lock == target


## 以 pos 为中心 radius 内可被 attacker 伤害的角色
static func targets_in_radius(attacker: Node3D, pos: Vector3, radius: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for b in bodies():
		var body := b as Node3D
		if body == null or not can_damage(attacker, body):
			continue
		var center := body.global_position + Vector3.UP * 0.9
		if center.distance_to(pos) <= radius + 0.5:
			out.append(body)
	return out


## 最近的敌对目标
static func nearest_hostile(from: Node3D, max_dist: float, require_hostile: bool = true) -> Node3D:
	var best: Node3D = null
	var bd := max_dist
	var me := combatant_of(from)
	for b in bodies():
		var body := b as Node3D
		if body == null or body == from:
			continue
		var c := combatant_of(body)
		if c == null or not c.alive:
			continue
		if require_hostile and me != null and not me.is_hostile_to(c):
			continue
		var d := body.global_position.distance_to(from.global_position)
		if d < bd:
			bd = d
			best = body
	return best


## 命中结算：伤害 + 受击反馈 + 事件 + 顿帧/震屏。info 见 DamageCalc。
static func hit(attacker: Node3D, target: Node3D, info: Dictionary) -> Dictionary:
	var t := combatant_of(target)
	if t == null or not t.alive:
		return {}
	var a := combatant_of(attacker)
	if a != null:
		info["source"] = a
	var provoked := a != null and not a.is_hostile_to(t)
	if not info.has("point"):
		info["point"] = target.global_position + Vector3.UP * 1.0
	if not info.has("dir") and attacker != null and is_instance_valid(attacker):
		var d := target.global_position - attacker.global_position
		d.y = 0.0
		info["dir"] = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	var res := t.take_damage(info)
	if res.is_empty():
		return res
	if provoked and a != null:
		t.add_grudge(a)
		a.add_grudge(t)
	if target.has_method("on_hit"):
		target.call("on_hit", info, res)
	var kind := str(info.get("kind", ""))
	Events.hit_landed.emit({
		"pos": info["point"], "amount": res["damage"], "crit": res["crit"], "kind": kind,
		"element": info.get("element", Elem.NONE), "shield": res["shield_damage"] > 0.0 and res["hp_damage"] <= 0.0,
		"target": target, "source": attacker, "killed": res["killed"], "provoked": provoked,
	})
	if kind != "dot":
		var p_att := is_player(attacker)
		var p_tgt := is_player(target)
		if p_att or p_tgt:
			var heavy: bool = info.get("heavy", false) or res["crit"] or res["killed"]
			if kind == "melee":
				HitStop.trigger(0.085 if heavy else 0.05, 0.05)
			elif heavy:
				HitStop.trigger(0.04, 0.1)
			shake((0.35 if heavy else 0.18) if p_att else 0.45)
	return res


## 范围伤害（中心伤害最高，边缘 60%）
static func aoe(attacker: Node3D, pos: Vector3, radius: float, info: Dictionary, falloff: bool = true) -> int:
	var n := 0
	for body in targets_in_radius(attacker, pos, radius):
		var i := info.duplicate()
		var d := (body.global_position + Vector3.UP * 0.9).distance_to(pos)
		if falloff:
			i["mult"] = float(info.get("mult", 1.0)) * lerpf(1.0, 0.6, clampf(d / maxf(radius, 0.1), 0.0, 1.0))
		var dir := body.global_position - pos
		dir.y = 0.0
		i["dir"] = dir.normalized() if dir.length() > 0.05 else Vector3.FORWARD
		i["point"] = body.global_position + Vector3.UP * 1.0
		hit(attacker, body, i)
		n += 1
	return n


## 对可破坏体素物体造成破坏
static func damage_destructibles(pos: Vector3, radius: float, power: float) -> void:
	var space := _space()
	if space == null:
		return
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	q.shape = s
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = 1 << 6
	for r in space.intersect_shape(q, 16):
		var col = r.get("collider")
		if col != null and col.has_method("apply_damage_at"):
			col.call("apply_damage_at", pos, radius, power)


## 在地形上炸出弹坑
static func crater(pos: Vector3, radius: float) -> void:
	if radius <= 0.0:
		return
	var t := tree().get_first_node_in_group("terrain")
	if t != null and t.has_method("carve_crater"):
		t.call("carve_crater", pos, radius)


static func shake(amount: float) -> void:
	var cam := tree().get_first_node_in_group("camera_rig")
	if cam != null and cam.has_method("add_trauma"):
		cam.call("add_trauma", amount * Settings.camera_shake)


static func _space() -> PhysicsDirectSpaceState3D:
	var t := tree()
	if t == null or t.root == null:
		return null
	var w := t.root.get_world_3d()
	return w.direct_space_state if w != null else null


## 射线（只检测世界与可破坏物）
static func ray_world(from: Vector3, to: Vector3, exclude: Array[RID] = []) -> Dictionary:
	var space := _space()
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | (1 << 6), exclude)
	return space.intersect_ray(q)


## 点到线段距离
static func dist_point_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## 带提前量的瞄准点
static func lead_point(from: Vector3, target: Node3D, speed: float) -> Vector3:
	var tp := target.global_position + Vector3.UP * 0.95
	var v := Vector3.ZERO
	if target is CharacterBody3D:
		v = (target as CharacterBody3D).velocity
	var t := from.distance_to(tp) / maxf(speed, 1.0)
	return tp + v * t * 0.8
