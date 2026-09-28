#!/usr/bin/env python3
"""程序化生成音效：assets/audio/sfx/<name>.wav（单声道 16-bit 44.1 kHz）。

用法：python3 tools/gen_sfx.py [名字 ...]      （不带参数则生成全部）
依赖：numpy、scipy、soundfile（pip install numpy scipy soundfile）

每个音效由若干层叠加：瞬态（click/thump）+ 滤波噪声 + 音高扫频 + 加性合成（钟/磬）+ Karplus-Strong 拨弦。
随机数种子由音效名决定，结果完全确定。输出统一去直流、淡入淡出、按目标峰值归一化，不会削波。
本文件同时提供 DSP 工具函数，供 tools/gen_music.py 复用。
"""
import os
import sys
import zlib

import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "audio", "sfx")


# ============================================================== DSP 工具

def n_of(dur):
    return max(int(round(dur * SR)), 1)


def tt(dur):
    return np.arange(n_of(dur)) / SR


def rng_for(name):
    return np.random.default_rng(zlib.crc32(name.encode("utf-8")))


def exp_env(dur, tau, attack=0.002):
    t = tt(dur)
    e = np.exp(-t / max(tau, 1e-4))
    if attack > 0:
        e *= np.clip(t / attack, 0.0, 1.0)
    return e


def adsr(dur, a=0.01, d=0.1, s=0.7, r=0.1):
    n = n_of(dur)
    t = np.arange(n) / SR
    e = np.full(n, s, dtype=float)
    e[t < a] = t[t < a] / max(a, 1e-6)
    m = (t >= a) & (t < a + d)
    e[m] = 1.0 - (1.0 - s) * (t[m] - a) / max(d, 1e-6)
    rel = t > dur - r
    e[rel] *= np.clip((dur - t[rel]) / max(r, 1e-6), 0.0, 1.0)
    return e


def osc(freq, dur, shape="sine", phase0=0.0):
    """freq 可为标量或逐样本数组（扫频）。"""
    n = n_of(dur)
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,)) if np.ndim(freq) == 0 else np.asarray(freq, dtype=float)[:n]
    ph = phase0 + 2 * np.pi * np.cumsum(f) / SR
    if shape == "sine":
        return np.sin(ph)
    if shape == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if shape == "saw":
        # 频带受限的近似：前 12 次谐波
        out = np.zeros(n)
        for k in range(1, 13):
            out += np.sin(k * ph) / k * (f * k < SR * 0.45)
        return out * 0.6
    if shape == "square":
        out = np.zeros(n)
        for k in range(1, 14, 2):
            out += np.sin(k * ph) / k * (f * k < SR * 0.45)
        return out * 0.8
    raise ValueError(shape)


def sweep(f0, f1, dur, curve="exp"):
    t = tt(dur) / max(dur, 1e-6)
    if curve == "exp":
        return f0 * (f1 / f0) ** t
    return f0 + (f1 - f0) * t


def noise(dur, rng):
    return rng.standard_normal(n_of(dur))


def _sos(btype, fc, order=2):
    nyq = SR / 2
    if btype == "bandpass":
        lo, hi = fc
        lo = max(lo, 10.0)
        hi = min(hi, nyq * 0.98)
        return signal.butter(order, [lo / nyq, hi / nyq], btype="bandpass", output="sos")
    return signal.butter(order, min(fc, nyq * 0.98) / nyq, btype=btype, output="sos")


def lp(x, fc, order=2):
    return signal.sosfilt(_sos("lowpass", fc, order), x)


