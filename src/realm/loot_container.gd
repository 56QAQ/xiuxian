class_name LootContainer
extends Node3D
## 可搜索的容器（秘境宝箱、药圃、矿脉、修士遗骸、祭坛；以及被击杀修士/妖兽掉落）。
## 在 "interactable" 组中；首次交互需要搜索读条，完成后打开拾取界面。

signal searched_done(container: LootContainer)

const NAMES := {"chest": "宝箱", "herb_patch": "灵药圃", "ore_vein": "矿脉", "corpse": "修士遗骸", "altar": "古祭坛",
	"cauldron": "残破丹炉", "bookshelf": "古籍书架", "beast": "妖兽尸骸", "bag": "储物袋"}

var kind: String = "chest"
var title: String = ""
var grid: InventoryGrid = InventoryGrid.new(6, 6)
var search_time: float = 3.0
var searched: bool = false
var interact_radius: float = 2.6
var best_grade: int = 0
var _glow: OmniLight3D
var _visual: Node3D


## 生成并放置容器。items 为空时按 table 抽取。
static func create(parent: Node, pos: Vector3, container_kind: String, table: String, time: float, rng: RandomNumberGenerator, items: Array[ItemInstance] = []) -> LootContainer:
	var c := LootContainer.new()
	c.kind = container_kind
	c.title = NAMES.get(container_kind, "容器")
	c.search_time = time
	parent.add_child(c)
	c.global_position = pos
	c.rotation.y = rng.randf() * TAU
	var loot := items
	if loot.is_empty() and table != "":
		loot = LootRoller.roll(table, rng, float(GS.stats.get("luck", 0.0)), float(GS.stats.get("loot_bonus", 0.0)))
	for it in loot:
		if c.grid.add(it) > 0:
			c.grid.resize(c.grid.w + 2, c.grid.h + 2)
			c.grid.add(it)
		c.best_grade = maxi(c.best_grade, it.get_grade())
	c._build_visual()
	return c


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("loot_container")


## 延迟出现（尸体倒地后再显示遗骸）
func reveal_after(t: float) -> void:
	visible = false
	remove_from_group("interactable")
	var tw := create_tween()
	tw.tween_interval(t)
	tw.tween_callback(func() -> void:
		visible = true
		add_to_group("interactable"))


func interact_prompt() -> String:
	if searched:
		return "查看%s" % title if not grid.entries.is_empty() else "%s（已空）" % title
	return "搜索%s" % title


func can_interact(_actor: Node3D) -> bool:
	return true


func interact(actor: Node3D) -> void:
	if searched:
		open_panel()
		return
	var task := SearchTask.new()
	task.container = self
	task.actor = actor
	actor.add_child(task)


func finish_search() -> void:
	searched = true
	if _glow != null:
		_glow.light_energy = 0.3
	Audio.play("search_done")
	searched_done.emit(self)
	open_panel()


func open_panel() -> void:
	Events.open_panel.emit("inventory", {"other": grid, "other_title": title})


