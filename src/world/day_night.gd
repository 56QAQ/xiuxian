class_name DayNight
extends Node3D
## 昼夜：按 GS.hour_of_day() 驱动太阳/月亮方向光、风格化天空（sky.gdshader）、环境光与雾色，
## 并带一层缓慢漂移的体素云。WorldEnvironment：AgX 色调映射、SSAO、辉光、指数雾 + 高度雾。
## 兼容渲染器下不支持的效果会被引擎自动忽略。

const TILT := deg_to_rad(30.0)   ## 太阳轨道向南倾斜
const CLOUD_Y := 215.0

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ShaderMaterial
var clouds: MeshInstance3D
var hour := 9.0
## 当前（线性空间外观的）天空/水面参考色，供水面着色器使用
var sky_tint := Color(0.6, 0.75, 0.9)
var water: Node = null
var shadow_distance := 220.0
var _cloud_offset := 0.0
var _cloud_mat: ShaderMaterial
var _last_applied := -99.0


func _ready() -> void:
	_build()
	apply_hour(hour)


func _build() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://assets/shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0008
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.25
	env.fog_sun_scatter = 0.2
	env.fog_height = 14.0
	env.fog_height_density = 0.006
	env.volumetric_fog_enabled = false
	env.sdfgi_enabled = false
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = shadow_distance
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.6
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 120.0
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)

	clouds = _build_clouds()
	add_child(clouds)


## 太阳方向（指向太阳）
static func sun_direction(h: float) -> Vector3:
	var a := (h - 6.0) / 12.0 * PI
	return Vector3(cos(a), sin(a) * cos(TILT), sin(a) * sin(TILT)).normalized()


func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	if absf(hour - _last_applied) > 0.002:
		apply_hour(hour)


func _process(delta: float) -> void:
	# 云层缓慢漂移（循环）
	_cloud_offset = fmod(_cloud_offset + delta * 1.6, 256.0)
	if clouds:
		clouds.position = Vector3(_cloud_offset, CLOUD_Y, _cloud_offset * 0.35)