def hp(x, fc, order=2):
    return signal.sosfilt(_sos("highpass", fc, order), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bandpass", (lo, hi), order), x)


def peak_eq(x, fc, q, gain_db):
    """RBJ 峰值均衡（共振峰）。"""
    a = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * fc / SR
    alpha = np.sin(w0) / (2 * q)
    b = [1 + alpha * a, -2 * np.cos(w0), 1 - alpha * a]
    den = [1 + alpha / a, -2 * np.cos(w0), 1 - alpha / a]
    return signal.lfilter(b, den, x)


def sweep_filter(x, freqs, btype="bandpass", q=4.0, block=128):
    """时变滤波：逐块更新系数并延续滤波器状态。freqs 为逐样本中心/截止频率。"""
    freqs = np.broadcast_to(np.asarray(freqs, dtype=float), x.shape)
    out = np.zeros_like(x)
    zi = None
    for s in range(0, len(x), block):
        fc = float(np.clip(freqs[s], 30.0, SR * 0.45))
        if btype == "bandpass":
            bw = fc / q
            sos = _sos("bandpass", (max(fc - bw / 2, 20.0), fc + bw / 2), 1)
        else:
            sos = _sos(btype, fc, 2)
        if zi is None or zi.shape[0] != sos.shape[0]:
            zi = np.zeros((sos.shape[0], 2))
        out[s:s + block], zi = signal.sosfilt(sos, x[s:s + block], zi=zi)
    return out


def pad_to(x, n):
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def at(x, sec):
    """把信号延后 sec 秒。"""
    return np.concatenate([np.zeros(n_of(sec) if sec > 0 else 0), x])


def tail_fade(x, max_sec=0.03):
    """层尾淡出，避免被截断的衰减音产生咔哒声。"""
    n = min(n_of(max_sec), len(x) // 4)
    if n > 1:
        x = x.copy()
        x[-n:] *= np.cos(np.linspace(0, np.pi / 2, n)) ** 2
    return x


def mix(*layers):
    n = max(len(l) for l in layers)
    out = np.zeros(n)
    for l in layers:
        out[:len(l)] += tail_fade(l)
    return out


def fade(x, fin=0.002, fout=0.02):
    x = x.copy()
    a, b = min(n_of(fin), len(x)), min(n_of(fout), len(x))
    if a > 1:
        x[:a] *= np.linspace(0, 1, a)
    if b > 1:
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def reverb_ir(rt, rng, bright=6000.0, pre=0.01):
    """指数衰减噪声脉冲响应（高频衰减更快）。"""
    n = n_of(rt * 1.2)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-6.9 * t / rt)
    ir = lp(ir, bright) * 0.6 + lp(ir, bright * 0.3) * 0.4
    ir = np.concatenate([np.zeros(n_of(pre)), ir])
    return ir / np.sqrt(np.sum(ir ** 2) + 1e-12)


def reverb(x, rt, wet, rng, bright=6000.0):
    ir = reverb_ir(rt, rng, bright)
    y = signal.fftconvolve(np.concatenate([x, np.zeros(len(ir))]), ir)[:len(x) + len(ir)]
    dry = np.concatenate([x, np.zeros(len(ir))])
    return dry * (1 - wet * 0.5) + y * wet * 0.5


def trim_tail(x, thresh_db=-54.0):
    thr = 10 ** (thresh_db / 20) * (np.max(np.abs(x)) + 1e-12)
    idx = np.nonzero(np.abs(x) > thr)[0]
    if len(idx) == 0:
        return x
    return x[:min(idx[-1] + n_of(0.01), len(x))]


def normalize(x, peak=0.89):
    x = x - np.mean(x)
    m = np.max(np.abs(x))
    return x if m < 1e-9 else x * (peak / m)


# ---------------------------------------------------------- 音源

def ks_pluck(freq, dur, rng, bright=0.6, t60=2.0, pick=0.2, noise_mix=1.0, attack_noise=0.3):
    """向量化 Karplus-Strong 拨弦。四抽头低通环路 + 分数延时，音准精确。
    bright：激励亮度 0~1；t60：基频衰减 60 dB 的时间；pick：拨弦位置（梳状）。"""
    period = SR / freq
    base = int(np.floor(period))
    u = period - base
    nd = max(base - 1, 2)
    k = (1 - u) * np.array([0.25, 0.5, 0.25, 0.0]) + u * np.array([0.0, 0.25, 0.5, 0.25])
    g = 10 ** (-3.0 / (t60 * freq))
    total = n_of(dur)
    y = np.zeros(total + nd + 8)
    exc_len = nd + 3
    ex = rng.standard_normal(exc_len) * noise_mix
    # 激励亮度：与平滑后的噪声混合
    sm = np.convolve(ex, np.ones(4) / 4, mode="same")
    ex = bright * ex + (1 - bright) * sm
    # 拨弦位置梳状
    d = max(int(pick * exc_len), 1)
    ex = ex - np.concatenate([np.zeros(d), ex[:-d]]) * 0.9
    y[:exc_len] = ex - np.mean(ex)
    n = exc_len
    while n < len(y):
        m = min(nd, len(y) - n)
        acc = k[0] * y[n - nd:n - nd + m] + k[1] * y[n - nd - 1:n - nd - 1 + m] + k[2] * y[n - nd - 2:n - nd - 2 + m] + k[3] * y[n - nd - 3:n - nd - 3 + m]
        y[n:n + m] = g * acc
        n += m
    out = y[exc_len:exc_len + total]
    out = np.concatenate([y[:exc_len] * attack_noise, out])[:total]
    return out / (np.max(np.abs(out)) + 1e-9)


def bell(freq, dur, partials=None, decay=1.2, rng=None):
    """加性合成钟磬：partials = [(频率比, 振幅, 衰减系数)]。"""
    if partials is None:
        partials = [(1.0, 1.0, 1.0), (2.0, 0.5, 0.7), (2.76, 0.45, 0.55), (5.4, 0.25, 0.3), (8.93, 0.12, 0.2)]
    t = tt(dur)
    out = np.zeros_like(t)
    for ratio, amp, dk in partials:
        f = freq * ratio
        if f > SR * 0.45:
            continue
        ph = rng.uniform(0, 2 * np.pi) if rng is not None else 0.0
        out += amp * np.sin(2 * np.pi * f * t + ph) * np.exp(-t / (decay * dk))
    return out * np.clip(t / 0.002, 0, 1)


def thump(f0, f1, dur, tau):
    """低频冲击：快速下滑的正弦。"""
    fr = f1 + (f0 - f1) * np.exp(-tt(dur) / (tau * 0.25))
    return osc(fr, dur) * exp_env(dur, tau, 0.001)


def click(rng, dur=0.004, fc=4000.0):
    return hp(noise(dur, rng), fc) * np.linspace(1, 0, n_of(dur))


def whoosh(dur, rng, f0, f1, q=2.0, curve=None):
    """气流声：带通噪声，中心频率扫动，包络为钟形。"""
    t = tt(dur) / dur
    fr = f0 * (f1 / f0) ** t if curve is None else curve(t)
    x = sweep_filter(noise(dur, rng), fr, "bandpass", q)
    env = np.sin(np.pi * np.clip(t, 0, 1)) ** 1.5
    return x * env


def crackle(dur, rng, density=60.0, fc=3000.0):
    n = n_of(dur)
    x = np.zeros(n)
    count = int(density * dur)
    for _ in range(count):
        p = rng.integers(0, n)
        L = rng.integers(20, 200)
        seg = rng.standard_normal(L) * np.exp(-np.arange(L) / (L / 4)) * rng.uniform(0.3, 1.0)
        e = min(p + L, n)
        x[p:e] += seg[:e - p]
    return hp(x, fc)


def notes_hz(root, semis):
    return [root * 2 ** (s / 12) for s in semis]


# ============================================================== 音效定义

def s_ui_click(r):
    body = osc(sweep(2200, 1500, 0.05), 0.05) * exp_env(0.05, 0.012)
    return mix(click(r, 0.003, 3000) * 0.6, body * 0.7)


def s_ui_hover(r):
    return osc(2900, 0.04) * exp_env(0.04, 0.01, 0.003) * 0.5 + osc(4350, 0.04) * exp_env(0.04, 0.006) * 0.2


def s_ui_open(r):
    fs = notes_hz(880, [0, 5, 9])  # 柔和的上行三音（磬）
    layers = [at(bell(f, 0.5, decay=0.35, rng=r) * (0.9 - i * 0.15), i * 0.045) for i, f in enumerate(fs)]
    air = whoosh(0.3, r, 800, 5000, 1.5) * 0.25
    return reverb(mix(*layers, air), 0.8, 0.35, r)


def s_ui_close(r):
    fs = notes_hz(1175, [0, -5])
    layers = [at(bell(f, 0.4, decay=0.25, rng=r) * (0.9 - i * 0.2), i * 0.05) for i, f in enumerate(fs)]
    air = whoosh(0.22, r, 4000, 700, 1.5) * 0.25
    return reverb(mix(*layers, air), 0.6, 0.3, r)


def s_equip(r):
    # 金属出鞘：高频“铮”+ 刮擦噪声 + 低沉落位
    scrape = sweep_filter(noise(0.28, r), sweep(3000, 8000, 0.28), "bandpass", 6) * adsr(0.28, 0.02, 0.1, 0.6, 0.12) * 0.5
    ring = bell(1760, 0.6, [(1, 1, 1), (2.41, 0.6, 0.6), (3.87, 0.4, 0.4), (5.9, 0.3, 0.25)], 0.35, r)
    return mix(scrape, at(ring * 0.8, 0.12), at(thump(180, 90, 0.15, 0.05) * 0.5, 0.12))


def s_pickup(r):
    a = osc(sweep(900, 1400, 0.08), 0.08) * exp_env(0.08, 0.04)
    b = at(osc(1760, 0.18) * exp_env(0.18, 0.06) * 0.8, 0.06)
    soft = lp(noise(0.05, r), 2500) * exp_env(0.05, 0.01) * 0.3
    return mix(soft, a * 0.7, b)


def s_coin(r):
    # 铜钱相击：两三枚短促的金属叮当
    part = [(1, 1, 1), (2.32, 0.6, 0.6), (3.95, 0.4, 0.4), (6.1, 0.25, 0.25)]
    layers = []
    for i, (f, dt) in enumerate([(2350, 0.0), (3140, 0.07), (2790, 0.12)]):
        layers.append(at(bell(f * r.uniform(0.98, 1.02), 0.4, part, 0.12, r) * (1.0 - 0.2 * i), dt))
    return mix(*layers, click(r, 0.002, 5000) * 0.4)


def s_error(r):
    b = []
    for i in range(2):
        tone = osc(185, 0.11, "square") * adsr(0.11, 0.005, 0.03, 0.8, 0.03)
        b.append(at(lp(tone, 1800), i * 0.14))
    return mix(*b) * 0.8


def s_notify(r):
    a = bell(1318, 0.9, decay=0.5, rng=r)
    b = at(bell(1760, 0.9, decay=0.45, rng=r) * 0.7, 0.09)
    return reverb(mix(a, b), 1.2, 0.35, r)


def s_quest_complete(r):
    # 宫商角徵羽上行 + 泛音闪烁
    fs = notes_hz(587.3, [0, 2, 4, 7, 9, 12])
    layers = [at(bell(f, 1.2, decay=0.6, rng=r) * 0.8, i * 0.085) for i, f in enumerate(fs)]
    pl = [at(ks_pluck(f / 2, 1.5, r, 0.5, 1.8) * 0.5, i * 0.085) for i, f in enumerate(fs[::2])]
    sh = at(hp(noise(0.9, r), 6000) * adsr(0.9, 0.3, 0.2, 0.5, 0.4) * 0.08, 0.3)
    chord = at(mix(*[bell(f, 1.4, decay=0.8, rng=r) * 0.35 for f in notes_hz(1174.7, [0, 4, 7])]), 0.55)
    return reverb(mix(*layers, *pl, sh, chord), 1.6, 0.4, r)


def s_swing_light(r):
    return whoosh(0.22, r, 700, 3200, 3.0, lambda t: 600 + 3200 * np.sin(np.pi * t) ** 2) * 1.0


def s_swing_heavy(r):
    w = whoosh(0.42, r, 300, 1500, 2.0, lambda t: 250 + 1400 * np.sin(np.pi * t) ** 2)
    low = lp(noise(0.42, r), 250) * np.sin(np.pi * tt(0.42) / 0.42) ** 2 * 1.5
    return mix(w, low)


def s_hit_flesh(r):
    body = thump(140, 55, 0.25, 0.08)
    smack = lp(noise(0.06, r), 1800) * exp_env(0.06, 0.012)
    crunch = bp(noise(0.08, r), 400, 1400) * exp_env(0.08, 0.02) * 0.6
    return mix(body * 1.0, smack * 0.9, crunch, click(r, 0.002, 2000) * 0.3)


def s_hit_metal(r):
    part = [(1, 1, 1), (2.76, 0.7, 0.7), (5.4, 0.5, 0.45), (8.93, 0.35, 0.3), (13.3, 0.2, 0.2)]
    ring = bell(620 * r.uniform(0.97, 1.03), 0.7, part, 0.25, r)
    tr = hp(noise(0.03, r), 2500) * exp_env(0.03, 0.006)
    body = thump(220, 120, 0.12, 0.03)
    return mix(ring * 0.8, tr * 0.9, body * 0.5)


def s_hit_shield(r):
    f = sweep(520, 300, 0.35)
    tone = (osc(f, 0.35) + osc(f * 1.007, 0.35) * 0.8 + osc(f * 2.01, 0.35) * 0.3) * exp_env(0.35, 0.09)
    shimmer = hp(noise(0.3, r), 5000) * exp_env(0.3, 0.05) * 0.25
    return reverb(mix(tone * 0.6, shimmer, thump(160, 80, 0.12, 0.03) * 0.5), 0.5, 0.25, r)


def s_shield_break(r):
    layers = [hp(noise(0.25, r), 3000) * exp_env(0.25, 0.06) * 0.6]
    for _ in range(26):
        f = r.uniform(2500, 8000)
        d = r.uniform(0.0, 0.35)
        layers.append(at(osc(f, 0.2) * exp_env(0.2, r.uniform(0.02, 0.07)) * r.uniform(0.1, 0.35), d))
    fall = osc(sweep(900, 180, 0.6), 0.6) * exp_env(0.6, 0.2) * 0.5
    layers.append(fall)
    layers.append(thump(200, 60, 0.3, 0.08) * 0.8)
    return reverb(mix(*layers), 0.9, 0.3, r)


def s_crit(r):
    hit = s_hit_flesh(r)
    zing = osc(sweep(3400, 1400, 0.35), 0.35) * exp_env(0.35, 0.09) * 0.5
    ring = bell(1245, 0.5, [(1, 1, 1), (2.76, 0.5, 0.6), (5.4, 0.3, 0.4)], 0.2, r) * 0.5
    slash = whoosh(0.12, r, 5000, 1500, 3.0) * 0.8
    return mix(slash, at(hit * 1.0, 0.02), at(zing, 0.02), at(ring, 0.02))


def s_bolt_fire(r):
    f = sweep(1100, 280, 0.25)
    tone = (osc(f, 0.25) + 0.3 * osc(f * 1.5, 0.25)) * exp_env(0.25, 0.08)
    air = whoosh(0.25, r, 3000, 900, 2.0) * 0.6
    return mix(tone * 0.7, air, thump(180, 90, 0.08, 0.025) * 0.5)


def s_bolt_hit(r):
    pop = thump(420, 90, 0.25, 0.05)
    burst = bp(noise(0.2, r), 600, 4000) * exp_env(0.2, 0.04)
    sh = osc(sweep(1800, 600, 0.15), 0.15) * exp_env(0.15, 0.04) * 0.4
    return reverb(mix(pop * 0.8, burst * 0.7, sh), 0.4, 0.2, r)


def s_bolt_charge(r):
    d = 1.0
    f = sweep(180, 900, d)
    trem = 1 + 0.3 * np.sin(2 * np.pi * np.cumsum(sweep(6, 22, d)) / SR)
    tone = (osc(f, d) + 0.5 * osc(f * 1.5, d) + 0.25 * osc(f * 2.02, d)) * trem
    hiss = sweep_filter(noise(d, r), sweep(500, 6000, d), "bandpass", 3) * 0.6
    env = np.clip(tt(d) / d, 0, 1) ** 1.3
    return fade(mix(tone * 0.35, hiss) * env, 0.01, 0.05)


def s_cast(r):
    d = 0.7
    fs = [440, 554, 659, 880]
    sh = mix(*[osc(sweep(f * 0.8, f * 1.25, d), d) * 0.2 for f in fs])
    env = adsr(d, 0.05, 0.2, 0.6, 0.35)
    air = whoosh(0.5, r, 400, 5000, 2.0) * 0.6
    sparkle = hp(noise(d, r), 7000) * env * 0.15
    return reverb(mix(sh * env, air, sparkle), 1.0, 0.35, r)


def s_summon(r):
    d = 1.0
    low = (osc(sweep(55, 110, d), d) + 0.5 * osc(sweep(82.5, 165, d), d)) * adsr(d, 0.3, 0.3, 0.7, 0.4)
    rise = whoosh(0.9, r, 200, 3000, 2.0)
    b = at(bell(880, 1.0, decay=0.5, rng=r) * 0.6, 0.55)
    b2 = at(bell(1318, 1.0, decay=0.4, rng=r) * 0.4, 0.62)
    return reverb(mix(low * 0.5, rise * 0.6, b, b2), 1.4, 0.4, r)


def s_heal(r):
    fs = notes_hz(784, [0, 2, 4, 7, 9])
    layers = [at(bell(f, 0.9, [(1, 1, 1), (2, 0.3, 0.6), (3, 0.15, 0.4)], 0.5, r) * 0.5, i * 0.07) for i, f in enumerate(fs)]
    pad = mix(*[osc(f / 2, 0.9) for f in fs[:3]]) * adsr(0.9, 0.2, 0.2, 0.6, 0.45) * 0.15
    sparkle = hp(noise(0.9, r), 7000) * adsr(0.9, 0.3, 0.2, 0.5, 0.3) * 0.1
    return reverb(mix(pad, sparkle, *layers), 1.5, 0.4, r)


def s_buff(r):
    d = 0.55
    tone = (osc(sweep(330, 990, d), d) + 0.5 * osc(sweep(495, 1485, d), d)) * adsr(d, 0.03, 0.15, 0.6, 0.25) * 0.4
    b = at(bell(1568, 0.6, decay=0.3, rng=r) * 0.6, 0.25)
    return reverb(mix(tone, b, whoosh(0.4, r, 600, 4000, 2.0) * 0.4), 0.9, 0.3, r)


def s_boost_start(r):
    d = 0.55
    roar = sweep_filter(noise(d, r), sweep(300, 2500, d), "lowpass") * adsr(d, 0.03, 0.2, 0.6, 0.3)
    low = thump(120, 50, d, 0.18)
    air = hp(noise(d, r), 3000) * adsr(d, 0.01, 0.1, 0.3, 0.3) * 0.3
    return mix(roar * 0.9, low * 0.8, air)


def s_quick_boost(r):
    d = 0.26
    burst = bp(noise(d, r), 400, 5000) * exp_env(d, 0.05, 0.004)
    low = thump(160, 60, d, 0.05)
    return mix(burst * 0.9, low * 0.8, whoosh(d, r, 3000, 600, 2.0) * 0.5)


def s_jump(r):
    return mix(whoosh(0.2, r, 500, 2000, 2.0) * 0.8, thump(110, 70, 0.1, 0.025) * 0.5)


def s_land(r):
    body = thump(120, 45, 0.22, 0.05)
    dust = lp(noise(0.18, r), 900) * exp_env(0.18, 0.04)
    return mix(body, dust * 0.6)


def s_footstep(r):
    tap = bp(noise(0.08, r), 200, 1500) * exp_env(0.08, 0.015, 0.002)
    return mix(tap * 0.9, thump(90, 60, 0.07, 0.015) * 0.5)


def s_fly_whoosh(r):
    d = 1.2
    t = tt(d)
    fr = 500 + 700 * np.sin(np.pi * t / d) + 120 * np.sin(2 * np.pi * 1.7 * t)
    w = sweep_filter(noise(d, r), fr, "bandpass", 1.5)
    env = np.sin(np.pi * t / d) ** 1.2 * (1 + 0.25 * np.sin(2 * np.pi * 2.3 * t))
    return mix(w * env, lp(noise(d, r), 200) * env * 0.8)


def s_explosion(r):
    d = 1.6
    boom = thump(90, 28, d, 0.45)
    body = lp(noise(d, r), 700) * exp_env(d, 0.35, 0.003)
    mid = bp(noise(0.5, r), 300, 3000) * exp_env(0.5, 0.08)
    cr = crackle(1.2, r, 50, 1500) * exp_env(1.2, 0.4) * 0.5
    return reverb(mix(boom * 1.2, body * 1.2, mid * 0.6, at(cr, 0.05)), 1.8, 0.3, r, 3000)


def s_fire_cast(r):
    d = 0.8
    roar = sweep_filter(noise(d, r), sweep(400, 2200, d), "lowpass") * adsr(d, 0.08, 0.2, 0.7, 0.4)
    cr = crackle(d, r, 90, 2500) * adsr(d, 0.05, 0.2, 0.7, 0.3) * 0.6
    return reverb(mix(roar, cr, whoosh(0.5, r, 300, 2500, 1.5) * 0.5), 0.8, 0.2, r)


def s_ice_cast(r):
    layers = [hp(noise(0.8, r), 4000) * adsr(0.8, 0.05, 0.3, 0.3, 0.4) * 0.25]
    for i in range(14):
        f = r.uniform(2000, 6500)
        layers.append(at(bell(f, 0.6, [(1, 1, 1), (2.76, 0.4, 0.5), (5.4, 0.2, 0.3)], r.uniform(0.08, 0.2), r) * r.uniform(0.15, 0.4), r.uniform(0, 0.45)))
    crack = at(bp(noise(0.05, r), 1500, 6000) * exp_env(0.05, 0.01) * 0.8, 0.02)
    return reverb(mix(*layers, crack), 1.2, 0.35, r, 8000)


def s_wind_blade(r):
    d = 0.42
    whistle = sweep_filter(noise(d, r), sweep(1500, 5500, d), "bandpass", 14) * 3.0
    env = np.sin(np.pi * tt(d) / d) ** 2
    slice_ = whoosh(d, r, 5000, 1200, 3.0) * 0.6
    return mix(whistle * env, slice_)


def s_vine(r):
    d = 0.75
    rust = bp(noise(d, r), 1500, 6000) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 7 * tt(d)))) * adsr(d, 0.05, 0.2, 0.6, 0.3) * 0.4
    creak_f = 120 + 60 * np.sin(2 * np.pi * 1.3 * tt(d)) + r.standard_normal(n_of(d)).cumsum() * 0.02
    creak = osc(creak_f, d, "saw")
    creak = bp(creak * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 23 * tt(d)))), 300, 2500) * adsr(d, 0.1, 0.2, 0.7, 0.3) * 0.4
    snap = at(bp(noise(0.03, r), 800, 4000) * exp_env(0.03, 0.006), 0.05)
    return mix(rust, creak, snap)


