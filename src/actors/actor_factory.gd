class_name ActorFactory
## 生成玩家、修士 NPC、妖兽。


## 生成玩家角色（含控制器与镜头）。返回 {actor, camera, controller}
static func spawn_player(parent: Node, pos: Vector3) -> Dictionary:
	var a := HumanoidActor.new()
	a.name = "Player"
	parent.add_child(a)
	a.global_position = pos
	a.setup(GS.player, Factions.player_faction(), true)
	var pc := PlayerController.new()
	pc.name = "PlayerController"
	a.add_child(pc)
	a.controller = pc
	var cam := CameraRig.new()
	cam.name = "CameraRig"
	parent.add_child(cam)
	cam.set_target(a)
	pc.cam = cam
	pc.actor = a
	return {"actor": a, "camera": cam, "controller": pc}


## 修士模板 → NPC PlayerData。template 为 enemies.json 中 kind=cultivator 的条目或自定义字典。
## overrides: realm, stage, gender, name, sect, faction, weapon, spells[], roots{}, appearance{}
static func make_cultivator_pd(template: Dictionary, rng: RandomNumberGenerator, overrides: Dictionary = {}) -> PlayerData:
	var pd := PlayerData.new()
	pd.gender = str(overrides.get("gender", "female" if rng.randf() < 0.5 else "male"))
	pd.name = str(overrides.get("name", NameGen.person(rng, pd.gender)))
	# 境界
	pd.realm = int(overrides.get("realm", template.get("realm", 0)))
	var st = overrides.get("stage", template.get("stage", 0))
	if st is Array:
		pd.stage = rng.randi_range(int(st[0]), int(st[1]))
	else:
		pd.stage = int(st)
	var max_stage := (DB.realm(pd.realm).get("stages", [""]) as Array).size() - 1
	pd.stage = clampi(pd.stage, 0, max_stage)
	# 灵根
	var roots = overrides.get("roots", template.get("roots", "random"))
	if roots is Dictionary and not (roots as Dictionary).is_empty():
		pd.roots = roots
	else:
		pd.roots = random_roots(rng, str(overrides.get("element", "")))
	# 兵器
	var weapons: Array = template.get("weapons", ["sword_iron"])
	var wid := str(overrides.get("weapon", weapons[rng.randi() % weapons.size()] if not weapons.is_empty() else "sword_iron"))
	if not DB.item(wid).is_empty():
		pd.equipment["weapon"] = ItemInstance.create(wid)
	# 法诀
	var spells: Array = overrides.get("spells", [])
	if spells.is_empty():
		var pool: Array = (template.get("spells", []) as Array).duplicate()
		var n := clampi(1 + pd.realm + rng.randi_range(0, 1), 1, 4)
		for i in n:
			if pool.is_empty():
				break
			var sid: String = pool.pop_at(rng.randi() % pool.size())
			spells.append(sid)
	var slot := 0
	for sid in spells:
		if DB.spell(sid).is_empty():
			continue
		pd.spells[sid] = {"lv": rng.randi_range(0, 2 + pd.realm * 2), "xp": 0.0}
		if slot < 4:
			pd.spell_slots[slot] = sid
			slot += 1
	# 功法：主元素对应的主修功法
	pd.main_technique = best_technique_for(pd.main_element(), pd.realm)
	if pd.main_technique != "":
		pd.techniques[pd.main_technique] = {"lv": clampi(pd.realm, 0, 3), "xp": 0.0}
	# 外貌
	var app: Dictionary = overrides.get("appearance", {})
	if app.is_empty():
		app = NpcLooks.random_appearance(rng, pd.gender)
	if template.has("outfit_colors"):
		app["outfit_colors"] = template["outfit_colors"]
	var sect := str(overrides.get("sect", ""))
	if sect != "":
		pd.sect = sect
		var sd := DB.sect(sect)
		app["outfit_colors"] = [sd.get("color", "#888888"), sd.get("color3", "#333333"), sd.get("color2", "#d0b050")]
		app["outfit"] = "robe" if rng.randf() < 0.6 else "martial"
	pd.appearance = app
	return pd


static func random_roots(rng: RandomNumberGenerator, prefer: String = "") -> Dictionary:
	var elems := Elem.LIST.duplicate()
	var n := 1
	var r := rng.randf()
	if r < 0.08:
		n = 1
	elif r < 0.35:
		n = 2
	elif r < 0.7:
		n = 3
	elif r < 0.9:
		n = 4
	else:
		n = 5
	var chosen: Array[String] = []
	if Elem.is_valid(prefer):
		chosen.append(prefer)
		elems.erase(prefer)
	while chosen.size() < n:
		chosen.append(elems.pop_at(rng.randi() % elems.size()))
	var weights: Array[float] = []
	var total := 0.0
	for i in chosen.size():
		var w := rng.randf_range(0.5, 1.5) * (1.6 if i == 0 else 1.0)
		weights.append(w)
		total += w
	var out := {}
	var acc := 0
	for i in chosen.size():
		var pct := int(round(weights[i] / total * 100.0))
		if i == chosen.size() - 1:
			pct = 100 - acc
		out[chosen[i]] = pct
		acc += pct
	return out


static func best_technique_for(element: String, realm: int) -> String:
	var best := "tuna_basic"
	var best_g := -1
	for tid in DB.techniques:
		var t: Dictionary = DB.techniques[tid]
		if str(t.get("slot", "main")) != "main" or str(t.get("element", "")) != element:
			continue
		var g := int(t.get("grade", 0))
		if g <= realm + 1 and g > best_g and (t.get("req", {}).get("root", {}) as Dictionary).size() <= 1:
			best = tid
			best_g = g
	return best if DB.techniques.has(best) else ""


## 生成修士 NPC
static func spawn_cultivator(parent: Node, pd: PlayerData, pos: Vector3, faction: String, personality: String = "balanced", passive: bool = true) -> HumanoidActor:
	var a := HumanoidActor.new()
	a.name = "Cultivator"
	parent.add_child(a)
	a.global_position = pos
	a.setup(pd, faction, false)
	var ai := CultivatorAI.new()
	ai.name = "AI"
	a.add_child(ai)
	ai.setup(a, personality)
	ai.home = pos
	ai.passive = passive
	a.controller = ai
	a.rotation.y = randf() * TAU
	return a
