class_name NpcInteract
extends Node3D
## 挂在 NPC 修士身上的交互点：[F] 交谈 → 对话菜单（交谈、赠礼、切磋、请教、交易、结交、宗门事务、袭杀）。

var actor: HumanoidActor
var npc_id: String = ""
var interact_radius: float = 3.2


static func attach(a: HumanoidActor, id: String) -> NpcInteract:
	var n := NpcInteract.new()
	n.actor = a
	n.npc_id = id
	n.name = "Interact"
	a.add_child(n)
	n.position = Vector3(0, 1.0, 0)
	a.combatant.npc_id = id
	return n


func _ready() -> void:
	add_to_group("interactable")


func can_interact(_who: Node3D) -> bool:
	return actor != null and actor.combatant.alive and not _hostile_to_player()


func interact_prompt() -> String:
	return "与%s交谈" % actor.combatant.display_name


func _hostile_to_player() -> bool:
	var p := get_tree().get_first_node_in_group("player")
	var pc := CombatUtil.combatant_of(p)
	return pc != null and actor.combatant.is_hostile_to(pc)


func interact(_who: Node3D) -> void:
	var ai := actor.controller as CultivatorAI
	if ai != null:
		ai.talk_to(get_tree().get_first_node_in_group("player") as Node3D)
	open_main(NpcSystem.chat(npc_id))


func _end_talk() -> void:
	var ai := actor.controller as CultivatorAI if is_instance_valid(actor) else null
	if ai != null and ai.state == "talk":
		ai.end_talk()


func _rec() -> Dictionary:
	return NpcSystem.get_npc(npc_id)


func _dialog(text: String, options: Array) -> void:
	var rec := _rec()
	var title := "%s · %s · %s" % [rec.get("title", ""), DB.realm_name(actor.combatant.realm, actor.combatant.stage), NpcSystem.bond_name(npc_id)]
	title += " · 好感 %d" % int(rec.get("favor", 0))
	Events.open_panel.emit("dialogue", {
		"name": actor.combatant.display_name, "title": title, "text": text, "options": options,
		"portrait_appearance": actor.pd.appearance,
	})


func _opt(text: String, cb: Callable, disabled: bool = false, hint: String = "") -> Dictionary:
	return {"text": text, "callback": cb, "disabled": disabled, "hint": hint}


# ================================================================ 主菜单

func open_main(text: String) -> void:
	var rec := _rec()
	var role := str(rec.get("role", "wanderer"))
	var favor := int(rec.get("favor", 0))
	var opts: Array = []
	opts.append(_opt("闲谈", _chat))
	# 宗门事务
	var sect := str(rec.get("sect", ""))
	if sect != "":
		match role:
			"sect_master":
				if GS.player.sect == "":
					var why := SectSystem.join_block_reason(sect)
					opts.append(_opt("恳请拜入%s" % DB.sect(sect).get("name", ""), _join.bind(sect), why != "", why))
				elif GS.player.sect == sect:
					opts.append(_opt("请教晋升之事", _promotion_talk))
					opts.append(_opt("叛出师门", _confirm_leave))
			"sect_teacher":
				opts.append(_opt("藏经阁（学习功法法诀）", _library.bind(sect), GS.player.sect != sect, "需为本门弟子"))
			"sect_steward":
				opts.append(_opt("任务堂", _missions.bind(sect), GS.player.sect != sect, "需为本门弟子"))
				opts.append(_opt("宗门宝库（贡献兑换）", _sect_shop.bind(sect), GS.player.sect != sect, "需为本门弟子"))
	if role == "merchant":
		opts.append(_opt("交易", _trade))
	opts.append(_opt("赠礼", _gift_menu))
	opts.append(_opt("切磋一番", _spar, GS.day_index() == int(rec.get("last_spar_day", -99)), "今日已切磋过"))
	opts.append(_opt("请教修行", _guidance))
	var bond := str(rec.get("bond", ""))
	if bond == "confidant":
		opts.append(_opt("结为道侣", _bond.bind("lover")))
	if favor >= 60 and actor.combatant.realm > GS.player.realm and bond not in ["master", "lover"]:
		opts.append(_opt("拜师", _bond.bind("master")))
	opts.append(_opt("袭杀此人（夺宝）", _confirm_attack))
	opts.append(_opt("告辞", _end_talk))
	_dialog(text, opts)


