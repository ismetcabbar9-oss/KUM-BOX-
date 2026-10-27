#!/usr/bin/env python3
"""Poly Haven CC0 PBR dokularını (1K: renk, normal, ARM) ve HDRI'yi indirir."""
import hashlib, json, os, urllib.request
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
UA = {"User-Agent": "Mozilla/5.0"}
TEXTURES = ["rocky_terrain_02", "concrete_floor_worn_001", "rough_concrete",
            "rough_wood", "metal_plate", "rusty_metal_02", "rock_boulder_dry"]


def get(u):
    return urllib.request.urlopen(urllib.request.Request(u, headers=UA)).read()


for t in TEXTURES:
    files = json.loads(get(f"https://api.polyhaven.com/files/{t}"))
    for key, short in [("Diffuse", "diff"), ("nor_gl", "nor_gl"), ("arm", "arm")]:
        path = os.path.join(ROOT, "assets", "textures", f"{t}_{short}_1k.jpg")
        if os.path.exists(path):
            continue
        f = files[key]["1k"]["jpg"]
        data = get(f["url"])
        assert hashlib.md5(data).hexdigest() == f["md5"]
        open(path, "wb").write(data)
    print(t, "ok")
