class_name OverworldGameplay
extends Node
## 大地图玩法层：把世界（地形/建筑/标记点）与玩家、NPC、遭遇、交互点连接起来。
## overworld.gd 在世界构建完成后调用 start(overworld, spawn_pos)。
##
## 依赖世界模块提供：
##   - Marker3D 标记点（名字见下方 MARKER_*，或在 "poi_marker" 组中，meta: sect_id / realm_id）
##   - 可选：overworld.set_focus(node)、WorldMap.pois()

const SPAWN_RADIUS := 110.0
const DESPAWN_RADIUS := 160.0
const ROLE_MARKERS := {
	"sect_master": "npc_master", "sect_teacher": "npc_teacher", "sect_steward": "npc_steward", "sect_senior": "npc_senior",
}

var overworld: Node3D
var session: GameSession
var director: EncounterDirector
var player: HumanoidActor
var _markers_done: Dictionary = {}
var _npc_actors: Dictionary = {}     ## npc_id -> HumanoidActor
var _anchors: Dictionary = {}        ## npc_id -> Vector3
var _scan_t: float = 0.0
var _spawn_t: float = 0.0
var _home_pos: Vector3 = Vector3.INF
var _sect_pos: Dictionary = {}       ## sect_id -> Vector3（宗门中心）
var _town_pos: Vector3 = Vector3.INF
var _respawning: bool = false


func start(ow: Node3D, spawn_pos: Vector3) -> void:
	overworld = ow
	session = GameSession.new()
	session.name = "Session"
	add_child(session)
	session.start(ow, spawn_pos)
	player = session.player
	if ow.has_method("set_focus"):
		ow.call("set_focus", player)
	director = EncounterDirector.new()
	director.name = "Encounters"
	director.world = ow
	director.player = player
	add_child(director)
	Events.actor_died.connect(_on_actor_died)
	session.player_died.connect(_on_player_died)
	Events.inventory_changed.connect(_convert_stones)
	GS.in_realm = false
	_read_pois()
	_scan_markers()
	if Audio.has_method("play_music"):
		Audio.call("play_music", "music_overworld")


func _exit_tree() -> void:
	if Events.actor_died.is_connected(_on_actor_died):
		Events.actor_died.disconnect(_on_actor_died)
	if Events.inventory_changed.is_connected(_convert_stones):
		Events.inventory_changed.disconnect(_convert_stones)


func _read_pois() -> void:
	if not ClassDB.class_exists("WorldMap") and not _has_global_class("WorldMap"):
		return
	var wm: Variant = load(_global_class_path("WorldMap"))
	if wm == null:
		return
	var pois: Array = wm.call("pois")
	for p in pois:
		var t := str(p.get("type", ""))
		var pos: Vector3 = p.get("pos", Vector3.ZERO)
		match t:
			"sect":
				_sect_pos[str(p.get("sect_id", p.get("id", "")))] = pos
			"town":
				_town_pos = pos
			"home":
				_home_pos = pos


static func _has_global_class(cls: String) -> bool:
	return _global_class_path(cls) != ""


static func _global_class_path(cls: String) -> String:
	for info in ProjectSettings.get_global_class_list():
		if info["class"] == cls:
			return info["path"]
	return ""


# ================================================================ 每帧

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	GS.overworld_position = player.global_position if player.combatant.alive else GS.overworld_position
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 1.5
		_scan_markers()
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = 1.0
		_update_npcs()
		_update_location()


func _update_location() -> void:
	var p := player.global_position
	var loc := "wild"
	if _home_pos != Vector3.INF and p.distance_to(_home_pos) < 18.0:
		loc = "home"
	elif GS.player.sect != "" and _sect_pos.has(GS.player.sect) and p.distance_to(_sect_pos[GS.player.sect]) < 60.0:
		loc = "sect"
	if loc != GS.location:
		GS.location = loc
		var names := {"home": "回到洞府（修炼效率 ×1.5）", "sect": "进入宗门（修炼效率 ×2）"}
		if names.has(loc):
			Events.notify.emit(names[loc], "info")


