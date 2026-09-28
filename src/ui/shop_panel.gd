class_name ShopPanel
extends UIWindow
## 商店面板（坊市、宗门商店共用）。
## args: {"title": String,
##        "entries": [{"item": id, "price": int, "currency": "灵石" | "贡献",
##                     "can_buy"?: Callable(entry) -> bool, "on_buy"?: Callable(entry), "stock"?: int, "note"?: String}],
##        "sell": bool}
## 未提供 on_buy 时默认：扣除灵石/本门贡献并 GS.give_item。sell=true 时可把储物袋物品拖入“出售”槽，按五成价值换取灵石。

const SELL_RATE := 0.5

var _list: VBoxContainer
var _wallet: HBoxContainer
var _bag_view: GridView


func _init() -> void:
	super()


func _build() -> void:
	set_title(str(args.get("title", "商铺")))
	var row := UITheme.hbox(20)
	add(row)
	var left := UITheme.vbox(8)
	var head := UITheme.hbox(10)
	var h := UITheme.header("货架")
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	_wallet = UITheme.hbox(14)
	head.add_child(_wallet)
	left.add_child(head)
	var lp := PanelContainer.new()
	lp.theme_type_variation = "InsetPanel"
	_list = UITheme.vbox(6)
	var sc := UITheme.scroll(_list)
	sc.custom_minimum_size = Vector2(600, 560)
	lp.add_child(sc)
	left.add_child(lp)
	row.add_child(left)
	if bool(args.get("sell", false)):
		var right := UITheme.vbox(8)
		right.add_child(UITheme.header("储物袋"))
		_bag_view = GridView.new()
		_bag_view.cell = 46.0
		_bag_view.bind(GS.player.bag)
		_bag_view.tooltip_extra = func(it: ItemInstance) -> String: return "出售可得 %d 灵石 · 右键出售" % sell_value(it, it.count)
		_bag_view.item_context.connect(_on_bag_context)
		right.add_child(_bag_view)
		var zone := ItemDropSlot.new()
		zone.title = "出售"
		zone.glyph = "售"
		zone.hint = "拖入物品，按五成价值收购"
		zone.accent = UITheme.GOLD
		zone.custom_minimum_size = Vector2(0, 110)
		zone.accept = func(it: ItemInstance) -> bool: return it.unit_value() > 0
		zone.on_item = _sell
		right.add_child(zone)
		row.add_child(right)


func refresh() -> void:
	if _list == null:
		return
	var p := GS.player
	UIWindow.clear_children(_wallet)
	var st := ItemIcon.new()
	st.item_id = "spirit_stone"
	st.show_frame = false
	st.custom_minimum_size = Vector2(24, 24)
	_wallet.add_child(st)
	_wallet.add_child(UITheme.label(UITheme.num(p.spirit_stones), 19, UITheme.GOLD_BRIGHT))
	if p.sect != "":
		_wallet.add_child(UITheme.label("贡献 %s" % UITheme.num(int(p.contribution.get(p.sect, 0))), 17, UITheme.JADE))
	UIWindow.clear_children(_list)
	var entries: Array = args.get("entries", [])
	if entries.is_empty():
		_list.add_child(UITheme.label("货架空空如也。", 17, UITheme.TEXT_FAINT))
	for e in entries:
		_list.add_child(_row(e))
	if _bag_view != null:
		if _bag_view.grid != p.bag:
			_bag_view.bind(p.bag)
		_bag_view.queue_redraw()


func _row(e: Dictionary) -> Control:
	var id := str(e.get("item", ""))
	var d := DB.item(id)
	var it := ItemInstance.create(id, 1)
	var card := ShopRow.new()
	card.item = it
	card.theme_type_variation = "CardPanel"
	var h := UITheme.hbox(12)
	card.add_child(h)
	var ic := ItemIcon.new()
	ic.item_id = id
	ic.custom_minimum_size = Vector2(52, 52)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var v := UITheme.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := UITheme.label(str(d.get("name", id)), 19, it.color().lerp(UITheme.TEXT, 0.15))
	v.add_child(nm)
	var sub := "%s · %s" % [Grade.name_of(it.get_grade()), ItemInstance._type_name(it.type())]
	if e.has("note"):
		sub += " · " + str(e["note"])
	if e.has("stock"):
		sub += " · 余 %d" % int(e["stock"])
	v.add_child(UITheme.label(sub, 14, UITheme.TEXT_DIM))
	h.add_child(v)
	var cur := str(e.get("currency", "灵石"))
	var price := int(e.get("price", 0))
	var ok := can_buy(e)
	var pl := UITheme.label("%s %s" % [UITheme.num(price), cur], 19, (UITheme.GOLD_BRIGHT if cur == "灵石" else UITheme.JADE) if ok else UITheme.BAD)
	pl.custom_minimum_size.x = 110
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(pl)
	var buy := UITheme.button("购买", "JadeButton", _buy.bind(e, 1))
	buy.disabled = not ok
	buy.add_theme_font_size_override("font_size", 17)
	h.add_child(buy)
	if int(d.get("stack", 1)) > 1:
		var many := UITheme.button("×N", "", _buy_many.bind(e))
		many.disabled = not ok
		h.add_child(many)
	return card


