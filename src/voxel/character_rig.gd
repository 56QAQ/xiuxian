class_name CharacterRig
extends Node3D
## 体素角色骨架 + 程序动画引擎。
##
## 由 CharacterBuilder 创建：它负责生成各骨骼节点（Node3D，名字见 BONES）与体素网格，
## 然后调用 setup()。本脚本负责：程序化移动动画、动作剪辑播放/混合、弹簧骨骼（发尾/兽尾）、
## 受击闪白与溶解。
##
## 坐标约定（全部骨骼静止旋转为单位旋转）：
## - 角色面朝 -Z，右手在 +X，左手在 -X，Y 向上。
## - 向下垂的肢体（手臂、腿）：+X 旋转 = 向前摆；小腿弯曲（膝）= -X；小臂弯曲（肘）= +X。
## - 向上的骨骼（spine、head）：-X 旋转 = 前倾/低头。
## - 右臂 +Z 旋转 = 向外侧抬起；左臂 -Z 旋转 = 向外侧抬起。
## - +Y 旋转 = 向左转。
## - 武器挂在 hand_r / hand_l 下：握把在原点，刃沿本地 -Z。
## 姿势（pose）：Dictionary，骨骼名 -> Vector3（欧拉角，度）；"root" -> Vector3（hips 位移，米）。

signal anim_event(event_name: String)
signal action_finished(clip_name: String)

const BONES: Array[String] = [
	"hips", "spine", "head",
	"arm_l", "forearm_l", "hand_l",
	"arm_r", "forearm_r", "hand_r",
	"leg_l", "shin_l", "leg_r", "shin_r",
]
const UPPER_BONES: Array[String] = ["spine", "head", "arm_l", "forearm_l", "hand_l", "arm_r", "forearm_r", "hand_r"]
const ARM_BONES: Array[String] = ["arm_r", "forearm_r", "hand_r"]
## 弹簧骨骼名前缀：名字以这些开头的骨骼自动参与二次运动
const SPRING_PREFIXES: Array[String] = ["hair_", "tail", "ear_", "cloth_"]

var bones: Dictionary = {}
var rest: Dictionary = {}
var meshes: Array[MeshInstance3D] = []
## 身高缩放（builder 写入），影响步幅
var body_scale: float = 1.0
var voxel_size: float = 1.0 / 36.0

# ---- 移动状态（由 Actor 每帧写入）
var local_velocity: Vector3 = Vector3.ZERO  ## 角色本地空间速度（-Z 为前）
var grounded: bool = true
var boosting: bool = false
var flying: bool = false
var meditating: bool = false
var stance: String = "fist"      ## 武器类型，决定待机持械姿势
var aim_pitch: float = 0.0       ## 瞄准俯仰（度），影响上身

# ---- 动作剪辑
var _clip: Dictionary = {}
var _clip_name: String = ""
var _clip_time: float = 0.0
var _clip_speed: float = 1.0
var _clip_weight: float = 0.0
var _clip_fading_out: bool = false
var _fired_events: Dictionary = {}

# ---- 程序动画相位
var _phase: float = 0.0
var _time: float = 0.0
var _loco_blend: Dictionary = {}   ## bone -> Quaternion（平滑后的移动姿势）
var _root_offset: Vector3 = Vector3.ZERO
var _lean: Vector2 = Vector2.ZERO

# ---- 弹簧骨骼
var _springs: Array[Dictionary] = []

# ---- 闪白
var _flash: float = 0.0
var _flash_color: Color = Color.WHITE


func setup() -> void:
	bones.clear()
	rest.clear()
	meshes.clear()
	_springs.clear()
	_collect(self)
	for b in bones:
		rest[b] = (bones[b] as Node3D).transform
	for bn in bones:
		for pre in SPRING_PREFIXES:
			if String(bn).begins_with(pre):
				var node: Node3D = bones[bn]
				_springs.append({
					"bone": node, "name": bn,
					"tip": Vector3.ZERO,
					"prev": Vector3.ZERO,
					"len": float(node.get_meta("spring_length", 0.3)),
					"stiff": float(node.get_meta("spring_stiffness", 0.12)),
					"limit": deg_to_rad(float(node.get_meta("spring_limit", 60.0))),
					"dir": node.get_meta("spring_dir", Vector3.DOWN),
					"init": false,
				})
				break


