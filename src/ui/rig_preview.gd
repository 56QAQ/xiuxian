class_name RigPreview
extends SubViewportContainer
## 体素角色 3D 预览（独立 World3D + 透明背景 + 影棚布光 + 体素石台）。
## 拖动旋转、滚轮缩放；set_appearance() 防抖（默认 0.15 秒）后重建角色。
## 捏人、角色面板、储物袋纸娃娃、对话头像共用。
##
## 影棚：暖色主光（柔和阴影）+ 冷色补光 + 两道轮廓光（冷月光 / 暖灯光），SSAO、轻辉光、
##       程序天空只用于环境光与金属反射（背景保持透明，透出水墨界面）；
##       地面为“只显示阴影”的投影层；背后一轮淡墨月晕（backdrop）；玉石金边的体素石台。
## 取景：full 全身 · upper 半身 · bust 面容特写（按角色身高自动对准头部）· face 更近的脸部特写

signal rebuilt(rig: CharacterRig)

## 取景：full 全身 · upper 半身 · bust 面容 · face 脸部特写
@export var framing: String = "full"
@export var allow_rotate: bool = true
@export var allow_zoom: bool = true
@export var pedestal: bool = true
## 背后淡墨月晕
@export var backdrop: bool = true
## 自动缓慢旋转（度/秒）
@export var auto_spin: float = 0.0
@export var debounce: float = 0.15

var appearance: Dictionary = {}
var equip_visual: Dictionary = {}
var yaw: float = -18.0
var zoom: float = 1.0
var meditating: bool = false
var rig: CharacterRig

var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _pending: float = -1.0
var _drag: bool = false
var _yaw_vel: float = 0.0
var _cam_look: Vector3 = Vector3(0, 0.95, 0)
var _cam_dist: float = 3.6
var _backdrop: MeshInstance3D

## look：注视点（米，按身高 1.0 的角色）；half：需要完整入镜的半高/半宽（米）；fov：竖直视角；h：镜头相对注视点的高度
## 距离按视口宽高比自动求出（窄视口也不会裁掉头部）
const FRAMES := {
	"full": {"look": Vector3(0, 0.96, 0), "half": Vector2(1.2, 0.72), "fov": 30.0, "h": 0.2},
	"upper": {"look": Vector3(0, 1.28, 0), "half": Vector2(0.6, 0.46), "fov": 30.0, "h": 0.06},
	"bust": {"look": Vector3(0, 1.5, 0), "half": Vector2(0.33, 0.3), "fov": 27.0, "h": 0.03},
	"face": {"look": Vector3(0, 1.52, 0), "half": Vector2(0.22, 0.24), "fov": 26.0, "h": 0.02},
}

