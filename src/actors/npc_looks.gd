class_name NpcLooks
## NPC 随机外貌（若 CharacterBuilder 提供 random_appearance 则优先使用）。


static func random_appearance(rng: RandomNumberGenerator, gender: String) -> Dictionary:
	var script: Variant = load("res://src/voxel/character_builder.gd")
	for m in (script as Script).get_script_method_list():
		if m["name"] == "random_appearance":
			return script.call("random_appearance", rng, gender)
	var ap := DB.appearance
	var pick := func(key: String, fallback: Variant) -> Variant:
		var arr: Array = ap.get(key, [])
		if arr.is_empty():
			return fallback
		var v = arr[rng.randi() % arr.size()]
		return v["id"] if v is Dictionary else v
	var a := {
		"gender": gender,
		"height": rng.randf_range(0.94, 1.06) if gender == "female" else rng.randf_range(1.0, 1.1),
		"build": rng.randf_range(0.2, 0.9),
		"skin": pick.call("skin_colors", "#f3d2bd"),
		"hair_style": pick.call("hair_styles", "long"),
		"hair_color": pick.call("hair_colors", "#1a1a22"),
		"eye_color": pick.call("eye_colors", "#3a2a1a"),
		"eye_style": pick.call("eye_styles", "almond"),
		"ears": "human" if rng.randf() < 0.85 else pick.call("ears", "human"),
		"tail": "none",
		"horns": "none" if rng.randf() < 0.95 else "dragon",
		"mark": "none" if rng.randf() < 0.7 else pick.call("marks", "none"),
		"outfit": pick.call("outfits", "robe"),
		"outfit_colors": pick.call("outfit_palettes", ["#8a8a7a", "#4a4a40", "#c0b080"]),
	}
	a["hair_color2"] = Color.html(a["hair_color"]).lightened(0.25).to_html(false)
	if a["ears"] == "fox" and rng.randf() < 0.5:
		a["tail"] = "fox"
	if gender == "male" and a["hair_style"] == "twin_tails":
		a["hair_style"] = "ponytail"
	return a
