# Kaya Yuvarla — prototip v0.2

Gerçekçi fizikli, dokunmatik kontrollü 3D mobil sandbox. Uzun beton rampadan kaya yuvarla; bariyerleri, duvarı ve **gerçek bina modellerini** yık.

- **Motor:** Godot 4.7.2 (stable), Mobile renderer
- **Fizik:** Jolt Physics (Godot'ta yerleşik), fizik interpolasyonu açık
- **Hedef:** Android (dokunmatik), yatay ekran

## Açma / test

1. Godot 4.7.2: https://godotengine.org/download
2. Godot → **Import** → `project.godot`. İlk açılışta modeller/dokular içe aktarılır (biraz sürer).
3. **F5**. Masaüstünde fare dokunmatiği taklit eder.

## Kontroller (sadece dokunmatik)

| Hareket | Ne yapar |
|---|---|
| Sağa-sola sürükle (fırlatmadan önce) | Kayayı hizala |
| Yukarı hızlı kaydır | İt (kaydırma hızı = güç) |
| **İT** | Sabit güçle it |
| Tek parmak (fırlattıktan sonra) | Kamerayı döndür |
| İki parmak kıstır | Yakınlaştır / uzaklaştır |
| **YENİ KAYA / BOYUT / AĞIR ÇEKİM / SIFIRLA** | — |
| **GRAFİK** | Düşük / Orta / Yüksek (mobilde varsayılan Orta) |
| **LİSANSLAR** | Model/ses atıfları |

Sol üstte FPS ve draw call sayısı görünür (telefonda test için).

## v0.2'de değişenler

- **Gerçek binalar** (Sketchfab, CC-BY): Sovyet panel apartman, Asya tipi kule blok, eski köşe bina, terk edilmiş tuğla fabrika, trafo binası.
  `tools/fracture_buildings.gd` her modeli önceden 4 m civarı hücrelere keser (toplam ~250 parça). Bina sağlamken **tek mesh** çizilir; ilk darbede parçalara geçer. Parçalar modelin kendi dokusunu taşır.
- **Gerçek kaya taraması** (yuvarlanan kaya + dekor kayalar), **beton bariyerler**, **variller**, **sandıklar**, **dinamik taşlar**.
- **Gerçek ses kayıtları** (Freesound, CC0): beton/kaya kırılması, moloz, bina çöküşü, cam, ahşap, metal, yuvarlanma, rüzgâr. Sentetik sesler kaldırıldı. Ağır kaya darbeleri: gerçek kayıt + yavaşlatılmış kopya + gövde katmanı.
- **Gereksiz arazi kaldırıldı**: rampa beton ayaklar üzerinde; zemin tek düzlem (2 üçgen) + tekrar desenini kıran shader.
- **Performans (kasma düzeltmeleri)**:
  - Parçalarda temas izleme (contact monitor) ve her karede script kaldırıldı; uyuyan gövde hiç kod çalıştırmaz.
  - Binalar sağlamken 1 draw call; kırılınca parçalar görünür.
  - Uzun süre yerinde titreyen moloz dondurulur; yeni kaya yaklaşınca çözülür.
  - Kaya durunca uyur (aksi hâlde dokunduğu tüm yığını uyanık tutuyordu).
  - Jolt adımları 6/1, uyku eşiği yükseltildi, fizik interpolasyonu.
  - Grafik kalitesi: gölge bölmeleri/mesafe, MSAA, 3D çözünürlük ölçeği.
  - Ölçüm (bu geliştirme sunucusu, render hariç, 60 Hz): boşta ~0.4 ms/kare, en yoğun yıkımda ~1.5–2 ms/kare; 30 sn'lik test simülasyonu toplam ~0.9 sn işlem.
- Hata düzeltmesi: Godot 4.7 + Jolt'ta ağaca girerken verilen uyku komutu yok sayılıyordu; parçalar ilk fizik karesinden sonra uyutuluyor.

## Dosya yapısı

```
scripts/main.gd            seviye, girdi, grafik kalitesi, otomatik test
scripts/building.gd        gerçek bina + önceden kesilmiş parçalar
scripts/destructible.gd    yıkılabilir parça (ses/toz, uyku/dondurma)
scripts/rock.gd            oyuncu kayası
scripts/models.gd          glTF yardımcıları (ölçek, dışbükey örtü)
scripts/world_builder.gd   ayaklı rampa, zemin, PBR malzemeler
scripts/game_camera.gd     takip kamerası
scripts/hud.gd             dokunmatik arayüz, lisans paneli
scripts/sfx.gd, fx.gd      ses havuzu/bus'lar, toz + sarsıntı (autoload)
assets/models/             işlenmiş modeller (dokular ≤2K)
assets/buildings/*.scn     kesilmiş binalar (fracture aracının çıktısı)
assets/sounds/             işlenmiş ses kayıtları (OGG)
tools/prepare_models.py    Sketchfab/Poly Haven indir + dokuları küçült
tools/fracture_buildings.gd binaları parçalara böl
tools/process_sounds.py    Freesound CC0 indir + kes/katmanla
```

Varlıkları yeniden üretmek:
```
SKETCHFAB_API_TOKEN=... python3 tools/prepare_models.py
godot --headless --path . --import
godot --headless --path . -s res://tools/fracture_buildings.gd
python3 tools/process_sounds.py
```

## Lisanslar

- Modeller: `assets/models/CREDITS_MODELS.md` (Sketchfab **CC-BY 4.0** → oyunda ve mağaza sayfasında atıf gerekli; oyunda LİSANSLAR panelinde gösteriliyor). Poly Haven modelleri CC0.
- Sesler: `assets/sounds/CREDITS_SOUNDS.md` (hepsi **CC0**).
- Dokular ve HDRI: Poly Haven, CC0.

## Geliştirici testi

```
godot --headless --path . --fixed-fps 60 -- --autotest
```
Kayayı fırlatır; her simülasyon saniyesinde konum, hız, yıkılan/uyanık parça, kırık bina ve işlem süresini yazar.
`-- --autotest --shots` ekran görüntüsü alır (görüntülü ortam gerekir).

## Yol haritası

1. ~~v0.1: temel oynanış~~
2. **v0.2 (bu sürüm):** gerçek modeller, gerçek sesler, parçalanan binalar, performans.
3. **v0.3:** gerçek telefonda profil (FPS hedefi 60), birden çok harita, görev modu (yıkım %, süre, yıldız).
4. **v0.4:** yeni eylemler — mancınık, çoklu kaya, araçlar, tekrar oynatma kamerası.
5. **Yayın:** menü, ayarlar, Play Store sürümü.
