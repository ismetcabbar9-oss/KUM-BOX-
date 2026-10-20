#!/usr/bin/env python3
"""Prosedürel ses üretici (prototip). Çıktı: assets/sounds/*.wav (44.1 kHz, 16-bit mono).
Döngü sesleri WAV 'smpl' chunk'ı ile döngü noktası taşır; Godot bunu otomatik algılar.
Çalıştırma: python3 tools/gen_sounds.py
"""
import math, os, struct
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")
rng = np.random.default_rng(1234)


def lowpass(x, cutoff):
    # İki kademeli tek kutuplu alçak geçiren filtre (zamanla değişen cutoff destekli)
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1.0 - np.exp(-2.0 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    for _ in range(2):
        s = 0.0
        for i in range(len(x)):
            s += a[i] * (x[i] - s)
            y[i] = s
        x = y.copy()
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, lo, hi):
    return highpass(lowpass(x, hi), lo)


def env(n, attack, decay):
    t = np.arange(n) / SR
    e = np.exp(-t / decay)
    a = int(attack * SR)
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    return e


def noise(n):
    return rng.standard_normal(n)


def brown(n):
    b = np.cumsum(noise(n))
    b -= lowpass(b, 8.0)
    return b / (np.max(np.abs(b)) + 1e-9)


def norm(x, peak=0.9):
    return x * (peak / (np.max(np.abs(x)) + 1e-9))


def fade_out(x, sec=0.02):
    n = int(sec * SR)
    x[-n:] *= np.linspace(1, 0, n)
    return x


def write_wav(name, x, loop=False):
    x = np.clip(x, -1, 1)
    pcm = (x * 32767).astype("<i2").tobytes()
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"data" + struct.pack("<I", len(pcm)) + pcm
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(x) - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    data = b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks
    with open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.write(data)
    print("yazıldı:", name)


def make_loop(x, xfade_sec=0.5):
    # Sonu başa çapraz geçişle bağla -> dikişsiz döngü
    n = int(xfade_sec * SR)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    w = np.linspace(0, 1, n)
    mixed = tail * (1 - w) + head * w
    return np.concatenate([body, mixed])


def grains(n, rate, dur_ms, lo, hi, amp_jitter=0.6):
    """Çakıl/kırıntı taneleri: rastgele zamanlı kısa filtreli gürültü patlamaları."""
    out = np.zeros(n)
    count = int(rate * n / SR)
    for _ in range(count):
        pos = rng.integers(0, n)
        g = int(rng.uniform(0.4, 1.0) * dur_ms * SR / 1000)
        if pos + g >= n or g < 8:
            continue
        burst = noise(g) * env(g, 0.0005, g / SR / 4)
        out[pos:pos + g] += burst * rng.uniform(1 - amp_jitter, 1.0)
    return bandpass(out, lo, hi)


def modal(n, freqs, decays, amps):
    t = np.arange(n) / SR
    y = np.zeros(n)
    for f, d, a in zip(freqs, decays, amps):
        y += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / d)
    return y


def rock_impact(i):
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    f = 55 + 70 * np.exp(-t * 18) + rng.uniform(-6, 6)
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.002, 0.22)
    crack = bandpass(noise(n), 300, 3500) * env(n, 0.0005, 0.035)
    rubble = grains(n, 70, 25, 500, 6000) * env(n, 0.01, 0.35)
    body = lowpass(noise(n), 400) * env(n, 0.003, 0.18)
    return fade_out(norm(1.0 * thump + 0.55 * norm(crack) + 0.35 * norm(rubble) + 0.6 * norm(body)))


def brick_impact(i):
    n = int(0.9 * SR)
    crack = bandpass(noise(n), 700, 5000) * env(n, 0.0003, 0.02 + 0.01 * i)
    body = modal(n, [180 + 30 * i, 420 + 40 * i, 950], [0.05, 0.03, 0.015], [0.6, 0.35, 0.2])
    crumble = grains(n, 140, 12, 1200, 8000) * env(n, 0.01, 0.18)
    thud = lowpass(noise(n), 250) * env(n, 0.002, 0.09)
    return fade_out(norm(0.8 * norm(crack) + 0.6 * body + 0.5 * norm(crumble) + 0.7 * norm(thud)))


def wood_impact(i):
    n = int(0.7 * SR)
    f0 = 140 + 45 * i
    body = modal(n, [f0, f0 * 2.31, f0 * 3.9, f0 * 6.2], [0.12, 0.07, 0.04, 0.02], [1, 0.6, 0.4, 0.2])
    click = highpass(noise(n), 1500) * env(n, 0.0002, 0.006)
    knock = lowpass(noise(n), 600) * env(n, 0.001, 0.04)
    return fade_out(norm(body + 0.5 * norm(click) + 0.6 * norm(knock)))


def debris(i):
    n = int(0.6 * SR)
    g = grains(n, 260 + 80 * i, 8, 1500, 9000) * env(n, 0.003, 0.15)
    return fade_out(norm(g, 0.7))


def roll_loop():
    n = int(5.0 * SR)
    t = np.arange(n) / SR
    rumble = lowpass(brown(n), 160)
    # yavaş dalgalanan genlik: kaya yüzeyindeki düzensizlikler
    wobble = 0.75 + 0.25 * np.sin(2 * np.pi * 1.7 * t) * np.sin(2 * np.pi * 0.43 * t + 1)
    crunch = grains(n, 90, 18, 400, 4500)
    gravel = bandpass(noise(n), 1500, 6000) * 0.15
    x = norm(rumble) * wobble + 0.35 * norm(crunch) + 0.1 * norm(gravel)
    return norm(make_loop(x), 0.85)


def wind_loop():
    n = int(12.0 * SR)
    t = np.arange(n) / SR
    cut = 500 + 350 * np.sin(2 * np.pi * 0.07 * t) + 200 * np.sin(2 * np.pi * 0.19 * t + 2)
    w = lowpass(noise(n), cut)
    w = highpass(w, 60)
    gust = 0.6 + 0.4 * np.sin(2 * np.pi * 0.11 * t) ** 2
    return norm(make_loop(norm(w) * gust, 1.5), 0.6)


def crash_big():
    n = int(3.0 * SR)
    boom = lowpass(noise(n), 120) * env(n, 0.004, 0.5)
    crumble = grains(n, 400, 20, 400, 7000) * env(n, 0.05, 0.9)
    crack = bandpass(noise(n), 800, 6000) * env(n, 0.0005, 0.05)
    return fade_out(norm(norm(boom) + 0.6 * norm(crumble) + 0.5 * norm(crack)), 0.2)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for i in range(3):
        write_wav(f"rock_impact_{i}", rock_impact(i))
        write_wav(f"brick_impact_{i}", brick_impact(i))
        write_wav(f"debris_{i}", debris(i))
    for i in range(2):
        write_wav(f"wood_impact_{i}", wood_impact(i))
    write_wav("crash_big", crash_big())
    write_wav("roll_loop", roll_loop(), loop=True)
    write_wav("wind_loop", wind_loop(), loop=True)
