class_name BeastRig
extends CharacterRig
## 妖兽骨架（由 BeastBuilder 生成）。接口与 CharacterRig 相同：set_locomotion()、play() -> 时长、
## anim_event("hit")、action_finished、flash()、set_dissolve()、meshes。
##
## body（体型）：
##   quad     四足（狼/狐/野猪/熊）：hips（后躯，根）→ spine（前躯）→ neck → head → jaw；
##            leg_fl/fr（spine 下）、leg_bl/br（hips 下）+ shin_*；base_tail → tail_*（弹簧）；ear_l/r（弹簧）
##   serpent  蛇：hips（颈后第一节，根）→ seg_1..seg_N（向后）→ tail_*（弹簧）；hips → neck → head → jaw
##   bird     鹤：hips（躯干，根）→ neck_0 → neck_1 → head → jaw；wing_l/r → wing_tip_l/r；leg_l/r → shin_l/r；tail_0（弹簧）
##   spider   蛛：hips（腹部，根）→ spine（头胸部）→ jaw_l/jaw_r（螯）；leg_1l..leg_4r（头胸部下）+ knee_*
##   humanoid 石傀：CharacterRig 标准人形骨骼，可直接使用 AnimLib 的人形剪辑
## 朝向与旋转约定同 CharacterRig：面朝 -Z；下垂肢体 +X = 向前摆；头/颈（朝前）+X = 抬头；hips +X = 前躯抬起。
##
## 剪辑（BeastRig.CLIP_NAMES）：bite pounce charge slam spit hit_front stagger death(保持) howl，
## 以及别名 gore（野猪挑）、rock（石傀投石）、peck、roar、throw。所有攻击剪辑在出手帧发出 "hit" 事件，
## 时间见 BeastRig.hit_time(name)。未知攻击名按体型回退到 bite（石傀回退到 AnimLib 人形剪辑）。

const CLIP_NAMES: Array[String] = ["bite", "pounce", "charge", "slam", "spit", "hit_front", "stagger", "death", "howl"]
const ALIASES := {"gore": "gore", "rock": "rock", "peck": "bite", "roar": "howl", "throw": "rock", "claw": "slam", "leap": "pounce", "sting": "bite", "web": "spit"}

var body: String = "quad"
var model: String = "wolf"
## 步态参数（BeastBuilder 写入）：步幅（米，size=1）、快跑阈值（米/秒）、腿摆幅（度）
var stride: float = 1.3
var gallop_speed: float = 6.5
var leg_amp: float = 32.0
var tail_wag: float = 18.0

var _gphase: float = 0.0
var _idle_t: float = 0.0

static var _clip_cache: Dictionary = {}


# ================================================================ 剪辑

func play(clip_name: String, speed: float = 1.0) -> float:
	var clip := BeastRig.get_beast_clip(body, clip_name)
	if clip.is_empty():
		if body == "humanoid" and AnimLib.has_clip(clip_name):
			return super.play(clip_name, speed)
		clip = BeastRig.get_beast_clip(body, "bite")
		if clip.is_empty():
			return super.play(clip_name, speed)
	return play_clip(clip, clip_name, speed)


static func has_beast_clip(body_kind: String, clip_name: String) -> bool:
	return not get_beast_clip(body_kind, clip_name).is_empty()


## 攻击剪辑的 "hit" 事件时间（秒，速度 1）；没有则返回 -1
static func hit_time(body_kind: String, clip_name: String) -> float:
	var c := get_beast_clip(body_kind, clip_name)
	for ev in c.get("events", []):
		if str(ev.get("name", "")) == "hit":
			return float(ev.get("t", 0.0))
	return -1.0


static func get_beast_clip(body_kind: String, clip_name: String) -> Dictionary:
	if _clip_cache.is_empty():
		_clip_cache = {
			"quad": _quad_clips(), "serpent": _serpent_clips(), "bird": _bird_clips(),
			"spider": _spider_clips(), "humanoid": _golem_clips(),
		}
	var clips_of: Dictionary = _clip_cache.get(body_kind, {})
	if clips_of.has(clip_name):
		return clips_of[clip_name]
	var alias := str(ALIASES.get(clip_name, ""))
	if alias != "" and clips_of.has(alias):
		return clips_of[alias]
	# 别名在该体型中不存在（如四足没有 rock）：投掷类回退到 spit，其余回退到 bite
	if alias == "rock" and clips_of.has("spit"):
		return clips_of["spit"]
	return {}


static func _k(t: float, p: Dictionary, ease: String = "smooth") -> Dictionary:
	return {"t": t, "pose": p, "ease": ease}


static func _mk(length: float, keys: Array, hit_t: float = -1.0, blend_in: float = 0.06, blend_out: float = 0.18) -> Dictionary:
	var ev: Array = []
	if hit_t >= 0.0:
		ev.append({"t": hit_t, "name": "hit"})
	return {"length": length, "keys": keys, "events": ev, "mask": "full", "blend_in": blend_in, "blend_out": blend_out}


