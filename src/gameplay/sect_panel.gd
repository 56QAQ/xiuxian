class_name SectPanel
extends PanelContainer
## 宗门 / 人脉面板（J）：宗门阶位、贡献、声望、已接任务；五宗概览；结识的修士与羁绊。
## 操作（接任务、学功法、兑换）在宗门 NPC 处进行，本面板只做信息汇总。

signal close_requested

var _tabs: TabContainer


func _ready() -> void:
	custom_minimum_size = Vector2(760, 560)
	var root := VBoxContainer.new()
	add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "宗门 · 人脉"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_build()
	Events.sect_changed.connect(_rebuild)
	Events.missions_changed.connect(_rebuild)
	Events.relation_changed.connect(func(_id: String) -> void: _rebuild())


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var cur := _tabs.current_tab
	for c in _tabs.get_children():
		c.queue_free()
	await get_tree().process_frame
	_build()
	_tabs.current_tab = clampi(cur, 0, _tabs.get_tab_count() - 1)


func _build() -> void:
	_tabs.add_child(_my_sect())
	_tabs.add_child(_all_sects())
	_tabs.add_child(_relations())


func _scroll(tab_name: String) -> Array:
	var sc := ScrollContainer.new()
	sc.name = tab_name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	return [sc, v]


func _label(parent: Node, text: String, size: int = 17, color: Color = Color(0.92, 0.9, 0.85)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _my_sect() -> Control:
	var r := _scroll("本门")
	var v: VBoxContainer = r[1]
	var p := GS.player
	if p.sect == "":
		_label(v, "你目前是一介散修。", 20)
		_label(v, "前往五大宗门山门，拜见掌门即可拜入宗门（需满足灵根要求）。拜入后可在任务堂接取任务、积累贡献，在藏经阁学习本门功法与法诀。", 16, Color(0.8, 0.8, 0.78))
	else:
		var s := DB.sect(p.sect)
		var col := Color.html(str(s.get("color", "#ffffff")))
		_label(v, "%s · %s" % [s.get("name", ""), SectSystem.player_rank_name()], 24, col.lightened(0.2))
		_label(v, "「%s」" % s.get("motto", ""), 16, Color(0.8, 0.75, 0.6))
		_label(v, "贡献点 %d    声望 %d    业力 %d" % [SectSystem.contribution(), int(p.reputation.get(p.sect, 0)), p.karma], 18)
		var req := SectSystem.next_rank_requirement()
		_label(v, req if req != "" else "你已是本门真传弟子。", 16, Color(0.85, 0.8, 0.55))
		_label(v, "生产技艺：%s（%d 级）" % [PlayerData.PROFESSION_NAMES.get(s.get("profession", ""), ""), p.profession_level(str(s.get("profession", "")))], 16)
	_label(v, "", 8)
	_label(v, "—— 已接任务 ——", 18, Color(0.95, 0.8, 0.45))
	var ms := SectSystem.accepted()
	if ms.is_empty():
		_label(v, "（无）", 15, Color(0.6, 0.6, 0.6))
	for m in ms:
		var prog := "%d/%d" % [int(m["progress"]), int(m["count"])]
		if m["type"] == "deliver":
			prog = "持有 %d/%d" % [GS.player.bag.count_of(str(m.get("item", ""))), int(m["count"])]
		var done := SectSystem.can_turn_in(m)
		_label(v, "%s【%s】%s — %s  %s" % ["✔ " if done else "· ", DB.sect(str(m["sect"])).get("name", ""), m["name"], m["text"], prog], 15, Color(0.6, 1.0, 0.6) if done else Color(0.9, 0.9, 0.88))
	return r[0]


func _all_sects() -> Control:
	var r := _scroll("五宗")
	var v: VBoxContainer = r[1]
	for sid in DB.sects:
		var s: Dictionary = DB.sects[sid]
		var col := Color.html(str(s.get("color", "#ffffff")))
		var e := str(s.get("element", ""))
		var reason := SectSystem.join_block_reason(sid)
		_label(v, "%s  ·  %s  ·  %s" % [s.get("name", ""), Elem.name_of(e) + "系", PlayerData.PROFESSION_NAMES.get(s.get("profession", ""), "")], 20, col.lightened(0.25))
		_label(v, str(s.get("desc", "")), 15, Color(0.82, 0.8, 0.76))
		var rep := int(GS.player.reputation.get(sid, 0))
		var tail := "（可拜入）" if reason == "" else "（%s）" % reason
		if GS.player.sect == sid:
			tail = "（本门）"
		_label(v, "声望 %d  %s" % [rep, tail], 15, Color(0.7, 0.9, 0.7) if reason == "" or GS.player.sect == sid else Color(0.9, 0.6, 0.5))
		var sep := HSeparator.new()
		v.add_child(sep)
	return r[0]


func _relations() -> Control:
	var r := _scroll("人脉")
	var v: VBoxContainer = r[1]
	var list: Array = []
	for id in NpcSystem.npcs():
		var rec: Dictionary = NpcSystem.npcs()[id]
		if rec.get("met", false):
			list.append(rec)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("favor", 0)) > int(b.get("favor", 0)))
	if list.is_empty():
		_label(v, "你尚未结识任何修士。与人交谈、切磋、赠礼，便能结下羁绊。", 16, Color(0.7, 0.7, 0.7))
	for rec in list:
		var pd: Dictionary = rec.get("pd", {})
		var favor := int(rec.get("favor", 0))
		var col := Color(0.6, 1.0, 0.6) if favor >= 40 else (Color(1.0, 0.5, 0.45) if favor <= -30 else Color(0.9, 0.9, 0.88))
		var status := "" if rec.get("alive", true) else "【已陨落】"
		var sect_name := str(DB.sect(str(rec.get("sect", ""))).get("name", "散修"))
		_label(v, "%s%s  ·  %s %s  ·  %s  ·  %s  ·  好感 %d" % [status, pd.get("name", ""), sect_name, rec.get("title", ""),
			DB.realm_name(int(pd.get("realm", 0)), int(pd.get("stage", 0))), NpcSystem.bond_name(str(rec["id"])), favor], 16, col)
		var mem: Array = rec.get("memory", [])
		if not mem.is_empty():
			_label(v, "    " + str(mem[mem.size() - 1]), 13, Color(0.65, 0.65, 0.62))
	return r[0]
