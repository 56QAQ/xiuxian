#!/usr/bin/env python3
"""程序化生成背景音乐：assets/audio/music/<name>.ogg（立体声 44.1 kHz Ogg Vorbis，无缝循环）。

用法：python3 tools/gen_music.py [曲名 ...]      （不带参数则生成全部）
曲目：music_menu（古琴/箫，宁静）、music_overworld（古筝琶音 + 笛，舒展）、
      music_battle（太鼓 + 琵琶 + 笛，136 BPM）、music_realm（低鸣、泛音、心跳，紧张神秘）
依赖：numpy、scipy、soundfile；DSP 工具复用 tools/gen_sfx.py。

无缝循环：所有音符、混响尾音与噪声底都写入长度恰为一个循环的环形缓冲区——
越过末尾的部分回卷到开头（混响用环形卷积，风声用周期噪声），因此首尾天然衔接。
旋律用简谱书写（1=宫 2=商 3=角 5=徵 6=羽，' 高八度，, 低八度，#/b 升降），
也可直接写音名（E2、F#3）。时值单位为拍；后缀 v=揉弦/颤音，s=下方滑入，d=尾音下滑。
"""
import os
import re
import sys

import numpy as np
import soundfile as sf
from scipy import fft as sfft

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_sfx import (SR, ROOT, bp, hp, lp, ks_pluck, n_of, osc, peak_eq, tail_fade)  # noqa: E402

OUT_DIR = os.path.join(ROOT, "assets", "audio", "music")

JIANPU = {"1": 0, "2": 2, "3": 4, "4": 5, "5": 7, "6": 9, "7": 11}
NOTE_NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def name_midi(s):
    m = re.fullmatch(r"([A-G])([#b]?)(-?\d)", s)
    if not m:
        raise ValueError(s)
    acc = {"#": 1, "b": -1, "": 0}[m.group(2)]
    return NOTE_NAMES[m.group(1)] + acc + 12 * (int(m.group(3)) + 1)


def parse(seq, root=60):
    """返回 ([(拍, midi 或 None, 时值, 标记)], 总拍数)。"""
    out = []
    beat = 0.0
    for tok in seq.split():
        if tok == "|":
            continue
        note, rest = tok.split(":")
        m = re.fullmatch(r"([0-9.]+)([a-z]*)", rest)
        dur, flags = float(m.group(1)), m.group(2)
        if note[0] in NOTE_NAMES:
            midi = name_midi(note)
        else:
            acc = 0
            while note[0] in "#b":
                acc += 1 if note[0] == "#" else -1
                note = note[1:]
            deg = note[0]
            octv = note.count("'") - note.count(",")
            midi = None if deg == "0" else root + JIANPU[deg] + acc + 12 * octv
        out.append((beat, midi, dur, flags))
        beat += dur
    return out, beat


def check_bars(seq, bars, root=60, beats=4):
    ev, total = parse(seq, root)
    assert abs(total - bars * beats) < 1e-6, "小节长度不符：%s 拍 ≠ %d 小节（%s…）" % (total, bars, seq[:40])
    return ev


# ============================================================== 乐器

_cache = {}


def _warp(y, ratio):
    """按逐样本变速比重采样（滑音/揉弦）。"""
    pos = np.cumsum(ratio) - ratio[0]
    return np.interp(pos, np.arange(len(y)), y, right=0.0)


def _pitch_ratio(n, flags, depth=0.006):
    t = np.arange(n) / SR
    r = np.ones(n)
    if "s" in flags:  # 由下方大二度滑入
        g = np.clip(t / 0.14, 0, 1)
        r *= 2 ** (-2 / 12 * (1 - g) ** 2)
    if "v" in flags:  # 揉弦
        ramp = np.clip((t - 0.25) / 0.5, 0, 1)
        r *= 1 + depth * np.sin(2 * np.pi * 5.0 * t) * ramp
    if "d" in flags:  # 尾音下滑
        start = int(n * 0.55)
        g = np.clip((np.arange(n) - start) / max(n - start, 1), 0, 1)
        r *= 2 ** (-2 / 12 * g ** 1.5)
    return r


def _mellow(y, f, dark_mult, tau):
    """亮度随时间衰减：起音明亮，余音温润（丝弦的特征）。"""
    dark = lp(y, min(f * dark_mult, SR * 0.4))
    t = np.arange(len(y)) / SR
    return dark + (y - dark) * np.exp(-t / tau)


def guqin(midi, dur, flags, rng, variant=0):
    """古琴：温暖的 Karplus-Strong 拨弦 + 琴体共鸣，支持吟猱与滑音。"""
    f = midi_hz(midi)
    ring = min(max(dur + 1.5, 2.5), 6.0)
    key = ("qin", midi, round(ring, 1), variant % 3)
    if key not in _cache:
        t60 = float(np.clip(5.5 - 0.008 * f, 2.2, 5.0))
        y = ks_pluck(f, ring * 1.1, np.random.default_rng(midi * 7 + variant % 3), bright=0.2, t60=t60, pick=0.13, attack_noise=0.08)
        y = _mellow(y, f, 5.0, 0.12)
        y = peak_eq(y, 190, 1.2, 4.0)
        y = lp(y, 2600)
        y[:n_of(0.004)] *= np.linspace(0, 1, n_of(0.004))
        _cache[key] = y / (np.max(np.abs(y)) + 1e-9)
    y = _cache[key]
    n = n_of(ring)
    if flags:
        y = _warp(y, _pitch_ratio(n, flags, 0.008))
    y = y[:n].copy()
    # 离弦：音符时值后逐渐止音
    stop = n_of(dur + 0.9)
    if stop < n:
        y[stop:] *= np.exp(-np.arange(n - stop) / (0.25 * SR))
    return tail_fade(y, 0.05)