static func _quad_clips() -> Dictionary:
	var c := {}
	var crouch := {"hips": Vector3(-4, 0, 0), "spine": Vector3(-6, 0, 0), "leg_fl": Vector3(20, 0, 0), "shin_fl": Vector3(-40, 0, 0), "leg_fr": Vector3(20, 0, 0), "shin_fr": Vector3(-40, 0, 0), "leg_bl": Vector3(35, 0, 0), "shin_bl": Vector3(-60, 0, 0), "leg_br": Vector3(35, 0, 0), "shin_br": Vector3(-60, 0, 0), "root": Vector3(0, -0.12, 0.05)}
	# 撕咬：头颈后缩张口 → 前扑合口
	c["bite"] = _mk(0.5, [
		_k(0.0, {"neck": Vector3(18, 0, 0), "head": Vector3(10, 0, 0), "jaw": Vector3(-35, 0, 0), "spine": Vector3(4, 0, 0), "leg_bl": Vector3(10, 0, 0), "leg_br": Vector3(10, 0, 0), "root": Vector3(0, -0.02, 0.06)}),
		_k(0.2, {"neck": Vector3(-22, 0, 0), "head": Vector3(-8, 0, 0), "jaw": Vector3(-5, 0, 0), "spine": Vector3(-6, 0, 0), "leg_fl": Vector3(22, 0, 0), "leg_fr": Vector3(10, 0, 0), "leg_bl": Vector3(-18, 0, 0), "leg_br": Vector3(-12, 0, 0), "root": Vector3(0, -0.04, -0.22)}, "snap"),
		_k(0.5, {"neck": Vector3(-6, 0, 0), "jaw": Vector3(0, 0, 0), "root": Vector3(0, 0, -0.08)}),
	], 0.2)
	# 扑击：蓄力下伏 → 腾空前扑 → 落地
	c["pounce"] = _mk(1.0, [
		_k(0.0, crouch),
		_k(0.28, crouch.merged({"root": Vector3(0, -0.16, 0.1), "neck": Vector3(-6, 0, 0)}, true)),
		_k(0.5, {"hips": Vector3(18, 0, 0), "spine": Vector3(4, 0, 0), "neck": Vector3(6, 0, 0), "jaw": Vector3(-30, 0, 0), "leg_fl": Vector3(70, 0, 0), "shin_fl": Vector3(-10, 0, 0), "leg_fr": Vector3(62, 0, 0), "shin_fr": Vector3(-14, 0, 0), "leg_bl": Vector3(-55, 0, 0), "shin_bl": Vector3(-10, 0, 0), "leg_br": Vector3(-60, 0, 0), "shin_br": Vector3(-5, 0, 0), "root": Vector3(0, 0.55, -0.9)}, "out"),
		_k(0.66, {"hips": Vector3(-8, 0, 0), "neck": Vector3(-20, 0, 0), "jaw": Vector3(-4, 0, 0), "leg_fl": Vector3(30, 0, 0), "shin_fl": Vector3(-30, 0, 0), "leg_fr": Vector3(28, 0, 0), "shin_fr": Vector3(-35, 0, 0), "leg_bl": Vector3(-10, 0, 0), "leg_br": Vector3(-15, 0, 0), "root": Vector3(0, 0.05, -1.4)}, "in"),
		_k(1.0, {"root": Vector3(0, 0, -1.5)}),
	], 0.62, 0.08, 0.25)
	# 冲锋：低头刨地蓄势 → 猛冲顶撞（位移由行为层负责，剪辑只给姿态）
	c["charge"] = _mk(1.1, [
		_k(0.0, {"neck": Vector3(-14, 0, 0), "head": Vector3(-10, 0, 0), "leg_fr": Vector3(28, 0, 0), "shin_fr": Vector3(-50, 0, 0), "root": Vector3(0, -0.04, 0)}),
		_k(0.15, {"neck": Vector3(-16, 0, 0), "head": Vector3(-12, 0, 0), "leg_fr": Vector3(-20, 0, 0), "shin_fr": Vector3(-10, 0, 0), "root": Vector3(0, -0.05, 0.04)}),
		_k(0.32, {"neck": Vector3(-18, 0, 0), "head": Vector3(-14, 0, 0), "leg_fr": Vector3(26, 0, 0), "shin_fr": Vector3(-45, 0, 0), "hips": Vector3(-6, 0, 0), "root": Vector3(0, -0.07, 0.08)}),
		_k(0.48, {"neck": Vector3(-24, 0, 0), "head": Vector3(-6, 0, 0), "spine": Vector3(-4, 0, 0), "leg_fl": Vector3(45, 0, 0), "leg_fr": Vector3(-30, 0, 0), "leg_bl": Vector3(-40, 0, 0), "leg_br": Vector3(30, 0, 0), "shin_bl": Vector3(-30, 0, 0), "root": Vector3(0, 0.03, -0.35)}, "snap"),
		_k(0.62, {"neck": Vector3(10, 0, 0), "head": Vector3(14, 0, 0), "leg_fl": Vector3(-20, 0, 0), "leg_fr": Vector3(40, 0, 0), "leg_bl": Vector3(30, 0, 0), "leg_br": Vector3(-35, 0, 0), "root": Vector3(0, 0.02, -0.6)}),
		_k(1.1, {"root": Vector3(0, 0, -0.7)}),
	], 0.5, 0.05, 0.2)
	# 挑（野猪獠牙上挑）
	c["gore"] = _mk(0.55, [
		_k(0.0, {"neck": Vector3(-20, 0, 0), "head": Vector3(-14, 0, 0), "spine": Vector3(-4, 0, 0), "root": Vector3(0, -0.05, 0.04)}),
		_k(0.22, {"neck": Vector3(24, 10, 0), "head": Vector3(18, 0, 8), "spine": Vector3(8, 0, 0), "leg_fl": Vector3(15, 0, 0), "leg_fr": Vector3(15, 0, 0), "root": Vector3(0, 0.04, -0.2)}, "snap"),
		_k(0.55, {"neck": Vector3(4, 0, 0), "root": Vector3(0, 0, -0.1)}),
	], 0.22)
	# 拍击（熊）：人立而起，前掌砸下
	c["slam"] = _mk(1.1, [
		_k(0.0, {"root": Vector3(0, 0, 0)}),
		_k(0.38, {"hips": Vector3(42, 0, 0), "spine": Vector3(12, 0, 0), "neck": Vector3(-10, 0, 0), "head": Vector3(-12, 0, 0), "jaw": Vector3(-30, 0, 0), "leg_fl": Vector3(-50, 0, -15), "shin_fl": Vector3(-40, 0, 0), "leg_fr": Vector3(-50, 0, 15), "shin_fr": Vector3(-40, 0, 0), "leg_bl": Vector3(-38, 0, 0), "shin_bl": Vector3(10, 0, 0), "leg_br": Vector3(-38, 0, 0), "shin_br": Vector3(10, 0, 0), "root": Vector3(0, 0.1, 0.12)}, "out"),
		_k(0.56, {"hips": Vector3(-6, 0, 0), "spine": Vector3(-10, 0, 0), "neck": Vector3(-16, 0, 0), "jaw": Vector3(-10, 0, 0), "leg_fl": Vector3(40, 0, -8), "shin_fl": Vector3(-5, 0, 0), "leg_fr": Vector3(40, 0, 8), "shin_fr": Vector3(-5, 0, 0), "leg_bl": Vector3(10, 0, 0), "leg_br": Vector3(10, 0, 0), "root": Vector3(0, -0.1, -0.2)}, "in"),
		_k(1.1, {"root": Vector3(0, 0, -0.15)}),
	], 0.56, 0.08, 0.25)
	# 喷吐：抬头吸气 → 前伸张口喷出
	c["spit"] = _mk(0.7, [
		_k(0.0, {"neck": Vector3(26, 0, 0), "head": Vector3(12, 0, 0), "jaw": Vector3(-6, 0, 0), "spine": Vector3(6, 0, 0), "root": Vector3(0, 0.02, 0.06)}),
		_k(0.3, {"neck": Vector3(-8, 0, 0), "head": Vector3(-6, 0, 0), "jaw": Vector3(-42, 0, 0), "spine": Vector3(-4, 0, 0), "root": Vector3(0, -0.02, -0.08)}, "snap"),
		_k(0.5, {"neck": Vector3(-6, 0, 0), "jaw": Vector3(-36, 0, 0)}),
		_k(0.7, {}),
	], 0.3)
	c["hit_front"] = _mk(0.32, [
		_k(0.0, {"neck": Vector3(24, 0, 8), "head": Vector3(10, 0, 0), "spine": Vector3(8, 0, 0), "jaw": Vector3(-14, 0, 0), "root": Vector3(0, 0.02, 0.1)}, "snap"),
		_k(0.32, {}),
	], -1.0, 0.02, 0.12)
	c["stagger"] = _mk(0.8, [
		_k(0.0, {"hips": Vector3(-8, 0, 14), "spine": Vector3(6, 0, -8), "neck": Vector3(20, 18, 0), "jaw": Vector3(-20, 0, 0), "leg_fl": Vector3(-20, 0, -10), "leg_fr": Vector3(10, 0, 18), "leg_bl": Vector3(15, 0, 0), "shin_bl": Vector3(-40, 0, 0), "root": Vector3(0, -0.08, 0.18)}, "snap"),
		_k(0.45, {"hips": Vector3(-4, 0, 6), "neck": Vector3(8, 6, 0), "root": Vector3(0, -0.04, 0.1)}),
		_k(0.8, {}),
	], -1.0, 0.02, 0.2)
	var dc := _mk(1.3, [
		_k(0.0, {"neck": Vector3(20, 0, 0), "jaw": Vector3(-25, 0, 0), "hips": Vector3(-6, 0, 0), "root": Vector3(0, 0, 0.05)}),
		_k(0.45, {"hips": Vector3(-4, 0, 30), "spine": Vector3(0, 0, 10), "neck": Vector3(-10, 0, 0), "leg_fl": Vector3(40, 0, -10), "shin_fl": Vector3(-70, 0, 0), "leg_fr": Vector3(30, 0, 10), "shin_fr": Vector3(-60, 0, 0), "leg_bl": Vector3(40, 0, 0), "shin_bl": Vector3(-80, 0, 0), "leg_br": Vector3(30, 0, 0), "shin_br": Vector3(-60, 0, 0), "root": Vector3(0, -0.25, 0.05)}, "in"),
		_k(1.3, {"hips": Vector3(0, 0, 84), "spine": Vector3(0, 0, 6), "neck": Vector3(-14, 0, 8), "head": Vector3(-6, 0, 0), "jaw": Vector3(-12, 0, 0), "leg_fl": Vector3(20, 0, 10), "shin_fl": Vector3(-20, 0, 0), "leg_fr": Vector3(-10, 0, 20), "shin_fr": Vector3(-30, 0, 0), "leg_bl": Vector3(-20, 0, 8), "shin_bl": Vector3(-20, 0, 0), "leg_br": Vector3(10, 0, 18), "shin_br": Vector3(-30, 0, 0), "root": Vector3(0, -0.42, 0.1)}, "out"),
	], -1.0, 0.05, 0.01)
	dc["hold"] = true
	c["death"] = dc
	# 嚎叫：后坐、仰头张口
	c["howl"] = _mk(1.8, [
		_k(0.0, {}),
		_k(0.4, {"hips": Vector3(22, 0, 0), "spine": Vector3(10, 0, 0), "neck": Vector3(35, 0, 0), "head": Vector3(22, 0, 0), "jaw": Vector3(-30, 0, 0), "leg_bl": Vector3(55, 0, 0), "shin_bl": Vector3(-90, 0, 0), "leg_br": Vector3(55, 0, 0), "shin_br": Vector3(-90, 0, 0), "leg_fl": Vector3(-18, 0, 0), "leg_fr": Vector3(-18, 0, 0), "root": Vector3(0, -0.14, 0.1)}),
		_k(1.4, {"hips": Vector3(24, 0, 0), "spine": Vector3(10, 0, 0), "neck": Vector3(38, 0, 0), "head": Vector3(25, 0, 0), "jaw": Vector3(-34, 0, 0), "leg_bl": Vector3(55, 0, 0), "shin_bl": Vector3(-90, 0, 0), "leg_br": Vector3(55, 0, 0), "shin_br": Vector3(-90, 0, 0), "leg_fl": Vector3(-18, 0, 0), "leg_fr": Vector3(-18, 0, 0), "root": Vector3(0, -0.14, 0.1)}),
		_k(1.8, {}),
	], -1.0, 0.15, 0.3)
	return c


