#!/usr/bin/env python3
"""问道长生 · 方块世界材质生成器（numpy + Pillow）。

程序化绘制 32×32 像素画方块材质（1 米方块 = 32 像素），输出为 Godot 的 Texture2DArray 竖条图集：
  assets/textures/world/blocks_albedo.png   RGB 反照率（sRGB），A = 发光/夜窗遮罩
  assets/textures/world/blocks_detail.png   R,G = 法线 xy（0.5 为平），B = 粗糙度，A = 凹缝遮蔽（1 = 敞开）
以及对应的 .import 文件（2d_array_texture，无损，生成 mipmap），
并生成 src/world/block_ids.gd（层编号常量、每层标志与线性均值色）。

着色约定（见 assets/shaders/block.gdshader）：网格顶点色给出“均值反照率”，
着色器乘以材质的细节比值 tex / 均值，因此同一张材质可被宗门配色、生物群系色调任意着色；
chroma（保色）控制保留材质自身色相起伏的程度（0 = 只保留明暗）。

用法：python3 tools/gen_world_textures.py [--preview 输出.png]
"""
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

S = 32
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "textures", "world")
GD_OUT = os.path.join(ROOT, "src", "world", "block_ids.gd")

# 每层标志位（与 block.gdshader 一致）
F_SNOW = 1          # 顶面可积雪
F_WET = 2           # 近水可湿润
F_WIND_LEAF = 4     # 叶片微摆
F_WIND_GRASS = 8    # 草丛随高度摇摆
F_EMIT_MASK = 16    # A 通道为发光遮罩（配合顶点 alpha 发光）
F_LAVA = 32         # 熔岩流动（恒定发光）
F_METAL = 64        # 金属
F_NIGHT_GLOW = 128  # 夜间窗纸透光（A 通道遮罩）
F_GLOSSY = 256      # 釉面/冰：更高光
F_CRYSTAL = 512     # 晶体闪烁
F_FOLIAGE = 1024    # 叶片透光
F_TERRAIN = 2048    # 自然地表（宏观色斑）

NATURAL = F_SNOW | F_WET | F_TERRAIN

