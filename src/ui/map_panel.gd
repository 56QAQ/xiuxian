class_name MapPanel
extends UIWindow
## 地图面板。args: {"image": Image, "pois": [{"name", "type", "pos": Vector3, "desc"?, "color"?}],
##                  "player_pos": Vector3, "player_yaw"?: float, "world_size": 1024, "origin"?: Vector2（底图左上角的世界坐标 x,z，默认 0,0）,
##                  "title"?: String}
## POI type：sect town market home realm treasure npc extract beast danger portal quest（其他显示为菱形）。

const TYPE_NAMES := {"sect": "宗门", "town": "坊市", "market": "坊市", "home": "洞府", "realm": "秘境", "treasure": "天材地宝",
	"npc": "修士", "extract": "撤离阵", "beast": "妖兽", "danger": "险地", "portal": "传送阵", "quest": "任务"}

var _map: MapCanvas
var _coords: Label
var _list: VBoxContainer


func _init() -> void:
	super()


func _build() -> void:
	set_title(str(args.get("title", "舆图")))
	var row := UITheme.hbox(16)
	add(row)
	var mp := PanelContainer.new()
	mp.theme_type_variation = "InsetPanel"
	_map = MapCanvas.new()
	_map.custom_minimum_size = Vector2(860, 660)
	var img: Image = args.get("image", null)
	if img != null:
		var tex := ImageTexture.create_from_image(img)
		_map.texture = tex
	_map.world_size = float(args.get("world_size", 1024))
	_map.origin = args.get("origin", Vector2.ZERO)
	_map.pois = args.get("pois", [])
	_map.player_pos = args.get("player_pos", Vector3.INF)
	_map.player_yaw = float(args.get("player_yaw", 0.0))
	mp.add_child(_map)
	row.add_child(mp)
	var side := UITheme.vbox(8)
	side.custom_minimum_size.x = 280
	var tools := UITheme.hbox(6)
	tools.add_child(UITheme.button("＋", "ChipButton", func() -> void: _map.set_zoom(_map.zoom * 1.3)))
	tools.add_child(UITheme.button("－", "ChipButton", func() -> void: _map.set_zoom(_map.zoom / 1.3)))
	tools.add_child(UITheme.button("我的位置", "ChipButton", _center_player))
	tools.add_child(UITheme.button("全图", "ChipButton", func() -> void:
		_map.zoom = 1.0
		_map.center_on(Vector2(0.5, 0.5))))
	side.add_child(tools)
	_coords = UITheme.label("", 15, UITheme.TEXT_DIM)
	side.add_child(_coords)
	side.add_child(UITheme.header("要地", 18))
	var lp := PanelContainer.new()
	lp.theme_type_variation = "InsetPanel"
	_list = UITheme.vbox(4)
	var sc := UITheme.scroll(_list)
	sc.custom_minimum_size = Vector2(260, 500)
	lp.add_child(sc)
	side.add_child(lp)
	side.add_child(UITheme.label("拖动平移 · 滚轮缩放 · 双击放大", 13, UITheme.TEXT_FAINT))
	row.add_child(side)
	_fill_list()
	if _map.player_pos != Vector3.INF:
		_map.zoom = 1.6
		_center_player()


func refresh() -> void:
	if _coords == null:
		return
	if _map.player_pos != Vector3.INF:
		_coords.text = "当前位置：%d, %d  ·  %s" % [int(_map.player_pos.x), int(_map.player_pos.z), GS.date_text() if GS.active else ""]


func _center_player() -> void:
	if _map.player_pos != Vector3.INF:
		_map.center_on(_map.norm_of(_map.player_pos))


func _fill_list() -> void:
	UIWindow.clear_children(_list)
	var by_type := {}
	for p in _map.pois:
		var t := str(p.get("type", ""))
		if not by_type.has(t):
			by_type[t] = []
		by_type[t].append(p)
	if _map.pois.is_empty():
		_list.add_child(UITheme.label("此地尚无标记。", 16, UITheme.TEXT_FAINT))
	for t in by_type:
		var stl: Dictionary = MapCanvas.POI_STYLE.get(t, {"glyph": "◆", "color": UITheme.GOLD})
		_list.add_child(UITheme.label("%s %s" % [stl["glyph"], TYPE_NAMES.get(t, "其他")], 16, stl["color"]))
		for p2 in by_type[t]:
			var poi: Dictionary = p2
			var b := UITheme.button(str(poi.get("name", "")), "ListButton", func() -> void:
				_map.zoom = maxf(_map.zoom, 2.0)
				_map.center_on(_map.norm_of(poi.get("pos", Vector3.ZERO))))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", 15)
			b.custom_minimum_size.y = 32
			if poi.has("desc"):
				b.tooltip_text = str(poi["desc"])
			_list.add_child(b)