const _BACKDROP_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 halo : source_color = vec4(1.0, 0.93, 0.8, 0.22);
uniform vec4 ring : source_color = vec4(0.95, 0.78, 0.45, 0.35);
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	// 淡墨晕：中心暖白、向外渐隐，边缘带笔触噪声
	float brush = noise(vec2(a * 3.0, r * 6.0)) * 0.5 + noise(vec2(a * 9.0, r * 14.0)) * 0.25;
	float h = smoothstep(1.0, 0.15, r + brush * 0.18);
	// 细金环（法阵意味），断续
	float rr = abs(r - 0.78 - brush * 0.02);
	float g = smoothstep(0.018, 0.0, rr) * step(0.28, noise(vec2(a * 5.0, 1.7)));
	float g2 = smoothstep(0.008, 0.0, abs(r - 0.7)) * 0.6;
	vec4 c = halo * h;
	c = mix(c, ring, clamp(g + g2, 0.0, 1.0) * ring.a / max(ring.a, 0.001));
	ALBEDO = c.rgb;
	ALPHA = clamp(halo.a * h + (g + g2) * ring.a, 0.0, 1.0);
}
"""


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(160, 220)


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.positional_shadow_atlas_size = 1024
	_vp.size = Vector2i(maxi(int(size.x), 64), maxi(int(size.y), 64))
	add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	_build_studio()
	if pedestal:
		_world.add_child(build_pedestal(20, 1234))
	if backdrop:
		_world.add_child(_make_backdrop())
	_cam = Camera3D.new()
	_world.add_child(_cam)
	_apply_framing(true)
	if not appearance.is_empty() or rig == null:
		rebuild_now()


## 影棚：环境 + 四盏平行光 + 投影地面
func _build_studio() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	# 程序天空只作环境光与反射来源（背景透明）：上方暖白、地平线偏暖、下方深青
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.62, 0.66, 0.78)
	sky_mat.sky_horizon_color = Color(0.95, 0.86, 0.72)
	sky_mat.ground_horizon_color = Color(0.5, 0.42, 0.36)
	sky_mat.ground_bottom_color = Color(0.1, 0.12, 0.14)
	sky_mat.sun_angle_max = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.55
	e.ambient_light_sky_contribution = 0.85
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.ssao_enabled = true
	e.ssao_radius = 0.35
	e.ssao_intensity = 1.6
	e.ssao_power = 1.3
	e.ssao_detail = 0.8
	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.glow_strength = 0.9
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.1
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.06
	e.adjustment_contrast = 1.04
	env.environment = e
	_world.add_child(env)
	# 主光：左前上方暖光，柔和阴影
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.rotation_degrees = Vector3(-40, -38, 0)
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.92, 0.8)
	key.shadow_enabled = true
	key.shadow_blur = 2.2
	key.shadow_bias = 0.02
	key.shadow_normal_bias = 1.2
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 8.0
	_world.add_child(key)
	# 补光：右前方低位冷光（压暗面，不产生阴影）
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-12, 42, 0)
	fill.light_energy = 0.32
	fill.light_color = Color(0.75, 0.84, 1.0)
	fill.light_specular = 0.2
	_world.add_child(fill)
	# 轮廓光：右后上方冷月光 + 左后方暖灯光（勾出发丝与肩甲边缘）
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.rotation_degrees = Vector3(-25, 150, 0)
	rim.light_energy = 1.1
	rim.light_color = Color(0.62, 0.78, 1.0)
	rim.light_specular = 0.8
	_world.add_child(rim)
	var rim2 := DirectionalLight3D.new()
	rim2.name = "Rim2"
	rim2.rotation_degrees = Vector3(-18, -160, 0)
	rim2.light_energy = 0.55
	rim2.light_color = Color(1.0, 0.72, 0.45)
	rim2.light_specular = 0.6
	_world.add_child(rim2)
	# 投影地面：只显示阴影（透明背景上的柔和脚底阴影）
	var ground := MeshInstance3D.new()
	ground.name = "ShadowCatcher"
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shadow_to_opacity = true
	gm.albedo_color = Color(0.02, 0.03, 0.04, 0.85)
	ground.material_override = gm
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position.y = 0.0
	_world.add_child(ground)


## 背后淡墨月晕（面向镜头的竖直圆盘；角色转动时镜头不动，月晕始终正对）
func _make_backdrop() -> MeshInstance3D:
	_backdrop = MeshInstance3D.new()
	_backdrop.name = "Backdrop"
	var q := QuadMesh.new()
	q.size = Vector2(3.4, 3.4)
	_backdrop.mesh = q
	var sh := Shader.new()
	sh.code = _BACKDROP_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	_backdrop.material_override = m
	_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backdrop.position = Vector3(0, 1.05, -1.6)
	return _backdrop


func set_appearance(a: Dictionary, eq: Dictionary = {}, immediate: bool = false) -> void:
	if rig != null and a == appearance and eq == equip_visual and _pending < 0.0:
		return
	appearance = a.duplicate(true)
	equip_visual = eq.duplicate(true)
	if immediate or not is_inside_tree():
		_pending = -1.0
		if is_inside_tree():
			rebuild_now()
	else:
		_pending = debounce


## 由玩家数据求外观与装备外观（武器 visual、法衣 outfit 覆盖）
static func equip_visual_for(p: PlayerData) -> Dictionary:
	var out := {}
	var w := p.equipped("weapon")
	if w != null:
		var vis: Dictionary = w.def().get("weapon", {}).get("visual", {})
		if not vis.is_empty() and str(vis.get("kind", "")) != "fist":
			out["weapon"] = vis
	var ar := p.equipped("armor")
	# 与 HumanoidActor 一致：凡品法衣不覆盖玩家自选的服饰外观
	if ar != null and ar.get_grade() >= 1:
		var ov: Dictionary = ar.def().get("equip", {}).get("visual", {})
		if not ov.is_empty():
			out["outfit"] = ov
	return out


func show_player(p: PlayerData) -> void:
	set_appearance(p.appearance, equip_visual_for(p))


func rebuild_now() -> void:
	_pending = -1.0
	if _world == null:
		return
	if rig != null:
		rig.queue_free()
		rig = null
	# 预览总在近处：不挂远景 LOD
	rig = CharacterBuilder.build(appearance, equip_visual, {"lod": false})
	rig.meditating = meditating
	_world.add_child(rig)
	if pedestal:
		rig.position.y = 0.1
	_apply_yaw()
	_apply_framing(false)
	rebuilt.emit(rig)


func set_framing(f: String) -> void:
	framing = f
	_apply_framing(false)


## 取景目标（按角色身高缩放头部位置）
func _frame_target() -> Dictionary:
	var fr: Dictionary = FRAMES.get(framing, FRAMES["full"])
	var scale_h := rig.body_scale if rig != null else 1.0
	var look: Vector3 = fr["look"]
	if framing != "full":
		look.y *= scale_h
	if pedestal:
		look.y += 0.1
	var half: Vector2 = fr["half"]
	var t := tan(deg_to_rad(float(fr["fov"])) * 0.5)
	var aspect := 1.0
	if _vp != null and _vp.size.y > 0:
		aspect = float(_vp.size.x) / float(_vp.size.y)
	var dist := maxf(half.x / t, half.y / (t * maxf(aspect, 0.2)))
	return {"look": look, "dist": dist, "fov": fr["fov"], "h": fr["h"]}


func _apply_framing(snap: bool) -> void:
	var fr := _frame_target()
	if snap:
		_cam_look = fr["look"]
		_cam_dist = fr["dist"]
	if _cam != null:
		_cam.fov = fr["fov"]
		_update_camera()


func _update_camera() -> void:
	if _cam == null:
		return
	var fr := _frame_target()
	_cam.position = _cam_look + Vector3(0, float(fr["h"]), _cam_dist * zoom)
	_cam.look_at(_cam_look, Vector3.UP)
	if _backdrop != null:
		# 月晕跟随取景高度，特写时略缩小
		_backdrop.position.y = lerpf(_backdrop.position.y, _cam_look.y + (0.15 if framing == "full" else 0.05), 0.2)
		var sc := 1.0 if framing == "full" else (0.62 if framing == "upper" else 0.42)
		_backdrop.scale = _backdrop.scale.lerp(Vector3.ONE * sc, 0.2)


func _apply_yaw() -> void:
	if rig != null:
		rig.rotation_degrees.y = 180.0 + yaw


func _process(delta: float) -> void:
	if _pending >= 0.0:
		_pending -= delta
		if _pending < 0.0:
			rebuild_now()
	if not _drag:
		if absf(_yaw_vel) > 0.1:
			yaw += _yaw_vel * delta
			_yaw_vel = lerpf(_yaw_vel, 0.0, 1.0 - exp(-4.0 * delta))
		elif auto_spin != 0.0:
			yaw += auto_spin * delta
	_apply_yaw()
	var fr := _frame_target()
	var k := 1.0 - exp(-8.0 * delta)
	_cam_look = _cam_look.lerp(fr["look"], k)
	_cam_dist = lerpf(_cam_dist, float(fr["dist"]), k)
	_update_camera()
	if _vp != null and size.x > 1.0 and not stretch:
		_vp.size = Vector2i(size)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and allow_rotate:
			_drag = event.pressed
			accept_event()
		elif allow_zoom and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom - 0.08, 0.45, 1.35)
			accept_event()
		elif allow_zoom and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom + 0.08, 0.45, 1.35)
			accept_event()
	elif event is InputEventMouseMotion and _drag:
		yaw += event.relative.x * 0.6
		_yaw_vel = event.relative.x * 30.0
		accept_event()


## 体素石台：墨玉圆台（上下两层、侧面竖纹）+ 金边 + 台面云纹金环与中心太极点。radius 为旧单位（0.025m）半径
static func build_pedestal(radius: int = 20, seed_value: int = 1) -> Node3D:
	var R := radius * 2
	var mk := func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-R - 2, -8, -R - 2), Vector3i(R + 1, 1, R + 1))
		var ink := Color(0.1, 0.12, 0.13)
		var jade := Color(0.16, 0.24, 0.22)
		var gold := Color(0.86, 0.66, 0.3)
		var gold_hi := gold.lerp(Color(1, 0.96, 0.8), 0.5)
		for z in range(-R - 2, R + 2):
			for x in range(-R - 2, R + 2):
				var d := Vector2(x + 0.5, z + 0.5).length()
				if d > R + 1.5:
					continue
				var h := VoxCanvas.h3(x >> 1, seed_value, z >> 1)
				var stone := ink.lerp(jade, 0.25 + 0.35 * float(h & 7) / 7.0)
				# 下层（宽）与上层（收一圈）
				var top := 0 if d <= R - 1.5 else -3
				cv.set_mat(VoxCanvas.M_STONE)
				for y in range(-8, top + 1):
					var c := stone.darkened(0.2 * float(-y) / 8.0)
					# 侧面竖纹
					if d > R - 0.5 and posmod(int(floor(atan2(z, x) * 24.0)), 3) == 0:
						c = c.darkened(0.15)
					cv.put(x, y, z, c)
				cv.set_mat(VoxCanvas.M_GOLD)
				if d > R + 0.5:
					cv.put(x, -3, z, gold)
				elif d > R - 1.5 and d <= R - 0.5:
					cv.put(x, 0, z, gold_hi)
				elif d > R - 5.5 and d < R - 4.2:
					cv.put(x, 0, z, gold)
				elif d < 9.0 and d > 7.8:
					cv.put(x, 0, z, gold)
				elif d < 7.8:
					# 中心太极（阴阳两色）
					var yin := (x + 0.5) < 0.0
					var p1 := Vector2(x + 0.5, z + 0.5 - 3.9).length() < 3.9
					var p2 := Vector2(x + 0.5, z + 0.5 + 3.9).length() < 3.9
					if p1:
						yin = false
					if p2:
						yin = true
					cv.set_mat(VoxCanvas.M_JADE)
					cv.put(x, 0, z, Color(0.9, 0.88, 0.8) if not yin else Color(0.08, 0.1, 0.1))
				# 台面云纹金环（两圈之间的断续卷云）
				if d > R - 4.2 and d < R - 1.5:
					var seg := posmod(int(floor((atan2(z + 0.5, x + 0.5) + PI) / TAU * 36.0)), 3)
					if seg == 0 and absf(d - (R - 2.9)) < 0.7:
						cv.putm(x, 0, z, gold, VoxCanvas.M_GOLD)
		return cv
	var cv0: VoxCanvas = mk.call()
	var mi := MeshInstance3D.new()
	mi.mesh = VoxMesh.build_one(cv0, CharacterBuilder.VOXEL)
	mi.name = "Pedestal"
	mi.position.y = 0.1 - 1.0 * CharacterBuilder.VOXEL
	return mi
