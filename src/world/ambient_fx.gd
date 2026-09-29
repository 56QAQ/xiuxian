class_name AmbientFX
extends Node3D
## 环境粒子与区域氛围：按焦点所在生物群系与昼夜淡入淡出——
##   花瓣（平原/坊市/湖泽）、雪花（北方雪峰高处）、余烬与火山灰（西部赤岩）、萤火虫（湖泽/古林/平原的夜晚）、
##   灵气光点（各处，夜晚更多）、黄土浮尘（西南台地白天）、落叶（古林）。
## 发射器跟随焦点（粒子在世界坐标中运动）；每 0.4 秒按区域权重调整 amount_ratio，并把区域雾色/雾浓度交给 DayNight。
## 兼容渲染器使用 CPUParticles3D（由 GPU 粒子配置转换）。秘境可用 setup_static() 指定固定的效果权重。

const UPDATE_SEC := 0.4
const FADE_RATE := 0.6   ## 每秒权重变化上限

## 效果定义：amount 数量、life 寿命、box 发射盒半尺寸、off 相对焦点偏移、grav 重力、vel 初速度、spread 扩散角、
## turb 湍流、size 尺寸范围（米）、color 颜色（HDR 则发光）、tex 贴图、spin 旋转、add 叠加混合
static var DEFS := {
	"petals": {"amount": 110, "life": 10.0, "box": Vector3(30, 9, 30), "off": Vector3(0, 7, 0), "grav": Vector3(0.35, -0.32, 0.2),
		"vel": Vector2(0.3, 0.8), "spread": 60.0, "turb": 0.9, "size": Vector2(0.09, 0.15), "color": Color(1.0, 0.80, 0.86), "tex": "petal", "spin": 160.0, "add": false},
	"snow": {"amount": 520, "life": 11.0, "box": Vector3(40, 14, 40), "off": Vector3(0, 12, 0), "grav": Vector3(0.25, -0.75, 0.1),
		"vel": Vector2(0.1, 0.4), "spread": 30.0, "turb": 0.35, "size": Vector2(0.05, 0.11), "color": Color(0.96, 0.98, 1.0), "tex": "dot", "spin": 0.0, "add": false},
	"embers": {"amount": 140, "life": 5.0, "box": Vector3(30, 3, 30), "off": Vector3(0, -1, 0), "grav": Vector3(0.1, 0.7, 0.05),
		"vel": Vector2(0.2, 0.9), "spread": 35.0, "turb": 1.1, "size": Vector2(0.035, 0.07), "color": Color(4.0, 1.4, 0.35), "tex": "dot", "spin": 0.0, "add": true},
	"ash": {"amount": 170, "life": 10.0, "box": Vector3(32, 10, 32), "off": Vector3(0, 7, 0), "grav": Vector3(0.2, -0.22, 0.1),
		"vel": Vector2(0.1, 0.4), "spread": 50.0, "turb": 0.6, "size": Vector2(0.05, 0.1), "color": Color(0.30, 0.27, 0.27), "tex": "petal", "spin": 90.0, "add": false},
	"fireflies": {"amount": 70, "life": 6.0, "box": Vector3(26, 2.5, 26), "off": Vector3(0, 1.2, 0), "grav": Vector3(0, 0.02, 0),
		"vel": Vector2(0.1, 0.35), "spread": 180.0, "turb": 1.4, "size": Vector2(0.05, 0.08), "color": Color(2.4, 3.2, 0.9), "tex": "glow", "spin": 0.0, "add": true, "flicker": true},
	"motes": {"amount": 80, "life": 9.0, "box": Vector3(36, 10, 36), "off": Vector3(0, 4, 0), "grav": Vector3(0, 0.08, 0),
		"vel": Vector2(0.05, 0.25), "spread": 180.0, "turb": 0.5, "size": Vector2(0.03, 0.07), "color": Color(1.4, 2.6, 2.4), "tex": "glow", "spin": 0.0, "add": true, "flicker": true},
	"dust": {"amount": 140, "life": 9.0, "box": Vector3(30, 8, 30), "off": Vector3(0, 3, 0), "grav": Vector3(0.25, 0.02, 0.1),
		"vel": Vector2(0.05, 0.3), "spread": 180.0, "turb": 0.7, "size": Vector2(0.025, 0.05), "color": Color(1.0, 0.88, 0.62), "tex": "dot", "spin": 0.0, "add": false},
	"leaves": {"amount": 60, "life": 10.0, "box": Vector3(28, 8, 28), "off": Vector3(0, 8, 0), "grav": Vector3(0.3, -0.45, 0.15),
		"vel": Vector2(0.2, 0.6), "spread": 60.0, "turb": 1.0, "size": Vector2(0.12, 0.2), "color": Color(0.86, 0.42, 0.16), "tex": "leaf", "spin": 200.0, "add": false},
}

