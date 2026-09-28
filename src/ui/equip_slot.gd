class_name EquipSlot
extends Control
## 装备槽（兵刃/法衣/佩饰/储物袋）：拖入装备、拖出卸下（储物袋不可卸下，只能替换）、右键菜单、双击卸下。

signal slot_context(slot: EquipSlot, at_global: Vector2)

const SLOT_NAMES := {"weapon": "兵刃", "armor": "法衣", "accessory1": "佩饰", "accessory2": "佩饰", "bag": "储物袋"}
const SLOT_GLYPHS := {"weapon": "剑", "armor": "衣", "accessory1": "佩", "accessory2": "佩", "bag": "袋"}

var slot: String = "weapon"
var _hover: bool = false
var _drop_ok: int = 0   ## 0 无 1 可放 -1 不可放


static func create(p_slot: String, sz: Vector2) -> EquipSlot:
	var s := EquipSlot.new()
	s.slot = p_slot
	s.custom_minimum_size = sz
	return s


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	add_to_group("ui_drop_targets")
	Events.inventory_changed.connect(queue_redraw)
	Events.player_changed.connect(queue_redraw)


func item() -> ItemInstance:
	return GS.player.equipped(slot) if GS.player != null else null


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var it := item()
	if it != null:
		ItemIcon.draw_cell_bg(self, r.grow(-1), it.get_grade(), _hover)
		ItemIcon.draw_icon(self, r.grow(-8), it.id, it.grade, false)
	else:
		draw_rect(r.grow(-1), Color(0, 0, 0, 0.45))
		draw_rect(r.grow(-1), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.3 if not _hover else 0.6), false, 1.0)
		var f := UITheme.font_title()
		var g: String = SLOT_GLYPHS.get(slot, "")
		var fs := int(minf(size.x, size.y) * 0.42)
		var ts := f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2((size.x - ts.x) * 0.5, size.y * 0.5 + fs * 0.36), g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.16))
	# 角钩
	var c := UITheme.GOLD if it != null else Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.5)
	var k := 7.0
	for p in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]:
		var d: Vector2 = (size * 0.5 - p).sign()
		draw_line(p, p + Vector2(d.x * k, 0), c, 2.0)
		draw_line(p, p + Vector2(0, d.y * k), c, 2.0)
	# 槽名
	var lf := UITheme.font_regular()
	var name_t: String = SLOT_NAMES.get(slot, slot)
	draw_string_outline(lf, Vector2(5, size.y - 5), name_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.85))
	draw_string(lf, Vector2(5, size.y - 5), name_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
	if _drop_ok != 0:
		var col := Color(0.4, 0.95, 0.6) if _drop_ok > 0 else Color(1.0, 0.35, 0.3)
		draw_rect(r.grow(-1), Color(col.r, col.g, col.b, 0.15))
		draw_rect(r.grow(-1), col, false, 2.0)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			_drop_ok = 0
			queue_redraw()
		NOTIFICATION_DRAG_END:
			_drop_ok = 0
			queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and item() != null:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			slot_context.emit(self, get_global_mouse_position())
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.double_click and slot != "bag":
			GS.unequip(slot)
			accept_event()


func _get_tooltip(_at: Vector2) -> String:
	var it := item()
	return "equip:%d" % it.uid if it != null else "空%s槽：拖入%s以装备" % [SLOT_NAMES.get(slot, ""), SLOT_NAMES.get(slot, "")]


func _make_custom_tooltip(for_text: String) -> Object:
	var it := item()
	if it == null:
		return null
	var extra := "已装备 · 右键或双击卸下" if slot != "bag" else "储物袋只能替换，不能卸下"
	if not for_text.begins_with("equip:"):
		return null
	return ItemTooltip.build(it, extra)


func _get_drag_data(_at: Vector2) -> Variant:
	var it := item()
	if it == null or slot == "bag":
		return null
	var data := InvOps.make_drag(it, null, {}, slot, false, self)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ItemDragGhost.create(data, 48.0))
	set_drag_preview(holder)
	Audio.play("ui_pick", -4.0)
	return data


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or data.get("kind", "") != "item":
		return false
	var ok := InvOps.slot_accepts(slot, data["item"]) and str(data.get("slot", "")) != slot
	if str(data.get("slot", "")) == "bag":
		ok = false
	_drop_ok = 1 if ok else -1
	queue_redraw()
	return ok


func _drop_data(_at: Vector2, data: Variant) -> void:
	_drop_ok = 0
	var src: InventoryGrid = data.get("grid")
	var done := false
	if src != null:
		done = InvOps.equip_to(GS.player, src, data["entry"], slot)
	elif str(data.get("slot", "")) != "":
		done = InvOps.swap_slots(GS.player, str(data["slot"]), slot)
	if done:
		Audio.play("ui_equip")
		GS.recompute()
		Events.inventory_changed.emit()
	queue_redraw()


func _on_drag_rotated() -> void:
	pass