static func _serpent_clips() -> Dictionary:
	var c := {}
	c["bite"] = _mk(0.55, [
		_k(0.0, {"neck": Vector3(40, 0, 0), "head": Vector3(-20, 0, 0), "jaw": Vector3(-40, 0, 0), "seg_1": Vector3(0, 20, 0), "seg_2": Vector3(0, -25, 0), "root": Vector3(0, 0, 0.15)}),
		_k(0.2, {"neck": Vector3(-10, 0, 0), "head": Vector3(-10, 0, 0), "jaw": Vector3(-55, 0, 0), "seg_1": Vector3(0, 0, 0), "root": Vector3(0, 0, -0.5)}, "snap"),
		_k(0.28, {"neck": Vector3(-8, 0, 0), "jaw": Vector3(0, 0, 0), "root": Vector3(0, 0, -0.52)}),
		_k(0.55, {"root": Vector3(0, 0, -0.1)}),
	], 0.24)
	c["pounce"] = _mk(0.9, [
		_k(0.0, {"neck": Vector3(45, 0, 0), "head": Vector3(-25, 0, 0), "seg_1": Vector3(0, 30, 0), "seg_2": Vector3(0, -35, 0), "seg_3": Vector3(0, 30, 0), "root": Vector3(0, 0, 0.3)}),
		_k(0.35, {"neck": Vector3(0, 0, 0), "head": Vector3(0, 0, 0), "jaw": Vector3(-55, 0, 0), "seg_1": Vector3(0, 0, 0), "seg_2": Vector3(0, 0, 0), "root": Vector3(0, 0.25, -1.6)}, "snap"),
		_k(0.5, {"jaw": Vector3(0, 0, 0), "root": Vector3(0, 0, -1.8)}),
		_k(0.9, {"root": Vector3(0, 0, -1.8)}),
	], 0.38)
	c["charge"] = _mk(0.9, [
		_k(0.0, {"neck": Vector3(-20, 0, 0), "head": Vector3(10, 0, 0)}),
		_k(0.45, {"neck": Vector3(-25, 0, 0), "head": Vector3(15, 0, 0), "jaw": Vector3(-30, 0, 0), "root": Vector3(0, 0, -0.8)}, "snap"),
		_k(0.9, {"root": Vector3(0, 0, -1.0)}),
	], 0.45)
	# 甩尾横扫
	c["slam"] = _mk(0.9, [
		_k(0.0, {"seg_4": Vector3(0, -40, 0), "seg_5": Vector3(0, -35, 0), "seg_6": Vector3(0, -30, 0), "neck": Vector3(20, 0, 0)}),
		_k(0.45, {"seg_4": Vector3(0, 50, 0), "seg_5": Vector3(0, 45, 0), "seg_6": Vector3(0, 40, 0), "neck": Vector3(10, 0, 0)}, "snap"),
		_k(0.9, {}),
	], 0.42)
	c["spit"] = _mk(0.8, [
		_k(0.0, {"neck": Vector3(55, 0, 0), "head": Vector3(-30, 0, 0), "jaw": Vector3(-10, 0, 0)}),
		_k(0.35, {"neck": Vector3(30, 0, 0), "head": Vector3(-10, 0, 0), "jaw": Vector3(-60, 0, 0)}, "snap"),
		_k(0.55, {"neck": Vector3(32, 0, 0), "jaw": Vector3(-50, 0, 0)}),
		_k(0.8, {}),
	], 0.35)
	c["hit_front"] = _mk(0.35, [_k(0.0, {"neck": Vector3(50, 0, 10), "head": Vector3(10, 0, 0), "jaw": Vector3(-20, 0, 0), "root": Vector3(0, 0, 0.1)}, "snap"), _k(0.35, {})], -1.0, 0.02, 0.12)
	c["stagger"] = _mk(0.8, [_k(0.0, {"neck": Vector3(-10, 30, 0), "seg_1": Vector3(0, -30, 0), "seg_2": Vector3(0, 30, 0), "root": Vector3(0, 0, 0.2)}, "snap"), _k(0.8, {})], -1.0, 0.02, 0.2)
	var dc := _mk(1.3, [
		_k(0.0, {"neck": Vector3(50, 0, 0), "jaw": Vector3(-40, 0, 0)}),
		_k(1.3, {"hips": Vector3(0, 0, 70), "neck": Vector3(-30, 20, 0), "head": Vector3(0, 0, 20), "jaw": Vector3(-20, 0, 0), "seg_1": Vector3(0, 20, 0), "seg_2": Vector3(0, -15, 0), "seg_3": Vector3(0, 25, 0), "root": Vector3(0, -0.06, 0)}, "out"),
	], -1.0, 0.05, 0.01)
	dc["hold"] = true
	c["death"] = dc
	c["howl"] = _mk(1.5, [
		_k(0.0, {}),
		_k(0.4, {"neck": Vector3(65, 0, 0), "head": Vector3(-25, 0, 0), "jaw": Vector3(-60, 0, 0)}),
		_k(1.1, {"neck": Vector3(68, 0, 0), "head": Vector3(-28, 0, 0), "jaw": Vector3(-62, 0, 0)}),
		_k(1.5, {}),
	], -1.0, 0.1, 0.3)
	return c


