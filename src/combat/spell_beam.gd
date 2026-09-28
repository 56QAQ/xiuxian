class_name SpellBeam
extends Node3D
## 光束法诀：从施法者手中持续射出，沿射线周期性造成伤害。
## 表现：绕轴朝向镜头的滚动噪声光束（金光/火焰/水龙/雷光）+ 外层光晕 + 两端光斑 + 终点粒子与灯光。

var caster: Node3D
var def: Dictionary
var level: int = 0
var length: float = 30.0
var width: float = 0.6
var duration: float = 2.0
var tick: float = 0.2
var _t: float = 0.0
var _tick_t: float = 0.0
var _vis: Dictionary = {}
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
	b._vis = VfxSpells.beam_visual(b, VfxLib.spell_elem(spell_def), b._color, b.width)
	if caster_body.has_method("cast_origin"):
		var o: Vector3 = caster_body.call("cast_origin")
		var a: Vector3 = caster_body.call("aim_point")
		FX.cast_release(o, (a - o).normalized(), spell_def)
	if caster_body.has_method("begin_channel"):
		caster_body.call("begin_channel", b.duration)
	return b


func _physics_process(delta: float) -> void:
	_t += delta
	var c := CombatUtil.combatant_of(caster)
	if caster == null or not is_instance_valid(caster) or c == null or not c.alive or _t > duration:
		VfxSpells.beam_end(_vis)
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
	VfxSpells.beam_update(_vis, from, to, not hit.is_empty(), _t)
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
