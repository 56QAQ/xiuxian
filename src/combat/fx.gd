class_name FX
## 战斗特效门面（静态 API，可在任何静态代码中调用）。实现位于 src/combat/vfx/：
##   VfxLib 资源/配色/程序网格 · VfxParticles 粒子预设 · VfxManager 对象池与上限 · VfxRibbon 拖尾条带
##   VfxSpells 法诀表现 · VfxMotion 身法/死亡/突破表现 · ActorVfx 角色持续特效 · ScreenFx 屏幕特效
## 一次性特效全部挂在当前场景的 VfxManager 下，按寿命自动释放；持续特效随宿主节点释放。
## 旧接口（burst / dust / ring / shock_sphere / flash_light / pillar / telegraph / beam / meteor / sparkle）保留签名，
## 内部改为新的特效语言。

static var _mats: Dictionary = {}     ## 全部特效资源缓存（材质、贴图、网格、曲线），测试退出时清理
static var _cube: BoxMesh
static var budget_particles: int = 0  ## 兼容旧字段


static func root() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.current_scene if tree.current_scene != null else tree.root


static func mgr() -> VfxManager:
	return VfxManager.get_mgr()


## 把一次性特效节点挂到管理器下并放到 pos
static func spawn(n: Node3D, pos: Vector3) -> Node3D:
	var m := mgr()
	if m == null:
		n.free()
		return null
	m.add(n)
	n.position = pos
	return n


static func col(e: String) -> Color:
	return VfxLib.main_color(e)


## 镜头位置（没有镜头时返回 fallback）
static func cam_pos(fallback: Vector3 = Vector3.ZERO) -> Vector3:
	var m := mgr()
	return m.cam_pos if m != null and m.has_cam else fallback


static func _visible(pos: Vector3, dist: float) -> bool:
	var m := mgr()
	return m != null and m.visible_at(pos, dist)


# ================================================================ 旧接口材质（其他模块仍在使用）

## 发光（加色、无光照）材质，按颜色缓存
static func glow_mat(c: Color, additive: bool = true) -> StandardMaterial3D:
	var key := "%s|%s" % [c.to_html(), additive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_mats[key] = m
	return m


## 实体（有光照）的碎屑材质
static func solid_mat(c: Color) -> StandardMaterial3D:
	var key := "solid|" + c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	_mats[key] = m
	return m


static func cube_mesh() -> BoxMesh:
	if _cube == null:
		_cube = BoxMesh.new()
		_cube.size = Vector3.ONE
	return _cube


static func _fade_gradient(_c: Color) -> Gradient:
	return VfxParticles._ramp("fade")


# ================================================================ 基础图元

## 广告牌精灵：mat 为 VfxLib.PARTICLE_MATS 中的名字；size 起始边长，grow 结束时的尺寸倍率
static func sprite(pos: Vector3, mat: String, color: Color, size: float, life: float, grow: float = 1.0, alpha: float = 1.0) -> MeshInstance3D:
	var m := mgr()
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = VfxLib.quad()
	mi.material_override = VfxLib.particle_mat(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add(mi)
	mi.position = pos
	mi.scale = Vector3.ONE * size
	mi.set_instance_shader_parameter("tint", color)
	mi.set_instance_shader_parameter("fade", alpha)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "instance_shader_parameters/fade", 0.0, life).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	if not is_equal_approx(grow, 1.0):
		tw.tween_property(mi, "scale", Vector3.ONE * size * grow, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.chain().tween_callback(mi.queue_free)
	return mi


## 命中/爆炸闪光：星芒 + 柔光
static func flash(pos: Vector3, color: Color, size: float = 1.0, life: float = 0.14) -> void:
	if not _visible(pos, 120.0):
		return
	sprite(pos, "flare", color.lerp(Color.WHITE, 0.35), size * 1.3, life, 1.25)
	sprite(pos, "glow", color, size * 1.6, life * 1.6, 1.15, 0.7)


## 冲击环（着色器绘制的扩散光环）。normal 为环面法线；style 0 灵气 1 水波 2 火环 3 尘浪
static func shock_ring(pos: Vector3, radius: float, color: Color, time: float = 0.4, thick: float = 0.18, normal: Vector3 = Vector3.UP, style: int = 0, start: float = 0.12) -> MeshInstance3D:
	var m := mgr()
	if m == null or not m.visible_at(pos, 150.0):
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = VfxLib.plane()
	mi.material_override = VfxLib.ring_mat(style)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add(mi)
	mi.position = pos
	mi.basis = _basis_up(normal)
	var s0 := radius * 2.0 * start
	mi.scale = Vector3(s0, 1.0, s0)
	mi.set_instance_shader_parameter("tint", color)
	mi.set_instance_shader_parameter("thick", thick)
	mi.set_instance_shader_parameter("prog", 0.0)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius * 2.0, 1.0, radius * 2.0), time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "instance_shader_parameters/prog", 1.0, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)
	return mi


