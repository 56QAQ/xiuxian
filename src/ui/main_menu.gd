extends Control
## 主菜单（scenes/main_menu.tscn）：水墨远山 + 浮空仙岛上打坐的体素修士（3D，透明叠加）+ 飘落花瓣 + 灵气微光。
## 按钮：新的仙途 / 继续仙途 / 读取存档 / 设置 / 退出。

const VERSION_TEXT := "v0.1「初入仙途」"

var ui: UIManager
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _rig: CharacterRig
var _lanterns: Array[Node3D] = []
var _island: Node3D
var _time: float = 0.0
var _mouse: Vector2 = Vector2.ZERO
var _menu: VBoxContainer
var _title_box: Control
var _entries: Array[MenuEntry] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	GS.in_realm = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := InkBackdrop.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.moon_pos = Vector2(0.8, 0.2)
	add_child(bg)
	_build_3d()
	add_child(_make_mist())
	add_child(_make_particles())
	_build_ui()
	ui = UIManager.new()
	ui.hotkeys_enabled = false
	ui.pause_menu_enabled = false
	add_child(ui)
	_intro()


# ================================================================ 3D 场景

func _build_3d() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.8)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_world.add_child(env)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-35, 40, 0)
	moon.light_color = Color(0.75, 0.82, 1.0)
	moon.light_energy = 1.1
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 30.0
	_world.add_child(moon)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 200, 0)
	rim.light_color = Color(1.0, 0.75, 0.5)
	rim.light_energy = 0.8
	_world.add_child(rim)
	var warm := OmniLight3D.new()
	warm.position = Vector3(0.6, 1.4, 0.9)
	warm.light_color = Color(1.0, 0.6, 0.3)
	warm.light_energy = 1.6
	warm.omni_range = 4.5
	_world.add_child(warm)
	_island = _make_island()
	_world.add_child(_island)
	var spear: Dictionary = DB.item("flag_spear_fire").get("weapon", {}).get("visual", {})
	_rig = CharacterBuilder.build({"hair_style": "twin_tails", "ears": "fox", "outfit": "armor", "mark": "flame"}, {"weapon": spear})
	_rig.position = Vector3(0.1, 0.1, 0.2)
	_rig.rotation_degrees.y = 140.0
	_island.add_child(_rig)
	for i in 4:
		var l := _make_lantern(i)
		_world.add_child(l)
		_lanterns.append(l)
	_world.add_child(_make_motes())
	_cam = Camera3D.new()
	_cam.fov = 34.0
	_world.add_child(_cam)
	_update_camera(0.0)


func _update_camera(t: float) -> void:
	var sway := Vector3(_mouse.x * 0.25, -_mouse.y * 0.12, 0)
	_cam.position = Vector3(-2.4, 2.0, 8.4) + sway + Vector3(sin(t * 0.13) * 0.15, sin(t * 0.21) * 0.08, 0)
	_cam.look_at(Vector3(-2.05, 0.8, 0), Vector3.UP)


