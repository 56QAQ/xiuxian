extends Node
## 内容数据测试：属性键合法性、法诀参数、妖兽模型、掉落表、突破丹、各类交叉引用与内容规模。

var runner: Node

const ICONS := ["sword", "saber", "spear", "fist", "robe", "armor", "pendant", "ring", "pill", "herb", "flower", "fruit",
	"ore", "crystal", "core", "stone", "scroll", "talisman", "bag", "seed", "hide", "bone", "key", "disc"]
const ITEM_TYPES := ["weapon", "armor", "accessory", "pill", "material", "currency", "manual", "talisman", "treasure",
	"bag", "formation", "seed", "key", "misc"]
const USE_EFFECTS := ["heal", "qi", "shield", "buff", "cast", "exp", "breakthrough", "heal_injury", "detox", "attribute"]
const WEAPON_KINDS := ["sword", "saber", "spear", "fist"]
const ELEMENTS := ["metal", "wood", "water", "fire", "earth", "none"]
## 每种法诀类型必须提供的参数
const SPELL_PARAMS := {
	"projectile": ["count", "speed", "range"],
	"nova": ["radius"],
	"strike": ["radius", "delay", "range"],
	"dash": ["distance", "speed", "width"],
	"shield": ["amount"],
	"buff": ["status", "duration"],
	"heal": ["amount"],
	"field": ["radius", "duration", "tick", "range"],
	"summon": ["count", "duration", "fire_rate"],
	"beam": ["length", "width", "duration", "tick"],
}
const BEAST_MODELS := ["wolf", "fox", "boar", "bear", "golem", "snake", "crane", "spider"]
const BEAST_ATTACKS := ["bite", "pounce", "charge", "slam", "spit", "howl"]
const CONTAINER_TYPES := ["herb_patch", "chest", "ore_vein", "corpse", "altar", "cauldron", "bookshelf"]
const PROFESSIONS := ["alchemy", "forging", "talisman", "formation", "herbalism"]
const ATTRS := ["con", "int", "spi", "agi", "luk"]
const FACTIONS_EXTRA := ["none", "xuesha", "robber"]


func _ok(c: bool, m: String) -> void:
	runner.check(c, m)


static func _stat_key_ok(k: String) -> bool:
	if Stats.DEFAULTS.has(k):
		return true
	return k.ends_with("_pct") and Stats.DEFAULTS.has(k.trim_suffix("_pct"))


func _check_stats(d: Variant, where: String, bad: Array[String]) -> void:
	if not d is Dictionary:
		bad.append("%s 的属性字典不是字典" % where)
		return
	for k in d:
		if not _stat_key_ok(str(k)):
			bad.append("%s 使用了非法属性键 %s" % [where, k])
		elif not (d[k] is float or d[k] is int):
			bad.append("%s 属性 %s 不是数值" % [where, k])


func test_stat_keys_valid() -> void:
	var bad: Array[String] = []
	for iid in DB.items:
		var it: Dictionary = DB.items[iid]
		if it.has("weapon"):
			_check_stats(it["weapon"].get("stats", {}), "物品 %s(weapon)" % iid, bad)
		if it.has("equip"):
			_check_stats(it["equip"].get("stats", {}), "物品 %s(equip)" % iid, bad)
	for tid in DB.techniques:
		_check_stats(DB.techniques[tid].get("stats", {}), "功法 " + str(tid), bad)
	for tid in DB.talents:
		_check_stats(DB.talents[tid].get("stats", {}), "天赋 " + str(tid), bad)
	for bid in DB.backgrounds:
		_check_stats(DB.backgrounds[bid].get("stats", {}), "出身 " + str(bid), bad)
	for sid in DB.statuses:
		_check_stats(DB.statuses[sid].get("mods_per_stack", {}), "状态 " + str(sid), bad)
	for i in DB.realm_count():
		_check_stats(DB.realm(i).get("perk_stats", {}), "境界 %d" % i, bad)
	for eid in DB.enemies:
		var e: Dictionary = DB.enemies[eid]
		if e.has("mult"):
			_check_stats(e["mult"], "敌人 %s(mult)" % eid, bad)
	_ok(bad.is_empty(), "属性键错误:\n" + "\n".join(bad))


