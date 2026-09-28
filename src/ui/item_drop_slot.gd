class_name ItemDropSlot
extends Control
## 物品投放槽（服丹、炼化、出售等）：接受从网格拖入的物品；单击弹出储物袋中符合条件的物品列表。
## accept(item: ItemInstance) -> bool；on_item(grid: InventoryGrid, entry: Dictionary)

var title: String = "投放"
var hint: String = "拖入物品"
var glyph: String = "丹"
var accept: Callable
var on_item: Callable
var accent: Color = UITheme.JADE

var _hover: bool = false
var _drop_state: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(150, 120)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	add_to_group("ui_drop_targets")


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size).grow(-1)
	var bg := Color(accent.r * 0.12, accent.g * 0.12, accent.b * 0.12, 0.75)
	draw_rect(r, bg)
	var bc := Color(accent.r, accent.g, accent.b, 0.8 if _hover else 0.45)
	if _drop_state != 0:
		bc = Color(0.4, 0.95, 0.6) if _drop_state > 0 else Color(1.0, 0.35, 0.3)
	# 虚线框
	var dash := 8.0
	var pts := [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end], [r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]
	for seg in pts:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var n := int(a.distance_to(b) / dash)
		for i in range(0, n, 2):
			draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(mini(i + 1, n)) / n), bc, 1.5)
	var f := UITheme.font_title()
	var fs := int(minf(size.y * 0.42, 52.0))
	var ts := f.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(f, Vector2((size.x - ts.x) * 0.5, size.y * 0.46 + fs * 0.3), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(accent.r, accent.g, accent.b, 0.3 if not _hover else 0.5))
	var tf := UITheme.font_title()
	var tts := tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
	draw_string(tf, Vector2((size.x - tts.x) * 0.5, 24), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UITheme.GOLD_BRIGHT)
	var hf := UITheme.font_regular()
	var hs := hf.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(hf, Vector2((size.x - hs.x) * 0.5, size.y - 10), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT, NOTIFICATION_DRAG_END:
			_hover = false
			_drop_state = 0
			queue_redraw()


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or data.get("kind", "") != "item" or data.get("grid") == null:
		return false
	var ok := not accept.is_valid() or bool(accept.call(data["item"]))
	_drop_state = 1 if ok else -1
	queue_redraw()
	return ok


func _drop_data(_at: Vector2, data: Variant) -> void:
	_drop_state = 0
	queue_redraw()
	if on_item.is_valid():
		on_item.call(data["grid"], data["entry"])


## 储物袋与本命空间中符合条件的条目：[[grid, entry], ...]
func candidates() -> Array:
	var out: Array = []
	for g in [GS.player.bag, GS.player.secure]:
		var grid: InventoryGrid = g
		for e in grid.entries:
			if not accept.is_valid() or bool(accept.call(e["item"])):
				out.append([grid, e])
	return out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		var list := candidates()
		var pm := PopupMenu.new()
		pm.process_mode = Node.PROCESS_MODE_ALWAYS
		pm.add_separator(title)
		if list.is_empty():
			pm.add_item("储物袋中没有可用之物", 0)
			pm.set_item_disabled(pm.item_count - 1, true)
		for i in list.size():
			var it: ItemInstance = list[i][1]["item"]
			pm.add_icon_item(ItemIcon.texture_for(it.id, it.grade), "%s ×%d" % [it.display_name(), it.count], i + 1)
			pm.set_item_icon_max_width(pm.item_count - 1, 28)
		pm.id_pressed.connect(func(id: int) -> void:
			if id >= 1 and id <= list.size() and on_item.is_valid():
				on_item.call(list[id - 1][0], list[id - 1][1]))
		pm.popup_hide.connect(pm.queue_free)
		add_child(pm)
		pm.reset_size()
		pm.position = Vector2i(get_global_mouse_position() + Vector2(4, 4))
		pm.popup()
