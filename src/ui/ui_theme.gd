class_name UITheme
extends RefCounted
## 全局界面主题（纯代码生成）：漆墨底 + 宣纸纤维 · 双金线 · 祥云角 · 回纹带 · 书法标题 · 委角牌匾按钮 ·
## 笔触页签/菜单/提示 · 玉牌 · 宣纸提示框。纹理见 assets/textures/ui（tools/gen_ui_textures.py），绘制工具见 InkArt。
## Settings._ready() 中：get_tree().root.theme = UITheme.get_theme()
##
## 主题类型变体（Control.theme_type_variation）：
##   Label：TitleLabel HeaderLabel DimLabel SmallLabel GoldLabel ParchmentLabel
##   Button：PrimaryButton JadeButton MenuItem ChipButton TabButton IconButton ListButton SwatchButton
##   PanelContainer：WindowPanel InsetPanel CardPanel CardSelected ParchmentPanel TitleBar ToastPanel HudPanel
##   ProgressBar：ExpBar

# ---------------------------------------------------------------- 调色
const INK := Color(0.052, 0.056, 0.07, 0.95)
const INK_BROWN := Color(0.1, 0.09, 0.08, 0.95)
const INK_LIGHT := Color(0.15, 0.14, 0.13, 0.92)
const GOLD := Color(0.84, 0.68, 0.4)
const GOLD_BRIGHT := Color(1.0, 0.86, 0.56)
const GOLD_DIM := Color(0.55, 0.44, 0.27)
const JADE := Color(0.4, 0.82, 0.66)
const JADE_DEEP := Color(0.13, 0.36, 0.3)
const CINNABAR := Color(0.86, 0.27, 0.2)
const CINNABAR_DEEP := Color(0.42, 0.1, 0.08)
const PARCHMENT := Color(0.93, 0.87, 0.73)
const PARCHMENT_DARK := Color(0.82, 0.73, 0.56)
const PARCHMENT_INK := Color(0.2, 0.14, 0.09)
const TEXT := Color(0.93, 0.9, 0.83)
const TEXT_DIM := Color(0.66, 0.62, 0.55)
const TEXT_FAINT := Color(0.45, 0.43, 0.4)
const GOOD := Color(0.45, 0.88, 0.55)
const WARN := Color(1.0, 0.76, 0.3)
const BAD := Color(1.0, 0.4, 0.34)

## 提示种类配色（Events.notify）
const KIND_COLORS := {
	"info": Color(0.78, 0.86, 0.95),
	"good": Color(0.45, 0.88, 0.62),
	"warn": Color(1.0, 0.76, 0.3),
	"bad": Color(1.0, 0.38, 0.32),
	"loot": Color(1.0, 0.84, 0.45),
	"realm": Color(1.0, 0.86, 0.56),
}

const FONT_REGULAR := "res://assets/fonts/XianKai-Regular.ttf"
const FONT_MEDIUM := "res://assets/fonts/XianKai-Medium.ttf"
## 书法字体（马善政毛笔楷书子集，改名 XianShu）：标题、横幅、HUD 数字
const FONT_DISPLAY := "res://assets/fonts/XianShu-Regular.ttf"

static var _theme: Theme = null
static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}


# ================================================================ 主题

static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func font_regular() -> Font:
	return _font(FONT_REGULAR)


static func font_title() -> Font:
	return _font(FONT_MEDIUM)


## 书法字体；缺字回落到 XianKai
static func font_display() -> Font:
	if not _fonts.has(FONT_DISPLAY):
		var f: Font = null
		if ResourceLoader.exists(FONT_DISPLAY):
			var ff: FontFile = load(FONT_DISPLAY)
			if ff != null:
				ff.fallbacks = [font_title()]
				f = ff
		_fonts[FONT_DISPLAY] = f if f != null else font_title()
	return _fonts[FONT_DISPLAY]