static func _bird_clips() -> Dictionary:
	var c := {}
	var spread := {"wing_l": Vector3(0, 0, -80), "wing_tip_l": Vector3(0, 0, -10), "wing_r": Vector3(0, 0, 80), "wing_tip_r": Vector3(0, 0, 10)}
	c["bite"] = _mk(0.5, [
		_k(0.0, {"neck_0": Vector3(30, 0, 0), "neck_1": Vector3(-20, 0, 0), "head": Vector3(10, 0, 0), "hips": Vector3(6, 0, 0)}),
		_k(0.18, {"neck_0": Vector3(-50, 0, 0), "neck_1": Vector3(-10, 0, 0), "head": Vector3(-20, 0, 0), "jaw": Vector3(-20, 0, 0), "hips": Vector3(-12, 0, 0), "root": Vector3(0, 0, -0.15)}, "snap"),
		_k(0.5, {}),
	], 0.18)
	c["pounce"] = _mk(1.1, [
		_k(0.0, spread.merged({"hips": Vector3(10, 0, 0), "leg_l": Vector3(20, 0, 0), "shin_l": Vector3(-40, 0, 0), "leg_r": Vector3(20, 0, 0), "shin_r": Vector3(-40, 0, 0), "root": Vector3(0, -0.1, 0)})),
		_k(0.4, spread.merged({"wing_l": Vector3(0, 0, -20), "wing_r": Vector3(0, 0, 20), "hips": Vector3(-20, 0, 0), "neck_0": Vector3(-20, 0, 0), "leg_l": Vector3(-40, 0, 0), "leg_r": Vector3(-40, 0, 0), "root": Vector3(0, 1.0, -0.8)}), "out"),
		_k(0.7, {"hips": Vector3(-35, 0, 0), "neck_0": Vector3(-40, 0, 0), "head": Vector3(-20, 0, 0), "jaw": Vector3(-25, 0, 0), "leg_l": Vector3(60, 0, 0), "leg_r": Vector3(60, 0, 0), "wing_l": Vector3(0, 0, -100), "wing_r": Vector3(0, 0, 100), "root": Vector3(0, 0.2, -2.0)}, "in"),
		_k(1.1, {"root": Vector3(0, 0, -2.1)}),
	], 0.7, 0.08, 0.25)
	c["charge"] = c["pounce"]
	# 振翅拍击
	c["slam"] = _mk(0.9, [
		_k(0.0, spread.merged({"wing_l": Vector3(20, 0, -100), "wing_r": Vector3(20, 0, 100), "hips": Vector3(10, 0, 0)})),
		_k(0.4, {"wing_l": Vector3(-20, 0, -10), "wing_tip_l": Vector3(0, 0, 30), "wing_r": Vector3(-20, 0, 10), "wing_tip_r": Vector3(0, 0, -30), "hips": Vector3(-8, 0, 0), "root": Vector3(0, 0.1, -0.2)}, "snap"),
		_k(0.9, {}),
	], 0.4)
	c["spit"] = _mk(0.8, [
		_k(0.0, {"neck_0": Vector3(30, 0, 0), "neck_1": Vector3(20, 0, 0), "head": Vector3(10, 0, 0)}),
		_k(0.3, {"neck_0": Vector3(-30, 0, 0), "neck_1": Vector3(0, 0, 0), "head": Vector3(0, 0, 0), "jaw": Vector3(-35, 0, 0)}, "snap"),
		_k(0.8, {}),
	], 0.3)
	c["hit_front"] = _mk(0.35, [_k(0.0, spread.merged({"hips": Vector3(14, 0, 0), "neck_0": Vector3(30, 0, 0), "root": Vector3(0, 0.05, 0.12)}), "snap"), _k(0.35, {})], -1.0, 0.02, 0.12)
	c["stagger"] = _mk(0.8, [_k(0.0, {"hips": Vector3(10, 0, 20), "wing_l": Vector3(0, 0, -60), "wing_r": Vector3(0, 0, 30), "neck_0": Vector3(20, 25, 0), "root": Vector3(0, 0, 0.2)}, "snap"), _k(0.8, {})], -1.0, 0.02, 0.2)
	var dc := _mk(1.3, [
		_k(0.0, spread.merged({"neck_0": Vector3(40, 0, 0)})),
		_k(1.3, {"hips": Vector3(-10, 0, 80), "neck_0": Vector3(-60, 0, 20), "neck_1": Vector3(-30, 0, 0), "wing_l": Vector3(0, 0, -40), "wing_r": Vector3(0, 0, 70), "leg_l": Vector3(30, 0, 0), "shin_l": Vector3(-60, 0, 0), "leg_r": Vector3(-20, 0, 0), "root": Vector3(0, -0.7, 0)}, "out"),
	], -1.0, 0.05, 0.01)
	dc["hold"] = true
	c["death"] = dc
	c["howl"] = _mk(1.6, [
		_k(0.0, {}),
		_k(0.4, spread.merged({"neck_0": Vector3(50, 0, 0), "neck_1": Vector3(10, 0, 0), "head": Vector3(30, 0, 0), "jaw": Vector3(-30, 0, 0)})),
		_k(1.2, spread.merged({"neck_0": Vector3(52, 0, 0), "neck_1": Vector3(12, 0, 0), "head": Vector3(32, 0, 0), "jaw": Vector3(-34, 0, 0), "wing_l": Vector3(0, 0, -90), "wing_r": Vector3(0, 0, 90)})),
		_k(1.6, {}),
	], -1.0, 0.1, 0.3)
	return c


