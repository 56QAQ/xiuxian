class_name EncounterDirector
extends Node
## 大地图随机遭遇：同道切磋、劫修拦路、天材地宝出世、妖兽袭击、遇险求救。
## 由 OverworldGameplay 创建。遭遇按 data/encounters.json 权重抽取，受气运与天赋影响。

var world: Node3D
var player: HumanoidActor
var cooldown: float = 75.0
var active: Array[Node] = []
var rng := RandomNumberGenerator.new()
var _pending_talk: Dictionary = {}   ## actor -> {kind, cb}
var enabled: bool = true


func _ready() -> void:
	rng.randomize()


func _process(delta: float) -> void:
	if not enabled or player == null or not is_instance_valid(player) or not player.combatant.alive or GS.in_realm:
		return
	_check_approach()
	active = active.filter(func(n: Node) -> bool: return is_instance_valid(n))
	cooldown -= delta
	if cooldown > 0.0:
		return
	var hunted := GS.player.has_talent("hunted")
	cooldown = rng.randf_range(80.0, 170.0) * (0.75 if hunted else 1.0)
	if active.size() > 6 or CombatUtil.nearest_hostile(player, 40.0) != null or player.action == "meditate":
		cooldown = 20.0
		return
	trigger(_pick())


func _pick() -> String:
	var total := 0.0
	var ws := {}
	for id in DB.encounters:
		var w := float(DB.encounters[id].get("w", 1.0))
		if id == "robber" and GS.player.has_talent("hunted"):
			w *= 2.5
		if id == "treasure":
			w *= 1.0 + float(GS.stats.get("luck", 0.0)) * 0.1
		ws[id] = w
		total += w
	var r := rng.randf() * total
	for id in ws:
		r -= float(ws[id])
		if r <= 0.0:
			return id
	return "spar"


func trigger(kind: String) -> void:
	match kind:
		"spar":
			_spar_approach()
		"robber":
			_robbers()
		"treasure":
			_treasure()
		"beast_attack":
			_beasts(player.global_position, 32.0)
		"rescue":
			_rescue()
	var d: Dictionary = DB.encounters.get(kind, {})
	if d.has("desc") and kind in ["treasure", "beast_attack", "rescue"]:
		Events.notify.emit(str(d["desc"]), "warn")


# ================================================================ 工具

func _ground_near(center: Vector3, dmin: float, dmax: float) -> Vector3:
	for i in 12:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(dmin, dmax)
		var p := center + Vector3(cos(ang), 0, sin(ang)) * dist
		var hit := CombatUtil.ray_world(p + Vector3.UP * 120.0, p + Vector3.DOWN * 200.0)
		if not hit.is_empty():
			var y: float = hit["position"].y
			if y > 10.0 or i > 8:
				return Vector3(p.x, y + 0.3, p.z)
	return center + Vector3(dmin, 1.0, 0)


func _spawn_npc(id: String, pos: Vector3, faction: String, personality: String = "balanced") -> HumanoidActor:
	var pd := NpcSystem.pd_of(id)
	var a := ActorFactory.spawn_cultivator(world, pd, pos, faction, personality, true)
	NpcInteract.attach(a, id)
	active.append(a)
	return a


func _check_approach() -> void:
	for a in _pending_talk.keys():
		if not is_instance_valid(a) or not (a as HumanoidActor).combatant.alive:
			_pending_talk.erase(a)
			continue
		var h := a as HumanoidActor
		if h.global_position.distance_to(player.global_position) < 5.0:
			var info: Dictionary = _pending_talk[a]
			_pending_talk.erase(a)
			var ai := h.controller as CultivatorAI
			ai.follow = null
			ai.talk_to(player)
			(info["cb"] as Callable).call()


# ================================================================ 切磋

func _spar_approach() -> void:
	var p := GS.player
	var id := NpcSystem.create_wanderer(rng, p.realm, clampi(p.stage + rng.randi_range(-1, 2), 0, 8))
	var a := _spawn_npc(id, _ground_near(player.global_position, 30.0, 40.0), "neutral")
	var ai := a.controller as CultivatorAI
	ai.follow = player
	ai.set_state("follow")
	_pending_talk[a] = {"kind": "spar", "cb": _spar_dialog.bind(a, id)}


func _spar_dialog(a: HumanoidActor, id: String) -> void:
	var lines: Array = DB.dialogue.get("spar_invite", ["道友可愿切磋一番？"])
	Events.open_panel.emit("dialogue", {
		"name": a.combatant.display_name, "title": "散修 · " + DB.realm_name(a.combatant.realm, a.combatant.stage),
		"text": str(lines[rng.randi() % lines.size()]), "portrait_appearance": a.pd.appearance,
		"options": [
			{"text": "应战（点到为止）", "callback": func() -> void: start_spar(player, a)},
			{"text": "婉拒", "callback": _decline.bind(a, id)},
		],
	})