## 生物群系氛围：[雾浓度倍率, 体积雾倍率, 雾色调(a=混合量)]
static var REGION_MOOD := {
	"plains": [1.0, 1.0, Color(1, 1, 1, 0)], "snow": [1.05, 1.3, Color(0.86, 0.90, 0.98, 0.35)],
	"forest": [1.0, 1.6, Color(0.70, 0.82, 0.72, 0.3)], "lake": [1.1, 1.7, Color(0.76, 0.88, 0.86, 0.35)],
	"volcanic": [1.12, 1.5, Color(0.72, 0.52, 0.44, 0.45)], "plateau": [1.05, 1.1, Color(0.92, 0.82, 0.62, 0.35)],
	"ocean": [1.0, 1.0, Color(1, 1, 1, 0)],
}

var terrain: TerrainGen
var day_night: DayNight
var focus: Node3D
var focus_pos := Vector3.ZERO
## 固定权重（秘境/试炼场）：非空时不按生物群系计算
var static_weights: Dictionary = {}
var weights: Dictionary = {}
var _targets: Dictionary = {}
var _emitters: Dictionary = {}
var _mats: Dictionary = {}
var _t := 0.0
var _town := Vector2(-9999, -9999)
static var _tex: Dictionary = {}


func _init(t: TerrainGen = null, dn: DayNight = null) -> void:
	terrain = t
	day_night = dn


func _ready() -> void:
	name = "AmbientFX"
	for k in DEFS:
		_emitters[k] = _make_emitter(k, DEFS[k])
		weights[k] = 0.0
		_targets[k] = 0.0
	if terrain != null:
		var tp := terrain.find_poi("town")
		if not tp.is_empty():
			_town = Vector2(tp["pos"].x, tp["pos"].z)
	_update_targets()
	for k in _targets:
		weights[k] = _targets[k]
	_apply_weights()


## 固定效果权重（秘境等），例如 {"motes": 1.0, "fireflies": 0.5}
func setup_static(w: Dictionary) -> void:
	static_weights = w
	if is_inside_tree():
		_update_targets()
		for k in _targets:
			weights[k] = _targets[k]
		_apply_weights()


func set_focus(node: Node3D) -> void:
	focus = node


func _process(delta: float) -> void:
	if focus != null and is_instance_valid(focus) and focus.is_inside_tree():
		focus_pos = focus.global_position
	elif get_viewport() != null and get_viewport().get_camera_3d() != null:
		focus_pos = get_viewport().get_camera_3d().global_position
	for k in _emitters:
		var e: Node3D = _emitters[k]
		var d: Dictionary = DEFS[k]
		e.global_position = focus_pos + (d["off"] as Vector3)
	_t += delta
	if _t >= UPDATE_SEC:
		_update_targets()
		var step := FADE_RATE * _t
		_t = 0.0
		for k in weights:
			weights[k] = move_toward(float(weights[k]), float(_targets[k]), step)
		_apply_weights()


func _night() -> float:
	return day_night.night_amount if day_night != null else 0.0


func _update_targets() -> void:
	for k in _targets:
		_targets[k] = 0.0
	var night := _night()
	var day := 1.0 - night
	if not static_weights.is_empty():
		for k in static_weights:
			_targets[k] = float(static_weights[k])
		return
	if terrain == null:
		_targets["motes"] = 0.4 + 0.6 * night
		return
	# 焦点周围 5 点取样平均生物群系
	var bw := {}
	var p := Vector2(focus_pos.x, focus_pos.z)
	for o in [Vector2.ZERO, Vector2(40, 0), Vector2(-40, 0), Vector2(0, 40), Vector2(0, -40)]:
		var q: Vector2 = p + o
		var b := terrain.get_biome(clampf(q.x, 0, TerrainGen.SIZE - 1), clampf(q.y, 0, TerrainGen.SIZE - 1))
		bw[b] = float(bw.get(b, 0.0)) + 0.2
	var h := terrain.get_height(clampf(p.x, 0, TerrainGen.SIZE - 1), clampf(p.y, 0, TerrainGen.SIZE - 1))
	var near_town := 1.0 - smoothstep(90.0, 180.0, p.distance_to(_town))
	var plains := float(bw.get("plains", 0.0))
	var forest := float(bw.get("forest", 0.0))
	var lake := float(bw.get("lake", 0.0))
	var snow := float(bw.get("snow", 0.0))
	var volc := float(bw.get("volcanic", 0.0))
	var plat := float(bw.get("plateau", 0.0))
	_targets["petals"] = clampf(maxf(near_town, plains * 0.45 + lake * 0.5), 0.0, 1.0) * (0.35 + 0.65 * day)
	_targets["snow"] = snow * smoothstep(20.0, 30.0, h)
	_targets["embers"] = volc
	_targets["ash"] = volc * 0.9
	_targets["fireflies"] = clampf(lake + forest * 0.8 + plains * 0.35, 0.0, 1.0) * smoothstep(0.3, 0.8, night)
	_targets["motes"] = 0.25 + 0.55 * night + forest * 0.2
	_targets["dust"] = plat * day
	_targets["leaves"] = forest * 0.9 + plat * 0.3
	# 区域氛围 → DayNight
	if day_night != null:
		var fs := 0.0
		var vs := 0.0
		var tint := Color(0, 0, 0, 0)
		var tot := 0.0
		for b in bw:
			var m: Array = REGION_MOOD.get(b, REGION_MOOD["plains"])
			var w := float(bw[b])
			fs += float(m[0]) * w
			vs += float(m[1]) * w
			var c: Color = m[2]
			tint += Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a) * w
			tot += w
		if tot > 0.0:
			var a := tint.a / tot
			var tc := Color(1, 1, 1, 0)
			if tint.a > 0.001:
				tc = Color(tint.r / tint.a, tint.g / tint.a, tint.b / tint.a, a)
			day_night.set_region(fs / tot, vs / tot, tc)