static func _spider_clips() -> Dictionary:
	var c := {}
	var rear := {"spine": Vector3(28, 0, 0), "leg_1l": Vector3(60, 0, -30), "knee_1l": Vector3(-30, 0, 0), "leg_1r": Vector3(60, 0, 30), "knee_1r": Vector3(-30, 0, 0), "leg_2l": Vector3(30, 0, -10), "leg_2r": Vector3(30, 0, 10), "jaw_l": Vector3(0, 30, 0), "jaw_r": Vector3(0, -30, 0), "root": Vector3(0, 0.08, 0.1)}
	c["bite"] = _mk(0.55, [
		_k(0.0, rear),
		_k(0.22, {"spine": Vector3(-14, 0, 0), "leg_1l": Vector3(20, 0, -10), "leg_1r": Vector3(20, 0, 10), "jaw_l": Vector3(0, -10, 0), "jaw_r": Vector3(0, 10, 0), "root": Vector3(0, -0.04, -0.3)}, "snap"),
		_k(0.55, {}),
	], 0.22)
	c["pounce"] = _mk(1.0, [
		_k(0.0, {"root": Vector3(0, -0.12, 0.05), "knee_2l": Vector3(-30, 0, 0), "knee_2r": Vector3(-30, 0, 0), "knee_3l": Vector3(-30, 0, 0), "knee_3r": Vector3(-30, 0, 0)}),
		_k(0.25, {"root": Vector3(0, -0.14, 0.1)}),
		_k(0.55, rear.merged({"root": Vector3(0, 0.7, -1.2)}), "out"),
		_k(0.75, {"spine": Vector3(-10, 0, 0), "root": Vector3(0, 0, -1.8)}, "in"),
		_k(1.0, {"root": Vector3(0, 0, -1.8)}),
	], 0.72)
	c["charge"] = c["pounce"]
	c["slam"] = _mk(0.9, [
		_k(0.0, rear.merged({"leg_1l": Vector3(80, 0, -20), "leg_1r": Vector3(80, 0, 20)})),
		_k(0.4, {"spine": Vector3(-18, 0, 0), "leg_1l": Vector3(10, 0, -5), "leg_1r": Vector3(10, 0, 5), "knee_1l": Vector3(20, 0, 0), "knee_1r": Vector3(20, 0, 0), "root": Vector3(0, -0.06, -0.15)}, "snap"),
		_k(0.9, {}),
	], 0.4)
	# 吐丝：腹部上翘对准目标
	c["spit"] = _mk(0.8, [
		_k(0.0, {"hips": Vector3(-30, 0, 0), "spine": Vector3(10, 0, 0)}),
		_k(0.35, {"hips": Vector3(-55, 0, 0), "spine": Vector3(15, 0, 0), "root": Vector3(0, 0.05, 0)}, "snap"),
		_k(0.8, {}),
	], 0.35)
	c["hit_front"] = _mk(0.3, [_k(0.0, {"spine": Vector3(18, 0, 0), "hips": Vector3(8, 0, 0), "root": Vector3(0, 0.03, 0.1)}, "snap"), _k(0.3, {})], -1.0, 0.02, 0.12)
	c["stagger"] = _mk(0.8, [_k(0.0, {"hips": Vector3(0, 20, 18), "spine": Vector3(10, -10, 0), "root": Vector3(0, -0.05, 0.2)}, "snap"), _k(0.8, {})], -1.0, 0.02, 0.2)
	var legs_curl := {}
	for i in range(1, 5):
		legs_curl["leg_%dl" % i] = Vector3(0, 0, 70)
		legs_curl["leg_%dr" % i] = Vector3(0, 0, -70)
		legs_curl["knee_%dl" % i] = Vector3(-100, 0, 0)
		legs_curl["knee_%dr" % i] = Vector3(-100, 0, 0)
	var dc := _mk(1.2, [
		_k(0.0, rear),
		_k(1.2, legs_curl.merged({"hips": Vector3(0, 0, 180), "spine": Vector3(0, 0, 0), "root": Vector3(0, 0.1, 0)}), "out"),
	], -1.0, 0.05, 0.01)
	dc["hold"] = true
	c["death"] = dc
	c["howl"] = _mk(1.4, [_k(0.0, {}), _k(0.4, rear), _k(1.0, rear.merged({"jaw_l": Vector3(0, 40, 0), "jaw_r": Vector3(0, -40, 0)})), _k(1.4, {})], -1.0, 0.1, 0.3)
	return c


