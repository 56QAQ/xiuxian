class_name DayNight
extends Node3D
## 昼夜：按 GS.hour_of_day() 驱动太阳/月亮方向光、国风天空（sky.gdshader：水墨远山、写意云、日月星辰）、
## 环境光、雾与体积雾、夜间窗纸透光（BlockTex 环境参数）与夜灯（group "night_light"）。
## 环境配置由 Atmosphere 统一生成（AgX、SSAO + SSIL、辉光、空气透视雾 + 高度雾、体积雾光柱、3D LUT 调色）。
## 调色板按太阳高度在关键帧之间插值：深夜月色（蓝）→ 蓝调时刻 → 日出（桃粉）→ 清晨 → 正午（青绿）。
## 兼容渲染器下不支持的效果会被引擎自动忽略。

const TILT := deg_to_rad(30.0)   ## 太阳轨道向南倾斜
## 参数刷新阈值（时辰）：约每 0.6 秒现实时间刷新一次天空与环境
const APPLY_STEP := 0.01

## 关键帧：[太阳高度 sin, 调色板]（字段见 Atmosphere.DAY）
static var KEYS: Array = [
	[-0.30, {
		"zenith": Color(0.014, 0.024, 0.058), "horizon": Color(0.05, 0.08, 0.15), "haze": Color(0.07, 0.10, 0.18), "glow": Color(0.20, 0.22, 0.40),
		"ambient": Color(0.22, 0.30, 0.50), "amb_e": 0.55, "fog": Color(0.06, 0.09, 0.16), "fog_d": 0.85, "fog_end": 700.0,
		"vol": Color(0.55, 0.62, 0.80), "vol_d": 0.004, "ink": Color(0.02, 0.035, 0.07), "mist": Color(0.08, 0.11, 0.19),
		"cloud_l": Color(0.22, 0.27, 0.40), "cloud_s": Color(0.05, 0.07, 0.12), "sun": Color(1.0, 0.6, 0.35), "sun_e": 0.0,
		"exposure": 1.25, "cloud": 0.38}],
	[-0.08, {
		"zenith": Color(0.09, 0.12, 0.26), "horizon": Color(0.36, 0.30, 0.42), "haze": Color(0.50, 0.38, 0.44), "glow": Color(0.85, 0.45, 0.38),
		"ambient": Color(0.34, 0.33, 0.48), "amb_e": 0.5, "fog": Color(0.30, 0.27, 0.36), "fog_d": 0.85, "fog_end": 850.0,
		"vol": Color(0.70, 0.62, 0.70), "vol_d": 0.005, "ink": Color(0.13, 0.12, 0.20), "mist": Color(0.40, 0.33, 0.42),
		"cloud_l": Color(0.78, 0.48, 0.50), "cloud_s": Color(0.22, 0.20, 0.30), "sun": Color(1.0, 0.5, 0.3), "sun_e": 0.0,
		"exposure": 1.1, "cloud": 0.42}],
	[0.03, {
		"zenith": Color(0.30, 0.40, 0.64), "horizon": Color(0.98, 0.68, 0.46), "haze": Color(1.0, 0.76, 0.56), "glow": Color(1.0, 0.55, 0.28),
		"ambient": Color(0.56, 0.52, 0.58), "amb_e": 0.5, "fog": Color(0.88, 0.70, 0.56), "fog_d": 0.85, "fog_end": 900.0,
		"vol": Color(1.0, 0.82, 0.66), "vol_d": 0.006, "ink": Color(0.34, 0.28, 0.36), "mist": Color(0.92, 0.74, 0.62),
		"cloud_l": Color(1.0, 0.74, 0.52), "cloud_s": Color(0.46, 0.38, 0.46), "sun": Color(1.0, 0.60, 0.34), "sun_e": 1.2,
		"exposure": 1.0, "cloud": 0.45}],
	[0.18, {
		"zenith": Color(0.30, 0.50, 0.78), "horizon": Color(0.78, 0.84, 0.86), "haze": Color(0.88, 0.88, 0.84), "glow": Color(1.0, 0.82, 0.58),
		"ambient": Color(0.52, 0.60, 0.68), "amb_e": 0.56, "fog": Color(0.76, 0.81, 0.84), "fog_d": 0.76, "fog_end": 1150.0,
		"vol": Color(0.96, 0.94, 0.90), "vol_d": 0.003, "ink": Color(0.42, 0.52, 0.56), "mist": Color(0.82, 0.86, 0.86),
		"cloud_l": Color(1.0, 0.97, 0.92), "cloud_s": Color(0.64, 0.70, 0.78), "sun": Color(1.0, 0.90, 0.74), "sun_e": 1.6,
		"exposure": 0.9, "cloud": 0.45}],
	[0.55, Atmosphere.DAY],
]

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ShaderMaterial
var hour := 9.0
## 当前天空/水面参考色，供水面着色器使用
var sky_tint := Color(0.6, 0.75, 0.9)
var water: Node = null
var shadow_distance := 220.0
## 夜晚程度 0~1（黄昏开始点亮夜灯）
var night_amount := 0.0
## 当前调色板（插值结果）
var palette: Dictionary = {}
## 区域调节（AmbientFX 按生物群系写入）：雾浓度倍率、体积雾倍率、雾色调（a 为混合量）
var fog_scale := 1.0
var vol_scale := 1.0
var fog_tint := Color(1, 1, 1, 0)
var _cloud_time := 0.0
var _last_applied := -99.0


