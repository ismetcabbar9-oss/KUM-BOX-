#!/usr/bin/env python3
"""OpenGameArt CC0 seslerini indirir, keser, oyuna hazır OGG'lere çevirir (kale kalabalığı).

Çalıştırma:  python3 tools/process_sounds_oga.py [önbellek_klasörü]
Gerekenler:  ffmpeg (libvorbis), numpy
Çıktı:       assets/sounds/*.ogg  +  CREDITS_SOUNDS.md'ye ek bölüm
Not: Freesound bu ortamdan erişilemediği için kalabalık sesleri OpenGameArt'tan (CC0) alınır.
"""
import os
import subprocess
import sys
import zipfile

import numpy as np

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "sounds")
CACHE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".sound_cache", "oga")
UA = "Mozilla/5.0"
BASE = "https://opengameart.org/sites/default/files/"

# dosya: (OpenGameArt sayfası, yazar, başlık)
SOURCES = {
    "theircoming3_0.ogg": ("their-coming-generic-horn-sound", "StumpyStrust", "Their Coming (generic horn sound)"),
    "theircoming_0.ogg": ("their-coming-generic-horn-sound", "StumpyStrust", "Their Coming (generic horn sound)"),
    "crowd_shouting_0.ogg": ("crowd-shoutingspeaking-ambience", "StarNinjas", "Crowd Shouting/Speaking Ambience"),
    "death%20pain%20grunts.wav": ("grunts-male-death-and-pain", "thebardofblasphemy", "grunts of male death and pain"),
    "yelling%20sounds.zip": ("male-gruntyelling-sounds", "HaelDB", "Male Grunt/Yelling sounds"),
    "swishes.zip": ("swishes-sound-pack", "artisticdude", "Swishes Sound Pack"),
    "100-CC0-wood-metal-SFX.zip": ("100-cc0-metal-and-wood-sfx", "rubberduck", "100 CC0 metal and wood SFX"),
    "forger_0.ogg": ("hammer-on-anvil", "themightyglider", "Hammer on Anvil"),
    "fire.wav": ("fireplace-sound-loop", "PagDev", "Fireplace Sound loop"),
    "fire-1_0.ogg": ("fire-crackling", "AntumDeluge", "Fire Crackling"),
}


def fetch(name):
    os.makedirs(CACHE, exist_ok=True)
    local = os.path.join(CACHE, name.replace("%20", "_"))
    if not os.path.exists(local):
        subprocess.run(["curl", "-sfL", "-A", UA, "-o", local, BASE + name], check=True)
    if local.endswith(".zip"):
        d = local[:-4]
        if not os.path.isdir(d):
            zipfile.ZipFile(local).extractall(d)
        return d
    return local


