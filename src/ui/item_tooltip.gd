class_name ItemTooltip
## 物品提示（宣纸底 + 墨色名牌）。用于 Control._make_custom_tooltip()。

const INK := Color(0.2, 0.14, 0.09)
const INK_SOFT := Color(0.36, 0.28, 0.2)
const POS := Color(0.14, 0.45, 0.22)
const NEG := Color(0.62, 0.14, 0.1)


## item：物品实例；extra：追加的一行提示（如“右键：更多操作”）；price_text：价格行
static func build(item: ItemInstance, extra: String = "", price_text: String = "") -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.custom_minimum_size.x = 300
	# 名牌
	var plate := PanelContainer.new()
	var sb := OrnateBox.new()
	var gc := item.color()
	sb.bg_top = Color(0.1, 0.08, 0.06, 0.96)
	sb.bg_bottom = Color(0.05, 0.05, 0.06, 0.96)
	sb.border_color = Color(gc.r, gc.g, gc.b, 0.8)
	sb.accent_width = 4.0
	sb.accent_color = gc
	sb.set_margins(12, 6, 10, 7)
	plate.add_theme_stylebox_override("panel", sb)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 10)
	var icon := ItemIcon.new()
	icon.item_id = item.id
	icon.grade = item.grade
	icon.custom_minimum_size = Vector2(44, 44)
	ph.add_child(icon)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	var n := Label.new()
	n.text = item.display_name() + ("  ×%d" % item.count if item.count > 1 else "")
	n.add_theme_font_override("font", UITheme.font_title())
	n.add_theme_font_size_override("font_size", 21)
	n.add_theme_color_override("font_color", gc.lightened(0.1))
	names.add_child(n)
	var lines := item.describe().split("\n")
	var sub := Label.new()
	sub.text = lines[0] if lines.size() > 0 else ""
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(gc.r, gc.g, gc.b, 0.85).lerp(Color(0.8, 0.76, 0.68), 0.4))
	names.add_child(sub)
	ph.add_child(names)
	plate.add_child(ph)
	box.add_child(plate)
	# 正文
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.custom_minimum_size.x = 300
	rt.add_theme_color_override("default_color", INK)
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_font_size_override("bold_font_size", 16)
	var parts: PackedStringArray = []
	for i in range(1, lines.size()):
		parts.append(_fmt_line(lines[i], item))
	if price_text != "":
		parts.append(UITheme.bb(price_text, Color(0.55, 0.36, 0.08)))
	if extra != "":
		parts.append(UITheme.bb(extra, INK_SOFT))
	rt.text = "\n".join(parts)
	box.add_child(rt)
	return box


static func _fmt_line(line: String, item: ItemInstance) -> String:
	if line.begins_with("五行："):
		var e := item.element()
		return "五行：" + UITheme.bb(Elem.name_of(e), Elem.color_of(e).darkened(0.35))
	if line.begins_with("[使用]"):
		return UITheme.bb("【使用】", NEG) + UITheme.bb(line.substr(4).strip_edges(), INK)
	if line.begins_with("[可炼化]"):
		return UITheme.bb("【炼化】", Color(0.1, 0.4, 0.34)) + line.substr(5).strip_edges()
	if line.begins_with("价值："):
		return UITheme.bb(line, Color(0.55, 0.36, 0.08))
	if line.begins_with("兵器："):
		return "[b]%s[/b]" % line
	if line.contains(" +"):
		return UITheme.bb(line, POS)
	if line.contains(" -"):
		return UITheme.bb(line, NEG)
	if line == item.def().get("desc", ""):
		return UITheme.bb(line, INK_SOFT)
	return line


## 纯文本提示（法诀、功法等），宣纸风格：标题 + 正文
static func build_text(title_text: String, title_color: Color, body_bbcode: String, width: float = 320.0) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var t := Label.new()
	t.text = title_text
	t.add_theme_font_override("font", UITheme.font_title())
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", title_color)
	box.add_child(t)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.custom_minimum_size.x = width
	rt.add_theme_color_override("default_color", INK)
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.text = body_bbcode
	box.add_child(rt)
	return box
