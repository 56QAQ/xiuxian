class_name FreeCam
extends Camera3D
## 调试自由飞行相机（占位玩家）：WASD 移动，Space/Ctrl 升降，Shift 加速，滚轮调速；
## 鼠标左/右键捕获鼠标后转动视角，Esc 或 Alt 释放。

var speed := 24.0
var fast_mult := 6.0
var yaw := 0.0
var pitch := -0.25
var _captured := false


func _ready() -> void:
	current = true
	near = 0.1
	far = 4000.0
	fov = 70.0
	rotation = Vector3(pitch, yaw, 0.0)


## 从当前朝向同步 yaw/pitch（外部 look_at 之后调用）
func sync_angles() -> void:
	var e := global_transform.basis.get_euler()
	pitch = e.x
	yaw = e.y


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			_set_captured(true)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed = minf(speed * 1.2, 400.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed = maxf(speed / 1.2, 2.0)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and (k.keycode == KEY_ESCAPE or k.keycode == KEY_ALT):
			_set_captured(false)
	elif event is InputEventMouseMotion and _captured:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * Settings.mouse_sensitivity
		pitch = clampf(pitch - mm.relative.y * Settings.mouse_sensitivity, -1.55, 1.55)
		rotation = Vector3(pitch, yaw, 0.0)


func _set_captured(v: bool) -> void:
	_captured = v
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if v else Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	var b := global_transform.basis
	if Input.is_action_pressed("move_forward"):
		dir -= b.z
	if Input.is_action_pressed("move_back"):
		dir += b.z
	if Input.is_action_pressed("move_left"):
		dir -= b.x
	if Input.is_action_pressed("move_right"):
		dir += b.x
	if Input.is_action_pressed("jump"):
		dir += Vector3.UP
	if Input.is_action_pressed("descend"):
		dir -= Vector3.UP
	if dir == Vector3.ZERO:
		return
	var s := speed * (fast_mult if Input.is_action_pressed("boost") else 1.0)
	global_position += dir.normalized() * s * delta
