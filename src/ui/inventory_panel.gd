class_name InventoryPanel
extends UIWindow
## 储物袋面板：法器纸娃娃（3D 预览 + 五个装备槽）、储物袋网格、本命空间（2×2）、灵石与总值。
## args: {"other": InventoryGrid, "other_title": String} 时在左侧显示第二个网格（洞府仓库、秘境容器）；
##       可选 "other_hint": String（第二网格下方的说明）、"on_take_all": Callable()（覆盖“全部拾取”）。

var _bag_view: GridView
var _secure_view: GridView
var _other_view: GridView
var _other: InventoryGrid
var _preview: RigPreview
var _stones: Label
var _value: Label
var _bag_title: Label
var _quick: Label
var _other_value: Label


func _init() -> void:
	super()
	window_title = "储物袋"


func _build() -> void:
	_other = args.get("other", null)
	var row := UITheme.hbox(22)
	add(row)
	if _other != null:
		row.add_child(_build_other())
		var vs := VSeparator.new()
		row.add_child(vs)
	row.add_child(_build_equipment())
	row.add_child(_build_bag())
	var hint := UITheme.label("拖动整理 · 拖动中按 R 旋转 · 右键更多操作 · 双击使用/装备 · Shift+单击快速转移", 14, UITheme.TEXT_FAINT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add(hint)


func _build_other() -> Control:
	var col := UITheme.vbox(8)
	var head := UITheme.hbox(8)
	var h := UITheme.header(str(args.get("other_title", "容器")))
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	col.add_child(head)
	_other_view = GridView.new()
	_other_view.cell = clampf(minf(520.0 / _other.w, 600.0 / _other.h), 34.0, 52.0)
	_other_view.bind(_other)
	_connect_view(_other_view)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(minf(_other.w * _other_view.cell, 540.0) + 12, minf(_other.h * _other_view.cell, 610.0) + 4)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.add_child(_other_view)
	col.add_child(sc)
	_other_value = UITheme.label("", 15, UITheme.TEXT_DIM)
	col.add_child(_other_value)
	if args.has("other_hint"):
		col.add_child(UITheme.wrap_label(str(args["other_hint"]), 14, UITheme.TEXT_FAINT))
	var btns := UITheme.hbox(8)
	btns.add_child(UITheme.button("全部拾取", "JadeButton", _take_all))
	btns.add_child(UITheme.button("整理", "", func() -> void:
		InvOps.sort_grid(_other)
		Events.inventory_changed.emit()))
	col.add_child(btns)
	return col


func _build_equipment() -> Control:
	var col := UITheme.vbox(10)
	col.add_child(UITheme.header("法器"))
	var doll := UITheme.hbox(8)
	var left := UITheme.vbox(8)
	left.add_child(_slot("weapon", Vector2(88, 184)))
	left.add_child(_slot("bag", Vector2(88, 88)))
	doll.add_child(left)
	var mid := PanelContainer.new()
	mid.theme_type_variation = "InsetPanel"
	_preview = RigPreview.new()
	_preview.custom_minimum_size = Vector2(196, 262)
	_preview.allow_zoom = false
	mid.add_child(_preview)
	doll.add_child(mid)
	var right := UITheme.vbox(8)
	right.add_child(_slot("armor", Vector2(88, 132)))
	var accs := UITheme.vbox(8)
	accs.add_child(_slot("accessory1", Vector2(88, 66)))
	accs.add_child(_slot("accessory2", Vector2(88, 66)))
	right.add_child(accs)
	doll.add_child(right)
	col.add_child(doll)
	# 灵石与价值
	var info := PanelContainer.new()
	info.theme_type_variation = "InsetPanel"
	var iv := UITheme.vbox(4)
	var sr := UITheme.hbox(8)
	var st := ItemIcon.new()
	st.item_id = "spirit_stone"
	st.show_frame = false
	st.custom_minimum_size = Vector2(30, 30)
	sr.add_child(st)
	sr.add_child(UITheme.label("灵石", 18, UITheme.TEXT_DIM))
	_stones = UITheme.label("0", 24, UITheme.GOLD_BRIGHT)
	_stones.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stones.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sr.add_child(_stones)
	iv.add_child(sr)
	_value = UITheme.label("", 15, UITheme.TEXT_DIM)
	iv.add_child(_value)
	_quick = UITheme.label("", 15, UITheme.TEXT_DIM)
	iv.add_child(_quick)
	info.add_child(iv)
	col.add_child(info)
	return col


func _slot(slot_name: String, sz: Vector2) -> EquipSlot:
	var s := EquipSlot.create(slot_name, sz)
	s.slot_context.connect(_on_slot_context)
	return s


func _build_bag() -> Control:
	var col := UITheme.vbox(8)
	var head := UITheme.hbox(8)
	_bag_title = UITheme.label("储物袋", 21, Color(0, 0, 0, 0), "HeaderLabel")
	head.add_child(_bag_title)
	var sep := GoldSeparator.new()
	sep.ornament = false
	sep.fade_left = false
	head.add_child(sep)
	head.add_child(UITheme.button("整理", "ChipButton", func() -> void:
		if not InvOps.sort_grid(GS.player.bag):
			Events.notify.emit("整理失败：空间不足", "warn")
		Events.inventory_changed.emit()))
	col.add_child(head)
	_bag_view = GridView.new()
	_bag_view.cell = 52.0 if GS.player.bag.w <= 8 else 46.0
	_connect_view(_bag_view)
	col.add_child(_bag_view)
	var sh := UITheme.hbox(8)
	sh.add_child(UITheme.label("本命空间", 19, Color(0, 0, 0, 0), "HeaderLabel"))
	sh.add_child(UITheme.label("身陨后仍保留", 14, UITheme.TEXT_FAINT))
	col.add_child(sh)
	_secure_view = GridView.new()
	_secure_view.cell = 52.0
	_connect_view(_secure_view)
	col.add_child(_secure_view)
	return col


func _connect_view(v: GridView) -> void:
	v.item_context.connect(_on_item_context)
	v.item_activated.connect(_on_item_activated)
	v.item_quick_move.connect(_on_quick_move)


func refresh() -> void:
	if _bag_view == null:
		return
	var p := GS.player
	if _bag_view.grid != p.bag:
		_bag_view.bind(p.bag)
	if _secure_view.grid != p.secure:
		_secure_view.bind(p.secure)
	_bag_view.cell = 52.0 if p.bag.w <= 8 and p.bag.h <= 7 else 46.0
	_bag_title.text = "储物袋 · %d×%d" % [p.bag.w, p.bag.h]
	_stones.text = UITheme.num(p.spirit_stones)
	var total := p.bag.total_value() + p.secure.total_value()
	_value.text = "袋中物品估值 %s 灵石 · 已用 %d/%d 格" % [UITheme.num(total), p.bag.used_cells(), p.bag.w * p.bag.h]
	var q := p.quick_item
	if q != "" and not DB.item(q).is_empty():
		_quick.text = "快捷（Q）：%s ×%d" % [DB.item(q).get("name", q), p.bag.count_of(q) + p.secure.count_of(q)]
	else:
		_quick.text = "快捷（Q）：未设置"
	if _other_value != null:
		_other_value.text = "估值 %s 灵石 · %d 件" % [UITheme.num(_other.total_value()), _other.entries.size()]
	_preview.show_player(p)
	_bag_view.queue_redraw()
	_secure_view.queue_redraw()


# ================================================================ 操作

func _grid_of(v: GridView) -> InventoryGrid:
	return v.grid


## Shift+单击的目标网格
func _quick_target(v: GridView) -> InventoryGrid:
	if v == _other_view:
		return GS.player.bag
	if v == _secure_view:
		return GS.player.bag
	if _other != null:
		return _other
	return GS.player.secure


func _on_quick_move(v: GridView, entry: Dictionary) -> void:
	var dst := _quick_target(v)
	if InvOps.quick_move(v.grid, entry, dst):
		Audio.play("ui_drop", -4.0)
		Events.inventory_changed.emit()
	else:
		Events.notify.emit("空间不足", "warn")


func _on_item_activated(v: GridView, entry: Dictionary) -> void:
	var it: ItemInstance = entry["item"]
	if v == _other_view:
		_on_quick_move(v, entry)
		return
	if ItemActions.is_equippable(it):
		if GS.equip_from(v.grid, entry):
			Audio.play("ui_equip")
		return
	ItemActions.report(ItemActions.use(v.grid, entry))


func _on_item_context(v: GridView, entry: Dictionary, at: Vector2) -> void:
	var extra: Array = []
	var label := ""
	if v == _other_view:
		label = "放入储物袋"
	elif v == _secure_view:
		label = "移回储物袋"
	elif _other != null:
		label = "放入%s" % str(args.get("other_title", "容器"))
	else:
		label = "移入本命空间"
	extra.append({"text": label, "callback": func() -> void: _on_quick_move(v, entry)})
	var cb: Callable = args.get("context_extra", Callable())
	if cb.is_valid():
		extra.append_array(cb.call(v.grid, entry))
	ItemActions.popup_menu(self, v.grid, entry, at, extra)


func _on_slot_context(s: EquipSlot, at: Vector2) -> void:
	var it := s.item()
	if it == null:
		return
	var pm := PopupMenu.new()
	pm.add_separator(it.display_name())
	pm.add_item("卸下", 0)
	pm.set_item_disabled(pm.item_count - 1, s.slot == "bag")
	pm.id_pressed.connect(func(id: int) -> void:
		if id == 0:
			GS.unequip(s.slot))
	pm.popup_hide.connect(pm.queue_free)
	add_child(pm)
	pm.reset_size()
	pm.position = Vector2i(at + Vector2(4, 4))
	pm.popup()


func _take_all() -> void:
	var cb: Callable = args.get("on_take_all", Callable())
	if cb.is_valid():
		cb.call()
		return
	var moved := 0
	var left := 0
	for e in _other.entries.duplicate():
		if InvOps.quick_move(_other, e, GS.player.bag):
			moved += 1
		if _other.entries.has(e):
			left += 1
	Events.inventory_changed.emit()
	if left > 0:
		Events.notify.emit("储物袋已满，尚有 %d 件未能拾取" % left, "warn")
	elif moved > 0:
		Audio.play("ui_loot")