YY, XX = np.mgrid[0:S, 0:S].astype(np.float64)
_B4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 - 15.0 / 32.0
BAYER = np.tile(_B4, (S // 4, S // 4))

LAYERS = []


def reg(name, variants=1, rot=2, flags=0, chroma=1.0):
	"""注册一个材质层。rot：0 不变换，1 只左右翻转，2 任意 90° 旋转 + 翻转。"""
	def deco(fn):
		LAYERS.append(dict(name=name, variants=variants, rot=rot, flags=flags, chroma=chroma, fn=fn))
		return fn
	return deco


# ================================================================ 工具

def pal(*hs):
	return np.array([[int(h[i:i + 2], 16) / 255.0 for i in (1, 3, 5)] for h in hs])


def vnoise(rng, cx, cy=None):
	"""可平铺值噪声（cx × cy 格）。"""
	if cy is None:
		cy = cx
	g = rng.random((cy, cx))
	tx = np.arange(S) * cx / S
	ty = np.arange(S) * cy / S
	x0 = np.floor(tx).astype(int) % cx
	y0 = np.floor(ty).astype(int) % cy
	x1 = (x0 + 1) % cx
	y1 = (y0 + 1) % cy
	fx = tx - np.floor(tx)
	fy = ty - np.floor(ty)
	fx = (fx * fx * (3 - 2 * fx))[None, :]
	fy = (fy * fy * (3 - 2 * fy))[:, None]
	a = g[np.ix_(y0, x0)]
	b = g[np.ix_(y0, x1)]
	c = g[np.ix_(y1, x0)]
	d = g[np.ix_(y1, x1)]
	return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(rng, cx=4, octaves=3, gain=0.55, cy=None):
	if cy is None:
		cy = cx
	out = np.zeros((S, S))
	amp = 1.0
	tot = 0.0
	for o in range(octaves):
		out += vnoise(rng, cx * 2 ** o, cy * 2 ** o) * amp
		tot += amp
		amp *= gain
	return norm01(out / tot)


def norm01(a):
	lo = a.min()
	hi = a.max()
	return (a - lo) / (hi - lo + 1e-9)


def voronoi(rng, n=None, sx=1.0, sy=1.0, pts=None):
	"""可平铺 Voronoi：返回 F1、F2、所属点编号、点坐标。"""
	if pts is None:
		pts = rng.random((n, 2)) * S
	dx = np.abs(XX[..., None] + 0.5 - pts[None, None, :, 0])
	dx = np.minimum(dx, S - dx)
	dy = np.abs(YY[..., None] + 0.5 - pts[None, None, :, 1])
	dy = np.minimum(dy, S - dy)
	d = np.sqrt((dx * sx) ** 2 + (dy * sy) ** 2)
	order = np.argsort(d, axis=2)
	f1 = np.take_along_axis(d, order[..., 0:1], 2)[..., 0]
	f2 = np.take_along_axis(d, order[..., 1:2], 2)[..., 0]
	return f1, f2, order[..., 0], pts


def jitter_grid(rng, nx, ny, amt=0.7, stagger=False):
	pts = []
	for j in range(ny):
		for i in range(nx):
			ox = 0.5 if (stagger and j % 2) else 0.0
			pts.append([(i + ox + 0.5 + (rng.random() - 0.5) * amt) * S / nx, (j + 0.5 + (rng.random() - 0.5) * amt) * S / ny])
	return np.array(pts) % S


def light(h, k=3.0, L=(-0.55, -0.6, 0.58)):
	"""由高度场求左上方来光的相对明暗（平面 = 1）。"""
	gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
	gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
	n = np.stack([-gx * k, -gy * k, np.ones_like(h)], -1)
	n /= np.linalg.norm(n, axis=-1, keepdims=True)
	lv = np.array(L) / np.linalg.norm(L)
	return np.clip((n * lv).sum(-1), 0.0, 1.0) / lv[2]


def ramp(v, colors, dither=0.55):
	n = len(colors)
	b = BAYER if v.shape == (S, S) else np.tile(_B4, (v.shape[0] // 4 + 1, v.shape[1] // 4 + 1))[:v.shape[0], :v.shape[1]]
	idx = np.clip(np.floor(np.clip(v, 0.0, 0.9999) * n + b * dither), 0, n - 1).astype(int)
	return colors[idx]


def tdist(x, y, cx, cy):
	dx = np.abs(x - cx)
	dx = np.minimum(dx, S - dx)
	dy = np.abs(y - cy)
	dy = np.minimum(dy, S - dy)
	return np.sqrt(dx * dx + dy * dy)


def speck(rng, count, shape=(S, S)):
	m = np.zeros(shape, bool)
	for _ in range(count):
		m[rng.integers(0, S), rng.integers(0, S)] = True
	return m


def mix(a, b, t):
	t = np.asarray(t)
	if t.ndim == 2:
		t = t[..., None]
	return a * (1 - t) + b * t


def result(rgb, h, rough=0.9, mask=None, cav=None, nstr=2.5):
	rgb = np.clip(rgb, 0.0, 1.0)
	h = np.clip(h, 0.0, 1.0)
	if np.isscalar(rough):
		rough = np.full((S, S), float(rough))
	if mask is None:
		mask = np.ones((S, S))
	if cav is None:
		# 凹缝遮蔽：低于邻域平均的像素更暗
		blur = (h + np.roll(h, 1, 0) + np.roll(h, -1, 0) + np.roll(h, 1, 1) + np.roll(h, -1, 1)) / 5.0
		cav = np.clip(1.0 - np.maximum(blur - h, 0.0) * 2.2 - (1.0 - h) * 0.18, 0.35, 1.0)
	return dict(rgb=rgb, h=h, rough=np.clip(rough, 0.02, 1.0), mask=np.clip(mask, 0.0, 1.0), cav=cav, nstr=nstr)


# ================================================================ 调色板（深 → 浅，冷暗暖亮）

P_GRASS = pal("#1f3a1c", "#284a22", "#325b27", "#3d6c2c", "#4a7e31", "#5a9037", "#6ea23f", "#86b44c")
P_DIRT = pal("#382519", "#462f20", "#553a28", "#634530", "#725239", "#835f43", "#946e50")
P_STONE = pal("#3c3f42", "#484c4f", "#55595b", "#636667", "#717473", "#7f8280", "#8f918d", "#a1a29c")
P_GRANITE = pal("#3d434d", "#4a505a", "#575e67", "#656b73", "#747a80", "#83888c", "#94989a", "#a6a9a9")
P_SAND = pal("#a88f62", "#b69d6d", "#c3a978", "#cdb483", "#d7bf8f", "#e0ca9c", "#e9d6ab", "#f1e2bc")
P_SNOW = pal("#a6b8cf", "#b8c8dc", "#c9d6e7", "#d7e2ef", "#e3ebf5", "#eef3f9", "#f8fbfd")
P_ICE = pal("#3d6f99", "#4d80aa", "#5f92bb", "#73a4c9", "#89b6d6", "#a1c8e2", "#bddaec", "#d9ecf6")
P_RED = pal("#4e1e15", "#5f261a", "#712f1f", "#843925", "#96442b", "#a85233", "#b8623d", "#c7764b")
P_BASALT = pal("#1a191e", "#222127", "#2a2930", "#333139", "#3d3a43", "#48444e", "#534f59")
P_OBSID = pal("#0b0910", "#120e19", "#1a1423", "#231a2e", "#2e223b", "#3c2d4c", "#533f66", "#7a6390")
P_LAVA = pal("#2a0a04", "#5a1505", "#8f2406", "#c63a09", "#ee5f12", "#ff8c25", "#ffb848", "#ffe38a")
P_LOESS = pal("#7d5a2c", "#8e6833", "#9e763b", "#ae8545", "#bd9451", "#caa25e", "#d6b06e", "#e0be80")
P_MUD = pal("#261e17", "#30261d", "#3b3024", "#473a2c", "#534434", "#5f4f3d", "#6c5b48")
P_ASH = pal("#262223", "#2e2a2a", "#373232", "#403a39", "#4a4341", "#554d4a", "#615854")
P_WOOD = pal("#3f2b1c", "#4c3422", "#5a3e29", "#684930", "#765438", "#855f41", "#946c4b")
P_BARK = pal("#22170f", "#2c1e14", "#37261a", "#422f20", "#4e3827", "#5a412e")
P_LEAF = pal("#10240f", "#173117", "#1f3f1d", "#284e24", "#325e2b", "#3e6f33", "#4c823c", "#5f9647")
P_PINE = pal("#0b1d16", "#10261c", "#163023", "#1c3b2a", "#234732", "#2b543b", "#356245")
P_MAPLE = pal("#4a0f0a", "#66160d", "#831d10", "#a02613", "#bb3517", "#d24c1c", "#e36b26", "#ef8f35")
P_BAMBOO_L = pal("#233f18", "#2e521f", "#3a6526", "#47782e", "#568b36", "#699e40", "#80b14e")
P_WILLOW = pal("#30491a", "#3b5a20", "#476b27", "#557d2f", "#658f38", "#77a142", "#8db34f")
P_BLOSSOM = pal("#7c3a50", "#9a4b65", "#b75f7c", "#cf7894", "#e093aa", "#eeb0c3", "#f7cbd8", "#fde6ee")
P_NEUTRAL = pal("#5a5a58", "#666664", "#727270", "#7e7e7b", "#8a8a87", "#969692", "#a2a29e")


# ================================================================ 自然地表

@reg("plain", rot=2, flags=0, chroma=0.0)
def t_plain(rng, v):
	n = fbm(rng, 4, 3)
	val = 0.5 + (n - 0.5) * 0.35 + (rng.random((S, S)) - 0.5) * 0.18
	return result(ramp(val, P_NEUTRAL, 0.4), 0.5 + (n - 0.5) * 0.2, 0.85)


def grass_field(rng, pal_, density=60, base_v=0.46, spread=0.3):
	"""草地：成簇的草丛（Voronoi 簇，簇间暗缝）+ 簇上亮叶尖，少量抖动。"""
	base = fbm(rng, 4, 2)
	f1, f2, idx, pts = voronoi(rng, 11)
	tone = rng.uniform(-0.12, 0.12, len(pts))
	edge = np.clip((f2 - f1) / 2.2, 0, 1)
	clump = np.clip(1.0 - f1 / 6.0, 0, 1)
	b = np.zeros((S, S))
	for _ in range(density):
		x = rng.integers(0, S)
		y = rng.integers(0, S)
		if edge[y, x] < 0.35:
			continue
		ln = rng.integers(2, 4)
		lean = rng.choice([-1, 0, 0, 1])
		for k in range(ln):
			b[(y - k) % S, (x + (lean if k == ln - 1 else 0)) % S] = 1.0 - k * 0.25
	val = base_v + spread * (base - 0.5) + tone[idx] + 0.14 * (clump - 0.5) + 0.2 * b - 0.22 * (1 - edge) ** 3
	val += (rng.random((S, S)) - 0.5) * 0.04
	h = np.clip(0.3 + 0.4 * clump + 0.3 * b - 0.3 * (1 - edge) ** 3, 0, 1)
	return ramp(val, pal_, 0.3), h, b


@reg("grass_top", variants=3, rot=2, flags=NATURAL)
def t_grass(rng, v):
	rgb, h, b = grass_field(rng, P_GRASS)
	# 少量三叶草斑
	for _ in range(2 + v):
		cx, cy = rng.random(2) * S
		m = tdist(XX, YY, cx, cy) < rng.uniform(1.2, 2.2)
		rgb[m] = mix(rgb[m], P_GRASS[3][None, :] * 0.9, 0.5)
	return result(rgb, h, 0.95)


def paint_dirt(rng, pebbles=6, pal_=P_DIRT):
	f1, f2, idx, pts = voronoi(rng, 16)
	tone = rng.uniform(0.3, 0.7, len(pts))
	clump = np.clip((f2 - f1) / 3.0, 0, 1)
	n = fbm(rng, 8, 2)
	h = clump * 0.55 + n * 0.45
	lt = light(h, 2.2)
	val = tone[idx] * 0.45 + n * 0.35 + (lt - 1.0) * 0.55 + 0.1
	rgb = ramp(val, pal_, 0.6)
	for _ in range(pebbles):
		cx, cy = rng.random(2) * S
		r = rng.uniform(0.8, 1.5)
		d = tdist(XX, YY, cx, cy)
		m = d < r
		pv = 0.45 + 0.4 * np.clip((cx - XX) * 0.3 + (cy - YY) * 0.3, -0.5, 0.5)
		rgb[m] = ramp(pv, P_STONE, 0.3)[m]
		h[m] = 0.9
	return rgb, h


@reg("dirt", variants=2, rot=2, flags=NATURAL)
def t_dirt(rng, v):
	rgb, h = paint_dirt(rng)
	return result(rgb, h, 0.95)


def fringe(rng, base_len=4, var=3, drip=0.25):
	"""每列的顶部覆盖长度（草边/雪檐）。"""
	n = vnoise(rng, 8, 1)[0]
	ln = np.round(base_len + (n - 0.5) * 2 * var).astype(int)
	for x in range(S):
		if rng.random() < drip:
			ln[x] += rng.integers(1, 3)
	return np.clip(ln, 1, S - 2)


@reg("grass_side", rot=1, flags=NATURAL)
def t_grass_side(rng, v):
	rgb, h = paint_dirt(rng, 5)
	g_rgb, g_h, _ = grass_field(rng, P_GRASS, 60, 0.52, 0.25)
	ln = fringe(rng, 5, 2, 0.3)
	for x in range(S):
		L = ln[x]
		for y in range(L):
			t = y / max(L, 1)
			rgb[y, x] = g_rgb[y, x] * (1.02 - 0.18 * t)
			h[y, x] = 0.85 - 0.2 * t
		# 草边下缘阴影
		rgb[L, x] = rgb[L, x] * 0.62
		rgb[(L + 1) % S, x] = rgb[(L + 1) % S, x] * 0.85
		h[L, x] = 0.3
	rgb[0, :] = rgb[0, :] * 1.08
	return result(rgb, h, 0.95)


@reg("stone", variants=2, rot=2, flags=NATURAL)
def t_stone(rng, v):
	f1, f2, idx, pts = voronoi(rng, 5, 1.0, 1.25)
	edge = f2 - f1
	n = fbm(rng, 4, 3)
	n2 = fbm(rng, 16, 1)
	tone = rng.uniform(0.42, 0.62, len(pts))
	h = np.clip(edge / 5.0, 0, 1) ** 0.6 * 0.65 + n * 0.35
	lt = light(h, 3.0)
	val = tone[idx] + (n - 0.5) * 0.3 + (n2 - 0.5) * 0.12 + (lt - 1.0) * 0.55
	crack = edge < 1.05
	val[crack] -= 0.34
	h[crack] = 0.0
	pits = speck(rng, 10)
	val[pits] -= 0.16
	rgb = ramp(val, P_STONE, 0.5)
	# 地衣
	lich = (fbm(rng, 8, 2) > 0.8) & ~crack
	rgb[lich] = mix(rgb[lich], np.array([0.55, 0.58, 0.35]), 0.35)
	return result(rgb, h, 0.88)


def paint_cobble(rng, nx=3, ny=3, pal_=P_STONE, gap=1.3):
	pts = jitter_grid(rng, nx, ny, 0.8, stagger=True)
	f1, f2, idx, _ = voronoi(rng, pts=pts)
	edge = f2 - f1
	tone = rng.uniform(0.38, 0.66, len(pts))
	n = fbm(rng, 8, 2)
	h = np.clip(edge / 4.5, 0, 1) ** 0.5
	mortar = edge < gap
	h[mortar] = 0.0
	lt = light(h, 4.0)
	val = tone[idx] + (lt - 1.0) * 0.75 + (n - 0.5) * 0.18
	val[mortar] = 0.06 + n[mortar] * 0.1
	return ramp(val, pal_, 0.45), h, mortar


@reg("cobble", variants=2, rot=2, flags=NATURAL)
def t_cobble(rng, v):
	rgb, h, mortar = paint_cobble(rng, 3, 3 + v)
	return result(rgb, h, 0.85)


@reg("mossy_stone", rot=2, flags=NATURAL)
def t_mossy(rng, v):
	rgb, h, mortar = paint_cobble(rng, 3, 3)
	mn = fbm(rng, 4, 3)
	moss = ((mn + h * 0.35) > 0.78) | (mortar & (mn > 0.45))
	mv = 0.35 + fbm(rng, 16, 1) * 0.45 + light(h, 2.0) * 0.1
	mrgb = ramp(mv, P_LEAF[2:], 0.6)
	rgb[moss] = mrgb[moss]
	h[moss] = np.maximum(h[moss], 0.55)
	return result(rgb, h, 0.9)


@reg("gravel", rot=2, flags=NATURAL)
def t_gravel(rng, v):
	f1, f2, idx, pts = voronoi(rng, 30)
	edge = f2 - f1
	h = np.clip(edge / 2.4, 0, 1) ** 0.6
	lt = light(h, 3.0)
	tone = rng.uniform(0.25, 0.8, len(pts))
	warm = rng.random(len(pts)) < 0.35
	val = tone[idx] + (lt - 1.0) * 0.6
	val[edge < 0.7] = 0.05
	g = ramp(val, P_STONE, 0.3)
	w = ramp(val, pal("#4e3e30", "#5e4b3a", "#6f5a47", "#806a55", "#917b65", "#a28c76"), 0.3)
	rgb = np.where(warm[idx][..., None], w, g)
	return result(rgb, h, 0.9)


@reg("sand", variants=2, rot=2, flags=NATURAL)
def t_sand(rng, v):
	n = fbm(rng, 4, 3)
	warp = fbm(rng, 2, 2)
	rip = np.sin((XX * 0.35 + YY * 0.8 + warp * 7.0) * (2 * np.pi / 8.0))
	# 周期修正：保证可平铺（沿对角的正弦周期为 S 的约数）
	rip = np.sin(2 * np.pi * (XX * 1 + YY * 4) / S + warp * 5.0)
	rip = np.sign(rip) * np.abs(rip) ** 0.6
	val = 0.5 + 0.2 * (n - 0.5) + 0.13 * rip + (rng.random((S, S)) - 0.5) * 0.08
	rgb = ramp(val, P_SAND, 0.7)
	dark = speck(rng, 14)
	lightp = speck(rng, 10)
	rgb[dark] *= 0.8
	rgb[lightp] = np.minimum(rgb[lightp] * 1.12, 1.0)
	h = 0.5 + 0.2 * rip + 0.2 * (n - 0.5)
	return result(rgb, h, 0.92, nstr=1.2)


@reg("snow", variants=2, rot=2, flags=F_TERRAIN | F_SNOW)
def t_snow(rng, v):
	n = fbm(rng, 4, 3)
	f1, f2, idx, _ = voronoi(rng, 7)
	dimple = np.clip(f1 / 7.0, 0, 1)
	h = 0.6 - 0.35 * dimple + 0.25 * n
	lt = light(h, 2.5)
	val = 0.62 + 0.25 * (n - 0.5) + (lt - 1.0) * 0.5
	rgb = ramp(val, P_SNOW, 0.6)
	sp = speck(rng, 7)
	rgb[sp] = np.array([1.0, 1.0, 1.0])
	return result(rgb, h, 0.75, nstr=1.5)


def paint_packed_snow(rng):
	n = fbm(rng, 4, 2, cy=8)
	rows = vnoise(rng, 1, 8)
	val = 0.45 + 0.3 * (rows - 0.5) + 0.2 * (n - 0.5)
	h = 0.5 + 0.3 * (rows - 0.5)
	lines = (YY.astype(int) % 7 == 0) & (vnoise(rng, 8, 1) > 0.35)
	val[lines] -= 0.18
	return ramp(val, P_SNOW[:6], 0.5), h


@reg("packed_snow", rot=1, flags=F_TERRAIN | F_SNOW)
def t_packed_snow(rng, v):
	rgb, h = paint_packed_snow(rng)
	return result(rgb, h, 0.8)


@reg("snow_side", rot=1, flags=F_TERRAIN | F_SNOW)
def t_snow_side(rng, v):
	rgb, h = paint_packed_snow(rng)
	s_rgb = t_snow(rng, 0)["rgb"]
	ln = fringe(rng, 6, 2, 0.35)
	for x in range(S):
		L = ln[x]
		rgb[:L, x] = s_rgb[:L, x]
		h[:L, x] = 0.9
		rgb[L, x] = rgb[L, x] * 0.8 * np.array([0.92, 0.96, 1.05])
	return result(rgb, h, 0.8)


@reg("ice", rot=2, flags=F_TERRAIN | F_GLOSSY)
def t_ice(rng, v):
	n = fbm(rng, 2, 3)
	f1, f2, idx, pts = voronoi(rng, 4)
	edge = f2 - f1
	streak = np.sin(2 * np.pi * (XX + YY * 2) / S * 2 + n * 4) * 0.5 + 0.5
	val = 0.35 + 0.35 * n + 0.15 * streak
	crack = edge < 0.8
	val[crack] = 0.95
	rgb = ramp(val, P_ICE, 0.4)
	bub = speck(rng, 9)
	rgb[bub] = P_ICE[-1]
	h = 0.6 + 0.1 * n
	h[crack] = 0.2
	rough = 0.06 + 0.1 * (1 - n)
	return result(rgb, h, rough, nstr=1.0)


@reg("red_rock", rot=1, flags=NATURAL)
def t_red_rock(rng, v):
	n = fbm(rng, 4, 3)
	bands = vnoise(rng, 1, 6)
	warp = fbm(rng, 4, 2)
	yy = (YY + warp * 3.0) % S
	band_id = np.floor(yy / 5.3).astype(int)
	tone = rng.uniform(0.3, 0.75, 8)[band_id % 8]
	f1, f2, idx, _ = voronoi(rng, 9, 0.45, 1.6)
	edge = f2 - f1
	h = np.clip(edge / 3.0, 0, 1) ** 0.5 * 0.6 + n * 0.4
	lt = light(h, 2.6)
	val = tone * 0.6 + bands * 0.15 + (n - 0.5) * 0.25 + (lt - 1.0) * 0.55
	val[edge < 0.8] -= 0.3
	rgb = ramp(val, P_RED, 0.55)
	return result(rgb, h, 0.9)


@reg("basalt", rot=1, flags=NATURAL)
def t_basalt(rng, v):
	# 柱状节理：宽度不等的竖向石柱
	widths = []
	while sum(widths) < S:
		widths.append(int(rng.integers(5, 9)))
	widths[-1] -= sum(widths) - S
	if widths[-1] < 3:
		widths[-2] += widths[-1]
		widths.pop()
	val = np.zeros((S, S))
	h = np.zeros((S, S))
	x0 = 0
	n = fbm(rng, 8, 2)
	for w in widths:
		t = rng.uniform(0.35, 0.7)
		for i in range(w):
			x = x0 + i
			c = 1.0 - abs((i + 0.5) / w - 0.4) * 1.6
			val[:, x] = t + c * 0.18
			h[:, x] = 0.4 + c * 0.5
		val[:, x0] = 0.08
		h[:, x0] = 0.0
		# 横向节理
		jy = int(rng.integers(0, S))
		val[jy, x0:x0 + w] = 0.12
		h[jy, x0:x0 + w] = 0.1
		x0 += w
	val += (n - 0.5) * 0.2
	rgb = ramp(val, P_BASALT, 0.45)
	return result(rgb, h, 0.8)


@reg("obsidian", rot=2, flags=F_TERRAIN | F_GLOSSY)
def t_obsidian(rng, v):
	f1, f2, idx, pts = voronoi(rng, 7)
	edge = f2 - f1
	tone = rng.uniform(0.15, 0.55, len(pts))
	n = fbm(rng, 4, 2)
	val = tone[idx] + (n - 0.5) * 0.2
	rim = (edge < 1.2) & (rng.random(len(pts))[idx] > 0.4)
	val[rim] = 0.85
	glint = speck(rng, 5)
	val[glint] = 1.0
	rgb = ramp(val, P_OBSID, 0.3)
	h = np.clip(edge / 4.0, 0, 1)
	return result(rgb, h, 0.12 + 0.2 * n, nstr=1.8)


@reg("lava", rot=2, flags=F_LAVA | F_EMIT_MASK)
def t_lava(rng, v):
	# 熔岩：大块暗色结壳漂在明亮的熔流上，壳内偶有发光裂纹
	pts = jitter_grid(rng, 2, 2, 0.6)
	f1, f2, idx, _ = voronoi(rng, pts=pts)
	edge = f2 - f1
	n = fbm(rng, 4, 3)
	n2 = fbm(rng, 8, 2)
	river = 1.0 - smoothstep_np(2.2, 5.0, edge + (n - 0.5) * 3.0)
	crust = river < 0.45
	# 熔流：越靠近河心越亮
	hot = np.clip(river * 1.1 + (n2 - 0.5) * 0.3, 0, 1)
	rgb = ramp(0.35 + hot * 0.65, P_LAVA, 0.35)
	# 结壳：玄武岩色，左上受光，边缘被熔流烧红
	ch = np.clip((edge - 2.0) / 5.0, 0, 1)
	lt = light(ch * 0.8 + n2 * 0.2, 3.0)
	cv = 0.3 + (n2 - 0.5) * 0.35 + (lt - 1.0) * 0.4
	crgb = ramp(cv, P_BASALT, 0.4) * np.array([1.2, 0.95, 0.85])
	rim = crust & (river > 0.25)
	crgb[rim] = mix(crgb[rim], P_LAVA[3], 0.5)
	cf1, cf2, _, _ = voronoi(rng, 10)
	cracks = crust & ((cf2 - cf1) < 0.5) & (ch > 0.15)
	crgb[cracks] = P_LAVA[4]
	rgb[crust] = crgb[crust]
	mask = np.where(crust, np.where(cracks, 0.8, np.where(rim, 0.35, 0.05)), 0.4 + 0.6 * hot)
	h = np.where(crust, 0.6 + ch * 0.4, 0.2)
	return result(rgb, h, np.where(crust, 0.85, 0.3), mask=mask)


def smoothstep_np(a, b, x):
	t = np.clip((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3 - 2 * t)


@reg("loess", rot=1, flags=NATURAL)
def t_loess(rng, v):
	n = fbm(rng, 4, 3)
	layers = vnoise(rng, 1, 10)
	val = 0.5 + 0.28 * (layers - 0.5) + 0.2 * (n - 0.5)
	# 竖向节理
	h = 0.55 + 0.25 * (layers - 0.5)
	x = int(rng.integers(0, S))
	for _ in range(3):
		x = (x + int(rng.integers(8, 13))) % S
		y0 = int(rng.integers(0, S))
		ln = int(rng.integers(10, 26))
		cx = x
		for k in range(ln):
			y = (y0 + k) % S
			if rng.random() < 0.2:
				cx = (cx + rng.choice([-1, 1])) % S
			val[y, cx] -= 0.3
			val[y, (cx + 1) % S] += 0.08
			h[y, cx] = 0.1
	lt = light(h, 2.0)
	val += (lt - 1.0) * 0.4
	rgb = ramp(val, P_LOESS, 0.6)
	return result(rgb, h, 0.95)


@reg("clay_layers", rot=1, flags=NATURAL)
def t_clay(rng, v):
	n = fbm(rng, 4, 2)
	wave = np.sin(2 * np.pi * XX / S * 2 + n * 2.5) * 1.3
	yy = (YY + wave) % S
	cols = [pal("#8a3e25", "#9c4b2c", "#ad5a35"), pal("#b8894a", "#c89a56", "#d6ab64"), pal("#d9c29a", "#e4cfa8", "#eddbb7"),
		pal("#9a5a34", "#ab6a3d", "#bb7a48")]
	edges = [0, 5, 9, 13, 18, 21, 26, 29, 32]
	rgb = np.zeros((S, S, 3))
	h = np.zeros((S, S))
	for i in range(len(edges) - 1):
		m = (yy >= edges[i]) & (yy < edges[i + 1])
		c = cols[i % 4]
		loc = (yy - edges[i]) / (edges[i + 1] - edges[i])
		vv = 0.75 - loc * 0.5 + (n - 0.5) * 0.4
		rgb[m] = ramp(vv, c, 0.6)[m]
		h[m] = (0.7 - loc * 0.4)[m]
	return result(rgb, h, 0.95)


@reg("rammed_earth", rot=1, flags=F_WET | F_SNOW)
def t_rammed(rng, v):
	n = fbm(rng, 8, 2)
	per = 8
	loc = (YY % per) / per
	lay = np.floor(YY / per).astype(int)
	tone = rng.uniform(0.4, 0.6, S // per + 1)[lay]
	val = tone + 0.22 * (0.5 - loc) + 0.18 * (n - 0.5)
	seam = (YY % per) == per - 1
	val[seam] -= 0.25
	rgb = ramp(val, P_LOESS, 0.6)
	peb = speck(rng, 16)
	rgb[peb] = rgb[peb] * 0.72
	h = 0.7 - loc * 0.4
	h[seam] = 0.1
	return result(rgb, h, 0.95)


@reg("mud", rot=2, flags=NATURAL)
def t_mud(rng, v):
	n = fbm(rng, 4, 3)
	n2 = fbm(rng, 2, 2)
	pud = n2 > 0.66
	val = 0.45 + 0.35 * (n - 0.5)
	val[pud] += 0.18
	rgb = ramp(val, P_MUD, 0.6)
	h = 0.5 + 0.25 * n
	h[pud] = 0.3
	rough = np.where(pud, 0.25, 0.8)
	return result(rgb, h, rough, nstr=1.3)


@reg("farmland", rot=1, flags=F_WET | F_SNOW)
def t_farmland(rng, v):
	n = fbm(rng, 8, 2)
	loc = (YY % 8) / 8.0
	ridge = np.sin(loc * np.pi)
	h = ridge * 0.7 + n * 0.3
	lt = light(h, 3.0)
	val = 0.25 + ridge * 0.35 + (n - 0.5) * 0.3 + (lt - 1.0) * 0.4
	rgb = ramp(val, pal("#1e150e", "#291c13", "#352519", "#412e1f", "#4d3826", "#5a422e", "#684d37"), 0.6)
	sprout = speck(rng, 10) & (ridge > 0.7)
	rgb[sprout] = np.array([0.36, 0.55, 0.24])
	return result(rgb, h, 0.9)


@reg("dry_grass", variants=2, rot=2, flags=NATURAL)
def t_dry_grass(rng, v):
	p = pal("#4b4322", "#5b5129", "#6c6130", "#7e7138", "#908140", "#a3924b", "#b5a358", "#c6b468")
	rgb, h, b = grass_field(rng, p, 70, 0.5, 0.3)
	bare = (fbm(rng, 4, 2) > 0.72) & (b == 0)
	drgb, _ = paint_dirt(rng, 2, P_LOESS)
	rgb[bare] = drgb[bare] * 0.95
	return result(rgb, h, 0.95)


@reg("forest_floor", rot=2, flags=NATURAL)
def t_forest_floor(rng, v):
	rgb, h, b = grass_field(rng, P_GRASS, 70, 0.36, 0.3)
	cols = [np.array([0.55, 0.30, 0.12]), np.array([0.62, 0.45, 0.16]), np.array([0.40, 0.24, 0.12]), np.array([0.30, 0.34, 0.14])]
	for _ in range(16):
		cx, cy = rng.integers(0, S, 2)
		c = cols[rng.integers(0, len(cols))]
		for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
			if rng.random() < 0.85:
				rgb[(cy + dy) % S, (cx + dx) % S] = c * (0.85 + 0.3 * (dx == 0 and dy == 0))
				h[(cy + dy) % S, (cx + dx) % S] = 0.8
	for _ in range(3):
		x, y = rng.integers(0, S, 2)
		dx = rng.choice([-1, 1])
		for k in range(rng.integers(4, 7)):
			rgb[(y + k // 2) % S, (x + k * dx) % S] = np.array([0.30, 0.20, 0.12])
	return result(rgb, h, 0.95)


@reg("ash", rot=2, flags=NATURAL)
def t_ash(rng, v):
	n = fbm(rng, 4, 3)
	f1, f2, idx, pts = voronoi(rng, 6)
	crack = (f2 - f1) < 0.7
	val = 0.5 + 0.35 * (n - 0.5) + (rng.random((S, S)) - 0.5) * 0.18
	val[crack] -= 0.2
	rgb = ramp(val, P_ASH, 0.6)
	emb = speck(rng, 6)
	rgb[emb] = np.array([0.75, 0.25, 0.08])
	h = 0.5 + 0.3 * n
	h[crack] = 0.2
	return result(rgb, h, 0.95)


@reg("granite", variants=2, rot=2, flags=NATURAL)
def t_granite(rng, v):
	f1, f2, idx, pts = voronoi(rng, 4, 1.0, 1.4)
	edge = f2 - f1
	n = fbm(rng, 4, 3)
	tone = rng.uniform(0.42, 0.6, len(pts))
	h = np.clip(edge / 5.0, 0, 1) ** 0.6 * 0.6 + n * 0.4
	lt = light(h, 2.8)
	val = tone[idx] + (n - 0.5) * 0.28 + (lt - 1.0) * 0.5 + (rng.random((S, S)) - 0.5) * 0.16
	val[edge < 1.0] -= 0.32
	rgb = ramp(val, P_GRANITE, 0.5)
	dk = speck(rng, 18)
	lk = speck(rng, 14)
	pk = speck(rng, 6)
	rgb[dk] *= 0.6
	rgb[lk] = np.minimum(rgb[lk] * 1.25, 1.0)
	rgb[pk] = mix(rgb[pk], np.array([0.72, 0.58, 0.55]), 0.6)
	return result(rgb, h, 0.85)


@reg("path", rot=2, flags=NATURAL)
def t_path(rng, v):
	n = fbm(rng, 4, 3)
	val = 0.5 + 0.28 * (n - 0.5) + (rng.random((S, S)) - 0.5) * 0.1
	p = pal("#5a4632", "#68523b", "#765e44", "#846a4e", "#927759", "#a08464", "#ad9170")
	rgb = ramp(val, p, 0.6)
	h = 0.5 + 0.2 * n
	for _ in range(9):
		cx, cy = rng.random(2) * S
		r = rng.uniform(0.9, 1.8)
		d = tdist(XX, YY, cx, cy)
		m = d < r
		lv = 0.55 + np.clip(((cx - XX) + (cy - YY)) * 0.25, -0.35, 0.35)
		rgb[m] = ramp(lv, P_STONE, 0.3)[m]
		h[m] = 0.85
		sh = (tdist(XX - 1, YY - 1, cx, cy) < r) & ~m
		rgb[sh] *= 0.8
	return result(rgb, h, 0.92)


@reg("black_sand", rot=2, flags=NATURAL)
def t_black_sand(rng, v):
	n = fbm(rng, 4, 3)
	val = 0.5 + 0.3 * (n - 0.5) + (rng.random((S, S)) - 0.5) * 0.22
	rgb = ramp(val, P_BASALT, 0.7)
	gl = speck(rng, 12)
	rgb[gl] = np.array([0.55, 0.52, 0.6])
	return result(rgb, 0.5 + 0.2 * n, 0.8, nstr=1.2)


@reg("moss", rot=2, flags=NATURAL | F_FOLIAGE)
def t_moss(rng, v):
	n = fbm(rng, 8, 2)
	f1, f2, idx, pts = voronoi(rng, 40)
	h = np.clip(1 - f1 / 3.0, 0, 1) * 0.7 + n * 0.3
	lt = light(h, 3.0)
	val = 0.4 + (lt - 1.0) * 0.6 + (n - 0.5) * 0.3
	rgb = ramp(val, P_LEAF[1:], 0.5)
	return result(rgb, h, 0.95)


# ================================================================ 木与植物

@reg("planks", rot=1, flags=F_WET | F_SNOW, chroma=0.6)
def t_planks(rng, v):
	rgb = np.zeros((S, S, 3))
	h = np.zeros((S, S))
	grain = fbm(rng, 2, 3, cy=16)
	for b in range(4):
		y0 = b * 8
		tone = rng.uniform(0.35, 0.65)
		jx = int(rng.integers(0, S))
		sl = slice(y0, y0 + 8)
		loc = (YY[sl] - y0) / 8.0
		val = tone + (grain[sl] - 0.5) * 0.45 + 0.1 * (0.5 - np.abs(loc - 0.45))
		val[0, :] -= 0.28
		val[-1, :] -= 0.12
		val[:, jx] -= 0.35
		val[:, (jx + 1) % S] += 0.08
		for ny in (2, 5):
			for nx in ((jx + 2) % S, (jx - 2) % S):
				val[ny, nx] -= 0.3
		# 节疤
		if rng.random() < 0.5:
			kx = int(rng.integers(0, S))
			ky = int(rng.integers(2, 6))
			d = tdist(XX[sl], YY[sl] - y0, kx, ky)
			val -= np.where(d < 1.5, 0.25, np.where(d < 2.5, -0.06, 0.0))
		rgb[sl] = ramp(val, P_WOOD, 0.5)
		hh = 0.75 - np.abs(loc - 0.5) * 0.3
		hh[0, :] = 0.05
		hh[:, jx] = 0.2
		h[sl] = hh
	return result(rgb, h, 0.75)


@reg("log_bark", rot=1, flags=F_SNOW | F_WET)
def t_bark(rng, v):
	n = fbm(rng, 6, 3, cy=1)
	n2 = fbm(rng, 4, 2, cy=4)
	ridge = np.abs(np.sin(np.pi * (XX / S * 6 + n * 1.5)))
	h = ridge * 0.7 + n2 * 0.3
	lt = light(h, 3.5)
	val = 0.2 + ridge * 0.5 + (lt - 1.0) * 0.6 + (n2 - 0.5) * 0.2
	rgb = ramp(val, P_BARK, 0.5)
	# 横向裂纹
	for _ in range(5):
		x = int(rng.integers(0, S))
		y = int(rng.integers(0, S))
		for k in range(int(rng.integers(2, 4))):
			rgb[y, (x + k) % S] *= 0.6
	return result(rgb, h, 0.95)


@reg("log_end", rot=2, flags=F_SNOW)
def t_log_end(rng, v):
	n = fbm(rng, 4, 2)
	r = tdist(XX + 0.5, YY + 0.5, 16, 16) + n * 2.5
	ring = np.sin(r * 2 * np.pi / 3.0) * 0.5 + 0.5
	val = 0.45 + ring * 0.3 - np.clip(r / 22, 0, 1) * 0.15
	p = pal("#6b4a2c", "#7a5634", "#89623d", "#987047", "#a67e52", "#b48c5f", "#c19a6d")
	rgb = ramp(val, p, 0.4)
	bark = r > 15.5
	rgb[bark] = ramp(0.4 + n * 0.5, P_BARK, 0.4)[bark]
	return result(rgb, 0.5 + ring * 0.2, 0.9)


def leaf_canvas(rng, colors, count, rx=(1.4, 2.4), ry=None, gap_v=0.08, elong=0.0, angle=None):
	"""叶团：密集的小椭圆（左上高光、右下阴影），间隙为深色。"""
	val = np.full((S, S), gap_v)
	h = np.zeros((S, S))
	for _ in range(count):
		cx, cy = rng.random(2) * S
		a = rng.uniform(*rx)
		b = a * (1.0 - elong) if ry is None else rng.uniform(*ry)
		ang = rng.uniform(0, np.pi) if angle is None else angle + rng.uniform(-0.3, 0.3)
		dx = XX + 0.5 - cx
		dy = YY + 0.5 - cy
		dx = (dx + S / 2) % S - S / 2
		dy = (dy + S / 2) % S - S / 2
		u = dx * np.cos(ang) + dy * np.sin(ang)
		w = -dx * np.sin(ang) + dy * np.cos(ang)
		d = (u / a) ** 2 + (w / max(b, 0.6)) ** 2
		m = d < 1.0
		shade = 0.62 - (dx + dy) / (a + b) * 0.22 - d * 0.18 + rng.uniform(-0.12, 0.12)
		val[m] = shade[m]
		h[m] = (1.0 - d[m]) * 0.6 + 0.4
	return ramp(val, colors, 0.35), h, val


@reg("leaf_broad", rot=2, flags=F_WIND_LEAF | F_FOLIAGE | F_SNOW)
def t_leaf_broad(rng, v):
	rgb, h, val = leaf_canvas(rng, P_LEAF, 150, (1.3, 2.3), elong=0.25)
	return result(rgb, h, 0.8, mask=(val > 0.1).astype(float))


@reg("leaf_pine", rot=2, flags=F_WIND_LEAF | F_FOLIAGE | F_SNOW)
def t_leaf_pine(rng, v):
	val = np.full((S, S), 0.06)
	h = np.zeros((S, S))
	for _ in range(95):
		x, y = rng.integers(0, S, 2)
		dx = rng.choice([-1, 1])
		ln = int(rng.integers(3, 6))
		base = rng.uniform(0.35, 0.8)
		for k in range(ln):
			px = (x + k * dx) % S
			py = (y + k // 2) % S
			val[py, px] = base - k * 0.07
			h[py, px] = 0.9 - k * 0.1
			if k == 0:
				val[(py + 1) % S, px] = base * 0.55
	rgb = ramp(val, P_PINE, 0.35)
	return result(rgb, h, 0.85)


@reg("leaf_maple", rot=2, flags=F_WIND_LEAF | F_FOLIAGE | F_SNOW)
def t_leaf_maple(rng, v):
	rgb, h, val = leaf_canvas(rng, P_MAPLE, 130, (1.5, 2.6), elong=0.1)
	# 点缀金黄叶
	gold = speck(rng, 26) & (val > 0.4)
	rgb[gold] = mix(rgb[gold], np.array([0.95, 0.72, 0.25]), 0.55)
	return result(rgb, h, 0.8)


@reg("leaf_bamboo", rot=1, flags=F_WIND_LEAF | F_FOLIAGE | F_SNOW)
def t_leaf_bamboo(rng, v):
	rgb, h, val = leaf_canvas(rng, P_BAMBOO_L, 70, (3.2, 4.6), ry=(0.7, 1.1), angle=0.55)
	return result(rgb, h, 0.75)


@reg("leaf_willow", rot=1, flags=F_WIND_LEAF | F_FOLIAGE)
def t_leaf_willow(rng, v):
	val = np.full((S, S), 0.1)
	h = np.zeros((S, S))
	for x in range(S):
		for _ in range(2):
			if rng.random() < 0.8:
				y0 = int(rng.integers(0, S))
				ln = int(rng.integers(6, 14))
				base = rng.uniform(0.4, 0.85)
				for k in range(ln):
					val[(y0 + k) % S, x] = base - 0.25 * k / ln + (0.12 if k % 3 == 0 else 0.0)
					h[(y0 + k) % S, x] = 0.8
	rgb = ramp(val, P_WILLOW, 0.4)
	return result(rgb, h, 0.8)


@reg("leaf_blossom", rot=2, flags=F_WIND_LEAF | F_FOLIAGE | F_SNOW)
def t_leaf_blossom(rng, v):
	rgb, h, val = leaf_canvas(rng, P_BLOSSOM, 110, (1.3, 2.2), gap_v=0.05, elong=0.0)
	# 花心与白色花瓣
	for _ in range(22):
		x, y = rng.integers(0, S, 2)
		rgb[y, x] = np.array([1.0, 0.96, 0.97])
		rgb[(y + 1) % S, x] = np.array([0.98, 0.85, 0.35]) if rng.random() < 0.5 else rgb[(y + 1) % S, x]
	leaf = speck(rng, 20) & (val < 0.2)
	rgb[leaf] = P_LEAF[4]
	return result(rgb, h, 0.8)


@reg("bamboo_stalk", rot=1, flags=F_SNOW)
def t_bamboo(rng, v):
	n = fbm(rng, 4, 2, cy=1)
	ph = (XX % 8) / 8.0
	val = 0.35 + 0.4 * np.sin(ph * np.pi) + (n - 0.5) * 0.2
	node = (YY % 16 == 0)
	val[node] = 0.95
	val[(YY % 16 == 1)] -= 0.2
	rgb = ramp(val, pal("#2f4a1c", "#3a5c22", "#476f29", "#558331", "#65973b", "#78aa47", "#8fbc58", "#aacb73"), 0.4)
	h = 0.4 + 0.5 * np.sin(ph * np.pi)
	h[node] = 1.0
	return result(rgb, h, 0.55)


# ================================================================ 建筑（近中性，由网格配色着色）

A_DARK = pal("#3a3d44", "#454952", "#51555e", "#5d626b", "#6a6f78", "#787d86", "#878c94", "#989ca3")
A_MID = pal("#6a6763", "#76736f", "#827f7a", "#8e8b86", "#9a9792", "#a6a39e", "#b2afaa", "#bebbb6")
A_LIGHT = pal("#a9a59e", "#b3afa8", "#bdb9b2", "#c6c3bc", "#cfccc5", "#d8d5cf", "#e1ded9", "#eae8e3")
A_WARM = pal("#6f625a", "#7b6d64", "#87796f", "#93857a", "#a09186", "#ac9d92", "#b8aa9f", "#c4b7ad")


def fish_scale(rng, row=8, width=8, radius=5.2):
	"""鱼鳞瓦：逐行叠压的半圆瓦片（下一行盖住上一行）。"""
	val = np.full((S, S), 0.1)
	h = np.zeros((S, S))
	for r in range(S // row + 1):
		yc = r * row - 1.0
		off = (width / 2) * (r % 2)
		tone_row = rng.uniform(-0.06, 0.06)
		for k in range(S // width + 1):
			xc = k * width + off + width / 2
			d = tdist(XX + 0.5, YY + 0.5, xc % S, yc % S)
			below = ((YY + 0.5 - yc) % S) < row + 1.5
			m = (d < radius) & below
			t = np.clip(d / radius, 0, 1)
			shade = 0.72 - t * 0.35 - ((XX + 0.5 - xc + S / 2) % S - S / 2) / radius * 0.1 + tone_row + rng.uniform(-0.05, 0.05)
			rim = m & (t > 0.82)
			val[m] = shade[m]
			val[rim] = 0.12
			h[m] = (1 - t[m]) * 0.8 + 0.2
			h[rim] = 0.1
	return val, h


@reg("roof_top", rot=1, flags=F_SNOW | F_WET, chroma=0.3)
def t_roof_top(rng, v):
	val, h = fish_scale(rng)
	val += (fbm(rng, 4, 2) - 0.5) * 0.1
	return result(ramp(val, A_DARK, 0.3), h, 0.6)


def tile_ends(rng, row=8):
	"""瓦当滴水：每 8 像素一行圆形瓦当，中间悬三角滴水。"""
	val = np.full((S, S), 0.12)
	h = np.zeros((S, S))
	for r in range(S // row):
		y0 = r * row
		for k in range(S // 8):
			xc = k * 8 + 4
			yc = y0 + 3.5
			d = np.sqrt((XX + 0.5 - xc) ** 2 + (YY + 0.5 - yc) ** 2)
			m = d < 3.2
			sh = 0.72 - ((XX + 0.5 - xc) + (YY + 0.5 - yc)) * 0.05
			val[m] = sh[m]
			val[m & (d > 2.4)] = 0.42
			val[m & (d < 1.0)] = 0.85
			h[m] = 0.9 - d[m] * 0.12
			# 滴水（两瓦当之间）
			xd = k * 8
			for yy in range(y0 + 1, y0 + 7):
				wdt = max(0, 3 - (yy - y0 - 1) // 2)
				for dx in range(-wdt + 1, wdt):
					if yy < S:
						val[yy, (xd + dx) % S] = 0.5 - (yy - y0) * 0.04
						h[yy, (xd + dx) % S] = 0.6
		val[y0, :] = np.minimum(val[y0, :], 0.2)
	return val, h


@reg("roof_side", rot=1, flags=F_SNOW | F_WET, chroma=0.3)
def t_roof_side(rng, v):
	val, h = tile_ends(rng)
	return result(ramp(val, A_DARK, 0.25), h, 0.6)


@reg("roof_under", rot=1, flags=0, chroma=0.4)
def t_roof_under(rng, v):
	# 檐下椽子：圆椽 + 望板
	grain = fbm(rng, 2, 2, cy=8)
	ph = (YY % 8) / 8.0
	raft = ph < 0.6
	val = np.where(raft, 0.45 + 0.35 * np.sin(ph / 0.6 * np.pi), 0.15 + grain * 0.1)
	val += (grain - 0.5) * 0.15
	h = np.where(raft, 0.3 + 0.7 * np.sin(ph / 0.6 * np.pi), 0.0)
	return result(ramp(val, A_WARM, 0.4), h, 0.8)


@reg("roof_ridge", rot=1, flags=F_SNOW, chroma=0.3)
def t_ridge(rng, v):
	n = fbm(rng, 4, 2)
	ph = (YY % 4) / 4.0
	val = 0.6 - ph * 0.3 + (n - 0.5) * 0.15
	val[(YY % 4) == 3] = 0.15
	# 竖向接缝
	for y in range(0, S, 4):
		x = int(rng.integers(0, S))
		val[y:y + 3, x] -= 0.2
	return result(ramp(val, A_DARK, 0.3), 0.8 - ph * 0.5, 0.6)


@reg("glazed_top", rot=1, flags=F_SNOW | F_GLOSSY, chroma=0.3)
def t_glazed_top(rng, v):
	val, h = fish_scale(rng)
	val = val * 0.9 + 0.1
	hl = (h > 0.75) & (h < 0.95)
	val[hl] += 0.2
	return result(ramp(val, A_MID, 0.3), h, np.where(h > 0.3, 0.22, 0.6))


@reg("glazed_side", rot=1, flags=F_SNOW | F_GLOSSY, chroma=0.3)
def t_glazed_side(rng, v):
	val, h = tile_ends(rng)
	val = val * 0.9 + 0.1
	return result(ramp(val, A_MID, 0.25), h, np.where(h > 0.3, 0.22, 0.6))


def lacquer(rng, vertical=True):
	g = fbm(rng, 16, 2, cy=2) if vertical else fbm(rng, 2, 2, cy=16)
	crack_f1, crack_f2, _, _ = voronoi(rng, 26, 1.0, 0.5 if vertical else 2.0)
	crack = (crack_f2 - crack_f1) < 0.45
	val = 0.55 + (g - 0.5) * 0.22 + (rng.random((S, S)) - 0.5) * 0.05
	val[crack] -= 0.07
	# 磨损高光
	wear = fbm(rng, 4, 2) > 0.8
	val[wear] += 0.1
	h = 0.6 + (g - 0.5) * 0.2
	return ramp(val, A_WARM, 0.35), h


@reg("lacquer_v", rot=1, flags=F_WET, chroma=0.2)
def t_lacquer_v(rng, v):
	rgb, h = lacquer(rng, True)
	return result(rgb, h, 0.38, nstr=1.0)


@reg("lacquer_h", rot=1, flags=F_WET | F_SNOW, chroma=0.2)
def t_lacquer_h(rng, v):
	rgb, h = lacquer(rng, False)
	return result(rgb, h, 0.4, nstr=1.0)


@reg("painted_beam", rot=1, flags=0, chroma=0.25)
def t_painted_beam(rng, v):
	# 旋子彩画（单色明暗版）：上下箍线 + 连续的旋花与菱形
	val = np.full((S, S), 0.5)
	h = np.full((S, S), 0.6)
	yl = YY % 16
	val[(yl == 0) | (yl == 15)] = 0.12
	val[(yl == 1) | (yl == 14)] = 0.85
	val[(yl == 2) | (yl == 13)] = 0.3
	for k in range(4):
		xc = k * 8 + 4
		for yc in (7.5, 23.5):
			d = np.sqrt((XX + 0.5 - xc) ** 2 + (YY + 0.5 - yc) ** 2)
			ring = (np.abs(d - 3.6) < 0.7)
			core = d < 1.4
			val[ring] = 0.88
			val[core] = 0.95
			val[(d > 1.4) & (d < 2.9)] = 0.38
	for x in range(0, S, 8):
		for yc in (7, 23):
			for dy in range(-3, 4):
				w = 3 - abs(dy)
				val[yc + dy, (x - w) % S] = 0.7
				val[yc + dy, (x + w) % S] = 0.7
	h = 0.5 + (val - 0.5) * 0.4
	return result(ramp(val, A_MID, 0.2), h, 0.55, nstr=1.2)


@reg("plaster", rot=1, flags=F_WET | F_SNOW, chroma=0.3)
def t_plaster(rng, v):
	n = fbm(rng, 4, 3)
	streak = fbm(rng, 16, 1, cy=1)
	val = 0.6 + (n - 0.5) * 0.18 + (streak - 0.5) * 0.08 + (rng.random((S, S)) - 0.5) * 0.04
	h = 0.6 + n * 0.2
	for _ in range(2):
		x, y = rng.integers(0, S, 2)
		for k in range(int(rng.integers(5, 12))):
			val[y % S, x % S] -= 0.18
			h[y % S, x % S] = 0.3
			y += 1
			x += rng.choice([-1, 0, 0, 1])
	return result(ramp(val, A_LIGHT, 0.5), h, 0.9, nstr=1.2)


@reg("brick", rot=1, flags=F_WET | F_SNOW, chroma=0.35)
def t_brick(rng, v):
	val = np.zeros((S, S))
	h = np.zeros((S, S))
	n = fbm(rng, 8, 2)
	for r in range(S // 8):
		y0 = r * 8
		off = 8 * (r % 2)
		for k in range(S // 16):
			x0 = (k * 16 + off) % S
			tone = rng.uniform(0.35, 0.65)
			for yy in range(y0, y0 + 8):
				for xx in range(16):
					x = (x0 + xx) % S
					lx = xx
					ly = yy - y0
					if lx == 15 or ly == 7:
						val[yy, x] = 0.85
						h[yy, x] = 0.1
						continue
					e = min(lx, 14 - lx, ly, 6 - ly)
					val[yy, x] = tone + (n[yy, x] - 0.5) * 0.25 + (0.1 if (lx == 0 or ly == 0) else 0.0) - (0.1 if (lx == 14 or ly == 6) else 0.0)
					h[yy, x] = 0.6 + min(e, 2) * 0.15
	return result(ramp(val, A_DARK, 0.4), h, 0.85)


@reg("stone_brick", rot=1, flags=F_WET | F_SNOW, chroma=0.3)
def t_stone_brick(rng, v):
	val = np.zeros((S, S))
	h = np.zeros((S, S))
	n = fbm(rng, 8, 2)
	hatch = ((XX + YY * 2) % 4 == 0)
	for r in range(2):
		y0 = r * 16
		cuts = [0, 16] if r == 0 else [8, 24]
		for k in range(2):
			x0 = cuts[k]
			w = 16
			tone = rng.uniform(0.4, 0.62)
			for yy in range(y0, y0 + 16):
				for xx in range(w):
					x = (x0 + xx) % S
					ly = yy - y0
					if xx == w - 1 or ly == 15:
						val[yy, x] = 0.1
						h[yy, x] = 0.0
						continue
					e = min(xx, w - 2 - xx, ly, 14 - ly)
					bev = 0.14 if (xx == 0 or ly == 0) else (-0.14 if (xx == w - 2 or ly == 14) else 0.0)
					val[yy, x] = tone + (n[yy, x] - 0.5) * 0.3 + bev - (0.05 if hatch[yy, x] else 0)
					h[yy, x] = 0.5 + min(e, 2) * 0.2
	return result(ramp(val, A_MID, 0.4), h, 0.85)


@reg("flagstone", rot=2, flags=F_WET | F_SNOW, chroma=0.3)
def t_flagstone(rng, v):
	pts = jitter_grid(rng, 2, 2, 0.5)
	f1, f2, idx, _ = voronoi(rng, pts=pts, sx=1.0, sy=1.0)
	edge = f2 - f1
	n = fbm(rng, 4, 3)
	tone = rng.uniform(0.42, 0.62, len(pts))
	h = np.clip(edge / 3.0, 0, 1) ** 0.4
	grout = edge < 1.1
	lt = light(h, 2.5)
	val = tone[idx] + (n - 0.5) * 0.22 + (lt - 1.0) * 0.4
	val[grout] = 0.14
	h[grout] = 0.0
	chip = speck(rng, 8)
	val[chip] -= 0.12
	return result(ramp(val, A_MID, 0.45), h, 0.75)


@reg("floor_tile", rot=2, flags=F_WET | F_SNOW, chroma=0.3)
def t_floor_tile(rng, v):
	n = fbm(rng, 4, 2)
	val = np.zeros((S, S))
	for ty in range(2):
		for tx in range(2):
			tone = rng.uniform(0.4, 0.6)
			sl = (slice(ty * 16, ty * 16 + 16), slice(tx * 16, tx * 16 + 16))
			val[sl] = tone
	loc_x = XX % 16
	loc_y = YY % 16
	val += (n - 0.5) * 0.18
	val[(loc_x == 0) | (loc_y == 0)] += 0.12
	val[(loc_x == 14) | (loc_y == 14)] -= 0.1
	g = (loc_x == 15) | (loc_y == 15)
	val[g] = 0.12
	h = np.where(g, 0.0, 0.7)
	return result(ramp(val, A_MID, 0.4), h, 0.55)


@reg("marble", rot=2, flags=F_WET | F_SNOW, chroma=0.5)
def t_marble(rng, v):
	n = fbm(rng, 2, 4)
	vein = np.abs(np.sin(2 * np.pi * (XX / S + YY / S * 2) + n * 7.0))
	val = 0.62 + (n - 0.5) * 0.15 - np.clip(0.18 - vein, 0, 1) * 1.6
	h = 0.7 - np.clip(0.18 - vein, 0, 1)
	return result(ramp(val, A_LIGHT, 0.4), h, 0.35, nstr=0.8)


@reg("lattice", rot=1, flags=F_NIGHT_GLOW, chroma=0.4)
def t_lattice(rng, v):
	# 步步锦窗棂：木格 + 窗纸（遮罩 = 窗纸）
	val = np.full((S, S), 0.82)
	paper_n = fbm(rng, 4, 2)
	val += (paper_n - 0.5) * 0.06
	wood = np.zeros((S, S), bool)
	lx = XX % 16
	ly = YY % 16
	wood |= (lx < 1) | (ly < 1)
	wood |= ((lx == 8) & (ly > 3) & (ly < 13))
	wood |= ((ly == 8) & ((lx < 4) | (lx > 12)))
	wood |= ((ly == 4) & (lx > 3) & (lx < 13)) | ((ly == 12) & (lx > 3) & (lx < 13))
	wood |= ((lx == 4) & (ly > 3) & (ly < 13)) | ((lx == 12) & (ly > 3) & (ly < 13))
	val[wood] = 0.2
	sh = np.roll(wood, 1, 0) & ~wood
	val[sh] -= 0.12
	h = np.where(wood, 0.9, 0.2)
	mask = np.where(wood, 0.0, 1.0)
	return result(ramp(val, A_LIGHT, 0.2), h, np.where(wood, 0.6, 0.9), mask=mask)


@reg("paper_lantern", rot=1, flags=F_EMIT_MASK, chroma=0.3)
def t_lantern(rng, v):
	n = fbm(rng, 4, 2)
	val = 0.7 + (n - 0.5) * 0.1
	rib = (YY % 5) == 0
	val[rib] = 0.25
	seam = (XX % 16) == 0
	val[seam] = 0.4
	mask = np.where(rib, 0.25, np.where(seam, 0.6, 1.0))
	h = np.where(rib, 0.9, 0.6)
	return result(ramp(val, A_LIGHT, 0.3), h, 0.8, mask=mask)


@reg("stone_carved", rot=1, flags=F_WET | F_SNOW, chroma=0.3)
def t_carved(rng, v):
	# 祥云纹浮雕
	h = np.full((S, S), 0.4)
	n = fbm(rng, 8, 2)
	for (cx, cy, r) in ((10, 12, 6.0), (22, 20, 5.0), (26, 8, 3.5), (6, 26, 3.5)):
		d = tdist(XX + 0.5, YY + 0.5, cx, cy)
		ang = np.arctan2(((YY + 0.5 - cy + S / 2) % S - S / 2), ((XX + 0.5 - cx + S / 2) % S - S / 2))
		spiral = np.abs(((d - ang / (2 * np.pi) * 2.8) % 2.8) - 1.4)
		m = (d < r) & (spiral < 0.75)
		h[m] = 0.9
	lt = light(h, 3.5)
	val = 0.5 + (lt - 1.0) * 0.6 + (n - 0.5) * 0.2
	return result(ramp(val, A_MID, 0.4), h, 0.85)


@reg("gold", rot=2, flags=F_METAL, chroma=0.15)
def t_gold(rng, v):
	n = fbm(rng, 4, 3)
	f1, f2, idx, pts = voronoi(rng, 18)
	ham = np.clip(f1 / 4.0, 0, 1)
	val = 0.55 + (n - 0.5) * 0.25 - ham * 0.15
	# 回纹刻线
	lx = XX % 8
	ly = YY % 8
	eng = ((lx == 1) & (ly > 0) & (ly < 7)) | ((ly == 1) & (lx > 0) & (lx < 7)) | ((lx == 5) & (ly > 2) & (ly < 7)) | ((ly == 5) & (lx > 2) & (lx < 6))
	eng &= (YY % 16 < 8) & (XX % 16 < 8)
	val[eng] -= 0.12
	hl = speck(rng, 10)
	val[hl] = 1.0
	h = 0.7 - ham * 0.2
	h[eng] = 0.2
	return result(ramp(val, A_LIGHT, 0.3), h, 0.3 + ham * 0.15, nstr=1.2)


@reg("bronze", rot=2, flags=F_METAL | F_WET, chroma=1.0)
def t_bronze(rng, v):
	n = fbm(rng, 4, 3)
	pat = fbm(rng, 4, 3) > 0.62
	val = 0.5 + (n - 0.5) * 0.3
	rgb = ramp(val, pal("#4b3a24", "#5a462b", "#6a5333", "#7a613c", "#8a6f46", "#9a7e51"), 0.5)
	pv = 0.4 + fbm(rng, 8, 2) * 0.5
	prgb = ramp(pv, pal("#2f5a50", "#3a6d60", "#478170", "#569582", "#6aa895"), 0.5)
	rgb[pat] = prgb[pat]
	rough = np.where(pat, 0.9, 0.45)
	return result(rgb, 0.5 + n * 0.3 + pat * 0.2, rough)


@reg("door_panel", rot=1, flags=F_WET, chroma=0.3)
def t_door(rng, v):
	grain = fbm(rng, 16, 2, cy=2)
	val = 0.5 + (grain - 0.5) * 0.25
	h = np.full((S, S), 0.6)
	seam = (XX % 8) == 7
	val[seam] -= 0.25
	h[seam] = 0.1
	# 门钉
	for yy in range(3, S, 8):
		for xx in range(3, S, 8):
			d = np.sqrt((XX + 0.5 - xx - 0.5) ** 2 + (YY + 0.5 - yy - 0.5) ** 2)
			m = d < 1.6
			val[m] = 0.92 - ((XX[m] - xx) + (YY[m] - yy)) * 0.08
			h[m] = 1.0
			sh = (d >= 1.6) & (d < 2.3) & (XX >= xx) & (YY >= yy)
			val[sh] -= 0.15
	return result(ramp(val, A_WARM, 0.35), h, np.where(h > 0.9, 0.35, 0.7))


@reg("cloth", rot=1, flags=F_WET, chroma=0.3)
def t_cloth(rng, v):
	weave = ((XX + YY) % 2) * 0.05
	fold = np.sin(2 * np.pi * XX / S * 3 + fbm(rng, 2, 2) * 2) * 0.1
	val = 0.55 + weave + fold + (fbm(rng, 8, 2) - 0.5) * 0.1
	return result(ramp(val, A_LIGHT, 0.3), 0.5 + fold, 0.95, nstr=1.0)


@reg("crystal", rot=1, flags=F_EMIT_MASK | F_CRYSTAL | F_GLOSSY, chroma=0.2)
def t_crystal(rng, v):
	f1, f2, idx, pts = voronoi(rng, 7, 1.6, 0.6)
	edge = f2 - f1
	tone = rng.uniform(0.35, 0.8, len(pts))
	val = tone[idx] + (1 - np.clip(f1 / 6, 0, 1)) * 0.15
	val[edge < 0.8] = 1.0
	mask = 0.55 + 0.45 * np.clip(val, 0, 1)
	return result(ramp(val, A_LIGHT, 0.3), np.clip(edge / 3, 0, 1), 0.1, mask=mask, nstr=1.5)


@reg("rune", rot=1, flags=F_EMIT_MASK, chroma=0.3)
def t_rune(rng, v):
	n = fbm(rng, 8, 2)
	val = 0.3 + (n - 0.5) * 0.2
	mask = np.zeros((S, S))
	# 方形回旋符纹
	for (x0, y0) in ((2, 2), (18, 2), (2, 18), (18, 18)):
		pts = [(0, 0), (11, 0), (11, 11), (2, 11), (2, 3), (8, 3), (8, 8), (5, 8)]
		for a, b in zip(pts, pts[1:]):
			for t in np.linspace(0, 1, 24):
				x = int(round(x0 + a[0] + (b[0] - a[0]) * t)) % S
				y = int(round(y0 + a[1] + (b[1] - a[1]) * t)) % S
				mask[y, x] = 1.0
	val[mask > 0] = 0.95
	h = np.where(mask > 0, 0.2, 0.6)
	return result(ramp(val, A_MID, 0.3), h, 0.8, mask=mask)


@reg("glow_plain", rot=2, flags=F_EMIT_MASK, chroma=0.0)
def t_glow(rng, v):
	n = fbm(rng, 4, 2)
	val = 0.7 + (n - 0.5) * 0.15
	return result(ramp(val, A_LIGHT, 0.3), 0.5 + n * 0.1, 0.6, mask=np.full((S, S), 1.0), nstr=0.5)


# ================================================================ 输出

def build():
	rows_alb = []
	rows_det = []
	meta = []
	for L in LAYERS:
		for v in range(L["variants"]):
			rng = np.random.default_rng(abs(hash_name(L["name"])) + v * 7919)
			r = L["fn"](rng, v)
			rgb = r["rgb"]
			h = r["h"]
			nstr = r["nstr"]
			gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * nstr
			gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * nstr
			nrm = np.stack([-gx, gy, np.ones_like(h)], -1)  # y 翻转：纹理 v 向下，法线 y 取向上为正
			nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
			alb = np.dstack([rgb, r["mask"]])
			det = np.dstack([nrm[..., 0] * 0.5 + 0.5, nrm[..., 1] * 0.5 + 0.5, r["rough"], r["cav"]])
			# A 通道上限 250/255：保证每层（含各级 mipmap）都被识别为带透明度，导入后所有层都是 RGBA8
			# （否则 4.4 兼容渲染器会因层格式不一致拒绝创建纹理数组）；对发光遮罩/凹缝遮蔽的影响可忽略
			alb[..., 3] = np.minimum(alb[..., 3], 250.0 / 255.0)
			det[..., 3] = np.minimum(det[..., 3], 250.0 / 255.0)
			rows_alb.append(np.round(alb * 255).clip(0, 255).astype(np.uint8))
			rows_det.append(np.round(det * 255).clip(0, 255).astype(np.uint8))
			lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
			meta.append(dict(name=L["name"] if v == 0 else "%s_%d" % (L["name"], v), base=L["name"], variant=v,
				variants=L["variants"], rot=L["rot"], flags=L["flags"], chroma=L["chroma"], avg=lin.reshape(-1, 3).mean(0).tolist()))
	return np.vstack(rows_alb), np.vstack(rows_det), meta


def hash_name(s):
	h = 2166136261
	for ch in s.encode():
		h = ((h ^ ch) * 16777619) & 0xffffffff
	return h


IMPORT_TMPL = """[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[deps]

source_file="res://assets/textures/world/{name}"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal=1
slices/vertical={n}
"""


def write_import(name, n):
	path = os.path.join(OUT_DIR, name + ".import")
	# 保留已有 uid / 导入路径（Godot 导入后会补写），只更新切片数
	if os.path.exists(path):
		txt = open(path, encoding="utf-8").read()
		txt2 = re.sub(r"slices/vertical=\d+", "slices/vertical=%d" % n, txt)
		if txt2 != txt or "2d_array_texture" in txt:
			open(path, "w", encoding="utf-8").write(txt2)
			return
	open(path, "w", encoding="utf-8").write(IMPORT_TMPL.format(name=name, n=n))


def gd_const(name):
	return name.upper()


# ================================================================ 调色 LUT（国风：柔和对比、暖高光、青绿暗部、略去饱和）

LUT_N = 32


def grade(rgb):
	"""输入/输出：显示空间 sRGB（色调映射之后）。"""
	x = rgb.copy()
	lw = np.array([0.2126, 0.7152, 0.0722])
	lum = (x * lw).sum(-1, keepdims=True)
	r, g, b = x[..., 0:1], x[..., 1:2], x[..., 2:3]
	# 绿色偏向玉青（青绿山水），黄绿草色略收
	gdom = np.clip((g - np.maximum(r, b)) * 3.0, 0.0, 1.0)
	x = x + gdom * g * np.array([-0.05, -0.01, 0.045])
	# 纯红偏朱砂
	rdom = np.clip((r - np.maximum(g, b)) * 2.0, 0.0, 1.0)
	x = x + rdom * r * np.array([-0.02, 0.035, 0.0])
	# 去饱和（高饱和处更多）
	lum = (x * lw).sum(-1, keepdims=True)
	sat = np.max(x, -1, keepdims=True) - np.min(x, -1, keepdims=True)
	k = 0.9 - 0.08 * np.clip(sat - 0.4, 0.0, 1.0)
	x = lum + (x - lum) * k
	# 分离色调：暗部青蓝、亮部暖金
	lum = np.clip((x * lw).sum(-1, keepdims=True), 0.0, 1.0)
	sh = (1.0 - lum) ** 2
	hi = lum ** 2
	x = x + sh * np.array([-0.012, 0.010, 0.030]) + hi * np.array([0.028, 0.012, -0.030])
	# 纸感：抬黑、柔化高光
	x = 0.022 + x * 0.968
	x = x - 0.035 * np.maximum(x - 0.8, 0.0) ** 2 / 0.04
	return np.clip(x, 0.0, 1.0)


def write_lut():
	n = LUT_N
	c = (np.arange(n) + 0.5) / n
	img = np.zeros((n, n * n, 3))
	for s in range(n):  # 切片 = 蓝
		rr, gg = np.meshgrid(c, c)  # x = 红，y = 绿
		rgb = np.stack([rr, gg, np.full_like(rr, c[s])], -1)
		img[:, s * n:(s + 1) * n, :] = grade(rgb)
	Image.fromarray(np.round(img * 255).astype(np.uint8), "RGB").save(os.path.join(OUT_DIR, "grade_lut.png"))
	path = os.path.join(OUT_DIR, "grade_lut.png.import")
	if not os.path.exists(path):
		open(path, "w", encoding="utf-8").write("""[remap]

importer="3d_texture"
type="CompressedTexture3D"

[deps]

source_file="res://assets/textures/world/grade_lut.png"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
slices/horizontal=%d
slices/vertical=1
""" % n)


def write_gd(meta):
	lines = [
		"class_name BlockIds",
		"## 方块材质层编号与每层参数（由 tools/gen_world_textures.py 自动生成，请勿手改）。",
		"## 层在 Texture2DArray（assets/textures/world/blocks_*.png）中的序号；带变体的层占用连续多层，常量指向第一层。",
		"",
		"const COUNT := %d" % len(meta),
		"",
		"# 标志位（与 block.gdshader 一致）",
	]
	for k, val in (("F_SNOW", F_SNOW), ("F_WET", F_WET), ("F_WIND_LEAF", F_WIND_LEAF), ("F_WIND_GRASS", F_WIND_GRASS),
			("F_EMIT_MASK", F_EMIT_MASK), ("F_LAVA", F_LAVA), ("F_METAL", F_METAL), ("F_NIGHT_GLOW", F_NIGHT_GLOW),
			("F_GLOSSY", F_GLOSSY), ("F_CRYSTAL", F_CRYSTAL), ("F_FOLIAGE", F_FOLIAGE), ("F_TERRAIN", F_TERRAIN)):
		lines.append("const %s := %d" % (k, val))
	lines.append("")
	lines.append("# 层编号")
	for i, m in enumerate(meta):
		if m["variant"] == 0:
			lines.append("const %s := %d" % (gd_const(m["name"]), i))
	lines.append("")
	lines.append("## 每层名称")
	lines.append("const NAMES := [%s]" % ", ".join('"%s"' % m["name"] for m in meta))
	lines.append("## 每层参数：x 变体数，y 变换模式（0 无 / 1 左右翻转 / 2 旋转+翻转），z 标志位，w 保色")
	lines.append("const INFO := [")
	for m in meta:
		lines.append("\tVector4(%d, %d, %d, %.2f),  # %s" % (m["variants"] if m["variant"] == 0 else 1, m["rot"], m["flags"], m["chroma"], m["name"]))
	lines.append("]")
	lines.append("## 每层线性空间平均色（着色器用于求细节比值）")
	lines.append("const AVG := [")
	for m in meta:
		a = m["avg"]
		lines.append("\tColor(%.5f, %.5f, %.5f),  # %s" % (a[0], a[1], a[2], m["name"]))
	lines.append("]")
	open(GD_OUT, "w", encoding="utf-8").write("\n".join(lines) + "\n")


def preview(alb, meta, out):
	n = len(meta)
	cols = 8
	cell = 32 * 4
	pad = 18
	rows = (n + cols - 1) // cols
	img = Image.new("RGB", (cols * (cell + 8) + 8, rows * (cell + pad + 8) + 8), (40, 40, 44))
	dr = ImageDraw.Draw(img)
	for i, m in enumerate(meta):
		tile = Image.fromarray(alb[i * 32:(i + 1) * 32, :, :3])
		# 2×2 平铺检查接缝
		big = Image.new("RGB", (64, 64))
		for yy in range(2):
			for xx in range(2):
				big.paste(tile, (xx * 32, yy * 32))
		big = big.resize((cell, cell), Image.NEAREST)
		x = 8 + (i % cols) * (cell + 8)
		y = 8 + (i // cols) * (cell + pad + 8)
		img.paste(big, (x, y + pad))
		dr.text((x, y + 2), "%d %s" % (i, m["name"]), fill=(230, 230, 230))
	img.save(out)


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	alb, det, meta = build()
	Image.fromarray(alb, "RGBA").save(os.path.join(OUT_DIR, "blocks_albedo.png"), optimize=True)
	Image.fromarray(det, "RGBA").save(os.path.join(OUT_DIR, "blocks_detail.png"), optimize=True)
	write_import("blocks_albedo.png", len(meta))
	write_import("blocks_detail.png", len(meta))
	write_gd(meta)
	write_lut()
	print("生成 %d 层材质（%d×%d），%s" % (len(meta), S, S, OUT_DIR))
	if "--preview" in sys.argv:
		preview(alb, meta, sys.argv[sys.argv.index("--preview") + 1])


if __name__ == "__main__":
	main()
