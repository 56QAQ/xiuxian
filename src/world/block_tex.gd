class_name BlockTex
## 方块材质：纹理数组（assets/textures/world/blocks_*.png，由 tools/gen_world_textures.py 生成）、
## 共享 ShaderMaterial（block.gdshader）与“方块种类”（建筑/道具体素的顶、侧、底三面材质层）。
## 网格约定：COLOR = 均值反照率（sRGB，含 AO），UV.x = 材质层（BlockIds），UV.y = 风摆幅度。
## 环境参数（积雪、水位、夜窗、风）通过 set_env() 同步到所有共享材质。

const SHADER_PATH := "res://assets/shaders/block.gdshader"
const ALBEDO_PATH := "res://assets/textures/world/blocks_albedo.png"
const DETAIL_PATH := "res://assets/textures/world/blocks_detail.png"
const MAX_LAYERS := 96

# ---------------------------------------------------------------- 方块种类（K_*）
const K_PLAIN := 0
const K_STONE := 1          ## 石台基/台阶：顶石板，侧条石
const K_STONE_SMOOTH := 2   ## 汉白玉/玉石
const K_BRICK := 3          ## 青砖
const K_WALL := 4           ## 白粉墙
const K_ROOF := 5           ## 黛瓦：顶鱼鳞瓦，侧瓦当，底椽子
const K_GLAZED := 6         ## 琉璃瓦
const K_RIDGE := 7          ## 屋脊
const K_PILLAR := 8         ## 漆柱（竖纹）
const K_BEAM := 9           ## 漆枋（横纹）
const K_PAINTED := 10       ## 彩画额枋
const K_WOOD := 11          ## 木板
const K_DOOR := 12          ## 门扇（门钉）
const K_LATTICE := 13       ## 窗棂（夜间透光）
const K_GOLD := 14          ## 金饰
const K_BRONZE := 15        ## 青铜
const K_LANTERN := 16       ## 纸灯笼
const K_CLOTH := 17         ## 布
const K_SOIL := 18          ## 药田土
const K_LEAF := 19          ## 叶（阔叶）
const K_LOG := 20           ## 原木：侧树皮，顶年轮
const K_GLOW := 21          ## 发光体
const K_RUNE := 22          ## 符纹
const K_CRYSTAL := 23       ## 晶体
const K_TILE_FLOOR := 24    ## 地砖
const K_CARVED := 25        ## 浮雕石
const K_GRASS := 26         ## 草方块
const K_DIRT := 27
const K_COBBLE := 28
const K_MOSSY := 29
const K_SNOW := 30          ## 雪（道具/树上的积雪：各面均为雪）
const K_ICE := 31
const K_PINE := 32
const K_MAPLE := 33
const K_BLOSSOM := 34
const K_BAMBOO := 35        ## 竹竿
const K_BAMBOO_LEAF := 36
const K_WILLOW := 37
const K_BARK := 38          ## 全树皮（枝干）
const K_ROCK := 39          ## 自然岩石
const K_ROCK_RED := 40
const K_ROCK_YELLOW := 41
const K_GRANITE := 42
const K_MOSS := 43
const K_SAND := 44
const K_BASALT := 45
const K_OBSIDIAN := 46
const K_LAVA := 47
const K_RAMMED := 48        ## 夯土
const K_FLAGSTONE := 49     ## 石板（顶、侧同）
const K_GRASS_BLADE := 50   ## 草叶（随风摇摆的小体素）
const K_REED := 51
const K_PLANKS_FLOOR := 52  ## 木地板
const K_LOESS := 53

