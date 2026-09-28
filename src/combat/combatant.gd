class_name Combatant
extends Node
## 战斗单位组件：生命 / 护体 / 灵力 / 韧性 / 状态 / 伤害结算。
## 作为子节点挂在角色身体（HumanoidActor / BeastActor）下，身体加入 "combatants" 组。

signal damaged(info: Dictionary, result: Dictionary)
signal died(killer: Combatant)
signal shield_broken
signal poise_broken
signal statuses_changed
signal yielded(winner: Combatant)   ## 切磋中认输（非致命模式生命见底）

var display_name: String = "无名"
var faction: String = "neutral"
var realm: int = 0
var stage: int = 0
var element: String = Elem.NONE
## 可选：该单位的 PlayerData（玩家与修士 NPC 有；用于五行威力倍率）
var pd: PlayerData = null
## NPC 名册 id（修士 NPC 有）
var npc_id: String = ""

var base_stats: Dictionary = Stats.DEFAULTS.duplicate()
var stats: Dictionary = Stats.DEFAULTS.duplicate()

var hp: float = 100.0
var shield: float = 0.0
var qi: float = 100.0
var poise: float = 100.0
var alive: bool = true

## 切磋（非致命）：生命不会低于 1，见底时触发 yielded
var nonlethal_vs: Combatant = null
## 私仇：对这些单位强制敌对（被攻击、劫修、袭杀等）
var grudges: Dictionary = {}   ## instance_id -> true

## id -> {stacks: float, time: float, power: float, source: WeakRef}
var statuses: Dictionary = {}
var _bind_immune: float = 0.0

var since_damage: float = 99.0
var qi_block: float = 0.0        ## >0 时灵力不回复（推进/飞行中）
var _poise_regen_delay: float = 0.0
var invuln: float = 0.0
var escape_day: int = -999   ## 元婴出窍保命（每日一次）
var last_attacker: WeakRef = null
var last_hit_dir: Vector3 = Vector3.ZERO


func body() -> Node3D:
	return get_parent() as Node3D


## 初始化属性并回满
func setup(final_stats: Dictionary, realm_idx: int, stage_idx: int, elem: String, player_data: PlayerData = null) -> void:
	base_stats = final_stats.duplicate()
	realm = realm_idx
	stage = stage_idx
	element = elem
	pd = player_data
	_recompute()
	hp = stats["max_hp"]
	shield = stats["max_shield"]
	qi = stats["max_qi"]
	poise = stats["poise"]
	alive = true


## 属性变化（装备、境界变化）时更新，保持当前资源比例
func refresh_stats(final_stats: Dictionary) -> void:
	var hp_r := hp / maxf(stats["max_hp"], 1.0)
	var qi_r := qi / maxf(stats["max_qi"], 1.0)
	base_stats = final_stats.duplicate()
	_recompute()
	hp = clampf(stats["max_hp"] * hp_r, 1.0 if alive else 0.0, stats["max_hp"])
	qi = stats["max_qi"] * qi_r
	shield = minf(shield, stats["max_shield"])


func stat(k: String) -> float:
	return float(stats.get(k, 0.0))


func hp_ratio() -> float:
	return hp / maxf(stats["max_hp"], 1.0)


# ================================================================ 资源

func spend_qi(amount: float) -> bool:
	if qi < amount:
		return false
	qi -= amount
	return true


## 持续消耗（推进、飞行）；灵力耗尽时进入枯竭
func drain_qi(amount: float) -> bool:
	qi_block = 0.45
	if qi <= amount:
		qi = 0.0
		if not has_status("qi_burnout"):
			apply_status("qi_burnout", 1.0, null)
		return false
	qi -= amount
	return true


func heal(amount: float) -> void:
	if not alive:
		return
	amount *= stat("heal_mult")
	var before := hp
	hp = minf(hp + amount, stat("max_hp"))
	_heal_accum += hp - before


## 治疗累积到一定量后广播一次（持续回春每帧都会调用 heal）
var _heal_accum: float = 0.0
var _heal_emit_t: float = 0.0


func _flush_heal(delta: float) -> void:
	_heal_emit_t -= delta
	if _heal_accum <= 0.0:
		return
	if _heal_accum >= stat("max_hp") * 0.05 or _heal_emit_t <= 0.0:
		var b := body()
		Events.hit_landed.emit({
			"pos": (b.global_position if b != null else Vector3.ZERO) + Vector3.UP * 1.6, "amount": _heal_accum,
			"crit": false, "kind": "heal", "element": Elem.WOOD, "shield": false,
			"target": b, "source": null, "killed": false, "provoked": false,
		})
		_heal_accum = 0.0
		_heal_emit_t = 0.6


func restore_qi(amount: float) -> void:
	qi = minf(qi + amount, stat("max_qi"))


func add_shield(amount: float) -> void:
	shield = minf(shield + amount, stat("max_shield") * 1.5)


# ================================================================ 敌我