## 朝向镜头的冲击环
static func cam_ring(pos: Vector3, radius: float, color: Color, time: float = 0.25, thick: float = 0.2) -> void:
	shock_ring(pos, radius, color, time, thick, (cam_pos(pos + Vector3.BACK) - pos).normalized(), 0, 0.2)


## 以 up 为 Y 轴的基
static func _basis_up(up: Vector3) -> Basis:
	var y := up.normalized()
	if y.length_squared() < 0.5:
		return Basis()
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## 在局部轴上缩放（Basis.scaled 是在父空间缩放，旋转后的非均匀缩放需用此函数）
static func scale_local(b: Basis, s: Vector3) -> Basis:
	return Basis(b.x * s.x, b.y * s.y, b.z * s.z)


## 以 fwd 为 -Z 的基
static func _basis_fwd(fwd: Vector3) -> Basis:
	var z := -fwd.normalized()
	if z.length_squared() < 0.5:
		return Basis()
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	return Basis(x, z.cross(x), z)


## 贴合地面的贴花：kind = crack（地裂）/ scorch（焦痕）/ frost（霜花）。glow 为初始发光强度（熔岩/灵光）
static func ground_decal(pos: Vector3, radius: float, kind: String, life: float = 7.0, glow_color: Color = Color(1.0, 0.45, 0.12), glow: float = 0.0) -> MeshInstance3D:
	var m := mgr()
	if m == null or radius <= 0.05 or not m.visible_at(pos, 90.0):
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = VfxLib.ground_mesh(pos, radius, 7, randf() * TAU, 0.05 + randf() * 0.02)
	mi.material_override = VfxLib.decal_mat(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.sorting_offset = -1.0
	m.add(mi)
	mi.position = pos
	mi.set_instance_shader_parameter("tint", glow_color)
	mi.set_instance_shader_parameter("glow", glow)
	mi.set_instance_shader_parameter("fade", 0.0)
	var tw := mi.create_tween()
	tw.tween_property(mi, "instance_shader_parameters/fade", 1.0, 0.06)
	if glow > 0.0:
		tw.parallel().tween_property(mi, "instance_shader_parameters/glow", 0.0, minf(2.2, life * 0.4)).set_ease(Tween.EASE_IN).set_delay(0.1)
	tw.tween_interval(maxf(life - 1.6, 0.1))
	tw.tween_property(mi, "instance_shader_parameters/fade", 0.0, 1.5)
	tw.tween_callback(mi.queue_free)
	m.register_decal(mi)
	return mi


## 法阵。opts：
##   normal 法线（默认竖直向上，贴地）；ground=true 贴合地形；follow 跟随的节点（作为其子节点）
##   reveal 绘出时间；spin 角速度（弧度/秒）；alpha；glyph 中心字（默认按元素）；fill 预警填充时长（秒）
##   color 覆盖颜色；fade_in / fade_out 时长
static func magic_circle(pos: Vector3, radius: float, elem: String, life: float, opts: Dictionary = {}) -> MeshInstance3D:
	var m := mgr()
	if m == null or not m.visible_at(pos, 160.0):
		return null
	var mi := MeshInstance3D.new()
	var normal: Vector3 = opts.get("normal", Vector3.UP)
	var ground := bool(opts.get("ground", false))
	if ground:
		mi.mesh = VfxLib.ground_mesh(pos, radius, 9, 0.0, 0.08)
	else:
		mi.mesh = VfxLib.plane()
	mi.material_override = VfxLib.circle_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var follow: Node3D = opts.get("follow", null)
	if follow != null and is_instance_valid(follow) and follow.is_inside_tree():
		follow.add_child(mi)
		mi.top_level = false
		mi.position = opts.get("offset", Vector3(0, 0.06, 0))
		mi.global_basis = _basis_up(normal)
	else:
		m.add(mi)
		mi.position = pos
		mi.basis = _basis_up(normal)
	if not ground:
		mi.scale = Vector3(radius * 2.0, 1.0, radius * 2.0)
	var c: Color = opts.get("color", VfxLib.main_color(elem))
	var alpha := float(opts.get("alpha", 1.0))
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("alpha", 0.0)
	mi.set_instance_shader_parameter("glyph", float(opts.get("glyph", VfxLib.pal(elem)["glyph"])))
	var spin0 := randf() * TAU
	mi.set_instance_shader_parameter("spin", spin0)
	var reveal := float(opts.get("reveal", 0.35))
	mi.set_instance_shader_parameter("reveal", 0.0 if reveal > 0.0 else 1.0)
	var fill_t := float(opts.get("fill", -1.0))
	mi.set_instance_shader_parameter("fill", 0.0 if fill_t > 0.0 else -1.0)
	var fade_in := float(opts.get("fade_in", 0.12))
	var fade_out := float(opts.get("fade_out", minf(0.35, life * 0.35)))
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "instance_shader_parameters/alpha", alpha, fade_in)
	if reveal > 0.0:
		tw.tween_property(mi, "instance_shader_parameters/reveal", 1.0, reveal).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(mi, "instance_shader_parameters/spin", spin0 + float(opts.get("spin", 0.9)) * life, life)
	if fill_t > 0.0:
		tw.tween_property(mi, "instance_shader_parameters/fill", 1.0, fill_t).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(mi, "instance_shader_parameters/alpha", 0.0, fade_out).set_delay(maxf(life - fade_out, 0.0))
	tw.chain().tween_callback(mi.queue_free)
	return mi