static func _font(path: String) -> Font:
	if not _fonts.has(path):
		var f: Font = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
		_fonts[path] = f
	return _fonts[path]


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = font_regular()
	t.default_font_size = 18

	# ---- Label
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("line_spacing", "Label", 2)
	_label_var(t, "TitleLabel", GOLD_BRIGHT, 32, true)
	t.set_font("font", "TitleLabel", font_display())
	t.set_color("font_outline_color", "TitleLabel", Color(0.08, 0.05, 0.02, 0.9))
	t.set_constant("outline_size", "TitleLabel", 6)
	t.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "TitleLabel", 0)
	t.set_constant("shadow_offset_y", "TitleLabel", 3)
	_label_var(t, "HeaderLabel", GOLD, 23, true)
	t.set_font("font", "HeaderLabel", font_display())
	t.set_color("font_outline_color", "HeaderLabel", Color(0.05, 0.03, 0.02, 0.8))
	t.set_constant("outline_size", "HeaderLabel", 3)
	_label_var(t, "DisplayLabel", TEXT, 22, true)
	t.set_font("font", "DisplayLabel", font_display())
	_label_var(t, "GoldLabel", GOLD_BRIGHT, 18, false)
	_label_var(t, "DimLabel", TEXT_DIM, 16, false)
	_label_var(t, "SmallLabel", TEXT_DIM, 14, false)
	_label_var(t, "ParchmentLabel", PARCHMENT_INK, 17, false)

	# ---- 面板
	t.set_stylebox("panel", "PanelContainer", _ink_box(0, 10))
	t.set_stylebox("panel", "Panel", _ink_box(0, 0))
	t.set_type_variation("WindowPanel", "PanelContainer")
	var win := _ink_box(4, 0)
	win.set_margins(24, 14, 24, 20)
	win.shadow_size = 28.0
	win.shadow_color = Color(0, 0, 0, 0.6)
	win.border_width = 1.5
	win.inner_line_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.3)
	win.inner_inset = 6.0
	win.corner_len = 13.0
	win.ornament_color = Color(0.96, 0.8, 0.5, 0.72)
	win.top_glow = 1.0
	win.wash = 1.0
	win.watermark = 1.0
	win.paper_color = Color(1.0, 0.9, 0.72, 0.04)
	win.mottle_color = Color(0.0, 0.0, 0.0, 0.16)
	win.hui_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.12)
	t.set_stylebox("panel", "WindowPanel", win)
	t.set_type_variation("InsetPanel", "PanelContainer")
	var inset := OrnateBox.new()
	inset.bg_top = Color(0, 0, 0, 0.34)
	inset.bg_bottom = Color(0, 0, 0, 0.22)
	inset.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.2)
	inset.chamfer = 4.0
	inset.mottle_color = Color(0, 0, 0, 0.1)
	inset.set_all_margins(10)
	t.set_stylebox("panel", "InsetPanel", inset)
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", card_box(false))
	t.set_type_variation("CardSelected", "PanelContainer")
	t.set_stylebox("panel", "CardSelected", card_box(true))
	t.set_type_variation("ParchmentPanel", "PanelContainer")
	t.set_stylebox("panel", "ParchmentPanel", parchment_box())
	t.set_type_variation("TitleBar", "PanelContainer")
	var bar := OrnateBox.new()
	bar.bg_top = Color(0.2, 0.16, 0.1, 0.55)
	bar.bg_bottom = Color(0.06, 0.05, 0.04, 0.0)
	bar.border_width = 0.0
	bar.set_margins(8, 4, 8, 6)
	t.set_stylebox("panel", "TitleBar", bar)
	t.set_type_variation("ToastPanel", "PanelContainer")
	var toast := OrnateBox.new()
	toast.brush = 1.0
	toast.brush_color = Color(0.025, 0.02, 0.02, 0.84)
	toast.brush_u1 = 0.8
	toast.border_width = 0.0
	toast.set_margins(14, 9, 44, 10)
	t.set_stylebox("panel", "ToastPanel", toast)
	t.set_type_variation("HudPanel", "PanelContainer")
	var hud := _ink_box(3, 8)
	hud.bg_top = Color(0.04, 0.045, 0.055, 0.72)
	hud.bg_bottom = Color(0.04, 0.045, 0.055, 0.72)
	hud.chamfer = 5.0
	t.set_stylebox("panel", "HudPanel", hud)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# ---- 提示框（宣纸）
	var tip := parchment_box()
	tip.set_margins(16, 12, 16, 14)
	tip.shadow_size = 12.0
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", PARCHMENT_INK)
	t.set_font_size("font_size", "TooltipLabel", 16)
	t.set_color("font_shadow_color", "TooltipLabel", Color(0, 0, 0, 0))

	# ---- 按钮
	_button(t, "Button", _btn_box(INK_LIGHT, GOLD_DIM, 0), _btn_box(Color(0.24, 0.2, 0.15, 0.95), GOLD, 2),
		_btn_box(Color(0.12, 0.3, 0.25, 0.95), JADE, 2), _btn_box(Color(0.1, 0.1, 0.1, 0.6), Color(0.3, 0.3, 0.3, 0.5), 0))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD_BRIGHT)
	t.set_color("font_pressed_color", "Button", Color(0.9, 1.0, 0.95))
	t.set_color("font_hover_pressed_color", "Button", Color(0.95, 1.0, 0.97))
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.48, 0.45, 0.8))
	t.set_color("icon_normal_color", "Button", TEXT)
	t.set_color("icon_hover_color", "Button", GOLD_BRIGHT)
	t.set_color("icon_pressed_color", "Button", Color.WHITE)
	t.set_color("icon_disabled_color", "Button", Color(0.5, 0.5, 0.5, 0.6))
	t.set_constant("h_separation", "Button", 8)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(GOLD_BRIGHT.r, GOLD_BRIGHT.g, GOLD_BRIGHT.b, 0.35)
	focus.set_border_width_all(1)
	focus.set_expand_margin_all(2)
	t.set_stylebox("focus", "Button", focus)

	t.set_type_variation("PrimaryButton", "Button")
	_button(t, "PrimaryButton", _btn_grad(Color(0.52, 0.15, 0.11), Color(0.3, 0.07, 0.05), GOLD, 2),
		_btn_grad(Color(0.68, 0.2, 0.14), Color(0.4, 0.09, 0.06), GOLD_BRIGHT, 2),
		_btn_grad(Color(0.36, 0.09, 0.07), Color(0.5, 0.13, 0.1), GOLD_BRIGHT, 2),
		_btn_grad(Color(0.2, 0.14, 0.13, 0.7), Color(0.14, 0.1, 0.1, 0.7), Color(0.4, 0.34, 0.26, 0.6), 0))
	t.set_font_size("font_size", "PrimaryButton", 24)
	t.set_font("font", "PrimaryButton", font_display())
	t.set_color("font_outline_color", "PrimaryButton", Color(0.2, 0.03, 0.02, 0.8))
	t.set_constant("outline_size", "PrimaryButton", 3)
	t.set_color("font_color", "PrimaryButton", Color(1.0, 0.93, 0.8))
	t.set_color("font_hover_color", "PrimaryButton", Color(1.0, 0.97, 0.88))

	t.set_type_variation("JadeButton", "Button")
	var jn := _btn_grad(Color(0.16, 0.42, 0.34), Color(0.07, 0.2, 0.17), GOLD, 2)
	jn.jade = 0.3
	var jh := _btn_grad(Color(0.22, 0.54, 0.44), Color(0.1, 0.28, 0.23), GOLD_BRIGHT, 2)
	jh.jade = 0.38
	var jp := _btn_grad(Color(0.08, 0.24, 0.2), Color(0.16, 0.4, 0.33), GOLD_BRIGHT, 2)
	jp.jade = 0.22
	_button(t, "JadeButton", jn, jh, jp,
		_btn_grad(Color(0.14, 0.18, 0.17, 0.7), Color(0.1, 0.12, 0.12, 0.7), Color(0.35, 0.35, 0.3, 0.6), 0))
	t.set_font("font", "JadeButton", font_display())
	t.set_font_size("font_size", "JadeButton", 22)
	t.set_color("font_color", "JadeButton", Color(0.96, 1.0, 0.97))
	t.set_color("font_hover_color", "JadeButton", Color(1.0, 1.0, 0.94))
	t.set_color("font_outline_color", "JadeButton", Color(0.02, 0.12, 0.08, 0.85))
	t.set_constant("outline_size", "JadeButton", 4)

	# 主菜单大字按钮：常态透明，悬停出现横向墨痕
	t.set_type_variation("MenuItem", "Button")
	var mi_normal := StyleBoxEmpty.new()
	mi_normal.content_margin_left = 34
	mi_normal.content_margin_right = 30
	mi_normal.content_margin_top = 6
	mi_normal.content_margin_bottom = 6
	var mi_hover := OrnateBox.new()
	mi_hover.brush = 1.0
	mi_hover.brush_color = Color(0.58, 0.09, 0.06, 0.62)
	mi_hover.border_width = 0.0
	mi_hover.set_margins(34, 6, 30, 6)
	t.set_stylebox("normal", "MenuItem", mi_normal)
	t.set_stylebox("hover", "MenuItem", mi_hover)
	t.set_stylebox("pressed", "MenuItem", mi_hover)
	t.set_stylebox("hover_pressed", "MenuItem", mi_hover)
	t.set_stylebox("disabled", "MenuItem", mi_normal)
	t.set_stylebox("focus", "MenuItem", StyleBoxEmpty.new())
	t.set_font("font", "MenuItem", font_display())
	t.set_font_size("font_size", "MenuItem", 34)
	t.set_color("font_color", "MenuItem", Color(0.9, 0.86, 0.76))
	t.set_color("font_hover_color", "MenuItem", GOLD_BRIGHT)
	t.set_color("font_pressed_color", "MenuItem", Color(1, 1, 1))
	t.set_color("font_disabled_color", "MenuItem", Color(0.5, 0.48, 0.44, 0.55))
	t.set_color("font_outline_color", "MenuItem", Color(0.02, 0.02, 0.03, 0.85))
	t.set_constant("outline_size", "MenuItem", 6)

	# 选项小片（切换按钮）
	t.set_type_variation("ChipButton", "Button")
	var chip_n := _btn_box(Color(0.1, 0.1, 0.11, 0.85), Color(GOLD.r, GOLD.g, GOLD.b, 0.28), 0)
	chip_n.set_margins(12, 5, 12, 6)
	chip_n.chamfer = 4.0
	var chip_h := _btn_box(Color(0.2, 0.17, 0.13, 0.95), GOLD, 0)
	chip_h.set_margins(12, 5, 12, 6)
	chip_h.chamfer = 4.0
	var chip_p := _btn_grad(Color(0.2, 0.46, 0.38), Color(0.1, 0.27, 0.22), GOLD_BRIGHT, 0)
	chip_p.set_margins(12, 5, 12, 6)
	chip_p.chamfer = 4.0
	chip_p.jade = 0.22
	chip_p.inner_line_color = Color(0, 0, 0, 0)
	var chip_d := _btn_box(Color(0.08, 0.08, 0.08, 0.5), Color(0.3, 0.3, 0.3, 0.3), 0)
	chip_d.set_margins(12, 5, 12, 6)
	chip_d.chamfer = 4.0
	_button(t, "ChipButton", chip_n, chip_h, chip_p, chip_d)
	t.set_font_size("font_size", "ChipButton", 16)

	# 页签
	t.set_type_variation("TabButton", "Button")
	var tab_n := OrnateBox.new()
	tab_n.bg_top = Color(0, 0, 0, 0)
	tab_n.bg_bottom = Color(0, 0, 0, 0)
	tab_n.border_width = 0.0
	tab_n.set_margins(20, 7, 20, 9)
	var tab_h := OrnateBox.new()
	tab_h.brush = 1.0
	tab_h.brush_color = Color(0.85, 0.66, 0.36, 0.16)
	tab_h.border_width = 0.0
	tab_h.set_margins(20, 7, 20, 9)
	var tab_p := OrnateBox.new()
	tab_p.brush = 1.0
	tab_p.brush_color = Color(0.5, 0.08, 0.05, 0.78)
	tab_p.border_width = 0.0
	tab_p.set_margins(20, 7, 20, 9)
	_button(t, "TabButton", tab_n, tab_h, tab_p, tab_n)
	t.set_font("font", "TabButton", font_display())
	t.set_font_size("font_size", "TabButton", 24)
	t.set_color("font_outline_color", "TabButton", Color(0.05, 0.02, 0.01, 0.7))
	t.set_constant("outline_size", "TabButton", 3)
	t.set_color("font_color", "TabButton", TEXT_DIM)
	t.set_color("font_pressed_color", "TabButton", GOLD_BRIGHT)
	t.set_color("font_hover_pressed_color", "TabButton", GOLD_BRIGHT)

	# 图标按钮（关闭等）
	t.set_type_variation("IconButton", "Button")
	var ib_n := StyleBoxEmpty.new()
	ib_n.set_content_margin_all(4)
	var ib_h := StyleBoxFlat.new()
	ib_h.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.15)
	ib_h.set_corner_radius_all(3)
	ib_h.set_content_margin_all(4)
	var ib_p := ib_h.duplicate() as StyleBoxFlat
	ib_p.bg_color = Color(CINNABAR.r, CINNABAR.g, CINNABAR.b, 0.4)
	_button(t, "IconButton", ib_n, ib_h, ib_p, ib_n)

	# 列表行（存档位、配方等），toggle 选中带左侧玉色条
	t.set_type_variation("ListButton", "Button")
	var lb_n := OrnateBox.new()
	lb_n.bg_top = Color(1, 1, 1, 0.03)
	lb_n.bg_bottom = Color(1, 1, 1, 0.01)
	lb_n.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.14)
	lb_n.chamfer = 4.0
	lb_n.set_margins(14, 8, 12, 8)
	var lb_h := lb_n.duplicate() as OrnateBox
	lb_h.bg_top = Color(GOLD.r, GOLD.g, GOLD.b, 0.14)
	lb_h.bg_bottom = Color(GOLD.r, GOLD.g, GOLD.b, 0.05)
	lb_h.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.45)
	var lb_p := lb_n.duplicate() as OrnateBox
	lb_p.bg_top = Color(JADE.r, JADE.g, JADE.b, 0.2)
	lb_p.bg_bottom = Color(JADE.r, JADE.g, JADE.b, 0.08)
	lb_p.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.7)
	lb_p.accent_width = 3.0
	lb_p.accent_color = JADE
	_button(t, "ListButton", lb_n, lb_h, lb_p, lb_n)
	t.set_constant("align", "ListButton", HORIZONTAL_ALIGNMENT_LEFT)

	# 色块按钮
	t.set_type_variation("SwatchButton", "Button")
	var sw_n := StyleBoxFlat.new()
	sw_n.bg_color = Color(0, 0, 0, 0)
	sw_n.border_color = Color(0, 0, 0, 0.6)
	sw_n.set_border_width_all(2)
	sw_n.set_corner_radius_all(3)
	var sw_h := sw_n.duplicate() as StyleBoxFlat
	sw_h.border_color = GOLD
	var sw_p := sw_n.duplicate() as StyleBoxFlat
	sw_p.border_color = GOLD_BRIGHT
	sw_p.set_border_width_all(3)
	sw_p.set_expand_margin_all(2)
	_button(t, "SwatchButton", sw_n, sw_h, sw_p, sw_n)

	# ---- 勾选框 / 开关
	var clear := StyleBoxEmpty.new()
	clear.set_content_margin_all(3)
	var hov := StyleBoxFlat.new()
	hov.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.08)
	hov.set_content_margin_all(3)
	hov.set_corner_radius_all(3)
	for ty in ["CheckBox", "CheckButton"]:
		t.set_stylebox("normal", ty, clear)
		t.set_stylebox("pressed", ty, clear)
		t.set_stylebox("hover", ty, hov)
		t.set_stylebox("hover_pressed", ty, hov)
		t.set_stylebox("focus", ty, StyleBoxEmpty.new())
		t.set_stylebox("disabled", ty, clear)
		t.set_color("font_color", ty, TEXT)
		t.set_color("font_hover_color", ty, GOLD_BRIGHT)
		t.set_color("font_pressed_color", ty, TEXT)
		t.set_color("font_hover_pressed_color", ty, GOLD_BRIGHT)
		t.set_constant("h_separation", ty, 8)
	t.set_icon("checked", "CheckBox", icon("check_on"))
	t.set_icon("unchecked", "CheckBox", icon("check_off"))
	t.set_icon("checked_disabled", "CheckBox", icon("check_on"))
	t.set_icon("unchecked_disabled", "CheckBox", icon("check_off"))
	t.set_icon("radio_checked", "CheckBox", icon("radio_on"))
	t.set_icon("radio_unchecked", "CheckBox", icon("radio_off"))
	t.set_icon("checked", "CheckButton", icon("switch_on"))
	t.set_icon("unchecked", "CheckButton", icon("switch_off"))
	t.set_icon("checked_disabled", "CheckButton", icon("switch_on"))
	t.set_icon("unchecked_disabled", "CheckButton", icon("switch_off"))

	# ---- 下拉
	_button(t, "OptionButton", _btn_box(INK_LIGHT, GOLD_DIM, 0), _btn_box(Color(0.24, 0.2, 0.15, 0.95), GOLD, 0),
		_btn_box(Color(0.2, 0.17, 0.12, 0.95), GOLD_BRIGHT, 0), _btn_box(Color(0.1, 0.1, 0.1, 0.6), Color(0.3, 0.3, 0.3, 0.5), 0))
	t.set_icon("arrow", "OptionButton", icon("arrow_down"))
	t.set_constant("arrow_margin", "OptionButton", 10)
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_hover_color", "OptionButton", GOLD_BRIGHT)
	for ty in ["PopupMenu", "PopupPanel"]:
		var pp := _ink_box(3, 6)
		pp.shadow_size = 10.0
		pp.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.6)
		pp.paper_color = Color(1.0, 0.9, 0.72, 0.04)
		t.set_stylebox("panel", ty, pp)
	var pm_hover := StyleBoxFlat.new()
	pm_hover.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.2)
	pm_hover.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.5)
	pm_hover.border_width_left = 2
	t.set_stylebox("hover", "PopupMenu", pm_hover)
	var pm_sep := StyleBoxLine.new()
	pm_sep.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.25)
	pm_sep.thickness = 1
	t.set_stylebox("separator", "PopupMenu", pm_sep)
	t.set_stylebox("labeled_separator_left", "PopupMenu", pm_sep)
	t.set_stylebox("labeled_separator_right", "PopupMenu", pm_sep)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", GOLD_BRIGHT)
	t.set_color("font_disabled_color", "PopupMenu", TEXT_FAINT)
	t.set_color("font_separator_color", "PopupMenu", GOLD)
	t.set_constant("v_separation", "PopupMenu", 8)
	t.set_constant("item_start_padding", "PopupMenu", 12)
	t.set_constant("item_end_padding", "PopupMenu", 16)
	t.set_font_size("font_size", "PopupMenu", 17)

	# ---- 输入框
	var le := OrnateBox.new()
	le.bg_top = Color(0.02, 0.02, 0.03, 0.7)
	le.bg_bottom = Color(0.04, 0.04, 0.05, 0.7)
	le.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	le.set_margins(10, 6, 10, 6)
	var le_f := le.duplicate() as OrnateBox
	le_f.border_color = GOLD
	le_f.ornament = 3
	for ty in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", ty, le)
		t.set_stylebox("focus", ty, le_f)
		t.set_stylebox("read_only", ty, le)
		t.set_color("font_color", ty, TEXT)
		t.set_color("font_placeholder_color", ty, TEXT_FAINT)
		t.set_color("caret_color", ty, GOLD_BRIGHT)
		t.set_color("selection_color", ty, Color(GOLD.r, GOLD.g, GOLD.b, 0.35))

	# ---- 滑条
	var track := OrnateBox.new()
	track.brush = 1.0
	track.brush_color = Color(0, 0, 0, 0.6)
	track.border_width = 0.0
	track.set_margins(0, 4, 0, 4)
	var fill := OrnateBox.new()
	fill.brush = 1.0
	fill.brush_color = Color(GOLD.r * 0.9, GOLD.g * 0.85, GOLD.b * 0.7, 0.92)
	fill.border_width = 0.0
	fill.set_margins(0, 4, 0, 4)
	var fill_h := fill.duplicate() as OrnateBox
	fill_h.brush_color = GOLD_BRIGHT
	for ty in ["HSlider", "VSlider"]:
		t.set_stylebox("slider", ty, track)
		t.set_stylebox("grabber_area", ty, fill)
		t.set_stylebox("grabber_area_highlight", ty, fill_h)
		t.set_icon("grabber", ty, icon("grabber"))
		t.set_icon("grabber_highlight", ty, icon("grabber_hl"))
		t.set_icon("grabber_disabled", ty, icon("grabber_off"))
		t.set_icon("tick", ty, icon("tick"))
		t.set_constant("center_grabber", ty, 0)

	# ---- 进度条
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0, 0, 0, 0.55)
	pb_bg.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	pb_bg.set_border_width_all(1)
	pb_bg.set_corner_radius_all(2)
	var pb_fill := OrnateBox.new()
	pb_fill.bg_top = Color(0.5, 0.92, 0.76)
	pb_fill.bg_bottom = Color(0.14, 0.46, 0.38)
	pb_fill.border_width = 0.0
	pb_fill.set_all_margins(0)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_color("font_outline_color", "ProgressBar", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "ProgressBar", 4)
	t.set_font_size("font_size", "ProgressBar", 15)
	t.set_type_variation("ExpBar", "ProgressBar")
	var exp_fill := OrnateBox.new()
	exp_fill.bg_top = Color(1.0, 0.88, 0.55)
	exp_fill.bg_bottom = Color(0.66, 0.44, 0.16)
	exp_fill.border_width = 0.0
	exp_fill.set_all_margins(0)
	t.set_stylebox("fill", "ExpBar", exp_fill)

	# ---- 滚动条
	for ty in ["VScrollBar", "HScrollBar"]:
		var sc := StyleBoxFlat.new()
		sc.bg_color = Color(0, 0, 0, 0.25)
		sc.set_corner_radius_all(3)
		sc.set_content_margin_all(3)
		var gr := StyleBoxFlat.new()
		gr.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
		gr.set_corner_radius_all(3)
		gr.set_content_margin_all(3)
		var gr_h := gr.duplicate() as StyleBoxFlat
		gr_h.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.65)
		t.set_stylebox("scroll", ty, sc)
		t.set_stylebox("scroll_focus", ty, sc)
		t.set_stylebox("grabber", ty, gr)
		t.set_stylebox("grabber_highlight", ty, gr_h)
		t.set_stylebox("grabber_pressed", ty, gr_h)

	# ---- 分隔线
	var hs := StyleBoxLine.new()
	hs.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.3)
	hs.thickness = 1
	hs.grow_begin = -4
	hs.grow_end = -4
	t.set_stylebox("separator", "HSeparator", hs)
	t.set_constant("separation", "HSeparator", 10)
	var vs := StyleBoxLine.new()
	vs.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.3)
	vs.thickness = 1
	vs.vertical = true
	t.set_stylebox("separator", "VSeparator", vs)
	t.set_constant("separation", "VSeparator", 10)

	# ---- 富文本
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", font_regular())
	t.set_font("bold_font", "RichTextLabel", font_title())
	t.set_font_size("normal_font_size", "RichTextLabel", 17)
	t.set_font_size("bold_font_size", "RichTextLabel", 17)
	t.set_constant("line_separation", "RichTextLabel", 3)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())

	# ---- 列表
	t.set_stylebox("panel", "ItemList", _inset_flat())
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	var il_sel := StyleBoxFlat.new()
	il_sel.bg_color = Color(JADE.r, JADE.g, JADE.b, 0.22)
	il_sel.border_color = JADE
	il_sel.border_width_left = 3
	t.set_stylebox("selected", "ItemList", il_sel)
	t.set_stylebox("selected_focus", "ItemList", il_sel)
	var il_hov := StyleBoxFlat.new()
	il_hov.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.1)
	t.set_stylebox("hovered", "ItemList", il_hov)
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", GOLD_BRIGHT)
	t.set_color("font_hovered_color", "ItemList", GOLD_BRIGHT)
	t.set_constant("v_separation", "ItemList", 6)

	# ---- 页签容器（备用）
	var tab_sel := OrnateBox.new()
	tab_sel.brush = 1.0
	tab_sel.brush_color = Color(0.5, 0.08, 0.05, 0.8)
	tab_sel.border_width = 0.0
	tab_sel.set_margins(20, 6, 20, 8)
	var tab_un := OrnateBox.new()
	tab_un.bg_top = Color(0, 0, 0, 0)
	tab_un.bg_bottom = Color(0, 0, 0, 0)
	tab_un.border_width = 0.0
	tab_un.set_margins(20, 6, 20, 8)
	var tab_hov := OrnateBox.new()
	tab_hov.brush = 1.0
	tab_hov.brush_color = Color(0.85, 0.66, 0.36, 0.16)
	tab_hov.border_width = 0.0
	tab_hov.set_margins(20, 6, 20, 8)
	for ty in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", ty, tab_sel)
		t.set_stylebox("tab_unselected", ty, tab_un)
		t.set_stylebox("tab_hovered", ty, tab_hov)
		t.set_font("font", ty, font_display())
		t.set_font_size("font_size", ty, 22)
		t.set_stylebox("tab_disabled", ty, tab_un)
		t.set_color("font_selected_color", ty, GOLD_BRIGHT)
		t.set_color("font_unselected_color", ty, TEXT_DIM)
		t.set_color("font_hovered_color", ty, GOLD_BRIGHT)
	var tc_panel := OrnateBox.new()
	tc_panel.bg_top = Color(0, 0, 0, 0.22)
	tc_panel.bg_bottom = Color(0, 0, 0, 0.12)
	tc_panel.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.28)
	tc_panel.chamfer = 5.0
	tc_panel.set_all_margins(12)
	t.set_stylebox("panel", "TabContainer", tc_panel)
	return t


