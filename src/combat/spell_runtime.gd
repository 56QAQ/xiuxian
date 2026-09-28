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


## 法诀的表现色（五行配色；雷系为紫白，血神刀芒为血红）
static func color_of(def: Dictionary) -> Color:
	return VfxLib.spell_color(def)


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
			VfxSpells.nova(pos, r, VfxLib.spell_elem(def), str(p.get("visual", "ring")), col)
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
			VfxSpells.shield_cast(caster, col, float(p.get("duration", 3.0)) if p.has("status") else 3.0)
			Audio.play_at("buff", caster.global_position)
		"buff":
			var sid := str(p.get("status", "fury"))
			c.apply_status(sid, float(p.get("stacks", 1)), c)
			_extend_status(c, sid, float(p.get("duration", 6.0)) * (1.0 + 0.05 * level))
			VfxSpells.buff_cast(caster, col)
			Audio.play_at("buff", caster.global_position)
		"heal":
			var amt := c.stat("max_hp") * float(p.get("amount", 0.3)) * (1.0 + 0.05 * level)
			var over := float(p.get("over", 0.0))
			if over > 0.0:
				c.apply_status("regen", 1.0, c)
				_extend_status(c, "regen", over)
			else:
				c.heal(amt)
			VfxSpells.heal(caster, col)
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
			"color": col, "vfx_elem": VfxLib.spell_elem(def),
		})
	FX.cast_release(origin, dir, def)


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
		var ve := VfxLib.spell_elem(def)
		VfxSpells.strike_telegraph(pos, r, ve, t, visual, col)
		if visual == "meteor":
			VfxSpells.strike_fall(pos, r, ve, t)
		tree.create_timer(t, false).timeout.connect(_strike_land.bind(caster, def, level, pos, r, col, visual))
	Audio.play_at("cast", caster.global_position)


static func _strike_land(caster: Node3D, def: Dictionary, level: int, pos: Vector3, r: float, col: Color, visual: String) -> void:
	var owner: Node3D = caster if is_instance_valid(caster) else null
	var p: Dictionary = def.get("params", {})
	CombatUtil.aoe(owner, pos + Vector3.UP * 0.8, r, base_info(owner, def, level) if owner != null else {"kind": "spell", "mult": power_mult(def, level)})
	CombatUtil.damage_destructibles(pos, r * 0.6, power_mult(def, level) * 25.0)
	VfxSpells.strike_land(pos, r, VfxLib.spell_elem(def), visual, col)
	match visual:
		"lightning":
			Audio.play_at("thunder", pos)
		"meteor":
			Audio.play_at("explosion", pos)
		_:
			Audio.play_at("water_splash" if str(def.get("element", "")) == Elem.WATER else "explosion", pos)
	CombatUtil.crater(pos, float(p.get("crater", 0.0)))
	if owner != null and owner.global_position.distance_to(pos) < 30.0:
		CombatUtil.shake(0.3)
