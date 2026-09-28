class_name SpellRuntime
## 法诀运行时：按 spells.json 中的 kind 执行效果。
## caster 需提供：combatant, lock_target, aim_point(), cast_origin(), forward(), start_dash(...)


static func power_mult(def: Dictionary, level: int) -> float:
	return float(def.get("power", 1.0)) * (1.0 + 0.08 * level)


static func base_info(caster: Node3D, def: Dictionary, level: int) -> Dictionary:
	var info := {
		"kind": "spell", "mult": power_mult(def, level),
		"element": str(def.get("element", Elem.NONE)),
		"poise": 25.0 * float(def.get("power", 1.0)),
		"knock": float(def.get("params", {}).get("knock", 3.0)),
	}
	if def.has("status"):
		info["status"] = def["status"]
	return info


static func color_of(def: Dictionary) -> Color:
	var e := str(def.get("element", Elem.NONE))
	return Elem.color_of(e) if Elem.is_valid(e) else Color(0.8, 0.92, 1.0)


static func execute(caster: Node3D, def: Dictionary, level: int) -> void:
	var p: Dictionary = def.get("params", {})
	var col := color_of(def)
	var c := CombatUtil.combatant_of(caster)
	if c == null or not c.alive:
		return
	var sfx: String = {"metal": "wind_blade", "wood": "vine", "water": "ice_cast", "fire": "fire_cast", "earth": "earth_quake"}.get(str(def.get("element", "")), "cast")
	match str(def.get("kind", "projectile")):
		"projectile":
			_projectile(caster, def, level, p, col)
			Audio.play_at(sfx, caster.global_position)
		"nova":
			var pos := caster.global_position + Vector3.UP * 0.5
			var r := float(p.get("radius", 5.0))
			CombatUtil.aoe(caster, pos, r, base_info(caster, def, level))
			CombatUtil.damage_destructibles(pos, r * 0.5, power_mult(def, level) * 25.0)
			FX.ring(caster.global_position + Vector3.UP * 0.2, r, col, 0.45, 0.25)
			FX.shock_sphere(pos, r * 0.8, col, 0.3)
			FX.burst(pos, col, 30, 10.0, 0.16, 0.8, false)
			FX.dust(caster.global_position, 24)
			CombatUtil.crater(caster.global_position, float(p.get("crater", 0.0)))
			Audio.play_at(sfx, pos)
			if CombatUtil.is_player(caster):
				CombatUtil.shake(0.5)
		"strike":
			_strike(caster, def, level, p, col)
		"dash":
			var dir: Vector3 = caster.call("forward")
			var tgt: Node3D = caster.get("lock_target")
			if tgt != null and is_instance_valid(tgt):
				dir = (tgt.global_position - caster.global_position)
				dir.y = 0.0
				dir = dir.normalized()
			caster.call("start_dash", dir, float(p.get("distance", 10.0)), float(p.get("speed", 50.0)), float(p.get("width", 2.0)), base_info(caster, def, level), col)
			Audio.play_at(sfx, caster.global_position)
		"shield":
			c.add_shield(c.stat("max_shield") * float(p.get("amount", 0.5)) * (1.0 + 0.05 * level))
			if p.has("status"):
				c.apply_status(str(p["status"]), 1.0, c)
				_extend_status(c, str(p["status"]), float(p.get("duration", 5.0)))
			FX.shock_sphere(caster.global_position + Vector3.UP, 1.4, col, 0.4)
			FX.ring(caster.global_position + Vector3.UP * 0.1, 2.0, col, 0.4)
			Audio.play_at("buff", caster.global_position)
		"buff":
			var sid := str(p.get("status", "fury"))
			c.apply_status(sid, float(p.get("stacks", 1)), c)
			_extend_status(c, sid, float(p.get("duration", 6.0)) * (1.0 + 0.05 * level))
			FX.burst(caster.global_position + Vector3.UP, col, 20, 3.0, 0.08, 0.8, true, -3.0)
			FX.ring(caster.global_position + Vector3.UP * 0.1, 1.8, col, 0.5)
			Audio.play_at("buff", caster.global_position)
		"heal":
			var amt := c.stat("max_hp") * float(p.get("amount", 0.3)) * (1.0 + 0.05 * level)
			var over := float(p.get("over", 0.0))
			if over > 0.0:
				c.apply_status("regen", 1.0, c)
				_extend_status(c, "regen", over)
			else:
				c.heal(amt)
			FX.burst(caster.global_position + Vector3.UP, col, 24, 2.5, 0.08, 1.0, true, -2.0)
			Audio.play_at("heal", caster.global_position)
		"field":
			var at := _ground_target(caster, float(p.get("range", 30.0)))
			SpellField.spawn(caster, at, def, level)
			Audio.play_at(sfx, at)
		"summon":
			for i in int(p.get("count", 3)):
				SummonedBlade.spawn(caster, def, level, i, int(p.get("count", 3)))
			Audio.play_at("summon", caster.global_position)
		"beam":
			SpellBeam.spawn(caster, def, level)
			Audio.play_at(sfx, caster.global_position)
		_:
			push_warning("未知法诀类型 %s" % def.get("kind"))


