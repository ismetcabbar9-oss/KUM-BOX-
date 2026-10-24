class_name Fortress
extends BlockStructure
## Kesme taş örgü yapı parçası (kale halkası, ana kule, avlu binası). Castle birden çok
## Fortress'i bir araya getirir; hepsi ortak BrickPool'u kullanır. Parçalara bölmek, destek
## hesabını (_check_support) binlerce bloktan oluşan tek bir grafik yerine küçük
## grafiklerde tutar.
##
## Kesme taş ("masonry"): her blok bir Destructible'dır ve Building'in yapısal modelini
## kullanır (statik dondurulmuş, birikimli hasar, destek grafiği). Kopan blok BrickPool ile
## duvarda görünen tuğla ızgarasına ayrılır: yıkım iri kütleler değil, tuğlalar hâlinde olur.
##
## Kuleler: taban sıralarının (alt 3 sıra) yeterince kopunca kule ağırlığını taşıyamaz ve
## toptan çöker.

var row_h := 3.0
var thick := 3.0
var block := 4.5

## Kuleler: {"from", "to": blok indeks aralığı, "fallen", "center"}
var _towers: Array = []
const TOWER_BASE_ROWS := 3
const TOWER_COLLAPSE := 0.7  # taban sağlamlık oranı bunun altına inerse


func begin(part_name: String, pool: BrickPool) -> void:
	name = part_name
	kind = "concrete"
	# Taş örgü: oyuğun üstünde 1-2 sıra kemer gibi tutunur, daha yukarısı çöker
	max_span = 1.6
	hang_up = 0.6
	crash_sound = "stone_crash"
	brick_pool = pool


## Kare kule: dört duvar, tepede döşeme, döşeme kenarında mazgallar.
## cross: ortadan geçen iç duvar (geniş kulelerde döşemenin ortasını taşır).
## Döner: kule tepesinin (döşeme üstü) yüksekliği.
func tower(c: Vector3, w: float, rows: int, cross := false) -> float:
	var from := _defs.size()
	var h := w * 0.5
	var t2 := thick * 0.5
	wall(c + Vector3(-h, 0, -h + t2), c + Vector3(h, 0, -h + t2), rows, 0.0)
	wall(c + Vector3(-h, 0, h - t2), c + Vector3(h, 0, h - t2), rows, 0.0)
	wall(c + Vector3(-h + t2, 0, -h + thick), c + Vector3(-h + t2, 0, h - thick), rows, 0.0)
	wall(c + Vector3(h - t2, 0, -h + thick), c + Vector3(h - t2, 0, h - thick), rows, 0.0)
	if cross:
		wall(c + Vector3(0, 0, -h + thick), c + Vector3(0, 0, h - thick), rows, 0.0)
	# Tepe döşemesi: duvarların üstüne oturur (desteği alttaki duvar sırasından alır)
	var top := rows * row_h
	var n := maxi(1, roundi(w / block))
	var cell := w / n
	for i in n:
		for j in n:
			add_block(c + Vector3(-h + cell * (i + 0.5), top + 0.5, -h + cell * (j + 0.5)), Vector3(cell, 1.0, cell), rows, "masonry")
	# Mazgallar: döşeme kenarında
	var m := 1.5
	var count := int(w / (m * 2.0))
	var off := (w - (count * 2 - 1) * m) * 0.5
	for i in count:
		var a := -h + off + m * 0.5 + i * m * 2.0
		for s in [-1.0, 1.0]:
			add_block(c + Vector3(a, top + 1.0 + 0.75, s * (h - 0.5)), Vector3(m, 1.5, 1.0), rows + 1, "masonry")
			add_block(c + Vector3(s * (h - 0.5), top + 1.0 + 0.75, a), Vector3(1.0, 1.5, m), rows + 1, "masonry")
	_towers.append({"from": from, "to": _defs.size(), "fallen": false, "center": c})
	return top + 1.0