def s_earth_quake(r):
    d = 1.6
    rumble = lp(noise(d, r), 120, 4) * adsr(d, 0.08, 0.4, 0.7, 0.8) * 3.0
    hits = [thump(80, 40, 0.5, 0.15) * 1.0]
    for _ in range(6):
        hits.append(at(bp(noise(0.12, r), 150, 1200) * exp_env(0.12, 0.03) * r.uniform(0.2, 0.5), r.uniform(0.05, 1.0)))
    return mix(rumble, *hits)


def s_water_splash(r):
    d = 0.7
    body = bp(noise(d, r), 400, 5000) * exp_env(d, 0.12, 0.003)
    low = thump(150, 70, 0.2, 0.05) * 0.5
    drops = []
    for _ in range(12):
        f0 = r.uniform(700, 1800)
        dd = r.uniform(0.04, 0.09)
        drops.append(at(osc(sweep(f0, f0 * 2.2, dd), dd) * exp_env(dd, dd / 3) * r.uniform(0.1, 0.3), r.uniform(0.05, 0.55)))
    return reverb(mix(body * 0.8, low, *drops), 0.6, 0.25, r)


def s_thunder(r):
    d = 2.2
    crack = hp(noise(0.25, r), 1200) * exp_env(0.25, 0.04, 0.001) * 1.2
    zap = crackle(0.3, r, 400, 2000) * 0.8
    rumble = lp(noise(d, r), 180, 4) * (np.exp(-tt(d) / 0.9) * (1 + 0.5 * np.sin(2 * np.pi * 3.1 * tt(d)))) * 3.0
    rumble = rumble * np.clip(tt(d) / 0.08, 0, 1)
    return reverb(mix(crack, zap, at(rumble, 0.05), thump(70, 30, 1.2, 0.4) * 0.8), 2.0, 0.3, r, 2500)