## 两点之间的能量光束（绕轴朝向镜头的单片）
static func beam_strip(from: Vector3, to: Vector3, color: Color, width: float, life: float, style: int = 0, alpha: float = 1.0) -> MeshInstance3D:
	var m := mgr()
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = VfxLib.beam_strip()
	mi.material_override = VfxLib.beam_mat(style)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add(mi)
	set_beam(mi, from, to, width)
	mi.set_instance_shader_parameter("tint", color)
	mi.set_instance_shader_parameter("alpha", alpha)
	mi.set_instance_shader_parameter("seed", randf() * 10.0)
	if life > 0.0:
		var tw := mi.create_tween()
		tw.tween_property(mi, "instance_shader_parameters/alpha", 0.0, life).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
	return mi


## 更新光束节点的两端与宽度
static func set_beam(mi: MeshInstance3D, from: Vector3, to: Vector3, width: float) -> void:
	var d := to - from
	var l := d.length()
	if l < 0.01:
		return
	mi.transform = Transform3D(scale_local(_basis_fwd(d / l), Vector3(width, width, l)), from)
	mi.set_instance_shader_parameter("len", l)


# ================================================================ 旧接口（签名不变）

## 迸溅：glow=true 为发光火花 + 光点；glow=false 为受光照的碎块（岩石、木屑）
static func burst(pos: Vector3, color: Color, amount: int = 16, speed: float = 6.0, size: float = 0.09, life: float = 0.55, glow: bool = true, gravity: float = 9.0) -> void:
	if amount <= 0:
		return
	if glow:
		VfxParticles.burst("spark", pos, color.lerp(Color.WHITE, 0.25), maxi(int(amount * 0.7), 3), {"speed": speed / 8.0, "life": life / 0.45})
		VfxParticles.burst("glow", pos, color, maxi(int(amount * 0.35), 2), {"speed": speed / 7.0, "size": size / 0.09, "life": life / 0.5})
	else:
		VfxParticles.burst("debris", pos, color, amount, {"speed": speed / 7.0, "size": size / 0.12, "life": life, "grav": Vector3(0, -maxf(gravity, 2.0), 0)})


## 地面扬尘（向四周扩散的烟团）
static func dust(pos: Vector3, amount: int = 10, color: Color = Color(0.78, 0.74, 0.66)) -> void:
	VfxParticles.burst("dust", pos + Vector3.UP * 0.15, color, clampi(int(amount * 0.6), 3, 24), {"shape": "ring", "shape_r": 0.25 + amount * 0.02})