func test_items_schema() -> void:
	var bad: Array[String] = []
	var taught_t := {}
	var taught_s := {}
	for iid in DB.items:
		var it: Dictionary = DB.items[iid]
		var where := "物品 " + str(iid)
		for f in ["name", "type", "grade", "size", "stack", "value", "icon", "desc"]:
			if not it.has(f):
				bad.append("%s 缺少字段 %s" % [where, f])
		if not ITEM_TYPES.has(str(it.get("type", ""))):
			bad.append("%s 类型非法 %s" % [where, it.get("type")])
		if not ICONS.has(str(it.get("icon", ""))):
			bad.append("%s 图标非法 %s" % [where, it.get("icon")])
		var g := int(it.get("grade", -1))
		if g < 0 or g > Grade.MAX:
			bad.append("%s 品阶非法" % where)
		var sz: Array = it.get("size", [])
		if sz.size() != 2 or int(sz[0]) < 1 or int(sz[1]) < 1 or int(sz[0]) > 4 or int(sz[1]) > 6:
			bad.append("%s 尺寸非法 %s" % [where, str(sz)])
		if int(it.get("stack", 0)) < 1:
			bad.append("%s 堆叠数非法" % where)
		if it.has("element") and not ELEMENTS.has(str(it["element"])):
			bad.append("%s 五行非法" % where)
		var t := str(it.get("type", ""))
		if t == "weapon":
			var w: Dictionary = it.get("weapon", {})
			if not WEAPON_KINDS.has(str(w.get("kind", ""))):
				bad.append("%s 兵器类型非法" % where)
			if float(w.get("attack", 0)) <= 0.0:
				bad.append("%s 攻击力非正" % where)
			var vis: Dictionary = w.get("visual", {})
			if str(vis.get("kind", "")) != str(w.get("kind", "")):
				bad.append("%s visual.kind 与兵器类型不一致" % where)
			if vis.has("glow") and not Elem.is_valid(str(vis["glow"])):
				bad.append("%s visual.glow 非法" % where)
		if t == "armor":
			var vis2: Dictionary = it.get("equip", {}).get("visual", {})
			if not ["robe", "martial", "armor"].has(str(vis2.get("outfit", ""))):
				bad.append("%s 法衣 outfit 非法" % where)
			if (vis2.get("outfit_colors", []) as Array).size() != 3:
				bad.append("%s 法衣 outfit_colors 需 3 色" % where)
		if (t == "armor" or t == "accessory") and not it.has("equip"):
			bad.append("%s 缺少 equip" % where)
		if t == "bag":
			var b: Dictionary = it.get("bag", {})
			if int(b.get("w", 0)) < 1 or int(b.get("h", 0)) < 1:
				bad.append("%s 储物袋容量非法" % where)
		if it.has("use"):
			var u: Dictionary = it["use"]
			var eff := str(u.get("effect", ""))
			if not USE_EFFECTS.has(eff):
				bad.append("%s 使用效果非法 %s" % [where, eff])
			if not u.has("text"):
				bad.append("%s use 缺少 text" % where)
			if eff == "buff" and not DB.statuses.has(str(u.get("status", ""))):
				bad.append("%s buff 状态不存在 %s" % [where, u.get("status")])
			if eff == "attribute" and not ATTRS.has(str(u.get("attr", ""))):
				bad.append("%s attribute 属性非法" % where)
			if (eff == "heal" or eff == "qi" or eff == "shield") and float(u.get("amount", 0)) <= 0.0:
				bad.append("%s %s 数值非正" % [where, eff])
		if it.has("teaches"):
			var tt: Dictionary = it["teaches"]
			if tt.has("technique"):
				taught_t[tt["technique"]] = true
			if tt.has("spell"):
				taught_s[tt["spell"]] = true
		if it.has("grow") and not DB.items.has(str(it["grow"].get("item", ""))):
			bad.append("%s 灵种产出不存在" % where)
		if it.has("refine") and float(it["refine"].get("exp", 0)) <= 0.0:
			bad.append("%s 炼化修为非正" % where)
	for tid in DB.techniques:
		if not taught_t.has(tid):
			bad.append("功法 %s 没有对应玉简" % tid)
	for sid in DB.spells:
		if not taught_s.has(sid):
			bad.append("法诀 %s 没有对应玉简" % sid)
	_ok(bad.is_empty(), "物品数据错误:\n" + "\n".join(bad))


