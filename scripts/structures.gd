class_name Structures
extends RefCounted
## Bloklardan kurulan hazır yapılar. Bloklar birbirinin içine geçmez (serbest kalınca
## patlamasın diye): kirişler direkler arasına tam oturur.


## Ahşap gözetleme kulesi: 4 direk (her biri 4 parça), kat kirişleri, platform, korkuluk, çatı.
static func wood_tower() -> BlockStructure:
	var s := BlockStructure.new()
	s.name = "AhsapKule"
	s.kind = "wood"
	s.max_span = 2.0
	var h := 1.6  # direk yarı aralığı
	var post := 0.32
	var sec := 3.0
	s.min_columns = 3
	for k in 4:
		var col := 0
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				s.add_block(Vector3(sx * h, sec * k + sec * 0.5, sz * h), Vector3(post, sec - 0.02, post), k, "wood", {"column": col})
				col += 1
		if k > 0:
			# Direkler arası kuşak kirişleri (direk yüzeyleri arasına tam oturur)
			var y := sec * k
			var inner := h * 2.0 - post
			for sz in [-1.0, 1.0]:
				s.add_block(Vector3(0, y, sz * h), Vector3(inner - 0.02, 0.24, 0.24), k, "wood")
			for sx in [-1.0, 1.0]:
				s.add_block(Vector3(sx * h, y + 0.26, 0), Vector3(0.24, 0.24, inner - 0.02), k, "wood")
	# Platform tahtaları (direklerin üstünde)
	var top := sec * 4.0
	for i in 6:
		s.add_block(Vector3(0, top + 0.07, -1.65 + i * 0.66), Vector3(4.0, 0.12, 0.64), 4, "wood")
	# Korkuluk direkleri + küpeşte
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			s.add_block(Vector3(sx * 1.85, top + 0.13 + 0.55, sz * 1.85), Vector3(0.18, 1.1, 0.18), 5, "wood")
	for sz in [-1.0, 1.0]:
		s.add_block(Vector3(0, top + 1.3, sz * 1.85), Vector3(3.5, 0.12, 0.12), 6, "wood")
	# Çatı: dört kısa direk + kalın kapak
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			s.add_block(Vector3(sx * 1.85, top + 1.24 + 0.9, sz * 1.85), Vector3(0.18, 1.8, 0.18), 6, "wood")
	s.add_block(Vector3(0, top + 3.04 + 0.125, 0), Vector3(4.6, 0.25, 4.6), 7, "wood")
	s.finalize()
	return s


## Çelik su kulesi: 4 ayak (3 parça), kuşak kirişleri, platform ve suyla dolu ağır depo.
## Ayaklar kırılınca ~200 tonluk depo düşer ve altını ezer.
static func water_tower() -> BlockStructure:
	var s := BlockStructure.new()
	s.name = "SuKulesi"
	s.kind = "metal"
	s.max_span = 2.0
	var h := 3.0
	var leg := 0.5
	var sec := 4.0
	s.min_columns = 3
	for k in 3:
		var col := 0
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				s.add_block(Vector3(sx * h, sec * k + sec * 0.5, sz * h), Vector3(leg, sec - 0.02, leg), k, "steel", {"column": col})
				col += 1
		if k > 0:
			var inner := h * 2.0 - leg
			for sz in [-1.0, 1.0]:
				s.add_block(Vector3(0, sec * k, sz * h), Vector3(inner - 0.02, 0.3, 0.3), k, "steel")
			for sx in [-1.0, 1.0]:
				s.add_block(Vector3(sx * h, sec * k + 0.32, 0), Vector3(0.3, 0.3, inner - 0.02), k, "steel")
	var top := sec * 3.0
	s.add_block(Vector3(0, top + 0.2, 0), Vector3(7.6, 0.4, 7.6), 3, "steel")
	# Depo: su dolu (ortalama yoğunluk ~1000 kg/m³)
	s.add_block(Vector3(0, top + 0.4 + 3.0, 0), Vector3(7.0, 6.0, 7.0), 4, "steel", {"shape": "cylinder", "density": 1000.0, "strength": 120000.0})
	s.finalize()
	return s