def load(path):
    x = subprocess.run(["ffmpeg", "-v", "quiet", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                       capture_output=True, check=True).stdout
    return np.frombuffer(x, dtype=np.float32).astype(np.float64)


def find(d, fname):
    for r, _, fs in os.walk(d):
        if "__MACOSX" in r:
            continue
        if fname in fs:
            return os.path.join(r, fname)
    raise FileNotFoundError(fname)


def norm(x, peak=0.89):
    return x * (peak / (np.max(np.abs(x)) + 1e-9))


def fade(x, fin=0.003, fout=0.06):
    x = x.copy()
    a, b = int(fin * SR), min(int(fout * SR), len(x) // 2)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def trim(x, thr=0.02):
    env = np.abs(x)
    idx = np.where(env > thr * env.max())[0]
    return x[idx[0]:idx[-1] + 1] if len(idx) else x


def segments(x, min_gap=0.25, thr=0.06, min_len=0.25):
    """Sessizlikle ayrılmış parçalar (çığlık/inleme kayıtlarını tek tek ayırmak için)."""
    win = int(0.02 * SR)
    env = np.convolve(np.abs(x), np.ones(win) / win, mode="same")
    on = env > thr * env.max()
    out, start, quiet = [], None, 0
    for i in range(0, len(on), win):
        if on[i]:
            if start is None:
                start = i
            quiet = 0
        elif start is not None:
            quiet += win
            if quiet > min_gap * SR:
                end = i - quiet + win
                if end - start > min_len * SR:
                    out.append(x[max(0, start - win):end + win])
                start, quiet = None, 0
    return out


def loop(x, xfade=0.8):
    n = int(xfade * SR)
    head, tail = x[:n], x[-n:]
    t = np.linspace(0, 1, n)
    body = x[n:-n].copy()
    return np.concatenate([body, tail * (1 - t) + head * t])


def write(name, x, peak=0.89):
    path = os.path.join(OUT, name + ".ogg")
    pcm = (norm(x, peak) * 32767).astype(np.int16).tobytes()
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", path], input=pcm, check=True)
    print("yazıldı", name, f"{len(x) / SR:.2f} sn")


def main():
    files = {k: fetch(k) for k in SOURCES}
    # Borazan (alarm)
    write("horn_0", fade(trim(load(files["theircoming3_0.ogg"])), 0.01, 0.4), 0.85)
    write("horn_1", fade(trim(load(files["theircoming_0.ogg"]))[:int(6.5 * SR)], 0.01, 1.2), 0.85)
    # Kalabalık bağırış döngüsü (alarm sırasında)
    crowd = load(files["crowd_shouting_0.ogg"])
    write("crowd_loop", loop(crowd[int(2 * SR):int(16 * SR)]), 0.7)
    # Ölüm/acı inlemeleri: kayıttan en güçlü parçalar
    segs = segments(load(files["death%20pain%20grunts.wav"]))
    segs = sorted(segs, key=lambda s: -np.sqrt(np.mean(s ** 2)))[:8]
    for i, s in enumerate(segs):
        write(f"scream_{i}", fade(s[:int(1.6 * SR)], 0.003, 0.15), 0.8)
    # Savaş/korku bağırışları
    yd = files["yelling%20sounds.zip"]
    for i, f in enumerate(["yell3.wav", "yell5.wav", "yell8.wav", "1yell4.wav", "2yell6.wav", "3yell2.wav"]):
        write(f"yell_{i}", fade(trim(load(find(yd, f)))), 0.75)
    # Ok: vınlama + tahtaya/toprağa saplanma
    sd = files["swishes.zip"]
    for i, f in enumerate(["swish-2.wav", "swish-6.wav", "swish-11.wav"]):
        write(f"arrow_whoosh_{i}", fade(trim(load(find(sd, f)))), 0.7)
    wd = files["100-CC0-wood-metal-SFX.zip"]
    for i, f in enumerate(["wood_hit_02.ogg", "wood_hit_05.ogg", "wood_hit_08.ogg"]):
        write(f"arrow_hit_{i}", fade(trim(load(find(wd, f)))[:int(0.5 * SR)]), 0.7)
    # Demirci: örs + çekiç
    write("anvil_0", fade(trim(load(files["forger_0.ogg"])), 0.002, 0.2), 0.8)
    for i, f in enumerate(["hammer_01.ogg", "hammer_03.ogg"]):
        write(f"anvil_{i + 1}", fade(trim(load(find(wd, f)))), 0.8)
    # Yangın: çıtırtı döngüsü + tutuşma
    fire = load(files["fire.wav"])
    write("fire_loop", loop(fire[:min(len(fire), int(12 * SR))], 1.0), 0.8)
    write("ignite_0", fade(trim(load(files["fire-1_0.ogg"]))[:int(2.5 * SR)], 0.005, 0.6), 0.85)
    # Atıflar
    cred = os.path.join(OUT, "CREDITS_SOUNDS.md")
    text = open(cred).read()
    marker = "\n## OpenGameArt (CC0)\n"
    if marker in text:
        text = text[:text.index(marker)]
    lines = [marker, "Freesound bu geliştirme ortamından erişilemediği için kale kalabalığı sesleri OpenGameArt'tan alındı (hepsi CC0).\n"]
    seen = set()
    for page, author, title in SOURCES.values():
        if page in seen:
            continue
        seen.add(page)
        lines.append(f"- [{title}](https://opengameart.org/content/{page}) — {author}")
    open(cred, "w").write(text.rstrip("\n") + "\n" + "\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