static func _label_var(t: Theme, variation: String, color: Color, size: int, title_font: bool) -> void:
	t.set_type_variation(variation, "Label")
	t.set_color("font_color", variation, color)
	t.set_font_size("font_size", variation, size)
	if title_font:
		t.set_font("font", variation, font_title())


static func _button(t: Theme, ty: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox, disabled: StyleBox) -> void:
	t.set_stylebox("normal", ty, normal)
	t.set_stylebox("hover", ty, hover)
	t.set_stylebox("pressed", ty, pressed)
	t.set_stylebox("hover_pressed", ty, pressed)
	t.set_stylebox("disabled", ty, disabled)


# ================================================================ 样式框工厂

## 通用水墨框。ornament：0 无 1 回纹角 2 小角钩 3 菱形角点
static func _ink_box(ornament: int, margin: float) -> OrnateBox:
	var b := OrnateBox.new()
	b.bg_top = Color(0.108, 0.088, 0.074, 0.96)
	b.bg_bottom = Color(0.045, 0.043, 0.055, 0.96)
	b.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.7)
	b.ornament = ornament
	b.ornament_color = Color(0.95, 0.8, 0.5)
	b.set_all_margins(margin)
	return b


static func ink_box(ornament: int = 0, margin: float = 10.0) -> OrnateBox:
	return _ink_box(ornament, margin)