# ================================================================ 标记点 → 交互

func _scan_markers() -> void:
	var nodes: Array[Node] = []
	for n in get_tree().get_nodes_in_group("poi_marker"):
		nodes.append(n)
	for n in overworld.find_children("*", "Marker3D", true, false):
		if not nodes.has(n):
			nodes.append(n)
	for n in nodes:
		var m := n as Node3D
		if m == null or _markers_done.has(m.get_instance_id()):
			continue
		_markers_done[m.get_instance_id()] = true
		_setup_marker(m)


func _setup_marker(m: Node3D) -> void:
	var nm := String(m.name)
	var sect := str(m.get_meta("sect_id", ""))
	if nm.begins_with("home_"):
		_home_pos = m.global_position if nm == "home_cushion" else (_home_pos if _home_pos != Vector3.INF else m.global_position)
	match nm:
		"home_cushion":
			MarkerInteract.create(m, "打坐 / 闭关（洞府）", func(_a: Node3D) -> void:
				Events.open_panel.emit("cultivation", {"location": "home"}))
		"home_stash":
			MarkerInteract.create(m, "洞府仓库", func(_a: Node3D) -> void:
				Events.open_panel.emit("inventory", {"other": GS.player.stash, "other_title": "洞府仓库"}))
		"home_furnace":
			MarkerInteract.create(m, "丹炉与器台（生产）", _open_crafting)
		"home_field":
			MarkerInteract.create(m, "灵田（灵植）", func(_a: Node3D) -> void:
				Events.open_panel.emit("craft", {"profession": "herbalism", "title": "灵田"}))
		"realm_portal":
			var rid := str(m.get_meta("realm_id", "herb_valley"))
			MarkerInteract.create(m, "秘境入口：%s" % DB.secret_realms.get(rid, {}).get("name", rid), _portal_dialog.bind(rid, m), 5.0)
		"mission_board":
			if sect != "":
				MarkerInteract.create(m, "%s任务堂" % DB.sect(sect).get("name", ""), func(_a: Node3D) -> void: _sect_board(sect))
		"shop":
			if sect != "":
				MarkerInteract.create(m, "%s宝库" % DB.sect(sect).get("name", ""), func(_a: Node3D) -> void: _sect_shop(sect))
		"cultivation_room":
			if sect != "":
				MarkerInteract.create(m, "%s闭关室" % DB.sect(sect).get("name", ""), func(_a: Node3D) -> void: _cult_room(sect))
		"town_board":
			MarkerInteract.create(m, "坊市告示", _town_board)
	if nm == "sect_gate" and sect != "":
		_sect_pos[sect] = m.global_position
	if nm == "town_center":
		_town_pos = m.global_position
	# NPC 锚点
	if sect != "":
		for role in ROLE_MARKERS:
			if ROLE_MARKERS[role] == nm:
				var id := NpcSystem.by_role(sect, role)
				if id != "":
					_anchors[id] = m.global_position
		if nm == "sect_gate" or nm == "npc_senior":
			var i := 0
			for id in NpcSystem.at_poi(sect):
				if str(NpcSystem.get_npc(id).get("role", "")) == "sect_disciple" and not _anchors.has(id):
					_anchors[id] = m.global_position + Vector3(4.0 + i * 2.0, 0, 3.0 - i * 2.0)
					i += 1
	if nm.begins_with("npc_merchant_"):
		var idx := int(nm.substr(13)) - 1
		var merchants: Array[String] = []
		for id in NpcSystem.at_poi("town"):
			if str(NpcSystem.get_npc(id).get("role", "")) == "merchant":
				merchants.append(id)
		if idx >= 0 and idx < merchants.size():
			_anchors[merchants[idx]] = m.global_position
	if nm == "town_center":
		var j := 0
		for id in NpcSystem.at_poi("town"):
			if str(NpcSystem.get_npc(id).get("role", "")) == "wanderer":
				var ang := TAU * j / 5.0
				_anchors[id] = m.global_position + Vector3(cos(ang), 0, sin(ang)) * 9.0
				j += 1