def qin_harmonic(midi, dur, flags, rng, variant=0):
    """古琴泛音：纯净明亮、似钟非钟。"""
    f = midi_hz(midi)
    d = max(dur + 2.0, 2.5)
    t = np.arange(n_of(d)) / SR
    y = np.sin(2 * np.pi * f * t) + 0.18 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / 0.4) + 0.05 * np.sin(2 * np.pi * 3 * f * t) * np.exp(-t / 0.2)
    y *= np.exp(-t / 1.3) * np.clip(t / 0.003, 0, 1)
    return tail_fade(y, 0.1)


def zheng(midi, dur, flags, rng, variant=0, bright=0.7, t60=1.6):
    """古筝/琵琶：明亮的拨弦。"""
    f = midi_hz(midi)
    ring = min(max(dur + 0.8, 0.6), 3.5)
    key = ("zheng", midi, round(ring, 1), variant % 3, bright, t60)
    if key not in _cache:
        y = ks_pluck(f, ring, np.random.default_rng(midi * 13 + variant % 3), bright=bright, t60=t60, pick=0.11, attack_noise=0.15)
        y = _mellow(y, f, 8.0, 0.25)
        y = hp(peak_eq(y, 2500, 1.0, 3.0), 120)
        _cache[key] = y / (np.max(np.abs(y)) + 1e-9)
    y = _cache[key]
    if flags:
        y = _warp(y, _pitch_ratio(len(y), flags, 0.01))
    return tail_fade(y, 0.04)


def pipa(midi, dur, flags, rng, variant=0):
    return zheng(midi, min(dur, 0.6), flags, rng, variant, bright=0.85, t60=0.7)


def _wind_instr(midi, dur, flags, rng, harm, breath, attack, vib_depth, buzz=0.0):
    f = midi_hz(midi)
    d = dur + 0.25
    n = n_of(d)
    t = np.arange(n) / SR
    vib = np.clip((t - 0.3) / 0.5, 0, 1) * vib_depth * (2.0 if "v" in flags else 1.0) * np.sin(2 * np.pi * 5.2 * t + rng.uniform(0, 6))
    ratio = _pitch_ratio(n, flags.replace("v", ""), 0.0) * (1 + vib)
    ph = 2 * np.pi * np.cumsum(f * ratio) / SR
    tone = np.zeros(n)
    for k, a in enumerate(harm, 1):
        if f * k < SR * 0.45:
            tone += a * np.sin(k * ph)
    env = np.clip(t / attack, 0, 1) ** 1.5
    env *= 1 + 0.08 * np.sin(np.pi * np.clip(t / max(dur, 0.1), 0, 1))  # 气息微微鼓起
    rel = t > dur
    env[rel] *= np.exp(-(t[rel] - dur) / 0.07)
    noise_src = rng.standard_normal(n)
    br = bp(noise_src, f * 0.8, min(f * 4.5, SR * 0.4)) * breath
    chiff = hp(noise_src, 2000) * np.exp(-t / 0.035) * breath * 1.5
    y = tone * env + br * env + chiff
    if buzz > 0:
        y = y + bp(np.tanh(tone * 3.0), 2500, 6000) * buzz * env
    return tail_fade(lp(y, 7000), 0.05)


def xiao(midi, dur, flags, rng, variant=0):
    """洞箫：柔和、气声重。"""
    return _wind_instr(midi, dur, flags, rng, [1.0, 0.22, 0.1, 0.04, 0.02], 0.16, 0.14, 0.006)


def dizi(midi, dur, flags, rng, variant=0):
    """竹笛：明亮，带笛膜的沙沙声。"""
    return _wind_instr(midi, dur, flags, rng, [1.0, 0.5, 0.33, 0.2, 0.12, 0.07, 0.04], 0.08, 0.04, 0.008, buzz=0.12)


def pad(midis, dur, rng, cutoff=1100.0, attack=2.0, release=2.5, detune=0.004):
    """笙/弦乐铺底：失谐锯齿波叠加后低通。"""
    n = n_of(dur + release)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for m in midis:
        f = midi_hz(m)
        for dt in (-detune, 0.0, detune):
            y += osc(f * (1 + dt), dur + release, "saw", rng.uniform(0, 6.28))[:n]
    y = lp(lp(y, cutoff), cutoff * 1.5)
    env = np.clip(t / attack, 0, 1) ** 2
    rel = t > dur
    env[rel] *= np.cos(np.clip((t[rel] - dur) / release, 0, 1) * np.pi / 2) ** 2
    return y * env / max(len(midis) * 3, 1)


