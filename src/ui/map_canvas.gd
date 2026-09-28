class_name MapCanvas
extends Control
## 可平移/缩放的地图画布：底图 + 坐标网格 + 兴趣点（图标与名称）+ 玩家箭头。
## 世界坐标 (x, z) → 底图：u = (x - origin.x) / world_size，v = (z - origin.y) / world_size。

signal poi_hovered(poi: Dictionary)

const POI_STYLE := {
	"sect": {"glyph": "宗", "color": Color(0.95, 0.8, 0.45)},
	"town": {"glyph": "市", "color": Color(1.0, 0.72, 0.3)},
	"market": {"glyph": "市", "color": Color(1.0, 0.72, 0.3)},
	"home": {"glyph": "府", "color": Color(0.45, 0.9, 0.7)},
	"realm": {"glyph": "秘", "color": Color(0.78, 0.5, 1.0)},
	"treasure": {"glyph": "宝", "color": Color(1.0, 0.55, 0.2)},
	"npc": {"glyph": "人", "color": Color(0.75, 0.85, 1.0)},
	"extract": {"glyph": "阵", "color": Color(0.4, 0.95, 0.6)},
	"beast": {"glyph": "妖", "color": Color(1.0, 0.4, 0.3)},
	"danger": {"glyph": "险", "color": Color(1.0, 0.35, 0.3)},
	"portal": {"glyph": "门", "color": Color(0.5, 0.8, 1.0)},
	"quest": {"glyph": "令", "color": Color(1.0, 0.9, 0.4)},
}

var texture: Texture2D
var world_size: float = 1024.0
var origin: Vector2 = Vector2.ZERO
var pois: Array = []
var player_pos: Vector3 = Vector3.INF
## 玩家朝向（弧度，绕 Y；0 表示朝 -Z）
var player_yaw: float = 0.0
var zoom: float = 1.0
var center: Vector2 = Vector2(0.5, 0.5)   ## 视图中心（归一化底图坐标）

var _drag: bool = false
var _hover: int = -1
var _time: float = 0.0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(400, 400)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## 地图像素尺寸（zoom=1 时占满较短边）
func _map_px() -> float:
	return minf(size.x, size.y) * zoom


func norm_of(p: Variant) -> Vector2:
	var w := Vector2.ZERO
	if p is Vector3:
		w = Vector2(p.x, p.z)
	elif p is Vector2:
		w = p
	elif p is Array and (p as Array).size() >= 2:
		var a: Array = p
		w = Vector2(float(a[0]), float(a[2] if a.size() >= 3 else a[1]))
	return (w - origin) / maxf(world_size, 1.0)


func to_screen(n: Vector2) -> Vector2:
	return size * 0.5 + (n - center) * _map_px()


func to_norm(s: Vector2) -> Vector2:
	return center + (s - size * 0.5) / _map_px()


func center_on(n: Vector2) -> void:
	center = n
	_clamp()


func set_zoom(z: float, anchor_screen: Vector2 = Vector2(-1, -1)) -> void:
	if anchor_screen.x < 0:
		anchor_screen = size * 0.5
	var before := to_norm(anchor_screen)
	zoom = clampf(z, 0.6, 8.0)
	var after := to_norm(anchor_screen)
	center += before - after
	_clamp()