def s_death(r):
    d = 1.1
    fall = (osc(sweep(260, 70, d), d, "tri") + 0.4 * osc(sweep(390, 105, d), d)) * adsr(d, 0.02, 0.3, 0.6, 0.6) * 0.6
    body = at(s_land(r) * 0.8, 0.55)
    air = whoosh(0.6, r, 2000, 300, 2.0) * 0.4
    return reverb(mix(fall, air, body), 1.2, 0.3, r)


def _formant_voice(f0, d, formants, r, rough=0.0):
    src = osc(f0, d, "saw")
    if rough > 0:
        src *= 1 + rough * lp(r.standard_normal(n_of(d)), 60) * 3
    out = np.zeros(n_of(d))
    for fc, gain in formants:
        out += bp(src, fc * 0.85, fc * 1.15) * gain
    return out


def s_beast_growl(r):
    d = 0.95
    f0 = 85 + 15 * np.sin(2 * np.pi * 0.9 * tt(d)) + lp(r.standard_normal(n_of(d)), 30) * 40
    v = _formant_voice(f0, d, [(400, 1.0), (900, 0.6), (2300, 0.25)], r, 0.5)
    env = adsr(d, 0.12, 0.2, 0.8, 0.35) * (1 + 0.4 * np.sin(2 * np.pi * 18 * tt(d)))
    breath = bp(noise(d, r), 300, 2000) * adsr(d, 0.1, 0.2, 0.6, 0.3) * 0.3
    return mix(v * env, breath)