def taiko(kind, vel, rng):
    if kind == "big":
        d, f0, f1, tau = 1.4, 110.0, 52.0, 0.5
    elif kind == "mid":
        d, f0, f1, tau = 0.7, 175.0, 92.0, 0.22
    elif kind == "heart":
        d, f0, f1, tau = 0.6, 75.0, 44.0, 0.2
    else:  # rim：鼓边/鼓钉
        d, f0, f1, tau = 0.15, 900.0, 820.0, 0.025
    t = np.arange(n_of(d)) / SR
    fr = f1 + (f0 - f1) * np.exp(-t / 0.03)
    body = np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t / tau)
    body += 0.35 * np.sin(2 * np.pi * np.cumsum(fr * 1.58) / SR) * np.exp(-t / (tau * 0.4))
    skin = lp(rng.standard_normal(len(t)), 500 if kind != "rim" else 5000) * np.exp(-t / 0.03) * (0.5 if kind != "rim" else 1.2)
    y = (body + skin) * np.clip(t / 0.0015, 0, 1)
    if kind != "rim":
        y = np.tanh(y * 1.4) / np.tanh(1.4)
    return tail_fade(y * vel, 0.05)


def cymbal(kind, vel, rng):
    d, tau, lo = (2.8, 1.0, 3000.0) if kind == "crash" else (0.5, 0.12, 4500.0)
    t = np.arange(n_of(d)) / SR
    x = rng.standard_normal(len(t))
    y = hp(x, lo) * 0.6
    for fc in (3600, 5300, 7900):
        y += bp(x, fc * 0.95, fc * 1.05) * 1.5
    return tail_fade(y * np.exp(-t / tau) * np.clip(t / 0.002, 0, 1) * vel, 0.1)


GONG_PARTIALS = [(1.0, 1.0, 1.0), (1.48, 0.7, 0.8), (2.02, 0.55, 0.7), (2.54, 0.45, 0.55), (3.17, 0.3, 0.45), (4.1, 0.2, 0.35), (5.3, 0.12, 0.25)]


def gong(f0, vel, rng, dur=5.0, swell=0.0):
    """锣：非谐分音，音高轻微下滑；swell>0 时先有一段逆向渐强。"""
    t = np.arange(n_of(dur)) / SR
    y = np.zeros(len(t))
    for ratio, amp, dk in GONG_PARTIALS:
        fr = f0 * ratio * (1 - 0.02 * (1 - np.exp(-t / 1.0)))
        y += amp * np.sin(2 * np.pi * np.cumsum(fr) / SR + rng.uniform(0, 6.28)) * np.exp(-t / (2.4 * dk))
    y += lp(rng.standard_normal(len(t)), 1500) * np.exp(-t / 0.05) * 0.6
    y *= np.clip(t / 0.004, 0, 1)
    y = tail_fade(y * vel, 0.3)
    if swell > 0:
        ns = n_of(swell)
        ts = np.arange(ns) / SR
        pre = np.zeros(ns)
        for ratio, amp, dk in GONG_PARTIALS[:5]:
            pre += amp * np.sin(2 * np.pi * f0 * ratio * ts + rng.uniform(0, 6.28))
        pre += bp(rng.standard_normal(ns), 300, 3000) * 0.6
        pre *= (ts / swell) ** 3 * 0.5 * vel
        # 逆涌在击锣前 20 ms 内收住，避免断口咔哒声
        k = n_of(0.02)
        pre[-k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
        y = np.concatenate([pre, y])
    return y


def bianzhong(midi, vel, rng, dur=3.0):
    f = midi_hz(midi)
    t = np.arange(n_of(dur)) / SR
    y = np.zeros(len(t))
    for ratio, amp, dk in [(1.0, 1.0, 1.0), (2.4, 0.5, 0.45), (3.0, 0.3, 0.35), (4.5, 0.25, 0.25), (6.2, 0.12, 0.15)]:
        y += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / (1.4 * dk))
    return tail_fade(y * np.clip(t / 0.002, 0, 1) * vel, 0.2)


def woodblock(vel, rng, pitch=1.0):
    d = 0.14
    t = np.arange(n_of(d)) / SR
    y = (np.sin(2 * np.pi * 950 * pitch * t) + 0.4 * np.sin(2 * np.pi * 2280 * pitch * t)) * np.exp(-t / 0.03)
    y += hp(rng.standard_normal(len(t)), 3000) * np.exp(-t / 0.004) * 0.5
    return tail_fade(y * vel, 0.02)


def bowed_metal(f0, dur, rng):
    t = np.arange(n_of(dur)) / SR
    y = np.zeros(len(t))
    for ratio in (1.0, 1.41, 2.13, 2.76, 3.93, 5.1):
        y += np.sin(2 * np.pi * f0 * ratio * (1 + 0.002 * np.sin(2 * np.pi * rng.uniform(0.1, 0.4) * t)) * t + rng.uniform(0, 6.28)) / ratio
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2
    return y * env


# ============================================================== 环形混音台

