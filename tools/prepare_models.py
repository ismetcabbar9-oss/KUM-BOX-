#!/usr/bin/env python3
"""Sketchfab (CC-BY) ve Poly Haven (CC0) modellerini indirir, dokuları mobile göre küçültür.

Çalıştırma:  SKETCHFAB_API_TOKEN=... python3 tools/prepare_models.py [önbellek_klasörü]
Çıktı:       assets/models/<ad>/scene.gltf (+bin, dokular) ve assets/models/CREDITS_MODELS.md
"""
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
import zipfile

from PIL import Image

Image.MAX_IMAGE_PIXELS = None
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "models")
CACHE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".model_cache")
UA = {"User-Agent": "Mozilla/5.0"}

# ad: (sketchfab uid, ana doku boyutu)
SKETCHFAB = {
    "rock_hero": ("b66d5b63deb447299ca3effa904bc789", 1024),
    "rock_boulder2": ("70fd18ec2a4a4d378d9d8c1ba878dcbc", 1024),
    "rock_medium": ("54cef4772d2a442680d5f18dcb2f93e7", 1024),
    "rocks4": ("a3db6dd1c31b4c63a8ce372d470bdf5d", 1024),
    "smooth_rocks": ("4503b42e55fd4fd4b42f0f18abc43298", 1024),
    "border_stone": ("ed49866dbdfd4b52aad3edaabc63c70f", 1024),
    "saw": ("98d471f4e3ec40ec97703867e04a0a61", 1024),
    "pine_a": ("fbd656918d5e4126b82c7b41432aff5f", 1024),
    "pine_b": ("dc3fbd9205cf4027a4455d1f415e0478", 1024),
    "caveman_a": ("3ba4da569fae4f2eb1a84988c90cc5ed", 1024),
    "caveman_b": ("83d99a21ce154571bdf6d4ecef2fe183", 1024),
    "soldier": ("271c26d2137a46f6911b09566b552d14", 512),
    "anim_donor": ("f1775be7b1b94e4ea40d25287585ee69", 256),  # yalnız animasyonları kullanılır
    "peasant": ("e279c8bba68941088c6de68b7b7aeab7", 512),
    "peasant_swing": ("a1b90d1f7d834f17a24b7a7c2429cd2f", 512),  # yalnız animasyonu
    "peasant_idle": ("2a2ab18caa6e48b0a709d7ef52a78e70", 512),  # yalnız animasyonu
    "archer": ("dda7a92d3bbf4a7aacfb5a2ed9bdf6d8", 512),
}
POLYHAVEN = {"barrel": "Barrel_01"}


def get(url, headers=None):
    return urllib.request.urlopen(urllib.request.Request(url, headers=headers or UA)).read()


def sketchfab(name, uid):
    token = os.environ["SKETCHFAB_API_TOKEN"]
    h = {"Authorization": "Token " + token}
    dst = os.path.join(CACHE, name)
    info_path = os.path.join(CACHE, name + ".json")
    if not os.path.exists(os.path.join(dst, "scene.gltf")):
        info = json.loads(get(f"https://api.sketchfab.com/v3/models/{uid}", h))
        dl = json.loads(get(f"https://api.sketchfab.com/v3/models/{uid}/download", h))
        # Büyük arşivler: curl (urllib uzun indirmede kopuyor)
        data = subprocess.run(["curl", "-sfL", "--retry", "3", dl["gltf"]["url"]], check=True, capture_output=True).stdout
        zipfile.ZipFile(io.BytesIO(data)).extractall(dst)
        json.dump({"title": info["name"], "author": info["user"]["displayName"],
                   "license": info["license"]["label"], "url": info["viewerUrl"]}, open(info_path, "w"))
    return dst, json.load(open(info_path))


