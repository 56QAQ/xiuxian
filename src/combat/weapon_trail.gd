class_name WeaponTrail
extends MeshInstance3D
## 刀光拖尾：记录武器尖端与根部的轨迹，生成渐隐的条带网格（世界坐标）。

const MAX_POINTS := 18
const LIFE := 0.16

var rig: CharacterRig
var color: Color = Color(1, 1, 1)
var active: bool = false
var _pts: Array[Dictionary] = []   ## {tip, base, t}
var _im: ImmediateMesh
var _mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_im = ImmediateMesh.new()
	mesh = _im
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0


func start(c: Color) -> void:
	color = c
	active = true


func stop() -> void:
	active = false


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if active and rig != null and is_instance_valid(rig):
		var tip := rig.weapon_tip("r")
		var hand := rig.bone("hand_r")
		var base := hand.global_position.lerp(tip, 0.3) if hand != null else tip
		_pts.append({"tip": tip, "base": base, "t": now})
		if _pts.size() > MAX_POINTS:
			_pts.pop_front()
	while not _pts.is_empty() and now - float(_pts[0]["t"]) > LIFE:
		_pts.pop_front()
	_im.clear_surfaces()
	if _pts.size() < 2:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in _pts:
		var a := 1.0 - (now - float(p["t"])) / LIFE
		var c := Color(color.r, color.g, color.b, a * 0.85)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p["tip"])
		_im.surface_set_color(Color(c.r, c.g, c.b, a * 0.15))
		_im.surface_add_vertex(p["base"])
	_im.surface_end()