static func card_box(selected: bool) -> OrnateBox:
	var b := OrnateBox.new()
	b.chamfer = 5.0
	b.paper_color = Color(1.0, 0.9, 0.72, 0.03)
	b.bg_top = Color(0.14, 0.13, 0.12, 0.7) if not selected else Color(0.16, 0.3, 0.26, 0.75)
	b.bg_bottom = Color(0.07, 0.07, 0.08, 0.7) if not selected else Color(0.07, 0.14, 0.13, 0.75)
	b.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.28) if not selected else GOLD
	b.ornament = 2
	b.corner_len = 8.0
	b.ornament_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55) if not selected else GOLD_BRIGHT
	if selected:
		b.accent_width = 3.0
		b.accent_color = JADE
	b.set_margins(12, 9, 12, 10)
	return b


static func parchment_box() -> OrnateBox:
	var b := OrnateBox.new()
	b.bg_top = Color(0.96, 0.91, 0.79, 1.0)
	b.bg_bottom = Color(0.87, 0.79, 0.63, 1.0)
	b.border_color = Color(0.42, 0.27, 0.14, 0.9)
	b.border_width = 1.5
	b.inner_line_color = Color(0.62, 0.18, 0.1, 0.45)
	b.inner_inset = 4.0
	b.ornament = 4
	b.corner_len = 7.0
	b.ornament_color = Color(0.6, 0.2, 0.1, 0.55)
	b.paper_color = Color(0.45, 0.3, 0.15, 0.2)
	b.mottle_color = Color(0.55, 0.38, 0.18, 0.16)
	b.set_margins(14, 10, 14, 12)
	return b


