class_name Stats
## 属性表工具。属性以 Dictionary[String, float] 表示。
##
## 修正值（modifier）约定：
##   "attack": 5        → 平加
##   "attack_pct": 0.1  → 百分比加成（同一属性的所有 _pct 相加后乘算）
## 最终值 = (基础 + Σ平加) × (1 + Σ百分比)
## 比率类属性（暴击率等）直接平加即可。

const DEFAULTS := {
	# 资源
	"max_hp": 300.0, "max_shield": 80.0, "max_qi": 100.0,
	"hp_regen": 0.0, "shield_regen": 22.0, "qi_regen": 26.0,
	"shield_delay": 3.0,
	# 攻防
	"attack": 30.0, "defense": 15.0,
	"crit_rate": 0.05, "crit_dmg": 1.5,
	"dmg_reduction": 0.0,
	"poise": 100.0,
	"melee_mult": 1.0, "bolt_mult": 1.0, "spell_mult": 1.0,
	"cdr": 0.0,
	# 五行增伤
	"dmg_metal": 0.0, "dmg_wood": 0.0, "dmg_water": 0.0, "dmg_fire": 0.0, "dmg_earth": 0.0,
	# 状态强度
	"bleed_power": 1.0, "poison_power": 1.0, "bind_power": 1.0, "burn_power": 1.0, "stagger_power": 1.0,
	"status_chance": 0.0, "status_resist": 0.0,
	# 机动
	"move_speed": 6.5, "boost_speed": 15.0, "boost_cost": 1.0, "qb_cost": 1.0, "flight_cost": 1.0,
	# 武器专精
	"sword_dmg": 0.0, "saber_dmg": 0.0, "spear_dmg": 0.0, "fist_dmg": 0.0,
	# 修炼与探索
	"cult_speed": 1.0, "insight_gain": 1.0, "breakthrough": 0.0,
	"search_speed": 1.0, "luck": 0.0, "lock_range": 60.0,
	"heal_mult": 1.0, "pill_eff": 1.0, "pill_tox": 1.0, "favor_gain": 1.0, "loot_bonus": 0.0,
	# 生产
	"alchemy": 0.0, "forging": 0.0, "talisman": 0.0, "formation": 0.0, "herbalism": 0.0,
}

const LABELS := {
	"max_hp": "生命上限", "max_shield": "护体上限", "max_qi": "灵力上限",
	"hp_regen": "生命回复", "shield_regen": "护体回复", "qi_regen": "灵力回复",
	"shield_delay": "护体回复延迟",
	"attack": "攻击", "defense": "防御", "crit_rate": "暴击率", "crit_dmg": "暴击伤害",
	"dmg_reduction": "伤害减免", "poise": "韧性",
	"melee_mult": "近战伤害", "bolt_mult": "灵气弹伤害", "spell_mult": "法诀伤害", "cdr": "冷却缩减",
	"dmg_metal": "金系伤害", "dmg_wood": "木系伤害", "dmg_water": "水系伤害",
	"dmg_fire": "火系伤害", "dmg_earth": "土系伤害",
	"bleed_power": "流血强度", "poison_power": "中毒强度", "bind_power": "束缚强度",
	"burn_power": "灼烧强度", "stagger_power": "震慑强度",
	"status_chance": "状态触发", "status_resist": "状态抗性",
	"move_speed": "移动速度", "boost_speed": "疾行速度", "boost_cost": "疾行消耗",
	"qb_cost": "瞬步消耗", "flight_cost": "飞行消耗",
	"sword_dmg": "剑法伤害", "saber_dmg": "刀法伤害", "spear_dmg": "枪法伤害", "fist_dmg": "拳法伤害",
	"cult_speed": "修炼速度", "insight_gain": "感悟获取", "breakthrough": "突破成功率",
	"search_speed": "搜索速度", "luck": "气运", "lock_range": "锁定距离",
	"heal_mult": "治疗效果", "pill_eff": "丹药药效", "pill_tox": "丹毒累积", "favor_gain": "好感获取",
	"loot_bonus": "寻宝品阶",
	"alchemy": "炼丹", "forging": "炼器", "talisman": "制符", "formation": "阵法", "herbalism": "灵植",
}

## 以百分比展示的属性
const PERCENT_KEYS := [
	"crit_rate", "crit_dmg", "dmg_reduction", "melee_mult", "bolt_mult", "spell_mult", "cdr",
	"dmg_metal", "dmg_wood", "dmg_water", "dmg_fire", "dmg_earth",
	"bleed_power", "poison_power", "bind_power", "burn_power", "stagger_power",
	"status_chance", "status_resist", "boost_cost", "qb_cost", "flight_cost",
	"sword_dmg", "saber_dmg", "spear_dmg", "fist_dmg",
	"cult_speed", "insight_gain", "breakthrough", "search_speed", "heal_mult", "pill_eff", "pill_tox",
	"favor_gain", "loot_bonus",
]


## 合并修正值：把 src 中的每一项累加到 acc（acc 为修正累加器）
static func add_mods(acc: Dictionary, src: Dictionary, scale: float = 1.0) -> void:
	for k in src:
		acc[k] = float(acc.get(k, 0.0)) + float(src[k]) * scale


## 根据基础属性与累计修正值求最终属性
static func resolve(base: Dictionary, mods: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate()
	for k in base:
		out[k] = float(base[k])
	var pct := {}
	for k in mods:
		var key: String = k
		if key.ends_with("_pct"):
			pct[key.substr(0, key.length() - 4)] = float(pct.get(key.substr(0, key.length() - 4), 0.0)) + float(mods[k])
		else:
			out[key] = float(out.get(key, 0.0)) + float(mods[k])
	for k in pct:
		out[k] = float(out.get(k, 0.0)) * (1.0 + float(pct[k]))
	# 上下限
	out["crit_rate"] = clampf(out["crit_rate"], 0.0, 1.0)
	out["dmg_reduction"] = clampf(out["dmg_reduction"], 0.0, 0.8)
	out["cdr"] = clampf(out["cdr"], 0.0, 0.6)
	out["status_resist"] = clampf(out["status_resist"], 0.0, 0.8)
	out["boost_cost"] = maxf(out["boost_cost"], 0.2)
	out["qb_cost"] = maxf(out["qb_cost"], 0.2)
	out["flight_cost"] = maxf(out["flight_cost"], 0.2)
	return out


static func label(key: String) -> String:
	var k := key.trim_suffix("_pct")
	return LABELS.get(k, k)


## 把一条修正值格式化为可读文本，如 “攻击 +12%”
static func format_mod(key: String, value: float) -> String:
	var sgn := "+" if value >= 0.0 else ""
	if key.ends_with("_pct") or PERCENT_KEYS.has(key):
		return "%s %s%s%%" % [label(key), sgn, _num(value * 100.0)]
	return "%s %s%s" % [label(key), sgn, _num(value)]


static func format_value(key: String, value: float) -> String:
	if PERCENT_KEYS.has(key):
		return "%s%%" % _num(value * 100.0)
	return _num(value)


static func _num(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return str(int(roundf(v)))
	return "%.1f" % v
