class_name SpellField
extends Node3D
## 持续领域（青藤缠等）：周期性对范围内敌人造成伤害、附加状态并减速。

var caster: Node3D
var def: Dictionary
var level: int = 0
var radius: float = 5.0
var duration: float = 5.0
var tick: float = 0.5
var slow: float = 0.0
var _t: float = 0.0
var _tick_t: float = 0.0
var _color: Color
var _particles: CPUParticles3D


static func spawn(caster_body: Node3D, pos: Vector3, spell_def: Dictionary, lv: int) -> SpellField:
	var f := SpellField.new()
	f.caster = caster_body
	f.def = spell_def
	f.level = lv
	var p: Dictionary = spell_def.get("params", {})
	f.radius = float(p.get("radius", 5.0))
	f.duration = float(p.get("duration", 5.0)) * (1.0 + 0.04 * lv)
	f.tick = float(p.get("tick", 0.5))
	f.slow = float(p.get("slow", 0.0))
	f._color = SpellRuntime.color_of(spell_def)
	FX.root().add_child(f)
	f.global_position = pos
	f._build()
	return f


func _build() -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.06
	cm.radial_segments = 32
	disc.mesh = cm
	var m := FX.glow_mat(_color).duplicate() as StandardMaterial3D
	m.albedo_color = Color(_color.r, _color.g, _color.b, 0.28)
	disc.material_override = m
	disc.position.y = 0.08
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	_particles = CPUParticles3D.new()
	_particles.amount = int(radius * 12)
	_particles.lifetime = 1.2
	_particles.mesh = FX.cube_mesh()
	_particles.material_override = FX.glow_mat(_color)
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = radius
	_particles.direction = Vector3.UP
	_particles.spread = 15.0
	_particles.gravity = Vector3(0, 1.5, 0)
	_particles.initial_velocity_min = 0.5
	_particles.initial_velocity_max = 2.0
	_particles.scale_amount_min = 0.06
	_particles.scale_amount_max = 0.18
	_particles.color_ramp = FX._fade_gradient(_color)
	_particles.position.y = 0.3
	add_child(_particles)
	FX.ring(global_position + Vector3.UP * 0.1, radius, _color, 0.4)


func _physics_process(delta: float) -> void:
	_t += delta
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = tick
		var owner_b: Node3D = caster if is_instance_valid(caster) else null
		for body in CombatUtil.targets_in_radius(owner_b, global_position + Vector3.UP * 0.5, radius):
			var info := SpellRuntime.base_info(owner_b, def, level) if owner_b != null else {"kind": "spell", "mult": 0.2}
			info["knock"] = 0.0
			info["poise"] = 4.0
			info["no_react"] = true
			CombatUtil.hit(owner_b, body, info)
			var c := CombatUtil.combatant_of(body)
			if c != null and slow > 0.0:
				c.apply_status("slow", 1.0, null)
	if _t >= duration:
		set_physics_process(false)
		_particles.emitting = false
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3(1, 0.01, 1), 0.4)
		tw.tween_callback(queue_free)
