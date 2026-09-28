#!/usr/bin/env python3
"""Subset LXGW WenKai into assets/fonts/XianKai-*.ttf.

Keeps ASCII, CJK punctuation, the full GB2312 hanzi set, and every character
that appears in data/ and src/ so generated names and UI text always render.

The OFL Reserved Font Name clause forbids a modified (subsetted) font from
using the original name, so the family is renamed to "XianKai".

Usage: python3 tools/subset_font.py <path/to/LXGWWenKai-Regular.ttf> [Medium.ttf]
"""
import os
import sys
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def gb2312_chars():
    chars = set()
    for hi in range(0xA1, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                chars.add(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return chars


def project_chars():
    chars = set()
    for sub in ("data", "src", "scenes"):
        for dirpath, _, files in os.walk(os.path.join(ROOT, sub)):
            for f in files:
                if f.endswith((".json", ".gd", ".tscn", ".tres", ".txt")):
                    with open(os.path.join(dirpath, f), encoding="utf-8") as fh:
                        chars.update(fh.read())
    return chars


def build(src, dst, style):
    chars = set(chr(c) for c in range(0x20, 0x7F))
    chars |= set("·、。，：；！？“”‘’（）《》【】〔〕…—～￥×÷±°℃①②③④⑤⑥⑦⑧⑨⑩→←↑↓★☆●○◆◇■□▲△")
    chars |= gb2312_chars()
    chars |= project_chars()
    chars = {c for c in chars if c.isprintable() or c == " "}
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    opts.hinting = False
    font = TTFont(src)
    sub = subset.Subsetter(opts)
    sub.populate(text="".join(sorted(chars)))
    sub.subset(font)
    name = font["name"]
    family = "XianKai"
    for rec in name.names:
        if rec.nameID in (1, 16):
            rec.string = family
        elif rec.nameID == 4:
            rec.string = f"{family} {style}"
        elif rec.nameID == 6:
            rec.string = f"{family}-{style}"
        elif rec.nameID in (2, 17):
            rec.string = style
        elif rec.nameID == 3:
            rec.string = f"{family}-{style};subset"
    font.save(dst)
    print(f"{dst}: {len(chars)} chars, {os.path.getsize(dst) // 1024} KiB")


if __name__ == "__main__":
    out = os.path.join(ROOT, "assets", "fonts")
    os.makedirs(out, exist_ok=True)
    build(sys.argv[1], os.path.join(out, "XianKai-Regular.ttf"), "Regular")
    if len(sys.argv) > 2:
        build(sys.argv[2], os.path.join(out, "XianKai-Medium.ttf"), "Medium")
