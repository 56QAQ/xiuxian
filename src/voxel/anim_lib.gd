class_name AnimLib
## 动作库：持械待机姿势 + 动作剪辑（近战连段、施法、受击、死亡等）。
## 旋转约定见 CharacterRig 顶部注释。剪辑格式：
## { "length": 秒, "blend_in": 秒, "blend_out": 秒, "mask": "full"|"upper"|"arm", "loop": bool,
##   "keys": [{ "t": 秒, "pose": {...}, "ease": "smooth"|"linear"|"in"|"out"|"snap" }],
##   "events": [{ "t": 秒, "name": "hit" }] }


static var _clips: Dictionary = {}


static func pose(pose_name: String) -> Dictionary:
	match pose_name:
		"meditate":
			return {
				"hips": Vector3(0, 0, 0), "spine": Vector3(4, 0, 0), "head": Vector3(-6, 0, 0),
				"leg_l": Vector3(88, 32, -38), "shin_l": Vector3(-150, 0, 25),
				"leg_r": Vector3(88, -32, 38), "shin_r": Vector3(-150, 0, -25),
				"arm_l": Vector3(20, 0, -14), "forearm_l": Vector3(55, -20, 0), "hand_l": Vector3(0, 0, 30),
				"arm_r": Vector3(20, 0, 14), "forearm_r": Vector3(55, 20, 0), "hand_r": Vector3(0, 0, -30),
			}
		"salute":
			return {
				"arm_l": Vector3(70, -30, 0), "forearm_l": Vector3(80, 0, 0),
				"arm_r": Vector3(70, 30, 0), "forearm_r": Vector3(80, 0, 0), "hand_r": Vector3(0, 0, 20),
				"head": Vector3(-10, 0, 0), "spine": Vector3(-8, 0, 0),
			}
	return {}


## 各武器的待机持械姿势（上半身）
static func stance_pose(kind: String) -> Dictionary:
	match kind:
		"sword":
			return {
				"arm_l": Vector3(0, 0, -8), "forearm_l": Vector3(12, 0, 0),
				"arm_r": Vector3(12, 0, 12), "forearm_r": Vector3(30, 0, 0), "hand_r": Vector3(-72, 0, 0),
			}
		"saber":
			return {
				"arm_l": Vector3(0, 0, -8), "forearm_l": Vector3(12, 0, 0),
				"arm_r": Vector3(-5, 0, 14), "forearm_r": Vector3(20, 0, 0), "hand_r": Vector3(-100, 0, 0),
			}
		"spear":
			return {
				"spine": Vector3(0, 12, 0),
				"arm_l": Vector3(40, -20, -10), "forearm_l": Vector3(50, 0, 0),
				"arm_r": Vector3(20, 10, 16), "forearm_r": Vector3(45, 0, 0), "hand_r": Vector3(-50, 0, 0),
			}
	return {
		"arm_l": Vector3(0, 0, -7), "forearm_l": Vector3(18, 0, 0),
		"arm_r": Vector3(0, 0, 7), "forearm_r": Vector3(18, 0, 0),
	}


static func get_clip(clip_name: String) -> Dictionary:
	if _clips.is_empty():
		_build()
	return _clips.get(clip_name, {})


static func has_clip(clip_name: String) -> bool:
	if _clips.is_empty():
		_build()
	return _clips.has(clip_name)


static func _k(t: float, p: Dictionary, ease: String = "smooth") -> Dictionary:
	return {"t": t, "pose": p, "ease": ease}


static func _clip(length: float, keys: Array, events: Array = [], mask: String = "full", blend_in: float = 0.05, blend_out: float = 0.14) -> Dictionary:
	return {"length": length, "keys": keys, "events": events, "mask": mask, "blend_in": blend_in, "blend_out": blend_out}


static func _hit(t: float) -> Array:
	return [{"t": t, "name": "hit"}]


