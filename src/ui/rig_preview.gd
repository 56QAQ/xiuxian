class_name RigPreview
extends SubViewportContainer
## 体素角色 3D 预览（独立 World3D + 透明背景 + 影棚三点光 + 体素石台）。
## 拖动旋转、滚轮缩放；set_appearance() 防抖（默认 0.15 秒）后重建角色。
## 捏人、角色面板、储物袋纸娃娃、对话头像共用。

signal rebuilt(rig: CharacterRig)

## 取景：full 全身 · upper 半身 · bust 头像
@export var framing: String = "full"
@export var allow_rotate: bool = true
@export var allow_zoom: bool = true
@export var pedestal: bool = true
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

const FRAMES := {
	"full": {"look": Vector3(0, 0.9, 0), "dist": 4.5, "fov": 30.0},
	"upper": {"look": Vector3(0, 1.3, 0), "dist": 2.2, "fov": 30.0},
	"bust": {"look": Vector3(0, 1.48, 0), "dist": 1.75, "fov": 28.0},
}


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(160, 220)


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = Vector2i(maxi(int(size.x), 64), maxi(int(size.y), 64))
	add_child(_vp)
	_world = Node3D.new()
	_vp.add_child(_world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.74, 0.85)
	e.ambient_light_energy = 0.62
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	env.environment = e
	_world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -32, 0)
	key.light_energy = 1.3
	key.light_color = Color(1.0, 0.93, 0.82)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 12.0
	_world.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, 160, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.6, 0.75, 1.0)
	_world.add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 40, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(1.0, 0.85, 0.75)
	_world.add_child(fill)
	if pedestal:
		_world.add_child(build_pedestal(20, 1234))
	_cam = Camera3D.new()
	_world.add_child(_cam)
	_apply_framing(true)
	if not appearance.is_empty() or rig == null:
		rebuild_now()


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
	if ar != null:
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
	rig = CharacterBuilder.build(appearance, equip_visual)
	rig.meditating = meditating
	_world.add_child(rig)
	if pedestal:
		rig.position.y = 0.1
	_apply_yaw()
	rebuilt.emit(rig)


func set_framing(f: String) -> void:
	framing = f
	_apply_framing(false)


func _apply_framing(snap: bool) -> void:
	var fr: Dictionary = FRAMES.get(framing, FRAMES["full"])
	if snap:
		_cam_look = fr["look"]
		_cam_dist = fr["dist"]
	if _cam != null:
		_cam.fov = fr["fov"]
		_update_camera()


func _update_camera() -> void:
	if _cam == null:
		return
	var h := 0.18 if framing == "full" else 0.05
	_cam.position = _cam_look + Vector3(0, h, _cam_dist * zoom)
	_cam.look_at(_cam_look, Vector3.UP)


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
	var fr: Dictionary = FRAMES.get(framing, FRAMES["full"])
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


## 体素石台：圆形青石 + 金边回纹
static func build_pedestal(radius: int = 20, seed_value: int = 1) -> Node3D:
	var g := VoxelGrid.new(radius * 2 + 2, 5, radius * 2 + 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var c := Vector2(radius + 1, radius + 1)
	for z in g.sz:
		for x in g.sx:
			var d := Vector2(x + 0.5, z + 0.5).distance_to(c)
			if d > radius + 0.5:
				continue
			var stone := Color(0.34, 0.36, 0.4).lerp(Color(0.44, 0.45, 0.47), rng.randf())
			for y in 3:
				g.set_color(x, y, z, stone.darkened(0.15 * (2 - y)))
			if d > radius - 1.5:
				g.set_color(x, 3, z, Color(0.82, 0.64, 0.3))
			elif d > radius - 3.5:
				g.set_color(x, 3, z, Color(0.25, 0.26, 0.3))
			elif d < 5.5 and d > 4.2:
				g.set_color(x, 3, z, Color(0.7, 0.55, 0.28))
	var mi := VoxelMesher.build_instance(g, CharacterBuilder.VOXEL, Vector3(-radius - 1, -3.9, -radius - 1) * CharacterBuilder.VOXEL)
	mi.name = "Pedestal"
	return mi
