class_name NpcSystem
## NPC 修士名册：生成、离线模拟、好感与羁绊。数据全部存于 GS.world["npcs"]（可序列化字典）。
##
## 记录格式：
## { id, pd: PlayerData 字典, role, sect, personality, alignment(-100~100), traits[],
##   favor(-100~100), bond(""/friend/confidant/lover/master/disciple/enemy), alive, met,
##   home_poi, last_talk_day, last_gift_day, last_spar_day, last_teach_day, memory[] }
##
## role: sect_master / sect_teacher / sect_steward / sect_senior / sect_disciple / merchant / wanderer

const TRAITS := ["豪爽", "谨慎", "贪财", "好战", "仁厚", "孤傲", "嗜酒", "痴剑", "爱美", "多疑", "重情", "阴狠"]
const BOND_NAMES := {"": "陌生", "acq": "相识", "friend": "好友", "confidant": "知己", "lover": "道侣", "master": "师父", "disciple": "弟子", "enemy": "仇敌"}

static var _cache: Dictionary = {}   ## id -> PlayerData（避免反复反序列化）


static func npcs() -> Dictionary:
	if not GS.world.has("npcs"):
		GS.world["npcs"] = {}
	return GS.world["npcs"]


static func get_npc(id: String) -> Dictionary:
	return npcs().get(id, {})


## 该 NPC 的 PlayerData（缓存；修改后需 save_pd）
static func pd_of(id: String) -> PlayerData:
	if _cache.has(id):
		return _cache[id]
	var rec := get_npc(id)
	if rec.is_empty():
		return null
	var pd := PlayerData.from_dict(rec.get("pd", {}))
	_cache[id] = pd
	return pd


static func save_pd(id: String) -> void:
	if _cache.has(id) and npcs().has(id):
		npcs()[id]["pd"] = (_cache[id] as PlayerData).to_dict()


static func clear_cache() -> void:
	_cache.clear()


# ================================================================ 生成

static func generate_world_npcs(world: Dictionary, seed_value: int) -> void:
	_cache.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 7
	var roster := {}
	world["npcs"] = roster
	var n := 0
	for sid in DB.sects:
		var sect: Dictionary = DB.sects[sid]
		var elem := str(sect.get("element", ""))
		for role_def in sect.get("npcs", []):
			var role := "sect_" + str(role_def.get("role", "disciple"))
			var realm := int(role_def.get("realm", 1))
			var rec := _make(rng, "npc_%d" % n, role, sid, realm, rng.randi_range(0, 3), elem)
			rec["title"] = str(role_def.get("title", ""))
			rec["home_poi"] = sid
			if role == "sect_master" or role == "sect_teacher":
				rec["pd"]["name"] = NameGen.daoist(rng)
				rec["alignment"] = rng.randi_range(20, 80)
			roster[rec["id"]] = rec
			n += 1
		# 普通弟子
		for i in 3:
			var rec2 := _make(rng, "npc_%d" % n, "sect_disciple", sid, 0, rng.randi_range(1, 8), elem)
			rec2["title"] = "外门弟子" if i > 0 else "内门弟子"
			rec2["home_poi"] = sid
			roster[rec2["id"]] = rec2
			n += 1
	# 坊市商人
	for i in 4:
		var rec3 := _make(rng, "npc_%d" % n, "merchant", "", rng.randi_range(0, 1), rng.randi_range(0, 3), "")
		rec3["title"] = ["丹药铺掌柜", "法器阁掌柜", "杂货摊主", "符箓店掌柜"][i]
		rec3["home_poi"] = "town"
		rec3["shop"] = ["pills", "gear", "misc", "talismans"][i]
		rec3["alignment"] = rng.randi_range(-10, 40)
		roster[rec3["id"]] = rec3
		n += 1
	# 散修
	for i in 10:
		var rec4 := _make(rng, "npc_%d" % n, "wanderer", "", 0 if rng.randf() < 0.75 else 1, rng.randi_range(0, 8), "")
		rec4["title"] = "散修"
		rec4["home_poi"] = "town" if i < 5 else "wild"
		roster[rec4["id"]] = rec4
		n += 1
	world["npc_counter"] = n