# ================================================================ NPC 生成 / 回收

func _update_npcs() -> void:
	var pp := player.global_position
	for id in _anchors:
		var rec := NpcSystem.get_npc(id)
		if rec.is_empty() or not rec.get("alive", true):
			continue
		var anchor: Vector3 = _anchors[id]
		var d := Vector2(anchor.x - pp.x, anchor.z - pp.z).length()
		var a: HumanoidActor = _npc_actors.get(id, null)
		if a != null and not is_instance_valid(a):
			_npc_actors.erase(id)
			a = null
		if a == null and d < SPAWN_RADIUS:
			_spawn_npc(id, anchor)
		elif a != null and d > DESPAWN_RADIUS and a.combatant.alive and a.action == "":
			NpcSystem.save_pd(id)
			a.queue_free()
			_npc_actors.erase(id)


func _spawn_npc(id: String, anchor: Vector3) -> void:
	var pd := NpcSystem.pd_of(id)
	if pd == null:
		return
	var rec := NpcSystem.get_npc(id)
	var pos := anchor
	var hit := CombatUtil.ray_world(anchor + Vector3.UP * 6.0, anchor + Vector3.DOWN * 30.0)
	if not hit.is_empty():
		pos = hit["position"] + Vector3.UP * 0.1
	var sect := str(rec.get("sect", ""))
	var faction := Factions.sect_faction(sect) if sect != "" else "neutral"
	var a := ActorFactory.spawn_cultivator(overworld, pd, pos, faction, str(rec.get("personality", "balanced")), true)
	var ai := a.controller as CultivatorAI
	ai.wander_radius = 3.0 if str(rec.get("role", "")) in ["sect_master", "sect_teacher", "sect_steward", "merchant"] else 8.0
	NpcInteract.attach(a, id)
	var bond := str(rec.get("bond", ""))
	if bond == "enemy":
		a.combatant.add_grudge(player.combatant)
		ai.passive = false
	_npc_actors[id] = a


# ================================================================ 交互动作

func _open_crafting(_a: Node3D) -> void:
	var opts: Array = []
	for prof in ["alchemy", "forging", "talisman", "formation"]:
		var nm: String = PlayerData.PROFESSION_NAMES[prof]
		opts.append({"text": "%s（%d 级）" % [nm, GS.player.profession_level(prof)], "callback": _craft.bind(prof, nm)})
	opts.append({"text": "离开", "callback": func() -> void: Events.close_panels.emit()})
	Events.open_panel.emit("dialogue", {"name": "洞府", "title": "生产", "text": "丹炉温热，器台上摆着锤錾与符纸。你想做些什么？", "options": opts})


func _craft(prof: String, nm: String) -> void:
	Events.open_panel.emit("craft", {"profession": prof, "title": nm})


func _portal_dialog(_a: Node3D, rid: String, marker: Node3D) -> void:
	var d: Dictionary = DB.secret_realms.get(rid, {})
	var cost := int(d.get("entry_cost", 0))
	var min_realm := int(d.get("min_realm", 0))
	var text := "%s\n\n推荐境界：%s以上 · 时限 %d 分钟 · 入场 %d 灵石\n死亡将失去储物袋中的全部物品（本命空间除外）。" % [
		d.get("desc", ""), DB.realm_name(min_realm, 0), int(d.get("time_limit", 600)) / 60, cost]
	var warn := GS.player.realm < min_realm
	Events.open_panel.emit("dialogue", {"name": str(d.get("name", rid)), "title": "秘境", "text": text, "options": [
		{"text": "进入秘境" + ("（境界不足，凶险万分）" if warn else ""), "callback": _enter_realm.bind(rid, cost, marker.global_position), "disabled": GS.player.spirit_stones < cost},
		{"text": "离开", "callback": func() -> void: Events.close_panels.emit()},
	]})


