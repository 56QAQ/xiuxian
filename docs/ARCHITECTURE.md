# 技术架构

Godot 4.4+（在 4.4.1 与 4.7.2 上验证），GDScript（静态类型），Forward+ 渲染，Jolt 物理。

## 目录

```
project.godot          输入映射在 src/autoload/settings.gd 中用代码注册
data/*.json            全部设计数据（见 docs/DATA.md）
assets/                字体（XianKai，OFL）、着色器、音效
scenes/*.tscn          顶层场景（只有根节点 + 脚本，内容由代码构建）
src/
  autoload/            全局单例
  core/                纯工具：Elem（五行）、Grade（品阶）、Stats（属性表）
  systems/             纯数据/规则层（不依赖场景树）：PlayerData、ItemInstance、InventoryGrid、
                       BuildCalc、Cultivation、WorldSetup、NpcSystem、SectSystem ...
  voxel/               体素：VoxelGrid、VoxelMesher、CharacterRig、AnimLib、CharacterBuilder、WeaponBuilder ...
  world/               大地图：地形、区块流式加载、生物群系、建筑、昼夜
  combat/              战斗：Combatant、伤害、状态、弹道、法诀运行时、特效、镜头
  actors/              角色：HumanoidActor（玩家与修士共用）、BeastActor、PlayerController、CultivatorAI、BeastAI、ActorFactory、GameSession
  gameplay/            大地图玩法层：OverworldGameplay（NPC 生成、交互点、地点）、EncounterDirector、TreasureSite、SectPanel
  realm/               秘境：生成（HeightfieldTerrain）、LootContainer、SearchTask、ExtractionPoint
  ui/                  界面
tests/                 无头测试（tools/run_tests.sh）
tools/                 字体子集化、截图（tools/shot.sh）、音效生成
```

## 全局单例（autoload）

| 名称 | 文件 | 职责 |
|---|---|---|
| `Settings` | settings.gd | 输入映射注册（`BINDINGS`）、用户设置读写 |
| `Events` | events.gd | 全局信号总线：notify、player_changed、inventory_changed、realm_changed、hit_landed、actor_died、open_panel … |
| `DB` | db.gd | 读取 `data/*.json`；`DB.item(id)`、`DB.spell(id)`、`DB.realm(i)`、`DB.realm_name(i, stage)` |
| `GS` | game_state.gd | `GS.player: PlayerData`、`GS.stats`（最终属性）、`GS.world`（世界存档字典）、时间、给予物品、装备、学习功法 |
| `SaveManager` | save_manager.gd | JSON 存档 `user://saves/slot_N.json` |
| `Audio` | audio.gd | 音效 `Audio.play(name)`、`Audio.play_at(name, pos)`（`assets/audio/sfx/<name>.wav`）；音乐 `play_music(name, fade)`、`stop_music(fade)`（`assets/audio/music/<name>.ogg`，交叉淡变、循环） |
| `Scenes` | scenes.gd | 淡入淡出切换：`goto_main_menu / goto_creator / goto_overworld / goto_realm(req)` |

## 数据层（src/systems）

- **PlayerData**：玩家（以及 NPC）的全部可存档数据。NPC 也用 PlayerData 表示其境界/灵根/装备/法诀，使战斗属性计算完全复用。
- **ItemInstance**：`id, count, grade(-1=默认), affixes[{k,v}], extra{}`；`def()` 取 DB 定义；`equip_mods()` 给出装备修正。
- **InventoryGrid**：网格背包，条目 `{item, x, y, rot}`；`add()` 自动堆叠/找位（含旋转），`take()`、`can_fit()`、`resize()`、序列化。
- **Stats**：属性以 `Dictionary` 表示。修正值 `"attack": 5`（平加）与 `"attack_pct": 0.1`（百分比，求和后乘算）。`Stats.resolve(base, mods)`。
- **BuildCalc**：`compute(p) -> stats`，汇总 境界基础 × 小境界成长 + 先天属性 + 灵根被动 + 天赋 + 出身 + 功法 + 法器 + 境界质变 + 伤势/丹毒。`elem_power(p, e)` 给出某系法术倍率；`resonance_pairs(p)` 相生共鸣。
- **Cultivation**：修为、自动小境界、瓶颈、突破判定、丹药、炼化、战斗感悟、时间流逝。

