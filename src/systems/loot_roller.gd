class_name LootRoller
## 掉落表抽取（data/loot_tables.json）。气运与寻宝加成提高高品阶物品权重与法器品阶。


static func roll(table_id: String, rng: RandomNumberGenerator, luck: float = 0.0, loot_bonus: float = 0.0) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	var t: Dictionary = DB.loot_tables.get(table_id, {})
	if t.is_empty():
		push_warning("LootRoller: 未知掉落表 %s" % table_id)
		return out
	var rolls: Array = t.get("rolls", [1, 1])
	var n := rng.randi_range(int(rolls[0]), int(rolls[1]))
	var entries: Array = t.get("entries", [])
	var weights: Array[float] = []
	var total := 0.0
	for e in entries:
		var g := int(DB.item(str(e["item"])).get("grade", 0))
		var w := float(e.get("w", 1.0)) * (1.0 + (loot_bonus + luck * 0.02) * g)
		weights.append(w)
		total += w
	for i in n:
		var r := rng.randf() * total
		for j in entries.size():
			r -= weights[j]
			if r <= 0.0:
				var e: Dictionary = entries[j]
				var nr: Array = e.get("n", [1, 1])
				var it := ItemInstance.create(str(e["item"]), rng.randi_range(int(nr[0]), int(nr[1])))
				if e.has("grade"):
					it.grade = int(e["grade"])
				_maybe_upgrade(it, rng, luck, loot_bonus)
				out.append(it)
				break
	return out


## 法器有几率品阶提升并附带随机词条
static func _maybe_upgrade(it: ItemInstance, rng: RandomNumberGenerator, luck: float, loot_bonus: float) -> void:
	var t := it.type()
	if t not in ["weapon", "armor", "accessory"]:
		return
	var g := it.get_grade()
	var chance := 0.12 + loot_bonus + luck * 0.01
	while g < Grade.MAX and rng.randf() < chance:
		g += 1
		chance *= 0.35
	if g != int(it.def().get("grade", 0)):
		it.grade = g
	var n_aff := clampi(g - 1 + (1 if rng.randf() < 0.3 else 0), 0, 4)
	const POOL := ["attack_pct", "crit_rate", "crit_dmg", "max_hp_pct", "max_shield_pct", "qi_regen_pct", "defense_pct", "move_speed_pct", "spell_mult", "dmg_reduction"]
	const RANGE := {"attack_pct": 0.04, "crit_rate": 0.02, "crit_dmg": 0.08, "max_hp_pct": 0.05, "max_shield_pct": 0.08, "qi_regen_pct": 0.06, "defense_pct": 0.05, "move_speed_pct": 0.02, "spell_mult": 0.04, "dmg_reduction": 0.02}
	for i in n_aff:
		var k: String = POOL[rng.randi() % POOL.size()]
		var v := float(RANGE[k]) * rng.randf_range(0.6, 1.4) * (1.0 + g * 0.35)
		it.affixes.append({"k": k, "v": snappedf(v, 0.001)})
