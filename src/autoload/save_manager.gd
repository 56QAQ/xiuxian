extends Node
## 存档管理（autoload: SaveManager）。JSON 存档位于 user://saves/slot_N.json

const DIR := "user://saves/"
const SLOTS := 6


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func slot_path(slot: int) -> String:
	return DIR + "slot_%d.json" % slot


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func any_save() -> int:
	## 返回最近修改的存档位，没有返回 -1
	var best := -1
	var best_t := -1
	for i in SLOTS:
		if has_save(i):
			var t := FileAccess.get_modified_time(slot_path(i))
			if t > best_t:
				best_t = t
				best = i
	return best


func save_game(slot: int) -> bool:
	if GS.in_realm:
		Events.notify.emit("秘境之中无法存档", "warn")
		return false
	var data := GS.to_dict()
	data["meta"] = {
		"name": GS.player.name,
		"realm": DB.realm_name(GS.player.realm, GS.player.stage),
		"date": GS.date_text(),
		"saved_at": Time.get_datetime_string_from_system(false, true),
	}
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		Events.notify.emit("存档失败：%s" % error_string(FileAccess.get_open_error()), "bad")
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	Events.notify.emit("已存档（%d号）" % (slot + 1), "good")
	return true


func load_game(slot: int) -> bool:
	var data := read_slot(slot)
	if data.is_empty():
		return false
	GS.from_dict(data)
	return true


func read_slot(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var text := FileAccess.get_file_as_string(slot_path(slot))
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("存档损坏: %s" % slot_path(slot))
		return {}
	return parsed


func slot_meta(slot: int) -> Dictionary:
	return read_slot(slot).get("meta", {})


func delete_slot(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(slot_path(slot))
