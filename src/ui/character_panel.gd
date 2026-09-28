class_name CharacterPanel
extends UIWindow
## 角色面板：立绘（3D）、身份/境界/寿元/门派/因果、灵根五边形、先天属性、天赋、全部属性（分组）。

const STAT_GROUPS := [
	["气血灵力", ["max_hp", "max_shield", "max_qi", "hp_regen", "shield_regen", "qi_regen", "shield_delay"]],
	["攻防", ["attack", "defense", "crit_rate", "crit_dmg", "dmg_reduction", "poise", "melee_mult", "bolt_mult", "spell_mult", "cdr"]],
	["五行", ["dmg_metal", "dmg_wood", "dmg_water", "dmg_fire", "dmg_earth", "bleed_power", "poison_power", "bind_power", "burn_power", "stagger_power", "status_chance", "status_resist"]],
	["身法", ["move_speed", "boost_speed", "boost_cost", "qb_cost", "flight_cost"]],
	["兵器专精", ["sword_dmg", "saber_dmg", "spear_dmg", "fist_dmg"]],
	["修行探索", ["cult_speed", "insight_gain", "breakthrough", "search_speed", "luck", "lock_range", "heal_mult", "pill_eff", "pill_tox", "favor_gain", "loot_bonus"]],
	["技艺", ["alchemy", "forging", "talisman", "formation", "herbalism"]],
]

## 数值越低越好的属性
const LOWER_BETTER := ["boost_cost", "qb_cost", "flight_cost", "pill_tox", "shield_delay"]

var _preview: RigPreview
var _ident: VBoxContainer
var _chart: PentagonChart
var _root_info: Label
var _attrs: VBoxContainer
var _talents: HFlowContainer
var _stats: VBoxContainer
var _status: VBoxContainer


func _init() -> void:
	super()
	window_title = "角色"


func _build() -> void:
	var row := UITheme.hbox(20)
	add(row)
	# 左：立绘与身份
	var left := UITheme.vbox(8)
	left.custom_minimum_size.x = 300
	var pv := PanelContainer.new()
	pv.theme_type_variation = "InsetPanel"
	_preview = RigPreview.new()
	_preview.custom_minimum_size = Vector2(280, 300)
	pv.add_child(_preview)
	left.add_child(pv)
	_ident = UITheme.vbox(3)
	left.add_child(_ident)
	_status = UITheme.vbox(4)
	left.add_child(_status)
	row.add_child(left)
	# 中：灵根、属性、天赋
	var mid := UITheme.vbox(8)
	mid.custom_minimum_size.x = 320
	mid.add_child(UITheme.header("灵根"))
	_chart = PentagonChart.new()
	_chart.custom_minimum_size = Vector2(250, 230)
	_chart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mid.add_child(_chart)
	_root_info = UITheme.label("", 16, UITheme.TEXT_DIM)
	_root_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_root_info)
	mid.add_child(UITheme.header("先天"))
	_attrs = UITheme.vbox(4)
	mid.add_child(_attrs)
	mid.add_child(UITheme.header("天赋"))
	_talents = HFlowContainer.new()
	_talents.add_theme_constant_override("h_separation", 6)
	_talents.add_theme_constant_override("v_separation", 6)
	mid.add_child(_talents)
	row.add_child(mid)
	# 右：属性
	var right := UITheme.vbox(8)
	right.custom_minimum_size.x = 420
	right.add_child(UITheme.header("属性"))
	var inset := PanelContainer.new()
	inset.theme_type_variation = "InsetPanel"
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stats = UITheme.vbox(4)
	var sc := UITheme.scroll(_stats)
	sc.custom_minimum_size = Vector2(400, 560)
	inset.add_child(sc)
	right.add_child(inset)
	row.add_child(right)