## 秘境中其他修士搜刮：取走内容
func loot_all_into(bag: InventoryGrid) -> void:
	for it in grid.items():
		bag.add(ItemInstance.from_dict(it.to_dict()))
	grid.clear()
	searched = true


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var g: VoxelGrid
	var vs := 0.1
	match kind:
		"chest":
			g = VoxelGrid.new(10, 7, 7)
			g.fill_box(Vector3i(0, 0, 0), Vector3i(9, 6, 6), Color(0.45, 0.26, 0.12))
			g.fill_box(Vector3i(0, 4, 0), Vector3i(9, 4, 6), Color(0.85, 0.66, 0.25))
			g.fill_box(Vector3i(4, 2, 0), Vector3i(5, 4, 0), Color(0.95, 0.8, 0.3))
			g.fill_box(Vector3i(0, 0, 0), Vector3i(0, 6, 0), Color(0.85, 0.66, 0.25))
			g.fill_box(Vector3i(9, 0, 0), Vector3i(9, 6, 0), Color(0.85, 0.66, 0.25))
		"herb_patch":
			g = VoxelGrid.new(10, 6, 10)
			var rng := RandomNumberGenerator.new()
			rng.seed = get_instance_id()
			for i in 9:
				var x := rng.randi_range(1, 8)
				var z := rng.randi_range(1, 8)
				var h := rng.randi_range(2, 5)
				g.fill_box(Vector3i(x, 0, z), Vector3i(x, h - 1, z), Color(0.25, 0.65, 0.25))
				g.set_color(x, h, z, VoxelGrid.glow(Color(0.6, 1.0, 0.7), 0.6) if i % 3 == 0 else Color(0.9, 0.4, 0.6))
		"ore_vein":
			g = VoxelGrid.new(10, 8, 9)
			g.fill_ellipsoid(Vector3(5, 2, 4.5), Vector3(5, 4, 4.5), Color(0.42, 0.4, 0.4))
			for i in 6:
				g.fill_box(Vector3i(2 + i, 3 + i % 3, 1 + (i * 3) % 7), Vector3i(2 + i, 4 + i % 3, 1 + (i * 3) % 7), VoxelGrid.glow(Color(0.5, 0.85, 1.0), 0.8))
		"corpse", "bag", "beast":
			g = VoxelGrid.new(12, 3, 6)
			var cc := Color(0.35, 0.3, 0.28) if kind != "beast" else Color(0.45, 0.4, 0.36)
			g.fill_box(Vector3i(1, 0, 1), Vector3i(10, 1, 4), cc)
			g.fill_box(Vector3i(8, 0, 1), Vector3i(11, 2, 4), Color(0.85, 0.82, 0.75))
			g.fill_box(Vector3i(3, 1, 2), Vector3i(4, 2, 3), Color(0.8, 0.65, 0.3))
		"cauldron":
			g = VoxelGrid.new(10, 10, 10)
			g.fill_cylinder_y(5, 5, 4.6, 2, 7, Color(0.55, 0.42, 0.25))
			g.fill_cylinder_y(5, 5, 3.6, 5, 7, Color(0.3, 0.22, 0.14))
			g.fill_box(Vector3i(1, 0, 1), Vector3i(2, 2, 2), Color(0.5, 0.38, 0.22))
			g.fill_box(Vector3i(7, 0, 1), Vector3i(8, 2, 2), Color(0.5, 0.38, 0.22))
			g.fill_box(Vector3i(4, 0, 8), Vector3i(5, 2, 9), Color(0.5, 0.38, 0.22))
			g.fill_box(Vector3i(0, 7, 4), Vector3i(0, 9, 5), Color(0.62, 0.48, 0.28))
			g.fill_box(Vector3i(9, 7, 4), Vector3i(9, 9, 5), Color(0.62, 0.48, 0.28))
			g.fill_cylinder_y(5, 5, 2.0, 7, 7, VoxelGrid.glow(Color(1.0, 0.55, 0.2), 0.7))
		"bookshelf":
			g = VoxelGrid.new(12, 14, 4)
			g.fill_box(Vector3i(0, 0, 0), Vector3i(11, 13, 3), Color(0.4, 0.26, 0.14))
			for row in [2, 6, 10]:
				g.clear_box(Vector3i(1, row, 0), Vector3i(10, row + 2, 2))
				for x in range(1, 11):
					if (x * 7 + row) % 5 != 0:
						var bc: Color = [Color(0.7, 0.2, 0.15), Color(0.2, 0.35, 0.6), Color(0.8, 0.7, 0.4), Color(0.3, 0.5, 0.3)][(x + row) % 4]
						g.fill_box(Vector3i(x, row, 1), Vector3i(x, row + 1 + (x % 2), 2), bc)
		"altar":
			g = VoxelGrid.new(12, 10, 12)
			g.fill_box(Vector3i(0, 0, 0), Vector3i(11, 2, 11), Color(0.6, 0.58, 0.55))
			g.fill_box(Vector3i(2, 3, 2), Vector3i(9, 6, 9), Color(0.7, 0.68, 0.64))
			g.fill_box(Vector3i(4, 7, 4), Vector3i(7, 9, 7), VoxelGrid.glow(Color(1.0, 0.8, 0.4), 1.0))
		_:
			g = VoxelGrid.new(8, 8, 8)
			g.fill_box(Vector3i(0, 0, 0), Vector3i(7, 7, 7), Color(0.5, 0.4, 0.3))
	var mi := VoxelMesher.build_instance(g, vs, Vector3(-g.sx * vs * 0.5, 0, -g.sz * vs * 0.5))
	_visual.add_child(mi)
	# 品阶光晕（灵品以上，或有“灵眼”天赋时显示）
	var see := GS.player.has_talent("spirit_eye") or best_grade >= 3
	if best_grade >= 1 and see:
		_glow = OmniLight3D.new()
		_glow.light_color = Grade.color_of(best_grade)
		_glow.light_energy = 0.8 + best_grade * 0.4
		_glow.omni_range = 3.0 + best_grade
		_glow.position = Vector3(0, 0.8, 0)
		add_child(_glow)