func test_spell_params() -> void:
	var bad: Array[String] = []
	var kinds_seen := {}
	var per_elem := {}
	for sid in DB.spells:
		var sp: Dictionary = DB.spells[sid]
		var kind := str(sp.get("kind", ""))
		kinds_seen[kind] = true
		var e := str(sp.get("element", ""))
		per_elem[e] = int(per_elem.get(e, 0)) + 1
		if not ELEMENTS.has(e):
			bad.append("法诀 %s 五行非法" % sid)
		if not SPELL_PARAMS.has(kind):
			bad.append("法诀 %s 类型非法 %s" % [sid, kind])
			continue
		var params: Dictionary = sp.get("params", {})
		for p in SPELL_PARAMS[kind]:
			if not params.has(p):
				bad.append("法诀 %s(%s) 缺少参数 %s" % [sid, kind, p])
		if params.has("status") and not DB.statuses.has(str(params["status"])):
			bad.append("法诀 %s 参数状态不存在 %s" % [sid, params["status"]])
		for f in ["qi", "cd", "cast_time", "power", "grade"]:
			if not sp.has(f):
				bad.append("法诀 %s 缺少字段 %s" % [sid, f])
		if float(sp.get("qi", 0)) <= 0.0 or float(sp.get("cd", 0)) <= 0.0:
			bad.append("法诀 %s 灵力或冷却非正" % sid)
		if not AnimLib.has_clip(str(sp.get("anim", ""))):
			bad.append("法诀 %s 动作不存在" % sid)
	for k in SPELL_PARAMS:
		if not kinds_seen.has(k):
			bad.append("没有任何 %s 类型的法诀" % k)
	for e in Elem.LIST:
		if int(per_elem.get(e, 0)) < 6:
			bad.append("%s 系法诀不足 6 个" % e)
	_ok(bad.is_empty(), "法诀数据错误:\n" + "\n".join(bad))


func test_techniques() -> void:
	var bad: Array[String] = []
	for tid in DB.techniques:
		var t: Dictionary = DB.techniques[tid]
		var slot := str(t.get("slot", ""))
		if slot != "main" and slot != "aux":
			bad.append("功法 %s 槽位非法" % tid)
		if slot == "main":
			if float(t.get("cult_mult", 0)) < 1.0:
				bad.append("功法 %s 修炼倍率过低" % tid)
			var mr := int(t.get("max_realm", -1))
			if mr < 0 or mr >= DB.realm_count():
				bad.append("功法 %s max_realm 越界" % tid)
		var req: Dictionary = t.get("req", {})
		for e in req.get("root", {}):
			if not Elem.is_valid(str(e)):
				bad.append("功法 %s 灵根要求非法 %s" % [tid, e])
		if req.has("realm") and int(req["realm"]) >= DB.realm_count():
			bad.append("功法 %s 境界要求越界" % tid)
	_ok(bad.is_empty(), "功法数据错误:\n" + "\n".join(bad))