func refresh() -> void:
	if _ident == null:
		return
	var p := GS.player
	var st := GS.stats
	_preview.show_player(p)
	# 身份
	UIWindow.clear_children(_ident)
	var nm := UITheme.title(p.name, 30)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ident.add_child(nm)
	var realm := UITheme.label(DB.realm_name(p.realm, p.stage), 22, UITheme.GOLD_BRIGHT)
	realm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ident.add_child(realm)
	var bg: Dictionary = DB.backgrounds.get(p.background, {})
	_ident.add_child(UITheme.kv_row("出身", str(bg.get("name", "散修")), UITheme.TEXT))
	_ident.add_child(UITheme.kv_row("年岁 / 寿元", "%d / %d 载" % [p.age_years(), Cultivation.lifespan_years(p)], _age_color(p)))
	_ident.add_child(UITheme.kv_row("时日", GS.date_text(), UITheme.TEXT_DIM, 15))
	if p.sect != "":
		var s := DB.sect(p.sect)
		var ranks: Array = s.get("ranks", [])
		var rank_name := str(ranks[clampi(p.sect_rank, 0, ranks.size() - 1)].get("name", "")) if not ranks.is_empty() else ""
		var sc := CharacterBuilder.col(s.get("color", "#ffffff"))
		_ident.add_child(UITheme.kv_row("宗门", "%s · %s" % [s.get("name", p.sect), rank_name], sc.lerp(UITheme.TEXT, 0.3)))
		_ident.add_child(UITheme.kv_row("贡献 / 声望", "%d / %d" % [int(p.contribution.get(p.sect, 0)), int(p.reputation.get(p.sect, 0))], UITheme.TEXT))
	else:
		_ident.add_child(UITheme.kv_row("宗门", "散修（未入宗门）", UITheme.TEXT_DIM))
	# 状态
	UIWindow.clear_children(_status)
	_status.add_child(UITheme.kv_row("业力", _karma_text(p.karma), UITheme.BAD if p.karma > 20 else UITheme.TEXT))
	_status.add_child(UITheme.kv_row("伤势", "内伤 · 余 %d 日" % ceili(p.injury_days) if p.injury_days > 0.0 else "无恙", UITheme.BAD if p.injury_days > 0.0 else UITheme.GOOD))
	var tox := UITheme.hbox(8)
	var tl := UITheme.label("丹毒", 17, UITheme.TEXT_DIM)
	tl.custom_minimum_size.x = 60
	tox.add_child(tl)
	var tb := UITheme.progress(p.pill_toxicity, 100.0, "", 12)
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tfill := UITheme.flat(Color(0.55, 0.75, 0.25) if p.pill_toxicity < 50 else Color(0.8, 0.35, 0.2))
	tb.add_theme_stylebox_override("fill", tfill)
	tox.add_child(tb)
	tox.add_child(UITheme.label("%d" % int(p.pill_toxicity), 16, UITheme.TEXT))
	_status.add_child(tox)
	_status.add_child(UITheme.kv_row("斩敌 / 秘境", "%d / %d" % [p.kills, p.realms_cleared], UITheme.TEXT_DIM, 15))
	# 灵根
	_chart.values = p.roots
	var rt := BuildCalc.root_type(p)
	_root_info.text = "%s · 修炼 ×%.1f · 当前修速 ×%.2f" % [rt["name"], float(rt["cult"]), float(st.get("cult_speed", 1.0))]
	# 先天
	UIWindow.clear_children(_attrs)
	for a in PlayerData.ATTRS:
		_attrs.add_child(_attr_row(a, int(p.attributes.get(a, 5))))
	# 天赋
	UIWindow.clear_children(_talents)
	if p.talents.is_empty():
		_talents.add_child(UITheme.label("无", 16, UITheme.TEXT_FAINT))
	for tid in p.talents:
		var t := DB.talent(tid)
		var chip := Label.new()
		chip.text = str(t.get("name", tid))
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.tooltip_text = "%s（%s）\n%s" % [t.get("name", tid), t.get("category", ""), t.get("desc", "")]
		var neg := int(t.get("cost", 0)) < 0
		var sb := UITheme.flat(Color(0.35, 0.08, 0.06, 0.6) if neg else Color(0.1, 0.28, 0.24, 0.6), UITheme.CINNABAR if neg else UITheme.JADE, 1, 3, 0)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 3
		sb.content_margin_bottom = 4
		chip.add_theme_stylebox_override("normal", sb)
		chip.add_theme_font_size_override("font_size", 16)
		_talents.add_child(chip)
	# 属性
	UIWindow.clear_children(_stats)
	for grp in STAT_GROUPS:
		var g := UITheme.label("◆ " + str(grp[0]), 17, UITheme.GOLD)
		_stats.add_child(g)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 2)
		for k in grp[1]:
			var key: String = k
			var v := float(st.get(key, 0.0))
			var lab := UITheme.label(Stats.label(key), 15, UITheme.TEXT_DIM)
			lab.custom_minimum_size.x = 92
			grid.add_child(lab)
			var val := UITheme.label(Stats.format_value(key, v), 15, _stat_color(key, v))
			val.custom_minimum_size.x = 76
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if PlayerData.PROFESSIONS.has(key):
				val.text = "%d 级" % (p.profession_level(key) + int(v))
			grid.add_child(val)
		_stats.add_child(grid)
	var perks := BuildCalc.perks(p)
	if not perks.is_empty():
		_stats.add_child(UITheme.label("◆ 境界神通", 17, UITheme.GOLD))
		for i in range(0, p.realm + 1):
			var pt: Dictionary = DB.realm(i).get("perk_text", {})
			for k2 in pt:
				_stats.add_child(UITheme.wrap_label(str(pt[k2]), 15, UITheme.TEXT))


