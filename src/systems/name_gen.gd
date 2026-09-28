class_name NameGen
## 随机姓名（data/names.json）。


static func _pick(rng: RandomNumberGenerator, arr: Array, fallback: String) -> String:
	if arr.is_empty():
		return fallback
	return str(arr[rng.randi() % arr.size()])


static func person(rng: RandomNumberGenerator, gender: String) -> String:
	var sur := _pick(rng, DB.names.get("surnames", []), "李")
	var given := _pick(rng, DB.names.get("given_female" if gender == "female" else "given_male", []), "无名")
	return sur + given


static func daoist(rng: RandomNumberGenerator) -> String:
	return _pick(rng, DB.names.get("daoist", []), "清虚") + ("子" if rng.randf() < 0.5 else "真人")


static func evil(rng: RandomNumberGenerator, gender: String) -> String:
	return _pick(rng, DB.names.get("evil_titles", []), "血手") + person(rng, gender).substr(0, 1) + ("老怪" if rng.randf() < 0.3 else "")
