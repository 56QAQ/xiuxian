class_name ItemActions
## 物品操作：使用 / 装备 / 炼化 / 拆分 / 丢弃 / 设为快捷(Q)。储物袋、仓库、容器共用。
## 所有操作作用于 GS.player，完成后 GS.recompute() 并广播 Events.inventory_changed。

## 可在野外直接生效的丹药效果
const FIELD_EFFECTS := ["exp", "heal_injury", "detox", "attribute"]
## 仅斗法中（Q）生效
const COMBAT_EFFECTS := ["heal", "qi", "shield", "buff", "cast"]


## 使用方式：field（直接服用）· combat（斗法中 Q）· breakthrough（突破时服用）· manual（参悟玉简）· none
static func use_kind(item: ItemInstance) -> String:
	var d := item.def()
	if d.has("teaches"):
		return "manual"
	var use: Dictionary = d.get("use", {})
	var eff := str(use.get("effect", ""))
	if eff == "":
		return "none"
	if eff == "breakthrough":
		return "breakthrough"
	if FIELD_EFFECTS.has(eff):
		return "field"
	if COMBAT_EFFECTS.has(eff) or bool(use.get("combat", false)):
		return "combat"
	return "none"


static func is_equippable(item: ItemInstance) -> bool:
	return GS.slot_for(item) != ""


static func can_refine(item: ItemInstance) -> bool:
	return item.def().has("refine")


## 功法参悟条件；返回空字符串表示满足
static func technique_req_text(p: PlayerData, tid: String) -> String:
	var t := DB.technique(tid)
	var req: Dictionary = t.get("req", {})
	var roots: Dictionary = req.get("root", {})
	for e in roots:
		if int(p.roots.get(e, 0)) < int(roots[e]):
			return "需%s灵根占比 ≥ %d%%" % [Elem.name_of(e), int(roots[e])]
	if req.has("realm") and p.realm < int(req["realm"]):
		return "需达到%s" % str(DB.realm(int(req["realm"])).get("name", ""))
	return ""


## 消耗 entry 中 n 个物品
static func consume(grid: InventoryGrid, entry: Dictionary, n: int = 1) -> void:
	var it: ItemInstance = entry["item"]
	it.count -= n
	if it.count <= 0:
		grid.remove_entry(entry)
	else:
		grid.changed.emit()


## 使用物品，返回 {ok, text, kind}
static func use(grid: InventoryGrid, entry: Dictionary) -> Dictionary:
	var it: ItemInstance = entry["item"]
	var d := it.def()
	var p := GS.player
	match use_kind(it):
		"field":
			var eff := str(d.get("use", {}).get("effect", ""))
			if eff == "exp" and Cultivation.at_bottleneck(p):
				return _res(false, "修为已至瓶颈，药力无处可去。先设法突破吧。", "warn")
			var text := Cultivation.use_pill(p, GS.stats, it.id)
			consume(grid, entry)
			_done()
			return _res(true, "服下%s：%s" % [it.display_name(), text], "good")
		"combat":
			return _res(false, "%s需在斗法中以快捷键 Q 使用。可在右键菜单中“设为快捷”。" % it.display_name(), "info")
		"breakthrough":
			return _res(false, "%s须在冲击大境界瓶颈时服用（修炼界面 → 突破）。" % it.display_name(), "info")
		"manual":
			var tt: Dictionary = d["teaches"]
			if tt.has("technique"):
				var tid := str(tt["technique"])
				if p.techniques.has(tid):
					return _res(false, "你已参悟过《%s》。" % DB.technique(tid).get("name", tid), "info")
				var why := technique_req_text(p, tid)
				if why != "":
					return _res(false, "无法参悟《%s》：%s" % [DB.technique(tid).get("name", tid), why], "warn")
				GS.learn_technique(tid)
			elif tt.has("spell"):
				var sid := str(tt["spell"])
				if p.spells.has(sid):
					return _res(false, "你已掌握【%s】。" % DB.spell(sid).get("name", sid), "info")
				GS.learn_spell(sid)
			consume(grid, entry)
			_done()
			return _res(true, "玉简化作点点灵光没入眉心。", "good")
	if can_refine(it):
		return refine(grid, entry, 1)
	return _res(false, "此物无法直接使用。", "info")


## 炼化 n 个，返回 {ok, text, kind}
static func refine(grid: InventoryGrid, entry: Dictionary, n: int = 1) -> Dictionary:
	var it: ItemInstance = entry["item"]
	var p := GS.player
	if not can_refine(it):
		return _res(false, "此物无法炼化。", "info")
	if Cultivation.at_bottleneck(p):
		return _res(false, "修为已至瓶颈，炼化无益。", "warn")
	n = clampi(n, 1, it.count)
	var amount := Cultivation.refine_value(p, it.id) * n
	var name_t := it.display_name()
	consume(grid, entry, n)
	Cultivation.add_exp(p, amount, "refine")
	GS.advance_time(minf(float(n), 24.0))
	_done()
	return _res(true, "炼化%s ×%d，修为 +%d" % [name_t, n, int(amount)], "good")


