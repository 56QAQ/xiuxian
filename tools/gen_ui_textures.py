#!/usr/bin/env python3
"""程序化生成界面纹理 → assets/textures/ui/*.png（numpy + Pillow）。

国风界面用到的底材与笔触：
  paper_fiber.png   宣纸纤维（可平铺，白色 + alpha，叠在深色/浅色底上）
  paper_mottle.png  宣纸斑驳（可平铺，大尺度云状深浅）
  ink_wash.png      水墨晕染团（不平铺）
  brush_stroke.png  横向粗笔触（起笔饱满、收笔飞白）
  brush_thin.png    细笔触（横线、下划线）
  cloud_corner.png  祥云角饰（白色线描，运行时着金色）
  cloud_band.png    横向祥云纹带（标题两侧）
  seal_square.png   方印（边缘残破、内框留白）
  seal_round.png    圆印
  ink_splash.png    墨点飞溅
  noise.png         着色器噪声（可平铺；R 低频云 G 顺向毛笔丝 B 高频 A 裂纹）
  jade.png          玉石纹理（可平铺）
  compass.png       罗盘盘面（二十四向刻度、八卦、同心环）
  lattice_cell.png  窗棂格（背包格子底）

所有随机数固定种子，重复运行结果一致。
用法：python3 tools/gen_ui_textures.py
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures", "ui")


# ================================================================ 基础工具

def periodic_noise(size, scale, seed, aniso=(1.0, 1.0), power=2.0):
	"""FFT 滤波白噪声 → 天然可平铺的噪声，归一化到 0..1。
	scale：特征波长（像素），aniso：x/y 方向拉伸（>1 表示该方向更平滑）。"""
	rng = np.random.default_rng(seed)
	h, w = (size, size) if isinstance(size, int) else size
	white = rng.standard_normal((h, w))
	fy = np.fft.fftfreq(h)[:, None] * aniso[1]
	fx = np.fft.fftfreq(w)[None, :] * aniso[0]
	f = np.sqrt(fx * fx + fy * fy)
	f0 = 1.0 / scale
	filt = 1.0 / (1.0 + (f / f0) ** power)
	filt[0, 0] = 0.0
	out = np.real(np.fft.ifft2(np.fft.fft2(white) * filt))
	out -= out.min()
	out /= max(out.max(), 1e-9)
	return out


def fbm(size, seed, octaves=5, base=64.0, aniso=(1.0, 1.0)):
	acc = None
	amp = 1.0
	total = 0.0
	for i in range(octaves):
		n = periodic_noise(size, base / (2 ** i), seed + i * 17, aniso)
		acc = n * amp if acc is None else acc + n * amp
		total += amp
		amp *= 0.5
	return acc / total


def smoothstep(e0, e1, x):
	t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


def save_la(alpha, name, rgb=(255, 255, 255)):
	"""白色（或指定色）+ alpha 通道保存为 RGBA PNG。"""
	a = np.clip(alpha * 255.0 + 0.5, 0, 255).astype(np.uint8)
	h, w = a.shape
	img = np.zeros((h, w, 4), np.uint8)
	img[..., 0] = rgb[0]
	img[..., 1] = rgb[1]
	img[..., 2] = rgb[2]
	img[..., 3] = a
	Image.fromarray(img, "RGBA").save(os.path.join(OUT, name), optimize=True)
	print("  %-18s %dx%d" % (name, w, h))


def save_rgba(arr, name):
	a = np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)
	Image.fromarray(a, "RGBA").save(os.path.join(OUT, name), optimize=True)
	print("  %-18s %dx%d" % (name, arr.shape[1], arr.shape[0]))


def save_rgb(arr, name):
	a = np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)
	Image.fromarray(a, "RGB").save(os.path.join(OUT, name), optimize=True)
	print("  %-18s %dx%d" % (name, arr.shape[1], arr.shape[0]))


def supersample(draw_fn, w, h, ss=4):
	"""在 ss 倍画布上用 PIL 画（L 模式），再缩小得到抗锯齿 alpha。"""
	img = Image.new("L", (w * ss, h * ss), 0)
	d = ImageDraw.Draw(img)
	draw_fn(d, ss)
	img = img.resize((w, h), Image.LANCZOS)
	return np.asarray(img, np.float32) / 255.0


# ================================================================ 宣纸

def paper():
	n = 512
	rng = np.random.default_rng(11)
	# 纤维：大量细长随机方向线段（绕边界环绕 → 可平铺）
	img = Image.new("L", (n * 2, n * 2), 0)
	d = ImageDraw.Draw(img)
	for _ in range(1700):
		x, y = rng.uniform(0, n * 2, 2)
		ang = rng.normal(0.35, 0.9)
		ln = rng.uniform(8, 46) * 2
		wv = rng.uniform(0.5, 1.4)
		val = int(rng.uniform(30, 110))
		pts = []
		for k in range(6):
			t = k / 5.0
			pts.append((x + math.cos(ang) * ln * t + math.sin(t * 5 + x) * 2, y + math.sin(ang) * ln * t + math.cos(t * 4 + y) * 2))
		for ox in (-n * 2, 0, n * 2):
			for oy in (-n * 2, 0, n * 2):
				d.line([(px + ox, py + oy) for px, py in pts], fill=val, width=max(1, int(wv * 2)))
	fib = np.asarray(img.filter(ImageFilter.GaussianBlur(1.2)).resize((n, n), Image.LANCZOS), np.float32) / 255.0
	# 细颗粒
	grain = periodic_noise(n, 2.0, 3)
	grain = smoothstep(0.55, 0.9, grain) * 0.35
	fiber = np.clip(fib * 0.9 + grain, 0, 1)
	save_la(fiber, "paper_fiber.png")
	# 斑驳：大尺度云
	m = fbm(n, 21, octaves=5, base=160.0)
	m = smoothstep(0.35, 0.8, m)
	save_la(m, "paper_mottle.png")


# ================================================================ 水墨

def ink_wash():
	w = h = 512
	yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
	cx, cy = w / 2, h / 2
	r = np.sqrt(((xx - cx) / (w * 0.42)) ** 2 + ((yy - cy) / (h * 0.36)) ** 2)
	n = fbm(w, 5, octaves=5, base=110.0)
	n2 = fbm(w, 9, octaves=4, base=40.0)
	edge = r + (n - 0.5) * 0.7 + (n2 - 0.5) * 0.25
	a = 1.0 - smoothstep(0.35, 1.0, edge)
	# 墨色层次：内部淡、边缘积墨（水墨的“水线”）
	rim = np.exp(-((edge - 0.78) / 0.07) ** 2) * 0.35
	a = np.clip(a * (0.55 + 0.45 * n2) + rim * (a > 0.02), 0, 1)
	save_la(a, "ink_wash.png")


def brush_stroke(w, h, seed, name, dry_tail=0.35, bristle=1.0, head_blob=0.25):
	"""横向毛笔笔触：起笔圆厚（藏锋）、中段饱满、收笔渐细并飞白。"""
	rng = np.random.default_rng(seed)
	yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
	t = xx / (w - 1)          # 沿笔画 0..1
	v = (yy - h / 2) / (h / 2)  # 横截面 -1..1
	# 笔画宽度轮廓
	wid = 0.78 + 0.14 * np.sin(t * 3.1 + 0.4)
	wid += head_blob * np.exp(-((t - 0.035) / 0.05) ** 2)
	wid *= 1.0 - smoothstep(0.72, 1.0, t) * 0.55
	# 起笔圆头
	head = np.clip(t / 0.045, 0, 1)
	wid *= np.sqrt(np.maximum(1.0 - (1.0 - head) ** 2, 0.0))
	# 边缘抖动（低频，沿笔画）
	edge_n = periodic_noise((h, w), 50.0, seed + 1, aniso=(1.0, 8.0))
	wid_top = wid * (0.9 + 0.2 * edge_n)
	edge_n2 = periodic_noise((h, w), 50.0, seed + 2, aniso=(1.0, 8.0))
	wid_bot = wid * (0.9 + 0.2 * edge_n2)
	lim = np.where(v < 0, wid_top, wid_bot)
	body = 1.0 - smoothstep(lim - 0.06, lim + 0.02, np.abs(v))
	# 毛笔丝（横向拉长的噪声）
	hair = periodic_noise((h, w), 2.5 / bristle, seed + 3, aniso=(40.0, 1.0))
	hair2 = periodic_noise((h, w), 5.0, seed + 4, aniso=(60.0, 1.0))
	streak = hair * 0.6 + hair2 * 0.4
	# 飞白：向收笔处与边缘增强
	dry = smoothstep(1.0 - dry_tail, 1.0, t) * 0.85 + smoothstep(0.55, 1.0, np.abs(v) / np.maximum(lim, 0.05)) * 0.35
	thr = np.clip(dry, 0, 1) * 0.75
	keep = smoothstep(thr - 0.08, thr + 0.08, streak)
	a = body * np.where(dry > 0.02, keep, 1.0)
	# 墨色浓淡（笔肚略淡）
	dens = 0.82 + 0.18 * streak
	a = np.clip(a * dens, 0, 1)
	# 收笔尖
	a *= 1.0 - smoothstep(0.975, 1.0, t)
	save_la(a, name)


# ================================================================ 祥云

def stroke(d, pts, w0, w1, ss, fill=255):
	"""锥形笔画：沿折线密集盖圆点，半径从 w0 渐变到 w1（像素，未乘 ss）。"""
	seg = []
	total = 0.0
	for i in range(len(pts) - 1):
		l = math.dist(pts[i], pts[i + 1])
		seg.append(l)
		total += l
	if total <= 0:
		return
	acc = 0.0
	for i in range(len(pts) - 1):
		n = max(2, int(seg[i] * 1.5))
		for k in range(n):
			t = k / n
			x = pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t
			y = pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t
			u = (acc + seg[i] * t) / total
			r = (w0 + (w1 - w0) * u) * 0.5
			d.ellipse([(x - r) * ss, (y - r) * ss, (x + r) * ss, (y + r) * ss], fill=fill)
		acc += seg[i]


def spiral_pts(cx, cy, r0, r1, a0, turns, n=120):
	pts = []
	for i in range(n + 1):
		t = i / n
		a = a0 + t * turns * math.tau
		r = r0 + (r1 - r0) * t
		pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
	return pts


def cloud_corner():
	"""窗口左上角的如意祥云：一大一小两股内卷云头 + 包络弧 + 沿边延伸的云尾。运行时按角翻转。"""
	S = 160

	def draw(d, ss):
		# 大云头：自左下外侧起笔，顺时针内卷
		stroke(d, spiral_pts(50, 50, 30, 3, math.radians(150), 1.3), 5.0, 2.0, ss)
		# 小云头：右上，逆时针内卷
		stroke(d, spiral_pts(92, 30, 15, 2, math.radians(200), -1.2), 3.6, 1.6, ss)
		# 小云头：左下
		stroke(d, spiral_pts(28, 94, 14, 2, math.radians(-40), 1.2), 3.6, 1.6, ss)
		# 包络：从小云头外缘沿大云头外侧的弧
		env = []
		for i in range(40):
			t = i / 39
			a = math.radians(-8 - t * 100)
			env.append((50 + math.cos(a) * 38, 50 + math.sin(a) * 38 * 1.02))
		stroke(d, env, 2.2, 3.4, ss)
		env2 = []
		for i in range(40):
			t = i / 39
			a = math.radians(100 + t * 95)
			env2.append((50 + math.cos(a) * 38, 50 + math.sin(a) * 38))
		stroke(d, env2, 3.4, 2.2, ss)
		# 云尾：沿上边、左边渐细
		stroke(d, [(106, 12), (130, 12), (156, 12)], 2.6, 0.6, ss)
		stroke(d, [(110, 20), (138, 20)], 1.4, 0.4, ss, 180)
		stroke(d, [(12, 110), (12, 132), (12, 156)], 2.6, 0.6, ss)
		stroke(d, [(20, 114), (20, 140)], 1.4, 0.4, ss, 180)
		# 角点菱形
		c = (7 * ss, 7 * ss)
		r = 5.5 * ss
		d.polygon([(c[0], c[1] - r), (c[0] + r, c[1]), (c[0], c[1] + r), (c[0] - r, c[1])], fill=255)
	a = supersample(draw, S, S)
	save_la(a, "cloud_corner.png")


def cloud_band():
	"""横向小祥云（标题两侧装饰）：云头在右端，尾线向左渐细。运行时水平翻转得到另一侧。"""
	W, H = 256, 64

	def draw(d, ss):
		stroke(d, spiral_pts(214, 30, 17, 2, math.radians(100), 1.25), 3.8, 1.4, ss)
		stroke(d, spiral_pts(186, 38, 10, 1.5, math.radians(-60), -1.15), 2.8, 1.2, ss)
		arc = []
		for i in range(30):
			t = i / 29
			a = math.radians(120 + t * 150)
			arc.append((214 + math.cos(a) * 24, 30 + math.sin(a) * 22))
		stroke(d, arc, 1.6, 2.6, ss)
		stroke(d, [(6, 48), (60, 48), (120, 48), (176, 48)], 0.4, 2.2, ss)
		stroke(d, [(70, 40), (120, 40), (164, 40)], 0.3, 1.4, ss, 170)
	a = supersample(draw, W, H)
	save_la(a, "cloud_band.png")


# ================================================================ 印章

def seal(shape, name):
	S = 128
	rng = np.random.default_rng(77 if shape == "square" else 78)
	yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
	c = S / 2
	n = periodic_noise(S, 10.0, 31 if shape == "square" else 32)
	n2 = periodic_noise(S, 3.0, 33)
	if shape == "square":
		d = np.maximum(np.abs(xx - c), np.abs(yy - c)) / (S * 0.44)
		# 略圆的角
		dx = np.maximum(np.abs(xx - c) - S * 0.36, 0)
		dy = np.maximum(np.abs(yy - c) - S * 0.36, 0)
		d = np.where((dx > 0) & (dy > 0), (S * 0.36 + np.sqrt(dx * dx + dy * dy)) / (S * 0.44), d)
	else:
		d = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / (S * 0.44)
	edge = d + (n - 0.5) * 0.09 + (n2 - 0.5) * 0.04
	body = 1.0 - smoothstep(0.97, 1.0, edge)
	# 内框留白（朱文边框：外框实，内侧一圈细白线）
	ring = np.exp(-((edge - 0.84) / 0.022) ** 2)
	body *= 1.0 - ring * 0.92
	# 印泥不匀：少量斑驳缺失
	blot = periodic_noise(S, 5.0, 35)
	body *= 1.0 - smoothstep(0.78, 0.9, blot) * 0.7
	body *= 0.88 + 0.12 * n2
	save_la(np.clip(body, 0, 1), name)


def ink_splash():
	S = 256
	rng = np.random.default_rng(41)
	yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
	c = S / 2
	ang = np.arctan2(yy - c, xx - c)
	r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / (S * 0.5)
	# 放射状毛刺：角向噪声
	spikes = np.zeros_like(r)
	for k in range(14):
		a0 = rng.uniform(-math.pi, math.pi)
		wv = rng.uniform(0.06, 0.14)
		ln = rng.uniform(0.1, 0.22)
		da = np.angle(np.exp(1j * (ang - a0)))
		spikes += np.exp(-(da / wv) ** 2) * ln
	n = fbm(S, 43, octaves=4, base=40.0)
	edge = r - 0.36 - spikes * 0.8 + (n - 0.5) * 0.18
	a = 1.0 - smoothstep(-0.02, 0.02, edge)
	# 墨滴
	img = Image.new("L", (S * 4, S * 4), 0)
	d = ImageDraw.Draw(img)
	for _ in range(26):
		aa = rng.uniform(-math.pi, math.pi)
		rr = rng.uniform(0.5, 0.92) * S * 0.5
		sz = rng.uniform(2, 7) * (1.2 - rr / (S * 0.5))
		x = (c + math.cos(aa) * rr) * 4
		y = (c + math.sin(aa) * rr) * 4
		d.ellipse([x - sz * 4, y - sz * 4, x + sz * 4, y + sz * 4], fill=255)
	drops = np.asarray(img.resize((S, S), Image.LANCZOS), np.float32) / 255.0
	a = np.clip(np.maximum(a, drops) * (0.85 + 0.15 * n), 0, 1)
	save_la(a, "ink_splash.png")


# ================================================================ 着色器噪声 / 玉

def noise_tex():
	S = 256
	r = fbm(S, 51, octaves=5, base=64.0)
	g = periodic_noise(S, 3.0, 52, aniso=(24.0, 1.0))           # 沿 x 拉长的毛笔丝
	g = (g - g.min()) / (g.max() - g.min())
	b = periodic_noise(S, 3.0, 53)
	# 裂纹：两层低频噪声的等值线
	c1 = periodic_noise(S, 30.0, 54)
	c2 = periodic_noise(S, 14.0, 55)
	crack = np.maximum(np.exp(-((c1 - 0.5) / 0.012) ** 2), np.exp(-((c2 - 0.5) / 0.01) ** 2) * 0.7)
	arr = np.stack([r, g, b, 1.0 - crack * 0.9], axis=-1)
	save_rgba(arr, "noise.png")


def jade():
	S = 256
	n = fbm(S, 61, octaves=5, base=90.0)
	vein = periodic_noise(S, 40.0, 62, aniso=(1.0, 0.5))
	vein = np.exp(-((vein - 0.5) / 0.05) ** 2) * 0.6
	cloud = fbm(S, 63, octaves=4, base=40.0)
	base = np.array([0.46, 0.72, 0.6])
	light = np.array([0.82, 0.93, 0.86])
	deep = np.array([0.16, 0.42, 0.34])
	t = smoothstep(0.3, 0.75, n)[..., None]
	col = deep * (1 - t) + base * t
	col = col * (1 - cloud[..., None] * 0.35) + light * (cloud[..., None] * 0.35)
	col = col * (1 - vein[..., None] * 0.35) + light * (vein[..., None] * 0.35)
	save_rgb(col, "jade.png")


# ================================================================ 罗盘

TRIGRAMS = [  # 先天八卦，自上（乾）顺时针；爻自内向外（初爻在内）
	(1, 1, 1), (0, 1, 1), (0, 1, 0), (0, 0, 1), (0, 0, 0), (1, 0, 0), (1, 0, 1), (1, 1, 0),
]


def compass():
	S = 512

	def draw(d, ss):
		c = S / 2 * ss

		def circ(r, w, fill=255):
			d.ellipse([c - r * ss, c - r * ss, c + r * ss, c + r * ss], outline=fill, width=max(1, int(w * ss)))
		circ(250, 3.0)
		circ(242, 1.2, 200)
		circ(208, 1.6)
		circ(168, 1.2, 200)
		circ(120, 1.0, 150)
		circ(62, 1.4, 220)
		circ(54, 0.8, 160)
		# 刻度：外环 360 细刻、24 山大刻
		for i in range(120):
			a = i / 120 * math.tau
			major = i % 5 == 0
			r0 = 242 if not major else 232
			w = 1.0 if not major else 2.2
			d.line([(c + math.cos(a) * r0 * ss, c + math.sin(a) * r0 * ss), (c + math.cos(a) * 248 * ss, c + math.sin(a) * 248 * ss)], fill=230 if major else 150, width=max(1, int(w * ss)))
		# 分隔线（24 山分格）
		for i in range(24):
			a = (i + 0.5) / 24 * math.tau
			d.line([(c + math.cos(a) * 208 * ss, c + math.sin(a) * 208 * ss), (c + math.cos(a) * 232 * ss, c + math.sin(a) * 232 * ss)], fill=160, width=max(1, int(1.0 * ss)))
		# 八卦（168..208 环带），乾在上（-90°）
		for k, tri in enumerate(TRIGRAMS):
			a = -math.pi / 2 + k * math.tau / 8
			tang = (-math.sin(a), math.cos(a))
			rad = (math.cos(a), math.sin(a))
			for j, yang in enumerate(tri):
				rr = 176 + j * 12
				half = 17
				cxx = c + rad[0] * rr * ss
				cyy = c + rad[1] * rr * ss
				segs = [(-half, half)] if yang else [(-half, -4), (4, half)]
				for s0, s1 in segs:
					p0 = (cxx + tang[0] * s0 * ss, cyy + tang[1] * s0 * ss)
					p1 = (cxx + tang[0] * s1 * ss, cyy + tang[1] * s1 * ss)
					d.line([p0, p1], fill=235, width=int(5.0 * ss))
			# 卦间分隔
			a2 = a + math.tau / 16
			d.line([(c + math.cos(a2) * 168 * ss, c + math.sin(a2) * 168 * ss), (c + math.cos(a2) * 208 * ss, c + math.sin(a2) * 208 * ss)], fill=120, width=max(1, int(1.0 * ss)))
		# 内环：十二细纹
		for i in range(72):
			a = i / 72 * math.tau
			d.line([(c + math.cos(a) * 120 * ss, c + math.sin(a) * 120 * ss), (c + math.cos(a) * (126 if i % 6 else 132) * ss, c + math.sin(a) * (126 if i % 6 else 132) * ss)], fill=120, width=max(1, int(1.0 * ss)))

	lines = supersample(draw, S, S, ss=3)
	yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
	r = np.sqrt((xx - S / 2) ** 2 + (yy - S / 2) ** 2)
	n = fbm(S, 71, octaves=4, base=60.0)
	disc = 1.0 - smoothstep(250, 253, r)
	# 盘面：深漆色 + 木纹斑驳，天池（中心）更深
	base = np.stack([0.09 + 0.04 * n, 0.075 + 0.03 * n, 0.06 + 0.02 * n], axis=-1)
	pool = smoothstep(62, 50, r)[..., None]
	base = base * (1 - pool * 0.5)
	band = ((r > 168) & (r < 208)).astype(np.float32)[..., None]
	base = base * (1 - band) + np.array([0.16, 0.11, 0.06]) * band * (0.8 + 0.2 * n[..., None])
	gold = np.array([0.93, 0.76, 0.42])
	col = base * (1 - lines[..., None]) + gold * lines[..., None]
	alpha = disc * (0.78 + lines * 0.22)
	arr = np.concatenate([col, alpha[..., None]], axis=-1)
	save_rgba(arr, "compass.png")


# ================================================================ 窗棂格

def lattice_cell():
	"""64×64 的单格窗棂：凹陷格心 + 木棂边框 + 四角榫卯小方块（运行时着色）。"""
	S = 64

	def draw(d, ss):
		def R(x0, y0, x1, y1, v):
			d.rectangle([x0 * ss, y0 * ss, x1 * ss - 1, y1 * ss - 1], fill=v)
		R(0, 0, 64, 64, 255)       # 木棂
		R(4, 4, 60, 60, 70)        # 格心（凹）
		R(6, 6, 58, 58, 40)
		# 内侧回纹角（小）
		for (x, y, sx, sy) in [(6, 6, 1, 1), (58, 6, -1, 1), (6, 58, 1, -1), (58, 58, -1, -1)]:
			for (a, b, w, h) in [(0, 0, 9, 1.4), (0, 0, 1.4, 9), (3, 3, 4, 1), (3, 3, 1, 4)]:
				x0 = x + a * sx
				y0 = y + b * sy
				x1 = x + (a + w) * sx
				y1 = y + (b + h) * sy
				R(min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1), 150)
	a = supersample(draw, S, S, ss=4)
	save_la(a, "lattice_cell.png")


def main():
	os.makedirs(OUT, exist_ok=True)
	print("生成界面纹理 →", OUT)
	paper()
	ink_wash()
	brush_stroke(1024, 128, 101, "brush_stroke.png", dry_tail=0.38, bristle=1.0, head_blob=0.28)
	brush_stroke(512, 32, 202, "brush_thin.png", dry_tail=0.3, bristle=1.4, head_blob=0.15)
	cloud_corner()
	cloud_band()
	seal("square", "seal_square.png")
	seal("round", "seal_round.png")
	ink_splash()
	noise_tex()
	jade()
	compass()
	lattice_cell()


if __name__ == "__main__":
	main()
