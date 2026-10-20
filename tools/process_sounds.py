#!/usr/bin/env python3
"""Freesound CC0 kayıtlarını indirir, keser, katmanlar ve oyuna hazır OGG'lere çevirir.

Çalıştırma:  python3 tools/process_sounds.py [önbellek_klasörü]
Gerekenler:  ffmpeg (libvorbis), numpy
Çıktı:       assets/sounds/*.ogg  +  assets/sounds/CREDITS_SOUNDS.md
Tüm kaynaklar Creative Commons 0 (kamu malı); atıf zorunlu değil ama listeleniyor.
"""
import html
import json
import os
import re
import subprocess
import sys
import urllib.request

import numpy as np

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "sounds")
CACHE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".sound_cache")
UA = {"User-Agent": "Mozilla/5.0"}

# Freesound ses kimlikleri (hepsi CC0)
IDS = {
    "concrete_smash_2": 522099, "concrete_smash": 522098, "collision": 332058,
    "rock_smash": 512243, "small_rock_hits": 179365, "concrete_hit_2": 321478,
    "big_debris": 703247, "fall_debris": 703248, "collapse_a": 712918, "collapse_b": 845932,
    "concrete_breaks": 843339, "gravel_falling": 567249, "stones_falling": 567251,
    "dropping_rocks": 567250, "rockfall": 381645, "tumbling_rocks": 488660,
    "rumble_loop": 258339, "rolling_ball": 260778,
    "crate_break_4": 66780, "crate_destroy": 500902, "crate_impact_1": 667655,
    "crate_impact_2": 667654, "crate_break_2": 667652,
    "drum_soft": 524817, "metal_hard": 488589, "metal_impact": 530486,
    "glass_a": 221528, "glass_b": 141563, "glass_c": 536763,
    "wind_light": 352436,
}