## 浮空仙岛：体素顶面（青石台 + 金边）+ 倒锥形岩体 + 松树
func _make_island() -> Node3D:
	var root := Node3D.new()
	var vs := 0.1
	var R := 19
	var H := 20
	var g := VoxelGrid.new(R * 2 + 1, H + 3, R * 2 + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.15
	for z in g.sz:
		for x in g.sx:
			var d := Vector2(x - R, z - R).length()
			var edge := R - 0.5 + noise.get_noise_2d(x, z) * 1.8
			if d > edge:
				continue
			# 倒锥：离中心越远越浅
			var depth := int((1.0 - d / edge) * H * (0.75 + 0.25 * noise.get_noise_2d(x * 2.0, z * 2.0))) + 1
			for y in range(H - depth, H + 1):
				var tone := 0.3 + 0.08 * noise.get_noise_2d(x * 3.0, y * 3.0)
				var c := Color(tone, tone * 1.02, tone * 1.12)
				if y == H:
					c = Color(0.28, 0.46, 0.3).lerp(Color(0.36, 0.55, 0.32), rng.randf())
				elif y >= H - 1:
					c = Color(0.36, 0.28, 0.2)
				g.set_color(x, y, z, c)
	# 石台
	for z in g.sz:
		for x in g.sx:
			var d2 := Vector2(x - R, z - R).length()
			if d2 <= 7.5:
				var stone := Color(0.52, 0.53, 0.56).lerp(Color(0.6, 0.6, 0.62), rng.randf())
				var ring := d2 > 6.6 or (d2 > 3.2 and d2 < 4.0)
				g.set_color(x, H + 1, z, Color(0.82, 0.64, 0.3) if ring else stone)
	var mi := VoxelMesher.build_instance(g, vs, Vector3(-R - 0.5, -H - 1, -R - 0.5) * vs)
	root.add_child(mi)
	# 松树
	var tree := VoxelGrid.new(9, 16, 9)
	tree.fill_box(Vector3i(4, 0, 4), Vector3i(4, 6, 4), Color(0.35, 0.24, 0.16))
	for layer in 4:
		var y0 := 4 + layer * 3
		var rr := 4.2 - layer * 0.9
		tree.fill_cylinder_y(4.5, 4.5, rr, y0, y0 + 2, Color(0.16, 0.3, 0.22).lerp(Color(0.22, 0.4, 0.28), layer / 3.0))
	var tmi := VoxelMesher.build_instance(tree, vs * 0.9, Vector3(-4.5, 0, -4.5) * vs * 0.9)
	tmi.position = Vector3(1.25, 0.05, -0.9)
	root.add_child(tmi)
	root.position = Vector3(0, -0.2, 0)
	return root


func _make_lantern(i: int) -> Node3D:
	var n := Node3D.new()
	var g := VoxelGrid.new(6, 9, 6)
	var red := VoxelGrid.glow(Color(1.0, 0.35, 0.15), 0.75)
	g.fill_ellipsoid(Vector3(3, 4.5, 3), Vector3(3, 3.6, 3), red)
	g.fill_box(Vector3i(1, 0, 1), Vector3i(4, 0, 4), Color(0.2, 0.12, 0.08))
	g.fill_box(Vector3i(1, 8, 1), Vector3i(4, 8, 4), Color(0.2, 0.12, 0.08))
	g.fill_box(Vector3i(2, 4, 0), Vector3i(3, 5, 0), VoxelGrid.glow(Color(1.0, 0.85, 0.4), 1.0))
	var mi := VoxelMesher.build_instance(g, 0.045, Vector3(-3, -4.5, -3) * 0.045)
	n.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.25)
	light.light_energy = 0.9
	light.omni_range = 2.2
	n.add_child(light)
	n.set_meta("phase", i * 1.7)
	n.set_meta("radius", 2.1 + i * 0.4)
	n.set_meta("height", 1.3 + i * 0.5)
	return n


## 灵气微光：上升的金色光点
func _make_motes() -> Node3D:
	var p := CPUParticles3D.new()
	p.amount = 48
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.2
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0, 0.12, 0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = UITheme.icon("dot")
	mat.albedo_color = Color(1.0, 0.85, 0.45, 0.9)
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.position = Vector3(0, 1.0, 0)
	return p


func _make_mist() -> Control:
	var m := MistLayer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return m


## 飘落花瓣（2D 粒子）
func _make_particles() -> Control:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var petals := CPUParticles2D.new()
	petals.texture = _petal_texture()
	petals.amount = 46
	petals.lifetime = 14.0
	petals.preprocess = 14.0
	petals.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	petals.emission_rect_extents = Vector2(1100, 20)
	petals.position = Vector2(700, -40)
	petals.direction = Vector2(0.5, 1.0)
	petals.spread = 20.0
	petals.gravity = Vector2(14, 22)
	petals.initial_velocity_min = 30.0
	petals.initial_velocity_max = 70.0
	petals.angular_velocity_min = -90.0
	petals.angular_velocity_max = 90.0
	petals.angle_min = 0.0
	petals.angle_max = 360.0
	petals.scale_amount_min = 0.5
	petals.scale_amount_max = 1.1
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.1, Color(1, 1, 1, 0.9))
	ramp.add_point(0.85, Color(1, 1, 1, 0.8))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	petals.color_ramp = ramp
	host.add_child(petals)
	var motes := CPUParticles2D.new()
	motes.texture = UITheme.icon("dot")
	motes.amount = 40
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(1000, 60)
	motes.position = Vector2(960, 1100)
	motes.direction = Vector2(0, -1)
	motes.spread = 25.0
	motes.gravity = Vector2(0, -6)
	motes.initial_velocity_min = 20.0
	motes.initial_velocity_max = 50.0
	motes.scale_amount_min = 0.12
	motes.scale_amount_max = 0.3
	var mr := Gradient.new()
	mr.set_color(0, Color(1.0, 0.85, 0.5, 0))
	mr.add_point(0.3, Color(1.0, 0.85, 0.5, 0.7))
	mr.set_color(mr.get_point_count() - 1, Color(1.0, 0.85, 0.5, 0))
	motes.color_ramp = mr
	host.add_child(motes)
	return host