class Loop:
    def __init__(self, name, bpm, bars, seed, beats=4):
        self.name = name
        self.bpm = bpm
        self.beat_sec = 60.0 / bpm
        self.bars = bars
        self.beats = beats
        self.L = int(round(bars * beats * self.beat_sec * SR))
        self.dry = np.zeros((2, self.L))
        self.send = np.zeros(self.L)
        self.rng = np.random.default_rng(seed)

    def sec(self, bar, beat=0.0):
        return (bar * self.beats + beat) * self.beat_sec

    def add(self, x, t_sec, pan=0.0, gain=1.0, send=0.3, jitter=0.006):
        if jitter:
            t_sec += self.rng.uniform(-jitter, jitter)
        x = np.asarray(x, dtype=float)[:self.L]
        start = int(round(t_sec * SR)) % self.L
        th = (pan + 1) * np.pi / 4
        gl, gr = np.cos(th) * gain, np.sin(th) * gain
        n1 = min(len(x), self.L - start)
        self.dry[0, start:start + n1] += x[:n1] * gl
        self.dry[1, start:start + n1] += x[:n1] * gr
        self.send[start:start + n1] += x[:n1] * gain * send
        if n1 < len(x):
            rest = x[n1:]
            self.dry[0, :len(rest)] += rest * gl
            self.dry[1, :len(rest)] += rest * gr
            self.send[:len(rest)] += rest * gain * send

    def phrase(self, instr, seq, bar, root=60, pan=0.0, gain=1.0, send=0.3, vel=(0.8, 1.0), bars=None, octave=0, legato=1.0):
        ev, total = parse(seq, root)
        if bars is not None:
            assert abs(total - bars * self.beats) < 1e-6, "%s: %s 拍 ≠ %d 小节" % (self.name, total, bars)
        for i, (b, midi, dur, flags) in enumerate(ev):
            if midi is None:
                continue
            v = self.rng.uniform(*vel)
            x = instr(midi + 12 * octave, dur * self.beat_sec * legato, flags, self.rng, i)
            self.add(x * v, self.sec(bar, b), pan, gain, send)

    def periodic_noise(self, lo, hi, gain, lfo=((3, 0.3), (7, 0.15)), send=0.2, pan_spread=0.3):
        """周期噪声（风声）：频域整形，长度恰为一个循环，首尾无缝。"""
        for ch in range(2):
            spec = sfft.rfft(self.rng.standard_normal(self.L))
            fr = sfft.rfftfreq(self.L, 1 / SR)
            shape = 1 / (1 + ((fr - (lo + hi) / 2) / ((hi - lo) / 2)) ** 4)
            x = sfft.irfft(spec * shape, n=self.L)
            x /= np.std(x) + 1e-9
            t = np.arange(self.L) / self.L
            m = 1.0 + sum(a * np.sin(2 * np.pi * k * t + ch * 0.9) for k, a in lfo)
            self.dry[ch] += x * m * gain * (1 - pan_spread if ch else 1)
            self.send += x * m * gain * send * 0.5

    def render(self, rt=3.0, wet=0.3, bright=5000.0, target_rms_db=-19.0):
        out = self.dry.copy()
        if wet > 0:
            spec = sfft.rfft(self.send)
            for ch in range(2):
                r = np.random.default_rng(1000 + ch)
                n = n_of(rt * 1.3)
                t = np.arange(n) / SR
                ir = r.standard_normal(n) * np.exp(-6.9 * t / rt)
                ir = lp(ir, bright) * 0.7 + lp(ir, bright * 0.25) * 0.3
                ir = np.concatenate([np.zeros(n_of(0.02 + 0.007 * ch)), ir])
                ir /= np.sqrt(np.sum(ir ** 2))
                # 环形卷积：混响尾音回卷到循环开头
                wet_sig = sfft.irfft(spec * sfft.rfft(ir, n=self.L), n=self.L)
                out[ch] += wet_sig * wet
        out -= out.mean(axis=1, keepdims=True)
        rms = np.sqrt(np.mean(out ** 2))
        out *= 10 ** (target_rms_db / 20) / (rms + 1e-12)
        # 柔和限幅（逐点运算，不破坏循环）
        peak = np.max(np.abs(out))
        if peak > 0.8:
            k = 0.8
            over = np.abs(out) > k
            out[over] = np.sign(out[over]) * (k + (1 - k) * np.tanh((np.abs(out[over]) - k) / (1 - k)))
        out *= min(1.0, 0.89 / np.max(np.abs(out)))
        return out


# ============================================================== 曲目