func _clamp() -> void:
	center = center.clamp(Vector2(0.0, 0.0), Vector2(1.0, 1.0))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.06, 0.07))
	var tl := to_screen(Vector2.ZERO)
	var mp := _map_px()
	var mr := Rect2(tl, Vector2(mp, mp))
	if texture != null:
		draw_texture_rect(texture, mr, false, Color(0.92, 0.9, 0.84))
	else:
		draw_rect(mr, Color(0.2, 0.22, 0.2))
	# 宣纸色调与网格
	draw_rect(mr, Color(0.35, 0.28, 0.18, 0.12))
	var divs := 8
	for i in divs + 1:
		var f := float(i) / divs
		var gc := Color(0.1, 0.07, 0.04, 0.22 if i % 4 else 0.35)
		draw_line(Vector2(mr.position.x + mp * f, mr.position.y), Vector2(mr.position.x + mp * f, mr.end.y), gc, 1.0)
		draw_line(Vector2(mr.position.x, mr.position.y + mp * f), Vector2(mr.end.x, mr.position.y + mp * f), gc, 1.0)
	draw_rect(mr, Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.7), false, 2.0)
	# 兴趣点
	var f2 := UITheme.font_title()
	var lf := UITheme.font_regular()
	for i in pois.size():
		var poi: Dictionary = pois[i]
		var sp := to_screen(norm_of(poi.get("pos", Vector3.ZERO)))
		if not Rect2(Vector2(-60, -60), size + Vector2(120, 120)).has_point(sp):
			continue
		var stl: Dictionary = POI_STYLE.get(str(poi.get("type", "")), {"glyph": "◆", "color": UITheme.GOLD})
		var c: Color = stl["color"]
		if poi.has("color"):
			c = CharacterBuilder.col(poi["color"], c)
		var hovered := i == _hover
		var r := 13.0 if not hovered else 16.0
		draw_circle(sp + Vector2(1, 2), r, Color(0, 0, 0, 0.45))
		draw_circle(sp, r, Color(c.r * 0.22, c.g * 0.22, c.b * 0.22, 0.95))
		draw_arc(sp, r, 0, TAU, 24, c, 2.0, true)
		var g := str(poi.get("glyph", stl["glyph"]))
		var gs := f2.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string(f2, sp + Vector2(-gs.x * 0.5, 6), g, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, c.lightened(0.25))
		if zoom >= 0.9 or hovered:
			var nm := str(poi.get("name", ""))
			var ns := lf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
			var np := sp + Vector2(-ns.x * 0.5, r + 17)
			draw_string_outline(lf, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0.05, 0.04, 0.03, 0.9))
			draw_string(lf, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.96, 0.88) if hovered else Color(0.95, 0.9, 0.8))
	# 玩家
	if player_pos != Vector3.INF:
		var pp := to_screen(norm_of(player_pos))
		var pulse := fmod(_time, 1.6) / 1.6
		draw_arc(pp, 10.0 + pulse * 22.0, 0, TAU, 32, Color(1.0, 0.3, 0.25, 0.7 * (1.0 - pulse)), 2.0, true)
		var dir := Vector2(-sin(player_yaw), -cos(player_yaw))
		var side := dir.orthogonal()
		var tri := PackedVector2Array([pp + dir * 14.0, pp - dir * 8.0 + side * 9.0, pp - dir * 3.0, pp - dir * 8.0 - side * 9.0])
		draw_colored_polygon(tri, Color(1.0, 0.32, 0.25))
		tri.append(tri[0])
		draw_polyline(tri, Color(1, 0.95, 0.85), 1.5, true)
	# 暗角
	var vg := Color(0, 0, 0, 0.35)
	draw_rect(Rect2(Vector2.ZERO, size), vg, false, 6.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_drag = event.pressed
			if event.pressed and event.double_click:
				set_zoom(zoom * 1.6, event.position)
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(zoom * 1.15, event.position)
			accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(zoom / 1.15, event.position)
			accept_event()
	elif event is InputEventMouseMotion:
		if _drag:
			center -= event.relative / _map_px()
			_clamp()
		var best := -1
		var bd := 18.0
		for i in pois.size():
			var d: float = to_screen(norm_of(pois[i].get("pos", Vector3.ZERO))).distance_to(event.position)
			if d < bd:
				bd = d
				best = i
		if best != _hover:
			_hover = best
			if best >= 0:
				poi_hovered.emit(pois[best])


func _get_tooltip(at: Vector2) -> String:
	if _hover < 0 or _hover >= pois.size():
		var n := to_norm(at)
		var w := origin + n * world_size
		return "坐标 %d, %d" % [int(w.x), int(w.y)]
	var poi: Dictionary = pois[_hover]
	var t := str(poi.get("name", ""))
	if poi.has("desc"):
		t += "\n" + str(poi["desc"])
	return t