static func _extend_status(c: Combatant, sid: String, duration: float) -> void:
	if c.statuses.has(sid):
		c.statuses[sid]["time"] = maxf(float(c.statuses[sid]["time"]), duration)


static func _projectile(caster: Node3D, def: Dictionary, level: int, p: Dictionary, col: Color) -> void:
	var origin: Vector3 = caster.call("cast_origin")
	var target: Node3D = caster.get("lock_target")
	var speed := float(p.get("speed", 50.0))
	var aim: Vector3
	if target != null and is_instance_valid(target):
		aim = CombatUtil.lead_point(origin, target, speed)
	else:
		aim = caster.call("aim_point")
	var dir := (aim - origin).normalized()
	var count := int(p.get("count", 1))
	var spread := deg_to_rad(float(p.get("spread", 0.0)))
	for i in count:
		var ang := 0.0 if count == 1 else lerpf(-spread, spread, float(i) / float(count - 1))
		var d := dir.rotated(Vector3.UP, ang)
		Projectile.spawn({
			"owner": caster, "pos": origin, "dir": d, "speed": speed,
			"size": float(p.get("size", 0.3)), "range": float(p.get("range", 60.0)),
			"homing": float(p.get("homing", 0.0)), "target": target,
			"pierce": int(p.get("pierce", 0)), "explode": float(p.get("explode", 0.0)),
			"crater": float(p.get("crater", 0.0)), "shape": str(p.get("shape", "orb")),
			"info": base_info(caster, def, level), "element": str(def.get("element", Elem.NONE)),
		})
	FX.sparkle(origin, col, 10)


## 地面目标点：锁定目标脚下，或准星指向的地面
static func _ground_target(caster: Node3D, max_range: float) -> Vector3:
	var target: Node3D = caster.get("lock_target")
	var pos: Vector3
	if target != null and is_instance_valid(target) and target.global_position.distance_to(caster.global_position) <= max_range * 1.2:
		pos = target.global_position
	else:
		pos = caster.call("aim_point")
		if pos.distance_to(caster.global_position) > max_range:
			pos = caster.global_position + (pos - caster.global_position).normalized() * max_range
	var down := CombatUtil.ray_world(pos + Vector3.UP * 20.0, pos + Vector3.DOWN * 60.0)
	if not down.is_empty():
		pos = down["position"]
	return pos


static func _strike(caster: Node3D, def: Dictionary, level: int, p: Dictionary, col: Color) -> void:
	var center := _ground_target(caster, float(p.get("range", 40.0)))
	var count := int(p.get("count", 1))
	var spread := float(p.get("spread", 0.0))
	var delay := float(p.get("delay", 0.6))
	var interval := float(p.get("interval", 0.15))
	var r := float(p.get("radius", 3.0))
	var visual := str(p.get("visual", "pillar"))
	var tree := CombatUtil.tree()
	for i in count:
		var pos := center
		if i > 0 or count > 1:
			pos += Vector3(randf_range(-spread, spread), 0, randf_range(-spread, spread))
			var down := CombatUtil.ray_world(pos + Vector3.UP * 20.0, pos + Vector3.DOWN * 40.0)
			if not down.is_empty():
				pos = down["position"]
		var t := delay + interval * i
		FX.telegraph(pos, r, col, t)
		if visual == "meteor":
			FX.meteor(pos + Vector3(randf_range(-6, 6), 30, randf_range(-6, 6)), pos, col, t)
		tree.create_timer(t, false).timeout.connect(_strike_land.bind(caster, def, level, pos, r, col, visual))
	Audio.play_at("cast", caster.global_position)


static func _strike_land(caster: Node3D, def: Dictionary, level: int, pos: Vector3, r: float, col: Color, visual: String) -> void:
	var owner: Node3D = caster if is_instance_valid(caster) else null
	var p: Dictionary = def.get("params", {})
	CombatUtil.aoe(owner, pos + Vector3.UP * 0.8, r, base_info(owner, def, level) if owner != null else {"kind": "spell", "mult": power_mult(def, level)})
	CombatUtil.damage_destructibles(pos, r * 0.6, power_mult(def, level) * 25.0)
	match visual:
		"lightning":
			FX.beam(pos + Vector3.UP * 40.0, pos, col.lightened(0.4), 0.35, 0.25, true)
			Audio.play_at("thunder", pos)
		"meteor":
			Audio.play_at("explosion", pos)
		_:
			FX.pillar(pos, r * 0.7, 8.0, col, 0.8)
			Audio.play_at("water_splash" if str(def.get("element", "")) == Elem.WATER else "explosion", pos)
	FX.ring(pos + Vector3.UP * 0.2, r * 1.2, col, 0.4, 0.2)
	FX.burst(pos + Vector3.UP * 0.5, col, 24, 8.0, 0.14, 0.7)
	FX.flash_light(pos + Vector3.UP, col, 5.0, r * 3.0, 0.3)
	CombatUtil.crater(pos, float(p.get("crater", 0.0)))
	if owner != null and owner.global_position.distance_to(pos) < 30.0:
		CombatUtil.shake(0.3)
