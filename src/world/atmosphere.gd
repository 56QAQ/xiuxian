class_name Atmosphere
## 国风大气：统一的 Environment 配置（AgX 色调映射、SSAO + SSIL、柔和辉光、指数雾 + 空气透视 + 高度雾、
## 体积雾（光柱）、3D LUT 调色）与天空材质（sky.gdshader：水墨远山、写意云、日月星辰）。
## 大地图（DayNight 按时辰插值调色板）、秘境与试炼场（固定调色板）共用，保证画面一致。
## 兼容渲染器不支持的效果（SSIL、体积雾等）会被引擎自动忽略。

const LUT_PATH := "res://assets/textures/world/grade_lut.png"
const SKY_SHADER := "res://assets/shaders/sky.gdshader"

## 调色板字段（颜色均为 sRGB）：
## zenith horizon haze glow（天空）、ambient amb_e（环境光与强度）、fog fog_d（雾色与密度）、
## vol vol_d（体积雾反照率与密度）、ink mist（远山墨色与山脚雾色）、cloud_l cloud_s（云亮/暗部）、
## sun sun_e（太阳色与强度）、exposure（曝光）、cloud（云量）
const DAY := {
	"zenith": Color(0.28, 0.52, 0.84), "horizon": Color(0.70, 0.83, 0.92), "haze": Color(0.84, 0.90, 0.94), "glow": Color(1.0, 0.92, 0.76),
	"ambient": Color(0.50, 0.60, 0.72), "amb_e": 0.62, "fog": Color(0.74, 0.83, 0.90), "fog_d": 0.78, "fog_end": 1150.0,
	"vol": Color(0.92, 0.94, 0.96), "vol_d": 0.0025, "ink": Color(0.46, 0.58, 0.66), "mist": Color(0.84, 0.90, 0.93),
	"cloud_l": Color(1.0, 1.0, 0.98), "cloud_s": Color(0.68, 0.74, 0.84), "sun": Color(1.0, 0.96, 0.88), "sun_e": 1.7,
	"exposure": 0.95, "cloud": 0.42,
}


static func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = make_sky_material()
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# 色调映射：AgX（柔和对比）
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.95
	if "tonemap_agx_contrast" in env:
		env.set("tonemap_agx_contrast", 1.12)
	# 屏幕空间环境光遮蔽与间接光
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.5
	env.ssao_power = 1.5
	env.ssao_detail = 0.5
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.12
	env.ssao_ao_channel_affect = 0.25
	env.ssil_enabled = true
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.8
	env.ssil_sharpness = 0.98
	# 辉光：柔和的光晕，灯笼/熔岩/法术发光
	env.glow_enabled = true
	env.glow_normalized = false
	env.set("glow_levels/1", 0.0)
	env.set("glow_levels/2", 0.6)
	env.set("glow_levels/3", 1.0)
	env.set("glow_levels/4", 0.8)
	env.set("glow_levels/5", 0.4)
	env.glow_intensity = 0.55
	env.glow_strength = 0.95
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# 指数雾 + 空气透视（远景融入天色，层层远山）+ 高度雾（湖面、谷地薄雾）
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 0.8
	env.fog_depth_begin = 40.0
	env.fog_depth_end = 1100.0
	env.fog_depth_curve = 1.7
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.16
	env.fog_sun_scatter = 0.2
	env.fog_height = 15.0
	env.fog_height_density = 0.018
	# 体积雾：光柱与晨雾（仅 Forward+）
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.003
	env.volumetric_fog_albedo = Color(0.92, 0.94, 0.96)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.35
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.85
	env.sdfgi_enabled = false
	# 调色：3D LUT（暖高光、青绿暗部、略去饱和、纸感抬黑）
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0
	if ResourceLoader.exists(LUT_PATH):
		env.adjustment_color_correction = load(LUT_PATH)
	return env


static func make_sky_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SKY_SHADER)
	return m


## 太阳/月亮方向光的通用设置
static func setup_sun(sun: DirectionalLight3D, max_dist: float = 220.0) -> void:
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = max_dist
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.8
	sun.light_volumetric_fog_energy = 1.4
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY


## 应用调色板（字段见 DAY）到环境、天空与太阳
static func apply(env: Environment, sky_mat: ShaderMaterial, sun: DirectionalLight3D, p: Dictionary) -> void:
	var zen: Color = p["zenith"]
	var hor: Color = p["horizon"]
	sky_mat.set_shader_parameter("zenith_color", zen)
	sky_mat.set_shader_parameter("horizon_color", hor)
	sky_mat.set_shader_parameter("haze_color", p["haze"])
	sky_mat.set_shader_parameter("ground_color", (p["haze"] as Color).darkened(0.45))
	sky_mat.set_shader_parameter("sun_glow_color", p["glow"])
	sky_mat.set_shader_parameter("mountain_ink", p["ink"])
	sky_mat.set_shader_parameter("mountain_mist", p["mist"])
	sky_mat.set_shader_parameter("cloud_light", p["cloud_l"])
	sky_mat.set_shader_parameter("cloud_shadow", p["cloud_s"])
	sky_mat.set_shader_parameter("cloud_cover", float(p.get("cloud", 0.42)))
	env.ambient_light_color = p["ambient"]
	env.ambient_light_energy = float(p["amb_e"])
	env.fog_light_color = p["fog"]
	env.fog_light_energy = 1.0
	# 深度雾：fog_d 为远处最大浓度，fog_end 为达到最大浓度的距离
	env.fog_density = float(p["fog_d"])
	env.fog_depth_end = float(p.get("fog_end", 1100.0))
	env.volumetric_fog_albedo = p["vol"]
	env.volumetric_fog_density = float(p["vol_d"])
	env.tonemap_exposure = float(p["exposure"])
	if sun != null:
		sun.light_color = p["sun"]
		sun.light_energy = float(p["sun_e"])


## 两个调色板插值
static func lerp_palette(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in a:
		var va: Variant = a[k]
		var vb: Variant = b.get(k, va)
		if va is Color:
			out[k] = (va as Color).lerp(vb, t)
		elif va is float or va is int:
			out[k] = lerpf(float(va), float(vb), t)
		else:
			out[k] = va
	return out