## a -> b ekseni boyunca (X ya da Z) duvar; şaşırtmalı örgü, isteğe bağlı kapı.
## outward: dış yön (+1/-1, duvara dik eksende); 0 = mazgal yok.
func wall(a: Vector3, b: Vector3, rows: int, outward: float, gate_w := 0.0, gate_rows := 3) -> void:
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	var length := absf((b - a).x if along_x else (b - a).z)
	if length < 0.3:
		return
	var n := maxi(1, roundi(length / block))
	var bl := length / n
	var start := minf(a.x, b.x) if along_x else minf(a.z, b.z)
	var fixed := a.z if along_x else a.x
	var mid := start + length * 0.5
	for r in rows:
		var y := a.y + r * row_h + row_h * 0.5
		# Tek sıralar yarım blokla başlar (şaşırtmalı)
		var cuts: Array[float] = [start]
		var p := start + (bl * 0.5 if r % 2 == 1 else 0.0)
		if r % 2 == 1:
			cuts.append(p)
		while p + bl < start + length - 0.01:
			p += bl
			cuts.append(p)
		cuts.append(start + length)
		for i in cuts.size() - 1:
			var c0: float = cuts[i]
			var c1: float = cuts[i + 1]
			if c1 - c0 < 0.3:
				continue
			var cc := (c0 + c1) * 0.5
			# Kapı boşluğu: alt gate_rows sıra
			if gate_w > 0.0 and r < gate_rows and absf(cc - mid) < gate_w * 0.5:
				continue
			var size := Vector3(c1 - c0, row_h, thick) if along_x else Vector3(thick, row_h, c1 - c0)
			var pos := Vector3(cc, y, fixed) if along_x else Vector3(fixed, y, cc)
			add_block(pos, size, r, "masonry")
	if outward != 0.0:
		# Mazgal dişleri: dış kenarda, aralıklı
		var m := 1.5
		var count := int(length / (m * 2.0))
		var off := (length - (count * 2 - 1) * m) * 0.5
		var edge := fixed + outward * (thick * 0.5 - 0.5)
		for i in count:
			var cc := start + off + m * 0.5 + i * m * 2.0
			var size := Vector3(m, 1.5, 1.0) if along_x else Vector3(1.0, 1.5, m)
			var y := a.y + rows * row_h + 0.75
			var pos := Vector3(cc, y, edge) if along_x else Vector3(edge, y, cc)
			add_block(pos, size, rows, "masonry")


## Avlu binası: taş duvarlar (kapı boşluğuyla) + ahşap beşik çatı (mahya uzun kenar boyunca).
## size: x = X genişliği, z = Z derinliği. door: kapının olduğu yüz (-Z: 0, +Z: 1, -X: 2, +X: 3)
func house(c: Vector3, size: Vector3, rows: int, door: int) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var t2 := thick * 0.5
	var doors := [0.0, 0.0, 0.0, 0.0]
	doors[door] = 2.4
	wall(c + Vector3(-hx, 0, -hz + t2), c + Vector3(hx, 0, -hz + t2), rows, 0.0, doors[0], 1)
	wall(c + Vector3(-hx, 0, hz - t2), c + Vector3(hx, 0, hz - t2), rows, 0.0, doors[1], 1)
	wall(c + Vector3(-hx + t2, 0, -hz + thick), c + Vector3(-hx + t2, 0, hz - thick), rows, 0.0, doors[2], 1)
	wall(c + Vector3(hx - t2, 0, -hz + thick), c + Vector3(hx - t2, 0, hz - thick), rows, 0.0, doors[3], 1)
	roof(c + Vector3(0, rows * row_h, 0), size, rows)