## 冲击环（水平扩散）
static func ring(pos: Vector3, radius: float, color: Color, time: float = 0.35, thickness: float = 0.15, up: Vector3 = Vector3.UP) -> void:
	shock_ring(pos, radius, color, time, clampf(thickness * 1.3, 0.08, 0.4), up)


## 灵气冲击（原球形冲击波）：闪光 + 竖直/水平双环 + 光点，不再使用会遮挡镜头的球体
static func shock_sphere(pos: Vector3, radius: float, color: Color, time: float = 0.3) -> void:
	flash(pos, color, minf(radius * 0.6, 3.0), 0.16)
	cam_ring(pos, radius * 0.7, color, time * 1.1, 0.16)
	shock_ring(pos + Vector3.DOWN * 0.8, radius, color, time * 1.3, 0.14)
	VfxParticles.burst("mote", pos, color, clampi(int(radius * 6), 6, 28), {"spread": 180.0, "speed": 1.5 + radius * 0.4, "shape": "sphere", "shape_r": radius * 0.25})


## 短暂点光源（对象池，最多 8 盏）
static func flash_light(pos: Vector3, color: Color, energy: float = 4.0, light_range: float = 7.0, time: float = 0.2) -> void:
	var m := mgr()
	if m != null:
		m.flash_light(pos, color, energy, light_range, time)


## 光柱（能量圆柱，底部冲击环）
static func pillar(pos: Vector3, radius: float, height: float, color: Color, time: float = 0.6) -> void:
	VfxSpells.light_column(pos, radius, height, color, time, 0)


## 预警：地面法阵（由内向外绘出，径向填充表示剩余时间）
static func telegraph(pos: Vector3, radius: float, color: Color, time: float) -> void:
	magic_circle(pos, radius, VfxLib.elem_of_color(color), time + 0.2, {"ground": true, "fill": time, "reveal": minf(0.4, time * 0.6), "color": color, "spin": 0.7})


## 两点之间的光束/闪电
static func beam(from: Vector3, to: Vector3, color: Color, width: float = 0.2, time: float = 0.15, jagged: bool = false) -> void:
	if jagged:
		VfxSpells.lightning(from, to, color, width, time)
	else:
		beam_strip(from, to, color, width * 3.0, time, 0)


## 陨星/流火
static func meteor(from: Vector3, to: Vector3, color: Color, time: float) -> void:
	VfxSpells.meteor(from, to, VfxLib.elem_of_color(color), time, 1.0)


## 聚灵光点（施法、蓄力）
static func sparkle(pos: Vector3, color: Color, amount: int = 8) -> void:
	VfxParticles.burst("mote", pos, color, maxi(amount, 2), {"spread": 180.0, "speed": 1.2, "size": 0.7, "life": 0.5})
	VfxParticles.burst("glow", pos, color, maxi(amount / 2, 2), {"speed": 0.6, "size": 0.6, "life": 0.6})


# ================================================================ 命中与爆炸

## 近战命中：拉伸火花（沿攻击方向）、冲击闪光、镜头向小环、元素附加粒子。strength 1 普通 / 2 重击；tint 覆盖主色（如妖兽撕咬）
static func hit(point: Vector3, dir: Vector3, elem: String, strength: float = 1.0, _crit: bool = false, tint: Color = Color(0, 0, 0, 0)) -> void:
	if not _visible(point, 80.0):
		return
	var p := VfxLib.pal(elem)
	var main: Color = p["main"] if tint.a <= 0.0 else tint
	var core: Color = p["core"] if tint.a <= 0.0 else tint.lerp(Color.WHITE, 0.6)
	var d := dir.normalized() if dir.length_squared() > 0.01 else Vector3.UP
	var heavy := strength >= 1.5
	flash(point, main, 0.55 + strength * 0.3, 0.1 + strength * 0.03)
	cam_ring(point, 0.35 + strength * 0.25, main, 0.16, 0.3)
	var spark_col: Color = core.lerp(main, 0.35)
	VfxParticles.burst("spark", point, spark_col, int(8 + strength * 6), {"dir": (d + Vector3.UP * 0.25).normalized(), "spread": 55.0, "speed": 0.9 + strength * 0.25})
	VfxParticles.burst("glow", point, main, int(3 + strength * 2), {"speed": 0.8, "size": 0.9})
	_elem_hit_extra(point, d, elem, strength)
	if heavy:
		flash_light(point, main, 3.0, 6.0, 0.18)