def s_beast_bite(r):
    snap = bp(noise(0.03, r), 1000, 6000) * exp_env(0.03, 0.005) * 1.2
    clack = at(bell(900, 0.08, [(1, 1, 1), (2.3, 0.5, 0.5)], 0.02, r) * 0.6, 0.01)
    tear = at(bp(noise(0.2, r), 500, 3000) * exp_env(0.2, 0.05) * 0.6, 0.03)
    return mix(snap, clack, tear, thump(150, 70, 0.1, 0.025) * 0.6)


def s_beast_hurt(r):
    d = 0.42
    tt_ = tt(d) / d
    f0 = 380 + 380 * np.sin(np.pi * np.clip(tt_ * 1.4, 0, 1)) - 150 * tt_
    v = _formant_voice(f0, d, [(700, 1.0), (1200, 0.7), (2600, 0.3)], r, 0.3)
    return v * adsr(d, 0.02, 0.1, 0.7, 0.2)


def s_levelup(r):
    fs = notes_hz(523.25, [0, 4, 7, 12, 16])
    layers = [at(bell(f, 1.2, decay=0.5, rng=r) * 0.6, i * 0.07) for i, f in enumerate(fs)]
    rise = osc(sweep(260, 1040, 0.5), 0.5) * adsr(0.5, 0.05, 0.1, 0.5, 0.2) * 0.2
    sh = at(hp(noise(1.0, r), 6000) * adsr(1.0, 0.2, 0.3, 0.4, 0.5) * 0.12, 0.2)
    return reverb(mix(rise, sh, *layers), 1.6, 0.4, r)


