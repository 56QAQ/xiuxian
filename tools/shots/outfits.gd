extends RefCounted
## 服饰展示：战甲 / 道袍 / 劲装 × 女 / 男（其余外貌为典型搭配）


func frames() -> int:
	return 40


func build(root: Node) -> void:
	ArtStudio.setup(root, Vector3(0, 1.25, 8.6), Vector3(0, 0.95, 0), 30.0)
	var looks := [
		{"gender": "female", "outfit": "armor"},
		{"gender": "female", "outfit": "robe", "hair_style": "long", "hair_color": "#1a1a22", "hair_color2": "#50506a", "ears": "human", "mark": "lotus", "eye_color": "#3080f0", "outfit_colors": ["#e8ecf4", "#4a5a78", "#d8b050"]},
		{"gender": "female", "outfit": "martial", "hair_style": "ponytail", "hair_color": "#8a4a2a", "hair_color2": "#c07a4a", "ears": "cat", "ear_color": "#6a3a20", "eye_color": "#40c060", "outfit_colors": ["#5ab86a", "#2a4a30", "#e0d8a0"]},
		{"gender": "male", "outfit": "armor", "hair_style": "short", "hair_color": "#1a1a22", "hair_color2": "#4a4a60", "ears": "human", "eye_color": "#d02020", "brow_style": 2},
		{"gender": "male", "outfit": "robe", "hair_style": "bun", "hair_color": "#1a1a22", "hair_color2": "#4a4a60", "ears": "human", "eye_color": "#1a1a1a", "outfit_colors": ["#3a6ad0", "#1a2a50", "#c8e0ff"]},
		{"gender": "male", "outfit": "martial", "hair_style": "ponytail", "hair_color": "#e8c060", "hair_color2": "#fff0a0", "ears": "human", "eye_color": "#3080f0", "outfit_colors": ["#2a2a30", "#101014", "#c02030"]},
	]
	for i in looks.size():
		var rig := CharacterBuilder.build(looks[i])
		rig.position = Vector3(-3.25 + i * 1.3, 0, 0)
		rig.rotation_degrees.y = 180.0 + (20.0 if i % 2 == 1 else -15.0)
		rig.stance = "none"
		root.add_child(rig)