func apply_hour(h: float) -> void:
	_last_applied = h
	var sd := sun_direction(h)
	var md := -sd
	md = (md + Vector3(0.0, 0.0, -0.25)).normalized()
	var e := sd.y
	# 太阳
	_orient(sun, sd)
	var day := smoothstep(-0.04, 0.22, e)
	var warm := 1.0 - smoothstep(0.02, 0.45, e)
	sun.light_color = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.58, 0.32), warm)
	sun.light_energy = 1.45 * day
	sun.visible = day > 0.001
	sun.shadow_enabled = day > 0.02
	# 月亮
	_orient(moon, md)
	var night := smoothstep(0.0, 0.2, md.y) * (1.0 - day)
	moon.light_energy = 0.32 * night
	moon.visible = night > 0.01
	moon.shadow_enabled = night > 0.2
	# 天空关键帧（按太阳高度）
	var zen: Color
	var hor: Color
	var glow_c: Color
	var amb: Color
	var fog: Color
	var amb_e: float
	var keys := [
		[-0.35, Color(0.015, 0.02, 0.06), Color(0.04, 0.06, 0.13), Color(0.2, 0.2, 0.4), Color(0.13, 0.17, 0.30), Color(0.05, 0.07, 0.13), 0.55],
		[-0.08, Color(0.08, 0.10, 0.24), Color(0.40, 0.30, 0.38), Color(0.9, 0.4, 0.3), Color(0.30, 0.28, 0.40), Color(0.28, 0.24, 0.32), 0.5],
		[0.04, Color(0.26, 0.38, 0.66), Color(1.0, 0.64, 0.42), Color(1.0, 0.55, 0.3), Color(0.62, 0.52, 0.52), Color(0.86, 0.66, 0.54), 0.5],
		[0.2, Color(0.24, 0.46, 0.82), Color(0.80, 0.84, 0.88), Color(1.0, 0.78, 0.5), Color(0.58, 0.62, 0.72), Color(0.74, 0.80, 0.88), 0.55],
		[0.6, Color(0.20, 0.44, 0.86), Color(0.70, 0.83, 0.96), Color(1.0, 0.9, 0.7), Color(0.56, 0.64, 0.78), Color(0.70, 0.80, 0.92), 0.6],
	]
	var k0: Array = keys[0]
	var k1: Array = keys[keys.size() - 1]
	var t := 0.0
	if e <= float(k0[0]):
		k1 = k0
	elif e >= float(k1[0]):
		k0 = k1
	else:
		for i in keys.size() - 1:
			if e >= float(keys[i][0]) and e < float(keys[i + 1][0]):
				k0 = keys[i]
				k1 = keys[i + 1]
				t = (e - float(k0[0])) / (float(k1[0]) - float(k0[0]))
				break
	t = smoothstep(0.0, 1.0, t)
	zen = (k0[1] as Color).lerp(k1[1], t)
	hor = (k0[2] as Color).lerp(k1[2], t)
	glow_c = (k0[3] as Color).lerp(k1[3], t)
	amb = (k0[4] as Color).lerp(k1[4], t)
	fog = (k0[5] as Color).lerp(k1[5], t)
	amb_e = lerpf(float(k0[6]), float(k1[6]), t)
	sky_mat.set_shader_parameter("zenith_color", zen)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("ground_color", hor.darkened(0.45))
	sky_mat.set_shader_parameter("sun_glow_color", glow_c)
	sky_mat.set_shader_parameter("moon_dir", md)
	sky_mat.set_shader_parameter("moon_intensity", smoothstep(-0.05, 0.1, md.y) * (1.0 - day * 0.8))
	sky_mat.set_shader_parameter("star_intensity", smoothstep(0.0, -0.25, e))
	env.ambient_light_color = amb
	env.ambient_light_energy = amb_e
	env.fog_light_color = fog
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.35 * warm * day
	sky_tint = hor.lerp(zen, 0.35)
	if clouds:
		var cc := Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.72, 0.6), warm * day)
		cc = cc.lerp(Color(0.16, 0.19, 0.3), 1.0 - maxf(day, 0.15))
		_cloud_mat.set_shader_parameter("tint", Color(cc.r, cc.g, cc.b))
	if water and water.has_method("set_sky_color"):
		water.call("set_sky_color", sky_tint, day)


func _orient(light: DirectionalLight3D, toward: Vector3) -> void:
	var up := Vector3.UP if absf(toward.y) < 0.98 else Vector3.RIGHT
	light.basis = Basis.looking_at(-toward, up)


## 体素云：在 12 米网格上按噪声阈值放置扁平方块，按行合并。
func _build_clouds() -> MeshInstance3D:
	var n := FastNoiseLite.new()
	n.seed = 777
	n.frequency = 1.0 / 180.0
	n.fractal_octaves = 3
	var n2 := FastNoiseLite.new()
	n2.seed = 991
	n2.frequency = 1.0 / 40.0
	var bm := BuildingMesh.new(5)
	bm.jitter = 0.0
	var cell := 12.0
	var half := 1400.0
	var cnt := int(half * 2.0 / cell)
	var white := Color(1, 1, 1)
	var shade := Color(0.86, 0.88, 0.93)
	for j in cnt:
		var run_start := -1
		var run_th := 0
		for i in cnt + 1:
			var x := -half + i * cell + 512.0
			var z := -half + j * cell + 512.0
			var v := -1.0
			if i < cnt:
				v = n.get_noise_2d(x, z) + 0.25 * n2.get_noise_2d(x, z)
			var th := 0
			if v > 0.34:
				th = 1 if v < 0.46 else 2
			if th != run_th:
				if run_th > 0 and run_start >= 0:
					var x0 := -half + run_start * cell + 512.0
					var x1 := -half + i * cell + 512.0
					var hgt := 5.0 * run_th
					bm.box(Vector3(x0, -hgt * 0.5, z), Vector3(x1, hgt * 0.5, z + cell), white if run_th == 2 else shade)
				run_start = i
				run_th = th
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = load("res://assets/shaders/cloud.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = bm.build_mesh(_cloud_mat)
	mi.name = "Clouds"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, CLOUD_Y, 0)
	mi.extra_cull_margin = 400.0
	return mi
