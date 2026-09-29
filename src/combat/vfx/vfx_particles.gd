class_name VfxParticles
## 粒子预设（CPUParticles3D：Forward+ 与 Compatibility 渲染器通用）。
## burst()：一次性迸发，节点来自 VfxManager 对象池；make()：持续发射器（随宿主节点释放）。
## 颜色：粒子 color（sRGB）× 渐变 color_ramp；尺寸：scale_amount × 预设曲线。

## 预设字段：mat 材质、mesh（quad/tall/cube）、life、dir、spread、vel、grav、damp、scale、curve、ramp、
## align（沿速度拉伸）、ang（初始角度范围）、angvel、anim（序列帧速度）、anim_rand（随机帧/变体）、
## shape（point/sphere/ring/box）、shape_r、radial、tang、flat（扁平度）
const PRESETS := {
	"spark": {"mat": "spark", "life": 0.34, "spread": 180.0, "vel": Vector2(5, 13), "grav": Vector3(0, -14, 0), "damp": Vector2(3, 6), "scale": Vector2(0.035, 0.07), "curve": "shrink", "ramp": "spark", "align": true},
	"streak": {"mat": "streak", "life": 0.26, "spread": 12.0, "vel": Vector2(9, 18), "grav": Vector3.ZERO, "damp": Vector2(8, 14), "scale": Vector2(0.04, 0.07), "curve": "shrink", "ramp": "spark", "align": true},
	"glow": {"mat": "glow", "life": 0.45, "spread": 180.0, "vel": Vector2(1.5, 5), "grav": Vector3.ZERO, "damp": Vector2(3, 5), "scale": Vector2(0.12, 0.26), "curve": "shrink", "ramp": "fade"},
	"mote": {"mat": "mote", "life": 1.1, "spread": 50.0, "vel": Vector2(0.4, 1.4), "grav": Vector3(0, 0.6, 0), "damp": Vector2(0.5, 1.2), "scale": Vector2(0.14, 0.26), "curve": "pop", "ramp": "fade_in_out", "ang": Vector2(0, 360)},
	"ember": {"mat": "spark", "life": 0.9, "spread": 70.0, "vel": Vector2(1.5, 5), "grav": Vector3(0, 2.5, 0), "damp": Vector2(1, 2.5), "scale": Vector2(0.018, 0.035), "curve": "shrink", "ramp": "ember", "align": true},
	"flame": {"mat": "flame", "life": 0.55, "spread": 25.0, "vel": Vector2(0.5, 2.0), "grav": Vector3(0, 3.5, 0), "damp": Vector2(1, 2), "scale": Vector2(0.35, 0.7), "curve": "flame", "ramp": "flame", "anim": 1.0, "anim_rand": true, "ang": Vector2(-20, 20)},
	"smoke": {"mat": "smoke", "life": 1.5, "spread": 35.0, "vel": Vector2(0.4, 1.4), "grav": Vector3(0, 0.7, 0), "damp": Vector2(0.8, 1.5), "scale": Vector2(0.7, 1.3), "curve": "puff", "ramp": "smoke", "anim_rand": true, "ang": Vector2(0, 360), "angvel": Vector2(-30, 30)},
	"dust": {"mat": "smoke", "life": 0.95, "spread": 90.0, "flat": 0.85, "vel": Vector2(2.0, 5.5), "grav": Vector3(0, 0.4, 0), "damp": Vector2(3, 5), "scale": Vector2(0.55, 1.05), "curve": "puff", "ramp": "dust", "anim_rand": true, "ang": Vector2(0, 360), "angvel": Vector2(-40, 40)},
	"debris": {"mat": "debris", "mesh": "cube", "life": 1.1, "spread": 60.0, "vel": Vector2(4, 9), "grav": Vector3(0, -20, 0), "damp": Vector2(0.2, 0.6), "scale": Vector2(0.07, 0.17), "curve": "late_shrink", "ramp": "solid", "angvel": Vector2(-400, 400)},
	"leaf": {"mat": "leaf", "life": 1.3, "spread": 180.0, "vel": Vector2(1.5, 4.5), "grav": Vector3(0, -1.6, 0), "damp": Vector2(1.5, 3), "scale": Vector2(0.14, 0.24), "curve": "late_shrink", "ramp": "leaf", "anim_rand": true, "ang": Vector2(0, 360), "angvel": Vector2(-300, 300)},
	"pollen": {"mat": "mote", "life": 1.6, "spread": 180.0, "vel": Vector2(0.2, 0.9), "grav": Vector3(0, 0.35, 0), "damp": Vector2(0.3, 0.8), "scale": Vector2(0.05, 0.1), "curve": "pop", "ramp": "fade_in_out"},
	"droplet": {"mat": "spark", "life": 0.6, "spread": 55.0, "vel": Vector2(3, 8), "grav": Vector3(0, -16, 0), "damp": Vector2(0.3, 1), "scale": Vector2(0.035, 0.06), "curve": "late_shrink", "ramp": "spark", "align": true},
	"mist": {"mat": "smoke", "life": 1.1, "spread": 90.0, "flat": 0.7, "vel": Vector2(1.0, 3.0), "grav": Vector3(0, 0.3, 0), "damp": Vector2(2, 3), "scale": Vector2(0.8, 1.5), "curve": "puff", "ramp": "mist", "anim_rand": true, "ang": Vector2(0, 360)},
	"ice": {"mat": "shard", "life": 0.8, "spread": 70.0, "vel": Vector2(3.5, 8), "grav": Vector3(0, -16, 0), "damp": Vector2(0.3, 1), "scale": Vector2(0.14, 0.26), "curve": "late_shrink", "ramp": "solid", "ang": Vector2(0, 360), "angvel": Vector2(-500, 500)},
	"blood": {"mat": "drop", "life": 0.6, "spread": 40.0, "vel": Vector2(0.5, 2.5), "grav": Vector3(0, -14, 0), "damp": Vector2(0, 0.5), "scale": Vector2(0.03, 0.05), "curve": "late_shrink", "ramp": "solid", "align": true},
	"paper": {"mat": "paper", "mesh": "tall", "life": 1.5, "spread": 60.0, "vel": Vector2(2.0, 4.5), "grav": Vector3(0, -1.2, 0), "damp": Vector2(1.5, 2.5), "scale": Vector2(0.22, 0.3), "curve": "late_shrink", "ramp": "paper", "ang": Vector2(-40, 40), "angvel": Vector2(-260, 260)},
	"glass": {"mat": "shard", "life": 0.7, "spread": 180.0, "vel": Vector2(4, 9), "grav": Vector3(0, -12, 0), "damp": Vector2(0.5, 1.5), "scale": Vector2(0.1, 0.22), "curve": "late_shrink", "ramp": "fade", "ang": Vector2(0, 360), "angvel": Vector2(-600, 600)},
	"rune": {"mat": "mote", "life": 1.4, "spread": 20.0, "vel": Vector2(1.0, 2.5), "grav": Vector3(0, 0.5, 0), "damp": Vector2(0.5, 1), "scale": Vector2(0.16, 0.3), "curve": "pop", "ramp": "fade_in_out", "ang": Vector2(0, 360)},
}

