"""“电话里的狗版的你”的声音处理：线路底噪、轻微过载、压缩、通话频段（高清通话，170 Hz–6.5 kHz）。
生成语音时一次处理好，App 里直接放，不再做声音处理。"""
from math import gcd
import numpy as np
from scipy.signal import butter, resample_poly, sosfilt

OUT = 44100


def to_rate(x, sr, out=OUT):
    g = gcd(sr, out)
    return resample_poly(x, out // g, sr // g)


def peaking(f0, gain_db, q, sr):
    a = 10 ** (gain_db / 40); w = 2 * np.pi * f0 / sr; al = np.sin(w) / (2 * q)
    b = [1 + al * a, -2 * np.cos(w), 1 - al * a]; den = [1 + al / a, -2 * np.cos(w), 1 - al / a]
    return np.array([[b[0] / den[0], b[1] / den[0], b[2] / den[0], 1, den[1] / den[0], den[2] / den[0]]])


def compress(x, sr, thr_db=-24, ratio=4, attack=0.003, release=0.08):
    env = 0.0; out = np.empty_like(x)
    ka = np.exp(-1 / (attack * sr)); kr = np.exp(-1 / (release * sr))
    for i, v in enumerate(x):
        a = abs(v); k = ka if a > env else kr
        env = k * env + (1 - k) * a
        db = 20 * np.log10(env + 1e-9)
        out[i] = v * 10 ** (((thr_db + (db - thr_db) / ratio - db) if db > thr_db else 0.0) / 20)
    return out


def normalize(x, rms_db=-18, peak_db=-1.5):
    x = x * 10 ** (rms_db / 20) / np.sqrt(np.mean(x[np.abs(x) > 1e-4] ** 2))
    lim = 10 ** (peak_db / 20)
    return np.tanh(x / lim) * lim if np.abs(x).max() > lim else x


def phone(x, sr, rng=None, lead=0.25, tail=0.4):
    """高清通话：170 Hz–6.5 kHz，轻微过载和压缩，很轻的线路底噪"""
    rng = rng or np.random.default_rng(7)
    x = to_rate(x, sr)
    x = np.concatenate([np.zeros(int(lead * OUT)), x / np.abs(x).max() * 0.7, np.zeros(int(tail * OUT))])
    x = x + rng.standard_normal(len(x)) * 0.0015
    x = np.tanh(1.6 * x) / np.tanh(1.6)
    x = compress(x, OUT)
    x = sosfilt(butter(4, 170, "highpass", fs=OUT, output="sos"), x)
    x = sosfilt(butter(4, 6500, "lowpass", fs=OUT, output="sos"), x)
    x = sosfilt(peaking(2200, 3, 0.9, OUT), x)
    return normalize(x)
