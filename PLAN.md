# Geliştirme planı (kademeli)

Kural: temel oynanış oturmadan harita/görev sistemine geçilmez. Her aşama sonunda
otomatik test + ekran görüntüsü + commit + ZIP.

## Aşama 1 — Kontrol ve his düzeltmeleri  ✅ (v0.4)
- [x] Sapan: çek-bırak. Ne kadar geri çekilirse o kadar güç; parmak kalkınca kendiliğinden atar. Buton gerekmez.
- [x] Mermi boyutu 5 kademe: ÇOK KÜÇÜK, KÜÇÜK, ORTA, BÜYÜK, DEV.
- [x] Çevre sesi değişti (sert rüzgâr yerine yumuşak kır ambiyansı, düşük seviye).
- [x] Dikey ve yatay ekran: arayüz yönlendirmeye göre yeniden dizilir, kamera görüş açısı uyarlanır.
- [x] Hedef yerleşimi: her fırlatıcının önünde kendi düzenli şeridi (dağınık taşlar kaldırıldı).

## Aşama 2 — Dev kale  ✅ (v0.4)
- [x] Ayrı harita: tek, devasa taş kale (surlar, 4 kule, iç kale/donjon, mazgallar).
- [x] Taş bloklar birikimli hasar alır: aynı yere tekrar tekrar vurdukça çatlar ve kopar. Hedef: 20–30 iyi atışta yıkım.
- [x] Sağlam bloklar tek MultiMesh ile çizilir (yüzlerce blok ≈ birkaç draw call).
- [x] HARİTA butonu: Test alanı / Kale.

## Aşama 3 — Fizik derinliği ve yeni obje türleri  ✅ (v0.5)
- [x] Malzeme çeşitliliği (BlockStructure): taş, ahşap (kolay kırılır, kopan kiriş ikiye kırılır), çelik (çok dayanıklı, bölünmez), cam (koptuğu an tuzla buz), beton.
- [x] Bina kat döşemeleri: duvarlar yıkılınca döşemeler düşer, alt katları ezer (pancake).
- [x] İkinci kademe kırılma: bina parçalarının önceden hesaplanmış iki yarısı; kutu parçalar (taş blok, döşeme, kiriş, tuğla) sert düşüşte ikiye bölünür. Kuşak sınırı + kare başı bütçe + toplam tavan (grafik kalitesine bağlı).
- [x] Taşıyıcı ayak kuralı: 4 ayaklı yapılarda 2 ayak koparsa yapı devrilir.
- [x] Yeni yapılar: ahşap gözetleme kulesi, çelik su kulesi (≈200 t su deposu), cam sera.
- [x] Yeni objeler: 4 araç (terk edilmiş sedan, LADA 2107, Moskvitch kamyonet, kutu kamyon), çelik I-kiriş yığını, kütük yığını, çam ağaçları.
- [x] Köprü, elektrik direkleri (Aşama 4'te eklendi).

## Aşama 4 — Rampa ve fırlatıcı çeşitleri  ✅ (v0.6)
- [x] Rampa türleri (AYAR butonu): klasik, kayak atlama, S-kıvrım (yatışlı), spiral, tepeli (kicker'lar).
- [x] Roket kızağı: U-kanalda kızak, itki ayarı, tampona çarpınca mermi kalkış dudağından uçar.
- [x] Sarkaçlı yıkım vinci: zincirli gülle geri çekilip savrulur, sallanırken zincir kesilebilir.
- [x] Yeni mermi: zincirli gülle, üçlü testere, yapışkan bomba.
- [x] Yeni hedef şeridi: elektrik hattı (kablolar direk kırılınca kopar) + beton köprü.
- [ ] Buldozer ve çift şeritli rampa → Aşama 5'e (haritalarla birlikte).

## Ara sürüm v0.7 (istek üzerine)  ✅
- [x] İki taş devri adamı: tüm fırlatıcılarda ekip; rampada kayayı iterek fırlatır.
- [x] Kale yeniden: 4 kule (ön 2 kısa, arka 2 yüksek), ~4 kat büyük, tuğla tuğla yıkım, 15–20 iyi atışta yıkılır.
- [x] 29 asker (kuleler, surlar, avlu).
- [x] Kale haritasında güçlendirilmiş mancınık rampanın tepesinde.

## Yaşayan Kale planı (v0.8 → v1.0)
- [x] A: İç içe kale (dış/iç halka, ana kule, hendek, asma köprü, avlu binaları, sancak)
- [x] B: Daha küçük tuğla (0,75 m) + görsel tuğla parçacıkları + moloz yığınları + çatlaklar
- [ ] C: Kalabalık (60–120 figür, mesafeye göre detay), okçular, devriye, işçiler, kaçışma, sesler
- [ ] D: Mancınık nişan yardımı, kuşatma görevleri + yıldız, yavaş çekim tekrar kamerası, yangın

## Aşama 5 — Görevler ve haritalar
- Görev türleri: X atışta Y% yıkım, belirli hedefi düşür, zincirleme çöküş, süre.
- Yıldız puanı, ilerleme kaydı.
- Haritalar: şehir bloğu, liman (konteynerler), kale kuşatması, maden ocağı.

## Aşama 6 — Grafik
- Daha iyi gökyüzü/ışık (gün saati), toz/duman kalitesi, yumuşak gölgeler.
- Çatlak dokuları, decal izleri (çarpma lekesi), kırık kenar detayı.
- Bitki örtüsü (çim kümeleri, çalılar – MultiMesh), uzak manzara.

## Aşama 7 — Ses
- Katmanlı çarpma sesleri (malzeme × kütle × hız), uzaklık gecikmesi, yankı bölgeleri.
- Taş kale için taş kırılma/çökme kayıtları, ahşap gıcırtı, metal gürültü.

## Aşama 8 — Optimizasyon ve yayın hazırlığı
- Gerçek cihazda profil (hedef 60 FPS orta segment).
- Moloz havuzu, uzak parçaların uykuya alınması, LOD, gölge mesafeleri.
- Menü, ayarlar, kayıt, Play Store paketleme.