def music_menu():
    """主菜单：古琴独奏于低鸣之上，洞箫应和。D 宫调，64 BPM，20 小节 ≈ 75 秒。"""
    m = Loop("music_menu", 64, 20, 101)
    D2, D3, D4, D5 = 38, 50, 62, 74
    # 低鸣铺底（每 4 小节一组，长 5 小节，相互交叠并回卷）
    for bar in range(0, 20, 4):
        chord = [D2, D2 + 7, D3] if bar % 8 == 0 else [D2, D2 + 7, D3 + 2]
        m.add(pad(chord, m.sec(5), m.rng, cutoff=700, attack=3.0, release=4.0), m.sec(bar), 0.0, 0.5, 0.4, 0)
    m.periodic_noise(250, 1400, 0.012)
    # 引子：泛音
    m.phrase(qin_harmonic, "5:2.5 1':1.5 | 2':2 5:2 | 6:1.5 5:1.5 3:1 | 2:2 0:2", 0, D5, 0.25, 0.28, 0.5, bars=4)
    # 古琴主题（第 5~12 小节）与低音
    qin_a = ("3:1 5:1 6:2 | 5:1 3:0.5 2:0.5 1:2v | 2:1 3:1 5:1 3:1 | 2:4v | "
             "3:1 5:1 6:1 1':1 | 6:1.5 5:0.5 3:2s | 2:1 3:0.5 2:0.5 6,:1 1:1 | 1:4v")
    m.phrase(guqin, qin_a, 4, D3, -0.15, 0.9, 0.35, bars=8)
    bass = "1,:2 5,:2 | 1,:4 | 5,:2 1,:2 | 5,:4 | 6,:2 1,:2 | 1,:4 | 5,:4 | 1,:4"
    m.phrase(guqin, bass, 4, D3, -0.3, 0.55, 0.3, vel=(0.6, 0.75), bars=8)
    # 洞箫（第 13~20 小节）与古琴分解和弦
    xiao_b = "6:3v 5:1 | 3:2 5:2v | 6:2 1':1 6:1 | 5:4v | 3:3v 2:1 | 1:2 2:2 | 3:1 5:1 3:1 2:1 | 1:4v"
    m.phrase(xiao, xiao_b, 12, D4, 0.2, 0.55, 0.45, bars=8)
    arp = ("1,:1 5,:1 1:1 5,:1 | 1,:1 5,:1 1:1 2:1 | 6,:1 3:1 6:1 3:1 | 5,:1 2:1 5:1 2:1 | "
           "1,:1 5,:1 1:1 5,:1 | 1,:1 5,:1 2:1 1:1 | 6,:1 3:1 5:1 3:1 | 1,:2 5,:1 1:1")
    m.phrase(guqin, arp, 12, D3, -0.2, 0.42, 0.35, vel=(0.55, 0.75), bars=8)
    m.phrase(qin_harmonic, "0:2 3':2 | 0:4 | 5:2 0:2 | 0:2 1':2", 16, D5, 0.35, 0.18, 0.5, bars=4)
    # 磬声标记段落
    m.add(bianzhong(D5, 0.25, m.rng), m.sec(4), 0.3, 1.0, 0.6, 0)
    m.add(bianzhong(D4 + 7, 0.22, m.rng), m.sec(12), -0.3, 1.0, 0.6, 0)
    return m.render(rt=3.6, wet=0.4, bright=4500, target_rms_db=-21.0)


def music_overworld():
    """大地图：古筝琶音、竹笛旋律、轻鼓，舒展而有行进感。G 宫调，84 BPM，28 小节 = 80 秒。"""
    m = Loop("music_overworld", 84, 28, 202)
    G2, G3, G4 = 43, 55, 67
    chords = [[0, 4, 7], [-3, 0, 4], [2, 7, 9], [-5, 0, 2]]  # I、vi、ii、V(sus4)，均为五声音
    roots = [0, -3, 2, -5]
    for bar in range(28):
        c = chords[bar % 4]
        # 低音：第 1、3 拍
        r = G2 + roots[bar % 4]
        m.add(guqin(r, m.beat_sec * 2, "", m.rng, bar), m.sec(bar, 0), -0.25, 0.6, 0.25)
        m.add(guqin(r, m.beat_sec * 2, "", m.rng, bar + 1) * 0.6, m.sec(bar, 2), -0.25, 0.6, 0.25)
        # 古筝八分音符琶音
        tones = sorted([G3 + x for x in c]) + sorted([G3 + 12 + x for x in c])
        pattern = [0, 2, 3, 4, 5, 4, 3, 2] if bar % 2 == 0 else [0, 1, 3, 2, 4, 5, 3, 1]
        for i, idx in enumerate(pattern):
            v = (0.75 if i % 2 == 0 else 0.55) * m.rng.uniform(0.9, 1.05)
            m.add(zheng(tones[idx], m.beat_sec * 0.5, "", m.rng, i) * v, m.sec(bar, i * 0.5), 0.25 - 0.1 * (i % 3), 0.32, 0.3)
        # 铺底
        if bar % 4 == 0:
            m.add(pad([G3 + x for x in [0, 7]] + [G2], m.sec(4.5), m.rng, cutoff=900, attack=2.0, release=2.5), m.sec(bar), 0.0, 0.35, 0.3, 0)
        # 鼓：第 13 小节起
        if bar >= 12:
            m.add(taiko("mid", 0.5, m.rng), m.sec(bar, 0), -0.1, 0.45, 0.2, 0.003)
            m.add(taiko("mid", 0.3, m.rng), m.sec(bar, 2), 0.1, 0.45, 0.2, 0.003)
            if bar % 4 == 3:
                m.add(taiko("mid", 0.35, m.rng), m.sec(bar, 3.5), 0.0, 0.45, 0.2, 0.003)
        if bar >= 20:
            m.add(woodblock(0.25, m.rng), m.sec(bar, 1.5), 0.4, 0.5, 0.15, 0.003)
            m.add(woodblock(0.2, m.rng, 1.12), m.sec(bar, 3.5), 0.4, 0.5, 0.15, 0.003)
    mel_a = ("5:1 6:1 1':1.5 2':0.5 | 3':2 2':1 1':1 | 6:1 1':1 2':1 6:1 | 5:4v | "
             "3:1 5:1 6:1 1':1 | 2':1.5 3':0.5 2':1 1':1 | 6:1 5:1 3:1 2:1 | 1:3v 0:1")
    mel_b = ("6:2 5:1 6:1 | 1':2 2':2v | 3':1 2':1 1':1 6:1 | 5:3v 3:1 | "
             "5:1 6:1 5:1 3:1 | 2:2 3:1 5:1 | 6:1.5 1':0.5 6:1 5:1 | 6:4v")
    m.phrase(dizi, mel_a, 4, G4, 0.1, 0.42, 0.35, bars=8)
    m.phrase(dizi, mel_b, 12, G4, 0.1, 0.42, 0.35, bars=8)
    m.phrase(zheng, mel_a, 20, G4, 0.15, 0.55, 0.35, vel=(0.8, 0.95), bars=8)
    m.phrase(xiao, "3:4 | 1:4 | 2:4 | 5,:4 | 3:4 | 2:2 1:2 | 6,:4 | 1:4", 20, G4, -0.2, 0.35, 0.4, bars=8)
    for bar, midi in ((4, G4 + 12), (12, G4 + 7), (20, G4 + 12)):
        m.add(bianzhong(midi, 0.2, m.rng), m.sec(bar), 0.3, 1.0, 0.5, 0)
    m.add(cymbal("crash", 0.12, m.rng), m.sec(12), 0.2, 1.0, 0.4, 0)
    m.add(cymbal("crash", 0.12, m.rng), m.sec(20), -0.2, 1.0, 0.4, 0)
    return m.render(rt=2.6, wet=0.3, bright=6000, target_rms_db=-20.0)