static func discard(grid: InventoryGrid, entry: Dictionary) -> void:
	grid.remove_entry(entry)
	var it: ItemInstance = entry["item"]
	if GS.player.quick_item == it.id and GS.player.bag.count_of(it.id) == 0:
		GS.player.quick_item = ""
	Audio.play("ui_discard")
	_done()


static func set_quick(item: ItemInstance) -> void:
	GS.player.quick_item = item.id
	Events.notify.emit("快捷使用（Q）：%s" % item.display_name(), "info")
	_done()


static func _done() -> void:
	GS.recompute()
	Events.inventory_changed.emit()


static func _res(ok: bool, text: String, kind: String) -> Dictionary:
	return {"ok": ok, "text": text, "kind": kind}


static func report(res: Dictionary) -> void:
	Events.notify.emit(str(res["text"]), str(res["kind"]))
	if res["ok"]:
		Audio.play("ui_use")


# ================================================================ 右键菜单

## 弹出物品右键菜单。extra: [{text, callback, disabled?}] 追加在前面（如“放入仓库”“出售”）
static func popup_menu(owner: Control, grid: InventoryGrid, entry: Dictionary, at_global: Vector2, extra: Array = []) -> PopupMenu:
	var it: ItemInstance = entry["item"]
	var pm := PopupMenu.new()
	pm.process_mode = Node.PROCESS_MODE_ALWAYS
	var actions: Array[Callable] = []
	var add := func(text: String, cb: Callable, disabled: bool) -> void:
		pm.add_item(text, actions.size())
		pm.set_item_disabled(pm.item_count - 1, disabled)
		actions.append(cb)
	pm.add_separator(it.display_name() + ("  ×%d" % it.count if it.count > 1 else ""))
	for e in extra:
		add.call(str(e["text"]), e["callback"], bool(e.get("disabled", false)))
	var uk := use_kind(it)
	if uk in ["field", "manual"]:
		add.call("参悟" if uk == "manual" else "使用", func() -> void: report(use(grid, entry)), false)
	elif uk in ["combat", "breakthrough"]:
		add.call("使用", func() -> void: report(use(grid, entry)), false)
	var do_equip := func() -> void:
		if GS.equip_from(grid, entry):
			Audio.play("ui_equip")
	var do_refine_all := func() -> void:
		var um := UIManager.find(owner.get_tree())
		if um != null:
			um.ask_number("炼化数量", 1, it.count, it.count, func(v: int) -> void: report(refine(grid, entry, v)), "每炼化一枚耗时一个时辰（最多一日）。")
		else:
			report(refine(grid, entry, it.count))
	var do_split := func() -> void:
		var um2 := UIManager.find(owner.get_tree())
		if um2 == null:
			return
		var on_split := func(v: int) -> void:
			if InvOps.split(grid, entry, v):
				Events.inventory_changed.emit()
			else:
				Events.notify.emit("没有空位放置拆分出的物品", "warn")
		um2.ask_number("拆分 %s" % it.display_name(), 1, it.count - 1, it.count / 2, on_split)
	var do_discard := func() -> void:
		var um3 := UIManager.find(owner.get_tree())
		if um3 != null and (it.get_grade() >= 2 or it.total_value() >= 100):
			var dlg := um3.confirm("丢弃 %s ×%d？丢弃后无法找回。" % [it.display_name(), it.count], func() -> void: discard(grid, entry), "丢弃物品", "丢弃")
			dlg.danger = true
		else:
			discard(grid, entry)
	var bottleneck := Cultivation.at_bottleneck(GS.player)
	if is_equippable(it):
		add.call("装备", do_equip, false)
	if can_refine(it):
		add.call("炼化", func() -> void: report(refine(grid, entry, 1)), bottleneck)
		if it.count > 1:
			add.call("全部炼化", do_refine_all, bottleneck)
	if it.count > 1:
		add.call("拆分", do_split, false)
	if uk == "combat":
		add.call("设为快捷(Q)" if GS.player.quick_item != it.id else "已是快捷(Q)", func() -> void: set_quick(it), GS.player.quick_item == it.id)
	add.call("丢弃", do_discard, false)
	pm.id_pressed.connect(func(id: int) -> void:
		if id >= 0 and id < actions.size():
			actions[id].call())
	pm.popup_hide.connect(pm.queue_free)
	owner.add_child(pm)
	pm.reset_size()
	var vp := owner.get_viewport_rect().size
	var pos := at_global + Vector2(4, 4)
	pos.x = minf(pos.x, vp.x - pm.size.x - 8)
	pos.y = minf(pos.y, vp.y - pm.size.y - 8)
	pm.position = Vector2i(pos)
	pm.popup()
	return pm
