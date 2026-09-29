#!/usr/bin/env python3
"""程序生成战斗特效贴图 → assets/textures/vfx/

用法：python3 tools/gen_vfx_textures.py
依赖：numpy、Pillow（pip install pillow）
所有贴图均为确定性生成（固定随机种子），可重复运行。

贴图清单（通道约定见各函数注释）：
  glow        柔光圆斑（L）
  flare       星芒闪光（L）
  spark       拉伸火花条（L，竖向）
  mote        四角星点（L）
  smoke       烟团 2×2 图集（LA：亮度 + 密度）
  flame       火焰 4×4 序列帧（L，循环）
  noise       可平铺噪声（RGB：低频 fbm / 高频 fbm / 细胞）
  ribbon      横向拉丝噪声（L，可平铺）
  circle      法阵三层（RGB：外圈符文 / 八卦 / 内层星阵），带 mipmap 用于泛光
  glyphs      法阵中心字 4×2 图集（L）：金 木 水 火 土 灵 雷 敕
  crack       地裂贴花（RGBA：裂纹 / 裂纹泛光 / 中心污迹 / 透明度）
  scorch      焦痕贴花（LA）
  frost       霜花贴花（LA）
  leaf        叶片 2×1 图集（LA）
  shard       冰晶/碎片（LA）
  talisman    符纸（RGBA 彩色）
  hex         护盾六角符纹（L，可平铺）
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "vfx")
FONT = os.path.join(ROOT, "assets", "fonts", "XianKai-Regular.ttf")


# ---------------------------------------------------------------- 工具

def coords(n, m=None):
	"""像素中心坐标，范围 [-1, 1]"""
	m = m or n
	y, x = np.mgrid[0:m, 0:n].astype(np.float64)
	return (x + 0.5) / n * 2 - 1, (y + 0.5) / m * 2 - 1


def smoothstep(e0, e1, x):
	t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3 - 2 * t)


def fft_noise(w, h, beta, seed, aniso=(1.0, 1.0)):
	"""可平铺的 1/f^beta 噪声，归一化到 [0, 1]"""
	rng = np.random.default_rng(seed)
	white = rng.standard_normal((h, w))
	fy = np.fft.fftfreq(h)[:, None] * aniso[1]
	fx = np.fft.fftfreq(w)[None, :] * aniso[0]
	f = np.sqrt(fx * fx + fy * fy)
	f[0, 0] = 1.0
	spec = np.fft.fft2(white) / (f ** beta)
	spec[0, 0] = 0
	n = np.real(np.fft.ifft2(spec))
	n = (n - n.min()) / (n.max() - n.min() + 1e-9)
	return n


def voronoi(w, h, count, seed):
	"""可平铺的细胞噪声（F1 距离），归一化到 [0, 1]"""
	rng = np.random.default_rng(seed)
	pts = rng.random((count, 2))
	y, x = np.mgrid[0:h, 0:w].astype(np.float64)
	x = (x + 0.5) / w
	y = (y + 0.5) / h
	d = np.full((h, w), 10.0)
	for px, py in pts:
		dx = np.abs(x - px)
		dx = np.minimum(dx, 1 - dx)
		dy = np.abs(y - py)
		dy = np.minimum(dy, 1 - dy)
		d = np.minimum(d, np.sqrt(dx * dx + dy * dy))
	return np.clip(d / d.max(), 0, 1)


def save_l(arr, name):
	a = np.clip(arr, 0, 1)
	Image.fromarray((a * 255 + 0.5).astype(np.uint8), "L").save(os.path.join(OUT, name + ".png"))


def save_la(lum, alpha, name):
	l8 = (np.clip(lum, 0, 1) * 255 + 0.5).astype(np.uint8)
	a8 = (np.clip(alpha, 0, 1) * 255 + 0.5).astype(np.uint8)
	Image.fromarray(np.dstack([l8, a8]), "LA").save(os.path.join(OUT, name + ".png"))


def save_rgb(r, g, b, name):
	c = np.dstack([np.clip(x, 0, 1) for x in (r, g, b)])
	Image.fromarray((c * 255 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, name + ".png"))


def save_rgba(r, g, b, a, name):
	c = np.dstack([np.clip(x, 0, 1) for x in (r, g, b, a)])
	Image.fromarray((c * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"))


def img_to_arr(im):
	return np.asarray(im).astype(np.float64) / 255.0


# ---------------------------------------------------------------- 光斑类

def gen_glow():
	x, y = coords(128)
	r = np.sqrt(x * x + y * y)
	g = np.exp(-r * r * 5.0) * 0.8 + np.exp(-r * r * 22.0) * 0.35
	g *= smoothstep(1.0, 0.75, r)
	save_l(g / g.max(), "glow")


def gen_flare():
	n = 256
	x, y = coords(n)
	r = np.sqrt(x * x + y * y)
	core = np.exp(-r * r * 70.0)
	halo = np.exp(-r * r * 7.0) * 0.28
	rays = np.zeros_like(r)
	for k, (ang, length, width) in enumerate([(0, 1.0, 0.018), (90, 1.0, 0.018), (45, 0.55, 0.012), (135, 0.55, 0.012)]):
		a = math.radians(ang)
		dx, dy = math.cos(a), math.sin(a)
		along = np.abs(x * dx + y * dy)
		perp = np.abs(-x * dy + y * dx)
		w = width * (1.0 + along * 2.0)
		rays = np.maximum(rays, np.exp(-(perp / w) ** 2) * np.clip(1 - along / length, 0, 1) ** 2.2)
	f = core + halo + rays * 0.8
	f *= smoothstep(1.0, 0.85, r)
	save_l(f / f.max(), "flare")


def gen_spark():
	w, h = 32, 128
	x, y = coords(w, h)
	v = (y + 1) * 0.5  # 0 顶 → 1 底
	width = 0.32 * (1.0 - 0.55 * v)
	across = np.exp(-(x / width) ** 2)
	along = np.sin(np.pi * np.clip(v, 0, 1)) ** 0.7 * (1.15 - 0.5 * v)
	s = across * along
	core = np.exp(-(x / (width * 0.35)) ** 2) * along
	s = s * 0.7 + core * 0.6
	save_l(s / s.max(), "spark")


def gen_mote():
	x, y = coords(64)
	r = np.sqrt(x * x + y * y)
	core = np.exp(-r * r * 40.0)
	cross = np.exp(-(np.abs(x) / 0.05) ** 2) * np.clip(1 - np.abs(y), 0, 1) ** 3 + np.exp(-(np.abs(y) / 0.05) ** 2) * np.clip(1 - np.abs(x), 0, 1) ** 3
	halo = np.exp(-r * r * 6.0) * 0.25
	m = core + cross * 0.7 + halo
	m *= smoothstep(1.0, 0.8, r)
	save_l(m / m.max(), "mote")


# ---------------------------------------------------------------- 烟、火

def gen_smoke():
	cell = 256
	lum = np.zeros((cell * 2, cell * 2))
	alp = np.zeros((cell * 2, cell * 2))
	for i in range(4):
		x, y = coords(cell)
		r = np.sqrt(x * x + y * y)
		n1 = fft_noise(cell, cell, 2.2, 100 + i)
		n2 = fft_noise(cell, cell, 1.4, 200 + i)
		warp = (n1 - 0.5) * 0.35
		rr = np.sqrt((x + warp) ** 2 + (y + (n2 - 0.5) * 0.35) ** 2)
		base = np.clip(1 - rr * rr, 0, 1) ** 1.3
		dens = np.clip(base * (0.45 + 1.1 * n1 * 0.6 + n2 * 0.5) - 0.18, 0, 1)
		dens *= smoothstep(1.0, 0.7, r)
		dens = dens / (dens.max() + 1e-6)
		# 顶光：上亮下暗，外加噪声明暗
		light = 0.62 + 0.3 * (-y * 0.5 + 0.5) + (n2 - 0.5) * 0.35
		cy, cx = divmod(i, 2)
		lum[cy * cell:(cy + 1) * cell, cx * cell:(cx + 1) * cell] = np.clip(light, 0, 1)
		alp[cy * cell:(cy + 1) * cell, cx * cell:(cx + 1) * cell] = dens ** 1.1
	save_la(lum, alp, "smoke")


def gen_flame():
	"""火焰序列帧：饱满的火团底部 + 向上撕裂的火舌，逐帧沿可平铺噪声上卷形成无缝循环"""
	cell = 128
	frames = 16
	img = np.zeros((cell * 4, cell * 4))
	nz = fft_noise(cell, cell * 2, 1.6, 7)
	nz2 = fft_noise(cell, cell * 2, 2.2, 8)
	nz3 = fft_noise(cell, cell * 2, 1.2, 9)
	for f in range(frames):
		t = f / frames
		x, y = coords(cell)
		v = (1 - y) * 0.5  # 0 底 → 1 顶
		oy = int(t * cell * 2) % (cell * 2)
		rows = (np.arange(cell)[:, None] + oy) % (cell * 2)
		rows2 = (np.arange(cell)[:, None] * 2 + oy * 2) % (cell * 2)
		cols = np.arange(cell)[None, :]
		n = nz[rows, cols]
		n2 = nz2[rows2, cols]
		n3 = nz3[rows, (cols + 37) % cell]
		# 横向摆动随高度增加
		disp = ((n - 0.5) * 0.7 + (n3 - 0.5) * 0.3) * v * 0.9
		half_w = 0.66 * np.clip(1 - v, 0, 1) ** 0.75 * np.clip(v * 5.0, 0, 1) ** 0.35 + 0.03
		d = np.abs(x - disp) / half_w
		body = smoothstep(1.0, 0.15, d)
		# 顶部被噪声撕成火舌
		cut = smoothstep(0.25 + n2 * 0.75, 0.0 + n2 * 0.45, v - 0.18)
		inten = body * np.clip(cut + (v < 0.2) * 1.0, 0, 1)
		inten *= smoothstep(0.0, 0.1, v)
		# 核心更亮（底部中心）
		core = np.exp(-((x - disp * 0.5) / (half_w * 0.45)) ** 2) * np.clip(1.0 - v * 1.3, 0, 1)
		inten = np.clip(inten * (0.55 + 0.45 * n2) + core * 0.45 * body, 0, 1)
		cy, cx = divmod(f, 4)
		img[cy * cell:(cy + 1) * cell, cx * cell:(cx + 1) * cell] = inten
	save_l(img, "flame")


def gen_noise():
	n = 256
	r = fft_noise(n, n, 2.0, 1)
	g = fft_noise(n, n, 1.2, 2)
	b = 1.0 - voronoi(n, n, 24, 3)
	save_rgb(r, g, b, "noise")


def gen_ribbon():
	w, h = 256, 64
	n = fft_noise(w, h, 1.6, 21, aniso=(0.12, 1.0))
	n2 = fft_noise(w, h, 1.2, 22, aniso=(0.3, 1.0))
	s = np.clip(n * 0.7 + n2 * 0.5 - 0.1, 0, 1)
	s = (s - s.min()) / (s.max() - s.min())
	save_l(s, "ribbon")


# ---------------------------------------------------------------- 法阵

def _font(size):
	return ImageFont.truetype(FONT, size)


def _draw_trigram(d, cx, cy, ang, lines, size, width):
	"""在 (cx, cy) 以角度 ang（径向朝外）绘制卦象：lines 自内向外，1 为阳爻，0 为阴爻"""
	ca, sa = math.cos(ang), math.sin(ang)
	tx, ty = -sa, ca  # 切向
	for i, yang in enumerate(lines):
		off = (i - 1) * size * 0.42
		px, py = cx + ca * off, cy + sa * off
		half = size * 0.5
		segs = [(-half, half)] if yang else [(-half, -half * 0.18), (half * 0.18, half)]
		for a, b in segs:
			d.line([(px + tx * a, py + ty * a), (px + tx * b, py + ty * b)], fill=255, width=width)


def gen_circle():
	S = 2048
	c = S / 2
	layers = []
	# R：外圈（双环 + 刻度 + 符文带）
	im = Image.new("L", (S, S), 0)
	d = ImageDraw.Draw(im)
	for rr, w in [(0.985, 10), (0.955, 5), (0.80, 6), (0.775, 3)]:
		R = rr * c
		d.ellipse([c - R, c - R, c + R, c + R], outline=255, width=w)
	for k in range(144):
		a = k / 144 * math.tau
		r0 = 0.955 * c
		r1 = (0.93 if k % 4 else 0.915) * c
		d.line([(c + math.cos(a) * r0, c + math.sin(a) * r0), (c + math.cos(a) * r1, c + math.sin(a) * r1)], fill=255, width=4)
	text = "天地玄黄宇宙洪荒日月星辰敕令急如律乾坤震巽坎离艮兑罡斗阴阳五行"
	font = _font(int(S * 0.062))
	n = 32
	for k in range(n):
		ch = text[k % len(text)]
		a = k / n * math.tau
		glyph = Image.new("L", (int(S * 0.09), int(S * 0.09)), 0)
		gd = ImageDraw.Draw(glyph)
		bbox = gd.textbbox((0, 0), ch, font=font)
		gw, gh = bbox[2] - bbox[0], bbox[3] - bbox[1]
		gd.text(((glyph.width - gw) / 2 - bbox[0], (glyph.height - gh) / 2 - bbox[1]), ch, font=font, fill=255)
		rot = glyph.rotate(-math.degrees(a) - 90, resample=Image.BICUBIC, expand=True)
		R = 0.865 * c
		px, py = c + math.cos(a) * R, c + math.sin(a) * R
		im.paste(255, (int(px - rot.width / 2), int(py - rot.height / 2)), rot)
	layers.append(im)
	# G：八卦环
	im = Image.new("L", (S, S), 0)
	d = ImageDraw.Draw(im)
	for rr, w in [(0.705, 6), (0.52, 6), (0.505, 3)]:
		R = rr * c
		d.ellipse([c - R, c - R, c + R, c + R], outline=255, width=w)
	trigrams = [(1, 1, 1), (0, 1, 1), (1, 0, 1), (0, 0, 1), (1, 1, 0), (0, 1, 0), (1, 0, 0), (0, 0, 0)]
	for k, tg in enumerate(trigrams):
		a = k / 8 * math.tau - math.pi / 2
		R = 0.612 * c
		_draw_trigram(d, c + math.cos(a) * R, c + math.sin(a) * R, a, tg, S * 0.085, 16)
		a2 = a + math.tau / 16
		R2 = 0.612 * c
		px, py = c + math.cos(a2) * R2, c + math.sin(a2) * R2
		d.ellipse([px - 9, py - 9, px + 9, py + 9], fill=255)
	layers.append(im)
	# B：内层五芒星 + 五边形 + 内环
	im = Image.new("L", (S, S), 0)
	d = ImageDraw.Draw(im)
	R = 0.47 * c
	pts = [(c + math.cos(k / 5 * math.tau - math.pi / 2) * R, c + math.sin(k / 5 * math.tau - math.pi / 2) * R) for k in range(5)]
	for k in range(5):
		d.line([pts[k], pts[(k + 2) % 5]], fill=255, width=7)
		d.line([pts[k], pts[(k + 1) % 5]], fill=255, width=4)
		d.ellipse([pts[k][0] - 22, pts[k][1] - 22, pts[k][0] + 22, pts[k][1] + 22], outline=255, width=6)
	for rr, w in [(0.47, 5), (0.25, 7), (0.235, 3)]:
		R = rr * c
		d.ellipse([c - R, c - R, c + R, c + R], outline=255, width=w)
	for k in range(24):
		a = k / 24 * math.tau
		r0, r1 = 0.25 * c, (0.29 if k % 2 == 0 else 0.27) * c
		d.line([(c + math.cos(a) * r0, c + math.sin(a) * r0), (c + math.cos(a) * r1, c + math.sin(a) * r1)], fill=255, width=5)
	layers.append(im)
	arrs = [img_to_arr(l.resize((1024, 1024), Image.LANCZOS)) for l in layers]
	save_rgb(arrs[0], arrs[1], arrs[2], "circle")


def gen_glyphs():
	chars = "金木水火土灵雷敕"
	cell = 256
	im = Image.new("L", (cell * 4, cell * 2), 0)
	font = _font(int(cell * 0.78))
	for i, ch in enumerate(chars):
		cy, cx = divmod(i, 4)
		g = Image.new("L", (cell, cell), 0)
		gd = ImageDraw.Draw(g)
		bbox = gd.textbbox((0, 0), ch, font=font)
		gw, gh = bbox[2] - bbox[0], bbox[3] - bbox[1]
		gd.text(((cell - gw) / 2 - bbox[0], (cell - gh) / 2 - bbox[1]), ch, font=font, fill=255)
		im.paste(g, (cx * cell, cy * cell))
	im.save(os.path.join(OUT, "glyphs.png"))


# ---------------------------------------------------------------- 贴花

def _crack_paths(rng, S, count, length, branch_p, jitter):
	paths = []
	c = S / 2

	def walk(x, y, ang, L, w, depth):
		pts = [(x, y)]
		step = S * 0.018
		n = int(L / step)
		for i in range(n):
			ang += rng.normal(0, jitter)
			x += math.cos(ang) * step
			y += math.sin(ang) * step
			pts.append((x, y))
			if depth < 2 and rng.random() < branch_p:
				walk(x, y, ang + rng.choice([-1, 1]) * rng.uniform(0.4, 0.9), L * rng.uniform(0.25, 0.5) * (1 - i / n), max(1, w * 0.6), depth + 1)
		paths.append((pts, w))

	for k in range(count):
		a = k / count * math.tau + rng.uniform(-0.25, 0.25)
		r0 = S * rng.uniform(0.03, 0.08)
		walk(c + math.cos(a) * r0, c + math.sin(a) * r0, a, length * S * rng.uniform(0.6, 1.0), rng.uniform(9, 14), 0)
	return paths


def gen_crack():
	S = 1024
	rng = np.random.default_rng(42)
	im = Image.new("L", (S, S), 0)
	d = ImageDraw.Draw(im)
	for pts, w in _crack_paths(rng, S, 9, 0.44, 0.07, 0.22):
		for i in range(len(pts) - 1):
			t = i / max(len(pts) - 1, 1)
			d.line([pts[i], pts[i + 1]], fill=255, width=max(2, int(w * (1 - t * 0.8))))
	# 中心碎裂环
	for k in range(14):
		a0 = k / 14 * math.tau
		R = S * rng.uniform(0.09, 0.13)
		d.line([(S / 2 + math.cos(a0) * R, S / 2 + math.sin(a0) * R), (S / 2 + math.cos(a0 + 0.45) * R * 1.1, S / 2 + math.sin(a0 + 0.45) * R * 1.1)], fill=255, width=7)
	sharp = img_to_arr(im.resize((512, 512), Image.LANCZOS))
	wide = img_to_arr(im.filter(ImageFilter.GaussianBlur(14)).resize((512, 512), Image.LANCZOS))
	wide = np.clip(wide * 3.0, 0, 1)
	x, y = coords(512)
	r = np.sqrt(x * x + y * y)
	n = fft_noise(512, 512, 1.8, 43)
	stain = np.clip((1 - r / 0.55) * (0.6 + n * 0.8), 0, 1) ** 1.4
	edge = smoothstep(1.0, 0.8, r)
	a = np.clip(np.maximum(np.maximum(sharp, wide * 0.55), stain * 0.7), 0, 1) * edge
	save_rgba(sharp * edge, wide * edge, stain * edge, a, "crack")


def gen_scorch():
	S = 512
	x, y = coords(S)
	r = np.sqrt(x * x + y * y)
	ang = np.arctan2(y, x)
	n = fft_noise(S, S, 1.9, 51)
	n2 = fft_noise(S, S, 1.1, 52)
	streak = 0.5 + 0.5 * np.sin(ang * 23 + n * 6) * np.sin(ang * 7 + n2 * 4)
	shape = np.clip(1.0 - r / (0.62 + (n - 0.5) * 0.45 + streak * 0.18), 0, 1)
	alpha = smoothstep(0.0, 0.35, shape) * smoothstep(1.0, 0.85, r)
	lum = np.clip(0.15 + n2 * 0.35 + (1 - shape) * 0.25, 0, 1)
	save_la(lum, alpha, "scorch")


def gen_frost():
	S = 1024
	rng = np.random.default_rng(61)
	im = Image.new("L", (S, S), 0)
	d = ImageDraw.Draw(im)

	def dendrite(x, y, ang, L, w, depth):
		step = S * 0.012
		n = int(L / step)
		for i in range(n):
			nx, ny = x + math.cos(ang) * step, y + math.sin(ang) * step
			d.line([(x, y), (nx, ny)], fill=int(255 * (1 - i / max(n, 1) * 0.5)), width=max(1, int(w)))
			x, y = nx, ny
			if depth < 3 and i % 3 == 2:
				for s in (-1, 1):
					dendrite(x, y, ang + s * math.pi / 3, L * 0.32 * (1 - i / n), w * 0.6, depth + 1)

	c = S / 2
	for k in range(6):
		a = k / 6 * math.tau + rng.uniform(-0.1, 0.1)
		dendrite(c, c, a, S * 0.42, 6, 0)
	for k in range(10):
		a = rng.uniform(0, math.tau)
		R = rng.uniform(0.15, 0.35) * S
		dendrite(c + math.cos(a) * R, c + math.sin(a) * R, a + rng.uniform(-1, 1), S * 0.14, 3, 1)
	lines = img_to_arr(im.resize((512, 512), Image.LANCZOS))
	x, y = coords(512)
	r = np.sqrt(x * x + y * y)
	n = fft_noise(512, 512, 1.6, 62)
	sheen = np.clip((1 - r / 0.8) * (0.4 + n * 0.6), 0, 1) ** 1.2
	edge = smoothstep(1.0, 0.8, r)
	lum = np.clip(0.55 + lines * 0.45 + n * 0.1, 0, 1)
	alpha = np.clip(np.maximum(lines, sheen * 0.45), 0, 1) * edge
	save_la(lum, alpha, "frost")


# ---------------------------------------------------------------- 小物件

def gen_leaf():
	cell = 128
	lum = np.zeros((cell, cell * 2))
	alp = np.zeros((cell, cell * 2))
	for i in range(2):
		x, y = coords(cell)
		# 叶形：沿 y 轴，上尖下圆
		v = (y + 1) * 0.5
		width = (0.55 if i == 0 else 0.38) * np.sin(np.pi * np.clip(v, 0, 1)) ** (0.9 if i == 0 else 0.7) * (1 - 0.3 * (1 - v))
		inside = smoothstep(width + 0.02, width - 0.03, np.abs(x)) * smoothstep(0.02, 0.06, v) * smoothstep(0.98, 0.92, v)
		midrib = np.exp(-(x / 0.025) ** 2)
		veins = np.clip(np.sin((v * 9 - np.abs(x) * 5) * math.pi), 0, 1) ** 8 * smoothstep(width, width * 0.2, np.abs(x))
		shade = 0.72 + 0.28 * (1 - np.abs(x) / (width + 1e-3)).clip(0, 1) - midrib * 0.25 - veins * 0.15
		lum[:, i * cell:(i + 1) * cell] = np.clip(shade, 0, 1)
		alp[:, i * cell:(i + 1) * cell] = inside
	save_la(lum, alp, "leaf")


def gen_shard():
	S = 128
	x, y = coords(S)
	# 细长菱形晶体：上尖下尖，左右两个晶面明暗不同
	v = y
	half = 0.36 * (1 - np.abs(v) ** 1.25)
	inside = smoothstep(half + 0.02, half - 0.02, np.abs(x + v * 0.08))
	face = np.where(x + v * 0.08 < 0, 0.95, 0.62)
	edge = np.exp(-((np.abs(x + v * 0.08) - half) / 0.035) ** 2) * inside
	ridge = np.exp(-((x + v * 0.08) / 0.03) ** 2) * inside
	lum = np.clip(face * 0.75 + edge * 0.5 + ridge * 0.35, 0, 1)
	save_la(lum, inside * (0.72 + edge * 0.28), "shard")


def gen_talisman():
	W, H = 128, 256
	rng = np.random.default_rng(77)
	fiber = fft_noise(W, H, 1.3, 78, aniso=(1.0, 0.3))
	paper = np.dstack([0.96 + fiber * 0.04, 0.80 + fiber * 0.08, 0.40 + fiber * 0.1])
	im = Image.fromarray((np.clip(paper, 0, 1) * 255).astype(np.uint8), "RGB").convert("RGBA")
	d = ImageDraw.Draw(im)
	red = (190, 25, 20, 255)
	d.rectangle([6, 6, W - 7, H - 7], outline=red, width=4)
	d.rectangle([12, 12, W - 13, H - 13], outline=red, width=2)
	font = _font(40)
	for i, ch in enumerate("敕令"):
		bbox = d.textbbox((0, 0), ch, font=font)
		d.text(((W - (bbox[2] - bbox[0])) / 2 - bbox[0], 22 + i * 44 - bbox[1]), ch, font=font, fill=red)
	# 符胆：盘绕笔画
	pts = []
	for k in range(60):
		t = k / 59
		pts.append((W / 2 + math.sin(t * 13) * 26 * (1 - t * 0.4) + rng.normal(0, 1.2), 118 + t * 90))
	d.line(pts, fill=red, width=5, joint="curve")
	d.rectangle([W / 2 - 16, H - 42, W / 2 + 16, H - 16], outline=red, width=4)
	d.line([(W / 2 - 10, H - 29), (W / 2 + 10, H - 29)], fill=red, width=3)
	d.line([(W / 2, H - 38), (W / 2, H - 20)], fill=red, width=3)
	arr = np.asarray(im).astype(np.float64) / 255.0
	# 轻微不规则的纸边
	x, y = coords(W, H)
	edge_n = fft_noise(W, H, 1.5, 79)
	a = smoothstep(1.0, 0.94 - edge_n * 0.04, np.maximum(np.abs(x), np.abs(y)))
	save_rgba(arr[..., 0], arr[..., 1], arr[..., 2], a, "talisman")


def gen_hex():
	S = 256
	y, x = np.mgrid[0:S, 0:S].astype(np.float64)
	# 尖顶六边形（外接圆半径 1）：6 列 × 4 行刚好在单位方块内平铺
	px = (x + 0.5) / S * 6 * math.sqrt(3)
	py = (y + 0.5) / S * 6.0
	qf = px * math.sqrt(3) / 3 - py / 3
	rf = py * 2 / 3
	sf = -qf - rf
	q, r, s = np.round(qf), np.round(rf), np.round(sf)
	dq, dr, ds = np.abs(q - qf), np.abs(r - rf), np.abs(s - sf)
	m1 = (dq > dr) & (dq > ds)
	q = np.where(m1, -r - s, q)
	m2 = ~m1 & (dr > ds)
	r = np.where(m2, -q - s, r)
	cx = math.sqrt(3) * (q + r / 2)
	cy = 1.5 * r
	dx, dy = px - cx, py - cy
	k = math.sqrt(3) / 2
	hexd = np.maximum(np.abs(dx), np.maximum(np.abs(dx * 0.5 + dy * k), np.abs(dx * 0.5 - dy * k))) / k
	edge = np.exp(-((1.0 - hexd) / 0.07) ** 2)
	sel = ((q * 7 + r * 13) % 3) == 0
	dot = np.exp(-(hexd / 0.16) ** 2) * sel
	v = np.clip(edge + dot * 0.55, 0, 1)
	save_l(v, "hex")


def main():
	os.makedirs(OUT, exist_ok=True)
	for fn in [gen_glow, gen_flare, gen_spark, gen_mote, gen_smoke, gen_flame, gen_noise, gen_ribbon,
			gen_circle, gen_glyphs, gen_crack, gen_scorch, gen_frost, gen_leaf, gen_shard, gen_talisman, gen_hex]:
		fn()
		print("生成", fn.__name__[4:])


if __name__ == "__main__":
	main()
