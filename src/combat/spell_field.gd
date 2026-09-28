class_name SpellField
extends Node3D
## 持续领域（青藤缠等）：周期性对范围内敌人造成伤害、附加状态并减速。
## 表现：贴地动画领域（藤蔓/冰域/流沙/火海）+ 清晰的范围边缘 + 元素粒子（见 VfxSpells.field_visual）。

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
var _vis: Array[Node] = []


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
	_vis = VfxSpells.field_visual(self, radius, VfxLib.spell_elem(def), _color)


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
		VfxSpells.field_fade(_vis, 0.5)
		var tw := create_tween()
		tw.tween_interval(1.4)
		tw.tween_callback(queue_free)
