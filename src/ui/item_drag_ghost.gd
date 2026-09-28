class_name ItemDragGhost
extends Control
## 物品拖动预览：以鼠标为中心绘制物品（半透明），拖动中按 R 旋转。

var data: Dictionary = {}
var cell: float = 52.0


static func create(p_data: Dictionary, p_cell: float) -> ItemDragGhost:
	var g := ItemDragGhost.new()
	g.data = p_data
	g.cell = p_cell
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.process_mode = Node.PROCESS_MODE_ALWAYS
	GridView.drag_data = p_data
	return g


func _draw() -> void:
	var item: ItemInstance = data.get("item")
	if item == null:
		return
	var rot := bool(data.get("rot", false))
	var fp := InventoryGrid.footprint(item, rot)
	var sz := Vector2(fp) * cell
	var r := Rect2(-sz * 0.5, sz)
	ItemIcon.draw_cell_bg(self, r, item.get_grade(), true, 0.55)
	ItemIcon.draw_icon(self, r.grow(-4), item.id, item.grade, rot, 0.9)
	if item.count > 1:
		ItemIcon.draw_count(self, r, item.count)
	var hint := "R 旋转" if item.size().x != item.size().y else ""
	if hint != "":
		var f := UITheme.font_regular()
		draw_string_outline(f, r.position + Vector2(2, -6), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
		draw_string(f, r.position + Vector2(2, -6), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.GOLD_BRIGHT)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and event.is_action_pressed("rotate_item"):
		var item: ItemInstance = data.get("item")
		if item != null and item.size().x != item.size().y:
			data["rot"] = not bool(data.get("rot", false))
			Audio.play("ui_rotate", -6.0)
			queue_redraw()
			get_tree().call_group("ui_drop_targets", "_on_drag_rotated")
			get_viewport().set_input_as_handled()