const BUCKETS := [4, 8, 12, 16, 24, 32, 48, 64, 96, 128]


static func bucket(amount: int) -> int:
	for b in BUCKETS:
		if amount <= b:
			return b
	return BUCKETS[BUCKETS.size() - 1]


# ================================================================ 资源

static func _curve(name: String) -> Curve:
	var key := "curve:" + name
	var c := FX._mats
	if c.has(key):
		return c[key]
	var cv := Curve.new()
	var pts: Array = {
		"shrink": [Vector2(0, 1), Vector2(1, 0)],
		"late_shrink": [Vector2(0, 1), Vector2(0.7, 0.9), Vector2(1, 0)],
		"pop": [Vector2(0, 0.2), Vector2(0.15, 1), Vector2(0.7, 0.8), Vector2(1, 0)],
		"puff": [Vector2(0, 0.35), Vector2(0.4, 0.8), Vector2(1, 1)],
		"flame": [Vector2(0, 0.35), Vector2(0.25, 1), Vector2(1, 0.25)],
		"grow": [Vector2(0, 0.3), Vector2(1, 1)],
		"flat": [Vector2(0, 1), Vector2(1, 1)],
	}.get(name, [Vector2(0, 1), Vector2(1, 0)])
	for p in pts:
		cv.add_point(p)
	c[key] = cv
	return cv