BIG = {"intro": "X.......X.......", "drive": "X..X..X.X.......", "full": "X..X..X.X...X.x.",
       "fill": "X.x.X.x.XxXxXXXX", "break": "X...............", "none": "................"}
SMALL = {"back": "....x.......x...", "busy": "..x.x..x..x.x.xx", "roll": "xxxxxxxxxxxxxxxx", "none": "................"}


def music_battle():
    """战斗：太鼓驱动、琵琶急弦、竹笛高亢。A 羽调，136 BPM，40 小节 ≈ 70.6 秒。"""
    m = Loop("music_battle", 136, 40, 303)
    C3, C4 = 48, 60
    roots = [45, 45, 43, 40, 45, 45, 38, 40]  # A2 A2 G2 E2 A2 A2 D2 E2
    step = 0.25
    for bar in range(40):
        sec = bar // 8
        big = ["intro", "drive", "full", "full", "break"][sec]
        small = ["back", "busy", "busy", "busy", "none"][sec]
        if sec == 0 and bar < 4:
            small = "none"
        if bar in (7, 15, 23, 31):
            big = "fill"
        if bar in (36, 37):
            big, small = "intro", "back"
        if bar in (38, 39):
            big, small = ("drive" if bar == 38 else "fill"), "roll"
        for i in range(16):
            c = BIG[big][i]
            if c != ".":
                v = 1.0 if c == "X" else 0.6
                m.add(taiko("big", v, m.rng), m.sec(bar, i * step), -0.05, 0.9, 0.2, 0.002)
            c = SMALL[small][i]
            if c != ".":
                v = 0.45 + (0.5 * (bar - 38 + i / 16) / 2 if small == "roll" else 0.0)
                m.add(taiko("mid", v, m.rng), m.sec(bar, i * step), 0.25, 0.6, 0.2, 0.002)
            if 16 <= bar < 32 and i % 2 == 0:
                m.add(taiko("rim", 0.18 if i % 4 else 0.28, m.rng), m.sec(bar, i * step), -0.35, 0.5, 0.1, 0.002)
        if 16 <= bar < 32:
            m.add(cymbal("small", 0.22, m.rng), m.sec(bar, 1), 0.4, 0.6, 0.2, 0.002)
            m.add(cymbal("small", 0.22, m.rng), m.sec(bar, 3), 0.4, 0.6, 0.2, 0.002)
        # 低音八分音符
        r = roots[bar % 8]
        if bar < 32 or bar >= 36:
            for i, off in enumerate([0, 0, 12, 0, 0, 12, 0, 7]):
                v = 0.9 if i % 2 == 0 else 0.7
                m.add(zheng(r + off, m.beat_sec * 0.5, "", m.rng, i, 0.5, 0.35) * v, m.sec(bar, i * 0.5), -0.15, 0.55, 0.1, 0.003)
        elif bar >= 34:
            for q in range(4):
                m.add(zheng(r, m.beat_sec, "", m.rng, q, 0.5, 0.5) * 0.8, m.sec(bar, q), -0.15, 0.55, 0.1, 0.003)
        if bar % 2 == 0 and not (32 <= bar < 34):
            sub = np.sin(2 * np.pi * midi_hz(r - 12) * np.arange(n_of(m.beat_sec * 2)) / SR) * np.exp(-np.arange(n_of(m.beat_sec * 2)) / (0.5 * SR))
            m.add(tail_fade(sub, 0.05), m.sec(bar), 0.0, 0.35, 0.0, 0)
    for bar in (0, 8, 16, 24, 32):
        m.add(cymbal("crash", 0.35, m.rng), m.sec(bar), -0.3, 1.0, 0.4, 0)
    # 琵琶急弦
    rb1 = "6,:0.25 6,:0.25 1:0.25 6,:0.25 2:0.5 1:0.25 6,:0.25 3:0.5 2:0.25 1:0.25 6,:0.5 5,:0.5"
    rb2 = "6,:0.25 6,:0.25 1:0.25 2:0.25 3:0.5 5:0.5 6:0.25 5:0.25 3:0.25 2:0.25 3:1"
    rb3 = "5,:0.25 5,:0.25 6,:0.25 5,:0.25 1:0.5 6,:0.25 5,:0.25 2:0.5 1:0.25 6,:0.25 5,:0.5 3,:0.5"
    rb4 = "3,:0.25 3,:0.25 5,:0.25 6,:0.25 1:0.5 2:0.5 3:0.25 2:0.25 1:0.25 6,:0.25 3:1"
    rb7 = "2:0.25 2:0.25 3:0.25 2:0.25 5:0.5 3:0.25 2:0.25 6:0.5 5:0.25 3:0.25 2:0.5 1:0.5"
    riff = " | ".join([rb1, rb2, rb3, rb4, rb1, rb2, rb7, rb4])
    m.phrase(pipa, riff, 8, C4, 0.35, 0.5, 0.2, vel=(0.75, 1.0), bars=8)
    m.phrase(pipa, riff, 16, C4, 0.35, 0.36, 0.2, vel=(0.7, 0.9), bars=8)
    m.phrase(pipa, riff, 24, C4, 0.35, 0.36, 0.2, vel=(0.7, 0.9), bars=8)
    lead_a = ("6:1.5 1':0.5 2':1 3':1 | 2':1.5 1':0.5 6:2 | 5:1 6:0.5 1':0.5 2':1 1':1 | 6:4v | "
              "3':1.5 5':0.5 3':1 2':1 | 1':1 2':0.5 1':0.5 6:2 | 5:1 3:1 5:0.5 6:0.5 1':1 | 6:3v 0:1")
    lead_b = ("6':2 5':1 3':1 | 5':1.5 3':0.5 2':2v | 3':1 2':0.5 1':0.5 2':1 3':1 | 6:2 1':2 | "
              "2':1 3':1 5':1 6':1 | 5':0.5 3':0.5 2':1 3':2 | 2':0.5 1':0.5 6:1 1':1 2':1 | 6:4v")
    m.phrase(dizi, lead_a, 16, C4, -0.1, 0.45, 0.3, bars=8)
    m.phrase(dizi, lead_b, 24, C4, -0.1, 0.45, 0.3, bars=8)
    # 间奏：琵琶轮指长音，逐步推向循环开头
    trem = [57, 55, 52, 50, 52, 55, 57, 60]
    for k, midi in enumerate(trem):
        bar = 32 + k
        for j in range(32):
            v = (0.35 + 0.25 * (k / 7)) * m.rng.uniform(0.8, 1.1)
            m.add(pipa(midi, m.beat_sec * 0.125, "", m.rng, j) * v, m.sec(bar, j * 0.125), 0.3, 0.45, 0.25, 0.002)
    # 低鸣铺底
    for bar in range(0, 40, 8):
        swell = 0.7 if bar == 32 else 0.35
        m.add(pad([33, 40, 45], m.sec(9), m.rng, cutoff=600, attack=1.5, release=2.0), m.sec(bar), 0.0, swell, 0.3, 0)
    return m.render(rt=2.0, wet=0.22, bright=6000, target_rms_db=-16.5)