static func _petal_texture() -> ImageTexture:
	var w := 28
	var h := 18
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5) / h * 2.0 - 1.0
			var shape := u * u + (v * v) / maxf(1.0 - absf(u) * 0.45, 0.2)
			if shape <= 1.0:
				var a := clampf((1.0 - shape) * 3.0, 0.0, 1.0)
				var c := Color(1.0, 0.72, 0.8).lerp(Color(1.0, 0.9, 0.93), (1.0 - v) * 0.4)
				c.a = a
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_time += delta
	var vp := get_viewport_rect().size
	if vp.x > 0:
		var m := get_viewport().get_mouse_position() / vp - Vector2(0.5, 0.5)
		_mouse = _mouse.lerp(m, 1.0 - exp(-2.0 * delta))
	if _cam != null:
		_update_camera(_time)
	if _island != null:
		_island.position.y = -0.2 + sin(_time * 0.7) * 0.05
	for l in _lanterns:
		var ph := float(l.get_meta("phase"))
		var r := float(l.get_meta("radius"))
		var a := _time * 0.12 + ph
		l.position = Vector3(cos(a) * r, float(l.get_meta("height")) + sin(_time * 0.9 + ph) * 0.12, sin(a) * r * 0.6 - 0.3)
		l.rotation.y = _time * 0.3 + ph


# ================================================================ 界面

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# 标题
	_title_box = TitleBlock.new()
	_title_box.position = Vector2(110, 110)
	root.add_child(_title_box)
	# 菜单
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 4)
	_menu.position = Vector2(118, 420)
	_menu.custom_minimum_size = Vector2(420, 0)
	root.add_child(_menu)
	_add_entry("新的仙途", "", Scenes.goto_creator)
	var slot := SaveManager.any_save()
	var sub := ""
	if slot >= 0:
		var meta := SaveManager.slot_meta(slot)
		sub = "%s · %s · %s" % [meta.get("name", "无名"), meta.get("realm", ""), meta.get("date", "")]
	var cont := _add_entry("继续仙途", sub, _continue)
	cont.disabled = slot < 0
	_add_entry("读取存档", "", func() -> void: ui.open("saves", {"mode": "load"}))
	_add_entry("设置", "", func() -> void: ui.open("settings"))
	_add_entry("退出", "", func() -> void: get_tree().quit())
	# 角标
	var ver := UITheme.label(VERSION_TEXT, 15, UITheme.TEXT_FAINT)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(24, -36)
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(ver)
	var hint := UITheme.label("天元界 · 青州", 15, UITheme.TEXT_FAINT)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position = Vector2(-150, -36)
	root.add_child(hint)


func _add_entry(text: String, sub: String, cb: Callable) -> MenuEntry:
	var e := MenuEntry.new()
	e.label_text = text
	e.sub_text = sub
	e.pressed.connect(cb)
	_menu.add_child(e)
	_entries.append(e)
	return e


func _intro() -> void:
	_title_box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_title_box, "modulate:a", 1.0, 1.2).set_delay(0.2)
	for i in _entries.size():
		var e := _entries[i]
		e.modulate.a = 0.0
		var t2 := create_tween()
		t2.tween_property(e, "modulate:a", 1.0, 0.5).set_delay(0.6 + i * 0.1)


func _continue() -> void:
	var slot := SaveManager.any_save()
	if slot < 0:
		return
	if SaveManager.load_game(slot):
		Scenes.goto_overworld()
	else:
		Events.notify.emit("存档损坏，无法读取", "bad")


