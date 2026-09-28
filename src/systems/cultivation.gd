class_name Cultivation
## 修炼规则：修为获取、小境界自动提升、大境界突破、丹药、炼化、战斗感悟。
## 所有函数只修改传入的 PlayerData，并通过 Events 广播；调用方负责 GS.recompute()。

## 地点倍率
const LOCATION_MULT := {"wild": 1.0, "home": 1.5, "sect": 2.0, "vein": 3.0, "realm": 0.5}


static func exp_needed(p: PlayerData) -> float:
	var r := DB.realm(p.realm)
	var arr: Array = r.get("exp", [])
	if arr.is_empty():
		return INF
	return float(arr[clampi(p.stage, 0, arr.size() - 1)])


static func is_last_stage(p: PlayerData) -> bool:
	return p.stage >= (DB.realm(p.realm).get("stages", []) as Array).size() - 1


static func is_peak_realm(p: PlayerData) -> bool:
	return p.realm >= DB.realm_count() - 1


## 是否处于大境界瓶颈（需要突破）
static func at_bottleneck(p: PlayerData) -> bool:
	return is_last_stage(p) and p.cult_exp >= exp_needed(p) and not is_peak_realm(p)


## 每小时打坐获得的修为
static func rate_per_hour(p: PlayerData, stats: Dictionary, location: String = "wild") -> float:
	var r := DB.realm(p.realm)
	var rate := float(r.get("cult_rate", 10.0))
	rate *= float(stats.get("cult_speed", 1.0))
	rate *= float(LOCATION_MULT.get(location, 1.0))
	if location == "home":
		rate *= home_formation_mult()
	if p.main_technique == "":
		rate *= 0.5  # 无主修功法只能粗浅吐纳
	return maxf(rate, 0.0)


## 增加修为，自动处理小境界提升。返回提升的小境界数。
static func add_exp(p: PlayerData, amount: float, source: String = "") -> int:
	if amount <= 0.0:
		return 0
	p.cult_exp += amount
	var ups := 0
	while p.cult_exp >= exp_needed(p):
		if is_last_stage(p):
			# 瓶颈：修为封顶于需求值，等待突破
			p.cult_exp = exp_needed(p)
			break
		p.cult_exp -= exp_needed(p)
		p.stage += 1
		ups += 1
	if ups > 0:
		Events.realm_changed.emit(p.realm, p.stage)
		Events.notify.emit("修为精进，突破至 %s！" % DB.realm_name(p.realm, p.stage), "realm")
	Events.exp_changed.emit()
	return ups


## 突破成功率
static func breakthrough_chance(p: PlayerData, stats: Dictionary, bonus: float = 0.0) -> float:
	var r := DB.realm(p.realm)
	var bt: Dictionary = r.get("breakthrough", {})
	var c := float(bt.get("base", 0.5))
	c += float(stats.get("breakthrough", 0.0))
	c += bonus
	c += 0.05 * p.breakthrough_fails  # 失败积累的经验
	if p.injury_days > 0.0:
		c -= 0.2
	if p.pill_toxicity > 60.0:
		c -= 0.1
	return clampf(c, 0.05, 0.98)


## 尝试突破大境界。返回 {"ok": bool, "chance": float, "text": String}
static func attempt_breakthrough(p: PlayerData, stats: Dictionary, bonus: float, rng: RandomNumberGenerator) -> Dictionary:
	if not at_bottleneck(p):
		return {"ok": false, "chance": 0.0, "text": "修为尚未圆满，无法突破。"}
	var chance := breakthrough_chance(p, stats, bonus)
	if rng.randf() < chance:
		p.realm += 1
		p.stage = 0
		p.cult_exp = 0.0
		p.breakthrough_fails = 0
		var r := DB.realm(p.realm)
		var text := "天地灵气倒灌，你成功突破至【%s】！寿元增至 %d 载。" % [DB.realm_name(p.realm, 0), int(r.get("lifespan", 100))]
		for perk in r.get("perks", []):
			text += "\n" + str(DB.realm(p.realm).get("perk_text", {}).get(perk, ""))
		Events.realm_changed.emit(p.realm, p.stage)
		Events.notify.emit("突破成功！踏入%s" % DB.realm_name(p.realm, 0), "realm")
		return {"ok": true, "chance": chance, "text": text.strip_edges()}
	p.breakthrough_fails += 1
	p.cult_exp = exp_needed(p) * 0.7
	p.injury_days = maxf(p.injury_days, 30.0)
	Events.exp_changed.emit()
	Events.notify.emit("突破失败，经脉受损……", "bad")
	return {"ok": false, "chance": chance, "text": "灵气逆冲，突破失败！修为跌落三成，身受内伤（30 日）。"}


