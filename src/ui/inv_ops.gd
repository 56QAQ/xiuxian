class_name InvOps
## 背包拖放的模型操作（纯数据，不依赖场景树，可直接测试）。
## 调用方负责之后的 GS.recompute() 与 Events.inventory_changed.emit()。
##
## 拖动数据（Control 拖放 data）约定：
##   {"kind": "item", "item": ItemInstance, "grid": InventoryGrid 或 null, "entry": 条目字典或 {},
##    "slot": 装备槽名或 "", "rot": bool, "source": Control}


static func make_drag(item: ItemInstance, grid: InventoryGrid, entry: Dictionary, slot: String, rot: bool, source: Control) -> Dictionary:
	return {"kind": "item", "item": item, "grid": grid, "entry": entry, "slot": slot, "rot": rot, "source": source}


## 以鼠标所在（浮点）格坐标为中心，求物品左上角格，并夹在网格范围内
static func anchor_cell(grid: InventoryGrid, item: ItemInstance, rot: bool, cursor_cell: Vector2) -> Vector2i:
	var fp := InventoryGrid.footprint(item, rot)
	var x := int(floor(cursor_cell.x - fp.x * 0.5 + 0.5))
	var y := int(floor(cursor_cell.y - fp.y * 0.5 + 0.5))
	x = clampi(x, 0, maxi(grid.w - fp.x, 0))
	y = clampi(y, 0, maxi(grid.h - fp.y, 0))
	return Vector2i(x, y)


static func can_move(src: InventoryGrid, entry: Dictionary, dst: InventoryGrid, x: int, y: int, rot: bool) -> bool:
	var item: ItemInstance = entry["item"]
	return dst.can_place(item, x, y, rot, entry if src == dst else {})


## 移动条目到 (x, y, rot)；同一网格内原地更新，跨网格则移除后放置
static func move(src: InventoryGrid, entry: Dictionary, dst: InventoryGrid, x: int, y: int, rot: bool) -> bool:
	if not can_move(src, entry, dst, x, y, rot):
		return false
	var item: ItemInstance = entry["item"]
	if src == dst:
		entry["x"] = x
		entry["y"] = y
		entry["rot"] = rot
		dst.changed.emit()
		return true
	src.remove_entry(entry)
	return dst.place(item, x, y, rot)


static func can_stack(entry: Dictionary, target: Dictionary) -> bool:
	if target.is_empty() or entry.is_empty() or target == entry:
		return false
	var a: ItemInstance = entry["item"]
	var b: ItemInstance = target["item"]
	return b != a and b.can_stack_with(a) and b.count < b.max_stack()


## 把 entry 并入 target 堆叠，返回并入数量（entry 数量归零时从 src 移除）
static func stack_into(src: InventoryGrid, entry: Dictionary, dst: InventoryGrid, target: Dictionary) -> int:
	if not can_stack(entry, target):
		return 0
	var a: ItemInstance = entry["item"]
	var b: ItemInstance = target["item"]
	var moved := mini(b.max_stack() - b.count, a.count)
	b.count += moved
	a.count -= moved
	if a.count <= 0:
		src.remove_entry(entry)
	else:
		src.changed.emit()
	dst.changed.emit()
	return moved


## 拖放到网格：光标下有可堆叠的同类物品则合并，否则移动到 (x, y)
static func drop(src: InventoryGrid, entry: Dictionary, dst: InventoryGrid, x: int, y: int, rot: bool, cursor: Vector2i = Vector2i(-1, -1)) -> bool:
	if cursor.x >= 0:
		var target := dst.entry_at(cursor.x, cursor.y)
		if can_stack(entry, target):
			return stack_into(src, entry, dst, target) > 0
	return move(src, entry, dst, x, y, rot)


## 快速转移：整堆放入 dst（自动堆叠/找位），放不下的部分留在原处。返回是否有物品转移。
static func quick_move(src: InventoryGrid, entry: Dictionary, dst: InventoryGrid) -> bool:
	if src == dst:
		return false
	var item: ItemInstance = entry["item"]
	var before := item.count
	src.remove_entry(entry)
	var left := dst.add(item)
	if left > 0:
		item.count = left
		src.entries.append({"item": item, "x": entry["x"], "y": entry["y"], "rot": entry["rot"]})
		src.changed.emit()
	return left < before