func _enter_realm(rid: String, cost: int, portal_pos: Vector3) -> void:
	if cost > 0 and not GS.spend_stones(cost):
		return
	Events.close_panels.emit()
	var back := portal_pos + Vector3(3.0, 1.0, 3.0)
	GS.overworld_position = back
	Scenes.goto_realm({"realm_id": rid, "seed": randi(), "return_pos": back})


func _sect_board(sect: String) -> void:
	var steward := NpcSystem.by_role(sect, "sect_steward")
	var a: HumanoidActor = _npc_actors.get(steward, null)
	if a != null and is_instance_valid(a):
		var it := a.get_node_or_null("Interact") as NpcInteract
		if it != null:
			it._missions(sect)
			return
	Events.notify.emit("执事不在，稍后再来", "info")


func _sect_shop(sect: String) -> void:
	var steward := NpcSystem.by_role(sect, "sect_steward")
	var a: HumanoidActor = _npc_actors.get(steward, null)
	if a != null and is_instance_valid(a):
		var it := a.get_node_or_null("Interact") as NpcInteract
		if it != null:
			it._sect_shop(sect)


func _cult_room(sect: String) -> void:
	if GS.player.sect != sect:
		Events.notify.emit("闭关室只对本门弟子开放", "warn")
		return
	Events.open_panel.emit("cultivation", {"location": "sect"})


func _town_board(_a: Node3D) -> void:
	var rumors: Array = DB.dialogue.get("rumors", ["近日青州风平浪静。"])
	var lines: PackedStringArray = []
	var rng := RandomNumberGenerator.new()
	rng.seed = GS.day_index()
	for i in mini(3, rumors.size()):
		lines.append("· " + str(rumors[rng.randi() % rumors.size()]))
	Events.open_panel.emit("dialogue", {"name": "坊市告示", "title": GS.date_text(), "text": "\n".join(lines), "options": [
		{"text": "离开", "callback": func() -> void: Events.close_panels.emit()}]})


# ================================================================ 事件

func _on_actor_died(actor: Node, killer: Node) -> void:
	CombatRewards.on_actor_died(actor, killer)
	for id in _npc_actors.keys():
		if _npc_actors[id] == actor:
			_npc_actors.erase(id)


func _convert_stones() -> void:
	var n := GS.player.bag.count_of("spirit_stone")
	if n > 0:
		GS.player.bag.take("spirit_stone", n)
		GS.player.spirit_stones += n
		Events.notify.emit("灵石 +%d" % n, "loot")


func _on_player_died() -> void:
	if _respawning:
		return
	_respawning = true
	var lost := int(GS.player.spirit_stones * 0.1)
	GS.player.spirit_stones -= lost
	GS.player.injury_days = maxf(GS.player.injury_days, 10.0)
	Events.notify.emit("你身受重创，昏死过去……（遗失 %d 灵石，内伤 10 日）" % lost, "bad")
	await get_tree().create_timer(3.0).timeout
	GS.advance_time(24.0)
	var pos: Vector3 = _home_pos if _home_pos != Vector3.INF else (overworld.call("get_spawn_position") if overworld.has_method("get_spawn_position") else Vector3(0, 30, 0))
	player.queue_free()
	session.camera.queue_free()
	session.hud.queue_free()
	var r := ActorFactory.spawn_player(overworld, pos + Vector3.UP)
	player = r["actor"]
	session.player = player
	session.camera = r["camera"]
	session.controller = r["controller"]
	session.hud = CombatHUD.new()
	session.add_child(session.hud)
	session.hud.bind(player, session.camera)
	player.died.connect(session._on_player_died)
	player.combatant.hp = player.combatant.stat("max_hp") * 0.3
	director.player = player
	if overworld.has_method("set_focus"):
		overworld.call("set_focus", player)
	_respawning = false
