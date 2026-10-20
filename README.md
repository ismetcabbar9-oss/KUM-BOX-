# Kaya Yuvarla — prototip v0.6

Geliştirme planı: [PLAN.md](PLAN.md) (kademeli aşamalar).

Gerçekçi fizikli, dokunmatik kontrollü 3D mobil sandbox. Uzun beton rampadan kaya yuvarla; bariyerleri, duvarı ve **gerçek bina modellerini** yık.

- **Motor:** Godot 4.7.2 (stable), Mobile renderer
- **Fizik:** Jolt Physics (Godot'ta yerleşik), fizik interpolasyonu açık
- **Hedef:** Android (dokunmatik), yatay ekran

## Açma / test

1. Godot 4.7.2: https://godotengine.org/download
2. Godot → **Import** → `project.godot`. İlk açılışta modeller/dokular içe aktarılır (biraz sürer).
3. **F5**. Masaüstünde fare dokunmatiği taklit eder.

## Kontroller (sadece dokunmatik)

Sağdaki butonlar: **FIRLAT/YÜKLE**, **fırlatıcı** (dokundukça değişir), **mermi** (dokundukça değişir), **BOYUT**, **AĞIR ÇEKİM**, **SIFIRLA**. Fırlattıktan sonra tek parmak kamerayı döndürür, iki parmak yakınlaştırır.

| Fırlatıcı | Kontrol | Fizik |
|---|---|---|
| **RAMPA** | yana sürükle: hizala, yukarı kaydır: it | 55 m beton rampa, yerçekimiyle yuvarlanma |
| **MANCINIK** | yana: yön, yukarı/aşağı: karşı ağırlık (30–180 t) | menteşeli kol + serbest sallanan karşı ağırlık + kaşık; bırakma pimi 48°'de çözülür |
| **DEV SAPAN** | çek-bırak: parmağı koy, geri (aşağı) çek, yana nişan al, bırakınca atar; güç = çekme mesafesi | iki lastik Hooke yasasıyla (F = k·x) çeker; ağır mermi daha yavaş çıkar |
| **HAVA TOPU** | yana: yön, yukarı/aşağı: namlu açısı | sabit basınç enerjisi (½mv² = E) |
| **ROKET KIZAĞI** | yukarı/aşağı: itki gücü, FIRLAT: ateşle | kızak kanalda roket itkisiyle hızlanır, tampona çarpıp durur; mermi ataletle 8° dudaktan uçar |
| **YIKIM VİNCİ** | parmağı koy, aşağı çek: gülleyi kaldır, bırak: savur; sallanırken KES | bom ucuna menteşeli (PinJoint) 15 m zincir; gerçek sarkaç, kesince gülle teğet hızla uçar |

Sapan ve topta sarı noktalar tahmini yörüngeyi gösterir.

**Mermiler:** Granit, Bazalt, Yosunlu kaya, Kumtaşı, Dere taşı (gerçek kaya taramaları, farklı yoğunluklar), **Dönen testere** (yüksek devirle döner, yere değince ileri atılır, binaları keserek az enerji kaybeder), **Çelik gülle** (7.85 t/m³), **Patlayıcı varil** (çarpınca patlar: yapıya hasar + çevreye itki).

**Yeni mermiler (v0.6):** **Zincirli gülle** (havada ikiye ayrılır, aradaki esnemez zincirle dönerek uçar), **Üçlü testere** (havada ±8° açıyla üç diske ayrılır), **Yapışkan bomba** (değdiği yere yapışır, hızlanan bip sesleriyle 1,8 sn sonra patlar; hareketli gövdeye iğnelenir).

**Engeller:** dönen çelik pervane (kinematik), sallanan yıkım gülle sarkacı (gerçek menteşe), konteyner yığınları, beton bariyerler, tuğla duvar, variller, sandıklar, taşlar.

## v0.6'da değişenler (Aşama 4)

- **5 rampa türü** (AYAR butonu): KLASİK, KAYAK ATLAMA (kaya havalanır), S-KIVRIM (yatışlı virajlar), SPİRAL (72 m'den 1,25 tur), TEPELİ. Rampalar yol boyunca süpürülerek üretiliyor (`WorldBuilder.build_path_ramp`): yatış eğriliğe göre, duvarlar düşük sürtünmeli, ayaklar alttan geçen rampa kısmına basmıyor.
- **Roket kızağı** (x=22 şeridi) ve **sarkaçlı yıkım vinci** (Sovyet apartmanın yanında).
- **Zincirli gülle, üçlü testere, yapışkan bomba.**
- **Yeni hedefler:** beton köprü (3 ayak, tabliye ayak koparsa çöker), elektrik hattı (ahşap direkler, kablolar direk kırılınca kopar).
- Yeni gerçek sesler (Freesound CC0): roket ateşleme/itki döngüsü, zincir, bip.
- Ertelendi: buldozer ve çift şeritli rampa (Aşama 5).

## v0.5'te değişenler (Aşama 3)

- **Malzemeler:** taş, ahşap, çelik, cam, beton blokları farklı yoğunluk/dayanım/kırılma davranışıyla (`scripts/block_structure.gd`).
- **Yeni yapılar** (`scripts/structures.gd`): ahşap gözetleme kulesi, çelik su kulesi (suyla dolu ağır depo), cam sera. 4 ayaklı yapılarda 2 ayak koparsa yapı devrilir.
- **Binalarda kat döşemeleri:** duvarlar gidince döşemeler düşüp alt katları ezer.
- **İkinci kademe kırılma:** kopan bina parçası sert çarpışmada önceden hesaplanmış iki yarısına ayrılır; taş blok, döşeme, kiriş, tuğla gibi kutu parçalar ikiye bölünür (performans bütçeli).
- **Cam:** koptuğu an tuzla buz olur (parlak kırık parçacıkları + cam sesi).
- **Yeni objeler:** terk edilmiş sedan, LADA 2107, Moskvitch kamyonet, kutu kamyon (Sketchfab CC-BY), çelik I-kiriş yığını, kütük yığını, çam ağaçları.

## v0.4'te değişenler

- **Sapan çek-bırak:** buton yok. Ne kadar geri çekersen o kadar güç; parmağı kaldırınca kendiliğinden atar. Az çekip bırakırsan iptal olur.
- **5 boyut:** ÇOK KÜÇÜK, KÜÇÜK, ORTA, BÜYÜK, DEV (DEV rampa kayası ~960 t).
- **Dev kale haritası** (HARİTA butonu): ~1000 taş bloktan surlar, 4 kule, donjon, kapı, mazgallar. Bloklar birikimli hasar alır (aynı yere vurdukça çatlar, kopar); oyuğun üstü kemer gibi 1 sıra tutunur, daha yukarısı çöker. Testte 30 adet 12 MJ'lik darbe (≈ ORTA rampa kayası) kalenin ~%70'ini yıktı. Sağlam bloklar MultiMesh ile çizilir.
- **Dikey ve yatay ekran:** arayüz ve kamera yönlendirmeye uyar.
- **Düzenli hedef şeritleri:** her fırlatıcının önünde kendi hedefleri.
- **Yeni çevre sesi:** kuş ağırlıklı kır ambiyansı (rüzgâr uğultusu filtrelendi).
- Düzeltme: statikten çözülen parçaya verilen itki kayboluyordu; kopan parçalar artık darbe yönünde fırlıyor.

## v0.3'te değişenler

- **Yeni yıkım sistemi (kâğıt gibi dağılma yok):** bina parçaları artık dolu. Her cephe parçası içe doğru 35–50 cm kalınlaştırıldı, iç yüzleri ve kırık kenarları beton/tuğla malzemesiyle kaplı. Kesimler her katta kaydırılmış ve eğik; ızgara gibi değil, kırılmış gibi duruyor.
- **Yapısal bütünlük:** bina ayaktayken tüm parçalar statik (fizik maliyeti sıfır). Darbe enerjisi çarpma noktası çevresine dağılır; yalnız dayanımı aşılan parçalar kopar. Kırmaya giden enerji mermiden düşülür: sağlam bina ağır kayayı durdurur. Desteği kopan üst kısımlar kendi ağırlığıyla çöker; düşen ağır parçalar alttaki katları ezer.
- **Kaya tabanları kapatıldı:** taramalardaki açık tabanlar sınır kenarlarından bulunup dolduruldu (`tools/prepare_rocks.gd`); saydam gelen malzeme opak yapıldı. Kayalara LOD üretildi.
- Görsel moloz parçacıkları (zemine çarpan küçük taşlar), patlama efekti (ışık, ateş, duman).
- Yeni gerçek sesler (Freesound CC0): patlama, top, daire testere döngüsü, mancınık, sapan lastiği.
- Hata düzeltmesi: döngü sesleri (yuvarlanma, rüzgâr) döngüye ayarlı değildi, birkaç saniye sonra susuyordu.

## v0.2'de değişenler (önceki sürüm)

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
godot --headless --path . -s res://tools/prepare_rocks.gd
python3 tools/process_sounds.py
python3 tools/fetch_textures.py
```

## Lisanslar

- Modeller: `assets/models/CREDITS_MODELS.md` (Sketchfab **CC-BY 4.0** → oyunda ve mağaza sayfasında atıf gerekli; oyunda LİSANSLAR panelinde gösteriliyor). Poly Haven modelleri CC0.
- Sesler: `assets/sounds/CREDITS_SOUNDS.md` (hepsi **CC0**).
- Dokular ve HDRI: Poly Haven, CC0.

## Geliştirici testi

```
godot --headless --path . --fixed-fps 60 -- --autotest --launcher=1 --ammo=saw
```
`--map=castle` kale haritası, `--siege=N` N gerçek atış, `--siege-synth=N` N yapay 12 MJ darbe (denge testi).
`--launcher`: 0 rampa, 1 mancınık, 2 sapan, 3 top, 4 roket kızağı, 5 yıkım vinci (`--cut=SN` SN saniye sonra zinciri keser). `--ramp=0..4` rampa türü. `--ammo`: granite, basalt, mossy, sandstone, river, saw, steel, bomb, chain, multisaw, sticky. `--trace` ilk 2,5 sn'yi adım adım yazar.
`-- --autotest --shots` ekran görüntüsü alır (görüntülü ortam gerekir).

## Yol haritası

1. ~~v0.1: temel oynanış~~
2. ~~v0.2: gerçek modeller, gerçek sesler, performans~~
3. **v0.3 (bu sürüm):** fırlatıcılar, mermi türleri, engeller, dolu parçalı yapısal yıkım.
4. **Sıradaki:** telefonda his/FPS ayarı, tekrar oynatma kamerası, daha fazla fırlatıcı/mermi; temel oynanış oturunca haritalar ve görevler.
5. **Yayın:** menü, ayarlar, Play Store sürümü.