## 石傀（人形）：沉重的双拳砸地、投石、冲撞、怒吼；受击/硬直/死亡用 AnimLib 人形剪辑
static func _golem_clips() -> Dictionary:
	var c := {}
	c["slam"] = _mk(1.2, [
		_k(0.0, {}),
		_k(0.45, {"spine": Vector3(14, 0, 0), "head": Vector3(-8, 0, 0), "arm_l": Vector3(170, 0, -12), "forearm_l": Vector3(30, 0, 0), "arm_r": Vector3(170, 0, 12), "forearm_r": Vector3(30, 0, 0), "leg_l": Vector3(10, 0, -6), "leg_r": Vector3(-6, 0, 6), "root": Vector3(0, 0.04, 0)}, "out"),
		_k(0.62, {"spine": Vector3(-38, 0, 0), "head": Vector3(22, 0, 0), "arm_l": Vector3(55, 0, -5), "forearm_l": Vector3(5, 0, 0), "arm_r": Vector3(55, 0, 5), "forearm_r": Vector3(5, 0, 0), "leg_l": Vector3(45, 0, -8), "shin_l": Vector3(-60, 0, 0), "leg_r": Vector3(-20, 0, 8), "shin_r": Vector3(-30, 0, 0), "root": Vector3(0, -0.28, 0)}, "in"),
		_k(1.2, {"root": Vector3(0, 0, 0)}),
	], 0.62, 0.08, 0.3)
	c["rock"] = _mk(1.1, [
		_k(0.0, {"spine": Vector3(-20, 0, 0), "arm_r": Vector3(40, 0, 20), "forearm_r": Vector3(40, 0, 0), "leg_l": Vector3(20, 0, 0), "shin_l": Vector3(-40, 0, 0), "root": Vector3(0, -0.15, 0)}),
		_k(0.45, {"spine": Vector3(10, -35, 0), "arm_r": Vector3(170, -30, 20), "forearm_r": Vector3(60, 0, 0), "arm_l": Vector3(60, 0, -30), "leg_l": Vector3(25, 0, -5), "leg_r": Vector3(-15, 0, 5), "root": Vector3(0, 0, 0.05)}, "out"),
		_k(0.6, {"spine": Vector3(-14, 25, 0), "arm_r": Vector3(80, 25, 5), "forearm_r": Vector3(0, 0, 0), "arm_l": Vector3(-20, 0, -30), "leg_l": Vector3(35, 0, -5), "shin_l": Vector3(-30, 0, 0), "leg_r": Vector3(-25, 0, 5), "root": Vector3(0, -0.06, -0.1)}, "snap"),
		_k(1.1, {}),
	], 0.58, 0.1, 0.25)
	c["spit"] = c["rock"]
	c["bite"] = _mk(0.7, [
		_k(0.0, {"spine": Vector3(4, -30, 0), "arm_r": Vector3(30, 20, 40), "forearm_r": Vector3(90, 0, 0)}),
		_k(0.3, {"spine": Vector3(-10, 30, 0), "arm_r": Vector3(90, 10, 0), "forearm_r": Vector3(0, 0, 0), "arm_l": Vector3(-20, 0, -30), "leg_l": Vector3(35, 0, -4), "shin_l": Vector3(-35, 0, 0), "root": Vector3(0, -0.08, -0.15)}, "snap"),
		_k(0.7, {}),
	], 0.3)
	c["charge"] = _mk(1.0, [
		_k(0.0, {"spine": Vector3(-25, 0, 0), "arm_l": Vector3(20, 0, -30), "arm_r": Vector3(-30, 0, 25), "forearm_r": Vector3(60, 0, 0), "leg_l": Vector3(30, 0, 0), "shin_l": Vector3(-40, 0, 0), "root": Vector3(0, -0.12, 0)}),
		_k(0.45, {"spine": Vector3(-35, 15, 0), "arm_l": Vector3(70, 0, -40), "forearm_l": Vector3(70, 0, 0), "arm_r": Vector3(-40, 0, 30), "leg_l": Vector3(50, 0, 0), "shin_l": Vector3(-40, 0, 0), "leg_r": Vector3(-30, 0, 0), "root": Vector3(0, -0.14, -0.6)}, "snap"),
		_k(1.0, {"root": Vector3(0, 0, -0.8)}),
	], 0.45)
	c["pounce"] = c["slam"]
	c["howl"] = _mk(1.6, [
		_k(0.0, {}),
		_k(0.4, {"spine": Vector3(12, 0, 0), "head": Vector3(20, 0, 0), "arm_l": Vector3(30, 0, -70), "forearm_l": Vector3(60, 0, 0), "arm_r": Vector3(30, 0, 70), "forearm_r": Vector3(60, 0, 0), "leg_l": Vector3(0, 0, -10), "leg_r": Vector3(0, 0, 10), "root": Vector3(0, -0.06, 0)}),
		_k(1.2, {"spine": Vector3(14, 0, 0), "head": Vector3(24, 0, 0), "arm_l": Vector3(34, 0, -75), "forearm_l": Vector3(55, 0, 0), "arm_r": Vector3(34, 0, 75), "forearm_r": Vector3(55, 0, 0), "leg_l": Vector3(0, 0, -10), "leg_r": Vector3(0, 0, 10), "root": Vector3(0, -0.06, 0)}),
		_k(1.6, {}),
	], -1.0, 0.1, 0.3)
	c["hit_front"] = AnimLib.get_clip("hit_front")
	c["stagger"] = AnimLib.get_clip("stagger")
	c["death"] = AnimLib.get_clip("death")
	return c