## Ahşap beşik çatı: iki eğimli kalas sırası (30°) + mahya kirişi
func roof(base: Vector3, size: Vector3, layer: int) -> void:
	var along_x := size.x >= size.z
	var length := (size.x if along_x else size.z) + 1.0
	var span := (size.z if along_x else size.x) * 0.5 + 0.6
	var pitch := deg_to_rad(30.0)
	var slope := span / cos(pitch)
	var n := maxi(1, roundi(length / 1.5))
	var pw := length / n
	for i in n:
		var u := -length * 0.5 + pw * (i + 0.5)
		for s in [-1.0, 1.0]:
			var d := span * 0.5
			var y := base.y + 0.15 + tan(pitch) * (span - d)
			var basis: Basis
			var pos: Vector3
			var bsize: Vector3
			if along_x:
				basis = Basis(Vector3.RIGHT, s * pitch)
				pos = Vector3(base.x + u, y, base.z + s * d)
				bsize = Vector3(pw - 0.04, 0.22, slope)
			else:
				basis = Basis(Vector3.BACK, -s * pitch)
				pos = Vector3(base.x + s * d, y, base.z + u)
				bsize = Vector3(slope, 0.22, pw - 0.04)
			add_block(pos, bsize, layer, "wood", {"basis": basis})
	var ridge_y := base.y + 0.15 + tan(pitch) * span + 0.1
	add_block(Vector3(base.x, ridge_y, base.z), Vector3(length, 0.3, 0.3) if along_x else Vector3(0.3, 0.3, length), layer + 1, "wood")


## Ahşap sundurma (ahır): direkler + çatı, duvarsız
func shed(c: Vector3, size: Vector3, height: float) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var nx := maxi(1, roundi(size.x / 4.0))
	var nz := maxi(1, roundi(size.z / 4.0))
	for i in nx + 1:
		for j in nz + 1:
			if i > 0 and i < nx and j > 0 and j < nz:
				continue  # yalnız çevre direkleri
			add_block(c + Vector3(-hx + size.x * i / nx, height * 0.5, -hz + size.z * j / nz), Vector3(0.4, height, 0.4), 0, "wood")
	# Kiriş çerçevesi (direklerin üstünde) + çatı
	for s in [-1.0, 1.0]:
		add_block(c + Vector3(0, height + 0.15, s * hz), Vector3(size.x + 0.4, 0.3, 0.3), 1, "wood")
		add_block(c + Vector3(s * hx, height + 0.15, 0), Vector3(0.3, 0.3, size.z - 0.3), 1, "wood")
	roof(c + Vector3(0, height + 0.3, 0), size, 2)


func _check_support() -> void:
	super()
	for t: Dictionary in _towers:
		if t["fallen"]:
			continue
		if not t.has("blocks"):
			# Kule bloklarını bir kez topla (sonra yalnız taban sayılır)
			var all: Array[Destructible] = []
			var base_list: Array[Destructible] = []
			for b in chunks:
				var i: int = b.get_meta("def", -1)
				if i >= t["from"] and i < t["to"]:
					all.append(b)
					if b.layer < TOWER_BASE_ROWS:
						base_list.append(b)
			t["blocks"] = all
			t["base"] = base_list
		var blocks: Array = t["blocks"]
		var total: int = t["base"].size()
		var ok := 0
		for b in t["base"]:
			if is_instance_valid(b) and b.intact:
				ok += 1
		if total > 0 and float(ok) / total < TOWER_COLLAPSE:
			t["fallen"] = true
			# Kule devrilir: dışa doğru ortak eğilim, üst kısımlar daha çok savrulur
			var c: Vector3 = t["center"]
			var out := Vector3(c.x, 0, c.z).normalized()
			var lean := (out + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))).normalized()
			for b in blocks:
				if is_instance_valid(b) and b.intact:
					b.release(global_transform.basis * lean * b.mass * (0.2 + b.position.y * 0.05), b.global_position + Vector3.UP)
			Sfx.crash(to_global(c + Vector3.UP * 15.0), crash_sound)
			Fx.shake(1.0)
			Fx.big_dust(to_global(c + Vector3.UP * 6.0))
			# Çöküş sürerken taban çevresinde ikinci toz dalgası
			get_tree().create_timer(1.8).timeout.connect(func() -> void: Fx.big_dust(to_global(c + Vector3.UP * 3.0)))
