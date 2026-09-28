class_name CameraRig
extends Node3D
## 第三人称越肩镜头：鼠标环视、弹簧臂防穿墙、锁定时自动对准目标、推进时 FOV 拉伸、创伤式震屏。
## 表现：瞬步/疾行起步的 FOV 冲击、重击时的 FOV 收缩与屏幕径向模糊/色散（ScreenFx）、高速疾行速度线。

const SHOULDER := Vector3(0.55, 1.65, 0.0)
const DISTANCE := 4.3
const BOOST_DISTANCE := 5.2
const PITCH_MIN := -70.0
const PITCH_MAX := 55.0

var target: Node3D
var yaw: float = 0.0
var pitch: float = -12.0
var trauma: float = 0.0
var camera: Camera3D
var arm: SpringArm3D
var _pivot: Node3D
var _fov_extra: float = 0.0
var _dist: float = DISTANCE
var _noise := FastNoiseLite.new()
var _t: float = 0.0
var _follow: Vector3
var screen: ScreenFx
var _fov_kick: float = 0.0       ## FOV 冲击（度），弹簧回弹
var _fov_kick_v: float = 0.0
var _qb_prev: float = 0.0
var _boost_prev: bool = false


func _ready() -> void:
	add_to_group("camera_rig")
	top_level = true
	_pivot = Node3D.new()
	add_child(_pivot)
	arm = SpringArm3D.new()
	arm.spring_length = DISTANCE
	arm.collision_mask = 1
	var s := SphereShape3D.new()
	s.radius = 0.25
	arm.shape = s
	arm.margin = 0.1
	_pivot.add_child(arm)
	camera = Camera3D.new()
	camera.fov = Settings.fov
	camera.far = 1500.0
	camera.near = 0.08
	arm.add_child(camera)
	camera.current = true
	_noise.frequency = 2.5
	screen = ScreenFx.new()
	screen.name = "ScreenFx"
	add_child(screen)
	if target != null:
		_follow = target.global_position
		arm.add_excluded_object(target.get_rid())


func set_target(t: Node3D) -> void:
	target = t
	if t != null:
		_follow = t.global_position
		yaw = t.global_rotation.y
		if arm != null and t is CollisionObject3D:
			arm.add_excluded_object((t as CollisionObject3D).get_rid())


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## 重击冲击：FOV 短暂收缩 + 屏幕径向模糊/色散（强度随 Settings.camera_shake）
func impact_kick(amount: float) -> void:
	var k := clampf(amount, 0.0, 1.0) * clampf(Settings.camera_shake, 0.0, 1.5)
	_fov_kick_v -= 60.0 * k
	if screen != null:
		screen.kick(amount)


## FOV 冲击（正值拉宽，负值收缩）
func fov_punch(deg: float) -> void:
	_fov_kick_v += deg * 25.0


func _ui_blocking() -> bool:
	var ui := get_tree().get_first_node_in_group("ui_manager")
	return ui != null and ui.has_method("is_blocking") and bool(ui.call("is_blocking"))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _ui_blocking():
		var m := event as InputEventMouseMotion
		var sens := Settings.mouse_sensitivity
		yaw -= m.relative.x * sens
		pitch += (m.relative.y if Settings.invert_y else -m.relative.y) * sens * 57.2958
		pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_t += delta
	# 跟随：水平紧跟，垂直略有迟滞
	var tp := target.global_position
	_follow.x = tp.x
	_follow.z = tp.z
	_follow.y = lerpf(_follow.y, tp.y, 1.0 - exp(-12.0 * delta))
	if absf(_follow.y - tp.y) > 3.0:
		_follow.y = tp.y
	# 锁定：镜头转向目标
	var lock: Node3D = target.get("lock_target")
	if lock != null and is_instance_valid(lock):
		var to := lock.global_position + Vector3.UP * 1.0 - (_follow + SHOULDER.y * Vector3.UP)
		var want_yaw := atan2(-to.x, -to.z)
		yaw = lerp_angle(yaw, want_yaw, 1.0 - exp(-7.0 * delta))
		var flat := Vector2(to.x, to.z).length()
		var want_pitch := rad_to_deg(atan2(to.y, flat)) - 6.0
		pitch = lerpf(pitch, clampf(want_pitch, PITCH_MIN, PITCH_MAX), 1.0 - exp(-4.0 * delta))
	# 推进：拉远 + FOV
	var speed := 0.0
	if target is CharacterBody3D:
		speed = (target as CharacterBody3D).velocity.length()
	var boosting: bool = target.get("boosting") == true
	var want_extra := clampf((speed - 8.0) * 0.7, 0.0, 12.0) if boosting or speed > 14.0 else 0.0
	_fov_extra = lerpf(_fov_extra, want_extra, 1.0 - exp(-4.0 * delta))
	# 瞬步 / 疾行起步：FOV 冲击（弹簧回弹）
	var qb = target.get("qb_timer")
	var qbt := float(qb) if qb != null else 0.0
	if qbt > _qb_prev + 0.05:
		fov_punch(5.0)
	_qb_prev = qbt
	if boosting and not _boost_prev:
		fov_punch(2.5)
	_boost_prev = boosting
	var rdt := delta / maxf(Engine.time_scale, 0.05)
	_fov_kick_v += (-_fov_kick * 170.0 - _fov_kick_v * 18.0) * rdt
	_fov_kick = clampf(_fov_kick + _fov_kick_v * rdt, -8.0, 10.0)
	camera.fov = Settings.fov + _fov_extra + _fov_kick
	# 速度线：高速疾行 / 瞬步
	if screen != null:
		screen.speed = clampf((speed - 16.0) / 18.0, 0.0, 1.0) * 0.85 if boosting or qbt > 0.0 else 0.0
	_dist = lerpf(_dist, BOOST_DISTANCE if boosting else DISTANCE, 1.0 - exp(-3.0 * delta))
	arm.spring_length = _dist
	global_position = _follow
	_pivot.rotation = Vector3(0, yaw, 0)
	_pivot.position = Vector3(0, SHOULDER.y, 0)
	arm.rotation = Vector3(deg_to_rad(pitch), 0, 0)
	arm.position = _pivot.basis.inverse() * Vector3.ZERO + Vector3(SHOULDER.x, 0, 0)
	# 震屏
	trauma = maxf(trauma - delta * 1.6, 0.0)
	var s := trauma * trauma
	camera.h_offset = _noise.get_noise_2d(_t * 40.0, 0.0) * s * 0.35
	camera.v_offset = _noise.get_noise_2d(0.0, _t * 40.0) * s * 0.35
	camera.rotation = Vector3(0, 0, _noise.get_noise_2d(_t * 30.0, 50.0) * s * 0.06)


## 镜头前方（水平）
func forward_flat() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func right_flat() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


## 屏幕中心指向的世界坐标（射线检测世界与角色）
func aim_point(exclude: Array[RID] = [], max_dist: float = 250.0) -> Vector3:
	var from := camera.global_position
	var dir := -camera.global_basis.z
	var to := from + dir * max_dist
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4 | (1 << 6), exclude)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"]
	return to