func _chat() -> void:
	open_main(NpcSystem.chat(npc_id))


func _guidance() -> void:
	open_main(NpcSystem.ask_guidance(npc_id))


func _bond(kind: String) -> void:
	open_main(NpcSystem.try_bond(npc_id, kind))


# ================================================================ 宗门

func _promotion_talk() -> void:
	SectSystem.check_promotion()
	var req := SectSystem.next_rank_requirement()
	var tail := ("\n" + req) if req != "" else "\n你已是本门真传，望你光大门楣。"
	open_main("你如今是本门%s。%s" % [SectSystem.player_rank_name(), tail])


func _do_leave() -> void:
	SectSystem.leave()
	NpcSystem.change_favor(npc_id, -40.0, "叛出师门")
	open_main("……好自为之。")


func _back() -> void:
	open_main("还有何事？")


func _learn(e: Dictionary, sect: String) -> void:
	SectSystem.learn_entry(e)
	_library(sect)


func _turn_in(m: Dictionary, sect: String) -> void:
	SectSystem.turn_in(m)
	_missions(sect)


func _accept(m: Dictionary, sect: String) -> void:
	SectSystem.accept(m)
	_missions(sect)


func _join(sect: String) -> void:
	if SectSystem.join(sect):
		open_main("好！自今日起，你便是我%s弟子。去任务堂与藏经阁看看吧。" % DB.sect(sect).get("name", ""))
	else:
		open_main(SectSystem.join_block_reason(sect))


func _confirm_leave() -> void:
	_dialog("叛出师门将令你在本门声名扫地，确定吗？", [
		_opt("心意已决", _do_leave),
		_opt("再想想", _back),
	])


func _library(sect: String) -> void:
	var opts: Array = []
	for e in SectSystem.library_entries(sect):
		var nm: String = DB.technique(e["id"]).get("name", "") if e["kind"] == "technique" else DB.spell(e["id"]).get("name", "")
		var label := ("功法《%s》" if e["kind"] == "technique" else "法诀【%s】") % nm
		var hint := ""
		if e["learned"]:
			hint = "已习得"
		elif e["locked"]:
			hint = "需%s" % SectSystem.rank_name(sect, int(e["rank"]))
		opts.append(_opt("%s — %d 贡献" % [label, int(e["cost"])], _learn.bind(e, sect), e["learned"] or e["locked"], hint))
	opts.append(_opt("返回", _back))
	_dialog("藏经阁中典籍浩如烟海。你现有贡献 %d。" % SectSystem.contribution(), opts)


func _sect_shop(sect: String) -> void:
	var entries: Array = []
	for e in SectSystem.shop_entries(sect):
		var ent: Dictionary = e.duplicate()
		ent["can_buy"] = func(_x: Dictionary) -> bool: return not ent["locked"] and SectSystem.contribution() >= int(ent["price"])
		ent["on_buy"] = func(_x: Dictionary) -> void: SectSystem.buy_entry(ent)
		entries.append(ent)
	Events.open_panel.emit("shop", {"title": "%s宝库（贡献 %d）" % [DB.sect(sect).get("name", ""), SectSystem.contribution()], "entries": entries, "sell": false})


