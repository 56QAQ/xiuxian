class_name VoxelFragment
extends RigidBody3D
## 脱落的体素孤岛：整体下落的刚体（debris 层 5，只与 world 层碰撞），约 LIFETIME 秒后溶解消失。

const LIFETIME := 7.0
const FADE := 1.5

var _age := 0.0
var _mi: MeshInstance3D


func setup(mesh: ArrayMesh, voxels: int, vs: float) -> void:
	collision_layer = DebrisPool.LAYER_DEBRIS
	collision_mask = DebrisPool.MASK_WORLD
	mass = clampf(voxels * vs * vs * vs * 600.0, 2.0, 400.0)
	gravity_scale = 1.4
	_mi = MeshInstance3D.new()
	_mi.mesh = mesh
	add_child(_mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_convex_shape(true, true) if mesh.get_surface_count() > 0 else BoxShape3D.new()
	add_child(cs)


func _enter_tree() -> void:
	VoxelDestructible._falling_changed(1)


func _exit_tree() -> void:
	VoxelDestructible._falling_changed(-1)


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME - FADE and _mi:
		_mi.set_instance_shader_parameter("dissolve", clampf((_age - (LIFETIME - FADE)) / FADE, 0.0, 1.0))
	if _age >= LIFETIME or global_position.y < -30.0:
		queue_free()
