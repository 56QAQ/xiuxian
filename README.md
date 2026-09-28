# 问道长生

修仙开放世界 RPG（Godot 4）。体素画风、AC4 式高速斗法、五行灵根构筑、秘境搜打撤、门派与 NPC 羁绊。

- 设计文档：[docs/GDD.md](docs/GDD.md)
- 技术架构：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 数据格式：[docs/DATA.md](docs/DATA.md)

## 运行

1. 安装 [Godot 4.4 或更新版本](https://godotengine.org/download)（标准版，非 .NET）。
2. 用 Godot 打开本目录下的 `project.godot`，按 F5 运行。

## 开发

```bash
tools/run_tests.sh /path/to/godot           # 无头测试
tools/shot.sh /path/to/godot characters out.png --size=1600x900   # 截图（需要 xvfb）
python3 tools/subset_font.py LXGWWenKai-Regular.ttf LXGWWenKai-Medium.ttf  # 更新字体子集
```

## 许可

字体 XianKai 为霞鹜文楷（LXGW WenKai）的子集，遵循 SIL OFL 1.1，见 `assets/fonts/`。
