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
    "explosion_a": 235968, "explosion_b": 255111,
    "saw_free": 448133, "saw_cut": 267636,
    "catapult_launch": 479922,
    "countryside": 514550, "countryside_b": 458113,
    "rock_slide": 655368, "rockslide_b": 608957,
    "sling_1": 513934, "sling_2": 513933, "sling_3": 853649,
}


def fetch(sid):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"{sid}.ogg")
    meta_path = os.path.join(CACHE, f"{sid}.json")
    if not os.path.exists(path):
        # Freesound, Python'un HTTP istemcisini sık reddediyor; curl kullan
        out = subprocess.run(["curl", "-sSL", "-A", UA["User-Agent"], "-w", "\n%{url_effective}",
                              f"https://freesound.org/s/{sid}/"], capture_output=True, check=True).stdout.decode()
        page, final_url = out.rsplit("\n", 1)
        user = re.search(r"/people/([^/]+)/sounds/", final_url).group(1)
        title = html.unescape(re.search(r'<meta property="og:title" content="([^"]+)"', page).group(1))
        assert "Creative Commons 0" in page, f"{sid} CC0 değil"
        prev = re.search(r"(https://cdn.freesound.org/previews/\d+/%d_\d+)-(?:hq|lq)\.(?:ogg|mp3)" % sid, page).group(1)
        # Bazı yeni kayıtlarda yalnız MP3 önizleme var (ffmpeg ikisini de çözer)
        for ext in ("-hq.ogg", "-hq.mp3", "-lq.ogg"):
            if subprocess.run(["curl", "-sSfL", "-A", UA["User-Agent"], "-o", path, prev + ext]).returncode == 0:
                break
        else:
            raise RuntimeError(f"{sid} önizleme indirilemedi")
        json.dump({"id": sid, "user": user, "title": title, "url": final_url}, open(meta_path, "w"))
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


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


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

    # Patlama (iki kayıt) ve top atışı (patlamanın kısa, tiz başı + gürleme)
    exa, exb = trim_silence(S["explosion_a"]), trim_silence(S["explosion_b"])
    write("explosion_0", fade(exa[:int(5.5 * SR)], 0.001, 1.5))
    write("explosion_1", fade(exb[:int(5.5 * SR)], 0.001, 1.5))
    write("explosion_2", fade(mix((exa[:int(4 * SR)], 0.7), (resample(exb[:int(3 * SR)], 0.8), 0.6)), 0.001, 1.2))
    write("cannon_0", fade(mix((exa[:int(1.6 * SR)], 1.0), (resample(exa[:int(1.2 * SR)], 1.4), 0.5)), 0.001, 0.8))
    write("cannon_1", fade(mix((exb[:int(1.6 * SR)], 1.0), (lowpass(exa[:int(1.6 * SR)], 400), 0.6)), 0.001, 0.8))

    # Dönen testere döngüsü: boşta dönen gerçek daire testere sesinin kararlı kısmı
    saw = S["saw_free"]
    env = np.sqrt(np.convolve(saw ** 2, np.ones(4410) / 4410, mode="same"))
    start = int(np.argmax(env > env.max() * 0.6)) + int(0.5 * SR)
    write("saw_loop", loop(saw[start:start + int(4 * SR)], 0.4), 0.8)

    # Mancınık: ahşap gerilme/kalkış kayıtları
    cat = S["catapult_launch"]
    for i, seg in enumerate(slices(cat, 2, 2.5, 3.0, 0.4)):
        write(f"catapult_{i}", seg, 0.85)
    for i, seg in enumerate(slices(cat, 2, 1.5, 1.0, 0.15)[:2]):
        write(f"creak_{i}", lowpass(seg, 3000), 0.6)

    # Sapan: lastik bırakma (+ pes katman: dev lastik)
    for i, k in enumerate(["sling_1", "sling_2", "sling_3"]):
        snap = fade(trim_silence(S[k]), 0.001, 0.3)
        write(f"sling_{i}", mix((snap, 1.0), (resample(snap, 0.6), 0.5)), 0.85)

    # Kır ambiyansı: kuşlar + uzak doğa. Mikrofon rüzgâr gürültüsü (<150 Hz) kesilir,
    # en sakin 40 sn'lik bölüm seçilir, dikişsiz döngü yapılır.
    amb = highpass(S["countryside"][:int(120 * SR)], 150.0)
    win = int(40 * SR)
    best, best_score = 0, 1e9
    for st in range(0, max(len(amb) - win, 1), int(5 * SR)):
        seg = amb[st:st + win]
        r = np.sqrt(np.convolve(seg ** 2, np.ones(SR) / SR, mode="valid")[::SR])
        score = r.max() / (r.mean() + 1e-9)  # ani patlamalar (araba, ses) olmayan kısım
        if score < best_score:
            best, best_score = st, score
    write("ambient_loop", loop(amb[best:best + win], 3.0), 0.5)

    # Taş yığını çöküşü (kale)
    for i, k in enumerate(["rock_slide", "rockslide_b"]):
        write(f"stone_crash_{i}", fade(trim_silence(S[k])[:int(6 * SR)], 0.001, 1.5), 0.85)

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