## 默认购买条件：货币足够（可由 entry.can_buy 覆盖）
static func can_buy(e: Dictionary) -> bool:
	var cb: Callable = e.get("can_buy", Callable())
	if cb.is_valid():
		return bool(cb.call(e))
	if e.has("stock") and int(e["stock"]) <= 0:
		return false
	var price := int(e.get("price", 0))
	if str(e.get("currency", "灵石")) == "贡献":
		var p := GS.player
		return p.sect != "" and int(p.contribution.get(p.sect, 0)) >= price
	return GS.player.spirit_stones >= price


static func default_buy(e: Dictionary) -> bool:
	var price := int(e.get("price", 0))
	var p := GS.player
	if str(e.get("currency", "灵石")) == "贡献":
		if p.sect == "" or int(p.contribution.get(p.sect, 0)) < price:
			return false
		p.contribution[p.sect] = int(p.contribution.get(p.sect, 0)) - price
	elif not GS.spend_stones(price):
		return false
	GS.give_item(str(e.get("item", "")), 1)
	return true


func _buy(e: Dictionary, n: int) -> void:
	var bought := 0
	for i in n:
		if not can_buy(e):
			break
		var cb: Callable = e.get("on_buy", Callable())
		if cb.is_valid():
			cb.call(e)
		elif not default_buy(e):
			break
		if e.has("stock"):
			e["stock"] = int(e["stock"]) - 1
		bought += 1
	if bought > 0:
		Audio.play("ui_buy")
	else:
		Events.notify.emit("囊中羞涩", "warn")
	Events.inventory_changed.emit()
	queue_refresh()


func _buy_many(e: Dictionary) -> void:
	var price := maxi(int(e.get("price", 1)), 1)
	var have := GS.player.spirit_stones
	if str(e.get("currency", "灵石")) == "贡献":
		have = int(GS.player.contribution.get(GS.player.sect, 0))
	var mx := clampi(have / price, 1, 99)
	if e.has("stock"):
		mx = mini(mx, int(e["stock"]))
	ui().ask_number("购买 %s" % DB.item(str(e["item"])).get("name", ""), 1, mx, 1, func(n: int) -> void: _buy(e, n), "单价 %d %s" % [price, e.get("currency", "灵石")])


static func sell_value(it: ItemInstance, n: int) -> int:
	return maxi(int(floor(it.unit_value() * n * SELL_RATE)), 1)


func _sell(grid: InventoryGrid, entry: Dictionary) -> void:
	var it: ItemInstance = entry["item"]
	var do_sell := func(n: int) -> void:
		var v := sell_value(it, n)
		ItemActions.consume(grid, entry, n)
		GS.add_stones(v, false)
		Events.notify.emit("出售 %s ×%d，得灵石 %d" % [it.display_name(), n, v], "loot")
		Audio.play("ui_sell")
		Events.inventory_changed.emit()
	if it.count > 1:
		ui().ask_number("出售 %s" % it.display_name(), 1, it.count, it.count, do_sell, "单价 %d 灵石（五成）" % sell_value(it, 1))
	elif it.get_grade() >= 3 or sell_value(it, 1) >= 300:
		ui().confirm("以 %d 灵石出售 %s？" % [sell_value(it, 1), it.display_name()], func() -> void: do_sell.call(1), "出售", "出售")
	else:
		do_sell.call(1)


func _on_bag_context(v: GridView, entry: Dictionary, at: Vector2) -> void:
	var it: ItemInstance = entry["item"]
	ItemActions.popup_menu(self, v.grid, entry, at, [{"text": "出售（%d 灵石）" % sell_value(it, it.count), "callback": func() -> void: _sell(v.grid, entry)}])


## 带物品提示的货架行
class ShopRow extends PanelContainer:
	var item: ItemInstance

	func _get_tooltip(_at: Vector2) -> String:
		return "shop:%s" % item.id if item != null else ""

	func _make_custom_tooltip(_t: String) -> Object:
		return ItemTooltip.build(item, "", "") if item != null else null
