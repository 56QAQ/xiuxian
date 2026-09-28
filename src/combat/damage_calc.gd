class_name DamageCalc
## 伤害公式。
##
## info 字段：
##   source: Combatant       攻击者（可空）
##   kind: "melee"|"bolt"|"spell"|"dot"|"env"
##   mult: float             攻击力倍率（技能系数）
##   flat: float             直接给定的原始伤害（dot/env），忽略 mult
##   element: String         五行
##   weapon: String          兵器类型（专精加成）
##   crit_bonus: float       额外暴击率
##   status: {id, stacks, chance}
##   poise, knock, launch, dir: Vector3, point: Vector3
##   bypass_shield: bool     无视护体（流血/中毒）
##
## 公式：原始 = 攻击 × 系数 × 类别倍率 × 兵器专精 × 五行威力 × (1+五行增伤) × 相克
##       × 暴击 × 境界压制 × 防御减伤 × (1-伤害减免)

const REALM_SUPPRESS := 1.3


static func compute(src: Combatant, dst: Combatant, info: Dictionary) -> Dictionary:
	var kind := str(info.get("kind", "melee"))
	var element := str(info.get("element", Elem.NONE))
	var crit := false
	var dmg: float
	if info.has("flat"):
		dmg = float(info["flat"])
		if kind == "dot":
			# 持续伤害只受伤害减免影响
			return {"damage": dmg * (1.0 - dst.stat("dmg_reduction") * 0.5), "crit": false}
	else:
		var atk := src.stat("attack") if src != null else 30.0
		dmg = atk * float(info.get("mult", 1.0))
		if src != null:
			match kind:
				"melee":
					dmg *= src.stat("melee_mult")
					var w := str(info.get("weapon", ""))
					if w != "":
						dmg *= 1.0 + src.stat(w + "_dmg")
				"bolt":
					dmg *= src.stat("bolt_mult")
				"spell":
					dmg *= src.stat("spell_mult")
			if Elem.is_valid(element):
				if src.pd != null:
					dmg *= BuildCalc.elem_power(src.pd, element)
				dmg *= 1.0 + src.stat("dmg_" + element)
			var cr := src.stat("crit_rate") + float(info.get("crit_bonus", 0.0))
			if randf() < cr:
				crit = true
				dmg *= src.stat("crit_dmg")
	if Elem.is_valid(element):
		dmg *= Elem.counter_mult(element, dst.element)
	# 境界压制
	if src != null:
		var diff := (src.realm - dst.realm) + (src.stage - dst.stage) * 0.03
		dmg *= clampf(pow(REALM_SUPPRESS, diff), 0.2, 5.0)
	# 防御
	var k := 50.0 * pow(2.5, dst.realm)
	var def := maxf(dst.stat("defense"), 0.0)
	dmg *= 1.0 - def / (def + k)
	dmg *= 1.0 - dst.stat("dmg_reduction")
	dmg *= randf_range(0.95, 1.05)
	return {"damage": maxf(dmg, 1.0), "crit": crit}