func test_enemy_models_and_refs() -> void:
	var bad: Array[String] = []
	var beasts := 0
	var cultivators := 0
	for eid in DB.enemies:
		var e: Dictionary = DB.enemies[eid]
		var kind := str(e.get("kind", ""))
		if int(e.get("realm", -1)) < 0 or int(e.get("realm", -1)) >= DB.realm_count():
			bad.append("敌人 %s 境界越界" % eid)
		if kind == "beast":
			beasts += 1
			if not BEAST_MODELS.has(str(e.get("model", ""))):
				bad.append("妖兽 %s 使用了未制作的模型 %s" % [eid, e.get("model")])
			for a in e.get("attacks", []):
				if not BEAST_ATTACKS.has(str(a.get("name", ""))):
					bad.append("妖兽 %s 招式名非法 %s" % [eid, a.get("name")])
				if a.has("status") and not DB.statuses.has(str(a["status"].get("id", ""))):
					bad.append("妖兽 %s 招式状态不存在" % eid)
				if a.has("buff") and not DB.statuses.has(str(a["buff"].get("status", ""))):
					bad.append("妖兽 %s 嚎叫状态不存在" % eid)
			for d in e.get("drops", []):
				if not DB.items.has(str(d.get("item", ""))):
					bad.append("妖兽 %s 掉落不存在 %s" % [eid, d.get("item")])
			if bool(e.get("boss", false)) and (float(e.get("size", 1.0)) < 1.8 or float(e.get("size", 1.0)) > 2.5):
				bad.append("妖王 %s 体型应在 1.8~2.5" % eid)
		elif kind == "cultivator":
			cultivators += 1
			var fac := str(e.get("faction", ""))
			if not DB.sects.has(fac) and not FACTIONS_EXTRA.has(fac):
				bad.append("修士 %s 阵营非法 %s" % [eid, fac])
			var st: Array = e.get("stage", [])
			if st.size() != 2 or int(st[0]) > int(st[1]):
				bad.append("修士 %s 小境界范围非法" % eid)
			for w in e.get("weapons", []):
				if str(DB.item(str(w)).get("type", "")) != "weapon":
					bad.append("修士 %s 兵器非法 %s" % [eid, w])
			if e.has("technique") and not DB.techniques.has(str(e["technique"])):
				bad.append("修士 %s 功法不存在" % eid)
			if e.has("armor") and str(DB.item(str(e["armor"])).get("type", "")) != "armor":
				bad.append("修士 %s 法衣非法" % eid)
			if e.has("loot") and not DB.loot_tables.has(str(e["loot"])):
				bad.append("修士 %s 掉落表不存在" % eid)
		else:
			bad.append("敌人 %s 类型非法" % eid)
	_ok(beasts >= 20, "妖兽种类不足 20（%d）" % beasts)
	_ok(cultivators >= 8, "修士模板不足 8（%d）" % cultivators)
	_ok(bad.is_empty(), "敌人数据错误:\n" + "\n".join(bad))


func test_loot_tables() -> void:
	var bad: Array[String] = []
	for lid in DB.loot_tables:
		var l: Dictionary = DB.loot_tables[lid]
		var entries: Array = l.get("entries", [])
		if entries.is_empty():
			bad.append("掉落表 %s 为空" % lid)
		var rolls: Array = l.get("rolls", [])
		if rolls.size() != 2 or int(rolls[0]) < 1 or int(rolls[0]) > int(rolls[1]):
			bad.append("掉落表 %s rolls 非法" % lid)
		for en in entries:
			if float(en.get("w", 0)) <= 0.0:
				bad.append("掉落表 %s 条目 %s 权重非正" % [lid, en.get("item")])
			if en.has("n"):
				var n: Array = en["n"]
				if n.size() != 2 or int(n[0]) < 1 or int(n[0]) > int(n[1]):
					bad.append("掉落表 %s 条目 %s 数量非法" % [lid, en.get("item")])
			if en.has("grade") and (int(en["grade"]) < 0 or int(en["grade"]) > Grade.MAX):
				bad.append("掉落表 %s 条目品阶非法" % lid)
	_ok(bad.is_empty(), "掉落表错误:\n" + "\n".join(bad))


