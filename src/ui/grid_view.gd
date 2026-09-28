class_name GridView
extends Control
## 网格背包视图（绑定一个 InventoryGrid）。可复用于储物袋、本命空间、洞府仓库、秘境容器、商店出售。
##
## 交互：左键拖动（同网格/跨网格/到装备槽，拖动中 R 旋转）· 右键 item_context · 双击 item_activated ·
##      Shift+左键 item_quick_move。所有网格与装备槽共享拖放协议（见 InvOps）。

signal item_context(view: GridView, entry: Dictionary, at_global: Vector2)
signal item_activated(view: GridView, entry: Dictionary)
signal item_quick_move(view: GridView, entry: Dictionary)
## 成功放入本网格后发出（data 为拖放数据）
signal item_dropped(view: GridView, data: Dictionary)

## 当前进行中的物品拖动（所有视图共享）
static var drag_data: Dictionary = {}

var grid: InventoryGrid
## 每格像素
var cell: float = 52.0:
	set(v):
		cell = v
		update_minimum_size()
		queue_redraw()
## 只读（不能拖出/拖入）
var read_only: bool = false
## 可选：限制可放入的物品 (item: ItemInstance) -> bool
var accept_filter: Callable
## 可选：自定义拖入处理 (view, data, x, y, rot, cursor) -> bool；返回 true 表示已处理
var custom_drop: Callable
## 可选：提示框追加文本 (item) -> String
var tooltip_extra: Callable
## 标记物品（如高亮可出售）
var dim_filter: Callable

var _hover: Vector2i = Vector2i(-1, -1)
var _preview: Dictionary = {}
var _last_drop_pos: Vector2 = Vector2(-1, -1)
var _dragging_entry: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	add_to_group("ui_drop_targets")
	Events.inventory_changed.connect(queue_redraw)


func bind(g: InventoryGrid) -> GridView:
	if grid != null and grid.changed.is_connected(_on_grid_changed):
		grid.changed.disconnect(_on_grid_changed)
	grid = g
	if grid != null:
		grid.changed.connect(_on_grid_changed)
	update_minimum_size()
	queue_redraw()
	return self


func _on_grid_changed() -> void:
	update_minimum_size()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	if grid == null:
		return Vector2(cell, cell)
	return Vector2(grid.w, grid.h) * cell


func cell_at(local: Vector2) -> Vector2i:
	return Vector2i(int(floor(local.x / cell)), int(floor(local.y / cell)))


func entry_at_pos(local: Vector2) -> Dictionary:
	if grid == null:
		return {}
	var c := cell_at(local)
	if c.x < 0 or c.y < 0 or c.x >= grid.w or c.y >= grid.h:
		return {}
	return grid.entry_at(c.x, c.y)


func entry_rect(e: Dictionary) -> Rect2:
	var fp := InventoryGrid.footprint(e["item"], e["rot"])
	return Rect2(Vector2(int(e["x"]), int(e["y"])) * cell, Vector2(fp) * cell)


# ================================================================ 绘制

func _draw() -> void:
	if grid == null:
		return
	var full := Rect2(Vector2.ZERO, Vector2(grid.w, grid.h) * cell)
	draw_rect(full, Color(0.0, 0.0, 0.0, 0.42))
	var line := Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.09)
	for y in grid.h:
		for x in grid.w:
			var r := Rect2(Vector2(x, y) * cell, Vector2(cell, cell)).grow(-1.5)
			draw_rect(r, Color(1, 1, 1, 0.025))
			draw_rect(r, line, false, 1.0)
	draw_rect(full, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.35), false, 1.0)
	var hovered := grid.entry_at(_hover.x, _hover.y) if _hover.x >= 0 else {}
	var quick := GS.player.quick_item if GS.player != null else ""
	for e in grid.entries:
		var it: ItemInstance = e["item"]
		var r2 := entry_rect(e).grow(-2.0)
		var ghost := not _dragging_entry.is_empty() and e == _dragging_entry
		var alpha := 0.3 if ghost else 1.0
		if dim_filter.is_valid() and not bool(dim_filter.call(it)):
			alpha *= 0.35
		ItemIcon.draw_cell_bg(self, r2, it.get_grade(), e == hovered and not ghost, alpha)
		ItemIcon.draw_icon(self, r2.grow(-3.0), it.id, it.grade, bool(e["rot"]), alpha)
		if it.count > 1:
			ItemIcon.draw_count(self, r2, it.count)
		if quick != "" and it.id == quick and not ghost:
			_draw_badge(r2, "Q")
	if not _preview.is_empty():
		var pr: Rect2 = _preview["rect"]
		var ok: bool = _preview["ok"]
		var col := Color(0.4, 0.95, 0.6) if ok else Color(1.0, 0.35, 0.3)
		draw_rect(pr.grow(-1.0), Color(col.r, col.g, col.b, 0.18))
		draw_rect(pr.grow(-1.0), Color(col.r, col.g, col.b, 0.85), false, 2.0)
		if _preview.get("stack", false):
			_draw_badge(pr.grow(-2.0), "＋")


func _draw_badge(r: Rect2, text: String) -> void:
	var f := UITheme.font_title()
	var br := Rect2(r.position + Vector2(2, 2), Vector2(16, 16))
	draw_rect(br, Color(0.45, 0.1, 0.07, 0.9))
	draw_rect(br, UITheme.GOLD, false, 1.0)
	var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_string(f, br.position + Vector2((16 - ts.x) * 0.5, 13), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.GOLD_BRIGHT)


