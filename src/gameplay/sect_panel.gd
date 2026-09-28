class_name SectPanel
extends UIWindow
## 宗门 / 人脉面板（J）：宗门阶位、贡献、声望、已接任务；五宗概览；结识的修士与羁绊。
## 国风样式：宗门大印 + 书法宗名、门规题字；小节标题用朱印笔触；五宗与人脉为委角卡片。
## 操作（接任务、学功法、兑换）在宗门 NPC 处进行，本面板只做信息汇总。
## 由 GameSession 注册到 UIManager：UIManager.register_panel("sect", ...)

var _tabs: TabContainer


func _init() -> void:
	super._init()
	window_title = "宗门 · 人脉"


static func create(_args: Dictionary) -> UIWindow:
	return SectPanel.new()


func _build() -> void:
	custom_minimum_size = Vector2(780, 580)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size = Vector2(760, 520)
	body.add_child(_tabs)
	Events.sect_changed.connect(queue_refresh)
	Events.missions_changed.connect(queue_refresh)
	Events.relation_changed.connect(func(_id: String) -> void: queue_refresh())


func refresh() -> void:
	if _tabs == null:
		return
	var cur := _tabs.current_tab
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_tabs.add_child(_my_sect())
	_tabs.add_child(_all_sects())
	_tabs.add_child(_relations())
	_tabs.current_tab = clampi(cur, 0, _tabs.get_tab_count() - 1)


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
		var hh := UITheme.hbox(16)
		hh.add_child(InkSeal.make("散修", 72.0, Color(0.3, 0.28, 0.26)))
		var vv := UITheme.vbox(4)
		vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vv.add_child(UITheme.label("你目前是一介散修。", 30, UITheme.TEXT, "DisplayLabel"))
		var hint := _label(vv, "前往五大宗门山门，拜见掌门即可拜入宗门（需满足灵根要求）。拜入后可在任务堂接取任务、积累贡献，在藏经阁学习本门功法与法诀。", 16, Color(0.8, 0.8, 0.78))
		hint.custom_minimum_size.x = 560
		hh.add_child(vv)
		v.add_child(hh)
	else:
		var s := DB.sect(p.sect)
		var col := Color.html(str(s.get("color", "#ffffff")))
		var hh2 := UITheme.hbox(18)
		var seal := InkSeal.make(str(s.get("name", "宗")).substr(0, 2), 86.0, Color(0.74, 0.13, 0.08).lerp(col.darkened(0.3), 0.18))
		hh2.add_child(seal)
		var vv2 := UITheme.vbox(2)
		vv2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm := UITheme.label(str(s.get("name", "")), 38, col.lightened(0.35), "DisplayLabel")
		nm.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.02, 0.9))
		nm.add_theme_constant_override("outline_size", 5)
		vv2.add_child(nm)
		vv2.add_child(UITheme.label(SectSystem.player_rank_name(), 20, UITheme.GOLD_BRIGHT))
		vv2.add_child(UITheme.label("「%s」" % s.get("motto", ""), 20, Color(0.86, 0.78, 0.6), "DisplayLabel"))
		hh2.add_child(vv2)
		v.add_child(hh2)
		var stats := UITheme.hbox(28)
		for pair in [["贡献点", str(SectSystem.contribution())], ["声望", str(int(p.reputation.get(p.sect, 0)))], ["业力", str(p.karma)],
				["生产技艺", "%s %d 级" % [PlayerData.PROFESSION_NAMES.get(s.get("profession", ""), ""), p.profession_level(str(s.get("profession", "")))]]]:
			var cell := UITheme.vbox(0)
			cell.add_child(UITheme.label(str(pair[0]), 14, UITheme.TEXT_DIM))
			cell.add_child(UITheme.label(str(pair[1]), 22, UITheme.TEXT, "DisplayLabel"))
			stats.add_child(cell)
		v.add_child(UITheme.margin(stats, 6, 4))
		var req := SectSystem.next_rank_requirement()
		_label(v, req if req != "" else "你已是本门真传弟子。", 16, Color(0.9, 0.8, 0.55))
	v.add_child(UITheme.spacer(6.0))
	v.add_child(UITheme.header("已接任务"))
	var ms := SectSystem.accepted()
	if ms.is_empty():
		_label(v, "（无）", 15, Color(0.6, 0.6, 0.6))
	for m in ms:
		var prog := "%d/%d" % [int(m["progress"]), int(m["count"])]
		if m["type"] == "deliver":
			prog = "持有 %d/%d" % [GS.player.bag.count_of(str(m.get("item", ""))), int(m["count"])]
		var done := SectSystem.can_turn_in(m)
		var card := UITheme.panel("CardSelected" if done else "CardPanel")
		var row := UITheme.hbox(12)
		row.add_child(InkSeal.make("成" if done else "任", 30.0, Color(0.16, 0.5, 0.38) if done else Color(0.74, 0.14, 0.09)))
		var mv := UITheme.vbox(0)
		mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mv.add_child(UITheme.label("【%s】%s" % [DB.sect(str(m["sect"])).get("name", ""), m["name"]], 18, Color(0.7, 1.0, 0.72) if done else UITheme.TEXT))
		var mt := _label(mv, str(m["text"]), 14, UITheme.TEXT_DIM)
		mt.custom_minimum_size.x = 480
		row.add_child(mv)
		row.add_child(UITheme.label(prog, 18, UITheme.GOLD_BRIGHT))
		card.add_child(row)
		v.add_child(card)
	return r[0]


