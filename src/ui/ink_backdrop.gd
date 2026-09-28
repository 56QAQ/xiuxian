class_name InkBackdrop
extends Control
## 水墨远山背景：夜空渐变 + 明月 + 多层山峦视差（随时间缓慢漂移、随鼠标轻微偏移）+ 谷间云雾 + 松影。
## 主菜单与界面截图使用。

## 整体压暗（0~1）
@export var dim: float = 0.0
## 漂移速度（像素/秒，最远层）
@export var drift: float = 6.0
## 鼠标视差强度
@export var parallax: float = 18.0
@export var seed_value: int = 20240
## 月亮位置（相对尺寸）
@export var moon_pos: Vector2 = Vector2(0.73, 0.2)

const LAYERS := [
	{"base": 0.60, "amp": 0.24, "freq": 0.0021, "sharp": 1.6, "col": Color(0.32, 0.33, 0.43), "speed": 0.2, "depth": 0.15},
	{"base": 0.67, "amp": 0.24, "freq": 0.0028, "sharp": 1.9, "col": Color(0.22, 0.23, 0.31), "speed": 0.4, "depth": 0.3},
	{"base": 0.75, "amp": 0.21, "freq": 0.0036, "sharp": 2.2, "col": Color(0.14, 0.15, 0.21), "speed": 0.7, "depth": 0.5},
	{"base": 0.85, "amp": 0.17, "freq": 0.0046, "sharp": 2.0, "col": Color(0.085, 0.09, 0.13), "speed": 1.1, "depth": 0.75},
	{"base": 0.97, "amp": 0.13, "freq": 0.006, "sharp": 1.6, "col": Color(0.035, 0.038, 0.055), "speed": 1.6, "depth": 1.0},
]
const MIST := Color(0.5, 0.5, 0.58)

var _ridges: Array = []      ## 每层 PackedVector2Array（宽度为两倍屏宽，可循环）
var _pines: Array = []       ## 每层松树位置
var _built_size: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _mouse: Vector2 = Vector2.ZERO
var _clouds: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in 7:
		_clouds.append({"x": rng.randf(), "y": rng.randf_range(0.18, 0.62), "w": rng.randf_range(0.18, 0.4), "h": rng.randf_range(0.018, 0.04), "a": rng.randf_range(0.05, 0.14), "v": rng.randf_range(4.0, 12.0)})


func _process(delta: float) -> void:
	_time += delta
	var vp := get_viewport_rect().size
	var m := get_viewport().get_mouse_position()
	var target := ((m / vp) - Vector2(0.5, 0.5)) if vp.x > 0 else Vector2.ZERO
	_mouse = _mouse.lerp(target, 1.0 - exp(-2.0 * delta))
	queue_redraw()


func _build() -> void:
	_built_size = size
	_ridges.clear()
	_pines.clear()
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var W := size.x * 2.0
	for li in LAYERS.size():
		var L: Dictionary = LAYERS[li]
		var pts := PackedVector2Array()
		var pines := PackedVector2Array()
		var step := 6.0
		var n := int(W / step) + 2
		var base: float = size.y * float(L["base"])
		var amp: float = size.y * float(L["amp"])
		for i in n:
			var x := i * step
			# 循环：首尾衔接（x 在 [0, W) 上取周期）
			var u := x / W * TAU
			var r := 400.0 / float(L["freq"]) / 1000.0
			var nx := cos(u) * r * 0.2
			var ny := sin(u) * r * 0.2
			var v := noise.get_noise_3d(nx, ny, li * 37.0)
			var ridge := pow(1.0 - absf(noise.get_noise_3d(nx * 1.7, ny * 1.7, li * 11.0 + 5.0)), float(L["sharp"]))
			var hgt := amp * (0.45 * (v + 0.5) + 0.75 * ridge)
			pts.append(Vector2(x, base - hgt))
			if li >= 2 and i % 3 == 0 and ridge > 0.72:
				pines.append(Vector2(x, base - hgt))
		_ridges.append(pts)
		_pines.append(pines)


