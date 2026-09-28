class_name BuildCalc
## 构筑计算：把 境界 + 先天属性 + 灵根 + 天赋 + 功法 + 法器 汇总为最终属性。
## NPC 同样使用 PlayerData 表示，因此与玩家共用这套计算。

## 灵根类型：灵根数量 -> 信息
const ROOT_TYPES := {
	1: {"name": "天灵根", "cult": 2.0, "cost": 6},
	2: {"name": "双灵根", "cult": 1.5, "cost": 3},
	3: {"name": "三灵根", "cult": 1.1, "cost": 1},
	4: {"name": "四灵根", "cult": 0.8, "cost": 0},
	5: {"name": "五行杂灵根", "cult": 0.6, "cost": -2},
}

## 每 1.0 灵根占比提供的被动（天灵根另乘 1.25）
const ROOT_PASSIVES := {
	"metal": {"crit_rate": 0.12, "crit_dmg": 0.4, "bleed_power": 0.6},
	"wood": {"heal_mult": 0.3, "poison_power": 0.6, "max_hp_pct": 0.1},
	"water": {"qi_regen_pct": 0.45, "max_qi_pct": 0.2, "bind_power": 0.6},
	"fire": {"attack_pct": 0.3, "burn_power": 0.6},
	"earth": {"shield_regen_pct": 0.6, "max_shield_pct": 0.5, "dmg_reduction": 0.12, "stagger_power": 0.6},
}

## 先天属性（相对基准 5）每点提供
const ATTR_EFFECTS := {
	"con": {"max_hp_pct": 0.06, "defense_pct": 0.03, "poise_pct": 0.04, "breakthrough": 0.01},
	"int": {"cult_speed": 0.06, "insight_gain": 0.08},
	"spi": {"max_qi_pct": 0.05, "spell_mult": 0.03, "search_speed": 0.06, "lock_range": 3.0},
	"agi": {"move_speed_pct": 0.02, "boost_cost": -0.03, "qb_cost": -0.03, "crit_rate": 0.005},
	"luk": {"luck": 1.0, "loot_bonus": 0.02},
}


static func root_type(p: PlayerData) -> Dictionary:
	return ROOT_TYPES.get(clampi(p.root_count(), 1, 5), ROOT_TYPES[5])


## 某元素法术/攻击的威力倍率
static func elem_power(p: PlayerData, e: String) -> float:
	if not Elem.is_valid(e):
		return 1.0
	var pct := p.root_pct(e)
	var v := 0.6 + 0.8 * pct
	var n := p.root_count()
	if n == 1 and pct >= 0.99:
		v += 0.25
	elif n == 5:
		v = maxf(v, 0.9)
	return v


## 已装备法诀中的相生对数（多灵根构筑的核心加成）
static func resonance_pairs(p: PlayerData) -> int:
	var elems: Array[String] = []
	for sid in p.spell_slots:
		if sid == "":
			continue
		var e := str(DB.spell(sid).get("element", ""))
		if Elem.is_valid(e) and not elems.has(e):
			elems.append(e)
	var pairs := 0
	for i in elems.size():
		for j in range(i + 1, elems.size()):
			if Elem.generates_pair(elems[i], elems[j]):
				pairs += 1
	return pairs


static func realm_base(realm_idx: int, stage: int) -> Dictionary:
	var r := DB.realm(realm_idx)
	var base: Dictionary = r.get("base", {}).duplicate()
	var g := 1.0 + float(r.get("growth", 0.08)) * stage
	for k in ["max_hp", "max_shield", "max_qi", "attack", "defense", "poise"]:
		if base.has(k):
			base[k] = float(base[k]) * g
	return base


static func compute(p: PlayerData) -> Dictionary:
	var base := realm_base(p.realm, p.stage)
	var mods := collect_mods(p)
	var st := Stats.resolve(base, mods)
	# 派生：木灵根生命回复按最大生命比例
	st["hp_regen"] = float(st["hp_regen"]) + float(st["max_hp"]) * 0.006 * p.root_pct(Elem.WOOD)
	# 灵根修炼倍率
	st["cult_speed"] = float(st["cult_speed"]) * float(root_type(p)["cult"])
	return st


static func collect_mods(p: PlayerData) -> Dictionary:
	var mods := {}
	# 先天属性
	for a in ATTR_EFFECTS:
		var delta := float(p.attributes.get(a, 5)) - 5.0
		if delta != 0.0:
			Stats.add_mods(mods, ATTR_EFFECTS[a], delta)
	# 灵根被动
	var purity := 1.25 if p.root_count() == 1 else 1.0
	for e in ROOT_PASSIVES:
		var pct := p.root_pct(e)
		if pct > 0.0:
			Stats.add_mods(mods, ROOT_PASSIVES[e], pct * purity)
	# 五行杂灵根：五行轮转
	if p.root_count() == 5:
		Stats.add_mods(mods, {"spell_mult": 0.1, "cdr": 0.08})
	# 相生共鸣
	var pairs := resonance_pairs(p)
	if pairs > 0:
		var per := 0.16 if p.root_count() == 5 else 0.08
		Stats.add_mods(mods, {"spell_mult": per * pairs, "status_chance": 0.05 * pairs})
	# 天赋
	for tid in p.talents:
		Stats.add_mods(mods, DB.talent(tid).get("stats", {}))
	# 出身
	Stats.add_mods(mods, DB.backgrounds.get(p.background, {}).get("stats", {}))
	# 功法
	var tech_ids: Array = [p.main_technique] + p.aux_techniques
	for i in tech_ids.size():
		var tid: String = tech_ids[i]
		if tid == "":
			continue
		var t := DB.technique(tid)
		if t.is_empty():
			continue
		var lv := p.technique_level(tid)
		var scale := 1.0 + 0.25 * lv
		if i > 0:
			scale *= 0.8  # 辅修效果打折
		Stats.add_mods(mods, t.get("stats", {}), scale)
		if i == 0 and t.has("cult_mult"):
			Stats.add_mods(mods, {"cult_speed": float(t["cult_mult"]) - 1.0 + 0.05 * lv})
	# 法器
	for slot in p.equipment:
		var it: ItemInstance = p.equipment[slot]
		if it != null:
			Stats.add_mods(mods, it.equip_mods())
	# 境界质变
	var r := DB.realm(p.realm)
	Stats.add_mods(mods, r.get("perk_stats", {}))
	# 受伤
	if p.injury_days > 0.0:
		Stats.add_mods(mods, {"max_hp_pct": -0.2, "cult_speed": -0.3, "attack_pct": -0.1})
	# 丹毒
	if p.pill_toxicity > 50.0:
		Stats.add_mods(mods, {"cult_speed": -0.15, "qi_regen_pct": -0.1})
	return mods


## 境界质变解锁（数据中的 perks 汇总：当前境界及以下）
static func perks(p: PlayerData) -> Array[String]:
	var out: Array[String] = []
	for i in range(0, p.realm + 1):
		for k in DB.realm(i).get("perks", []):
			if not out.has(k):
				out.append(k)
	return out


static func has_perk(p: PlayerData, perk: String) -> bool:
	return perks(p).has(perk)


static func spell_slot_count(p: PlayerData) -> int:
	return 5 if has_perk(p, "spell_slot_5") else 4