func _apply_weights() -> void:
	var night := _night()
	for k in _emitters:
		var w := clampf(float(weights[k]), 0.0, 1.0)
		var e: Node = _emitters[k]
		e.set("amount_ratio", maxf(w, 0.001))
		e.set("emitting", w > 0.01)
		# 非发光粒子随昼夜变暗
		var d: Dictionary = DEFS[k]
		if not bool(d["add"]):
			var mat: StandardMaterial3D = _mats[k]
			var c: Color = d["color"]
			var lit := lerpf(1.0, 0.28, night)
			mat.albedo_color = Color(c.r * lit, c.g * lit * (1.0 + 0.05 * night), c.b * lit * (1.0 + 0.25 * night), c.a)


func _make_emitter(key: String, d: Dictionary) -> Node3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = d["box"]
	var g: Vector3 = d["grav"]
	pm.gravity = g
	var v: Vector2 = d["vel"]
	pm.direction = Vector3(g.x, 0.2, g.z).normalized() if g.length() > 0.01 else Vector3.UP
	pm.spread = float(d["spread"])
	pm.initial_velocity_min = v.x
	pm.initial_velocity_max = v.y
	pm.damping_min = 0.05
	pm.damping_max = 0.2
	var sz: Vector2 = d["size"]
	pm.scale_min = sz.x
	pm.scale_max = sz.y
	if float(d["spin"]) > 0.0:
		pm.angle_min = 0.0
		pm.angle_max = 360.0
		pm.angular_velocity_min = -float(d["spin"])
		pm.angular_velocity_max = float(d["spin"])
	if float(d["turb"]) > 0.0:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = float(d["turb"])
		pm.turbulence_noise_scale = 6.0
		pm.turbulence_noise_speed = Vector3(0.3, 0.2, 0.3)
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.15
	# 透明度：淡入淡出（萤火/灵光闪烁）
	var grad := Gradient.new()
	if d.get("flicker", false):
		grad.offsets = PackedFloat32Array([0.0, 0.15, 0.3, 0.45, 0.6, 0.75, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.25), Color(1, 1, 1, 1), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	else:
		grad.offsets = PackedFloat32Array([0.0, 0.12, 0.85, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if bool(d["add"]):
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = d["color"]
	mat.albedo_texture = _texture(str(d["tex"]))
	mat.disable_receive_shadows = true
	mat.no_depth_test = false
	_mats[key] = mat
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	var gp := GPUParticles3D.new()
	gp.name = key.capitalize()
	gp.amount = int(d["amount"])
	gp.lifetime = float(d["life"])
	gp.preprocess = float(d["life"])
	gp.local_coords = false
	gp.process_material = pm
	gp.draw_pass_1 = quad
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bx: Vector3 = d["box"]
	gp.visibility_aabb = AABB(-bx - Vector3(20, 20, 20), (bx + Vector3(20, 20, 20)) * 2.0)
	gp.emitting = false
	var node: Node3D = gp
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		var cp := CPUParticles3D.new()
		cp.name = gp.name
		cp.convert_from_particles(gp)
		cp.local_coords = false
		cp.emitting = false
		gp.free()
		node = cp
	add_child(node)
	return node


## 生成小贴图：dot 柔和圆点、glow 光点、petal 花瓣、leaf 叶片
static func _texture(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var a := 0.0
			var shade := 1.0
			match kind:
				"glow":
					var r := sqrt(u * u + v * v)
					a = clampf(1.0 - r, 0.0, 1.0)
					a = a * a * (0.6 + 0.4 * float(r < 0.3))
				"petal":
					# 带缺口的椭圆花瓣
					var d := (u / 0.62) * (u / 0.62) + (v / 0.95) * (v / 0.95)
					a = 1.0 if d < 1.0 else 0.0
					if v < -0.7 and absf(u) < 0.14:
						a = 0.0
					shade = 0.8 + 0.2 * (1.0 - (v + 1.0) * 0.5)
				"leaf":
					var d2 := (u / 0.45) * (u / 0.45) + (v / 0.95) * (v / 0.95)
					a = 1.0 if d2 < 1.0 else 0.0
					if absf(u) < 0.07:
						shade = 0.75
				_:
					var r2 := sqrt(u * u + v * v)
					a = clampf((1.0 - r2) * 2.2, 0.0, 1.0)
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t


static func clear_cache() -> void:
	_tex.clear()