修改 PlayerData 后调用 `GS.recompute()` 刷新 `GS.stats` 并广播 `Events.player_changed`。

## 体素与动画（src/voxel）

- **VoxelGrid**：稠密网格，颜色 RGBA8（0=空）；alpha<1 表示自发光（`VoxelGrid.glow(c, s)`）。
- **VoxelMesher.build(grid, voxel_size, origin)**：面剔除 + 逐顶点 AO → ArrayMesh；共享材质 `assets/shaders/voxel.gdshader`（sRGB 顶点色、发光、instance uniform：`flash`、`flash_color`、`dissolve`、`tint`）。
- **CharacterRig**（Node3D）：骨骼节点名固定（`BONES`），`setup()` 记录静止姿势。
  - 移动：Actor 每帧写入 `set_locomotion(local_vel, grounded, boosting, flying)`、`stance`（武器类型）、`meditating`。
  - 动作：`play(clip_name, speed) -> 时长`，信号 `anim_event(name)`（如近战 `"hit"`、施法 `"cast"`）与 `action_finished(name)`。
  - 弹簧骨骼：名字以 `hair_` / `tail` / `ear_` / `cloth_` 开头的节点自动做二次运动；meta `spring_length`、`spring_stiffness`、`spring_limit`、`spring_dir`（默认向下）。
  - 表现：`flash(amount, color)`、`set_dissolve(v)`、`set_tint(c, a)`、`attach_to_hand(node, "r")`、`weapon_tip()`。
  - 旋转约定：面朝 -Z，右手 +X；下垂肢体 +X=前摆，膝 -X，肘 +X；向上骨骼 -X=前倾；右臂 +Z 外展，左臂 -Z 外展；+Y=左转。武器握把在原点、刃沿 -Z。
- **AnimLib**：`stance_pose(kind)`、`pose(name)`、`get_clip(name)`。剪辑为关键帧字典，支持 mask（full/upper/arm）、缓动、事件、loop、hold。
- **CharacterBuilder.build(appearance, equip_visual, opts) -> CharacterRig**（实际为 HumanoidRig：裙摆随腿、发丝重力、眨眼）：外貌字段见 DATA.md。VOXEL = 0.0125m（每米 80 体素，头 32³；骨骼位置的米制尺寸与旧版 0.025m 完全相同），身高约 1.75m。`random_appearance(rng, gender)` 生成 NPC 外貌。opts `{"lod": false}` 不挂远景 LOD（界面预览）。
  - **build_async(appearance, equip_visual, opts)**：同参数，立即返回（隐藏的）骨架，网格在工作线程生成，完成后自动显示并发出 `rig.meshes_ready`；动画/挂武器/闪白可立即使用。`rig.meshes_pending()`、`rig.finish_meshes()`（阻塞等待）。
  - 部件以 VoxCanvas 绘制、VoxMesh 网格化（隐藏面剔除 + AO + 二维贪心合并 + 按参数缓存）。缺失部件在 WorkerThreadPool（高优先级）并行生成；同步构建只等近景 LOD0，远景 LOD1（2× 降采样）随后在后台生成，由 `VoxMesh.poll()`（CharacterRig 每帧调用）填入；`VoxMesh.finish_pending()` 阻塞等待全部完成。
  - LOD：每个部件两个 MeshInstance3D，visibility range 在约 22m 处切换（`VoxMesh.lod_distance`）。
  - 材质通道：体素低 8 位为属性字节（材质 << 4 | 发光等级），经顶点色 alpha 传给 `assets/shaders/voxel_char.gdshader`：布、皮肤（包裹光 + 次表面暖色）、头发（各向异性光泽）、金饰/钢银（GGX 金属高光）、宝石（高光 + 微自发光）、皮革、毛皮、眼睛、石、鳞角、丝绸、玉、火焰；另有菲涅尔边缘光。instance uniform 与 voxel.gdshader 相同（`flash`、`flash_color`、`dissolve`、`tint`）。