static func _btn_box(bg: Color, border: Color, ornament: int) -> OrnateBox:
	var b := OrnateBox.new()
	b.bg_top = Color(bg.r * 1.25, bg.g * 1.2, bg.b * 1.15, bg.a)
	b.bg_bottom = bg
	b.border_color = border
	b.ornament = ornament
	b.corner_len = 6.0
	b.chamfer = 5.0
	b.ornament_color = GOLD_BRIGHT
	b.paper_color = Color(1.0, 0.9, 0.72, 0.035)
	b.set_margins(16, 6, 16, 7)
	return b


static func _btn_grad(top: Color, bottom: Color, border: Color, ornament: int) -> OrnateBox:
	var b := OrnateBox.new()
	b.bg_top = top
	b.bg_bottom = bottom
	b.border_color = border
	b.ornament = ornament
	b.corner_len = 7.0
	b.chamfer = 7.0
	b.ornament_color = GOLD_BRIGHT
	b.top_glow = 1.5
	b.inner_line_color = Color(border.r, border.g, border.b, border.a * 0.35)
	b.inner_inset = 3.5
	b.paper_color = Color(1.0, 0.9, 0.72, 0.05)
	b.set_margins(24, 8, 24, 9)
	return b


static func _inset_flat() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.3)
	s.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.18)
	s.set_border_width_all(1)
	s.set_content_margin_all(6)
	return s