func _decline(a: HumanoidActor, id: String) -> void:
	NpcSystem.change_favor(id, -2.0)
	if is_instance_valid(a):
		(a.controller as CultivatorAI).end_talk()


## 开始切磋：双方进入非致命对决
static func start_spar(pl: HumanoidActor, npc: HumanoidActor) -> void:
	pl.combatant.nonlethal_vs = npc.combatant
	npc.combatant.nonlethal_vs = pl.combatant
	pl.lock_target = npc
	var ai := npc.controller as CultivatorAI
	if ai != null:
		ai.passive = false
		ai.engage(pl)
	Events.close_panels.emit()
	Events.notify.emit("切磋开始！点到为止", "info")
	npc.update_nameplate()
	if not npc.yielded.is_connected(_on_npc_yield):
		npc.yielded.connect(_on_npc_yield, CONNECT_ONE_SHOT)
	if not pl.yielded.is_connected(_on_player_yield.bind(npc)):
		pl.yielded.connect(_on_player_yield.bind(npc), CONNECT_ONE_SHOT)


static func _on_npc_yield(npc: HumanoidActor, _winner: Node3D) -> void:
	var id := npc.combatant.npc_id
	var gain := Cultivation.combat_insight(GS.player, GS.stats, npc.combatant.realm, npc.combatant.stage, true)
	Cultivation.add_exp(GS.player, gain, "spar")
	GS.recompute()
	if id != "":
		NpcSystem.change_favor(id, 8.0, "与你切磋，败于你手")
	SectSystem.on_spar_won()
	var lines: Array = DB.dialogue.get("spar_win", ["道友好身手！"])
	Events.notify.emit("%s：「%s」（感悟 +%d）" % [npc.combatant.display_name, lines[randi() % lines.size()], int(gain)], "good")
	_end_spar(npc)


static func _on_player_yield(_pl: HumanoidActor, _winner: Node3D, npc: HumanoidActor) -> void:
	if not is_instance_valid(npc):
		return
	var id := npc.combatant.npc_id
	var gain := Cultivation.combat_insight(GS.player, GS.stats, npc.combatant.realm, npc.combatant.stage, true) * 0.5
	Cultivation.add_exp(GS.player, gain, "spar")
	GS.recompute()
	if id != "":
		NpcSystem.change_favor(id, 3.0, "与你切磋，胜了一招")
	var lines: Array = DB.dialogue.get("spar_lose", ["承让了。"])
	Events.notify.emit("%s：「%s」（感悟 +%d）" % [npc.combatant.display_name, lines[randi() % lines.size()], int(gain)], "info")
	_end_spar(npc)


static func _end_spar(npc: HumanoidActor) -> void:
	var pl := npc.get_tree().get_first_node_in_group("player") as HumanoidActor
	if pl != null:
		pl.combatant.nonlethal_vs = null
		if pl.lock_target == npc:
			pl.lock_target = null
		pl.combatant.grudges.erase(npc.combatant.get_instance_id())
		npc.combatant.grudges.erase(pl.combatant.get_instance_id())
	npc.combatant.nonlethal_vs = null
	var ai := npc.controller as CultivatorAI
	if ai != null:
		ai.passive = true
		ai.target = null
		npc.lock_target = null
		ai.set_state("wander")
		ai.home = npc.global_position
	npc.update_nameplate()


# ================================================================ 劫修

func _robbers() -> void:
	var p := GS.player
	var n := 1 + (1 if rng.randf() < 0.5 else 0) + (1 if p.stage >= 5 and rng.randf() < 0.4 else 0)
	var center := _ground_near(player.global_position, 28.0, 36.0)
	var tpl_id := "robber" if DB.enemies.has("robber") else "xuesha_disciple"
	var group: Array[HumanoidActor] = []
	for i in n:
		var tpl := DB.enemy(tpl_id)
		var pd := ActorFactory.make_cultivator_pd(tpl, rng, {"realm": p.realm, "stage": clampi(p.stage + rng.randi_range(-2, 1), 0, 8)})
		pd.name = NameGen.evil(rng, pd.gender)
		pd.spirit_stones = rng.randi_range(20, 90)
		var a := ActorFactory.spawn_cultivator(world, pd, center + Vector3(i * 2.0, 0, 0), "neutral", "aggressive", true)
		a.set_meta("template_id", tpl_id)
		var ai := a.controller as CultivatorAI
		ai.follow = player
		ai.set_state("follow")
		group.append(a)
		active.append(a)
	_pending_talk[group[0]] = {"kind": "robber", "cb": _robber_dialog.bind(group)}


