class_name VfxRibbon
extends MeshInstance3D
## 世界空间拖尾条带：跟随目标节点（或手动 add_point）记录轨迹，Catmull-Rom 平滑，朝向镜头，尾部收窄渐隐。
## 用于弹道尾迹、疾行灵气尾流、飞剑残影、陨星火尾等。停止后（stop）在点全部过期时自动释放。

var target: Node3D
var offset: Vector3 = Vector3.ZERO     ## 目标局部偏移
var width: float = 0.3
var life: float = 0.25                 ## 轨迹点存活时间（秒）
var color: Color = Color.WHITE
var taper: float = 0.0                 ## 尾部宽度倍率（0 为尖）
var min_step: float = 0.08             ## 采样最小间距（米）
var subdiv: int = 3
var alpha: float = 1.0
var _emitting: bool = true
var _clock: float = 0.0
var _pos: PackedVector3Array = PackedVector3Array()
var _t: PackedFloat32Array = PackedFloat32Array()
var _im: ImmediateMesh
var _cam: Camera3D


## 创建并挂到管理器下。profile：center / wake / fire / bolt（见 VfxLib.ribbon_mat）
static func create(tgt: Node3D, col: Color, w: float, lifetime: float, profile: String = "center", local_offset: Vector3 = Vector3.ZERO) -> VfxRibbon:
	var r := VfxRibbon.new()
	r.target = tgt
	r.color = col
	r.width = w
	r.life = lifetime
	r.offset = local_offset
	r.material_override = VfxLib.ribbon_mat(profile)
	var m := VfxManager.get_mgr()
	if m == null:
		r.free()
		return null
	m.add(r)
	return r


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_im = ImmediateMesh.new()
	mesh = _im
	extra_cull_margin = 4.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		add_point(target.global_transform * offset)


func stop() -> void:
	_emitting = false
	target = null


func is_emitting() -> bool:
	return _emitting


func add_point(p: Vector3) -> void:
	var n := _pos.size()
	if n > 0 and _pos[n - 1].distance_squared_to(p) < min_step * min_step:
		# 距离太近时只更新最新点，保持头部贴合目标
		if n > 1:
			_pos[n - 1] = p
			_t[n - 1] = _clock
		return
	_pos.append(p)
	_t.append(_clock)


func _process(delta: float) -> void:
	_clock += delta
	if _emitting:
		if target == null or not is_instance_valid(target) or not target.is_inside_tree():
			_emitting = false
		else:
			add_point(target.global_transform * offset)
	# 过期点
	var drop := 0
	while drop < _t.size() and _clock - _t[drop] > life:
		drop += 1
	if drop > 0:
		_pos = _pos.slice(drop)
		_t = _t.slice(drop)
	if not _emitting and _pos.size() < 2:
		queue_free()
		return
	_rebuild()


func _cam_pos() -> Vector3:
	if _cam == null or not is_instance_valid(_cam):
		_cam = get_viewport().get_camera_3d() if get_viewport() != null else null
	return _cam.global_position if _cam != null else Vector3(0, 10, 10)


static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _rebuild() -> void:
	_im.clear_surfaces()
	var n := _pos.size()
	if n < 2:
		return
	# 平滑采样（从最新到最旧）
	var pts := PackedVector3Array()
	var ages := PackedFloat32Array()
	for k in range(n - 1, 0, -1):
		var p0 := _pos[mini(k + 1, n - 1)]
		var p1 := _pos[k]
		var p2 := _pos[k - 1]
		var p3 := _pos[maxi(k - 2, 0)]
		var a1 := (_clock - _t[k]) / life
		var a2 := (_clock - _t[k - 1]) / life
		for s in subdiv:
			var f := float(s) / subdiv
			pts.append(_cr(p0, p1, p2, p3, f))
			ages.append(lerpf(a1, a2, f))
	pts.append(_pos[0])
	ages.append((_clock - _t[0]) / life)
	var cam := _cam_pos()
	var m := pts.size()
	# 总长用于 UV（年龄）以外的宽度收窄
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var c := Color(color.r, color.g, color.b, alpha)
	for i in m:
		var p := pts[i]
		var tan: Vector3
		if i == 0:
			tan = pts[0] - pts[1]
		elif i == m - 1:
			tan = pts[m - 2] - pts[m - 1]
		else:
			tan = pts[i - 1] - pts[i + 1]
		var side := tan.cross(cam - p)
		if side.length_squared() < 1e-8:
			side = Vector3.UP
		side = side.normalized()
		var age := clampf(ages[i], 0.0, 1.0)
		var w := width * lerpf(1.0, taper, age) * 0.5
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(age, 0.0))
		_im.surface_add_vertex(p - side * w)
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(age, 1.0))
		_im.surface_add_vertex(p + side * w)
	_im.surface_end()
