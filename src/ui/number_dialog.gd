class_name NumberDialog
extends UIWindow
## 数量选择框（拆分堆叠、批量购买等）。on_ok(value: int)

var min_value: int = 1
var max_value: int = 1
var value: int = 1
var hint: String = ""
var on_ok: Callable

var _slider: HSlider
var _spin: SpinBox
var _updating: bool = false


func _init() -> void:
	super()
	modal = true
	auto_refresh = false


func setup(p_title: String, p_min: int, p_max: int, p_default: int, p_on_ok: Callable, p_hint: String = "") -> NumberDialog:
	window_title = p_title
	min_value = p_min
	max_value = maxi(p_max, p_min)
	value = clampi(p_default, min_value, max_value)
	on_ok = p_on_ok
	hint = p_hint
	return self


func _build() -> void:
	custom_minimum_size = Vector2(440, 0)
	if hint != "":
		var h := UITheme.wrap_label(hint, 17, UITheme.TEXT_DIM)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add(h)
	var row := UITheme.hbox(10)
	var minus := UITheme.button("－", "", func() -> void: _set_value(value - 1))
	minus.custom_minimum_size = Vector2(40, 36)
	row.add_child(minus)
	_slider = HSlider.new()
	_slider.min_value = min_value
	_slider.max_value = max_value
	_slider.step = 1
	_slider.value = value
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(func(v: float) -> void: _set_value(int(v)))
	row.add_child(_slider)
	var plus := UITheme.button("＋", "", func() -> void: _set_value(value + 1))
	plus.custom_minimum_size = Vector2(40, 36)
	row.add_child(plus)
	_spin = SpinBox.new()
	_spin.min_value = min_value
	_spin.max_value = max_value
	_spin.step = 1
	_spin.value = value
	_spin.custom_minimum_size.x = 96
	_spin.value_changed.connect(func(v: float) -> void: _set_value(int(v)))
	row.add_child(_spin)
	add(row)
	var quick := UITheme.hbox(8)
	quick.alignment = BoxContainer.ALIGNMENT_CENTER
	for pair in [["最少", min_value], ["一半", maxi(min_value, max_value / 2)], ["最多", max_value]]:
		var b := UITheme.button(str(pair[0]), "ChipButton", _set_value.bind(int(pair[1])))
		quick.add_child(b)
	add(quick)
	add(UITheme.separator())
	var btns := UITheme.hbox(24)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	var no := UITheme.button("取消", "", close)
	no.custom_minimum_size.x = 120
	btns.add_child(no)
	var ok := UITheme.button("确定", "JadeButton", _on_ok)
	ok.custom_minimum_size.x = 120
	btns.add_child(ok)
	add(btns)


func _set_value(v: int) -> void:
	if _updating:
		return
	_updating = true
	value = clampi(v, min_value, max_value)
	_slider.value = value
	_spin.value = value
	_updating = false


func _on_ok() -> void:
	close()
	if on_ok.is_valid():
		on_ok.call(value)