def music_realm():
    """秘境：低鸣、古琴低音与泛音、洞箫、心跳鼓、锣声逆涌，紧张神秘。E 羽调带半音，72 BPM，24 小节 = 80 秒。"""
    m = Loop("music_realm", 72, 24, 404)
    E2 = 40
    for bar in (0, 8, 16):
        m.add(pad([E2, E2 + 7, E2 + 12], m.sec(10), m.rng, cutoff=500, attack=4.0, release=5.0, detune=0.006), m.sec(bar), 0.0, 0.8, 0.4, 0)
    m.add(pad([E2 + 13], m.sec(8), m.rng, cutoff=700, attack=4.0, release=4.0, detune=0.008), m.sec(8), 0.2, 0.35, 0.5, 0)
    m.periodic_noise(180, 900, 0.03, lfo=((2, 0.45), (5, 0.2)), send=0.3)
    m.periodic_noise(2500, 6000, 0.004, lfo=((3, 0.6),), send=0.5)
    # 心跳
    for bar in range(8, 24):
        v = 0.55 if bar < 16 else 0.7
        m.add(taiko("heart", v, m.rng), m.sec(bar, 0), 0.0, 0.8, 0.15, 0)
        m.add(taiko("heart", v * 0.65, m.rng), m.sec(bar, 0.42), 0.0, 0.8, 0.15, 0)
    for bar in (4, 12):
        m.add(taiko("big", 0.8, m.rng), m.sec(bar, 0), 0.0, 0.7, 0.5, 0)
    # 古琴低音动机
    motif1 = "E2:1.5s F2:0.5 E2:2v | 0:2 B1:1 C2:1 | B1:3v 0:1 | E2:1 G2:1 F#2:1d 0:1"
    motif2 = "E2:1.5s F2:0.5 E2:2v | 0:2 A#1:1 B1:1 | E2:3v 0:1 | G2:1 F#2:1 F2:1d E2:1"
    m.phrase(guqin, motif1, 4, pan=-0.2, gain=0.85, send=0.45, bars=4)
    m.phrase(guqin, motif2, 16, pan=-0.2, gain=0.85, send=0.45, bars=4)
    # 泛音
    m.phrase(qin_harmonic, "0:1 B5:3 | 0:2 E6:2 | F6:1.5 E6:2.5 | 0:4", 0, pan=0.3, gain=0.2, send=0.6, bars=4)
    m.phrase(qin_harmonic, "0:2 B5:2 | 0:4 | C6:2 B5:2 | 0:4", 20, pan=0.35, gain=0.18, send=0.6, bars=4)
    # 洞箫
    m.phrase(xiao, "B4:3v C5:1 | B4:4v | A4:2 G4:1 F#4:1 | E4:4v | G4:2 F#4:2 | F4:3v E4:1", 10, pan=0.25, gain=0.45, send=0.55, bars=6)
    # 锣：逆向渐强后击出
    for bar in (0, 8, 16):
        sw = m.beat_sec * 2
        m.add(gong(82.4, 0.5, m.rng, 5.0, swell=sw), m.sec(bar) - sw, -0.1, 0.7, 0.5, 0)
    # 木鱼滴答
    for bar in range(16, 24):
        for b in range(4):
            m.add(woodblock(0.14 + 0.04 * (b == 0), m.rng, 0.8 if b % 2 else 0.72), m.sec(bar, b), 0.45, 0.6, 0.3, 0.004)
    m.add(bowed_metal(622.0, m.sec(4.5), m.rng), m.sec(19.5), 0.3, 0.05, 0.6, 0)
    return m.render(rt=5.0, wet=0.45, bright=3500, target_rms_db=-20.0)


