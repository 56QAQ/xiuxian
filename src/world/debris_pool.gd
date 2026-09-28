class_name DebrisPool
extends Node3D
## 体素碎块对象池：小立方体 RigidBody3D（debris 层 5，只与 world 层碰撞），
## 最多同时存在 MAX_LIVE 个，最旧的会被回收；存活约 LIFETIME 秒，最后 FADE 秒用 instance uniform
## "dissolve" 溶解后回池。颜色通过 voxel.gdshader 的 instance uniform "tint" 设置（共享一个白色立方体网格）。

const MAX_LIVE := 100
const LIFETIME := 5.0
const FADE := 1.2
const LAYER_DEBRIS := 1 << 4
const MASK_WORLD := 1

static var _cube: ArrayMesh

var _bodies: Array[RigidBody3D] = []
var _age: PackedFloat32Array = PackedFloat32Array()
var _next := 0


## 取得当前场景树中的碎块池（没有则创建，挂在当前场景下）
static func get_pool(from: Node) -> DebrisPool:
	var tree := from.get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene if tree.current_scene != null else tree.root
	var p := scene.get_node_or_null("DebrisPool")
	if p is DebrisPool:
		return p
	var pool := DebrisPool.new()
	pool.name = "DebrisPool"
	scene.add_child(pool)
	return pool


static func cube_mesh() -> ArrayMesh:
	if _cube == null:
		var bm := BuildingMesh.new()
		bm.jitter = 0.0
		bm.box(Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.5, 0.5), Color(1, 1, 1))
		_cube = bm.build_mesh()
	return _cube


func _ready() -> void:
	top_level = true
	_age.resize(MAX_LIVE)
	for i in MAX_LIVE:
		var rb := RigidBody3D.new()
		rb.collision_layer = LAYER_DEBRIS
		rb.collision_mask = MASK_WORLD
		rb.mass = 0.3
		rb.gravity_scale = 1.6
		rb.continuous_cd = false
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = cube_mesh()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rb.add_child(mi)
		rb.process_mode = Node.PROCESS_MODE_DISABLED
		rb.visible = false
		rb.freeze = true
		add_child(rb)
		_bodies.append(rb)
		_age[i] = -1.0


## 生成一个碎块。size 为边长（米），vel 为初速度。
func spawn(pos: Vector3, size: float, color: Color, vel: Vector3) -> void:
	var i := _next
	_next = (_next + 1) % MAX_LIVE
	var rb := _bodies[i]
	var cs := rb.get_child(0) as CollisionShape3D
	(cs.shape as BoxShape3D).size = Vector3.ONE * size
	var mi := rb.get_child(1) as MeshInstance3D
	mi.scale = Vector3.ONE * size
	mi.set_instance_shader_parameter("tint", Color(color.r, color.g, color.b, 1.0))
	mi.set_instance_shader_parameter("dissolve", 0.0)
	rb.process_mode = Node.PROCESS_MODE_INHERIT
	rb.visible = true
	rb.freeze = false
	rb.global_transform = Transform3D(Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU)), pos)
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	rb.sleeping = false
	_age[i] = 0.0


## 一次喷发多个碎块：从 center 向外飞散
func burst(center: Vector3, samples: Array, power: float = 1.0, size: float = 0.35) -> void:
	for s in samples:
		var p: Vector3 = s[0]
		var c: Color = s[1]
		var dir := (p - center)
		dir.y = absf(dir.y) + 0.6
		dir = dir.normalized()
		var v := dir * randf_range(3.0, 7.0) * (0.6 + 0.4 * power) + Vector3(0, randf_range(2.0, 5.0), 0)
		spawn(p, size * randf_range(0.7, 1.3), c, v)


func live_count() -> int:
	var n := 0
	for a in _age:
		if a >= 0.0:
			n += 1
	return n


func _process(delta: float) -> void:
	for i in MAX_LIVE:
		var a := _age[i]
		if a < 0.0:
			continue
		a += delta
		_age[i] = a
		var rb := _bodies[i]
		if a > LIFETIME - FADE:
			var mi := rb.get_child(1) as MeshInstance3D
			mi.set_instance_shader_parameter("dissolve", clampf((a - (LIFETIME - FADE)) / FADE, 0.0, 1.0))
		if a >= LIFETIME or rb.global_position.y < -20.0:
			_age[i] = -1.0
			rb.freeze = true
			rb.visible = false
			rb.process_mode = Node.PROCESS_MODE_DISABLED
