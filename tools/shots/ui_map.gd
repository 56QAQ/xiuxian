extends RefCounted
## 界面截图：舆图（程序生成的假底图 + 五宗/坊市/洞府/秘境标记 + 玩家箭头）

var ui: UIManager


func frames() -> int:
	return 26


func build(root: Node) -> void:
	UIShotCommon.new_game()
	UIShotCommon.backdrop(root)
	ui = UIShotCommon.manager(root)


static func fake_map(n: int = 256) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.012
	noise.fractal_octaves = 5
	var regions := {
		Vector2(0.5, 0.12): Color(0.86, 0.88, 0.92), Vector2(0.86, 0.45): Color(0.25, 0.5, 0.25),
		Vector2(0.5, 0.88): Color(0.22, 0.4, 0.62), Vector2(0.12, 0.45): Color(0.6, 0.3, 0.2), Vector2(0.2, 0.8): Color(0.66, 0.56, 0.32),
	}
	for y in n:
		for x in n:
			var u := Vector2(x, y) / n
			var h := noise.get_noise_2d(x, y) * 0.5 + 0.5 - u.distance_to(Vector2(0.5, 0.5)) * 0.35
			var c := Color(0.42, 0.55, 0.3)
			var best := 9.0
			for k in regions:
				var d: float = u.distance_to(k)
				if d < best:
					best = d
					c = Color(0.42, 0.55, 0.3).lerp(regions[k], clampf(1.2 - d * 3.0, 0.0, 0.85))
			if h < 0.28:
				c = Color(0.2, 0.36, 0.55).lerp(Color(0.3, 0.48, 0.66), h / 0.28)
			elif h > 0.62:
				c = c.lerp(Color(0.55, 0.53, 0.5), clampf((h - 0.62) * 4.0, 0.0, 1.0))
			if h > 0.74:
				c = c.lerp(Color(0.95, 0.95, 0.97), clampf((h - 0.74) * 6.0, 0.0, 1.0))
			img.set_pixel(x, y, c.darkened(0.08 - h * 0.1))
	return img


func step(_root: Node, frame: int) -> void:
	if frame != 1:
		return
	var pois := [
		{"name": "天剑宗", "type": "sect", "pos": Vector3(512, 0, 120), "color": "#e8ecf4", "desc": "北部雪峰，剑修圣地"},
		{"name": "青木谷", "type": "sect", "pos": Vector3(880, 0, 460), "color": "#5ab86a"},
		{"name": "玄水阁", "type": "sect", "pos": Vector3(512, 0, 900), "color": "#3a6ad0"},
		{"name": "离火殿", "type": "sect", "pos": Vector3(120, 0, 460), "color": "#c8281c"},
		{"name": "厚土宗", "type": "sect", "pos": Vector3(210, 0, 820), "color": "#c09040"},
		{"name": "青云坊市", "type": "town", "pos": Vector3(520, 0, 520), "desc": "散修聚集之地"},
		{"name": "洞府", "type": "home", "pos": Vector3(600, 0, 610)},
		{"name": "落霞秘境", "type": "realm", "pos": Vector3(700, 0, 300), "desc": "炼气期 · 林地"},
		{"name": "赤岩火窟", "type": "realm", "pos": Vector3(250, 0, 360), "desc": "炼气后期 · 火山"},
		{"name": "天材地宝出世", "type": "treasure", "pos": Vector3(380, 0, 640)},
		{"name": "血煞宗据点", "type": "danger", "pos": Vector3(820, 0, 820)},
	]
	ui.open("map", {"image": fake_map(), "pois": pois, "player_pos": Vector3(560, 0, 575), "player_yaw": 0.8, "world_size": 1024})
