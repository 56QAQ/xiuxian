# 问道长生

修仙开放世界 RPG（Godot 4）。体素画风、AC4 式高速斗法、五行灵根构筑、秘境搜打撤、门派与 NPC 羁绊。

- 设计文档：[docs/GDD.md](docs/GDD.md)
- 技术架构：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 数据格式：[docs/DATA.md](docs/DATA.md)
- 版本规划：[docs/ROADMAP.md](docs/ROADMAP.md)

## 运行

1. 安装 [Godot 4.4 或更新版本](https://godotengine.org/download)（标准版，非 .NET；已在 4.4.1 与 4.7.2 上验证）。
2. 用 Godot 打开本目录下的 `project.godot`，按 F5 运行。
3. 想直接试手感：在编辑器中打开并运行 `scenes/dev_arena.tscn`（试炼场，三名血煞宗弟子）。

## 操作

| 操作 | 键位 | 操作 | 键位 |
|---|---|---|---|
| 移动 | WASD | 近战普攻（锁定时突进） | 鼠标左键 |
| 跳跃 / 按住上升 | Space | 灵气弹（按住蓄力） | 鼠标右键 |
| 下降 | Ctrl | 法诀 | 1 ~ 5 |
| 疾行 | Shift（按住） | 锁定 / 切换目标 | 鼠标中键 / Tab |
| 瞬步 | E / 鼠标侧键 | 服用丹药 | Q |
| 交互 | F | 金丹爆发（金丹期） | G |
| 打坐 | T | 背包 / 角色 / 功法 / 宗门 / 地图 | B / C / K / J / M |

筑基后可在空中双击 Space 切换“御空”悬停。

## 一局游戏

1. **捏人**：外貌、灵根（消耗天赋点）、先天属性与天赋、出身。
2. **洞府**：在蒲团处打坐或闭关提升修为；仓库存放物品；丹炉与器台用于生产。
3. **拜入宗门**：前往五宗山门拜见掌门（需要对应灵根），在任务堂接任务、在藏经阁学功法法诀。
4. **闯荡**：路上会遇到切磋的同道、拦路的劫修、出世的天材地宝、遇险的修士。可以结交、赠礼、拜师、结为道侣，也可以袭杀夺宝。
5. **秘境**：从秘境入口进入，搜刮容器、击杀妖兽与其他寻宝者，在秘境崩塌前到撤离阵撤离。死亡会失去储物袋中的所有物品（本命空间 2×2 除外）。
6. **突破**：修为圆满后在修炼界面冲击大境界，每次大境界都有质变（御空、第五法诀槽与金丹爆发、元婴护主……）。

## 开发

```bash
tools/run_tests.sh /path/to/godot           # 无头测试（任何脚本错误都视为失败）
tools/shot.sh /path/to/godot combat out.png --size=1600x900   # 截图（需要 xvfb；镜头脚本见 tools/shots/）
python3 tools/gen_sfx.py && python3 tools/gen_music.py        # 重新生成音效与音乐
python3 tools/subset_font.py LXGWWenKai-Regular.ttf LXGWWenKai-Medium.ttf  # 更新字体子集
```

导出发布版时，请在导出预设的“非资源文件过滤”中加入 `data/*.json`。

## 许可

字体 XianKai 为霞鹜文楷（LXGW WenKai）的子集，遵循 SIL OFL 1.1，见 `assets/fonts/`。
音效与音乐由 `tools/` 下的脚本程序化生成。