# ================================================================ 程序化移动

func _locomotion_pose(delta: float) -> Dictionary:
	_idle_t += delta
	match body:
		"humanoid":
			var p := super._locomotion_pose(delta * 0.8)
			# 石傀：更沉的呼吸与微微前倾
			p["spine"] = (p.get("spine", Vector3.ZERO) as Vector3) + Vector3(-6, 0, 0)
			p["head"] = (p.get("head", Vector3.ZERO) as Vector3) + Vector3(4, 0, 0)
			return p
		"serpent":
			return _serpent_pose(delta)
		"bird":
			return _bird_pose(delta)
		"spider":
			return _spider_pose(delta)
	return _quad_pose(delta)


func _hspeed() -> float:
	return Vector2(local_velocity.x, local_velocity.z).length()


func _quad_pose(delta: float) -> Dictionary:
	var p := {}
	var speed := _hspeed()
	var t := _idle_t
	var sc := maxf(body_scale, 0.2)
	if not grounded and not flying:
		# 腾空：前腿前伸、后腿后蹬
		var vy := local_velocity.y
		var up := clampf(vy * 0.1, -1.0, 1.0)
		p = {
			"hips": Vector3(8 * up, 0, 0), "neck": Vector3(6, 0, 0),
			"leg_fl": Vector3(50, 0, 0), "shin_fl": Vector3(-15, 0, 0), "leg_fr": Vector3(45, 0, 0), "shin_fr": Vector3(-20, 0, 0),
			"leg_bl": Vector3(-45, 0, 0), "shin_bl": Vector3(-10, 0, 0), "leg_br": Vector3(-50, 0, 0), "shin_br": Vector3(-8, 0, 0),
			"base_tail": Vector3(10, 0, 0),
		}
		return p
	if speed > 0.25:
		var gallop := speed > gallop_speed * sc
		var st := stride * sc * (2.0 if gallop else 1.0)
		_gphase = fmod(_gphase + delta * speed / st * TAU, TAU * 64.0)
		var ph := _gphase
		var fwd := -local_velocity.z / speed
		var side := local_velocity.x / speed
		var dir := 1.0 if fwd >= -0.3 else -1.0
		var amp := leg_amp * clampf(0.55 + speed / (gallop_speed * sc) * 0.5, 0.5, 1.25)
		if gallop:
			# 旋转袭步：后腿先后着地，前腿随后；脊柱屈伸，身体起伏
			var bl := sin(ph)
			var br := sin(ph + 0.5)
			var fl := sin(ph + PI * 0.95)
			var fr := sin(ph + PI * 0.95 + 0.5)
			var flex := sin(ph + 0.3)
			p = {
				"hips": Vector3(flex * 7.0, -side * 10.0, 0), "spine": Vector3(-flex * 9.0, side * 12.0, 0),
				"neck": Vector3(-6 + flex * 8.0, side * 10.0, 0), "head": Vector3(-flex * 6.0, side * 6.0, 0),
				"leg_fl": Vector3(fl * amp * 1.2 * dir, 0, 0), "shin_fl": Vector3(-maxf(cos(ph + PI * 0.95), 0.0) * 75.0, 0, 0),
				"leg_fr": Vector3(fr * amp * 1.2 * dir, 0, 0), "shin_fr": Vector3(-maxf(cos(ph + PI * 0.95 + 0.5), 0.0) * 75.0, 0, 0),
				"leg_bl": Vector3(bl * amp * 1.1 * dir, 0, 0), "shin_bl": Vector3(-maxf(cos(ph), 0.0) * 70.0 - 10.0, 0, 0),
				"leg_br": Vector3(br * amp * 1.1 * dir, 0, 0), "shin_br": Vector3(-maxf(cos(ph + 0.5), 0.0) * 70.0 - 10.0, 0, 0),
				"base_tail": Vector3(-15 + flex * 10.0, -side * 20.0, 0), "jaw": Vector3(-12, 0, 0),
			}
			p["root"] = Vector3(0, (sin(ph * 2.0 - 0.6) * 0.5 + 0.2) * 0.06 * sc, 0)
		else:
			# 小跑：对角腿同相
			var a := sin(ph)
			var b := sin(ph + PI)
			p = {
				"hips": Vector3(0, -side * 8.0, a * 2.5), "spine": Vector3(0, side * 10.0, -a * 2.5),
				"neck": Vector3(-4, side * 10.0, 0), "head": Vector3(abs(a) * 3.0, side * 5.0, 0),
				"leg_fl": Vector3(a * amp * dir, 0, 0), "shin_fl": Vector3(-maxf(cos(ph), 0.0) * 55.0, 0, 0),
				"leg_br": Vector3(a * amp * dir, 0, 0), "shin_br": Vector3(-maxf(cos(ph), 0.0) * 50.0 - 6.0, 0, 0),
				"leg_fr": Vector3(b * amp * dir, 0, 0), "shin_fr": Vector3(-maxf(cos(ph + PI), 0.0) * 55.0, 0, 0),
				"leg_bl": Vector3(b * amp * dir, 0, 0), "shin_bl": Vector3(-maxf(cos(ph + PI), 0.0) * 50.0 - 6.0, 0, 0),
				"base_tail": Vector3(-6, sin(ph) * tail_wag * 0.5 - side * 15.0, 0),
			}
			p["root"] = Vector3(0, -absf(cos(ph)) * 0.025 * sc, 0)
		return p
	# 待机：呼吸、左右张望、摇尾
	var br2 := sin(t * 2.0)
	var look := sin(t * 0.37) * 0.7 + sin(t * 0.91) * 0.3
	p = {
		"spine": Vector3(br2 * 1.2, 0, 0), "hips": Vector3(-br2 * 0.6, 0, 0),
		"neck": Vector3(sin(t * 0.5) * 3.0, look * 12.0, 0), "head": Vector3(sin(t * 0.8) * 3.0, look * 8.0, sin(t * 0.3) * 4.0),
		"jaw": Vector3(-maxf(sin(t * 1.3), 0.0) * 4.0, 0, 0),
		"base_tail": Vector3(0, sin(t * 3.2) * tail_wag, 0),
	}
	p["root"] = Vector3(0, br2 * 0.004, 0)
	return p


