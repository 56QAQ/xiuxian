class_name SectSystem
## 门派：加入/叛出、声望与阶位、贡献点、藏经阁与宝库、任务堂。
## 宗门状态存于 GS.world["sects"][id]；玩家已接任务存于 GS.world["missions"]。
##
## 任务实例：{ uid, template, sect, type, name, text, target(敌人 id)/item, count, progress,
##            reward{contribution, stones, rep}, accepted, done, expires_day }

const MISSION_REFRESH_DAYS := 3
const BOARD_SIZE := 4


static func sect_state(id: String) -> Dictionary:
	if not GS.world.has("sects"):
		GS.world["sects"] = {}
	var s: Dictionary = GS.world["sects"]
	if not s.has(id):
		s[id] = {"missions": [], "last_refresh": -999}
	return s[id]


# ================================================================ 加入 / 叛出

## 能否加入：返回空字符串表示可以，否则为原因
static func join_block_reason(id: String) -> String:
	var p := GS.player
	var sect := DB.sect(id)
	if sect.is_empty():
		return "不存在的宗门"
	if p.sect == id:
		return "你已是本门弟子"
	if p.sect != "":
		return "你已拜入%s，需先叛出师门" % DB.sect(p.sect).get("name", "")
	if int(p.reputation.get(id, 0)) <= -200:
		return "你在本门声名狼藉"
	for e in sect.get("join", {}).get("root", {}):
		if int(p.roots.get(e, 0)) < int(sect["join"]["root"][e]):
			return "需要%s灵根占比至少 %d%%" % [Elem.name_of(e), int(sect["join"]["root"][e])]
	if p.karma >= 100:
		return "你身上煞气太重，正道宗门不收"
	return ""


static func join(id: String) -> bool:
	if join_block_reason(id) != "":
		return false
	var p := GS.player
	p.sect = id
	p.sect_rank = 0
	p.contribution[id] = int(p.contribution.get(id, 0)) + 20
	p.reputation[id] = maxi(int(p.reputation.get(id, 0)), 0)
	Events.notify.emit("拜入%s，成为记名弟子" % DB.sect(id).get("name", ""), "realm")
	Events.sect_changed.emit()
	GS.recompute()
	return true


static func leave() -> void:
	var p := GS.player
	if p.sect == "":
		return
	var id := p.sect
	add_reputation(id, -300)
	p.sect = ""
	p.sect_rank = 0
	# 放弃本门任务
	var ms: Array = GS.world.get("missions", [])
	GS.world["missions"] = ms.filter(func(m: Dictionary) -> bool: return m.get("sect", "") != id)
	Events.notify.emit("你叛出了%s" % DB.sect(id).get("name", ""), "bad")
	Events.sect_changed.emit()
	Events.missions_changed.emit()


# ================================================================ 声望 / 阶位 / 贡献

static func rank_name(id: String, rank: int) -> String:
	var ranks: Array = DB.sect(id).get("ranks", [])
	if ranks.is_empty():
		return ""
	return str(ranks[clampi(rank, 0, ranks.size() - 1)].get("name", ""))


static func player_rank_name() -> String:
	if GS.player.sect == "":
		return "散修"
	return rank_name(GS.player.sect, GS.player.sect_rank)


static func add_reputation(id: String, amount: int) -> void:
	var p := GS.player
	p.reputation[id] = int(p.reputation.get(id, 0)) + amount
	if p.sect == id:
		_update_rank()
	Events.sect_changed.emit()


static func add_contribution(amount: int) -> void:
	var p := GS.player
	if p.sect == "":
		return
	p.contribution[p.sect] = int(p.contribution.get(p.sect, 0)) + amount
	Events.sect_changed.emit()


static func contribution() -> int:
	return int(GS.player.contribution.get(GS.player.sect, 0))


## 下一阶位的要求说明；空字符串表示已满阶
static func next_rank_requirement() -> String:
	var p := GS.player
	var ranks: Array = DB.sect(p.sect).get("ranks", [])
	if p.sect_rank + 1 >= ranks.size():
		return ""
	var r: Dictionary = ranks[p.sect_rank + 1]
	var t := "声望 %d" % int(r.get("rep", 0))
	if r.has("realm"):
		t += "，境界 %s" % DB.realm_name(int(r["realm"]), int(r.get("stage", 0)))
	return "晋升%s：%s" % [r.get("name", ""), t]