def s_breakthrough(r):
    d = 3.0
    boom = thump(70, 30, 1.5, 0.6) * 1.2
    swell_env = np.clip(tt(d) / 1.4, 0, 1) ** 2 * np.exp(-np.clip(tt(d) - 1.6, 0, None) / 0.6)
    chord = mix(*[osc(f, d) + 0.3 * osc(f * 2.003, d) for f in notes_hz(146.8, [0, 7, 12, 16, 19])]) * swell_env * 0.2
    rise = whoosh(1.6, r, 150, 6000, 1.5) * 0.8
    bells = [at(bell(f, 2.0, decay=1.0, rng=r) * 0.5, 1.45 + i * 0.06) for i, f in enumerate(notes_hz(587.3, [0, 4, 7, 12]))]
    gong = at(bell(98, 2.5, [(1, 1, 1), (1.47, 0.6, 0.8), (2.09, 0.5, 0.6), (2.56, 0.4, 0.5), (3.37, 0.3, 0.4)], 1.2, r) * 0.6, 1.45)
    return reverb(mix(boom, chord, rise, gong, *bells), 2.5, 0.4, r)


def s_rock_break(r):
    crack = bp(noise(0.08, r), 800, 6000) * exp_env(0.08, 0.015, 0.001) * 1.2
    body = mix(thump(110, 50, 0.3, 0.07), lp(noise(0.3, r), 600) * exp_env(0.3, 0.06) * 0.8)
    debris = []
    for _ in range(16):
        f = r.uniform(600, 3000)
        debris.append(at(lp(bp(noise(0.07, r), f * 0.7, f * 1.3), 3500) * exp_env(0.07, 0.015) * r.uniform(0.2, 0.6), r.uniform(0.03, 0.6)))
    return mix(crack, body, *debris)