func _collect(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			meshes.append(c)
		if c is Node3D:
			if BONES.has(c.name) or _is_spring_name(c.name) or c.has_meta("bone"):
				bones[String(c.name)] = c
		_collect(c)


func _is_spring_name(n: String) -> bool:
	for pre in SPRING_PREFIXES:
		if n.begins_with(pre):
			return true
	return false


func bone(n: String) -> Node3D:
	return bones.get(n, null)


# ================================================================ 公共接口

func set_locomotion(vel_local: Vector3, is_grounded: bool, is_boosting: bool, is_flying: bool) -> void:
	local_velocity = vel_local
	grounded = is_grounded
	boosting = is_boosting
	flying = is_flying


## 播放动作剪辑（见 AnimLib）。返回剪辑时长（秒，已计入速度）
func play(clip_name: String, speed: float = 1.0) -> float:
	var clip := AnimLib.get_clip(clip_name)
	if clip.is_empty():
		push_warning("CharacterRig: 未知动作 %s" % clip_name)
		return 0.0
	return play_clip(clip, clip_name, speed)


func play_clip(clip: Dictionary, clip_name: String = "", speed: float = 1.0) -> float:
	_clip = clip
	_clip_name = clip_name
	_clip_time = 0.0
	_clip_speed = maxf(speed, 0.01)
	_clip_fading_out = false
	_fired_events.clear()
	if _clip_weight <= 0.0:
		_clip_weight = 0.0001
	return float(clip.get("length", 0.5)) / _clip_speed


func stop_action() -> void:
	if not _clip.is_empty():
		_clip_fading_out = true


func is_playing() -> bool:
	return not _clip.is_empty() and not _clip_fading_out


func current_action() -> String:
	return _clip_name if is_playing() else ""


func flash(amount: float = 1.0, color: Color = Color.WHITE) -> void:
	_flash = maxf(_flash, amount)
	_flash_color = color
	_apply_instance_param("flash_color", color)


func set_dissolve(v: float) -> void:
	_apply_instance_param("dissolve", v)


func set_tint(c: Color, amount: float) -> void:
	_apply_instance_param("tint", Color(c.r, c.g, c.b, amount))


func _apply_instance_param(p: String, v: Variant) -> void:
	for m in meshes:
		if is_instance_valid(m):
			m.set_instance_shader_parameter(p, v)


## 把节点挂到手上（清空该手原有挂件）
func attach_to_hand(node: Node3D, hand: String = "r") -> void:
	var h := bone("hand_" + hand)
	if h == null:
		return
	for c in h.get_children():
		if c.has_meta("attachment"):
			h.remove_child(c)
			c.queue_free()
	if node != null:
		node.set_meta("attachment", true)
		h.add_child(node)
		_collect_meshes(node)


func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		meshes.append(n)
	for c in n.get_children():
		_collect_meshes(c)


## 手中武器尖端的世界坐标（用于刀光拖尾）
func weapon_tip(hand: String = "r") -> Vector3:
	var h := bone("hand_" + hand)
	if h == null:
		return global_position
	for c in h.get_children():
		if c.has_meta("attachment") and c is Node3D:
			var tip: float = float(c.get_meta("tip_length", 0.9))
			return (c as Node3D).global_transform * Vector3(0, 0, -tip)
	return h.global_position


# ================================================================ 每帧

func _process(delta: float) -> void:
	if bones.is_empty():
		return
	_time += delta
	var pose := _locomotion_pose(delta)
	# 平滑移动姿势，避免状态切换时跳变
	var loco := {}
	var k := 1.0 - exp(-14.0 * delta)
	for b in pose:
		if b == "root":
			continue
		var q := _euler_q(pose[b])
		var prev: Quaternion = _loco_blend.get(b, q)
		loco[b] = prev.slerp(q, k)
		_loco_blend[b] = loco[b]
	var root_target: Vector3 = pose.get("root", Vector3.ZERO)
	_root_offset = _root_offset.lerp(root_target, k)
	var root := _root_offset
	# 动作剪辑
	var action := {}
	var action_root := Vector3.ZERO
	var mask := "full"
	if not _clip.is_empty():
		var len_c := float(_clip.get("length", 0.5))
		var bi := float(_clip.get("blend_in", 0.06))
		var bo := float(_clip.get("blend_out", 0.12))
		_clip_time += delta * _clip_speed
		_fire_events()
		if _clip.get("hold", false) and _clip_time >= len_c and not _clip_fading_out:
			if not _fired_events.has("__finished"):
				_fired_events["__finished"] = true
				action_finished.emit(_clip_name)
			_clip_weight = minf(_clip_weight + delta / maxf(bi, 0.01), 1.0)
		elif _clip_fading_out or (_clip_time >= len_c and not _clip.get("loop", false)):
			if not _clip_fading_out:
				_clip_fading_out = true
				action_finished.emit(_clip_name)
			_clip_weight -= delta / maxf(bo, 0.01)
			if _clip_weight <= 0.0:
				_clip_weight = 0.0
				_clip = {}
				_clip_name = ""
		else:
			_clip_weight = minf(_clip_weight + delta / maxf(bi, 0.01), 1.0)
		if not _clip.is_empty():
			var t := fmod(_clip_time, len_c) if _clip.get("loop", false) else minf(_clip_time, len_c)
			var sampled := _sample(_clip, t)
			mask = str(_clip.get("mask", "full"))
			for b in sampled:
				if b == "root":
					action_root = sampled[b]
				else:
					action[b] = _euler_q(sampled[b])
	var w := _smoothstep(_clip_weight)
	for b in bones:
		if not rest.has(b) or _is_spring_name(b):
			continue
		var q: Quaternion = loco.get(b, Quaternion.IDENTITY)
		if action.has(b) and _mask_allows(mask, b):
			q = q.slerp(action[b], w)
		var rt: Transform3D = rest[b]
		var node: Node3D = bones[b]
		node.transform = Transform3D(rt.basis * Basis(q), rt.origin)
	if bones.has("hips"):
		var hips: Node3D = bones["hips"]
		var ro := root
		if mask == "full" and w > 0.0:
			ro = root.lerp(action_root, w)
		elif action_root != Vector3.ZERO:
			ro = root + action_root * w
		hips.position = (rest["hips"] as Transform3D).origin + ro
	_update_springs(delta)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		_apply_instance_param("flash", _flash)


func _mask_allows(mask: String, b: String) -> bool:
	match mask:
		"upper":
			return UPPER_BONES.has(b)
		"arm":
			return ARM_BONES.has(b)
	return true


func _fire_events() -> void:
	for ev in _clip.get("events", []):
		var t := float(ev.get("t", 0.0))
		var n := str(ev.get("name", ""))
		var key := "%s@%f" % [n, t]
		if _clip_time >= t and not _fired_events.has(key):
			_fired_events[key] = true
			anim_event.emit(n)


## 关键帧采样：相邻两帧之间用平滑插值
func _sample(clip: Dictionary, t: float) -> Dictionary:
	var keys: Array = clip.get("keys", [])
	if keys.is_empty():
		return {}
	if keys.size() == 1 or t <= float(keys[0]["t"]):
		return keys[0]["pose"]
	for i in range(keys.size() - 1):
		var a: Dictionary = keys[i]
		var b: Dictionary = keys[i + 1]
		var ta := float(a["t"])
		var tb := float(b["t"])
		if t <= tb:
			var f := 0.0 if tb <= ta else (t - ta) / (tb - ta)
			f = _ease(f, str(b.get("ease", "smooth")))
			return _lerp_pose(a["pose"], b["pose"], f)
	return keys[keys.size() - 1]["pose"]


static func _ease(f: float, mode: String) -> float:
	match mode:
		"linear":
			return f
		"in":
			return f * f
		"out":
			return 1.0 - (1.0 - f) * (1.0 - f)
		"snap":
			return 1.0 - pow(1.0 - f, 4.0)
	return f * f * (3.0 - 2.0 * f)


static func _lerp_pose(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	var out := {}
	for k in a:
		out[k] = (a[k] as Vector3).lerp(b.get(k, a[k]), f)
	for k in b:
		if not out.has(k):
			out[k] = Vector3.ZERO.lerp(b[k], f)
	return out


static func _euler_q(deg: Vector3) -> Quaternion:
	return Quaternion.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z)))