static func _update_rank() -> void:
	var p := GS.player
	var ranks: Array = DB.sect(p.sect).get("ranks", [])
	var rep := int(p.reputation.get(p.sect, 0))
	var best := 0
	for i in ranks.size():
		var r: Dictionary = ranks[i]
		if rep < int(r.get("rep", 0)):
			break
		if r.has("realm"):
			var rr := int(r["realm"])
			if p.realm < rr or (p.realm == rr and p.stage < int(r.get("stage", 0))):
				break
		best = i
	if best > p.sect_rank:
		p.sect_rank = best
		Events.notify.emit("晋升为%s%s！" % [DB.sect(p.sect).get("name", ""), rank_name(p.sect, best)], "realm")
		Audio.play("levelup")


static func check_promotion() -> void:
	if GS.player.sect != "":
		_update_rank()


# ================================================================ 藏经阁 / 宝库

## 可学习条目：[{kind: "technique"/"spell", id, rank, cost, learned, locked}]
static func library_entries(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sect := DB.sect(id)
	var p := GS.player
	for t in sect.get("techniques", []):
		out.append({"kind": "technique", "id": t["id"], "rank": int(t.get("rank", 0)), "cost": int(t.get("cost", 50)),
			"learned": p.techniques.has(t["id"]), "locked": p.sect != id or p.sect_rank < int(t.get("rank", 0))})
	for s in sect.get("spells", []):
		out.append({"kind": "spell", "id": s["id"], "rank": int(s.get("rank", 0)), "cost": int(s.get("cost", 50)),
			"learned": p.spells.has(s["id"]), "locked": p.sect != id or p.sect_rank < int(s.get("rank", 0))})
	return out


static func learn_entry(e: Dictionary) -> bool:
	if e.get("learned", false) or e.get("locked", false):
		return false
	if contribution() < int(e["cost"]):
		Events.notify.emit("贡献点不足", "warn")
		return false
	GS.player.contribution[GS.player.sect] = contribution() - int(e["cost"])
	if e["kind"] == "technique":
		GS.learn_technique(e["id"])
	else:
		GS.learn_spell(e["id"])
	Events.sect_changed.emit()
	return true


static func shop_entries(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var p := GS.player
	for s in DB.sect(id).get("shop", []):
		out.append({"item": s["item"], "price": int(s.get("cost", 10)), "currency": "贡献", "rank": int(s.get("rank", 0)),
			"locked": p.sect != id or p.sect_rank < int(s.get("rank", 0))})
	return out


static func buy_entry(e: Dictionary) -> bool:
	if e.get("locked", false):
		Events.notify.emit("阶位不足", "warn")
		return false
	if contribution() < int(e["price"]):
		Events.notify.emit("贡献点不足", "warn")
		return false
	GS.player.contribution[GS.player.sect] = contribution() - int(e["price"])
	GS.give_item(str(e["item"]), 1)
	Events.sect_changed.emit()
	return true


# ================================================================ 任务堂

static func board(id: String) -> Array:
	var st := sect_state(id)
	var today := GS.day_index()
	if today - int(st.get("last_refresh", -999)) >= MISSION_REFRESH_DAYS or (st["missions"] as Array).is_empty():
		st["missions"] = _generate(id, BOARD_SIZE)
		st["last_refresh"] = today
	return st["missions"]


static func _generate(id: String, n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + GS.day_index() * 977 + int(GS.world.get("seed", 0))
	var pool: Array = DB.sect(id).get("mission_pool", [])
	var out := []
	var counter := int(GS.world.get("mission_counter", 0))
	for i in n:
		if pool.is_empty():
			break
		var tid: String = pool[rng.randi() % pool.size()]
		var tpl := DB.missions.get(tid, {}) as Dictionary
		if tpl.is_empty():
			continue
		counter += 1
		out.append(_instance(tpl, id, rng, counter))
	GS.world["mission_counter"] = counter
	return out


static func _instance(tpl: Dictionary, sect: String, rng: RandomNumberGenerator, uid: int) -> Dictionary:
	var cnt: Array = tpl.get("count", [1, 1])
	var count := rng.randi_range(int(cnt[0]), int(cnt[1]))
	var m := {
		"uid": uid, "template": tpl["id"], "sect": sect, "type": tpl.get("type", "kill"), "name": tpl.get("name", ""),
		"count": count, "progress": 0, "accepted": false, "done": false, "min_rank": int(tpl.get("min_rank", 0)),
		"expires_day": GS.day_index() + 15,
	}
	var tname := ""
	if tpl.has("targets"):
		var ts: Array = tpl["targets"]
		m["target"] = ts[rng.randi() % ts.size()]
		tname = str(DB.enemy(m["target"]).get("name", m["target"]))
	if tpl.has("items"):
		var its: Array = tpl["items"]
		m["item"] = its[rng.randi() % its.size()]
	var reward := {}
	var rw: Dictionary = tpl.get("reward", {})
	var scale := 1.0 + 0.5 * GS.player.realm
	for k in rw:
		var r: Array = rw[k]
		reward[k] = int(rng.randi_range(int(r[0]), int(r[1])) * scale)
	m["reward"] = reward
	var text := str(tpl.get("text", ""))
	text = text.replace("{target}", tname).replace("{count}", str(count)).replace("{item}", str(DB.item(m.get("item", "")).get("name", "")))
	m["text"] = text
	return m


static func accepted() -> Array:
	if not GS.world.has("missions"):
		GS.world["missions"] = []
	return GS.world["missions"]


static func accept(m: Dictionary) -> bool:
	if m.get("accepted", false):
		return false
	if GS.player.sect != m.get("sect", "") or GS.player.sect_rank < int(m.get("min_rank", 0)):
		Events.notify.emit("阶位不足，无法接取", "warn")
		return false
	if accepted().size() >= 5:
		Events.notify.emit("同时最多接取 5 个任务", "warn")
		return false
	m["accepted"] = true
	var board_list: Array = sect_state(str(m["sect"]))["missions"]
	board_list.erase(m)
	accepted().append(m)
	Events.notify.emit("接取任务：%s" % m["name"], "info")
	Events.missions_changed.emit()
	return true


## 击杀进度（由场景在 actor_died 时调用）
static func on_enemy_killed(enemy_id: String) -> void:
	for m in accepted():
		if m.get("done", false):
			continue
		if m["type"] == "kill" and str(m.get("target", "")) == enemy_id:
			m["progress"] = int(m["progress"]) + 1
			if int(m["progress"]) >= int(m["count"]):
				m["done"] = true
				Events.notify.emit("任务「%s」可以交付了" % m["name"], "good")
			Events.missions_changed.emit()


static func on_spar_won() -> void:
	for m in accepted():
		if m["type"] == "spar" and not m.get("done", false):
			m["progress"] = int(m["count"])
			m["done"] = true
			Events.notify.emit("任务「%s」可以交付了" % m["name"], "good")
			Events.missions_changed.emit()


static func can_turn_in(m: Dictionary) -> bool:
	if m["type"] == "deliver":
		return GS.player.bag.count_of(str(m.get("item", ""))) >= int(m["count"])
	return m.get("done", false)


static func turn_in(m: Dictionary) -> bool:
	if not can_turn_in(m):
		return false
	if m["type"] == "deliver":
		GS.player.bag.take(str(m["item"]), int(m["count"]))
	var r: Dictionary = m.get("reward", {})
	var sect := str(m.get("sect", ""))
	if GS.player.sect == sect:
		add_contribution(int(r.get("contribution", 0)))
	add_reputation(sect, int(r.get("rep", 0)))
	if int(r.get("stones", 0)) > 0:
		GS.add_stones(int(r["stones"]))
	accepted().erase(m)
	Events.notify.emit("任务完成：%s（贡献 +%d，声望 +%d）" % [m["name"], int(r.get("contribution", 0)), int(r.get("rep", 0))], "good")
	Audio.play("quest_complete")
	Events.missions_changed.emit()
	Events.inventory_changed.emit()
	return true


static func abandon(m: Dictionary) -> void:
	accepted().erase(m)
	Events.missions_changed.emit()


static func simulate_days(world: Dictionary, _player: PlayerData, _days: int) -> void:
	# 过期任务
	var today := int(float(world.get("hours", 0.0)) / 24.0)
	if world.has("missions"):
		var ms: Array = world["missions"]
		world["missions"] = ms.filter(func(m: Dictionary) -> bool: return int(m.get("expires_day", 99999)) >= today)