func _all_sects() -> Control:
	var r := _scroll("五宗")
	var v: VBoxContainer = r[1]
	for sid in DB.sects:
		var s: Dictionary = DB.sects[sid]
		var col := Color.html(str(s.get("color", "#ffffff")))
		var e := str(s.get("element", ""))
		var reason := SectSystem.join_block_reason(sid)
		var card := UITheme.panel("CardSelected" if GS.player.sect == sid else "CardPanel")
		var row := UITheme.hbox(14)
		row.add_child(InkSeal.make(str(s.get("name", "宗")).substr(0, 2), 58.0, Color(0.74, 0.13, 0.08).lerp(col.darkened(0.3), 0.18)))
		var sv := UITheme.vbox(2)
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var top := UITheme.hbox(12)
		top.add_child(UITheme.label(str(s.get("name", "")), 26, col.lightened(0.3), "DisplayLabel"))
		top.add_child(UITheme.label("%s  ·  %s" % [Elem.name_of(e) + "系", PlayerData.PROFESSION_NAMES.get(s.get("profession", ""), "")], 15, UITheme.TEXT_DIM))
		sv.add_child(top)
		var desc := _label(sv, str(s.get("desc", "")), 15, Color(0.82, 0.8, 0.76))
		desc.custom_minimum_size.x = 560
		var rep := int(GS.player.reputation.get(sid, 0))
		var tail := "可拜入" if reason == "" else reason
		if GS.player.sect == sid:
			tail = "本门"
		_label(sv, "声望 %d  ·  %s" % [rep, tail], 15, Color(0.7, 0.9, 0.7) if reason == "" or GS.player.sect == sid else Color(0.9, 0.6, 0.5))
		row.add_child(sv)
		card.add_child(row)
		v.add_child(card)
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
		var card := UITheme.panel("CardPanel")
		var row := UITheme.hbox(12)
		var alive: bool = rec.get("alive", true)
		row.add_child(InkSeal.make(InkArt.realm_glyph(int(pd.get("realm", 0))), 36.0, Color(0.74, 0.14, 0.09) if alive else Color(0.3, 0.28, 0.26)))
		var rv := UITheme.vbox(0)
		rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var top := UITheme.hbox(10)
		top.add_child(UITheme.label(status + str(pd.get("name", "")), 22, col, "DisplayLabel"))
		top.add_child(UITheme.label("%s %s  ·  %s" % [sect_name, rec.get("title", ""), DB.realm_name(int(pd.get("realm", 0)), int(pd.get("stage", 0)))], 15, UITheme.TEXT_DIM))
		rv.add_child(top)
		var mem: Array = rec.get("memory", [])
		if not mem.is_empty():
			_label(rv, str(mem[mem.size() - 1]), 13, Color(0.65, 0.65, 0.62))
		row.add_child(rv)
		var bond := UITheme.vbox(0)
		bond.add_child(UITheme.label(NpcSystem.bond_name(str(rec["id"])), 18, col))
		bond.add_child(UITheme.label("好感 %d" % favor, 14, UITheme.TEXT_DIM))
		row.add_child(bond)
		card.add_child(row)
		v.add_child(card)
	return r[0]
