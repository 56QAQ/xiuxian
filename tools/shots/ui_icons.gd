extends RefCounted
## 界面截图：程序化物品图标一览（全部 icon 种类 × 品阶，以及数据中的全部物品）

const KINDS := ["sword", "saber", "spear", "fist", "robe", "armor", "pendant", "ring", "pill", "herb", "flower", "fruit",
	"ore", "crystal", "core", "stone", "scroll", "talisman", "bag", "seed", "hide", "bone", "key", "disc"]
const SIZES := {"sword": [1, 4], "saber": [1, 4], "spear": [1, 5], "robe": [2, 3], "armor": [2, 3], "herb": [1, 2], "crystal": [1, 2],
	"scroll": [1, 2], "ore": [2, 2], "bag": [2, 2], "hide": [2, 2], "flower": [2, 2]}


func frames() -> int:
	return 6


func build(root: Node) -> void:
	UIShotCommon.backdrop(root)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var sheet := Sheet.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.theme = UITheme.get_theme()
	layer.add_child(sheet)


class Sheet extends Control:
	var _keep: Array = []

	func _draw() -> void:
		var cell := 40.0
		var x := 30.0
		var y := 30.0
		var row_h := 0.0
		var f := UITheme.font_regular()
		for k in KINDS:
			var s: Array = SIZES.get(k, [1, 1])
			for g in [0, 2, 4]:
				var d := {"icon": k, "size": s, "grade": g}
				var sz := Vector2(s[0], s[1]) * cell
				if x + sz.x > size.x - 30:
					x = 30.0
					y += row_h + 26.0
					row_h = 0.0
				var r := Rect2(Vector2(x, y), sz)
				ItemIcon.draw_cell_bg(self, r, g, false)
				var tex := ItemIcon.render(d, g)
				_keep.append(tex)
				var ts := Vector2(tex.get_width(), tex.get_height())
				var kk := minf((sz.x - 6) / ts.x, (sz.y - 6) / ts.y)
				draw_texture_rect(tex, Rect2(r.get_center() - ts * kk * 0.5, ts * kk), false)
				if g == 0:
					draw_string(f, Vector2(x, y + sz.y + 16), k, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
				x += sz.x + 8.0
				row_h = maxf(row_h, sz.y)
			x += 14.0
		# 数据中的全部物品
		y += row_h + 40.0
		x = 30.0
		row_h = 0.0
		for id in DB.items:
			var s2 := ItemIcon.size_of(str(id))
			var sz2 := Vector2(s2) * 46.0
			if x + sz2.x > size.x - 30:
				x = 30.0
				y += row_h + 10.0
				row_h = 0.0
			var r2 := Rect2(Vector2(x, y), sz2)
			var g2 := int(DB.items[id].get("grade", 0))
			ItemIcon.draw_cell_bg(self, r2.grow(-1), g2, false)
			ItemIcon.draw_icon(self, r2.grow(-4), str(id), g2)
			x += sz2.x + 6.0
			row_h = maxf(row_h, sz2.y)