func _robber_dialog(group: Array[HumanoidActor]) -> void:
	var leader := group[0]
	var demand := maxi(50, int(GS.player.spirit_stones * 0.3))
	var lines: Array = DB.dialogue.get("robber_demand", ["交出储物袋！"])
	Events.open_panel.emit("dialogue", {
		"name": leader.combatant.display_name, "title": "劫修 · " + DB.realm_name(leader.combatant.realm, leader.combatant.stage),
		"text": "%s\n（对方索要 %d 灵石）" % [lines[rng.randi() % lines.size()], demand], "portrait_appearance": leader.pd.appearance,
		"options": [
			{"text": "破财消灾（交出 %d 灵石）" % demand, "callback": _robber_pay.bind(group, demand), "disabled": GS.player.spirit_stones < demand},
			{"text": "想抢我？先问过我的剑！", "callback": _robber_fight.bind(group)},
			{"text": "（瞬步遁走）", "callback": _robber_flee.bind(group)},
		],
	})


func _robber_pay(group: Array[HumanoidActor], demand: int) -> void:
	GS.spend_stones(demand)
	var lines: Array = DB.dialogue.get("robber_paid", ["算你识相。"])
	Events.notify.emit("劫修：「%s」" % lines[rng.randi() % lines.size()], "warn")
	for a in group:
		if is_instance_valid(a):
			var ai := a.controller as CultivatorAI
			ai.follow = null
			ai.end_talk()
			ai.home = a.global_position + Vector3(rng.randf_range(-60, 60), 0, rng.randf_range(-60, 60))


func _robber_fight(group: Array[HumanoidActor]) -> void:
	for a in group:
		if is_instance_valid(a):
			a.combatant.faction = "robber"
			var ai := a.controller as CultivatorAI
			ai.follow = null
			ai.passive = false
			ai.engage(player)
			a.update_nameplate()
	player.lock_target = group[0]
	Events.notify.emit("劫修动手了！", "bad")


func _robber_flee(group: Array[HumanoidActor]) -> void:
	_robber_fight(group)
	player.lock_target = null
	Events.notify.emit("快走！劫修追上来了", "warn")


# ================================================================ 天材地宝

func _treasure() -> void:
	var pos := _ground_near(player.global_position, 90.0, 140.0)
	var site := TreasureSite.create(world, pos, rng)
	active.append(site)
	# 闻讯而来的修士
	var p := GS.player
	for i in rng.randi_range(2, 4):
		var tpl := DB.enemy("rogue_cultivator")
		var pd := ActorFactory.make_cultivator_pd(tpl, rng, {"realm": p.realm, "stage": clampi(p.stage + rng.randi_range(-2, 2), 0, 8)})
		var sp := _ground_near(pos, 45.0, 70.0)
		var a := ActorFactory.spawn_cultivator(world, pd, sp, "neutral", ["aggressive", "balanced", "cautious"][i % 3], true)
		var ai := a.controller as CultivatorAI
		ai.home = pos
		ai.wander_radius = 6.0
		site.contenders.append(a)
		active.append(a)


# ================================================================ 妖兽

func _beasts(center: Vector3, dist: float) -> Array[BeastActor]:
	var out: Array[BeastActor] = []
	var cands: Array[String] = []
	for id in DB.enemies:
		var e: Dictionary = DB.enemies[id]
		if str(e.get("kind", "")) == "beast" and int(e.get("realm", 0)) <= GS.player.realm and float(e.get("size", 1.0)) < 1.8:
			cands.append(id)
	if cands.is_empty():
		return out
	var eid := cands[rng.randi() % cands.size()]
	var pack: Array = DB.enemy(eid).get("pack", [1, 2])
	var c := _ground_near(center, dist, dist + 8.0)
	for i in rng.randi_range(int(pack[0]), int(pack[1]) + 1):
		var b := ActorFactory.spawn_beast(world, eid, c + Vector3(rng.randf_range(-3, 3), 0.5, rng.randf_range(-3, 3)))
		out.append(b)
		active.append(b)
	return out


# ================================================================ 救援

func _rescue() -> void:
	var p := GS.player
	var id := NpcSystem.create_wanderer(rng, p.realm, clampi(p.stage - 2, 0, 8))
	var pos := _ground_near(player.global_position, 50.0, 65.0)
	var a := _spawn_npc(id, pos, "neutral", "cautious")
	var ai := a.controller as CultivatorAI
	ai.passive = false
	var beasts := _beasts(pos, 4.0)
	for b in beasts:
		b.ai.target = a
	var check := Timer.new()
	check.wait_time = 1.0
	check.autostart = true
	add_child(check)
	check.timeout.connect(_rescue_check.bind(a, id, beasts, check))


func _rescue_check(a: HumanoidActor, id: String, beasts: Array[BeastActor], timer: Timer) -> void:
	if not is_instance_valid(a) or not a.combatant.alive:
		timer.queue_free()
		return
	for b in beasts:
		if is_instance_valid(b) and b.combatant.alive:
			return
	timer.queue_free()
	NpcSystem.change_favor(id, 30.0, "被你从兽口救下")
	var reward := 30 + 40 * GS.player.realm
	GS.add_stones(reward)
	var lines: Array = DB.dialogue.get("rescued", ["多谢道友出手相救！"])
	Events.notify.emit("%s：「%s」（赠你 %d 灵石）" % [a.combatant.display_name, lines[rng.randi() % lines.size()], reward], "good")
