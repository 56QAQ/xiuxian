class_name BlockIds
## 方块材质层编号与每层参数（由 tools/gen_world_textures.py 自动生成，请勿手改）。
## 层在 Texture2DArray（assets/textures/world/blocks_*.png）中的序号；带变体的层占用连续多层，常量指向第一层。

const COUNT := 73

# 标志位（与 block.gdshader 一致）
const F_SNOW := 1
const F_WET := 2
const F_WIND_LEAF := 4
const F_WIND_GRASS := 8
const F_EMIT_MASK := 16
const F_LAVA := 32
const F_METAL := 64
const F_NIGHT_GLOW := 128
const F_GLOSSY := 256
const F_CRYSTAL := 512
const F_FOLIAGE := 1024
const F_TERRAIN := 2048

# 层编号
const PLAIN := 0
const GRASS_TOP := 1
const DIRT := 4
const GRASS_SIDE := 6
const STONE := 7
const COBBLE := 9
const MOSSY_STONE := 11
const GRAVEL := 12
const SAND := 13
const SNOW := 15
const PACKED_SNOW := 17
const SNOW_SIDE := 18
const ICE := 19
const RED_ROCK := 20
const BASALT := 21
const OBSIDIAN := 22
const LAVA := 23
const LOESS := 24
const CLAY_LAYERS := 25
const RAMMED_EARTH := 26
const MUD := 27
const FARMLAND := 28
const DRY_GRASS := 29
const FOREST_FLOOR := 31
const ASH := 32
const GRANITE := 33
const PATH := 35
const BLACK_SAND := 36
const MOSS := 37
const PLANKS := 38
const LOG_BARK := 39
const LOG_END := 40
const LEAF_BROAD := 41
const LEAF_PINE := 42
const LEAF_MAPLE := 43
const LEAF_BAMBOO := 44
const LEAF_WILLOW := 45
const LEAF_BLOSSOM := 46
const BAMBOO_STALK := 47
const ROOF_TOP := 48
const ROOF_SIDE := 49
const ROOF_UNDER := 50
const ROOF_RIDGE := 51
const GLAZED_TOP := 52
const GLAZED_SIDE := 53
const LACQUER_V := 54
const LACQUER_H := 55
const PAINTED_BEAM := 56
const PLASTER := 57
const BRICK := 58
const STONE_BRICK := 59
const FLAGSTONE := 60
const FLOOR_TILE := 61
const MARBLE := 62
const LATTICE := 63
const PAPER_LANTERN := 64
const STONE_CARVED := 65
const GOLD := 66
const BRONZE := 67
const DOOR_PANEL := 68
const CLOTH := 69
const CRYSTAL := 70
const RUNE := 71
const GLOW_PLAIN := 72