func is_hostile_to(other: Combatant) -> bool:
	if other == null or other == self or not other.alive:
		return false
	if nonlethal_vs == other or other.nonlethal_vs == self:
		return true
	if grudges.has(other.get_instance_id()) or other.grudges.has(get_instance_id()):
		return true
	return Factions.hostile(faction, other.faction)


func add_grudge(other: Combatant) -> void:
	if other != null and other != self:
		grudges[other.get_instance_id()] = true


# ================================================================ 伤害

## 结算一次伤害。info 字段见 DamageCalc。返回 {damage, crit, shield_damage, hp_damage, killed, broke_shield, broke_poise}
func take_damage(info: Dictionary) -> Dictionary:
	var res := {"damage": 0.0, "crit": false, "shield_damage": 0.0, "hp_damage": 0.0, "killed": false, "broke_shield": false, "broke_poise": false}
	if not alive or invuln > 0.0:
		return res
	var src: Combatant = info.get("source", null)
	if src != null and not is_instance_valid(src):
		src = null
	var calc := DamageCalc.compute(src, self, info)
	var dmg: float = calc["damage"]
	res["crit"] = calc["crit"]
	var bypass_shield: bool = info.get("bypass_shield", false)
	if shield > 0.0 and not bypass_shield:
		var absorbed := minf(shield, dmg)
		shield -= absorbed
		res["shield_damage"] = absorbed
		dmg -= absorbed
		if shield <= 0.0:
			res["broke_shield"] = true
	if dmg > 0.0:
		hp -= dmg
		res["hp_damage"] = dmg
	res["damage"] = res["shield_damage"] + res["hp_damage"]
	since_damage = 0.0
	if src != null:
		last_attacker = weakref(src)
	if info.has("dir"):
		last_hit_dir = info["dir"]
	# 韧性
	var pd_amt := float(info.get("poise", 0.0))
	if src != null and info.get("element", "") == Elem.EARTH:
		pd_amt *= src.stat("stagger_power")
	if pd_amt > 0.0 and not has_status("stone_skin_unbreakable"):
		poise -= pd_amt
		_poise_regen_delay = 1.5
		if poise <= 0.0:
			poise = stat("poise")
			res["broke_poise"] = true
	# 状态
	var st: Dictionary = info.get("status", {})
	if not st.is_empty() and alive:
		var chance := float(st.get("chance", 1.0))
		if src != null:
			chance *= 1.0 + src.stat("status_chance")
		chance *= 1.0 - stat("status_resist")
		if randf() < chance:
			apply_status(str(st["id"]), float(st.get("stacks", 1)), src)
	# 死亡 / 认输
	if hp <= 0.0:
		if nonlethal_vs != null and (src == nonlethal_vs or src == null):
			hp = 1.0
			var winner := nonlethal_vs
			nonlethal_vs = null
			if winner != null:
				winner.nonlethal_vs = null
			yielded.emit(winner)
		elif pd != null and BuildCalc.has_perk(pd, "nascent_escape") and escape_day != GS.day_index():
			escape_day = GS.day_index()
			hp = stat("max_hp") * 0.3
			invuln = 2.0
			clear_debuffs()
			Events.notify.emit("%s 元婴出窍，护住心脉！" % display_name, "realm")
			FX.shock_sphere(body().global_position + Vector3.UP, 3.0, Color(1.0, 0.85, 0.4), 0.6)
		else:
			hp = 0.0
			res["killed"] = true
			_die(src)
	if res["broke_shield"]:
		shield_broken.emit()
	if res["broke_poise"]:
		poise_broken.emit()
	damaged.emit(info, res)
	return res


func _die(killer: Combatant) -> void:
	if not alive:
		return
	alive = false
	statuses.clear()
	statuses_changed.emit()
	died.emit(killer)
	Events.actor_died.emit(body(), killer.body() if killer != null else null)


func kill() -> void:
	hp = 0.0
	_die(null)


# ================================================================ 状态

func has_status(id: String) -> bool:
	return statuses.has(id)


func status_stacks(id: String) -> float:
	return float(statuses.get(id, {}).get("stacks", 0.0))


func is_rooted() -> bool:
	return statuses.has("rooted")


func apply_status(id: String, stacks: float, source: Combatant) -> void:
	var def := DB.status(id)
	if def.is_empty() or not alive:
		return
	var t := str(def.get("type", "debuff"))
	if t == "instant":
		# 震慑：直接削减韧性
		if id == "stagger":
			var amt := stacks * (source.stat("stagger_power") if source != null else 1.0)
			poise -= amt
			_poise_regen_delay = 1.5
			if poise <= 0.0:
				poise = stat("poise")
				poise_broken.emit()
		return
	var potency := 1.0
	var src_attack := 0.0
	if source != null:
		potency = source.stat(id + "_power") if source.stats.has(id + "_power") else 1.0
		src_attack = source.stat("attack")
	if t == "gauge":
		if _bind_immune > 0.0:
			return
		stacks *= potency
	var entry: Dictionary = statuses.get(id, {"stacks": 0.0, "time": 0.0, "power": 0.0, "source": null})
	var max_stacks := float(def.get("max_stacks", 1))
	entry["stacks"] = minf(float(entry["stacks"]) + stacks, max_stacks)
	entry["time"] = float(def.get("duration", 3.0))
	entry["power"] = maxf(float(entry["power"]), src_attack * float(def.get("dot", 0.0)) * potency)
	entry["potency"] = potency
	if source != null:
		entry["source"] = weakref(source)
	statuses[id] = entry
	if t == "gauge" and entry["stacks"] >= max_stacks:
		statuses.erase(id)
		var root_id := str(def.get("root_status", "rooted"))
		apply_status(root_id, 1.0, null)
		statuses[root_id]["time"] = float(def.get("root_duration", 1.5))
		_bind_immune = float(def.get("immune", 3.0)) + float(def.get("root_duration", 1.5))
	_recompute()
	statuses_changed.emit()


