class_name WeaponTrail
extends MeshInstance3D
## 刀光拖尾：记录武器尖端与根部的轨迹，Catmull-Rom 平滑成条带（刃口一侧最亮、根部柔和、随时间收窄消散）。
## release_arc()：在出手帧截取这一刀的轨迹，生成沿真实挥砍路径的剑气月牙（FX.slash_arc）。

const MAX_POINTS := 28
const LIFE := 0.2
const SUBDIV := 4
const ARC_BEFORE := 0.17     ## 月牙包含出手前的轨迹时长
const ARC_AFTER := 0.06      ## 出手后继续采样的时长

var rig: CharacterRig
var color: Color = Color(1, 1, 1)
var elem: String = Elem.NONE
var active: bool = false
var _clock: float = 0.0
var _tips: PackedVector3Array = PackedVector3Array()
var _bases: PackedVector3Array = PackedVector3Array()
var _times: PackedFloat32Array = PackedFloat32Array()
var _im: ImmediateMesh
var _arc: Dictionary = {}    ## 待生成的月牙 {from, until, heavy, color}


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_im = ImmediateMesh.new()
	mesh = _im
	material_override = VfxLib.ribbon_mat("blade")
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0


func start(c: Color, element: String = "") -> void:
	color = c
	if element != "":
		elem = element
	active = true


func stop() -> void:
	active = false
	if not _arc.is_empty():
		_flush_arc()


## 在出手帧调用：继续采样片刻后，以本刀轨迹生成剑气月牙
func release_arc(heavy: bool, c: Color = Color(0, 0, 0, 0)) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	if not _arc.is_empty():
		_flush_arc()
	_arc = {"from": _clock - ARC_BEFORE, "until": _clock + ARC_AFTER, "heavy": heavy, "color": color if c.a <= 0.0 else c}


func _process(delta: float) -> void:
	_clock += delta
	if (active or not _arc.is_empty()) and rig != null and is_instance_valid(rig) and rig.is_inside_tree():
		var tip := rig.weapon_tip("r")
		var hand := rig.bone("hand_r")
		var base := hand.global_position.lerp(tip, 0.3) if hand != null else tip
		var n := _tips.size()
		if n == 0 or _tips[n - 1].distance_squared_to(tip) > 0.0004:
			_tips.append(tip)
			_bases.append(base)
			_times.append(_clock)
		if _tips.size() > MAX_POINTS:
			_tips = _tips.slice(1)
			_bases = _bases.slice(1)
			_times = _times.slice(1)
	if not _arc.is_empty() and _clock >= float(_arc["until"]):
		_flush_arc()
	var drop := 0
	var keep := LIFE if _arc.is_empty() else ARC_BEFORE + ARC_AFTER + 0.05
	while drop < _times.size() and _clock - _times[drop] > keep:
		drop += 1
	if drop > 0:
		_tips = _tips.slice(drop)
		_bases = _bases.slice(drop)
		_times = _times.slice(drop)
	_rebuild()


func _flush_arc() -> void:
	var from := float(_arc["from"])
	var until := float(_arc["until"])
	var tips := PackedVector3Array()
	var bases := PackedVector3Array()
	for i in _times.size():
		if _times[i] >= from and _times[i] <= until + 0.001:
			tips.append(_tips[i])
			bases.append(_bases[i])
	var heavy := bool(_arc["heavy"])
	var c: Color = _arc["color"]
	_arc = {}
	if tips.size() >= 3 and rig != null and is_instance_valid(rig):
		# 挥砍幅度太小（如直刺）时不生成月牙
		if tips[0].distance_to(tips[tips.size() - 1]) > 0.5:
			FX.slash_arc(_smooth(tips), _smooth(bases), rig.global_position + Vector3.UP * 1.0, elem, c, heavy)


## Catmull-Rom 细分
static func _smooth(src: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := src.size()
	for i in n - 1:
		var p0 := src[maxi(i - 1, 0)]
		var p1 := src[i]
		var p2 := src[i + 1]
		var p3 := src[mini(i + 2, n - 1)]
		for s in SUBDIV:
			out.append(VfxRibbon._cr(p0, p1, p2, p3, float(s) / SUBDIV))
	out.append(src[n - 1])
	return out


func _rebuild() -> void:
	_im.clear_surfaces()
	var n := _tips.size()
	if n < 2:
		return
	# 只绘制 LIFE 内的点
	var first := 0
	while first < n and _clock - _times[first] > LIFE:
		first += 1
	if n - first < 2:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(first, n - 1):
		var i0 := maxi(i - 1, first)
		var i3 := mini(i + 2, n - 1)
		for s in SUBDIV:
			var f := float(s) / SUBDIV
			var tip := VfxRibbon._cr(_tips[i0], _tips[i], _tips[i + 1], _tips[i3], f)
			var base := VfxRibbon._cr(_bases[i0], _bases[i], _bases[i + 1], _bases[i3], f)
			var t := lerpf(_times[i], _times[i + 1], f)
			_emit(tip, base, t)
	_emit(_tips[n - 1], _bases[n - 1], _times[n - 1])
	_im.surface_end()


func _emit(tip: Vector3, base: Vector3, t: float) -> void:
	var age := clampf((_clock - t) / LIFE, 0.0, 1.0)
	# 越旧越窄：根部向刃口收拢
	var b := base.lerp(tip, age * 0.55)
	var c := Color(color.r, color.g, color.b, 1.0)
	_im.surface_set_color(c)
	_im.surface_set_uv(Vector2(age, 1.0))
	_im.surface_add_vertex(tip)
	_im.surface_set_color(c)
	_im.surface_set_uv(Vector2(age, 0.0))
	_im.surface_add_vertex(b)
