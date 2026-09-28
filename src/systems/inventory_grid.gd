class_name InventoryGrid
extends RefCounted
## 网格背包（储物袋 / 洞府仓库 / 本命空间 / 秘境容器）。
## 物品占据 w×h 格，可旋转 90°。条目格式：{ "item": ItemInstance, "x": int, "y": int, "rot": bool }

signal changed

var w: int = 6
var h: int = 5
var entries: Array[Dictionary] = []


func _init(width: int = 6, height: int = 5) -> void:
	w = width
	h = height


static func footprint(item: ItemInstance, rot: bool) -> Vector2i:
	var s := item.size()
	return Vector2i(s.y, s.x) if rot else s


## 在 (x,y) 放置 item（rot 旋转）是否可行。ignore 为移动中的自身条目。
func can_place(item: ItemInstance, x: int, y: int, rot: bool, ignore: Dictionary = {}) -> bool:
	var fp := footprint(item, rot)
	if x < 0 or y < 0 or x + fp.x > w or y + fp.y > h:
		return false
	var r := Rect2i(x, y, fp.x, fp.y)
	for e in entries:
		if not ignore.is_empty() and e == ignore:
			continue
		var efp := footprint(e["item"], e["rot"])
		if r.intersects(Rect2i(e["x"], e["y"], efp.x, efp.y)):
			return false
	return true


func entry_at(x: int, y: int) -> Dictionary:
	for e in entries:
		var fp := footprint(e["item"], e["rot"])
		if Rect2i(e["x"], e["y"], fp.x, fp.y).has_point(Vector2i(x, y)):
			return e
	return {}


func place(item: ItemInstance, x: int, y: int, rot: bool) -> bool:
	if not can_place(item, x, y, rot):
		return false
	entries.append({"item": item, "x": x, "y": y, "rot": rot})
	changed.emit()
	return true


## 寻找可放置位置，返回 {x,y,rot}；找不到返回空字典
func find_space(item: ItemInstance) -> Dictionary:
	for rot in [false, true]:
		var fp := footprint(item, rot)
		if rot and fp == item.size():
			continue
		for y in range(0, h - fp.y + 1):
			for x in range(0, w - fp.x + 1):
				if can_place(item, x, y, rot):
					return {"x": x, "y": y, "rot": rot}
	return {}


## 添加物品：先尝试堆叠，再寻找空位。返回未能放入的剩余数量（0 表示全部放入）。
func add(item: ItemInstance) -> int:
	if item.is_stackable():
		for e in entries:
			var other: ItemInstance = e["item"]
			if other.can_stack_with(item) and other.count < other.max_stack():
				var moved := mini(other.max_stack() - other.count, item.count)
				other.count += moved
				item.count -= moved
				if item.count <= 0:
					changed.emit()
					return 0
	while item.count > 0:
		var spot := find_space(item)
		if spot.is_empty():
			changed.emit()
			return item.count
		var piece := item
		if item.count > item.max_stack():
			piece = item.split(item.max_stack())
		entries.append({"item": piece, "x": spot["x"], "y": spot["y"], "rot": spot["rot"]})
		if piece == item:
			changed.emit()
			return 0
	changed.emit()
	return 0


## 能否整体放入（不修改背包）
func can_fit(item: ItemInstance) -> bool:
	var clone := duplicate_grid()
	var copy := ItemInstance.from_dict(item.to_dict())
	return clone.add(copy) == 0


func remove_entry(e: Dictionary) -> void:
	entries.erase(e)
	changed.emit()


func remove_item(item: ItemInstance) -> bool:
	for e in entries:
		if e["item"] == item:
			entries.erase(e)
			changed.emit()
			return true
	return false


func count_of(item_id: String) -> int:
	var n := 0
	for e in entries:
		if e["item"].id == item_id:
			n += e["item"].count
	return n


## 取走指定数量，返回是否成功（数量不足则不做修改）
func take(item_id: String, n: int) -> bool:
	if count_of(item_id) < n:
		return false
	var left := n
	for e in entries.duplicate():
		var it: ItemInstance = e["item"]
		if it.id != item_id:
			continue
		var t := mini(it.count, left)
		it.count -= t
		left -= t
		if it.count <= 0:
			entries.erase(e)
		if left <= 0:
			break
	changed.emit()
	return true


func items() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for e in entries:
		out.append(e["item"])
	return out


func total_value() -> int:
	var v := 0
	for e in entries:
		v += e["item"].total_value()
	return v


func clear() -> void:
	entries.clear()
	changed.emit()


func used_cells() -> int:
	var n := 0
	for e in entries:
		var s: Vector2i = e["item"].size()
		n += s.x * s.y
	return n


## 改变尺寸（更换储物袋）。放不下的物品返回给调用者。
func resize(nw: int, nh: int) -> Array[ItemInstance]:
	var old := entries.duplicate()
	entries.clear()
	w = nw
	h = nh
	var overflow: Array[ItemInstance] = []
	for e in old:
		if can_place(e["item"], e["x"], e["y"], e["rot"]):
			entries.append(e)
	for e in old:
		if not entries.has(e):
			if add(e["item"]) > 0:
				overflow.append(e["item"])
	changed.emit()
	return overflow


func duplicate_grid() -> InventoryGrid:
	var g := InventoryGrid.new(w, h)
	for e in entries:
		g.entries.append({"item": ItemInstance.from_dict(e["item"].to_dict()), "x": e["x"], "y": e["y"], "rot": e["rot"]})
	return g


func to_dict() -> Dictionary:
	var arr := []
	for e in entries:
		arr.append({"i": e["item"].to_dict(), "x": e["x"], "y": e["y"], "r": e["rot"]})
	return {"w": w, "h": h, "e": arr}


static func from_dict(d: Dictionary) -> InventoryGrid:
	var g := InventoryGrid.new(int(d.get("w", 6)), int(d.get("h", 5)))
	for e in d.get("e", []):
		g.entries.append({"item": ItemInstance.from_dict(e["i"]), "x": int(e["x"]), "y": int(e["y"]), "rot": bool(e["r"])})
	return g