func _attr_row(a: String, v: int) -> Control:
	var h := UITheme.hbox(10)
	var n := UITheme.label(str(PlayerData.ATTR_NAMES.get(a, a)), 18, UITheme.TEXT)
	n.custom_minimum_size.x = 48
	n.mouse_filter = Control.MOUSE_FILTER_PASS
	n.tooltip_text = attr_tooltip(a)
	h.add_child(n)
	var pips := AttrPips.new()
	pips.value = v
	pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pips.tooltip_text = n.tooltip_text
	h.add_child(pips)
	var vl := UITheme.label(str(v), 18, UITheme.GOLD_BRIGHT if v > 5 else (UITheme.BAD if v < 5 else UITheme.TEXT))
	vl.custom_minimum_size.x = 26
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(vl)
	return h


static func attr_tooltip(a: String) -> String:
	var lines: PackedStringArray = ["%s：每高于 5 一点" % PlayerData.ATTR_NAMES.get(a, a)]
	var eff: Dictionary = BuildCalc.ATTR_EFFECTS.get(a, {})
	for k in eff:
		lines.append("  " + Stats.format_mod(k, float(eff[k])))
	return "\n".join(lines)


func _stat_color(key: String, v: float) -> Color:
	if key in ["max_hp", "max_shield", "max_qi", "attack", "defense", "poise"]:
		return UITheme.GOLD_BRIGHT
	var d := float(Stats.DEFAULTS.get(key, v))
	if absf(v - d) < 0.0001:
		return UITheme.TEXT
	var better := v > d
	if LOWER_BETTER.has(key):
		better = not better
	return UITheme.GOOD if better else UITheme.BAD


static func _karma_text(k: int) -> String:
	if k <= 0:
		return "清白"
	if k <= 20:
		return "微瑕（%d）" % k
	if k <= 60:
		return "业障缠身（%d）" % k
	return "罪孽深重（%d）" % k


static func _age_color(p: PlayerData) -> Color:
	var left := Cultivation.lifespan_years(p) - p.age_years()
	if left < 10:
		return UITheme.BAD
	if left < 30:
		return UITheme.WARN
	return UITheme.TEXT


## 属性点刻度（1~10）
class AttrPips extends Control:
	var value: int = 5
	var max_value: int = 10

	func _init() -> void:
		custom_minimum_size = Vector2(150, 14)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var n := max_value
		var gap := 3.0
		var w := (size.x - gap * (n - 1)) / n
		var y := (size.y - 10.0) * 0.5
		for i in n:
			var r := Rect2(i * (w + gap), y, w, 10.0)
			var on := i < value
			var c := UITheme.GOLD if on else Color(1, 1, 1, 0.06)
			if on and i >= 5:
				c = UITheme.GOLD_BRIGHT
			if on and value < 5:
				c = UITheme.CINNABAR
			draw_rect(r, c)
			if i == 4:
				draw_line(Vector2(r.end.x + gap * 0.5, 0), Vector2(r.end.x + gap * 0.5, size.y), Color(1, 1, 1, 0.25), 1.0)