# ================================================================ 输入

func _gui_input(event: InputEvent) -> void:
	if grid == null:
		return
	if event is InputEventMouseMotion:
		var c := cell_at(event.position)
		if c != _hover:
			_hover = c
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var e := entry_at_pos(event.position)
		if e.is_empty():
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			item_context.emit(self, e, get_global_mouse_position())
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				item_activated.emit(self, e)
				accept_event()
			elif event.shift_pressed:
				item_quick_move.emit(self, e)
				accept_event()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_EXIT:
			_hover = Vector2i(-1, -1)
			_preview = {}
			queue_redraw()
		NOTIFICATION_DRAG_END:
			_dragging_entry = {}
			_preview = {}
			drag_data = {}
			queue_redraw()


func _get_tooltip(at_position: Vector2) -> String:
	var e := entry_at_pos(at_position)
	if e.is_empty() or not drag_data.is_empty():
		return ""
	return "item:%d" % (e["item"] as ItemInstance).uid


func _make_custom_tooltip(_for_text: String) -> Object:
	var e := entry_at_pos(get_local_mouse_position())
	if e.is_empty():
		return null
	var it: ItemInstance = e["item"]
	var extra := "右键：更多操作 · 拖动中 R 旋转"
	if tooltip_extra.is_valid():
		extra = str(tooltip_extra.call(it))
	return ItemTooltip.build(it, extra)


# ================================================================ 拖放

func _get_drag_data(at_position: Vector2) -> Variant:
	if read_only or grid == null:
		return null
	var e := entry_at_pos(at_position)
	if e.is_empty():
		return null
	var it: ItemInstance = e["item"]
	var data := InvOps.make_drag(it, grid, e, "", bool(e["rot"]), self)
	_dragging_entry = e
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ItemDragGhost.create(data, cell))
	set_drag_preview(holder)
	Audio.play("ui_pick", -4.0)
	queue_redraw()
	return data


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if read_only or grid == null or not (data is Dictionary) or data.get("kind", "") != "item":
		return false
	var it: ItemInstance = data["item"]
	if accept_filter.is_valid() and not bool(accept_filter.call(it)):
		_set_preview(at_position, data, false)
		return false
	_last_drop_pos = at_position
	var res := _evaluate(at_position, data)
	_preview = res
	queue_redraw()
	return res["ok"]


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var res := _evaluate(at_position, data)
	_preview = {}
	if not res["ok"]:
		return
	var x: int = res["x"]
	var y: int = res["y"]
	var rot: bool = data["rot"]
	var cursor := cell_at(at_position)
	var done := false
	if custom_drop.is_valid():
		done = bool(custom_drop.call(self, data, x, y, rot, cursor))
	if not done:
		var src: InventoryGrid = data.get("grid")
		var slot: String = str(data.get("slot", ""))
		if src != null:
			done = InvOps.drop(src, data["entry"], grid, x, y, rot, cursor)
		elif slot != "":
			done = InvOps.unequip_to(GS.player, slot, grid, x, y, rot)
			if done:
				GS.recompute()
	if done:
		Audio.play("ui_drop", -4.0)
		Events.inventory_changed.emit()
		item_dropped.emit(self, data)
	queue_redraw()


## 计算放置结果：{ok, x, y, rect, stack}
func _evaluate(at_position: Vector2, data: Dictionary) -> Dictionary:
	var it: ItemInstance = data["item"]
	var rot: bool = data["rot"]
	var cc := at_position / cell
	var a := InvOps.anchor_cell(grid, it, rot, cc)
	var fp := InventoryGrid.footprint(it, rot)
	var src: InventoryGrid = data.get("grid")
	var entry: Dictionary = data.get("entry", {})
	var cursor := cell_at(at_position)
	var target := grid.entry_at(cursor.x, cursor.y)
	if src != null and InvOps.can_stack(entry, target):
		return {"ok": true, "x": a.x, "y": a.y, "rect": entry_rect(target), "stack": true}
	var ok: bool
	if src != null:
		ok = InvOps.can_move(src, entry, grid, a.x, a.y, rot)
	else:
		ok = str(data.get("slot", "")) not in ["", "bag"] and grid.can_place(it, a.x, a.y, rot)
	return {"ok": ok, "x": a.x, "y": a.y, "rect": Rect2(Vector2(a) * cell, Vector2(fp) * cell), "stack": false}


func _set_preview(at_position: Vector2, data: Dictionary, ok: bool) -> void:
	var it: ItemInstance = data["item"]
	var a := InvOps.anchor_cell(grid, it, data["rot"], at_position / cell)
	var fp := InventoryGrid.footprint(it, data["rot"])
	_preview = {"ok": ok, "x": a.x, "y": a.y, "rect": Rect2(Vector2(a) * cell, Vector2(fp) * cell), "stack": false}
	queue_redraw()


## 拖动中旋转后，按最后的光标位置重新评估预览
func _on_drag_rotated() -> void:
	if _preview.is_empty() or drag_data.is_empty():
		return
	if get_global_rect().has_point(get_global_mouse_position()):
		_preview = _evaluate(get_local_mouse_position(), drag_data)
		queue_redraw()
