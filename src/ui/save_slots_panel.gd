class_name SaveSlotsPanel
extends UIWindow
## 存档位面板。args: {"mode": "load" | "save"}
## 读档默认行为：SaveManager.load_game(slot) → Scenes.goto_overworld()；可用 args["on_load"]: Callable(slot) 覆盖。

const NUMERALS := ["壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖", "拾"]

var _list: VBoxContainer
var _mode: String = "load"


func _init() -> void:
	super()
	modal = true
	auto_refresh = false


func _build() -> void:
	_mode = str(args.get("mode", "load"))
	set_title("读取存档" if _mode == "load" else "保存进度")
	custom_minimum_size = Vector2(720, 0)
	if _mode == "save" and GS.in_realm:
		var warn := UITheme.label("秘境之中灵机紊乱，无法存档。", 18, UITheme.WARN)
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add(warn)
	_list = UITheme.vbox(8)
	add(_list)
	add(UITheme.separator())
	var row := UITheme.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UITheme.button("返回", "", close))
	add(row)


func refresh() -> void:
	if _list == null:
		return
	UIWindow.clear_children(_list)
	for i in SaveManager.SLOTS:
		_list.add_child(_slot_row(i))


func _slot_row(slot: int) -> Control:
	var has := SaveManager.has_save(slot)
	var meta: Dictionary = SaveManager.slot_meta(slot) if has else {}
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	var h := UITheme.hbox(16)
	card.add_child(h)
	var seal := SealLabel.new()
	seal.text = NUMERALS[slot] if slot < NUMERALS.size() else str(slot + 1)
	seal.active = has
	h.add_child(seal)
	var info := UITheme.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if has:
		var top := UITheme.hbox(14)
		top.add_child(UITheme.label(str(meta.get("name", "无名")), 22, UITheme.TEXT))
		top.add_child(UITheme.label(str(meta.get("realm", "")), 19, UITheme.GOLD_BRIGHT))
		info.add_child(top)
		info.add_child(UITheme.label(str(meta.get("date", "")), 16, UITheme.TEXT_DIM))
		info.add_child(UITheme.label("存于 " + str(meta.get("saved_at", "")).replace("T", " "), 14, UITheme.TEXT_FAINT))
	else:
		info.add_child(UITheme.label("空存档位", 20, UITheme.TEXT_FAINT))
		info.add_child(UITheme.label("尚无仙途记载", 15, UITheme.TEXT_FAINT))
	h.add_child(info)
	var btns := UITheme.hbox(8)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _mode == "load":
		var b := UITheme.button("读取", "JadeButton", _load.bind(slot))
		b.disabled = not has
		btns.add_child(b)
	else:
		var b2 := UITheme.button("覆盖" if has else "存档", "JadeButton", _save.bind(slot))
		b2.disabled = GS.in_realm or not GS.active
		btns.add_child(b2)
	if has:
		btns.add_child(UITheme.button("删除", "", _delete.bind(slot)))
	h.add_child(btns)
	return card


func _load(slot: int) -> void:
	var cb: Callable = args.get("on_load", Callable())
	if cb.is_valid():
		close()
		cb.call(slot)
		return
	if SaveManager.load_game(slot):
		close()
		Scenes.goto_overworld()
	else:
		Events.notify.emit("存档损坏，无法读取", "bad")


func _save(slot: int) -> void:
	var do_save := func() -> void:
		if SaveManager.save_game(slot):
			refresh()
	if SaveManager.has_save(slot) and ui() != null:
		ui().confirm("覆盖 %d 号存档？原有记录将被抹去。" % (slot + 1), do_save, "覆盖存档")
	else:
		do_save.call()


func _delete(slot: int) -> void:
	var do_del := func() -> void:
		SaveManager.delete_slot(slot)
		refresh()
		Events.notify.emit("已删除 %d 号存档" % (slot + 1), "info")
	if ui() != null:
		var d := ui().confirm("确定删除 %d 号存档？此举无法挽回。" % (slot + 1), do_del, "删除存档", "删除")
		d.danger = true
	else:
		do_del.call()


## 印章式序号
class SealLabel extends Control:
	var text: String = ""
	var active: bool = true

	func _init() -> void:
		custom_minimum_size = Vector2(56, 56)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
		var col := UITheme.CINNABAR if active else Color(0.35, 0.33, 0.3)
		draw_rect(r, Color(col.r, col.g, col.b, 0.18))
		draw_rect(r, col, false, 2.0)
		draw_rect(r.grow(-4), Color(col.r, col.g, col.b, 0.5), false, 1.0)
		var f := UITheme.font_title()
		var fs := 28
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2((size.x - ts.x) * 0.5, (size.y + fs * 0.72) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lightened(0.15))