func _missions(sect: String) -> void:
	var opts: Array = []
	for m in SectSystem.accepted():
		if m.get("sect", "") != sect:
			continue
		var prog := "%d/%d" % [int(m["progress"]), int(m["count"])] if m["type"] != "deliver" else "持有 %d/%d" % [GS.player.bag.count_of(str(m.get("item", ""))), int(m["count"])]
		opts.append(_opt("交付：%s（%s）" % [m["name"], prog], _turn_in.bind(m, sect), not SectSystem.can_turn_in(m), "尚未完成"))
	for m in SectSystem.board(sect):
		var r: Dictionary = m.get("reward", {})
		var locked := GS.player.sect_rank < int(m.get("min_rank", 0))
		opts.append(_opt("接取：%s — %s（贡献 %d · 灵石 %d）" % [m["name"], m["text"], int(r.get("contribution", 0)), int(r.get("stones", 0))], _accept.bind(m, sect), locked, "阶位不足" if locked else ""))
	opts.append(_opt("返回", _back))
	_dialog("任务堂的玉壁上刻着近日的差事。（贡献 %d，声望 %d）" % [SectSystem.contribution(), int(GS.player.reputation.get(sect, 0))], opts)


# ================================================================ 交易 / 赠礼

func _trade() -> void:
	var rec := _rec()
	var stock: Array = MerchantStock.stock(str(rec.get("shop", "misc")), npc_id)
	var entries: Array = []
	for s in stock:
		var ent := {"item": s["item"], "price": int(s["price"]), "currency": "灵石"}
		ent["can_buy"] = func(_x: Dictionary) -> bool: return GS.player.spirit_stones >= int(ent["price"])
		ent["on_buy"] = _buy.bind(ent)
		entries.append(ent)
	Events.open_panel.emit("shop", {"title": "%s · %s" % [rec.get("title", ""), actor.combatant.display_name], "entries": entries, "sell": true})


func _buy(_x: Dictionary, ent: Dictionary) -> void:
	if GS.spend_stones(int(ent["price"])):
		GS.give_item(str(ent["item"]), 1)
		NpcSystem.change_favor(npc_id, 0.5)


func _gift_menu() -> void:
	var items := GS.player.bag.items()
	items.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool: return a.total_value() > b.total_value())
	var opts: Array = []
	for i in mini(items.size(), 7):
		var it: ItemInstance = items[i]
		opts.append(_opt("赠送 %s ×%d（价值 %d）" % [it.display_name(), it.count, it.total_value()], _give.bind(it)))
	opts.append(_opt("赠送 50 灵石", _give_stones, GS.player.spirit_stones < 50))
	opts.append(_opt("算了", _back))
	_dialog("你打算赠送什么？", opts)


func _give(it: ItemInstance) -> void:
	var one := it
	if it.count > 1:
		one = it.split(1)
	else:
		GS.player.bag.remove_item(it)
	Events.inventory_changed.emit()
	open_main(NpcSystem.gift(npc_id, one))


func _give_stones() -> void:
	if GS.spend_stones(50):
		open_main(NpcSystem.gift(npc_id, ItemInstance.create("spirit_stone", 50)))


# ================================================================ 切磋 / 袭杀

func _spar() -> void:
	var rec := _rec()
	rec["last_spar_day"] = GS.day_index()
	var pl := get_tree().get_first_node_in_group("player") as HumanoidActor
	if pl == null:
		return
	Events.close_panels.emit()
	EncounterDirector.start_spar(pl, actor)


func _confirm_attack() -> void:
	_dialog("（你暗暗运转灵力，杀意渐起……）\n袭杀修士会增加业力，若被旁人看见，还会结下更多仇怨。", [
		_opt("动手！", _attack),
		_opt("收敛杀意", _back),
	])


func _attack() -> void:
	Events.close_panels.emit()
	var pl := get_tree().get_first_node_in_group("player") as HumanoidActor
	if pl == null:
		return
	var rec := _rec()
	rec["hostile_first"] = false
	actor.combatant.add_grudge(pl.combatant)
	pl.combatant.add_grudge(actor.combatant)
	pl.lock_target = actor
	var ai := actor.controller as CultivatorAI
	if ai != null:
		ai.engage(pl)
	NpcSystem.change_favor(npc_id, -100.0, "遭你袭杀")
	var lines: Array = DB.dialogue.get("attacked", ["找死！"])
	Events.notify.emit("%s：「%s」" % [actor.combatant.display_name, lines[randi() % lines.size()]], "bad")
	actor.update_nameplate()