## 每层名称
const NAMES := ["plain", "grass_top", "grass_top_1", "grass_top_2", "dirt", "dirt_1", "grass_side", "stone", "stone_1", "cobble", "cobble_1", "mossy_stone", "gravel", "sand", "sand_1", "snow", "snow_1", "packed_snow", "snow_side", "ice", "red_rock", "basalt", "obsidian", "lava", "loess", "clay_layers", "rammed_earth", "mud", "farmland", "dry_grass", "dry_grass_1", "forest_floor", "ash", "granite", "granite_1", "path", "black_sand", "moss", "planks", "log_bark", "log_end", "leaf_broad", "leaf_pine", "leaf_maple", "leaf_bamboo", "leaf_willow", "leaf_blossom", "bamboo_stalk", "roof_top", "roof_side", "roof_under", "roof_ridge", "glazed_top", "glazed_side", "lacquer_v", "lacquer_h", "painted_beam", "plaster", "brick", "stone_brick", "flagstone", "floor_tile", "marble", "lattice", "paper_lantern", "stone_carved", "gold", "bronze", "door_panel", "cloth", "crystal", "rune", "glow_plain"]
## 每层参数：x 变体数，y 变换模式（0 无 / 1 左右翻转 / 2 旋转+翻转），z 标志位，w 保色
const INFO := [
	Vector4(1, 2, 0, 0.00),  # plain
	Vector4(3, 2, 2051, 1.00),  # grass_top
	Vector4(1, 2, 2051, 1.00),  # grass_top_1
	Vector4(1, 2, 2051, 1.00),  # grass_top_2
	Vector4(2, 2, 2051, 1.00),  # dirt
	Vector4(1, 2, 2051, 1.00),  # dirt_1
	Vector4(1, 1, 2051, 1.00),  # grass_side
	Vector4(2, 2, 2051, 1.00),  # stone
	Vector4(1, 2, 2051, 1.00),  # stone_1
	Vector4(2, 2, 2051, 1.00),  # cobble
	Vector4(1, 2, 2051, 1.00),  # cobble_1
	Vector4(1, 2, 2051, 1.00),  # mossy_stone
	Vector4(1, 2, 2051, 1.00),  # gravel
	Vector4(2, 2, 2051, 1.00),  # sand
	Vector4(1, 2, 2051, 1.00),  # sand_1
	Vector4(2, 2, 2049, 1.00),  # snow
	Vector4(1, 2, 2049, 1.00),  # snow_1
	Vector4(1, 1, 2049, 1.00),  # packed_snow
	Vector4(1, 1, 2049, 1.00),  # snow_side
	Vector4(1, 2, 2304, 1.00),  # ice
	Vector4(1, 1, 2051, 1.00),  # red_rock
	Vector4(1, 1, 2051, 1.00),  # basalt
	Vector4(1, 2, 2304, 1.00),  # obsidian
	Vector4(1, 2, 48, 1.00),  # lava
	Vector4(1, 1, 2051, 1.00),  # loess
	Vector4(1, 1, 2051, 1.00),  # clay_layers
	Vector4(1, 1, 3, 1.00),  # rammed_earth
	Vector4(1, 2, 2051, 1.00),  # mud
	Vector4(1, 1, 3, 1.00),  # farmland
	Vector4(2, 2, 2051, 1.00),  # dry_grass
	Vector4(1, 2, 2051, 1.00),  # dry_grass_1
	Vector4(1, 2, 2051, 1.00),  # forest_floor
	Vector4(1, 2, 2051, 1.00),  # ash
	Vector4(2, 2, 2051, 1.00),  # granite
	Vector4(1, 2, 2051, 1.00),  # granite_1
	Vector4(1, 2, 2051, 1.00),  # path
	Vector4(1, 2, 2051, 1.00),  # black_sand
	Vector4(1, 2, 3075, 1.00),  # moss
	Vector4(1, 1, 3, 0.60),  # planks
	Vector4(1, 1, 3, 1.00),  # log_bark
	Vector4(1, 2, 1, 1.00),  # log_end
	Vector4(1, 2, 1029, 1.00),  # leaf_broad
	Vector4(1, 2, 1029, 1.00),  # leaf_pine
	Vector4(1, 2, 1029, 1.00),  # leaf_maple
	Vector4(1, 1, 1029, 1.00),  # leaf_bamboo
	Vector4(1, 1, 1028, 1.00),  # leaf_willow
	Vector4(1, 2, 1029, 1.00),  # leaf_blossom
	Vector4(1, 1, 1, 1.00),  # bamboo_stalk
	Vector4(1, 1, 3, 0.30),  # roof_top
	Vector4(1, 1, 3, 0.30),  # roof_side
	Vector4(1, 1, 0, 0.40),  # roof_under
	Vector4(1, 1, 1, 0.30),  # roof_ridge
	Vector4(1, 1, 257, 0.30),  # glazed_top
	Vector4(1, 1, 257, 0.30),  # glazed_side
	Vector4(1, 1, 2, 0.20),  # lacquer_v
	Vector4(1, 1, 3, 0.20),  # lacquer_h
	Vector4(1, 1, 0, 0.25),  # painted_beam
	Vector4(1, 1, 3, 0.30),  # plaster
	Vector4(1, 1, 3, 0.35),  # brick
	Vector4(1, 1, 3, 0.30),  # stone_brick
	Vector4(1, 2, 3, 0.30),  # flagstone
	Vector4(1, 2, 3, 0.30),  # floor_tile
	Vector4(1, 2, 3, 0.50),  # marble
	Vector4(1, 1, 128, 0.40),  # lattice
	Vector4(1, 1, 16, 0.30),  # paper_lantern
	Vector4(1, 1, 3, 0.30),  # stone_carved
	Vector4(1, 2, 64, 0.15),  # gold
	Vector4(1, 2, 66, 1.00),  # bronze
	Vector4(1, 1, 2, 0.30),  # door_panel
	Vector4(1, 1, 2, 0.30),  # cloth
	Vector4(1, 1, 784, 0.20),  # crystal
	Vector4(1, 1, 16, 0.30),  # rune
	Vector4(1, 2, 16, 0.00),  # glow_plain
]
## 每层线性空间平均色（着色器用于求细节比值）
const AVG := [
	Color(0.20813, 0.20813, 0.19832),  # plain
	Color(0.05401, 0.16660, 0.02666),  # grass_top
	Color(0.05602, 0.17225, 0.02724),  # grass_top_1
	Color(0.05365, 0.16511, 0.02648),  # grass_top_2
	Color(0.12701, 0.06335, 0.03260),  # dirt
	Color(0.13681, 0.06878, 0.03545),  # dirt_1
	Color(0.10385, 0.07769, 0.02910),  # grass_side
	Color(0.13188, 0.14039, 0.13668),  # stone
	Color(0.13128, 0.13975, 0.13792),  # stone_1
	Color(0.12378, 0.13052, 0.12924),  # cobble
	Color(0.11613, 0.12266, 0.12192),  # cobble_1
	Color(0.08647, 0.17172, 0.07419),  # mossy_stone
	Color(0.12738, 0.11362, 0.10021),  # gravel
	Color(0.63501, 0.48072, 0.24694),  # sand
	Color(0.64166, 0.48743, 0.25214),  # sand_1
	Color(0.75426, 0.81918, 0.90320),  # snow
	Color(0.75695, 0.82151, 0.90524),  # snow_1
	Color(0.60642, 0.69313, 0.81207),  # packed_snow
	Color(0.62326, 0.70620, 0.81951),  # snow_side
	Color(0.34919, 0.55254, 0.73020),  # ice
	Color(0.15481, 0.02782, 0.01326),  # red_rock
	Color(0.04111, 0.03727, 0.04932),  # basalt
	Color(0.02884, 0.01722, 0.04531),  # obsidian
	Color(0.38562, 0.13622, 0.02651),  # lava
	Color(0.44954, 0.25551, 0.06894),  # loess
	Color(0.52257, 0.28811, 0.13521),  # clay_layers
	Color(0.43176, 0.24426, 0.06537),  # rammed_earth
	Color(0.05853, 0.03934, 0.02343),  # mud
	Color(0.05179, 0.02843, 0.01396),  # farmland
	Color(0.27007, 0.20085, 0.04969),  # dry_grass
	Color(0.21833, 0.16878, 0.04084),  # dry_grass_1
	Color(0.04387, 0.12108, 0.02184),  # forest_floor
	Color(0.05146, 0.04032, 0.03883),  # ash
	Color(0.13997, 0.15630, 0.17763),  # granite
	Color(0.13908, 0.15514, 0.17612),  # granite_1
	Color(0.22955, 0.14921, 0.08475),  # path
	Color(0.03696, 0.03406, 0.04542),  # black_sand
	Color(0.02694, 0.09187, 0.02037),  # moss
	Color(0.14199, 0.06870, 0.03098),  # planks
	Color(0.04564, 0.02368, 0.01235),  # log_bark
	Color(0.22810, 0.11960, 0.04886),  # log_end
	Color(0.02243, 0.07727, 0.01714),  # leaf_broad
	Color(0.00711, 0.02656, 0.01506),  # leaf_pine
	Color(0.38328, 0.03384, 0.00758),  # leaf_maple
	Color(0.04794, 0.13495, 0.02060),  # leaf_bamboo
	Color(0.06701, 0.14362, 0.02121),  # leaf_willow
	Color(0.55267, 0.21991, 0.29591),  # leaf_blossom
	Color(0.17722, 0.36091, 0.06292),  # bamboo_stalk
	Color(0.08129, 0.08976, 0.10803),  # roof_top
	Color(0.10668, 0.11756, 0.13981),  # roof_side
	Color(0.33240, 0.27005, 0.22904),  # roof_under
	Color(0.11182, 0.12397, 0.14873),  # roof_ridge
	Color(0.24677, 0.23529, 0.21877),  # glazed_top
	Color(0.27674, 0.26442, 0.24567),  # glazed_side
	Color(0.33996, 0.27406, 0.23024),  # lacquer_v
	Color(0.34454, 0.27785, 0.23366),  # lacquer_h
	Color(0.34803, 0.33399, 0.31170),  # painted_beam
	Color(0.63511, 0.61477, 0.57023),  # plaster
	Color(0.15209, 0.16694, 0.19538),  # brick
	Color(0.28684, 0.27420, 0.25420),  # stone_brick
	Color(0.27611, 0.26374, 0.24449),  # flagstone
	Color(0.30206, 0.28900, 0.26832),  # floor_tile
	Color(0.64166, 0.62107, 0.57738),  # marble
	Color(0.65392, 0.63172, 0.59430),  # lattice
	Color(0.63702, 0.61553, 0.57463),  # paper_lantern
	Color(0.29058, 0.27783, 0.25764),  # stone_carved
	Color(0.56077, 0.54057, 0.49816),  # gold
	Color(0.14951, 0.14997, 0.08326),  # bronze
	Color(0.33053, 0.26848, 0.22678),  # door_panel
	Color(0.63087, 0.61061, 0.56691),  # cloth
	Color(0.68471, 0.66466, 0.62328),  # crystal
	Color(0.28289, 0.27047, 0.25073),  # rune
	Color(0.69032, 0.66896, 0.62780),  # glow_plain
]