- **WeaponBuilder.build(visual, hand) -> Node3D**：meta `tip_length`；`attach_to_rig(rig, visual)`（拳套双手）；旗枪旗面与流苏有摆动。visual.length 仍为旧单位（0.025m），内部 ×2。
- **BeastBuilder.build(model, colors, size) -> BeastRig**（另有 `build_async` 同参数）：wolf fox boar bear snake crane spider golem；体型 quad/serpent/bird/spider/humanoid 各有步态；剪辑 bite pounce charge slam spit hit_front stagger death howl（`BeastRig.hit_time()` 给出出手帧）。
- **RigPreview**（src/ui）：捏人/角色面板/对话头像共用的影棚预览；取景 `full`/`upper`/`bust`（面容特写）/`face`。

## 大地图（src/world）

- **TerrainGen**（`TerrainGen.shared(seed)`，按种子缓存）：1024×1024 m、1 m 方块列、海平面 12 m；区域：中部平原坊市、北雪峰（天剑宗）、东古林（青木谷）、南湖泽（玄水阁）、西赤岩火山（离火殿）、西南黄土台地（厚土宗）。
  `get_height(x,z)`（与碰撞一致）、`get_ground_y`、`get_biome`、`is_water`、`is_lava`、`find_poi(id)`、`carve_crater(pos, r)`（本次会话持久）、`render_map_image(px)`。
- **TerrainStreamer**：32 m 区块，工作线程生成（`WorkerThreadPool` 一律 high_priority），主线程每帧预算；4 m 远景网格。碰撞为 HeightMapShape3D。
- **WorldMap**（静态）：`pois()` → `{id, name, type(sect/town/home/portal/landmark), pos, facing, yaw, region, sect_id?, realm_id?, markers}`；区块加载前即可用。
- **标记点**（Marker3D，组 `poi_marker`，meta `poi_id`/`sect_id`/`realm_id`）：宗门 `npc_master/npc_teacher/npc_steward/npc_senior/shop/mission_board/cultivation_room/sect_gate`；坊市 `npc_merchant_1..4/town_board/town_center`；洞府 `home_cushion/home_stash/home_furnace/home_field/home_spawn`；秘境 `realm_portal`。
- **VoxelDestructible**（组 `destructible`，层 1+7）：`apply_damage_at(point, radius, power)`；断开的部分整体坠落；碎屑为对象池 MultiMesh。
- **PropBuilder / BuildingBuilder / BuildingLayouts / DestructibleFactory**：植被、中式建筑、宗门布局与可破坏物。
- **DayNight**、**WaterPlane**：昼夜与水面；大地图 1 现实分钟 = 1 时辰。
- **OverworldGameplay**（src/gameplay）：`overworld._spawn_player()` 在已开局时创建它，负责玩家会话、NPC 按锚点生成/回收、标记点交互、地点加成、遭遇、地图参数（`UIManager.register_args_provider("map", ...)`）。

## 界面（src/ui）