def fetch(sid):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"{sid}.ogg")
    meta_path = os.path.join(CACHE, f"{sid}.json")
    if not os.path.exists(path):
        r = urllib.request.urlopen(urllib.request.Request(f"https://freesound.org/s/{sid}/", headers=UA))
        page = r.read().decode()
        user = re.search(r"/people/([^/]+)/sounds/", r.geturl()).group(1)
        title = html.unescape(re.search(r'<meta property="og:title" content="([^"]+)"', page).group(1))
        assert "Creative Commons 0" in page, f"{sid} CC0 değil"
        prev = re.search(r"(https://cdn.freesound.org/previews/\d+/%d_\d+)-(?:hq|lq)\.(?:ogg|mp3)" % sid, page).group(1)
        data = urllib.request.urlopen(urllib.request.Request(prev + "-hq.ogg", headers=UA)).read()
        open(path, "wb").write(data)
        json.dump({"id": sid, "user": user, "title": title, "url": r.geturl()}, open(meta_path, "w"))
    x = subprocess.run(["ffmpeg", "-v", "quiet", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                       capture_output=True, check=True).stdout
    return np.frombuffer(x, dtype=np.float32).astype(np.float64), json.load(open(meta_path))


def norm(x, peak=0.89):
    return x * (peak / (np.max(np.abs(x)) + 1e-9))


def fade(x, fin=0.002, fout=0.08):
    x = x.copy()
    a, b = int(fin * SR), min(int(fout * SR), len(x) // 2)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def resample(x, ratio):
    """ratio < 1 -> daha yavaş ve pes (büyük kütle hissi)."""
    idx = np.arange(0, len(x) - 1, ratio)
    return np.interp(idx, np.arange(len(x)), x)


def lowpass(x, cutoff):
    a = 1.0 - np.exp(-2.0 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    s = 0.0
    for i in range(len(x)):
        s += a * (x[i] - s)
        y[i] = s
    return y


def mix(*layers):
    n = max(len(l) for l, _ in layers)
    out = np.zeros(n)
    for l, g in layers:
        out[:len(l)] += l * g
    return out


def trim_silence(x, thr=0.01):
    env = np.abs(x)
    idx = np.where(env > thr * env.max())[0]
    if len(idx) == 0:
        return x
    return x[max(idx[0] - int(0.003 * SR), 0): idx[-1] + int(0.05 * SR)]


def onsets(x, min_gap=0.25, rel=0.3):
    env = np.sqrt(np.convolve(x ** 2, np.ones(256) / 256, mode="same"))
    thr = env.max() * rel
    res, last = [], -1e9
    i = 1
    while i < len(env):
        if env[i] > thr and env[i - 1] <= thr and (i - last) > min_gap * SR:
            res.append(i)
            last = i
        i += 1
    return res


def slices(x, count, length, min_gap=0.25, rel=0.3):
    out = []
    for o in onsets(x, min_gap, rel):
        start = max(o - int(0.004 * SR), 0)
        seg = x[start:start + int(length * SR)]
        if len(seg) > 0.1 * SR:
            out.append(fade(seg, 0.001, length * 0.5))
        if len(out) >= count:
            break
    return out


def loop(x, xfade=1.0):
    n = int(xfade * SR)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    w = np.linspace(0, 1, n)
    return np.concatenate([body, tail * np.sqrt(1 - w) + head * np.sqrt(w)])


written = []


def write(name, x, peak=0.89):
    x = norm(x, peak)
    path = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "f64le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", path], input=x.astype("<f8").tobytes(), check=True)
    written.append(name)


def main():
    os.makedirs(OUT, exist_ok=True)
    S, M = {}, {}
    for key, sid in IDS.items():
        S[key], M[key] = fetch(sid)

    thud = trim_silence(S["drum_soft"])
    # Kaya darbeleri: gerçek beton/kaya kırılması + yavaşlatılmış kopya + gövde (varil "thud") katmanı
    rock_src = [trim_silence(S["concrete_smash"]), trim_silence(S["concrete_smash_2"]), trim_silence(S["collision"])]
    rock_src += slices(S["rock_smash"], 3, 1.2)
    for i, src in enumerate(rock_src[:6]):
        body = lowpass(resample(thud, 0.55 + 0.05 * i), 500)
        heavy = resample(src, 0.62)
        write(f"rock_impact_{i}", fade(mix((src, 0.55), (heavy, 0.8), (body, 0.9)), 0.001, 0.3))

    # Tuğla/beton parça darbeleri
    conc = [trim_silence(S["concrete_hit_2"])] + slices(S["concrete_breaks"], 4, 0.9) + slices(S["small_rock_hits"], 3, 0.6)
    for i, src in enumerate(conc[:7]):
        write(f"concrete_impact_{i}", fade(mix((src, 1.0), (resample(src, 0.8), 0.5)), 0.001, 0.2), 0.8)

    # Moloz / çakıl dökülmesi
    deb = slices(S["gravel_falling"], 2, 1.4, 0.8, 0.5) + slices(S["stones_falling"], 2, 1.4, 0.8, 0.5) \
        + slices(S["dropping_rocks"], 2, 1.4, 0.8, 0.5)
    for i, src in enumerate(deb[:6]):
        write(f"debris_{i}", src, 0.7)

    # Büyük çöküş
    write("crash_big_0", fade(trim_silence(S["big_debris"]), 0.001, 0.8))
    write("crash_big_1", fade(trim_silence(S["collapse_b"]), 0.001, 1.0))
    write("crash_big_2", fade(mix((trim_silence(S["collapse_a"]), 1.0), (resample(trim_silence(S["fall_debris"]), 0.85), 0.6)), 0.001, 0.8))

    # Ahşap
    wood = [S["crate_impact_1"], S["crate_impact_2"], S["crate_break_2"], S["crate_break_4"], S["crate_destroy"]]
    for i, src in enumerate(wood):
        write(f"wood_impact_{i}", fade(trim_silence(src), 0.001, 0.15), 0.8)

    # Metal (varil)
    metal = [S["drum_soft"], S["metal_impact"], S["metal_hard"]]
    for i, src in enumerate(metal):
        write(f"metal_impact_{i}", fade(trim_silence(src), 0.001, 0.25), 0.8)

    # Cam (bina ilk yıkıldığında)
    for i, k in enumerate(["glass_a", "glass_b", "glass_c"]):
        write(f"glass_{i}", fade(trim_silence(S[k]), 0.001, 0.4), 0.7)

    # Yuvarlanma döngüsü: gerçek gürleme döngüsü + yavaşlatılmış yuvarlanan top + kaya dökülmesi dokusu
    rumble = S["rumble_loop"]
    ball = resample(np.tile(S["rolling_ball"], 3), 0.7)[:len(rumble)]
    grit = lowpass(np.tile(S["tumbling_rocks"], 2)[:len(rumble)], 2500)
    roll = mix((rumble, 1.0), (ball, 0.45), (grit, 0.25))
    write("roll_loop", loop(roll, 0.8), 0.85)

    # Rüzgâr ambiyansı (30 sn, dikişsiz)
    wind = S["wind_light"][int(5 * SR):int(37 * SR)]
    write("wind_loop", loop(wind, 2.0), 0.5)

    with open(os.path.join(OUT, "CREDITS_SOUNDS.md"), "w") as f:
        f.write("# Ses kaynakları\n\nTüm kayıtlar Freesound.org, **Creative Commons 0**. "
                "İşlenmiş hâlleri (kesme, katmanlama, perde) bu projede üretildi.\n\n")
        for key in IDS:
            m = M[key]
            f.write(f"- [{m['title']}]({m['url']}) — {m['user']}\n")
    print("yazıldı:", len(written), "dosya")


if __name__ == "__main__":
    main()
