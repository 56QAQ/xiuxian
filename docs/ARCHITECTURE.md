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
  actors/              角色：HumanoidActor（玩家与修士共用）、PlayerController、AI
  realm/               秘境：生成、容器、撤离
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
| `Audio` | audio.gd | `Audio.play(name)`、`Audio.play_at(name, pos)`；文件 `assets/audio/sfx/<name>.wav` |
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
- **CharacterBuilder.build(appearance, equip_visual) -> CharacterRig**：外貌字段见 DATA.md。VOXEL = 0.025m，身高约 1.75m。
- **WeaponBuilder.build(visual) -> Node3D**：meta `tip_length`。

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