## 菜单项：墨痕高亮 + 金色菱形 + 文字右移
class MenuEntry extends Button:
	var label_text: String = ""
	var sub_text: String = ""
	var hover_t: float = 0.0
	var _tw: Tween

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(420, 64)
		var empty := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			add_theme_stylebox_override(s, empty)
		mouse_entered.connect(_hover.bind(true))
		mouse_exited.connect(_hover.bind(false))
		pressed.connect(func() -> void: Audio.play("ui_click"))

	func _hover(on: bool) -> void:
		if disabled:
			return
		if on:
			Audio.play("ui_hover", -6.0)
		if _tw != null:
			_tw.kill()
		_tw = create_tween()
		_tw.tween_method(_set_hover, hover_t, 1.0 if on else 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _set_hover(v: float) -> void:
		hover_t = v
		queue_redraw()

	func _draw() -> void:
		var h := size.y
		if hover_t > 0.01:
			var w := size.x * hover_t
			var pts := PackedVector2Array()
			var n := 16
			for i in n + 1:
				var x := w * i / n
				pts.append(Vector2(x, h * 0.18 + sin(i * 1.7) * 2.0))
			for i in range(n, -1, -1):
				var x2 := w * i / n
				pts.append(Vector2(x2, h * 0.86 + sin(i * 2.3) * 2.0))
			var cols := PackedColorArray()
			for p in pts:
				var fa := 1.0 - p.x / maxf(size.x, 1.0)
				cols.append(Color(0.02, 0.02, 0.03, 0.62 * fa * hover_t))
			draw_polygon(pts, cols)
			draw_line(Vector2(0, h * 0.86), Vector2(w * 0.8, h * 0.86), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.6 * hover_t), 1.0)
		var f := UITheme.font_title()
		var fs := 32
		var x0 := 26.0 + 14.0 * hover_t
		var base_y := h * 0.5 + fs * 0.36 - (7.0 if sub_text != "" else 0.0)
		var col := Color(0.92, 0.88, 0.78).lerp(UITheme.GOLD_BRIGHT, hover_t)
		if disabled:
			col = Color(0.55, 0.53, 0.5, 0.55)
		var r := 5.0 + 1.5 * hover_t
		var dp := Vector2(8.0 + 6.0 * hover_t, base_y - fs * 0.34)
		var dc := Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.35 + 0.65 * hover_t) if not disabled else Color(0.4, 0.4, 0.4, 0.3)
		draw_colored_polygon(PackedVector2Array([dp + Vector2(0, -r), dp + Vector2(r, 0), dp + Vector2(0, r), dp + Vector2(-r, 0)]), dc)
		draw_string_outline(f, Vector2(x0, base_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.02, 0.02, 0.04, 0.7))
		draw_string(f, Vector2(x0, base_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if sub_text != "":
			var lf := UITheme.font_regular()
			draw_string_outline(lf, Vector2(x0 + 2, base_y + 22), sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.6))
			draw_string(lf, Vector2(x0 + 2, base_y + 22), sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.TEXT_DIM if not disabled else UITheme.TEXT_FAINT)


## 标题：大字“问道长生” + 朱砂印 + 副题
class TitleBlock extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(760, 260)
		size = custom_minimum_size

	func _draw() -> void:
		var f := UITheme.font_title()
		var fs := 124
		var t := "问道长生"
		var pos := Vector2(0, fs)
		# 墨晕
		var glow := UITheme.icon("dot")
		draw_texture_rect(glow, Rect2(Vector2(-80, -40), Vector2(720, 300)), false, Color(0, 0, 0, 0.45))
		draw_string(f, pos + Vector2(4, 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5))
		draw_string_outline(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color(0.1, 0.06, 0.02, 0.9))
		draw_string(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.GOLD_BRIGHT)
		# 高光：上半部分叠一层浅色
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# 朱砂印
		var seal := Rect2(Vector2(tw + 22, fs - 88), Vector2(56, 88))
		draw_rect(seal, Color(0.72, 0.14, 0.1, 0.92))
		draw_rect(seal.grow(-4), Color(1.0, 0.85, 0.75, 0.55), false, 1.5)
		var sf := 26
		for i in 2:
			var ch: String = ["仙", "途"][i]
			var cs := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sf)
			draw_string(f, Vector2(seal.position.x + (seal.size.x - cs.x) * 0.5, seal.position.y + 36 + i * 34), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sf, Color(1.0, 0.9, 0.82))
		# 副题
		var sep_y := fs + 36.0
		draw_line(Vector2(6, sep_y), Vector2(tw * 0.92, sep_y), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.6), 1.0)
		var d := Vector2(tw * 0.46, sep_y)
		draw_colored_polygon(PackedVector2Array([d + Vector2(0, -5), d + Vector2(5, 0), d + Vector2(0, 5), d + Vector2(-5, 0)]), UITheme.GOLD)
		var sub := "一 念 问 道   ·   万 古 长 生"
		var lf := UITheme.font_regular()
		draw_string_outline(lf, Vector2(10, sep_y + 38), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 5, Color(0, 0, 0, 0.6))
		draw_string(lf, Vector2(10, sep_y + 38), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.86, 0.8, 0.66))


## 前景薄雾：缓慢漂移的柔光团
class MistLayer extends Control:
	var _t: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var glow := UITheme.icon("dot")
		var w := size.x
		var h := size.y
		for i in 6:
			var speed := 8.0 + i * 3.0
			var x := fmod(i * 420.0 + _t * speed, w + 900.0) - 600.0
			var y := h * (0.72 + 0.05 * sin(i * 1.3 + _t * 0.1))
			draw_texture_rect(glow, Rect2(Vector2(x, y), Vector2(900, 260)), false, Color(0.72, 0.74, 0.82, 0.09))
		var pts := PackedVector2Array([Vector2(0, h * 0.8), Vector2(w, h * 0.8), Vector2(w, h), Vector2(0, h)])
		draw_polygon(pts, PackedColorArray([Color(0.5, 0.52, 0.6, 0.0), Color(0.5, 0.52, 0.6, 0.0), Color(0.12, 0.13, 0.17, 0.55), Color(0.12, 0.13, 0.17, 0.55)]))
		# 左侧压暗（保证菜单可读）
		var lp := PackedVector2Array([Vector2(0, 0), Vector2(w * 0.5, 0), Vector2(w * 0.5, h), Vector2(0, h)])
		draw_polygon(lp, PackedColorArray([Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.45)]))