## 元素附加（命中与弹道命中共用）
static func _elem_hit_extra(point: Vector3, d: Vector3, elem: String, strength: float) -> void:
	var p := VfxLib.pal(elem)
	match elem:
		"fire":
			VfxParticles.burst("ember", point, Color(1, 0.7, 0.3), int(6 * strength), {"dir": (d + Vector3.UP).normalized(), "speed": 1.4})
			VfxParticles.burst("flame", point, Color.WHITE, int(2 + strength), {"size": 0.6 + strength * 0.2, "life": 0.7})
		"water":
			VfxParticles.burst("droplet", point, Color(0.7, 0.9, 1.0), int(7 * strength), {"dir": (d + Vector3.UP * 0.8).normalized()})
			VfxParticles.burst("mist", point, Color(0.85, 0.95, 1.0), int(1 + strength), {"size": 0.5, "life": 0.7})
		"wood":
			VfxParticles.burst("leaf", point, Color(0.5, 0.95, 0.45), int(2 + strength * 2), {"speed": 1.0, "size": 0.8})
			VfxParticles.burst("pollen", point, p["main"], int(4 * strength), {"speed": 2.0})
		"earth":
			VfxParticles.burst("debris", point, Color(0.55, 0.45, 0.33), int(4 * strength), {"dir": (d + Vector3.UP).normalized(), "size": 0.7})
			VfxParticles.burst("dust", point, Color(0.78, 0.68, 0.5), int(1 + strength), {"size": 0.5, "speed": 0.6})
		"metal":
			VfxParticles.burst("spark", point, Color(1.0, 0.95, 0.7), int(6 * strength), {"spread": 180.0, "speed": 1.3})
		"thunder":
			VfxParticles.burst("spark", point, Color(0.85, 0.8, 1.0), int(6 * strength), {"spread": 180.0, "speed": 1.6, "life": 0.6})
		_:
			VfxParticles.burst("mote", point, p["main"], int(3 * strength), {"spread": 180.0, "speed": 2.0, "size": 0.6, "life": 0.5})


## 暴击：灵气迸发（星芒 + 双环 + 放射光线）
static func crit_burst(pos: Vector3, elem: String) -> void:
	if not _visible(pos, 70.0):
		return
	var e := elem if VfxLib.is_elem(elem) else "none"
	var c := VfxLib.main_color(e)
	sprite(pos, "flare", Color(1, 0.97, 0.85), 2.4, 0.18, 1.4)
	cam_ring(pos, 1.5, c, 0.3, 0.12)
	VfxParticles.burst("streak", pos, VfxLib.core_color(e), 14, {"spread": 180.0, "speed": 0.8})


## 弹道命中（无爆炸）：小闪光 + 沿法线的火花 + 元素附加
static func impact(point: Vector3, normal: Vector3, elem: String, size: float = 0.3) -> void:
	if not _visible(point, 90.0):
		return
	var p := VfxLib.pal(elem)
	var s := clampf(size / 0.3, 0.5, 2.5)
	flash(point, p["main"], 0.45 * s + 0.3, 0.1)
	VfxParticles.burst("spark", point, (p["core"] as Color).lerp(p["main"], 0.4), int(5 + 4 * s), {"dir": normal, "spread": 65.0, "speed": 0.8})
	_elem_hit_extra(point, normal, elem, 0.6 * s)


## 爆炸（按元素）：闪光、冲击环、元素碎屑与烟尘、地面贴花、点光源。opts：molten（熔岩）、ground（是否贴地加环，默认自动）
static func explosion(pos: Vector3, radius: float, elem: String, opts: Dictionary = {}) -> void:
	VfxSpells.explosion(pos, radius, elem, opts)


## 重击落地冲击（近战终结技）：地面冲击环 + 地裂 + 扬尘 + 碎石
static func heavy_ground(pos: Vector3, elem: String, radius: float = 2.2) -> void:
	var ground := CombatUtil.ray_world(pos + Vector3.UP * 1.5, pos + Vector3.DOWN * 3.0)
	if ground.is_empty():
		return
	var gp: Vector3 = ground["position"]
	var c := VfxLib.main_color(elem)
	shock_ring(gp + Vector3.UP * 0.12, radius * 1.6, c, 0.42, 0.14)
	shock_ring(gp + Vector3.UP * 0.1, radius * 1.1, Color(0.9, 0.85, 0.75), 0.55, 0.3, Vector3.UP, 3)
	ground_decal(gp, radius, "crack", 5.0, c, 1.4 if elem in ["fire", "earth"] else 0.9)
	dust(gp, 16)
	VfxParticles.burst("debris", gp + Vector3.UP * 0.2, Color(0.5, 0.45, 0.4), 10, {"size": 0.8, "speed": 0.9})