## 单色描边框（物品格、槽位高亮等）
static func flat(bg: Color, border: Color = Color(0, 0, 0, 0), width: int = 0, radius: int = 2, margin: float = 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


# ================================================================ 生成图标

static func icon(icon_name: String) -> Texture2D:
	if _icons.has(icon_name):
		return _icons[icon_name]
	var tex: Texture2D = null
	match icon_name:
		"check_off":
			tex = _sdf_icon(20, 20, func(p: Vector2) -> Color:
				var d := _sd_box(p, Vector2(10, 10), Vector2(7, 7))
				var c := Color(0, 0, 0, 0)
				c = _blend(c, Color(0.03, 0.03, 0.04, 0.8), _cov(d))
				c = _blend(c, GOLD_DIM, _cov(absf(d) - 0.7))
				return c)
		"check_on":
			tex = _sdf_icon(20, 20, func(p: Vector2) -> Color:
				var d := _sd_box(p, Vector2(10, 10), Vector2(7, 7))
				var c := Color(0, 0, 0, 0)
				c = _blend(c, Color(0.05, 0.12, 0.1, 0.9), _cov(d))
				c = _blend(c, GOLD, _cov(absf(d) - 0.8))
				var dd := (absf(p.x - 10) + absf(p.y - 10)) * 0.7071 - 3.3
				c = _blend(c, JADE.lightened(0.15), _cov(dd))
				return c)
		"radio_off":
			tex = _sdf_icon(20, 20, func(p: Vector2) -> Color:
				var d := p.distance_to(Vector2(10, 10)) - 7.0
				var c := Color(0, 0, 0, 0)
				c = _blend(c, Color(0.03, 0.03, 0.04, 0.8), _cov(d))
				c = _blend(c, GOLD_DIM, _cov(absf(d) - 0.7))
				return c)
		"radio_on":
			tex = _sdf_icon(20, 20, func(p: Vector2) -> Color:
				var d := p.distance_to(Vector2(10, 10)) - 7.0
				var c := Color(0, 0, 0, 0)
				c = _blend(c, Color(0.05, 0.12, 0.1, 0.9), _cov(d))
				c = _blend(c, GOLD, _cov(absf(d) - 0.8))
				c = _blend(c, JADE.lightened(0.15), _cov(p.distance_to(Vector2(10, 10)) - 3.5))
				return c)
		"switch_off", "switch_on":
			var on := icon_name == "switch_on"
			tex = _sdf_icon(40, 22, func(p: Vector2) -> Color:
				var d := _sd_round_box(p, Vector2(20, 11), Vector2(17, 8), 8.0)
				var c := Color(0, 0, 0, 0)
				c = _blend(c, Color(0.12, 0.34, 0.28, 0.95) if on else Color(0.05, 0.05, 0.06, 0.9), _cov(d))
				c = _blend(c, GOLD if on else GOLD_DIM, _cov(absf(d) - 0.7))
				var kx := 29.0 if on else 11.0
				var kd := p.distance_to(Vector2(kx, 11)) - 6.0
				c = _blend(c, GOLD_BRIGHT if on else Color(0.55, 0.52, 0.48), _cov(kd))
				return c)
		"grabber", "grabber_hl", "grabber_off":
			var fillc := GOLD if icon_name == "grabber" else (GOLD_BRIGHT if icon_name == "grabber_hl" else Color(0.45, 0.43, 0.4))
			tex = _sdf_icon(20, 20, func(p: Vector2) -> Color:
				var dd := (absf(p.x - 10) + absf(p.y - 10)) * 0.7071 - 5.6
				var c := Color(0, 0, 0, 0)
				c = _blend(c, Color(0.08, 0.06, 0.03, 0.95), _cov(dd - 1.4))
				c = _blend(c, fillc, _cov(dd))
				var inner := (absf(p.x - 10) + absf(p.y - 10)) * 0.7071 - 2.0
				c = _blend(c, fillc.lightened(0.35), _cov(inner))
				return c)
		"tick":
			tex = _sdf_icon(2, 6, func(_p: Vector2) -> Color:
				return Color(GOLD.r, GOLD.g, GOLD.b, 0.5))
		"arrow_down":
			tex = _sdf_icon(14, 10, func(p: Vector2) -> Color:
				var d := minf(_sd_segment(p, Vector2(3, 3), Vector2(7, 7)), _sd_segment(p, Vector2(7, 7), Vector2(11, 3))) - 1.1
				return Color(GOLD.r, GOLD.g, GOLD.b, _cov(d)))
		"arrow_right":
			tex = _sdf_icon(10, 14, func(p: Vector2) -> Color:
				var d := minf(_sd_segment(p, Vector2(3, 3), Vector2(7, 7)), _sd_segment(p, Vector2(7, 7), Vector2(3, 11))) - 1.1
				return Color(GOLD.r, GOLD.g, GOLD.b, _cov(d)))
		"close":
			tex = _sdf_icon(18, 18, func(p: Vector2) -> Color:
				var d := minf(_sd_segment(p, Vector2(4, 4), Vector2(14, 14)), _sd_segment(p, Vector2(14, 4), Vector2(4, 14))) - 1.2
				return Color(TEXT.r, TEXT.g, TEXT.b, _cov(d)))
		"diamond":
			tex = _sdf_icon(12, 12, func(p: Vector2) -> Color:
				var dd := (absf(p.x - 6) + absf(p.y - 6)) * 0.7071 - 3.2
				return Color(GOLD.r, GOLD.g, GOLD.b, _cov(dd)))
		"dice":
			tex = _sdf_icon(20, 20, func(p: Vector2) -> Color:
				var d := _sd_round_box(p, Vector2(10, 10), Vector2(7.5, 7.5), 2.5)
				var c := Color(0, 0, 0, 0)
				c = _blend(c, GOLD, _cov(absf(d) - 0.8))
				for q in [Vector2(6.5, 6.5), Vector2(13.5, 13.5), Vector2(10, 10), Vector2(13.5, 6.5), Vector2(6.5, 13.5)]:
					c = _blend(c, GOLD_BRIGHT, _cov(p.distance_to(q) - 1.4))
				return c)
		"dot":
			tex = _sdf_icon(32, 32, func(p: Vector2) -> Color:
				var d := p.distance_to(Vector2(16, 16)) / 16.0
				return Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2.2))
		_:
			tex = _sdf_icon(8, 8, func(_p: Vector2) -> Color:
				return Color.MAGENTA)
	_icons[icon_name] = tex
	return tex


