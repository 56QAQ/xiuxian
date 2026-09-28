class_name SpellBeam
extends Node3D
## 光束法诀：从施法者手中持续射出，沿射线周期性造成伤害。

var caster: Node3D
var def: Dictionary
var level: int = 0
var length: float = 30.0
var width: float = 0.6
var duration: float = 2.0
var tick: float = 0.2
var _t: float = 0.0
var _tick_t: float = 0.0
var _mesh: MeshInstance3D
var _color: Color


static func spawn(caster_body: Node3D, spell_def: Dictionary, lv: int) -> SpellBeam:
	var b := SpellBeam.new()
	b.caster = caster_body
	b.def = spell_def
	b.level = lv
	var p: Dictionary = spell_def.get("params", {})
	b.length = float(p.get("length", 30.0))
	b.width = float(p.get("width", 0.6))
	b.duration = float(p.get("duration", 2.0))
	b.tick = float(p.get("tick", 0.2))
	b._color = SpellRuntime.color_of(spell_def)
	FX.root().add_child(b)
	b._mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	b._mesh.mesh = bm
	b._mesh.material_override = FX.glow_mat(b._color)
	b._mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(b._mesh)
	if caster_body.has_method("begin_channel"):
		caster_body.call("begin_channel", b.duration)
	return b


func _physics_process(delta: float) -> void:
	_t += delta
	var c := CombatUtil.combatant_of(caster)
	if caster == null or not is_instance_valid(caster) or c == null or not c.alive or _t > duration:
		queue_free()
		return
	var from: Vector3 = caster.call("cast_origin")
	var aim: Vector3 = caster.call("aim_point")
	var tgt: Node3D = caster.get("lock_target")
	if tgt != null and is_instance_valid(tgt):
		aim = tgt.global_position + Vector3.UP
	var dir := (aim - from).normalized()
	var to := from + dir * length
	var hit := CombatUtil.ray_world(from, to)
	if not hit.is_empty():
		to = hit["position"]
	var l := from.distance_to(to)
	global_position = (from + to) * 0.5
	if l > 0.05:
		look_at(to, Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT)
	var w := width * (0.8 + 0.2 * sin(_t * 40.0))
	_mesh.scale = Vector3(w, w, l)
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = tick
		for b in CombatUtil.bodies():
			var body := b as Node3D
			if body == null or not CombatUtil.can_damage(caster, body):
				continue
			if CombatUtil.dist_point_segment(body.global_position + Vector3.UP, from, to) <= width + 0.5:
				var info := SpellRuntime.base_info(caster, def, level)
				info["knock"] = 1.0
				info["no_react"] = true
				CombatUtil.hit(caster, body, info)
		if not hit.is_empty():
			var col = hit.get("collider")
			if col != null and col.has_method("apply_damage_at"):
				col.call("apply_damage_at", to, width, SpellRuntime.power_mult(def, level) * 6.0)
			FX.burst(to, _color, 6, 4.0, 0.08, 0.3)