func test_breakthrough_pills() -> void:
	var bad: Array[String] = []
	for iid in DB.items:
		var u: Dictionary = DB.items[iid].get("use", {})
		if str(u.get("effect", "")) == "breakthrough":
			var r := int(u.get("realm", -1))
			if r < 0 or r >= DB.realm_count() - 1:
				bad.append("突破丹 %s 指向不存在的境界 %d" % [iid, r])
			if float(u.get("bonus", 0)) <= 0.0:
				bad.append("突破丹 %s 加成非正" % iid)
	for i in DB.realm_count():
		var pill := str(DB.realm(i).get("breakthrough", {}).get("pill", ""))
		if pill == "":
			continue
		var d := DB.item(pill)
		if d.is_empty():
			bad.append("境界 %d 推荐的突破丹 %s 不存在" % [i, pill])
		elif int(d.get("use", {}).get("realm", -1)) != i:
			bad.append("境界 %d 推荐的突破丹 %s 境界不符" % [i, pill])
	_ok(bad.is_empty(), "突破丹错误:\n" + "\n".join(bad))


func test_secret_realms() -> void:
	var bad: Array[String] = []
	var themes := {}
	for rid in DB.secret_realms:
		var sr: Dictionary = DB.secret_realms[rid]
		themes[str(sr.get("theme", ""))] = true
		if int(sr.get("min_realm", -1)) < 0 or int(sr.get("min_realm", -1)) >= DB.realm_count():
			bad.append("秘境 %s min_realm 越界" % rid)
		for r in sr.get("rival_ids", []):
			if str(DB.enemy(str(r)).get("kind", "")) != "cultivator":
				bad.append("秘境 %s 对手 %s 不是修士模板" % [rid, r])
		if sr.has("boss") and DB.enemy(str(sr["boss"])).is_empty():
			bad.append("秘境 %s 首领不存在" % rid)
		if sr.has("token") and str(DB.item(str(sr["token"])).get("type", "")) != "key":
			bad.append("秘境 %s 令牌不是信物" % rid)
		for c in sr.get("containers", {}).get("types", []):
			if not CONTAINER_TYPES.has(str(c.get("type", ""))):
				bad.append("秘境 %s 容器类型非法 %s" % [rid, c.get("type")])
			if float(c.get("w", 0)) <= 0.0 or float(c.get("time", 0)) <= 0.0:
				bad.append("秘境 %s 容器权重或搜索时间非正" % rid)
	_ok(DB.secret_realms.size() >= 6, "秘境不足 6 个")
	_ok(bad.is_empty(), "秘境数据错误:\n" + "\n".join(bad))


func test_missions_recipes_sects() -> void:
	var bad: Array[String] = []
	for mid in DB.missions:
		var m: Dictionary = DB.missions[mid]
		if not ["kill", "deliver", "spar", "realm_item"].has(str(m.get("type", ""))):
			bad.append("任务 %s 类型非法" % mid)
		for t in m.get("targets", []):
			if not DB.enemies.has(t):
				bad.append("任务 %s 目标不存在 %s" % [mid, t])
		for t in m.get("items", []):
			if not DB.items.has(t):
				bad.append("任务 %s 物品不存在 %s" % [mid, t])
		var ty := str(m.get("type", ""))
		if ty == "kill" and (m.get("targets", []) as Array).is_empty():
			bad.append("猎杀任务 %s 没有目标" % mid)
		if (ty == "deliver" or ty == "realm_item") and (m.get("items", []) as Array).is_empty():
			bad.append("上交任务 %s 没有物品" % mid)
	var per_prof := {}
	for rid in DB.recipes:
		var r: Dictionary = DB.recipes[rid]
		var prof := str(r.get("profession", ""))
		if not PROFESSIONS.has(prof):
			bad.append("配方 %s 技艺非法" % rid)
		per_prof[prof] = int(per_prof.get(prof, 0)) + 1
		if int(r.get("level", -1)) < 0 or int(r.get("level", -1)) > 6:
			bad.append("配方 %s 等级越界" % rid)
		if float(r.get("success", 0)) <= 0.0 or float(r.get("success", 0)) > 1.0:
			bad.append("配方 %s 成功率非法" % rid)
	for p in PROFESSIONS:
		if int(per_prof.get(p, 0)) < 6:
			bad.append("技艺 %s 配方不足 6 个" % p)
	for sid in DB.sects:
		var s: Dictionary = DB.sects[sid]
		var nranks := (s.get("ranks", []) as Array).size()
		for key in ["techniques", "spells", "shop"]:
			for e in s.get(key, []):
				if int(e.get("rank", -1)) < 0 or int(e.get("rank", -1)) >= nranks:
					bad.append("宗门 %s %s 阶位越界" % [sid, key])
		for r in s.get("rivals", []):
			if not DB.sects.has(r):
				bad.append("宗门 %s 敌对宗门不存在 %s" % [sid, r])
		if not PROFESSIONS.has(str(s.get("profession", ""))):
			bad.append("宗门 %s 技艺非法" % sid)
	_ok(DB.missions.size() >= 14, "任务模板不足 14")
	_ok(bad.is_empty(), "任务/配方/宗门错误:\n" + "\n".join(bad))