static func _sdf_icon(w: int, h: int, shade: Callable) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, shade.call(Vector2(x + 0.5, y + 0.5)))
	return ImageTexture.create_from_image(img)


static func _cov(d: float) -> float:
	return clampf(0.5 - d, 0.0, 1.0)


static func _blend(under: Color, over: Color, a: float) -> Color:
	var oa := over.a * a
	var out_a := oa + under.a * (1.0 - oa)
	if out_a <= 0.0001:
		return Color(0, 0, 0, 0)
	var rgb := (Vector3(over.r, over.g, over.b) * oa + Vector3(under.r, under.g, under.b) * under.a * (1.0 - oa)) / out_a
	return Color(rgb.x, rgb.y, rgb.z, out_a)


static func _sd_box(p: Vector2, c: Vector2, half: Vector2) -> float:
	var d := (p - c).abs() - half
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0)


static func _sd_round_box(p: Vector2, c: Vector2, half: Vector2, r: float) -> float:
	return _sd_box(p, c, half - Vector2(r, r)) - r


static func _sd_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length()


# ================================================================ 控件工厂

static func label(text: String, size: int = 0, color: Color = Color(0, 0, 0, 0), variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, size: int = 30) -> Label:
	var l := label(text, size, Color(0, 0, 0, 0), "TitleLabel")
	return l