static func _ramp(name: String) -> Gradient:
	var key := "ramp:" + name
	var c := FX._mats
	if c.has(key):
		return c[key]
	var g := Gradient.new()
	var pts: Array = {
		"fade": [[0.0, Color(1, 1, 1, 1)], [0.6, Color(1, 1, 1, 0.75)], [1.0, Color(1, 1, 1, 0)]],
		"fade_in_out": [[0.0, Color(1, 1, 1, 0)], [0.15, Color(1, 1, 1, 1)], [0.7, Color(1, 1, 1, 0.7)], [1.0, Color(1, 1, 1, 0)]],
		"spark": [[0.0, Color(1, 1, 1, 1)], [0.5, Color(1, 1, 1, 0.85)], [1.0, Color(1, 1, 1, 0)]],
		"ember": [[0.0, Color(1.0, 0.95, 0.7, 1)], [0.35, Color(1.0, 0.6, 0.25, 1)], [1.0, Color(0.7, 0.15, 0.05, 0)]],
		"flame": [[0.0, Color(1, 1, 1, 0)], [0.1, Color(1, 1, 1, 1)], [0.6, Color(1, 1, 1, 0.8)], [1.0, Color(1, 1, 1, 0)]],
		"smoke": [[0.0, Color(1, 1, 1, 0)], [0.12, Color(1, 1, 1, 0.55)], [0.6, Color(1, 1, 1, 0.35)], [1.0, Color(1, 1, 1, 0)]],
		"dust": [[0.0, Color(1, 1, 1, 0)], [0.08, Color(1, 1, 1, 0.6)], [0.5, Color(1, 1, 1, 0.35)], [1.0, Color(1, 1, 1, 0)]],
		"mist": [[0.0, Color(1, 1, 1, 0)], [0.15, Color(1, 1, 1, 0.4)], [0.6, Color(1, 1, 1, 0.22)], [1.0, Color(1, 1, 1, 0)]],
		"solid": [[0.0, Color(1, 1, 1, 1)], [0.8, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]],
		"leaf": [[0.0, Color(1, 1, 1, 0)], [0.08, Color(1, 1, 1, 1)], [0.8, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]],
		"paper": [[0.0, Color(1, 1, 1, 1)], [0.6, Color(1, 1, 1, 1)], [0.85, Color(1.0, 0.55, 0.2, 0.9)], [1.0, Color(0.3, 0.05, 0.0, 0)]],
	}.get(name, [[0.0, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
	g.set_offset(0, pts[0][0])
	g.set_color(0, pts[0][1])
	g.set_offset(1, pts[pts.size() - 1][0])
	g.set_color(1, pts[pts.size() - 1][1])
	for i in range(1, pts.size() - 1):
		g.add_point(pts[i][0], pts[i][1])
	c[key] = g
	return g


## 按预设配置粒子节点（不设置 amount / emitting）
static func configure(p: CPUParticles3D, preset: String) -> void:
	var d: Dictionary = PRESETS.get(preset, PRESETS["glow"])
	var mesh_kind := str(d.get("mesh", "quad"))
	match mesh_kind:
		"cube":
			p.mesh = VfxLib.cube()
		"tall":
			p.mesh = VfxLib.quad_tall()
		_:
			p.mesh = VfxLib.quad()
	var mat_name := str(d.get("mat", "glow"))
	p.material_override = VfxLib.debris_mat() if mat_name == "debris" else VfxLib.emitter_mat(mat_name)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.lifetime = float(d.get("life", 0.5))
	p.explosiveness = 1.0
	p.randomness = 0.3
	p.lifetime_randomness = 0.35
	p.local_coords = false
	p.direction = d.get("dir", Vector3.UP)
	p.spread = float(d.get("spread", 45.0))
	p.flatness = float(d.get("flat", 0.0))
	var vel: Vector2 = d.get("vel", Vector2(1, 3))
	p.initial_velocity_min = vel.x
	p.initial_velocity_max = vel.y
	p.gravity = d.get("grav", Vector3.ZERO)
	var damp: Vector2 = d.get("damp", Vector2.ZERO)
	p.damping_min = damp.x
	p.damping_max = damp.y
	var sc: Vector2 = d.get("scale", Vector2(0.1, 0.2))
	p.scale_amount_min = sc.x
	p.scale_amount_max = sc.y
	p.scale_amount_curve = _curve(str(d.get("curve", "shrink")))
	p.color_ramp = _ramp(str(d.get("ramp", "fade")))
	p.particle_flag_align_y = bool(d.get("align", false))
	var ang: Vector2 = d.get("ang", Vector2.ZERO)
	p.angle_min = ang.x
	p.angle_max = ang.y
	var av: Vector2 = d.get("angvel", Vector2.ZERO)
	p.angular_velocity_min = av.x
	p.angular_velocity_max = av.y
	var anim := float(d.get("anim", 0.0))
	p.anim_speed_min = anim
	p.anim_speed_max = anim
	if bool(d.get("anim_rand", false)):
		p.anim_offset_min = 0.0
		p.anim_offset_max = 1.0
	var radial: Vector2 = d.get("radial", Vector2.ZERO)
	p.radial_accel_min = radial.x
	p.radial_accel_max = radial.y
	var tang: Vector2 = d.get("tang", Vector2.ZERO)
	p.tangential_accel_min = tang.x
	p.tangential_accel_max = tang.y
	set_shape(p, str(d.get("shape", "point")), float(d.get("shape_r", 0.1)))


static func set_shape(p: CPUParticles3D, shape: String, r: float, h: float = 0.0) -> void:
	match shape:
		"sphere":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = r
		"shell":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
			p.emission_sphere_radius = r
		"ring":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			p.emission_ring_axis = Vector3.UP
			p.emission_ring_radius = r
			p.emission_ring_inner_radius = r * 0.85
			p.emission_ring_height = h
		"tube":
			# 圆筒壳（环绕角色身体表面，避免粒子被身体遮住）
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			p.emission_ring_axis = Vector3.UP
			p.emission_ring_radius = r
			p.emission_ring_inner_radius = r * 0.7
			p.emission_ring_height = maxf(h, 0.01)
		"box":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			p.emission_box_extents = Vector3(r, maxf(h, 0.01), r)
		_:
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT


## 一次性迸发。opts：dir 方向、spread、flat 扁平度、speed 速度倍率、size 尺寸倍率、life 寿命倍率、
## shape/shape_r/shape_h 发射形状、grav 重力、radial/tang 径向/切向加速度、damp 阻尼、expl 爆发度、cull 可见距离（默认 90 米）
static func burst(preset: String, pos: Vector3, color: Color, amount: int, opts: Dictionary = {}) -> CPUParticles3D:
	var mgr := VfxManager.get_mgr()
	if mgr == null or amount <= 0:
		return null
	if not mgr.visible_at(pos, float(opts.get("cull", 90.0))):
		return null
	amount = mgr.budget(amount)
	if amount <= 0:
		return null
	var p := mgr.acquire_particles(preset, amount)
	if p == null:
		return null
	var d: Dictionary = PRESETS.get(preset, PRESETS["glow"])
	p.direction = opts.get("dir", d.get("dir", Vector3.UP))
	p.spread = float(opts.get("spread", d.get("spread", 45.0)))
	var vel: Vector2 = d.get("vel", Vector2(1, 3))
	var spd := float(opts.get("speed", 1.0))
	p.initial_velocity_min = vel.x * spd
	p.initial_velocity_max = vel.y * spd
	var sc: Vector2 = d.get("scale", Vector2(0.1, 0.2))
	var sz := float(opts.get("size", 1.0))
	p.scale_amount_min = sc.x * sz
	p.scale_amount_max = sc.y * sz
	p.lifetime = float(d.get("life", 0.5)) * float(opts.get("life", 1.0))
	p.gravity = opts.get("grav", d.get("grav", Vector3.ZERO))
	var radial: Vector2 = opts.get("radial", d.get("radial", Vector2.ZERO))
	p.radial_accel_min = radial.x
	p.radial_accel_max = radial.y
	var tang: Vector2 = opts.get("tang", d.get("tang", Vector2.ZERO))
	p.tangential_accel_min = tang.x
	p.tangential_accel_max = tang.y
	var damp: Vector2 = opts.get("damp", d.get("damp", Vector2.ZERO))
	p.damping_min = damp.x
	p.damping_max = damp.y
	p.flatness = float(opts.get("flat", d.get("flat", 0.0)))
	if opts.has("shape"):
		set_shape(p, str(opts["shape"]), float(opts.get("shape_r", 0.3)), float(opts.get("shape_h", 0.0)))
	else:
		set_shape(p, str(d.get("shape", "point")), float(d.get("shape_r", 0.1)))
	p.explosiveness = float(opts.get("expl", 1.0))
	p.color = color
	p.position = pos
	mgr.started(p)
	p.restart()
	return p


## 持续发射器（挂在 parent 下，local=false 时粒子留在世界中形成拖尾）
static func make(preset: String, amount: int, parent: Node, color: Color, local: bool = false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	configure(p, preset)
	p.one_shot = false
	p.explosiveness = 0.0
	p.amount = maxi(amount, 1)
	p.local_coords = local
	p.color = color
	parent.add_child(p)
	p.emitting = true
	return p