static func _make(rng: RandomNumberGenerator, id: String, role: String, sect: String, realm: int, stage: int, elem: String) -> Dictionary:
	var tpl := DB.enemy("rogue_cultivator")
	var sect_def := DB.sect(sect)
	if not sect_def.is_empty():
		var spells: Array = []
		for s in sect_def.get("spells", []):
			spells.append(s["id"])
		tpl = tpl.duplicate()
		tpl["spells"] = spells if not spells.is_empty() else tpl.get("spells", [])
	var over := {"realm": realm, "stage": stage, "element": elem}
	if sect != "":
		over["sect"] = sect
	var pd := ActorFactory.make_cultivator_pd(tpl, rng, over)
	if sect != "":
		var techs: Array = sect_def.get("techniques", [])
		if not techs.is_empty() and DB.techniques.has(techs[0]["id"]):
			pd.main_technique = techs[0]["id"]
			pd.techniques[pd.main_technique] = {"lv": mini(realm, 3), "xp": 0.0}
	pd.spirit_stones = rng.randi_range(10, 60) * (realm + 1) * (realm + 1)
	# 储物袋里放些东西（被袭杀时可夺取）
	pd.bag = InventoryGrid.new(6, 5)
	for i in rng.randi_range(1, 3):
		var pool := ["pill_heal_small", "pill_qi_small", "herb_lingcao", "pill_exp_small", "beast_core_1", "spirit_stone_mid"]
		pd.bag.add(ItemInstance.create(pool[rng.randi() % pool.size()], rng.randi_range(1, 3)))
	var pers: String = ["aggressive", "balanced", "cautious"][rng.randi() % 3]
	return {
		"id": id, "pd": pd.to_dict(), "role": role, "sect": sect, "personality": pers,
		"alignment": rng.randi_range(-40, 70), "traits": [TRAITS[rng.randi() % TRAITS.size()]],
		"favor": 0, "bond": "", "alive": true, "met": false, "home_poi": "",
		"last_talk_day": -99, "last_gift_day": -99, "last_spar_day": -99, "last_teach_day": -99,
		"memory": [], "title": "",
	}


## 为随机遭遇临时创建并登记一名 NPC（例如切磋的散修），返回 id
static func create_wanderer(rng: RandomNumberGenerator, realm: int, stage: int, role: String = "wanderer") -> String:
	var counter := int(GS.world.get("npc_counter", 1000))
	GS.world["npc_counter"] = counter + 1
	var rec := _make(rng, "npc_%d" % counter, role, "", realm, stage, "")
	rec["title"] = "散修"
	rec["home_poi"] = "wild"
	npcs()[rec["id"]] = rec
	return rec["id"]


# ================================================================ 查询

static func display_name(id: String) -> String:
	var rec := get_npc(id)
	return str(rec.get("pd", {}).get("name", "无名"))


static func alignment_group(id: String) -> String:
	var a := int(get_npc(id).get("alignment", 0))
	if a >= 30:
		return "righteous"
	if a <= -30:
		return "evil"
	return "neutral"


static func at_poi(poi: String) -> Array[String]:
	var out: Array[String] = []
	for id in npcs():
		var r: Dictionary = npcs()[id]
		if r.get("alive", true) and str(r.get("home_poi", "")) == poi:
			out.append(id)
	return out


static func by_role(sect: String, role: String) -> String:
	for id in npcs():
		var r: Dictionary = npcs()[id]
		if r.get("alive", true) and r.get("sect", "") == sect and r.get("role", "") == role:
			return id
	return ""


static func bond_name(id: String) -> String:
	var rec := get_npc(id)
	var b := str(rec.get("bond", ""))
	if b == "" and rec.get("met", false):
		b = "acq"
	return BOND_NAMES.get(b, "陌生")


# ================================================================ 好感与羁绊

static func change_favor(id: String, amount: float, reason: String = "") -> void:
	var rec := get_npc(id)
	if rec.is_empty():
		return
	if amount > 0.0:
		amount *= float(GS.stats.get("favor_gain", 1.0))
	var before := int(rec.get("favor", 0))
	var after := clampi(before + int(round(amount)), -100, 100)
	rec["favor"] = after
	rec["met"] = true
	if reason != "":
		_remember(rec, reason)
	_update_bond(rec, before, after)
	Events.relation_changed.emit(id)


static func _update_bond(rec: Dictionary, before: int, after: int) -> void:
	var b := str(rec.get("bond", ""))
	var nm := str(rec["pd"].get("name", ""))
	if b in ["lover", "master", "disciple"]:
		if after <= -30:
			rec["bond"] = "enemy"
			Events.notify.emit("你与%s恩断义绝" % nm, "bad")
		return
	if after <= -50 and b != "enemy":
		rec["bond"] = "enemy"
		Events.notify.emit("%s 视你为仇敌！" % nm, "bad")
	elif after >= 70 and before < 70:
		rec["bond"] = "confidant"
		Events.notify.emit("你与%s结为知己" % nm, "good")
	elif after >= 40 and before < 40 and b != "confidant":
		rec["bond"] = "friend"
		Events.notify.emit("你与%s成为好友" % nm, "good")
	elif after > -50 and b == "enemy" and after >= 0:
		rec["bond"] = ""