static func _build() -> void:
	var c := _clips
	var legs_stance := {"leg_l": Vector3(22, 0, -4), "shin_l": Vector3(-25, 0, 0), "leg_r": Vector3(-18, 0, 4), "shin_r": Vector3(-10, 0, 0), "root": Vector3(0, -0.05, 0)}
	var legs_lunge := {"leg_l": Vector3(40, 0, -4), "shin_l": Vector3(-40, 0, 0), "leg_r": Vector3(-30, 0, 4), "shin_r": Vector3(-15, 0, 0), "root": Vector3(0, -0.12, 0)}

	# ---------------------------------------------------------------- 剑：四段
	c["sword_1"] = _clip(0.42, [
		_k(0.0, {"spine": Vector3(0, -30, 0), "arm_r": Vector3(150, -35, 20), "forearm_r": Vector3(35, 0, 0), "hand_r": Vector3(-80, 0, 0), "arm_l": Vector3(20, 0, -30)}.merged(legs_stance)),
		_k(0.14, {"spine": Vector3(-6, 32, 0), "arm_r": Vector3(55, 55, 0), "forearm_r": Vector3(10, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(-20, 0, -40)}.merged(legs_lunge), "snap"),
		_k(0.42, {"spine": Vector3(-4, 26, 0), "arm_r": Vector3(45, 45, 0), "forearm_r": Vector3(20, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(-15, 0, -30)}.merged(legs_lunge)),
	], _hit(0.1))
	c["sword_2"] = _clip(0.40, [
		_k(0.0, {"spine": Vector3(-4, 30, 0), "arm_r": Vector3(90, 60, 0), "forearm_r": Vector3(40, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(10, 0, -20)}.merged(legs_lunge)),
		_k(0.13, {"spine": Vector3(-6, -35, 0), "arm_r": Vector3(85, -70, 10), "forearm_r": Vector3(5, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(-25, 0, -35)}.merged(legs_stance), "snap"),
		_k(0.40, {"spine": Vector3(-4, -30, 0), "arm_r": Vector3(75, -60, 10), "forearm_r": Vector3(15, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(-20, 0, -30)}.merged(legs_stance)),
	], _hit(0.09))
	c["sword_3"] = _clip(0.40, [
		_k(0.0, {"spine": Vector3(10, -10, 0), "arm_r": Vector3(10, -10, 10), "forearm_r": Vector3(60, 0, 0), "hand_r": Vector3(-40, 0, 0), "arm_l": Vector3(30, 0, -20)}.merged(legs_stance)),
		_k(0.12, {"spine": Vector3(-12, 5, 0), "arm_r": Vector3(95, 0, 5), "forearm_r": Vector3(0, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(-30, 0, -40)}.merged(legs_lunge), "snap"),
		_k(0.40, {"spine": Vector3(-8, 5, 0), "arm_r": Vector3(85, 0, 5), "forearm_r": Vector3(10, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(-20, 0, -30)}.merged(legs_lunge)),
	], _hit(0.09))
	c["sword_4"] = _clip(0.62, [
		_k(0.0, {"spine": Vector3(14, 0, 0), "arm_r": Vector3(175, 0, 10), "forearm_r": Vector3(30, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(160, 0, -10), "forearm_l": Vector3(30, 0, 0), "leg_l": Vector3(60, 0, 0), "shin_l": Vector3(-90, 0, 0), "leg_r": Vector3(20, 0, 0), "shin_r": Vector3(-60, 0, 0), "root": Vector3(0, 0.35, 0)}),
		_k(0.18, {"spine": Vector3(16, 0, 0), "arm_r": Vector3(185, 0, 10), "forearm_r": Vector3(40, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(170, 0, -10), "forearm_l": Vector3(40, 0, 0), "leg_l": Vector3(70, 0, 0), "shin_l": Vector3(-100, 0, 0), "leg_r": Vector3(30, 0, 0), "shin_r": Vector3(-70, 0, 0), "root": Vector3(0, 0.45, 0)}),
		_k(0.30, {"spine": Vector3(-30, 0, 0), "head": Vector3(20, 0, 0), "arm_r": Vector3(40, 0, 5), "forearm_r": Vector3(0, 0, 0), "hand_r": Vector3(-100, 0, 0), "arm_l": Vector3(40, 0, -5), "forearm_l": Vector3(10, 0, 0), "leg_l": Vector3(55, 0, -4), "shin_l": Vector3(-90, 0, 0), "leg_r": Vector3(-30, 0, 4), "shin_r": Vector3(-30, 0, 0), "root": Vector3(0, -0.3, 0)}, "snap"),
		_k(0.62, {"spine": Vector3(-20, 0, 0), "head": Vector3(10, 0, 0), "arm_r": Vector3(35, 0, 5), "forearm_r": Vector3(10, 0, 0), "hand_r": Vector3(-100, 0, 0), "arm_l": Vector3(30, 0, -5), "leg_l": Vector3(45, 0, -4), "shin_l": Vector3(-70, 0, 0), "leg_r": Vector3(-25, 0, 4), "shin_r": Vector3(-25, 0, 0), "root": Vector3(0, -0.22, 0)}),
	], _hit(0.28))

	# ---------------------------------------------------------------- 刀：三段（大开大合）
	c["saber_1"] = _clip(0.52, [
		_k(0.0, {"spine": Vector3(0, -45, 0), "arm_r": Vector3(120, -70, 30), "forearm_r": Vector3(40, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(30, 0, -20)}.merged(legs_stance)),
		_k(0.2, {"spine": Vector3(-8, 45, 0), "arm_r": Vector3(80, 80, 0), "forearm_r": Vector3(5, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(-30, 0, -45)}.merged(legs_lunge), "snap"),
		_k(0.52, {"spine": Vector3(-6, 40, 0), "arm_r": Vector3(70, 70, 0), "forearm_r": Vector3(15, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(-20, 0, -35)}.merged(legs_lunge)),
	], _hit(0.15))
	c["saber_2"] = _clip(0.52, [
		_k(0.0, {"spine": Vector3(0, 40, 0), "arm_r": Vector3(100, 80, 0), "forearm_r": Vector3(50, 0, 0), "hand_r": Vector3(-90, 0, 0)}.merged(legs_lunge)),
		_k(0.2, {"spine": Vector3(-10, -50, 0), "arm_r": Vector3(90, -90, 10), "forearm_r": Vector3(0, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(-20, 0, -40)}.merged(legs_stance), "snap"),
		_k(0.52, {"spine": Vector3(-6, -40, 0), "arm_r": Vector3(80, -80, 10), "forearm_r": Vector3(15, 0, 0), "hand_r": Vector3(-90, 0, 0)}.merged(legs_stance)),
	], _hit(0.15))
	c["saber_3"] = _clip(0.75, [
		_k(0.0, {"spine": Vector3(15, -20, 0), "arm_r": Vector3(190, -20, 10), "forearm_r": Vector3(40, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(170, 0, -20), "forearm_l": Vector3(40, 0, 0), "root": Vector3(0, 0.05, 0)}),
		_k(0.3, {"spine": Vector3(20, -20, 0), "arm_r": Vector3(200, -20, 10), "forearm_r": Vector3(50, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(180, 0, -20), "forearm_l": Vector3(50, 0, 0), "root": Vector3(0, 0.1, 0)}),
		_k(0.42, {"spine": Vector3(-35, 5, 0), "head": Vector3(25, 0, 0), "arm_r": Vector3(35, 5, 0), "forearm_r": Vector3(0, 0, 0), "hand_r": Vector3(-100, 0, 0), "arm_l": Vector3(35, 0, 0), "leg_l": Vector3(60, 0, -4), "shin_l": Vector3(-80, 0, 0), "leg_r": Vector3(-35, 0, 4), "shin_r": Vector3(-20, 0, 0), "root": Vector3(0, -0.3, 0)}, "snap"),
		_k(0.75, {"spine": Vector3(-25, 5, 0), "head": Vector3(15, 0, 0), "arm_r": Vector3(30, 5, 0), "forearm_r": Vector3(10, 0, 0), "hand_r": Vector3(-100, 0, 0), "arm_l": Vector3(30, 0, 0), "leg_l": Vector3(50, 0, -4), "shin_l": Vector3(-70, 0, 0), "leg_r": Vector3(-30, 0, 4), "shin_r": Vector3(-20, 0, 0), "root": Vector3(0, -0.25, 0)}),
	], _hit(0.4))

	# ---------------------------------------------------------------- 枪：三段（突刺、横扫、回旋挑）
	c["spear_1"] = _clip(0.45, [
		_k(0.0, {"spine": Vector3(0, 30, 0), "arm_r": Vector3(30, 20, 20), "forearm_r": Vector3(70, 0, 0), "hand_r": Vector3(-30, 0, 0), "arm_l": Vector3(50, -10, -10), "forearm_l": Vector3(40, 0, 0)}.merged(legs_stance)),
		_k(0.12, {"spine": Vector3(-10, 5, 0), "arm_r": Vector3(88, 5, 5), "forearm_r": Vector3(0, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(80, -5, 0), "forearm_l": Vector3(10, 0, 0)}.merged(legs_lunge), "snap"),
		_k(0.45, {"spine": Vector3(-8, 5, 0), "arm_r": Vector3(80, 5, 5), "forearm_r": Vector3(10, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(70, -5, 0), "forearm_l": Vector3(20, 0, 0)}.merged(legs_lunge)),
	], _hit(0.1))
	c["spear_2"] = _clip(0.55, [
		_k(0.0, {"spine": Vector3(0, -50, 0), "arm_r": Vector3(80, -80, 10), "forearm_r": Vector3(20, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(60, -40, 0), "forearm_l": Vector3(30, 0, 0)}.merged(legs_stance)),
		_k(0.2, {"spine": Vector3(-5, 60, 0), "arm_r": Vector3(85, 80, 0), "forearm_r": Vector3(5, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(60, 40, -20), "forearm_l": Vector3(30, 0, 0)}.merged(legs_lunge), "snap"),
		_k(0.55, {"spine": Vector3(-5, 50, 0), "arm_r": Vector3(75, 70, 0), "forearm_r": Vector3(15, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(50, 30, -20), "forearm_l": Vector3(30, 0, 0)}.merged(legs_lunge)),
	], _hit(0.16))
	c["spear_3"] = _clip(0.7, [
		_k(0.0, {"spine": Vector3(10, 0, 0), "arm_r": Vector3(20, 0, 10), "forearm_r": Vector3(40, 0, 0), "hand_r": Vector3(-20, 0, 0), "arm_l": Vector3(10, 0, -10), "leg_l": Vector3(30, 0, 0), "shin_l": Vector3(-60, 0, 0), "root": Vector3(0, -0.2, 0)}),
		_k(0.25, {"spine": Vector3(-15, 0, 0), "arm_r": Vector3(170, 0, 10), "forearm_r": Vector3(0, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(150, 0, -10), "leg_l": Vector3(40, 0, 0), "shin_l": Vector3(-70, 0, 0), "leg_r": Vector3(-10, 0, 0), "root": Vector3(0, 0.4, 0)}, "snap"),
		_k(0.7, {"spine": Vector3(-5, 0, 0), "arm_r": Vector3(120, 0, 10), "forearm_r": Vector3(20, 0, 0), "hand_r": Vector3(-90, 0, 0), "arm_l": Vector3(100, 0, -10), "root": Vector3(0, 0.0, 0)}),
	], _hit(0.2))

	# ---------------------------------------------------------------- 拳：五段（快速）
	var jab_l := {"spine": Vector3(-4, -25, 0), "arm_l": Vector3(88, -10, 0), "forearm_l": Vector3(0, 0, 0), "arm_r": Vector3(40, 20, 20), "forearm_r": Vector3(110, 0, 0)}
	var jab_r := {"spine": Vector3(-4, 25, 0), "arm_r": Vector3(88, 10, 0), "forearm_r": Vector3(0, 0, 0), "arm_l": Vector3(40, -20, -20), "forearm_l": Vector3(110, 0, 0)}
	var guard := {"arm_l": Vector3(40, -20, -20), "forearm_l": Vector3(110, 0, 0), "arm_r": Vector3(40, 20, 20), "forearm_r": Vector3(110, 0, 0)}
	c["fist_1"] = _clip(0.26, [_k(0.0, guard.merged(legs_stance)), _k(0.07, jab_l.merged(legs_lunge), "snap"), _k(0.26, jab_l.merged(legs_lunge))], _hit(0.06))
	c["fist_2"] = _clip(0.26, [_k(0.0, jab_l.merged(legs_lunge)), _k(0.07, jab_r.merged(legs_lunge), "snap"), _k(0.26, jab_r.merged(legs_lunge))], _hit(0.06))
	c["fist_3"] = _clip(0.32, [
		_k(0.0, guard.merged(legs_stance)),
		_k(0.1, {"spine": Vector3(-6, 30, 0), "arm_r": Vector3(70, 70, 0), "forearm_r": Vector3(40, 0, 0), "arm_l": Vector3(40, -20, -20), "forearm_l": Vector3(110, 0, 0)}.merged(legs_lunge), "snap"),
		_k(0.32, {"spine": Vector3(-4, 25, 0), "arm_r": Vector3(60, 60, 0), "forearm_r": Vector3(50, 0, 0), "arm_l": Vector3(40, -20, -20), "forearm_l": Vector3(110, 0, 0)}.merged(legs_lunge)),
	], _hit(0.09))
	c["fist_4"] = _clip(0.36, [
		_k(0.0, guard.merged(legs_stance)),
		_k(0.12, {"hips": Vector3(10, 0, 20), "spine": Vector3(5, 0, 10), "arm_l": Vector3(40, 0, -60), "arm_r": Vector3(40, 0, 50), "leg_r": Vector3(95, 0, 15), "shin_r": Vector3(-5, 0, 0), "leg_l": Vector3(0, 0, -5)}, "snap"),
		_k(0.36, {"hips": Vector3(6, 0, 12), "arm_l": Vector3(30, 0, -50), "arm_r": Vector3(30, 0, 40), "leg_r": Vector3(70, 0, 10), "shin_r": Vector3(-20, 0, 0)}),
	], _hit(0.1))
	c["fist_5"] = _clip(0.5, [
		_k(0.0, {"spine": Vector3(10, 0, 0), "arm_r": Vector3(-20, 0, 20), "forearm_r": Vector3(100, 0, 0), "arm_l": Vector3(40, 0, -20), "forearm_l": Vector3(90, 0, 0)}.merged(legs_stance)),
		_k(0.18, {"spine": Vector3(-15, 0, 0), "arm_r": Vector3(95, 0, 0), "forearm_r": Vector3(0, 0, 0), "hand_r": Vector3(0, 0, 0), "arm_l": Vector3(-30, 0, -30), "forearm_l": Vector3(60, 0, 0)}.merged(legs_lunge), "snap"),
		_k(0.5, {"spine": Vector3(-10, 0, 0), "arm_r": Vector3(90, 0, 0), "forearm_r": Vector3(5, 0, 0), "arm_l": Vector3(-20, 0, -30), "forearm_l": Vector3(60, 0, 0)}.merged(legs_lunge)),
	], _hit(0.15))

	# ---------------------------------------------------------------- 施法
	c["cast_forward"] = _clip(0.45, [
		_k(0.0, {"spine": Vector3(4, 20, 0), "arm_r": Vector3(30, 20, 30), "forearm_r": Vector3(90, 0, 0), "arm_l": Vector3(40, 0, -30), "forearm_l": Vector3(80, 0, 0)}),
		_k(0.14, {"spine": Vector3(-8, -10, 0), "arm_r": Vector3(90, 5, 0), "forearm_r": Vector3(0, 0, 0), "hand_r": Vector3(-60, 0, 0), "arm_l": Vector3(20, 0, -20), "forearm_l": Vector3(60, 0, 0)}, "snap"),
		_k(0.45, {"spine": Vector3(-5, -8, 0), "arm_r": Vector3(85, 5, 0), "forearm_r": Vector3(5, 0, 0), "hand_r": Vector3(-60, 0, 0), "arm_l": Vector3(15, 0, -20), "forearm_l": Vector3(50, 0, 0)}),
	], [{"t": 0.13, "name": "cast"}], "upper")
	c["cast_up"] = _clip(0.55, [
		_k(0.0, {"spine": Vector3(6, 0, 0), "arm_r": Vector3(40, 0, 40), "forearm_r": Vector3(60, 0, 0), "arm_l": Vector3(40, 0, -40), "forearm_l": Vector3(60, 0, 0)}),
		_k(0.2, {"spine": Vector3(-10, 0, 0), "head": Vector3(-20, 0, 0), "arm_r": Vector3(175, 0, 10), "forearm_r": Vector3(0, 0, 0), "arm_l": Vector3(30, 0, -50), "forearm_l": Vector3(40, 0, 0)}, "snap"),
		_k(0.55, {"spine": Vector3(-6, 0, 0), "head": Vector3(-10, 0, 0), "arm_r": Vector3(165, 0, 10), "forearm_r": Vector3(5, 0, 0), "arm_l": Vector3(20, 0, -40), "forearm_l": Vector3(30, 0, 0)}),
	], [{"t": 0.2, "name": "cast"}], "upper")
	c["cast_self"] = _clip(0.5, [
		_k(0.0, {"arm_r": Vector3(30, 0, 40), "arm_l": Vector3(30, 0, -40)}),
		_k(0.18, {"spine": Vector3(-5, 0, 0), "head": Vector3(-8, 0, 0), "arm_r": Vector3(70, 40, 0), "forearm_r": Vector3(80, 0, 0), "arm_l": Vector3(70, -40, 0), "forearm_l": Vector3(80, 0, 0)}, "snap"),
		_k(0.5, {"spine": Vector3(-3, 0, 0), "arm_r": Vector3(65, 35, 0), "forearm_r": Vector3(80, 0, 0), "arm_l": Vector3(65, -35, 0), "forearm_l": Vector3(80, 0, 0)}),
	], [{"t": 0.18, "name": "cast"}], "upper")
	c["cast_ground"] = _clip(0.6, [
		_k(0.0, {"spine": Vector3(10, 0, 0), "arm_r": Vector3(160, 0, 20), "forearm_r": Vector3(20, 0, 0), "arm_l": Vector3(160, 0, -20), "forearm_l": Vector3(20, 0, 0), "root": Vector3(0, 0.1, 0)}),
		_k(0.25, {"spine": Vector3(-40, 0, 0), "head": Vector3(25, 0, 0), "arm_r": Vector3(30, 0, 10), "forearm_r": Vector3(10, 0, 0), "arm_l": Vector3(30, 0, -10), "forearm_l": Vector3(10, 0, 0), "leg_l": Vector3(70, 0, -5), "shin_l": Vector3(-110, 0, 0), "leg_r": Vector3(-10, 0, 5), "shin_r": Vector3(-80, 0, 0), "root": Vector3(0, -0.45, 0)}, "snap"),
		_k(0.6, {"spine": Vector3(-30, 0, 0), "head": Vector3(15, 0, 0), "arm_r": Vector3(25, 0, 10), "arm_l": Vector3(25, 0, -10), "leg_l": Vector3(60, 0, -5), "shin_l": Vector3(-100, 0, 0), "leg_r": Vector3(-10, 0, 5), "shin_r": Vector3(-70, 0, 0), "root": Vector3(0, -0.4, 0)}),
	], [{"t": 0.25, "name": "cast"}])
	c["bolt"] = _clip(0.22, [
		_k(0.0, {"arm_l": Vector3(70, -10, -10), "forearm_l": Vector3(30, 0, 0)}),
		_k(0.05, {"spine": Vector3(0, -15, 0), "arm_l": Vector3(92, -5, 0), "forearm_l": Vector3(0, 0, 0), "hand_l": Vector3(-30, 0, 0)}, "snap"),
		_k(0.22, {"spine": Vector3(0, -10, 0), "arm_l": Vector3(88, -5, 0), "forearm_l": Vector3(5, 0, 0)}),
	], [], "upper", 0.03, 0.18)
	c["charge"] = _clip(0.6, [
		_k(0.0, {"spine": Vector3(0, -15, 0), "arm_l": Vector3(60, -30, -20), "forearm_l": Vector3(60, 0, 0)}),
		_k(0.6, {"spine": Vector3(4, -20, 0), "arm_l": Vector3(50, -40, -30), "forearm_l": Vector3(80, 0, 0)}),
	], [], "upper", 0.1, 0.1)
	c["charge"]["loop"] = true

	# ---------------------------------------------------------------- 受击 / 死亡 / 其它
	c["hit_front"] = _clip(0.28, [
		_k(0.0, {"spine": Vector3(12, 0, 0), "head": Vector3(15, 0, 0), "arm_l": Vector3(-20, 0, -30), "arm_r": Vector3(-20, 0, 30)}, "snap"),
		_k(0.28, {"spine": Vector3(4, 0, 0), "head": Vector3(4, 0, 0)}),
	], [], "upper", 0.02, 0.15)
	c["stagger"] = _clip(0.7, [
		_k(0.0, {"hips": Vector3(15, 0, 0), "spine": Vector3(20, 0, 5), "head": Vector3(20, 0, 0), "arm_l": Vector3(-30, 0, -50), "arm_r": Vector3(-30, 0, 50), "leg_l": Vector3(-15, 0, 0), "leg_r": Vector3(25, 0, 0), "shin_r": Vector3(-40, 0, 0), "root": Vector3(0, -0.08, 0.1)}, "snap"),
		_k(0.45, {"hips": Vector3(10, 0, 0), "spine": Vector3(15, 0, 0), "head": Vector3(10, 0, 0), "arm_l": Vector3(-10, 0, -30), "arm_r": Vector3(-10, 0, 30), "root": Vector3(0, -0.05, 0)}),
		_k(0.7, {}),
	], [], "full", 0.02, 0.2)
	c["death"] = _clip(1.1, [
		_k(0.0, {"hips": Vector3(10, 0, 0), "spine": Vector3(20, 0, 0), "head": Vector3(20, 0, 0), "arm_l": Vector3(-20, 0, -40), "arm_r": Vector3(-20, 0, 40)}),
		_k(0.45, {"hips": Vector3(30, 0, 5), "spine": Vector3(15, 0, 0), "leg_l": Vector3(80, 0, -10), "shin_l": Vector3(-120, 0, 0), "leg_r": Vector3(70, 0, 10), "shin_r": Vector3(-110, 0, 0), "arm_l": Vector3(10, 0, -30), "arm_r": Vector3(10, 0, 30), "root": Vector3(0, -0.6, 0)}, "in"),
		_k(1.1, {"hips": Vector3(88, 0, 5), "spine": Vector3(5, 0, 0), "head": Vector3(-10, 20, 0), "leg_l": Vector3(0, 0, -10), "shin_l": Vector3(-10, 0, 0), "leg_r": Vector3(5, 0, 10), "shin_r": Vector3(-10, 0, 0), "arm_l": Vector3(0, 0, -70), "arm_r": Vector3(0, 0, 70), "root": Vector3(0, -0.78, 0.3)}, "out"),
	], [], "full", 0.05, 0.01)
	c["death"]["hold"] = true
	c["search"] = _clip(1.0, [
		_k(0.0, {"spine": Vector3(-30, 0, 0), "head": Vector3(-20, 0, 0), "leg_l": Vector3(80, 0, 0), "shin_l": Vector3(-100, 0, 0), "leg_r": Vector3(-10, 0, 0), "shin_r": Vector3(-90, 0, 0), "arm_r": Vector3(50, 0, 10), "forearm_r": Vector3(20, 0, 0), "arm_l": Vector3(40, 0, -10), "root": Vector3(0, -0.45, 0)}),
		_k(0.5, {"spine": Vector3(-32, 5, 0), "head": Vector3(-22, 0, 0), "leg_l": Vector3(80, 0, 0), "shin_l": Vector3(-100, 0, 0), "leg_r": Vector3(-10, 0, 0), "shin_r": Vector3(-90, 0, 0), "arm_r": Vector3(60, 10, 10), "forearm_r": Vector3(30, 0, 0), "arm_l": Vector3(35, 0, -10), "root": Vector3(0, -0.45, 0)}),
		_k(1.0, {"spine": Vector3(-30, 0, 0), "head": Vector3(-20, 0, 0), "leg_l": Vector3(80, 0, 0), "shin_l": Vector3(-100, 0, 0), "leg_r": Vector3(-10, 0, 0), "shin_r": Vector3(-90, 0, 0), "arm_r": Vector3(50, 0, 10), "forearm_r": Vector3(20, 0, 0), "arm_l": Vector3(40, 0, -10), "root": Vector3(0, -0.45, 0)}),
	], [], "full", 0.15, 0.2)
	c["search"]["loop"] = true
	c["salute"] = _clip(1.0, [_k(0.0, pose("salute")), _k(1.0, pose("salute"))], [], "upper", 0.15, 0.25)
	c["dodge_back"] = _clip(0.35, [
		_k(0.0, {"hips": Vector3(15, 0, 0), "spine": Vector3(10, 0, 0), "arm_l": Vector3(40, 0, -40), "arm_r": Vector3(40, 0, 40), "leg_l": Vector3(40, 0, 0), "shin_l": Vector3(-60, 0, 0)}, "snap"),
		_k(0.35, {}),
	], [], "full", 0.02, 0.1)