## 每种：[顶, 侧, 底]
const KIND_FACES := [
	[BlockIds.PLAIN, BlockIds.PLAIN, BlockIds.PLAIN],
	[BlockIds.FLAGSTONE, BlockIds.STONE_BRICK, BlockIds.STONE_BRICK],
	[BlockIds.MARBLE, BlockIds.MARBLE, BlockIds.MARBLE],
	[BlockIds.BRICK, BlockIds.BRICK, BlockIds.BRICK],
	[BlockIds.PLASTER, BlockIds.PLASTER, BlockIds.PLASTER],
	[BlockIds.ROOF_TOP, BlockIds.ROOF_SIDE, BlockIds.ROOF_UNDER],
	[BlockIds.GLAZED_TOP, BlockIds.GLAZED_SIDE, BlockIds.ROOF_UNDER],
	[BlockIds.ROOF_RIDGE, BlockIds.ROOF_RIDGE, BlockIds.ROOF_RIDGE],
	[BlockIds.LACQUER_H, BlockIds.LACQUER_V, BlockIds.LACQUER_H],
	[BlockIds.LACQUER_H, BlockIds.LACQUER_H, BlockIds.LACQUER_H],
	[BlockIds.LACQUER_H, BlockIds.PAINTED_BEAM, BlockIds.LACQUER_H],
	[BlockIds.PLANKS, BlockIds.PLANKS, BlockIds.PLANKS],
	[BlockIds.PLANKS, BlockIds.DOOR_PANEL, BlockIds.PLANKS],
	[BlockIds.PLANKS, BlockIds.LATTICE, BlockIds.PLANKS],
	[BlockIds.GOLD, BlockIds.GOLD, BlockIds.GOLD],
	[BlockIds.BRONZE, BlockIds.BRONZE, BlockIds.BRONZE],
	[BlockIds.PAPER_LANTERN, BlockIds.PAPER_LANTERN, BlockIds.PAPER_LANTERN],
	[BlockIds.CLOTH, BlockIds.CLOTH, BlockIds.CLOTH],
	[BlockIds.FARMLAND, BlockIds.DIRT, BlockIds.DIRT],
	[BlockIds.LEAF_BROAD, BlockIds.LEAF_BROAD, BlockIds.LEAF_BROAD],
	[BlockIds.LOG_END, BlockIds.LOG_BARK, BlockIds.LOG_END],
	[BlockIds.GLOW_PLAIN, BlockIds.GLOW_PLAIN, BlockIds.GLOW_PLAIN],
	[BlockIds.RUNE, BlockIds.RUNE, BlockIds.RUNE],
	[BlockIds.CRYSTAL, BlockIds.CRYSTAL, BlockIds.CRYSTAL],
	[BlockIds.FLOOR_TILE, BlockIds.STONE_BRICK, BlockIds.STONE_BRICK],
	[BlockIds.STONE_CARVED, BlockIds.STONE_CARVED, BlockIds.STONE_CARVED],
	[BlockIds.GRASS_TOP, BlockIds.GRASS_SIDE, BlockIds.DIRT],
	[BlockIds.DIRT, BlockIds.DIRT, BlockIds.DIRT],
	[BlockIds.COBBLE, BlockIds.COBBLE, BlockIds.COBBLE],
	[BlockIds.MOSSY_STONE, BlockIds.MOSSY_STONE, BlockIds.MOSSY_STONE],
	[BlockIds.SNOW, BlockIds.SNOW, BlockIds.SNOW],
	[BlockIds.ICE, BlockIds.ICE, BlockIds.ICE],
	[BlockIds.LEAF_PINE, BlockIds.LEAF_PINE, BlockIds.LEAF_PINE],
	[BlockIds.LEAF_MAPLE, BlockIds.LEAF_MAPLE, BlockIds.LEAF_MAPLE],
	[BlockIds.LEAF_BLOSSOM, BlockIds.LEAF_BLOSSOM, BlockIds.LEAF_BLOSSOM],
	[BlockIds.BAMBOO_STALK, BlockIds.BAMBOO_STALK, BlockIds.BAMBOO_STALK],
	[BlockIds.LEAF_BAMBOO, BlockIds.LEAF_BAMBOO, BlockIds.LEAF_BAMBOO],
	[BlockIds.LEAF_WILLOW, BlockIds.LEAF_WILLOW, BlockIds.LEAF_WILLOW],
	[BlockIds.LOG_BARK, BlockIds.LOG_BARK, BlockIds.LOG_BARK],
	[BlockIds.STONE, BlockIds.STONE, BlockIds.STONE],
	[BlockIds.RED_ROCK, BlockIds.RED_ROCK, BlockIds.RED_ROCK],
	[BlockIds.LOESS, BlockIds.LOESS, BlockIds.LOESS],
	[BlockIds.GRANITE, BlockIds.GRANITE, BlockIds.GRANITE],
	[BlockIds.MOSS, BlockIds.MOSSY_STONE, BlockIds.STONE],
	[BlockIds.SAND, BlockIds.SAND, BlockIds.SAND],
	[BlockIds.BASALT, BlockIds.BASALT, BlockIds.BASALT],
	[BlockIds.OBSIDIAN, BlockIds.OBSIDIAN, BlockIds.OBSIDIAN],
	[BlockIds.LAVA, BlockIds.LAVA, BlockIds.LAVA],
	[BlockIds.RAMMED_EARTH, BlockIds.RAMMED_EARTH, BlockIds.RAMMED_EARTH],
	[BlockIds.FLAGSTONE, BlockIds.FLAGSTONE, BlockIds.FLAGSTONE],
	[BlockIds.PLAIN, BlockIds.PLAIN, BlockIds.PLAIN],
	[BlockIds.PLAIN, BlockIds.PLAIN, BlockIds.PLAIN],
	[BlockIds.PLANKS, BlockIds.PLANKS, BlockIds.PLANKS],
	[BlockIds.LOESS, BlockIds.LOESS, BlockIds.LOESS],
]
## 种类的风摆类型：0 无，1 叶（整体微颤），2 草（随高度摇摆）
const KIND_WIND := {K_LEAF: 1, K_PINE: 1, K_MAPLE: 1, K_BLOSSOM: 1, K_BAMBOO_LEAF: 1, K_WILLOW: 1, K_GRASS_BLADE: 2, K_REED: 2}