def s_wood_break(r):
    crack = bp(noise(0.06, r), 1000, 5000) * exp_env(0.06, 0.01, 0.001) * 1.2
    creak = bp(osc(sweep(260, 140, 0.35), 0.35, "saw"), 300, 2000) * exp_env(0.35, 0.12) * 0.4
    body = bell(210, 0.3, [(1, 1, 1), (2.3, 0.5, 0.5), (3.9, 0.3, 0.3)], 0.06, r) * 0.6
    splint = [at(bp(noise(0.04, r), 1500, 7000) * exp_env(0.04, 0.008) * r.uniform(0.1, 0.4), r.uniform(0.02, 0.5)) for _ in range(10)]
    return mix(crack, body, at(creak, 0.03), *splint)


def s_search_tick(r):
    return bell(1200, 0.06, [(1, 1, 1), (2.6, 0.3, 0.5)], 0.015, r) * 0.8 + pad_to(click(r, 0.002, 3000) * 0.3, n_of(0.06))


def s_search_done(r):
    a = bell(1046.5, 0.7, decay=0.35, rng=r)
    b = at(bell(1568, 0.7, decay=0.35, rng=r) * 0.8, 0.1)
    return reverb(mix(a, b, ks_pluck(523.25, 0.7, r, 0.5, 1.0) * 0.3), 0.9, 0.3, r)


def s_extract(r):
    d = 1.6
    rise = whoosh(1.4, r, 200, 7000, 1.5) * 0.8
    tone = mix(*[osc(sweep(f, f * 2, d), d) for f in notes_hz(220, [0, 7, 12])]) * adsr(d, 0.4, 0.3, 0.6, 0.6) * 0.2
    b = [at(bell(f, 1.2, decay=0.6, rng=r) * 0.5, 1.0 + i * 0.07) for i, f in enumerate(notes_hz(880, [0, 4, 7, 12]))]
    return reverb(mix(rise, tone, *b), 1.8, 0.45, r)


