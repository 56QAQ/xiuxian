class_name WaterPlane
extends Node3D
## 海面/湖面：一个覆盖全图并延伸到地平线的平面（water.gdshader），
## 另有一个位于 water 层（第 8 层）的静态碰撞体，供入水判定与特效使用。

const LAYER_WATER := 1 << 7

var mesh_instance: MeshInstance3D
var material: ShaderMaterial
var body: StaticBody3D


func _ready() -> void:
	var y := TerrainGen.WATER_Y
	material = ShaderMaterial.new()
	material.shader = load("res://assets/shaders/water.gdshader")
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "WaterMesh"
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	mesh_instance.mesh = pm
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.position = Vector3(TerrainGen.SIZE * 0.5, y, TerrainGen.SIZE * 0.5)
	add_child(mesh_instance)
	body = StaticBody3D.new()
	body.name = "WaterBody"
	body.collision_layer = LAYER_WATER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(TerrainGen.SIZE + 400, 2.0, TerrainGen.SIZE + 400)
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(TerrainGen.SIZE * 0.5, y - 1.0, TerrainGen.SIZE * 0.5)
	add_child(body)


## 由 DayNight 调用：天空反射色与日照强度
func set_sky_color(c: Color, daylight: float) -> void:
	if material:
		material.set_shader_parameter("sky_color", c)
		material.set_shader_parameter("daylight", clampf(daylight, 0.08, 1.0))