## Cam sera: ince çelik dikmeler, cam duvar ve çatı panelleri.
static func greenhouse() -> BlockStructure:
	var s := BlockStructure.new()
	s.name = "Sera"
	s.kind = "glass"
	s.max_span = 2.0
	var lx := 9.0
	var lz := 5.0
	var hgt := 3.0
	var p := 0.12
	var nx := 6
	var nz := 3
	# Dikmeler
	var xs: Array[float] = []
	for i in nx + 1:
		xs.append(-lx * 0.5 + lx * i / nx)
	var zs: Array[float] = []
	for i in nz + 1:
		zs.append(-lz * 0.5 + lz * i / nz)
	for x in xs:
		for z in [-lz * 0.5, lz * 0.5]:
			s.add_block(Vector3(x, hgt * 0.5, z), Vector3(p, hgt, p), 0, "steel")
	for z in zs.slice(1, nz):
		for x in [-lx * 0.5, lx * 0.5]:
			s.add_block(Vector3(x, hgt * 0.5, z), Vector3(p, hgt, p), 0, "steel")
	# Duvar camları (dikmeler arası)
	for i in nx:
		var cx := (xs[i] + xs[i + 1]) * 0.5
		var w := xs[i + 1] - xs[i] - p - 0.02
		for z in [-lz * 0.5, lz * 0.5]:
			s.add_block(Vector3(cx, hgt * 0.5, z), Vector3(w, hgt - 0.05, 0.03), 0, "glass")
	for i in nz:
		var cz := (zs[i] + zs[i + 1]) * 0.5
		var w := zs[i + 1] - zs[i] - p - 0.02
		for x in [-lx * 0.5, lx * 0.5]:
			s.add_block(Vector3(x, hgt * 0.5, cz), Vector3(0.03, hgt - 0.05, w), 0, "glass")
	# Çatı kirişleri ve çatı camları
	for z in [-lz * 0.5, lz * 0.5]:
		s.add_block(Vector3(0, hgt + 0.06, z), Vector3(lx + p, 0.12, p), 1, "steel")
	for i in nx:
		var cx := (xs[i] + xs[i + 1]) * 0.5
		s.add_block(Vector3(cx, hgt + 0.08, 0), Vector3(xs[i + 1] - xs[i] - 0.04, 0.03, lz - p - 0.04), 1, "glass")
	s.finalize()
	return s


## Beton köprü: 3 ayak (beton kolon), ayaklar üstünde başlık, 2.5 m'lik tabliye parçaları,
## çelik korkuluk. X ekseni boyunca uzanır (yerel -12..+12). Ortadaki ayak koparsa iki
## açıklık birden çöker.
static func bridge() -> BlockStructure:
	var s := BlockStructure.new()
	s.name = "Kopru"
	s.kind = "concrete"
	s.max_span = 2.5
	var h := 6.0
	var seg := 2.5
	var piers := [-10.0, 0.0, 10.0]
	for px in piers:
		for k in 3:
			s.add_block(Vector3(px, h / 3.0 * k + h / 6.0, 0), Vector3(1.2, h / 3.0 - 0.02, 1.6), k, "concrete")
		s.add_block(Vector3(px, h + 0.3, 0), Vector3(2.0, 0.58, 6.0), 3, "concrete")  # başlık
	# Tabliye: başlıkların üstünden -12.5..+12.5
	var n := 10
	for i in n:
		var x := -12.5 + seg * (i + 0.5)
		s.add_block(Vector3(x, h + 0.8, 0), Vector3(seg - 0.02, 0.4, 6.0), 4, "concrete")
		for sz in [-1.0, 1.0]:
			s.add_block(Vector3(x, h + 1.5, sz * 2.85), Vector3(seg - 0.02, 0.1, 0.1), 5, "steel")
			s.add_block(Vector3(x - seg * 0.5 + 0.1, h + 1.25, sz * 2.85), Vector3(0.1, 0.38, 0.1), 5, "steel")
	s.finalize()
	return s


## Ahşap elektrik direği: 3 parça gövde + üstte travers (çapraz kol). top_point(): kablo ucu.
static func power_pole() -> BlockStructure:
	var s := BlockStructure.new()
	s.name = "Direk"
	s.kind = "wood"
	s.max_span = 1.0
	s.min_columns = 1
	for k in 3:
		s.add_block(Vector3(0, 3.0 * k + 1.5, 0), Vector3(0.3, 2.98, 0.3), k, "wood", {"shape": "cylinder", "column": 0})
	s.add_block(Vector3(0, 8.6, 0), Vector3(0.16, 0.16, 2.4), 3, "wood")
	s.finalize()
	return s