def polyhaven(name, asset):
    dst = os.path.join(CACHE, name)
    if not os.path.exists(os.path.join(dst, "scene.gltf")):
        files = json.loads(get(f"https://api.polyhaven.com/files/{asset}"))
        g = files["gltf"]["1k"]["gltf"]
        os.makedirs(dst, exist_ok=True)
        open(os.path.join(dst, "scene.gltf"), "wb").write(get(g["url"]))
        for rel, f in g["include"].items():
            p = os.path.join(dst, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            data = get(f["url"])
            assert hashlib.md5(data).hexdigest() == f["md5"]
            open(p, "wb").write(data)
        # Poly Haven gltf'i bin dosyasını kendi adıyla arar
        gl = json.load(open(os.path.join(dst, "scene.gltf")))
        for b in gl["buffers"]:
            b["uri"] = os.path.basename(b["uri"])
        json.dump(gl, open(os.path.join(dst, "scene.gltf"), "w"))
    return dst, {"title": asset, "author": "Poly Haven", "license": "CC0",
                 "url": f"https://polyhaven.com/a/{asset}"}


def convert(name, src, max_size):
    dst = os.path.join(OUT, name)
    shutil.rmtree(dst, ignore_errors=True)
    os.makedirs(os.path.join(dst, "textures"))
    gl = json.load(open(os.path.join(src, "scene.gltf")))
    for b in gl["buffers"]:
        shutil.copy(os.path.join(src, urllib.parse.unquote(b["uri"])), os.path.join(dst, os.path.basename(b["uri"])))
        b["uri"] = os.path.basename(b["uri"])
    # Hangi görüntü hangi rolde: renk dokusu büyük, diğerleri yarı boyut
    roles = {}
    for m in gl.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        if "baseColorTexture" in pbr:
            roles[gl["textures"][pbr["baseColorTexture"]["index"]]["source"]] = "color"
        sg = m.get("extensions", {}).get("KHR_materials_pbrSpecularGlossiness", {})
        if "diffuseTexture" in sg:
            roles[gl["textures"][sg["diffuseTexture"]["index"]]["source"]] = "color"
    for i, im in enumerate(gl.get("images", [])):
        p = os.path.join(src, urllib.parse.unquote(im["uri"]))
        img = Image.open(p)
        size = max_size if roles.get(i) == "color" else max(max_size // 2, 512)
        if max(img.size) > size:
            img = img.resize((size, size) if img.size[0] == img.size[1] else
                             (size, int(img.size[1] * size / img.size[0])), Image.LANCZOS)
        has_alpha = img.mode in ("RGBA", "LA") and img.getchannel("A").getextrema()[0] < 250
        base = f"tex{i}"
        if has_alpha:
            out, mime = base + ".png", "image/png"
            img.save(os.path.join(dst, "textures", out), optimize=True)
        else:
            out, mime = base + ".jpg", "image/jpeg"
            img.convert("RGB").save(os.path.join(dst, "textures", out), quality=90)
        im["uri"] = "textures/" + out
        im["mimeType"] = mime
    json.dump(gl, open(os.path.join(dst, "scene.gltf"), "w"))
    size = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(dst) for f in fs)
    print(f"{name:14} {size // 1024:6} KB")


def main():
    os.makedirs(CACHE, exist_ok=True)
    credits = []
    for name, (uid, size) in SKETCHFAB.items():
        src, info = sketchfab(name, uid)
        convert(name, src, size)
        credits.append((name, info))
    for name, asset in POLYHAVEN.items():
        src, info = polyhaven(name, asset)
        convert(name, src, 1024)
        credits.append((name, info))
    with open(os.path.join(OUT, "CREDITS_MODELS.md"), "w") as f:
        f.write("# 3D model kaynakları\n\nSketchfab modelleri **CC Attribution 4.0** lisanslıdır: oyunda ve "
                "mağaza sayfasında aşağıdaki atıflar gösterilmelidir. Poly Haven modelleri **CC0**.\n"
                "Dokular mobil için küçültüldü; bina modelleri oyunda yıkılabilir parçalara bölünür.\n\n")
        for name, i in credits:
            f.write(f"- `{name}`: \"{i['title']}\" — {i['author']} — {i['license']} — {i['url']}\n")


if __name__ == "__main__":
    main()