def _ogg_crc_table():
    table = []
    for i in range(256):
        r = i << 24
        for _ in range(8):
            r = ((r << 1) ^ 0x04C11DB7) if r & 0x80000000 else (r << 1)
        table.append(r & 0xFFFFFFFF)
    return table


_OGG_CRC = _ogg_crc_table()


def ogg_fix_serial(path, serial=0x57445353):
    """libsndfile 每次随机生成 Ogg 流序列号，导致文件字节不同。改写为固定值并重算页校验，
    使重新生成的文件逐字节一致（音频内容本身已是确定的）。"""
    with open(path, "rb") as f:
        data = bytearray(f.read())
    pos = 0
    while pos < len(data):
        assert data[pos:pos + 4] == b"OggS", "不是 Ogg 页"
        nseg = data[pos + 26]
        end = pos + 27 + nseg + sum(data[pos + 27:pos + 27 + nseg])
        data[pos + 14:pos + 18] = serial.to_bytes(4, "little")
        data[pos + 22:pos + 26] = b"\0\0\0\0"
        crc = 0
        for byte in data[pos:end]:
            crc = ((crc << 8) & 0xFFFFFFFF) ^ _OGG_CRC[((crc >> 24) ^ byte) & 0xFF]
        data[pos + 22:pos + 26] = crc.to_bytes(4, "little")
        pos = end
    with open(path, "wb") as f:
        f.write(data)


TRACKS = {"music_menu": music_menu, "music_overworld": music_overworld, "music_battle": music_battle, "music_realm": music_realm}


def main(argv):
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    for name in argv or list(TRACKS):
        audio = TRACKS[name]()
        path = os.path.join(OUT_DIR, name + ".ogg")
        data = np.ascontiguousarray(audio.T.astype(np.float32))
        # libsndfile 的 Vorbis 编码器一次写入过长会崩溃，分块写入
        with sf.SoundFile(path, "w", SR, 2, format="OGG", subtype="VORBIS", compression_level=0.5) as f:
            for i in range(0, len(data), SR):
                f.write(data[i:i + SR])
        ogg_fix_serial(path)
        size = os.path.getsize(path)
        total += size
        seam = np.max(np.abs(audio[:, 0] - audio[:, -1]))
        print("%-16s %5.1fs %7.1f KB  峰值 %.2f  首尾差 %.4f" % (name, audio.shape[1] / SR, size / 1024, np.max(np.abs(audio)), seam))
    print("合计 %.2f MB" % (total / 1024 / 1024))


if __name__ == "__main__":
    main(sys.argv[1:])