## 服用丹药。返回提示文本；丹药效果由 item.use 定义
static func use_pill(p: PlayerData, stats: Dictionary, item_id: String) -> String:
	var d := DB.item(item_id)
	var use: Dictionary = d.get("use", {})
	var eff := float(stats.get("pill_eff", 1.0)) * (1.0 - clampf(p.pill_toxicity / 150.0, 0.0, 0.66))
	var tox := float(use.get("toxicity", 0.0)) * float(stats.get("pill_tox", 1.0))
	var text := ""
	match str(use.get("effect", "")):
		"exp":
			var amount := float(use.get("amount", 0)) * eff
			add_exp(p, amount, "pill")
			text = "药力化开，修为 +%d" % int(amount)
		"heal_injury":
			p.injury_days = maxf(p.injury_days - float(use.get("amount", 30)), 0.0)
			text = "伤势好转。"
		"detox":
			p.pill_toxicity = maxf(p.pill_toxicity - float(use.get("amount", 30)), 0.0)
			text = "丹毒消退。"
		"attribute":
			var a := str(use.get("attr", "con"))
			p.attributes[a] = int(p.attributes.get(a, 5)) + int(use.get("amount", 1))
			text = "%s +%d" % [PlayerData.ATTR_NAMES.get(a, a), int(use.get("amount", 1))]
		_:
			text = str(use.get("text", "服下丹药。"))
	p.pill_toxicity = clampf(p.pill_toxicity + tox, 0.0, 100.0)
	return text


## 炼化灵物所得修为（与灵根同属性的灵物加成）
static func refine_value(p: PlayerData, item_id: String) -> float:
	var d := DB.item(item_id)
	var ref: Dictionary = d.get("refine", {})
	var v := float(ref.get("exp", 0))
	var e := str(ref.get("element", d.get("element", "")))
	if Elem.is_valid(e):
		v *= 0.6 + 0.8 * p.root_pct(e)
	return v


## 战斗感悟：击败对手获得修为。越阶战斗收益更高
static func combat_insight(p: PlayerData, stats: Dictionary, foe_realm: int, foe_stage: int, sparring: bool = false) -> float:
	var r := DB.realm(p.realm)
	var base := float(r.get("cult_rate", 10.0)) * 2.0
	var diff := (foe_realm - p.realm) * 4 + (foe_stage - p.stage) * 0.5
	var mult := clampf(1.0 + diff * 0.25, 0.1, 4.0)
	if sparring:
		mult *= 1.5
	return base * mult * float(stats.get("insight_gain", 1.0))


## 时间流逝对身体状态的影响（天）
static func pass_days(p: PlayerData, days: float) -> void:
	p.age_days += days
	p.injury_days = maxf(p.injury_days - days, 0.0)
	p.pill_toxicity = maxf(p.pill_toxicity - days * 0.8, 0.0)


static func lifespan_years(p: PlayerData) -> int:
	var years := float(DB.realm(p.realm).get("lifespan", 100))
	for tid in p.talents:
		if (DB.talent(tid).get("flags", []) as Array).has("longevity"):
			years *= 1.2
	return int(years)


## 洞府聚灵阵倍率
static func home_formation_mult() -> float:
	var home = GS.world.get("home", {})
	var fv = home.get("formation", {}) if home is Dictionary else {}
	if not fv is Dictionary:
		return 1.0
	var f: Dictionary = fv
	if f.is_empty() or int(f.get("until_day", -1)) < GS.day_index():
		return 1.0
	return float(f.get("mult", 1.0))


## 闭关：跳过 hours 小时，获得修为；可能顿悟或遭遇心魔。返回 {exp, text, events[]}
static func seclude(p: PlayerData, stats: Dictionary, hours: float, location: String, rng: RandomNumberGenerator) -> Dictionary:
	var rate := rate_per_hour(p, stats, location)
	var gain := rate * hours
	var events: Array[String] = []
	var days := hours / 24.0
	var heart_demon := false
	for tid in p.talents:
		if (DB.talent(tid).get("flags", []) as Array).has("heart_demon"):
			heart_demon = true
	# 顿悟：闭关越久越可能
	if rng.randf() < clampf(days / 60.0, 0.02, 0.5) * (1.0 + float(stats.get("insight_gain", 1.0)) * 0.2):
		var bonus := gain * rng.randf_range(0.3, 0.8)
		gain += bonus
		events.append("闭关中灵光一闪，你有所顿悟！额外修为 +%d" % int(bonus))
	# 心魔：长时间闭关、丹毒深重或心魔体质
	var demon_chance := clampf(days / 365.0 * 0.3 + p.pill_toxicity / 400.0, 0.0, 0.4)
	if heart_demon:
		demon_chance = demon_chance * 2.0 + 0.05
	if days >= 7.0 and rng.randf() < demon_chance:
		var loss := gain * rng.randf_range(0.3, 0.6)
		gain -= loss
		p.injury_days = maxf(p.injury_days, days * 0.2 + 5.0)
		events.append("心魔作祟，走火入魔！修为折损 %d，受了内伤。" % int(loss))
	var ups := add_exp(p, gain, "seclusion")
	if p.main_technique != "":
		GS.add_technique_xp(p.main_technique, hours)
	GS.advance_time(hours)
	var text := "闭关 %s，修为 +%d。" % [_duration_text(hours), int(gain)]
	if ups > 0:
		text += "境界提升至%s。" % DB.realm_name(p.realm, p.stage)
	if at_bottleneck(p):
		text += "\n修为已至瓶颈，需要突破。"
	return {"exp": gain, "text": text, "events": events}


static func _duration_text(hours: float) -> String:
	var days := int(round(hours / 24.0))
	if days >= 360:
		return "%d 年" % int(days / 360)
	if days >= 30:
		return "%d 月" % int(days / 30)
	return "%d 日" % maxi(days, 1)