static func _remember(rec: Dictionary, text: String) -> void:
	var mem: Array = rec.get("memory", [])
	mem.append("%s %s" % [GS.date_text().split(" ")[0], text])
	while mem.size() > 12:
		mem.pop_front()
	rec["memory"] = mem


## 赠礼：按物品价值与 NPC 喜好计算好感。返回反应文本
static func gift(id: String, item: ItemInstance) -> String:
	var rec := get_npc(id)
	var pd := pd_of(id)
	if rec.is_empty() or pd == null:
		return ""
	var today := GS.day_index()
	var repeat := today == int(rec.get("last_gift_day", -99))
	rec["last_gift_day"] = today
	var v := float(item.total_value())
	var realm_scale := pow(4.0, pd.realm)
	var gain := clampf(sqrt(v / realm_scale) * 1.6, 1.0, 30.0)
	# 喜好：同属性物品、贪财者爱灵石、好战者爱兵器、仁厚者不在乎贵贱
	var traits: Array = rec.get("traits", [])
	if Elem.is_valid(item.element()) and item.element() == pd.main_element():
		gain *= 1.5
	if traits.has("贪财"):
		gain *= 1.4
	if traits.has("好战") and item.type() == "weapon":
		gain *= 1.6
	if traits.has("仁厚"):
		gain = maxf(gain, 6.0)
	if repeat:
		gain *= 0.4
	change_favor(id, gain, "收到赠礼：%s" % item.display_name())
	pd.bag.add(ItemInstance.from_dict(item.to_dict()))
	save_pd(id)
	var lines: Array = DB.dialogue.get("gift_love" if gain >= 20.0 else ("gift_thanks" if gain >= 6.0 else "gift_meh"), DB.dialogue.get("gift_thanks", ["多谢。"]))
	return str(lines[randi() % lines.size()])


## 交谈（每天一次好感）
static func chat(id: String) -> String:
	var rec := get_npc(id)
	if rec.is_empty():
		return ""
	var today := GS.day_index()
	if int(rec.get("last_talk_day", -99)) != today:
		rec["last_talk_day"] = today
		change_favor(id, 2.0)
	rec["met"] = true
	var key := "greet"
	var b := str(rec.get("bond", ""))
	var pool: Array
	if b in ["friend", "confidant", "lover"]:
		pool = DB.dialogue.get("lover" if b == "lover" and DB.dialogue.has("lover") else "friend", [])
	elif b == "enemy":
		pool = DB.dialogue.get("rival", DB.dialogue.get("attacked", []))
	else:
		pool = DB.dialogue.get(key, {}).get(alignment_group(id), [])
	var rumors: Array = DB.dialogue.get("rumors", [])
	var line := str(pool[randi() % pool.size()]) if not pool.is_empty() else "……"
	if not rumors.is_empty() and randf() < 0.35:
		line += "\n" + str(rumors[randi() % rumors.size()])
	return line


## 请教：好感足够时传授一门法诀或指点修为
static func ask_guidance(id: String) -> String:
	var rec := get_npc(id)
	var pd := pd_of(id)
	if rec.is_empty() or pd == null:
		return ""
	var today := GS.day_index()
	if today - int(rec.get("last_teach_day", -99)) < 7:
		return "今日便到这里吧，过几日再来。"
	if int(rec.get("favor", 0)) < 30:
		return "你我交情尚浅，恕我不便多言。"
	rec["last_teach_day"] = today
	# 传授未学过的法诀
	for sid in pd.spells:
		if not GS.player.spells.has(sid) and int(rec.get("favor", 0)) >= 50:
			GS.learn_spell(sid)
			change_favor(id, 1.0, "传授了【%s】" % DB.spell(sid).get("name", sid))
			return "此乃我压箱底的【%s】，你且好生参悟。" % DB.spell(sid).get("name", sid)
	# 指点修为
	var gain := Cultivation.rate_per_hour(GS.player, GS.stats) * 12.0 * (1.0 + pd.realm - GS.player.realm)
	gain = maxf(gain, 10.0)
	Cultivation.add_exp(GS.player, gain, "teach")
	GS.recompute()
	var lines: Array = DB.dialogue.get("teach", ["修行之道，贵在持之以恒。"])
	return "%s\n（修为 +%d）" % [lines[randi() % lines.size()], int(gain)]