## 线程安全的运行时副本（Godot 4.4 并发读取 const 容器不安全）
static var _faces := _flat_faces()
static var _wind := _wind_arr()
static var _mats: Dictionary = {}
static var _albedo: TextureLayered
static var _detail: TextureLayered
static var _env := {
	"snow_params": Vector4(34.0, 52.0, 360.0, 250.0), "snow_global": 0.0, "water_level": 11.8, "night_glow": 0.0,
	"wind_strength": 1.0, "snow_tint": Color(0.93, 0.95, 1.0),
}


static func _flat_faces() -> PackedInt32Array:
	var out := PackedInt32Array()
	for f in KIND_FACES:
		out.append(int(f[0]))
		out.append(int(f[1]))
		out.append(int(f[2]))
	return out


static func _wind_arr() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(KIND_FACES.size())
	for k in KIND_WIND:
		out[int(k)] = int(KIND_WIND[k])
	return out


## 种类 kind 的某面材质层：face 0 顶、1 侧、2 底
static func face_layer(kind: int, face: int) -> int:
	return _faces[clampi(kind, 0, KIND_FACES.size() - 1) * 3 + face]


static func kind_wind(kind: int) -> int:
	if kind < 0 or kind >= _wind.size():
		return 0
	return _wind[kind]


static func kind_count() -> int:
	return KIND_FACES.size()


## 共享材质：name = "terrain"（近景地形）、"lod"（远景，带丢弃圆）、"static"（建筑/道具）
static func material(name: String = "static") -> ShaderMaterial:
	if _mats.has(name):
		return _mats[name]
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_PATH)
	_setup(m)
	match name:
		"lod":
			m.set_shader_parameter("use_holes", true)
			m.set_shader_parameter("block_jitter", 0.035)
			m.set_shader_parameter("detail_contrast", 0.75)
			m.set_shader_parameter("normal_strength", 0.6)
		"terrain":
			m.set_shader_parameter("block_jitter", 0.06)
		_:
			m.set_shader_parameter("block_jitter", 0.03)
			m.set_shader_parameter("macro_variation", 0.06)
	for k in _env:
		m.set_shader_parameter(k, _env[k])
	_mats[name] = m
	return m


static func textures() -> Array:
	if _albedo == null:
		_albedo = load(ALBEDO_PATH)
		_detail = load(DETAIL_PATH)
	return [_albedo, _detail]


static func _setup(m: ShaderMaterial) -> void:
	var tx := textures()
	m.set_shader_parameter("albedo_tex", tx[0])
	m.set_shader_parameter("detail_tex", tx[1])
	var info: Array[Vector4] = []
	var avg: Array[Vector4] = []
	for i in MAX_LAYERS:
		if i < BlockIds.COUNT:
			info.append(BlockIds.INFO[i])
			var c: Color = BlockIds.AVG[i]
			avg.append(Vector4(c.r, c.g, c.b, 1.0))
		else:
			info.append(Vector4(1, 0, 0, 0))
			avg.append(Vector4(0.5, 0.5, 0.5, 1.0))
	m.set_shader_parameter("layer_info", info)
	m.set_shader_parameter("layer_avg", avg)
	m.set_shader_parameter("snow_layer", BlockIds.SNOW)


## 新建一个独立材质（例如秘境/试炼场需要不同环境参数时），不进入共享缓存
static func new_material(params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_PATH)
	_setup(m)
	for k in _env:
		m.set_shader_parameter(k, _env[k])
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


## 设置环境参数并同步到所有共享材质：snow_params、snow_global、water_level、night_glow、wind_strength、snow_tint
static func set_env(params: Dictionary) -> void:
	for k in params:
		_env[k] = params[k]
	for name in _mats:
		var m: ShaderMaterial = _mats[name]
		for k in params:
			m.set_shader_parameter(k, params[k])


static func get_env(key: String) -> Variant:
	return _env.get(key)


## 恢复大地图默认环境（场景切换时调用）
static func reset_env() -> void:
	set_env({"snow_params": Vector4(34.0, 52.0, 360.0, 250.0), "snow_global": 0.0, "water_level": 11.8, "night_glow": 0.0,
		"wind_strength": 1.0, "snow_tint": Color(0.93, 0.95, 1.0)})


static func clear_cache() -> void:
	_mats.clear()
	_albedo = null
	_detail = null