## 拆分：从 entry 拆出 n 个放到同一网格空位。放不下则还原。
static func split(grid: InventoryGrid, entry: Dictionary, n: int) -> bool:
	var item: ItemInstance = entry["item"]
	if n <= 0 or n >= item.count:
		return false
	var piece := item.split(n)
	var spot := grid.find_space(piece)
	if spot.is_empty():
		item.count += piece.count
		return false
	return grid.place(piece, int(spot["x"]), int(spot["y"]), bool(spot["rot"]))


## 整理：按占格面积、类型、品阶排序后重新摆放；失败则保持原样
static func sort_grid(grid: InventoryGrid) -> bool:
	var old: Array[Dictionary] = grid.entries.duplicate()
	var items := grid.items()
	var order := ["weapon", "armor", "accessory", "bag", "manual", "pill", "talisman", "treasure", "material", "seed", "formation", "key", "misc"]
	items.sort_custom(func(a: ItemInstance, b: ItemInstance) -> bool:
		var sa := a.size().x * a.size().y
		var sb := b.size().x * b.size().y
		if sa != sb:
			return sa > sb
		var ta := order.find(a.type())
		var tb := order.find(b.type())
		if ta != tb:
			return ta < tb
		if a.get_grade() != b.get_grade():
			return a.get_grade() > b.get_grade()
		return a.id < b.id)
	grid.entries.clear()
	for it in items:
		var spot := grid.find_space(it)
		if spot.is_empty():
			grid.entries = old
			grid.changed.emit()
			return false
		grid.entries.append({"item": it, "x": spot["x"], "y": spot["y"], "rot": spot["rot"]})
	grid.changed.emit()
	return true


# ================================================================ 装备

static func slot_accepts(slot: String, item: ItemInstance) -> bool:
	if item == null:
		return false
	match slot:
		"weapon":
			return item.type() == "weapon"
		"armor":
			return item.type() == "armor"
		"accessory1", "accessory2":
			return item.type() == "accessory"
		"bag":
			return item.type() == "bag"
	return false


## 从网格装备到指定槽（替换下来的旧物品尽量放回原位）。储物袋槽会同步调整 p.bag 尺寸。
static func equip_to(p: PlayerData, grid: InventoryGrid, entry: Dictionary, slot: String) -> bool:
	var item: ItemInstance = entry["item"]
	if not slot_accepts(slot, item):
		return false
	grid.remove_entry(entry)
	var old: ItemInstance = p.equipment.get(slot, null)
	p.equipment[slot] = item
	if slot == "bag":
		var b: Dictionary = item.def().get("bag", {"w": 6, "h": 5})
		for over in p.bag.resize(int(b["w"]), int(b["h"])):
			p.stash.add(over)
	if old != null:
		if grid.can_place(old, int(entry["x"]), int(entry["y"]), bool(entry["rot"])):
			grid.place(old, int(entry["x"]), int(entry["y"]), bool(entry["rot"]))
		elif grid.add(old) > 0:
			p.stash.add(old)
	return true


## 卸下装备到网格指定位置（储物袋不可卸下）
static func unequip_to(p: PlayerData, slot: String, grid: InventoryGrid, x: int, y: int, rot: bool) -> bool:
	if slot == "bag":
		return false
	var item: ItemInstance = p.equipment.get(slot, null)
	if item == null or not grid.can_place(item, x, y, rot):
		return false
	p.equipment.erase(slot)
	return grid.place(item, x, y, rot)


## 两个装备槽互换（如 佩饰一 ↔ 佩饰二）
static func swap_slots(p: PlayerData, a: String, b: String) -> bool:
	var ia: ItemInstance = p.equipment.get(a, null)
	var ib: ItemInstance = p.equipment.get(b, null)
	if (ia != null and not slot_accepts(b, ia)) or (ib != null and not slot_accepts(a, ib)):
		return false
	if ib == null:
		p.equipment.erase(a)
	else:
		p.equipment[a] = ib
	if ia == null:
		p.equipment.erase(b)
	else:
		p.equipment[b] = ia
	return true