func _draw() -> void:
	if size.x < 2.0:
		return
	if size != _built_size:
		_build()
	var w := size.x
	var h := size.y
	# 天空
	var top := Color(0.035, 0.04, 0.075)
	var mid := Color(0.11, 0.11, 0.17)
	var hor := Color(0.36, 0.31, 0.34)
	_vgrad(0.0, h * 0.45, top, mid)
	_vgrad(h * 0.45, h * 0.8, mid, hor)
	draw_rect(Rect2(0, h * 0.8, w, h * 0.2), hor)
	# 月与月晕
	var glow := UITheme.icon("dot")
	var mp := Vector2(w * moon_pos.x, h * moon_pos.y) + _mouse * parallax * -0.1
	var mr := h * 0.075
	draw_texture_rect(glow, Rect2(mp - Vector2(mr, mr) * 7.0, Vector2(mr, mr) * 14.0), false, Color(1.0, 0.85, 0.6, 0.16))
	draw_texture_rect(glow, Rect2(mp - Vector2(mr, mr) * 3.0, Vector2(mr, mr) * 6.0), false, Color(1.0, 0.92, 0.75, 0.25))
	draw_circle(mp, mr, Color(0.98, 0.95, 0.86))
	draw_circle(mp + Vector2(mr * 0.25, -mr * 0.15), mr * 0.28, Color(0.9, 0.87, 0.78, 0.5))
	draw_circle(mp + Vector2(-mr * 0.35, mr * 0.3), mr * 0.18, Color(0.9, 0.87, 0.78, 0.45))
	# 星
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 3
	for i in 70:
		var sp := Vector2(rng.randf() * w, rng.randf() * h * 0.5)
		var tw := 0.5 + 0.5 * sin(_time * rng.randf_range(0.5, 2.0) + i)
		draw_rect(Rect2(sp, Vector2(1.5, 1.5)), Color(1, 1, 1, 0.15 + 0.35 * tw * rng.randf()))
	# 云带
	for c in _clouds:
		var cx := fmod(float(c["x"]) * w * 1.4 + _time * float(c["v"]), w * 1.4) - w * 0.2
		var cr := Rect2(cx, float(c["y"]) * h, float(c["w"]) * w, float(c["h"]) * h * 3.0)
		draw_texture_rect(glow, cr, false, Color(0.75, 0.74, 0.8, float(c["a"])))
	# 山峦（远 → 近）
	for li in LAYERS.size():
		var L: Dictionary = LAYERS[li]
		var pts: PackedVector2Array = _ridges[li]
		var span := w * 2.0
		var off := fmod(_time * drift * float(L["speed"]), span) + _mouse.x * parallax * float(L["depth"])
		var yoff := _mouse.y * parallax * 0.4 * float(L["depth"])
		var col: Color = L["col"]
		for rep in [-1, 0, 1]:
			var ox: float = -off + rep * span
			if ox > w or ox + span < 0:
				continue
			var poly := PackedVector2Array()
			for p in pts:
				poly.append(Vector2(p.x + ox, p.y + yoff))
			poly.append(Vector2(ox + span, h + 10))
			poly.append(Vector2(ox, h + 10))
			draw_colored_polygon(poly, col)
			# 松影
			var pines: PackedVector2Array = _pines[li]
			for pp in pines:
				var q := Vector2(pp.x + ox, pp.y + yoff)
				if q.x < -20 or q.x > w + 20:
					continue
				_pine(q, 5.0 + li * 2.0, col.darkened(0.25))
		# 谷间云雾
		var base: float = h * float(L["base"]) + yoff
		var mist_a := 0.34 - li * 0.045
		_vgrad(base - h * 0.14, base + h * 0.02, Color(MIST.r, MIST.g, MIST.b, 0.0), Color(MIST.r, MIST.g, MIST.b, mist_a))
		if li < LAYERS.size() - 1:
			draw_rect(Rect2(0, base + h * 0.02, w, h), Color(MIST.r, MIST.g, MIST.b, mist_a * 0.35))
	# 压暗与暗角
	if dim > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.01, 0.02, dim))
	_vgrad(h * 0.75, h, Color(0, 0, 0, 0), Color(0, 0, 0, 0.45))


func _vgrad(y0: float, y1: float, c0: Color, c1: Color) -> void:
	var w := size.x
	draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0, y1)]), PackedColorArray([c0, c0, c1, c1]))


func _pine(p: Vector2, s: float, c: Color) -> void:
	draw_line(p, p + Vector2(0, -s * 2.2), c, maxf(1.0, s * 0.15))
	for i in 3:
		var y := p.y - s * (0.6 + i * 0.55)
		var hw := s * (0.9 - i * 0.22)
		draw_colored_polygon(PackedVector2Array([Vector2(p.x - hw, y), Vector2(p.x + hw, y), Vector2(p.x, y - s * 0.7)]), c)
