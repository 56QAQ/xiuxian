# Fonts

`XianKai-Regular.ttf` / `XianKai-Medium.ttf` are subsets of **LXGW WenKai (霞鹜文楷)** v1.522
by LXGW, licensed under the SIL Open Font License 1.1 (see `OFL.txt`).

They are Modified Versions under the OFL (subset to ASCII + GB2312 + every character used in
`data/` and `src/`), so per the Reserved Font Name clause they are renamed to "XianKai".
Regenerate with `python3 tools/subset_font.py LXGWWenKai-Regular.ttf LXGWWenKai-Medium.ttf`
after adding text that uses characters outside GB2312.
