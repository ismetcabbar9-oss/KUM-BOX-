# Kaya Yuvarla — prototip v0.1

Gerçekçi fizikli, dokunmatik kontrollü 3D mobil sandbox. Uzun beton rampadan kaya yuvarla; duvarı, sütunları, sandıkları ve binaları yık.

- **Motor:** Godot 4.7.2 (stable), Mobile renderer
- **Fizik:** Jolt Physics (Godot'ta yerleşik)
- **Hedef:** Android (dokunmatik), yatay ekran

## Açma / test

1. Godot 4.7.2'yi indir: https://godotengine.org/download
2. Godot → **Import** → bu klasördeki `project.godot`.
3. **F5** ile çalıştır. Masaüstünde fare dokunmatiği taklit eder (sol tık = parmak).

İlk açılışta dokular içe aktarılır (birkaç saniye).

## Kontroller (sadece dokunmatik)

| Hareket | Ne yapar |
|---|---|
| Sağa-sola sürükle (fırlatmadan önce) | Kayayı rampada hizala |
| Yukarı hızlı kaydır | Kayayı it (kaydırma hızı = itiş gücü) |
| **İT** butonu | Sabit güçle it |
| Tek parmak sürükle (fırlattıktan sonra) | Kamerayı döndür |
| İki parmak kıstır | Yakınlaştır / uzaklaştır |
| **YENİ KAYA** | Tepeye yeni kaya koy (en fazla 4 kaya sahnede kalır) |
| **BOYUT** | Küçük / Orta / Büyük kaya |
| **AĞIR ÇEKİM** | Zaman %30, ses perdesi de düşer |
| **SIFIRLA** | Seviyeyi baştan kur |

## İçerik

- 55 m yüksek, ~190 m uzun beton rampa (düz başlangıç platformu → dik iniş → yumuşak düzlük)
- Kaya: gürültüyle şekillendirilmiş mesh, küre çarpışma, granit yoğunluğu (Orta ≈ 80 ton)
- ~480 fizik parçası: şaşırtmalı tuğla duvar, kirişli sütun kalıntısı, sandık piramidi, variller, 3 panel bina (4, 3 ve 6 kat)
- Parçalar uykuda başlar (performans); çarpışma darbesine göre malzemeye özgü ses + toz
- HDRI gökyüzü, AgX tonlama, sis, yön ışığı gölgeleri, tepelik arazi
- Ses: kaya çarpması, tuğla/beton kırılma, ahşap, moloz, yuvarlanma döngüsü (hıza bağlı), rüzgâr ambiyansı; sıkıştırıcı + açık alan yankısı + limiter

## Dosya yapısı

```
project.godot           proje ayarları (Jolt, Mobile renderer, dokunmatik)
scenes/main.tscn        ana sahne
scripts/main.gd         seviye kurulumu, girdi, oyun durumu
scripts/world_builder.gd rampa / arazi / kaya mesh'i, PBR malzemeler
scripts/rock.gd         oyuncu kayası
scripts/destructible.gd yıkılabilir parça (darbe → ses/toz)
scripts/game_camera.gd  takip kamerası
scripts/hud.gd          dokunmatik arayüz
scripts/sfx.gd          ses havuzu + bus/efektler (autoload)
scripts/fx.gd           toz parçacıkları + kamera sarsıntısı (autoload)
assets/textures         Poly Haven CC0 PBR dokular (1K)
assets/hdri             Poly Haven CC0 HDRI gökyüzü
assets/sounds           tools/gen_sounds.py ile üretilmiş sesler
```

## Varlık lisansları

- Dokular ve HDRI: [Poly Haven](https://polyhaven.com), **CC0** (ticari kullanım serbest, atıf gerekmez).
- Sesler: bu projede prosedürel üretildi (`python3 tools/gen_sounds.py`), proje sahibine ait.
- Sketchfab: indirme hesap/API anahtarı ister ve modellerin lisansı tek tek kontrol edilmeli. Ücretli oyunda CC-BY-NC modeller kullanılamaz. Sonraki aşamada CC0/CC-BY modellerle (araçlar, ağaçlar, detaylı binalar) eklenecek.

## Android'e aktarma

`export_presets.cfg` içinde Android ön ayarı var. Godot'ta: Editor → Manage Export Templates → 4.7.2 indir; Editor Settings'te Android SDK/JDK yolu ve debug keystore; Project → Export → Android.

## Geliştirici testi

```
godot --headless --path . -- --autotest
```
Kayayı otomatik fırlatır, 30 sn boyunca konum/hız/yıkım sayısını yazdırır.

## Yol haritası

1. **v0.1 (bu sürüm):** temel oynanış — rampa, kaya, yıkılabilir yapılar, ses, dokunmatik.
2. **v0.2:** kırılma (parçalara bölünen paneller), daha zengin ses (gerçek kayıtlar), kalite ayarları (düşük/orta/yüksek), FPS ölçümü gerçek cihazda.
3. **v0.3:** birden çok harita, hedef/görev modu (yıkım yüzdesi, süre), yıldız puanı.
4. **v0.4:** yeni eylemler — sapan/mancınık, bomba kaya, çoklu kaya, araçlar, tekrar oynatma (replay) kamerası.
5. **Yayın:** optimizasyon, menü, ayarlar, Play Store sürümü.