- **UIManager**（每个游戏场景一个，组 `ui_manager`）：`open/close/toggle(name, args)`、`is_blocking()`、`confirm`、`ask_number`、`notify`；静态 `register_panel(name, factory)`、`register_args_provider(name, provider)`。
- 内置面板：inventory（可带 other 网格：仓库/容器）、character、cultivation、skills、map、pause、settings、dialogue、shop、craft、saves；宗门面板 `sect` 由 GameSession 注册（SectPanel）。
- 面板继承 **UIWindow**：覆盖 `_build()` 与 `refresh()`；主题由 **UITheme** 代码生成（样式框 **OrnateBox**：漆墨底、宣纸纤维、委角、祥云角、回纹带、墨痕模式、卷轴木轴）。
- 国风美术：**InkArt**（src/ui/ink_art.gd）提供纹理平铺、笔触/弧形笔触、印章、八卦、委角牌匾、回纹、竖排书法；纹理由 `tools/gen_ui_textures.py` 程序化生成到 `assets/textures/ui/`；控件 **InkSeal**（印章）、**BrushLine**（笔触线）。
- 字体：正文 XianKai（霞鹜文楷子集）；标题/横幅/HUD 数字用书法字体 XianShu（马善政子集），`UITheme.font_display()`，缺字回落 XianKai。
- 战斗 HUD（src/ui/hud/）由 GameSession 创建，`CombatHUD.bind(actor, camera)`：玉璧着色器（jade_ring.gdshader：朱砂笔触生命、青色灵液灵力）+ HUDCluster（八卦护体、状态印章、准星、命中/斩印）+ HUDCanvas（八卦锁定环与悬牌、角落信息、卷轴目标、提示）+ HUDSpellBar（符纸法诀栏、葫芦丹药）+ HUDRadar（罗盘）+ 渗墨暗角（ink_vignette.gdshader）。
- 伤害跳字 **DamageNumbers**（世界中的 Node3D，内部画布层 9，低于 HUD）：书法数字、暴击墨溅 + “暴”印、治疗 `show_heal(pos, amount)` 或 hit_landed `kind == "heal"`。
- 头顶名牌 **Nameplate**：`setup(combatant, height, subtitle)` / `refresh()`；书法名 + 境界小印，固定屏幕尺寸，按距离渐隐，被锁定时隐去。
- 截图：`tools/shots/hud_showcase.gd`（--variant=full|low|burn|calm，--dark）固定一个战斗瞬间检查 HUD；`ui_panels.gd`（--panel=sect|pause|saves|settings|confirm|number）。

## 物理层

| 层 | 名称 | 用途 |
|---|---|---|
| 1 | world | 地形、建筑、静态碰撞 |
| 2 | player | 玩家身体 |
| 3 | actors | NPC、妖兽身体 |
| 4 | projectiles | （弹道用射线查询，一般不需要实体） |
| 5 | debris | 破碎体素碎块 |
| 6 | interact | 可交互 Area3D（容器、NPC 对话、传送阵） |
| 7 | destructible | 可破坏体素物体（同时也属于 world 层以参与移动碰撞） |
| 8 | water | 水面 |

近战与弹道使用即时物理查询（`intersect_shape` / `intersect_ray`），不使用持久 Area3D 命中盒。可破坏物实现 `apply_damage_at(point: Vector3, radius: float, power: float)`；地形实现 `carve_crater(point, radius)`。

## 场景流程

`main_menu` → `character_creator`（`GS.new_game(creation)`）→ `overworld`（大地图，`GS.overworld_position` 记录位置）→ `secret_realm`（`GS.realm_request`）→ 撤离/死亡后回到 `overworld`。

## 测试与截图

- `tools/run_tests.sh <godot>`：运行 `tests/test_*.gd` 中的所有 `test_*` 方法；任何脚本错误都视为失败。
- `tools/shot.sh <godot> <shot> <out.png> [--size=WxH]`：在 xvfb 中渲染 `tools/shots/<shot>.gd` 并截图（默认 Forward+/Vulkan，`SHOT_GL=1` 用兼容渲染器）。

## 编码约定

- 静态类型 GDScript，制表符缩进；注释与界面文本使用中文。
- 系统层（src/systems、src/core）不依赖场景树，可被测试直接调用。
- 场景中的内容尽量用代码构建；`.tscn` 只放根节点 + 脚本，避免手写复杂场景文件。
- 新增数据字段先写进 docs/DATA.md。
- 发布导出时需在导出预设的“非资源文件过滤”中加入 `data/*.json`。