def s_portal(r):
    d = 1.6
    t = tt(d)
    hum = (osc(110 + 3 * np.sin(2 * np.pi * 0.7 * t), d) + 0.6 * osc(165.5, d) + 0.3 * osc(221.3, d)) * 0.4
    swirl = sweep_filter(noise(d, r), 1200 + 900 * np.sin(2 * np.pi * 1.1 * t), "bandpass", 5) * 0.8
    env = adsr(d, 0.3, 0.3, 0.8, 0.5)
    return reverb(mix(hum, swirl) * env, 1.5, 0.35, r)


def s_alarm(r):
    # 铜锣示警：两记锣声，音高下滑
    part = [(1, 1, 1), (1.52, 0.7, 0.8), (2.1, 0.6, 0.7), (2.8, 0.45, 0.5), (3.6, 0.3, 0.4), (4.9, 0.2, 0.3)]
    layers = []
    for i in range(2):
        d = 0.9
        g = mix(*[osc(sweep(280 * ra * 1.02, 280 * ra * 0.97, d), d) * amp * np.exp(-tt(d) / (0.5 * dk)) for ra, amp, dk in part])
        g = mix(g, bp(noise(0.05, r), 800, 5000) * exp_env(0.05, 0.01) * 1.5)
        layers.append(at(g * (1.0 - 0.15 * i), i * 0.45))
    return reverb(mix(*layers), 1.0, 0.25, r)


SFX = {
    "ui_click": (s_ui_click, 0.55), "ui_hover": (s_ui_hover, 0.3), "ui_open": (s_ui_open, 0.7), "ui_close": (s_ui_close, 0.6),
    "equip": (s_equip, 0.8), "pickup": (s_pickup, 0.7), "coin": (s_coin, 0.7), "error": (s_error, 0.45),
    "notify": (s_notify, 0.65), "quest_complete": (s_quest_complete, 0.85),
    "swing_light": (s_swing_light, 0.75), "swing_heavy": (s_swing_heavy, 0.85), "hit_flesh": (s_hit_flesh, 0.89),
    "hit_metal": (s_hit_metal, 0.85), "hit_shield": (s_hit_shield, 0.8), "shield_break": (s_shield_break, 0.89), "crit": (s_crit, 0.89),
    "bolt_fire": (s_bolt_fire, 0.75), "bolt_hit": (s_bolt_hit, 0.8), "bolt_charge": (s_bolt_charge, 0.6), "cast": (s_cast, 0.75),
    "summon": (s_summon, 0.8), "heal": (s_heal, 0.7), "buff": (s_buff, 0.7),
    "boost_start": (s_boost_start, 0.75), "quick_boost": (s_quick_boost, 0.8), "jump": (s_jump, 0.6), "land": (s_land, 0.7),
    "footstep": (s_footstep, 0.45), "fly_whoosh": (s_fly_whoosh, 0.6),
    "explosion": (s_explosion, 0.89), "fire_cast": (s_fire_cast, 0.8), "ice_cast": (s_ice_cast, 0.75), "wind_blade": (s_wind_blade, 0.75),
    "vine": (s_vine, 0.75), "earth_quake": (s_earth_quake, 0.89), "water_splash": (s_water_splash, 0.8), "thunder": (s_thunder, 0.89),
    "death": (s_death, 0.8), "beast_growl": (s_beast_growl, 0.85), "beast_bite": (s_beast_bite, 0.85), "beast_hurt": (s_beast_hurt, 0.8),
    "levelup": (s_levelup, 0.85), "breakthrough": (s_breakthrough, 0.89), "rock_break": (s_rock_break, 0.85), "wood_break": (s_wood_break, 0.85),
    "search_tick": (s_search_tick, 0.4), "search_done": (s_search_done, 0.7), "extract": (s_extract, 0.85), "portal": (s_portal, 0.75),
    "alarm": (s_alarm, 0.85),
}


def render(name):
    fn, peak = SFX[name]
    x = fn(rng_for(name))
    x = np.nan_to_num(np.asarray(x, dtype=float))
    x = trim_tail(x)
    x = fade(x, 0.001, min(0.03, len(x) / SR * 0.2))
    return normalize(x, peak)


def main(argv):
    os.makedirs(OUT_DIR, exist_ok=True)
    names = argv or list(SFX)
    total = 0
    for name in names:
        x = render(name)
        assert np.max(np.abs(x)) <= 0.9, name
        path = os.path.join(OUT_DIR, name + ".wav")
        sf.write(path, x.astype(np.float32), SR, subtype="PCM_16")
        size = os.path.getsize(path)
        total += size
        print("%-16s %5.2fs %7.1f KB" % (name, len(x) / SR, size / 1024))
    print("共 %d 个音效，%.2f MB" % (len(names), total / 1024 / 1024))


if __name__ == "__main__":
    main(sys.argv[1:])