# ================================================================ 近战剑气

## 由挥砍轨迹生成剑气月牙：tips/bases 为武器尖端与根部的世界坐标序列（按时间先后）。
## 月牙以 pivot 为中心略微外扩并消散。
static func slash_arc(tips: PackedVector3Array, bases: PackedVector3Array, pivot: Vector3, elem: String, color: Color, heavy: bool) -> void:
	var m := mgr()
	var n := tips.size()
	if m == null or n < 3 or not m.visible_at(pivot, 90.0):
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ext := 0.55 if heavy else 0.32
	var inner_f := 0.25
	var rows: Array = []
	for i in n:
		var tip := tips[i] - pivot
		var base := bases[i] - pivot
		var span := tip - base
		rows.append([base + span * inner_f, tip + span * ext])
	for i in n - 1:
		var u0 := float(i) / (n - 1)
		var u1 := float(i + 1) / (n - 1)
		var a0: Array = rows[i]
		var a1: Array = rows[i + 1]
		var vs := [a0[0], a0[1], a1[1], a1[0]]
		var uvs := [Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[idx])
			st.add_vertex(vs[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = VfxLib.slash_mat(int(VfxLib.pal(elem)["slash"]))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.add(mi)
	mi.position = pivot
	mi.set_instance_shader_parameter("tint", color)
	mi.set_instance_shader_parameter("prog", 0.0)
	var life := 0.36 if heavy else 0.26
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "instance_shader_parameters/prog", 1.0, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(mi, "scale", Vector3.ONE * (1.22 if heavy else 1.1), life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.chain().tween_callback(mi.queue_free)
	if heavy:
		var tip_last := tips[n - 1]
		VfxParticles.burst("streak", tip_last, VfxLib.core_color(elem), 8, {"dir": (tips[n - 1] - tips[n - 2]).normalized(), "spread": 25.0})


# ================================================================ 施法、身法、状态（转发）

static func cast_begin(actor: Node3D, def: Dictionary) -> void:
	VfxSpells.cast_begin(actor, def)


static func cast_release(origin: Vector3, dir: Vector3, def: Dictionary) -> void:
	VfxSpells.cast_release(origin, dir, def)


static func talisman(actor: Node3D, elem: String) -> void:
	VfxSpells.talisman(actor, elem)


static func quick_boost(actor: Node3D, dir: Vector3, color: Color) -> void:
	VfxMotion.quick_boost(actor, dir, color)


static func dash_start(actor: Node3D, dir: Vector3, color: Color) -> void:
	VfxMotion.dash_start(actor, dir, color)


static func lunge_start(actor: Node3D, dir: Vector3, color: Color) -> void:
	VfxMotion.lunge_start(actor, dir, color)


static func land(pos: Vector3, strength: float) -> void:
	VfxMotion.land(pos, strength)


static func jump(pos: Vector3) -> void:
	VfxMotion.jump(pos)


static func afterimage(rig: Node3D, color: Color, life: float = 0.35) -> void:
	VfxMotion.afterimage(rig, color, life)


static func shield_break(pos: Vector3, color: Color) -> void:
	VfxMotion.shield_break(pos, color)


static func death(actor: Node3D, elem: String) -> void:
	VfxMotion.death(actor, elem)


static func dissolve(actor: Node3D, time: float) -> void:
	VfxMotion.dissolve(actor, time)


static func breakthrough(actor: Node3D) -> void:
	VfxMotion.breakthrough(actor)


static func level_up(actor: Node3D) -> void:
	VfxMotion.level_up(actor)


## 给角色挂上持续特效组件（疾行尾流、状态、护盾、蓄力等）
static func attach(actor: Node3D) -> ActorVfx:
	return ActorVfx.attach(actor)


static func vfx_of(actor: Node) -> ActorVfx:
	if actor == null or not is_instance_valid(actor) or not actor.has_meta("vfx"):
		return null
	var v = actor.get_meta("vfx")
	return v as ActorVfx if v != null and is_instance_valid(v) else null