static func _smoothstep(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# ================================================================ 程序化移动姿势

func _locomotion_pose(delta: float) -> Dictionary:
	if meditating:
		return AnimLib.pose("meditate").merged({"root": Vector3(0, -0.52 * body_scale, 0)}, true)
	var p: Dictionary = AnimLib.stance_pose(stance).duplicate()
	var hv := Vector2(local_velocity.x, local_velocity.z)
	var speed := hv.length()
	var breathe := sin(_time * 2.2)
	if not grounded or flying:
		if boosting or speed > 9.0:
			# 御风疾行：身体前倾，双臂后掠
			var fwd := -local_velocity.z / maxf(speed, 0.01)
			var side := local_velocity.x / maxf(speed, 0.01)
			var lean := 32.0 * clampf(fwd, -0.3, 1.0)
			p = _merge(p, {
				"hips": Vector3(-lean, 0, -side * 18.0),
				"spine": Vector3(-8, 0, 0), "head": Vector3(lean * 0.7, 0, 0),
				"arm_l": Vector3(-35, 0, -25), "forearm_l": Vector3(10, 0, 0),
				"leg_l": Vector3(-10, 0, -4), "shin_l": Vector3(-35, 0, 0),
				"leg_r": Vector3(8, 0, 4), "shin_r": Vector3(-15, 0, 0),
			}, stance == "fist")
			p["root"] = Vector3(0, sin(_time * 3.0) * 0.03, 0)
			return p
		if flying:
			p = _merge(p, {
				"hips": Vector3(-6, 0, 0), "spine": Vector3(2, 0, 0),
				"arm_l": Vector3(5, 0, -18), "forearm_l": Vector3(15, 0, 0),
				"leg_l": Vector3(6, 0, -3), "shin_l": Vector3(-20, 0, 0),
				"leg_r": Vector3(-4, 0, 3), "shin_r": Vector3(-8, 0, 0),
			}, true)
			p["root"] = Vector3(0, sin(_time * 2.0) * 0.05, 0)
			return p
		# 跳跃/下落
		var vy := local_velocity.y
		var tuck := clampf(0.5 - vy * 0.08, 0.0, 1.0)
		p = _merge(p, {
			"hips": Vector3(-5, 0, 0),
			"arm_l": Vector3(-15, 0, -35), "forearm_l": Vector3(20, 0, 0),
			"leg_l": Vector3(45 * tuck, 0, -4), "shin_l": Vector3(-80 * tuck, 0, 0),
			"leg_r": Vector3(10 * tuck, 0, 4), "shin_r": Vector3(-40 * tuck, 0, 0),
		}, true)
		return p
	if boosting and speed > 6.0:
		# 地面疾行：低姿态滑行
		var fwd2 := -local_velocity.z / maxf(speed, 0.01)
		var side2 := local_velocity.x / maxf(speed, 0.01)
		p = _merge(p, {
			"hips": Vector3(-28 * fwd2, 0, -side2 * 15.0), "spine": Vector3(-6, 0, 0), "head": Vector3(20 * fwd2, 0, 0),
			"arm_l": Vector3(-45, 0, -20), "forearm_l": Vector3(15, 0, 0),
			"leg_l": Vector3(35, 0, -5), "shin_l": Vector3(-60, 0, 0),
			"leg_r": Vector3(-20, 0, 5), "shin_r": Vector3(-30, 0, 0),
		}, stance == "fist")
		p["root"] = Vector3(0, -0.12 * body_scale, 0)
		return p
	if speed > 0.3:
		# 行走/奔跑循环
		var stride := 1.1 * body_scale
		_phase += delta * speed / stride * PI
		var run := clampf((speed - 2.0) / 5.0, 0.0, 1.0)
		var amp := lerpf(28.0, 50.0, run)
		var s := sin(_phase)
		var c := cos(_phase)
		var fwd3 := -local_velocity.z / speed
		var side3 := local_velocity.x / speed
		var dir := 1.0 if fwd3 >= -0.2 else -1.0
		var leg_amp := amp * (absf(fwd3) + absf(side3) * 0.6)
		p = _merge(p, {
			"hips": Vector3(-8 * run * dir, -side3 * 25.0 * dir, s * 3.0),
			"spine": Vector3(-4 * run, side3 * 15.0 * dir + s * 6.0 * run, 0),
			"head": Vector3(4 * run, -side3 * 10.0 * dir - s * 4.0 * run, 0),
			"arm_l": Vector3(s * amp * 0.8, 0, -8 - run * 6),
			"forearm_l": Vector3(20 + run * 50 + maxf(s, 0) * 20, 0, 0),
			"arm_r": Vector3(-s * amp * 0.8, 0, 8 + run * 6),
			"forearm_r": Vector3(20 + run * 50 + maxf(-s, 0) * 20, 0, 0),
			"leg_l": Vector3(-s * leg_amp * dir, 0, -side3 * 6), "shin_l": Vector3(-(maxf(c, 0.0) * (30 + 60 * run)) - 5, 0, 0),
			"leg_r": Vector3(s * leg_amp * dir, 0, side3 * 6), "shin_r": Vector3(-(maxf(-c, 0.0) * (30 + 60 * run)) - 5, 0, 0),
		}, stance == "fist")
		p["root"] = Vector3(0, -absf(c) * 0.05 * (0.5 + run) * body_scale, 0)
		return p
	# 待机：呼吸
	p["spine"] = (p.get("spine", Vector3.ZERO) as Vector3) + Vector3(breathe * 1.5, 0, 0)
	p["head"] = (p.get("head", Vector3.ZERO) as Vector3) + Vector3(-breathe * 1.0, 0, 0)
	p["arm_l"] = (p.get("arm_l", Vector3.ZERO) as Vector3) + Vector3(0, 0, -breathe * 1.5)
	p["root"] = Vector3(0, breathe * 0.004, 0)
	return p


## 双手持握的兵器：移动时双臂都保持持械姿势
const TWO_HANDED: Array[String] = ["spear"]
const LEFT_ARM_BONES: Array[String] = ["arm_l", "forearm_l", "hand_l"]


## 把 add 合并进 base；override_right_arm=false 时保留右臂的持械姿势（双手兵器同时保留左臂）
func _merge(base: Dictionary, add: Dictionary, override_right_arm: bool) -> Dictionary:
	var out := base.duplicate()
	var keep_left := not override_right_arm and TWO_HANDED.has(stance)
	for k in add:
		if not override_right_arm and ARM_BONES.has(k):
			continue
		if keep_left and LEFT_ARM_BONES.has(k):
			continue
		out[k] = add[k]
	return out


# ================================================================ 弹簧骨骼

func _update_springs(delta: float) -> void:
	if _springs.is_empty() or delta <= 0.0:
		return
	var dt := minf(delta, 0.05)
	for s in _springs:
		var node: Node3D = s["bone"]
		if not is_instance_valid(node):
			continue
		var parent := node.get_parent() as Node3D
		var rest_t: Transform3D = rest.get(s["name"], node.transform)
		var pivot := node.global_position
		var rest_dir: Vector3 = (parent.global_basis * rest_t.basis * (s["dir"] as Vector3)).normalized()
		var length: float = s["len"]
		if not s["init"]:
			s["tip"] = pivot + rest_dir * length
			s["prev"] = s["tip"]
			s["init"] = true
		var tip: Vector3 = s["tip"]
		var prev: Vector3 = s["prev"]
		var vel := (tip - prev) * 0.86
		var target := pivot + rest_dir * length
		var new_tip := tip + vel + (target - tip) * float(s["stiff"]) + Vector3.DOWN * 2.0 * dt * dt
		# 约束长度
		new_tip = pivot + (new_tip - pivot).normalized() * length
		# 约束角度
		var cur_dir := (new_tip - pivot).normalized()
		var ang := rest_dir.angle_to(cur_dir)
		var limit: float = s["limit"]
		if ang > limit:
			var axis := rest_dir.cross(cur_dir)
			if axis.length_squared() > 1e-6:
				cur_dir = rest_dir.rotated(axis.normalized(), limit)
				new_tip = pivot + cur_dir * length
		s["prev"] = tip
		s["tip"] = new_tip
		# 应用旋转：在父空间中把 rest_dir 转到 cur_dir
		var rot := Quaternion(rest_dir, cur_dir) if rest_dir.dot(cur_dir) < 0.9999 else Quaternion.IDENTITY
		var world_basis := Basis(rot) * (parent.global_basis * rest_t.basis)
		node.basis = (parent.global_basis.inverse() * world_basis).orthonormalized()