func _ready() -> void:
	_build()
	apply_hour(hour)


func _exit_tree() -> void:
	BlockTex.set_env({"night_glow": 0.0})


func _build() -> void:
	env = Atmosphere.make_environment()
	sky_mat = env.sky.sky_material as ShaderMaterial
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	Atmosphere.setup_sun(sun, shadow_distance)
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 120.0
	moon.shadow_blur = 2.0
	moon.light_color = Color(0.60, 0.72, 1.0)
	moon.light_volumetric_fog_energy = 2.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)


## 太阳方向（指向太阳）
static func sun_direction(h: float) -> Vector3:
	var a := (h - 6.0) / 12.0 * PI
	return Vector3(cos(a), sin(a) * cos(TILT), sin(a) * sin(TILT)).normalized()


func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	var dh := absf(hour - _last_applied)
	dh = minf(dh, 24.0 - dh)
	if dh > APPLY_STEP:
		apply_hour(hour)


func _process(delta: float) -> void:
	_cloud_time += delta


## 按太阳高度插值关键帧
static func palette_at(e: float) -> Dictionary:
	var k0: Array = KEYS[0]
	var k1: Array = KEYS[KEYS.size() - 1]
	if e <= float(k0[0]):
		return (k0[1] as Dictionary).duplicate()
	if e >= float(k1[0]):
		return (k1[1] as Dictionary).duplicate()
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if e >= float(a[0]) and e < float(b[0]):
			var t := smoothstep(0.0, 1.0, (e - float(a[0])) / (float(b[0]) - float(a[0])))
			return Atmosphere.lerp_palette(a[1], b[1], t)
	return (k1[1] as Dictionary).duplicate()


func apply_hour(h: float) -> void:
	_last_applied = h
	var sd := sun_direction(h)
	var md := -sd
	md = (md + Vector3(0.0, 0.0, -0.25)).normalized()
	var e := sd.y
	palette = palette_at(e)
	if fog_tint.a > 0.0:
		palette["fog"] = (palette["fog"] as Color).lerp(Color(fog_tint.r, fog_tint.g, fog_tint.b), fog_tint.a)
		palette["mist"] = (palette["mist"] as Color).lerp(Color(fog_tint.r, fog_tint.g, fog_tint.b), fog_tint.a * 0.5)
	palette["fog_d"] = float(palette["fog_d"]) * fog_scale
	palette["vol_d"] = float(palette["vol_d"]) * vol_scale
	# 太阳
	_orient(sun, sd)
	var day := smoothstep(-0.04, 0.22, e)
	palette["sun_e"] = float(palette["sun_e"]) * smoothstep(-0.03, 0.08, e)
	Atmosphere.apply(env, sky_mat, sun, palette)
	sun.visible = day > 0.001
	sun.shadow_enabled = day > 0.02
	var warm := 1.0 - smoothstep(0.02, 0.45, e)
	# 月亮（月夜：冷蓝月光，带阴影）
	_orient(moon, md)
	var night := smoothstep(0.0, 0.2, md.y) * (1.0 - day)
	moon.light_energy = 0.42 * night
	moon.visible = night > 0.01
	moon.shadow_enabled = night > 0.2
	sky_mat.set_shader_parameter("moon_dir", md)
	sky_mat.set_shader_parameter("moon_intensity", smoothstep(-0.05, 0.1, md.y) * (1.0 - day * 0.8))
	sky_mat.set_shader_parameter("star_intensity", smoothstep(0.0, -0.25, e))
	sky_mat.set_shader_parameter("sun_glow", 0.45 + 0.35 * warm)
	sky_mat.set_shader_parameter("cloud_time", _cloud_time)
	env.fog_sun_scatter = 0.35 * warm * day
	var hor: Color = palette["horizon"]
	var zen: Color = palette["zenith"]
	sky_tint = hor.lerp(zen, 0.35)
	if water and water.has_method("set_sky_color"):
		water.call("set_sky_color", sky_tint, day)
	# 夜灯（group "night_light"，meta base_energy）：黄昏后点亮；窗纸透光
	night_amount = 1.0 - smoothstep(-0.12, 0.08, e)
	BlockTex.set_env({"night_glow": night_amount})
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group("night_light"):
			var l := n as Light3D
			if l:
				l.light_energy = float(l.get_meta("base_energy", 1.0)) * night_amount
				l.visible = night_amount > 0.02


## 区域调节（雾浓度、体积雾、雾色），下一次刷新生效；force 立即刷新
func set_region(fog_s: float, vol_s: float, tint: Color, force: bool = false) -> void:
	fog_scale = fog_s
	vol_scale = vol_s
	fog_tint = tint
	if force:
		apply_hour(hour)


func _orient(light: DirectionalLight3D, toward: Vector3) -> void:
	var up := Vector3.UP if absf(toward.y) < 0.98 else Vector3.RIGHT
	light.basis = Basis.looking_at(-toward, up)
