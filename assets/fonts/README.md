# Fonts

## XianKai（正文）

`XianKai-Regular.ttf` / `XianKai-Medium.ttf` are subsets of **LXGW WenKai (霞鹜文楷)** v1.522
by LXGW, licensed under the SIL Open Font License 1.1 (see `OFL.txt`).

They are Modified Versions under the OFL (subset to ASCII + GB2312 + every character used in
`data/` and `src/`), so per the Reserved Font Name clause they are renamed to "XianKai".
Regenerate with `python3 tools/subset_font.py LXGWWenKai-Regular.ttf LXGWWenKai-Medium.ttf`
after adding text that uses characters outside GB2312.

## XianShu（书法：标题 / 横幅 / HUD 数字）

`XianShu-Regular.ttf` is a subset of **Ma Shan Zheng (马善政毛笔楷书)** v2.003 by the
Ma Shan Zheng Project Authors (https://github.com/googlefonts/mashanzheng), licensed under the
SIL Open Font License 1.1 (see `OFL-XianShu.txt`).

It is a Modified Version under the OFL (subset to ASCII + the GB2312 hanzi the font covers +
every character used in `data/`, `src/`, `scenes/` and `tools/shots/`). The upstream copyright
notice lists no Reserved Font Name; the family is renamed to "XianShu" regardless, so the subset
satisfies the RFN clause either way and can never be confused with the original. Characters the font lacks fall back to XianKai at runtime
(`UITheme.font_display()`).
Regenerate with `python3 tools/subset_font.py --display MaShanZheng-Regular.ttf`.