func remove_status(id: String) -> void:
	if statuses.erase(id):
		_recompute()
		statuses_changed.emit()


func clear_debuffs() -> void:
	for id in statuses.keys():
		if str(DB.status(id).get("type", "")) in ["debuff", "gauge", "control"]:
			statuses.erase(id)
	_recompute()
	statuses_changed.emit()


func _recompute() -> void:
	var s := base_stats.duplicate()
	for id in statuses:
		var def := DB.status(id)
		var mods: Dictionary = def.get("mods_per_stack", {})
		if mods.is_empty():
			continue
		var stacks := float(statuses[id]["stacks"]) * float(statuses[id].get("potency", 1.0))
		for k in mods:
			var key: String = k
			var v := float(mods[k]) * stacks
			if key.ends_with("_pct"):
				var base_k := key.substr(0, key.length() - 4)
				s[base_k] = float(s.get(base_k, 0.0)) * maxf(1.0 + v, 0.1)
			else:
				s[key] = float(s.get(key, 0.0)) + v
	# 束缚减速
	if statuses.has("bind"):
		var slow := float(statuses["bind"]["stacks"]) / 100.0 * float(DB.status("bind").get("slow", 0.5))
		s["move_speed"] = float(s["move_speed"]) * (1.0 - slow)
		s["boost_speed"] = float(s["boost_speed"]) * (1.0 - slow * 0.6)
	s["dmg_reduction"] = clampf(float(s["dmg_reduction"]), 0.0, 0.85)
	s["crit_rate"] = clampf(float(s["crit_rate"]), 0.0, 1.0)
	stats = s


# ================================================================ 每帧

func _physics_process(delta: float) -> void:
	if not alive:
		return
	since_damage += delta
	invuln = maxf(invuln - delta, 0.0)
	_bind_immune = maxf(_bind_immune - delta, 0.0)
	# 状态计时与持续伤害
	var changed := false
	var moving_fast := false
	var b := body()
	if b is CharacterBody3D:
		moving_fast = (b as CharacterBody3D).velocity.length() > 9.0
	for id in statuses.keys():
		var e: Dictionary = statuses[id]
		var def := DB.status(id)
		e["time"] = float(e["time"]) - delta
		var dot := float(e.get("power", 0.0)) * float(e["stacks"])
		if dot > 0.0:
			if id == "bleed" and moving_fast:
				dot *= float(def.get("moving_mult", 2.0))
			var src: Combatant = null
			var wr: WeakRef = e.get("source", null)
			if wr != null:
				src = wr.get_ref() as Combatant
			_dot_damage(dot * delta, id, src)
			if not alive:
				return
		var hot := float(def.get("hot", 0.0))
		if hot > 0.0:
			heal(stat("max_hp") * hot * delta)
		if float(e["time"]) <= 0.0:
			statuses.erase(id)
			changed = true
	if changed:
		_recompute()
		statuses_changed.emit()
	_flush_heal(delta)
	# 回复
	qi_block = maxf(qi_block - delta, 0.0)
	if qi_block <= 0.0:
		var qr := stat("qi_regen") * (0.4 if has_status("qi_burnout") else 1.0)
		qi = minf(qi + qr * delta, stat("max_qi"))
	if since_damage >= stat("shield_delay") and shield < stat("max_shield"):
		shield = minf(shield + stat("shield_regen") * delta, stat("max_shield"))
	if stat("hp_regen") > 0.0:
		hp = minf(hp + stat("hp_regen") * delta, stat("max_hp"))
	_poise_regen_delay -= delta
	if _poise_regen_delay <= 0.0:
		poise = minf(poise + stat("poise") * 0.35 * delta, stat("poise"))


var _dot_accum: Dictionary = {}


func _dot_damage(amount: float, status_id: String, src: Combatant) -> void:
	# 持续伤害累积到整数再结算，避免每帧都触发受击事件
	var acc := float(_dot_accum.get(status_id, 0.0)) + amount
	if acc < maxf(stat("max_hp") * 0.004, 1.0):
		_dot_accum[status_id] = acc
		return
	_dot_accum[status_id] = 0.0
	take_damage({
		"source": src, "kind": "dot", "flat": acc, "status_id": status_id,
		"bypass_shield": status_id in ["bleed", "poison"], "no_react": true,
		"element": str(DB.status(status_id).get("element", Elem.NONE)),
	})
