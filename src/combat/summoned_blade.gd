class_name SummonedBlade
extends Node3D
## 御剑术：环绕施法者的飞剑，定时斩向锁定/最近的敌人。

var caster: Node3D
var def: Dictionary
var level: int = 0
var index: int = 0
var total: int = 3
var life: float = 12.0
var orbit: float = 1.6
var fire_rate: float = 1.0
var speed: float = 50.0
var _cd: float = 0.0
var _t: float = 0.0
var _color: Color


static func spawn(caster_body: Node3D, spell_def: Dictionary, lv: int, i: int, n: int) -> SummonedBlade:
	var s := SummonedBlade.new()
	s.caster = caster_body
	s.def = spell_def
	s.level = lv
	s.index = i
	s.total = n
	var p: Dictionary = spell_def.get("params", {})
	s.life = float(p.get("duration", 12.0))
	s.orbit = float(p.get("orbit", 1.6))
	s.fire_rate = float(p.get("fire_rate", 1.0))
	s.speed = float(p.get("speed", 50.0))
	s._cd = 0.3 + 0.25 * i
	s._color = SpellRuntime.color_of(spell_def)
	FX.root().add_child(s)
	s.global_position = caster_body.global_position + Vector3.UP * 1.5
	var w := WeaponBuilder.build({"kind": "sword", "length": 28, "blade": s._color.lightened(0.5).to_html(), "guard": "#e0c060", "glow": spell_def.get("element", "metal")})
	s.add_child(w)
	var glow := CPUParticles3D.new()
	glow.amount = 10
	glow.lifetime = 0.35
	glow.mesh = FX.cube_mesh()
	glow.material_override = FX.glow_mat(s._color)
	glow.scale_amount_min = 0.03
	glow.scale_amount_max = 0.07
	glow.gravity = Vector3.ZERO
	glow.local_coords = false
	glow.color_ramp = FX._fade_gradient(s._color)
	s.add_child(glow)
	return s


func _physics_process(delta: float) -> void:
	_t += delta
	if caster == null or not is_instance_valid(caster) or _t > life or not CombatUtil.combatant_of(caster).alive:
		FX.burst(global_position, _color, 8, 3.0, 0.06, 0.4)
		queue_free()
		return
	var ang := _t * 2.4 + TAU * index / maxf(total, 1)
	var home := caster.global_position + Vector3(cos(ang) * orbit, 1.7 + sin(_t * 3.0 + index) * 0.15, sin(ang) * orbit)
	global_position = global_position.lerp(home, clampf(12.0 * delta, 0.0, 1.0))
	var target: Node3D = caster.get("lock_target")
	if target == null or not is_instance_valid(target) or not CombatUtil.can_damage(caster, target):
		target = CombatUtil.nearest_hostile(caster, 30.0)
	if target != null:
		look_at(target.global_position + Vector3.UP, Vector3.UP)
	else:
		rotation = Vector3(-PI / 2.0, ang, 0)
	_cd -= delta
	if _cd <= 0.0 and target != null:
		_cd = 1.0 / maxf(fire_rate, 0.1)
		var info := SpellRuntime.base_info(caster, def, level)
		Projectile.spawn({
			"owner": caster, "pos": global_position, "dir": (target.global_position + Vector3.UP - global_position).normalized(),
			"speed": speed, "size": 0.22, "range": 40.0, "homing": 0.5, "target": target, "shape": "blade",
			"info": info, "element": def.get("element", "metal"),
		})
		Audio.play_at("wind_blade", global_position, -8.0)