func _serpent_pose(delta: float) -> Dictionary:
	var p := {}
	var speed := _hspeed()
	var sc := maxf(body_scale, 0.2)
	var n := 0
	while bones.has("seg_%d" % (n + 1)):
		n += 1
	if speed > 0.2:
		_gphase = fmod(_gphase + delta * speed / (1.2 * sc) * TAU, TAU * 64.0)
	else:
		_gphase = fmod(_gphase + delta * 1.2, TAU * 64.0)
	var amp := 22.0 if speed > 0.2 else 7.0
	for i in range(1, n + 1):
		p["seg_%d" % i] = Vector3(0, sin(_gphase - i * 0.95) * amp * (0.6 + i * 0.06), 0)
	var side := local_velocity.x / maxf(speed, 0.01) if speed > 0.2 else 0.0
	p["hips"] = Vector3(0, sin(_gphase) * amp * 0.5 - side * 15.0, 0)
	# 前段昂起（静止时更高），头部补偿保持水平
	var rise := 38.0 if speed < 2.0 else 20.0
	p["neck"] = Vector3(rise + sin(_idle_t * 1.3) * 3.0, -sin(_gphase) * amp * 0.4, 0)
	p["head"] = Vector3(-rise * 0.85, sin(_idle_t * 0.6) * 10.0, 0)
	p["jaw"] = Vector3(-maxf(sin(_idle_t * 2.1), 0.0) * 6.0, 0, 0)
	return p


func _bird_pose(delta: float) -> Dictionary:
	var p := {}
	var speed := _hspeed()
	var t := _idle_t
	var sc := maxf(body_scale, 0.2)
	if flying or not grounded:
		_gphase = fmod(_gphase + delta * (7.0 if speed < 8.0 else 5.0), TAU * 64.0)
		var f := sin(_gphase)
		p = {
			"hips": Vector3(-14, 0, 0), "neck_0": Vector3(-35, 0, 0), "neck_1": Vector3(-5, 0, 0), "head": Vector3(10, 0, 0),
			"wing_l": Vector3(0, 0, -75 - f * 40.0), "wing_tip_l": Vector3(0, 0, -f * 25.0 - 5.0),
			"wing_r": Vector3(0, 0, 75 + f * 40.0), "wing_tip_r": Vector3(0, 0, f * 25.0 + 5.0),
			"leg_l": Vector3(-70, 0, 0), "shin_l": Vector3(10, 0, 0), "leg_r": Vector3(-70, 0, 0), "shin_r": Vector3(10, 0, 0),
		}
		p["root"] = Vector3(0, f * 0.05 * sc, 0)
		return p
	if speed > 0.2:
		_gphase = fmod(_gphase + delta * speed / (0.9 * sc) * TAU, TAU * 64.0)
		var a := sin(_gphase)
		p = {
			"hips": Vector3(-4, 0, a * 4.0), "neck_0": Vector3(-8 + a * 6.0, 0, 0), "neck_1": Vector3(-a * 6.0, 0, 0),
			"leg_l": Vector3(a * 35.0, 0, 0), "shin_l": Vector3(-maxf(cos(_gphase), 0.0) * 60.0, 0, 0),
			"leg_r": Vector3(-a * 35.0, 0, 0), "shin_r": Vector3(-maxf(-cos(_gphase), 0.0) * 60.0, 0, 0),
			"wing_l": Vector3(0, 0, -6), "wing_r": Vector3(0, 0, 6),
		}
		p["root"] = Vector3(0, -absf(cos(_gphase)) * 0.02 * sc, 0)
		return p
	# 待机：优雅地转头、偶尔理羽（抬翅）
	var preen := maxf(sin(t * 0.4) - 0.8, 0.0) * 5.0
	p = {
		"neck_0": Vector3(sin(t * 0.6) * 4.0, sin(t * 0.33) * 20.0, 0), "neck_1": Vector3(sin(t * 0.9) * 5.0, 0, 0),
		"head": Vector3(0, sin(t * 0.5) * 25.0, 0), "hips": Vector3(sin(t * 2.0) * 1.0, 0, 0),
		"wing_l": Vector3(0, 0, -preen * 40.0), "wing_r": Vector3(0, 0, preen * 40.0),
	}
	return p


func _spider_pose(delta: float) -> Dictionary:
	var p := {}
	var speed := _hspeed()
	var sc := maxf(body_scale, 0.2)
	var t := _idle_t
	if speed > 0.2:
		_gphase = fmod(_gphase + delta * speed / (0.7 * sc) * TAU, TAU * 64.0)
	var moving := speed > 0.2
	# 交替四足步态：L1 R2 L3 R4 与 R1 L2 R3 L4 反相
	for i in range(1, 5):
		for sd in ["l", "r"]:
			var group := (i + (0 if sd == "l" else 1)) % 2
			var ph := _gphase + (PI if group == 1 else 0.0)
			var sw := sin(ph) * (26.0 if moving else 0.0)
			var lift := maxf(cos(ph), 0.0) * (30.0 if moving else 0.0)
			var tw := sin(t * 1.3 + i + (0.0 if sd == "l" else 2.0)) * (0.0 if moving else 2.0)
			p["leg_%d%s" % [i, sd]] = Vector3(0, sw, (lift + tw) * (1.0 if sd == "r" else -1.0))
			p["knee_%d%s" % [i, sd]] = Vector3(-lift * 0.5, 0, 0)
	p["hips"] = Vector3(sin(t * 1.5) * 2.0, 0, 0)
	p["spine"] = Vector3(0, 0, sin(_gphase * 2.0) * (2.0 if moving else 0.0))
	p["jaw_l"] = Vector3(0, maxf(sin(t * 2.5), 0.0) * 12.0, 0)
	p["jaw_r"] = Vector3(0, -maxf(sin(t * 2.5), 0.0) * 12.0, 0)
	p["root"] = Vector3(0, (absf(sin(_gphase * 2.0)) * 0.015 if moving else sin(t * 1.5) * 0.004) * sc, 0)
	return p


func _mask_allows(mask: String, b: String) -> bool:
	if body == "humanoid":
		return super._mask_allows(mask, b)
	if mask == "upper":
		return b != "hips" and not b.begins_with("leg") and not b.begins_with("shin") and not b.begins_with("knee")
	return true