## 结为道侣 / 拜师
static func try_bond(id: String, bond: String) -> String:
	var rec := get_npc(id)
	if rec.is_empty():
		return ""
	var favor := int(rec.get("favor", 0))
	var nm := str(rec["pd"].get("name", ""))
	match bond:
		"lover":
			if str(rec.get("bond", "")) != "confidant" or favor < 85:
				return "（%s 微微一愣，轻轻摇了摇头。）" % nm
			for oid in npcs():
				if str(npcs()[oid].get("bond", "")) == "lover":
					return "（你已有道侣，此事不妥。）"
			rec["bond"] = "lover"
			_remember(rec, "结为道侣")
			Events.notify.emit("你与%s结为道侣！" % nm, "realm")
			Events.relation_changed.emit(id)
			return "（%s 眼波流转）……从今往后，大道同行。" % nm
		"master":
			var pd := pd_of(id)
			if pd == null or pd.realm <= GS.player.realm or favor < 60:
				return "你我修为相近，何来师徒之说？" if pd != null and pd.realm <= GS.player.realm else "（%s 打量了你一番）根骨尚可，心性还需磨砺。再说吧。" % nm
			for oid in npcs():
				if str(npcs()[oid].get("bond", "")) == "master":
					return "你已有师承，岂可另投他门？"
			rec["bond"] = "master"
			_remember(rec, "收为弟子")
			Events.notify.emit("你拜%s为师" % nm, "realm")
			Events.relation_changed.emit(id)
			return "好！从今日起，你便是我%s的弟子。" % nm
	return ""


## NPC 被玩家杀死
static func on_killed_by_player(id: String, witnesses: Array[String]) -> void:
	var rec := get_npc(id)
	if rec.is_empty():
		return
	rec["alive"] = false
	var al := int(rec.get("alignment", 0))
	var nm := str(rec["pd"].get("name", ""))
	var provoked: bool = rec.get("hostile_first", false)
	if not provoked:
		GS.player.karma += 20 if al >= 0 else 5
		if al < -30:
			GS.player.karma -= 10  # 斩除恶人反而积德
	var sect := str(rec.get("sect", ""))
	if sect != "" and not provoked:
		SectSystem.add_reputation(sect, -150)
		Events.notify.emit("%s 的死讯传回%s……" % [nm, DB.sect(sect).get("name", "")], "bad")
	for w in witnesses:
		change_favor(w, -60.0, "目睹你杀害%s" % nm)
	# 亲友记仇
	for oid in npcs():
		var o: Dictionary = npcs()[oid]
		if o.get("alive", true) and oid != id and str(o.get("sect", "")) == sect and sect != "":
			o["favor"] = clampi(int(o.get("favor", 0)) - 15, -100, 100)


# ================================================================ 离线模拟

static func simulate_days(world: Dictionary, days: int) -> void:
	if days <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(world.get("seed", 0)) + int(world.get("hours", 0.0))
	var roster: Dictionary = world.get("npcs", {})
	for id in roster:
		var rec: Dictionary = roster[id]
		if not rec.get("alive", true):
			continue
		var pdd: Dictionary = rec["pd"]
		# 修炼：按天推进小境界（粗略）
		var realm := int(pdd.get("realm", 0))
		var stage := int(pdd.get("stage", 0))
		var stages := (DB.realm(realm).get("stages", []) as Array).size()
		var chance := clampf(days * 0.012 / (1.0 + realm), 0.0, 0.9)
		if rng.randf() < chance:
			if stage < stages - 1:
				pdd["stage"] = stage + 1
			elif realm < DB.realm_count() - 1 and rng.randf() < 0.2:
				pdd["realm"] = realm + 1
				pdd["stage"] = 0
				_remember(rec, "突破至%s" % DB.realm_name(realm + 1, 0))
		pdd["age_days"] = float(pdd.get("age_days", 20 * 360)) + days
		# 寿元
		if float(pdd["age_days"]) / 360.0 > float(DB.realm(int(pdd["realm"])).get("lifespan", 100)):
			rec["alive"] = false
		# 好感向 0 回落（非羁绊）
		if str(rec.get("bond", "")) == "" and days >= 30:
			rec["favor"] = int(rec.get("favor", 0) * 0.9)
		_cache.erase(id)
