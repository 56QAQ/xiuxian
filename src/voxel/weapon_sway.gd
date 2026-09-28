class_name WeaponSway
extends Node3D
## 兵器挂件的二次运动（剑穗、枪缨、旗面）：跟随父节点，带惯性地朝重力方向摆动。
## mode:
##   "hinge"    只绕本地 Z 轴（枪杆方向）转动，使旗面/挂件的 -Y 尽量朝下（旗帜）
##   "pendulum" 自由摆（剑穗、流苏）：-Y 朝重力方向并有惯性
## 网格作为本节点的子节点，静止时沿本地 -Y 下垂。

@export var mode: String = "pendulum"
@export var stiffness: float = 10.0     ## 回正速度
@export var damping: float = 4.0
@export var max_angle: float = 75.0     ## 相对静止姿势的最大偏转（度）
@export var flutter: float = 0.0        ## 旗面抖动幅度（度）

var _ang: Vector2 = Vector2.ZERO       ## 当前偏转（x: 绕 X，y: 绕 Z），弧度
var _vel: Vector2 = Vector2.ZERO
var _prev_pos: Vector3 = Vector3.ZERO
var _prev_vel: Vector3 = Vector3.ZERO
var _init_done := false
var _t := 0.0
var _rest: Basis = Basis.IDENTITY


func _ready() -> void:
	_rest = transform.basis


func _process(delta: float) -> void:
	if delta <= 0.0 or not is_inside_tree():
		return
	var dt := minf(delta, 0.05)
	_t += dt
	var parent := get_parent() as Node3D
	if parent == null:
		return
	var gp := global_position
	if not _init_done:
		_prev_pos = gp
		_init_done = true
	var vel := (gp - _prev_pos) / dt
	var acc := (vel - _prev_vel) / dt
	_prev_pos = gp
	_prev_vel = vel
	# 有效重力 = 重力 - 加速度（惯性），换算到父节点（静止姿势）空间
	var g := Vector3.DOWN * 9.8 - acc.limit_length(60.0) * 0.6
	var pb := (parent.global_basis * _rest).orthonormalized()
	var gl := pb.inverse() * g
	var target := Vector2.ZERO
	match mode:
		"hinge":
			# 绕 Z 旋转 θ 后 -Y 方向 = (sinθ, -cosθ)，令其对齐 gl 的 XY 投影
			var gxy := Vector2(gl.x, gl.y)
			if gxy.length() > 0.5:
				target.y = atan2(gxy.x, -gxy.y)
		_:
			var gn := gl.normalized()
			target.x = atan2(-gn.z, -gn.y)
			target.y = atan2(gn.x, -gn.y)
	var lim := deg_to_rad(max_angle)
	target = target.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	_vel += (target - _ang) * stiffness * dt - _vel * damping * dt
	_ang += _vel * dt
	var fl := 0.0
	if flutter > 0.0:
		fl = deg_to_rad(flutter) * sin(_t * 9.0) * clampf(vel.length() * 0.2, 0.2, 1.0)
	var rot := Basis(Vector3.RIGHT, _ang.x + fl * 0.3) * Basis(Vector3.BACK, _ang.y + fl)
	if mode == "hinge":
		rot = Basis(Vector3.BACK, _ang.y + fl)
	transform.basis = _rest * rot