static func dim(text: String, size: int = 0) -> Label:
	return label(text, size, Color(0, 0, 0, 0), "DimLabel")


static func wrap_label(text: String, size: int = 0, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 60
	return l


## 小节标题：朱砂小印点 + 书法标题 + 渐淡的金色笔触线
static func header(text: String, size: int = 23) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var d := InkSeal.make("", 13.0, Color(0.78, 0.16, 0.1))
	d.angle = 0.785
	h.add_child(d)
	var l := label(text, size, Color(0, 0, 0, 0), "HeaderLabel")
	h.add_child(l)
	var sep := BrushLine.new()
	sep.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.45)
	sep.thickness = 6.0
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sep)
	return h


static func separator(ornament: bool = true) -> GoldSeparator:
	var s := GoldSeparator.new()
	s.ornament = ornament
	return s


static func panel(variation: String = "WindowPanel") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	return p


static func vbox(sep: int = 8) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func hbox(sep: int = 8) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func margin(child: Control, l: int, t: int = -1, r: int = -1, b: int = -1) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", l if t < 0 else t)
	m.add_theme_constant_override("margin_right", l if r < 0 else r)
	m.add_theme_constant_override("margin_bottom", (l if t < 0 else t) if b < 0 else b)
	if child != null:
		m.add_child(child)
	return m


static func spacer(h: float = 0.0, w: float = 0.0, expand: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## 按钮（带悬停/点击音效）
static func button(text: String, variation: String = "", on_press: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	hook_sounds(b)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func icon_button(icon_name: String, tip: String = "", on_press: Callable = Callable()) -> Button:
	var b := Button.new()
	b.theme_type_variation = "IconButton"
	b.icon = icon(icon_name)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	hook_sounds(b)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func chip(text: String, toggled: bool = false, group: ButtonGroup = null) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "ChipButton"
	b.toggle_mode = true
	b.button_pressed = toggled
	b.focus_mode = Control.FOCUS_NONE
	if group != null:
		b.button_group = group
	hook_sounds(b)
	return b


static func hook_sounds(b: BaseButton) -> void:
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Audio.play("ui_hover", -8.0))
	b.pressed.connect(func() -> void: Audio.play("ui_click"))


## 键值行：左侧名称（暗色），右侧数值
static func kv_row(key: String, value: String, value_color: Color = TEXT, size: int = 17) -> HBoxContainer:
	var h := HBoxContainer.new()
	var k := label(key, size, TEXT_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(k)
	var v := label(value, size, value_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return h


static func progress(value: float, max_value: float, variation: String = "", height: float = 16.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = maxf(max_value, 0.0001)
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size.y = height
	if variation != "":
		pb.theme_type_variation = variation
	return pb


static func scroll(child: Control, horizontal: bool = false) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal else ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if child != null:
		child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.add_child(child)
	return s


static func rich(bbcode: String = "", fit: bool = true) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = fit
	r.scroll_active = not fit
	r.text = bbcode
	r.selection_enabled = false
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


# ================================================================ 文本工具

static func hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func bb(text: String, c: Color) -> String:
	return "[color=%s]%s[/color]" % [hex(c), text]


static func grade_bb(text: String, g: int) -> String:
	return bb(text, Grade.color_of(g))


static func elem_bb(e: String) -> String:
	return bb(Elem.name_of(e), Elem.color_of(e))


## 较暗的元素色（用于背景填充）
static func elem_dark(e: String, f: float = 0.55) -> Color:
	return Elem.color_of(e).darkened(f)


static func kind_color(kind: String) -> Color:
	return KIND_COLORS.get(kind, KIND_COLORS["info"])


## 小时数的中文描述
static func hours_text(h: float) -> String:
	if h >= 24.0 * 360.0:
		return "%s年" % _trim(h / (24.0 * 360.0))
	if h >= 24.0 * 30.0:
		return "%s月" % _trim(h / (24.0 * 30.0))
	if h >= 24.0:
		return "%s日" % _trim(h / 24.0)
	return "%s个时辰" % _trim(h / 2.0)


static func _trim(v: float) -> String:
	if absf(v - roundf(v)) < 0.05:
		return str(int(roundf(v)))
	return "%.1f" % v


## 大数字分组（12,345）
static func num(v: float) -> String:
	var n := int(roundf(v))
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