func test_text_pools() -> void:
	var bad: Array[String] = []
	for k in ["surnames", "given_female", "given_male"]:
		if (DB.names.get(k, []) as Array).size() < 80:
			bad.append("名字池 %s 不足 80" % k)
	var compound := 0
	for s in DB.names.get("surnames", []):
		if str(s).length() >= 2:
			compound += 1
	if compound < 10:
		bad.append("复姓不足 10")
	for k in ["daoist", "evil_titles"]:
		if (DB.names.get(k, []) as Array).size() < 20:
			bad.append("名字池 %s 过少" % k)
	for k in DB.dialogue:
		var v = DB.dialogue[k]
		var groups: Array = []
		if v is Dictionary:
			for k2 in v:
				groups.append([str(k) + "." + str(k2), v[k2]])
		else:
			groups.append([str(k), v])
		for g in groups:
			if (g[1] as Array).size() < 8:
				bad.append("台词组 %s 少于 8 句" % g[0])
	for k in ["greet", "friend", "spar_invite", "spar_win", "spar_lose", "robber_demand", "robber_paid", "gift_thanks", "gift_meh",
			"attacked", "flee", "teach", "rescued", "lover", "master", "rival", "gift_love", "trade", "farewell", "rumors", "robber_flee"]:
		if not DB.dialogue.has(k):
			bad.append("缺少台词组 %s" % k)
	for a in ["righteous", "neutral", "evil"]:
		if not DB.dialogue.get("greet", {}).has(a):
			bad.append("缺少 greet.%s" % a)
	for eid in ["spar", "robber", "treasure", "beast_attack", "rescue"]:
		if not DB.encounters.has(eid):
			bad.append("缺少遭遇 %s" % eid)
	_ok(bad.is_empty(), "文本数据错误:\n" + "\n".join(bad))


func test_content_scale() -> void:
	_ok(DB.items.size() >= 130, "物品数量不足 130（%d）" % DB.items.size())
	_ok(DB.spells.size() >= 40, "法诀数量不足 40（%d）" % DB.spells.size())
	_ok(DB.techniques.size() >= 25, "功法数量不足 25（%d）" % DB.techniques.size())
	_ok(DB.talents.size() >= 36, "天赋数量不足 36（%d）" % DB.talents.size())
	var weapon_grid := {}
	for iid in DB.items:
		var it: Dictionary = DB.items[iid]
		if it.has("weapon"):
			weapon_grid["%s_%d" % [it["weapon"]["kind"], int(it["grade"])]] = true
	for k in WEAPON_KINDS:
		for g in 5:
			_ok(weapon_grid.has("%s_%d" % [k, g]), "缺少 %s 品阶 %d 的兵器" % [k, g])
	var aux := 0
	for tid in DB.techniques:
		if str(DB.techniques[tid].get("slot", "")) == "aux":
			aux += 1
	_ok(aux >= 8, "辅修功法不足 8")
