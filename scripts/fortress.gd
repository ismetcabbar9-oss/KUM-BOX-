class_name Fortress
extends BlockStructure
## Dev taş kale: dört kule (öndeki ikisi kısa, arkadaki ikisi çok daha yüksek), aralarında
## surlar, ön surda kapı, kule tepelerinde döşeme ve mazgallar.
##
## Kesme taş örgü ("masonry"): her blok bir Destructible'dır ve Building'in yapısal modelini
## kullanır (statik dondurulmuş, birikimli hasar, destek grafiği). Kopan blok BrickPool ile
## duvarda görünen tuğla ızgarasına (1.5 × 1 × 1 m) ayrılır: yıkım iri kütleler değil,
## tek tek tuğlalar hâlinde olur.
##
## Askerler: kule tepelerinde, sur yürüyüş yolunda ve avluda durur (soldier_spots).

const ROW_H := 3.0
const THICK := 3.0
const BLOCK := 4.5
const BRICK := Vector3(1.5, 1.0, 1.0)

## [yerel konum, bakış açısı (radyan)]
var soldier_spots: Array = []
## Kuleler: {"from", "to": blok indeks aralığı, "fallen"}. Taban sıralarının (alt 3 sıra)
## yeterince kopunca kule ağırlığını taşıyamaz ve toptan çöker.
var _towers: Array = []
const TOWER_BASE_ROWS := 3
const TOWER_COLLAPSE := 0.7  # taban sağlamlık oranı bunun altına inerse


func setup_castle() -> void:
	name = "Kale"
	kind = "concrete"
	# Taş örgü: oyuğun üstünde 1-2 sıra kemer gibi tutunur, daha yukarısı çöker
	max_span = 1.6
	hang_up = 0.6
	crash_sound = "stone_crash"
	brick_pool = BrickPool.new()
	brick_pool.name = "Tuglalar"
	brick_pool.setup(material("masonry"), BRICK, "stone", 2300.0)
	add_child(brick_pool)
	# Yerel koordinat: kale merkezi orijinde, ön yüz -Z (fırlatıcılara bakar)
	var cx := 52.0
	var cz := 42.0
	var front_w := 18.0
	var back_w := 20.0
	var front_rows := 9  # 27 m
	var back_rows := 15  # 45 m
	var wall_rows := 6  # 18 m
	for sx in [-1.0, 1.0]:
		_tower(Vector3(sx * cx, 0, -cz), front_w, front_rows)
		_tower(Vector3(sx * cx, 0, cz), back_w, back_rows)
	# Surlar: ön (kapılı), arka, iki yan
	var fi := cx - front_w * 0.5
	var bi := cx - back_w * 0.5
	_wall(Vector3(-fi, 0, -cz), Vector3(fi, 0, -cz), wall_rows, -1.0, 10.0)
	_wall(Vector3(-bi, 0, cz), Vector3(bi, 0, cz), wall_rows, 1.0)
	for sx in [-1.0, 1.0]:
		_wall(Vector3(sx * cx, 0, -cz + front_w * 0.5), Vector3(sx * cx, 0, cz - back_w * 0.5), wall_rows, sx)
	finalize()
	_place_soldiers(cx, cz, front_w, back_w, front_rows, back_rows, wall_rows)


func _place_soldiers(cx: float, cz: float, fw: float, bw: float, fr: int, br: int, wr: int) -> void:
	var front := PI  # -Z'ye bak (fırlatıcılara)
	# Kule tepeleri: 3'er asker
	for sx in [-1.0, 1.0]:
		var ft := fr * ROW_H + 1.0
		var bt := br * ROW_H + 1.0
		for k in 3:
			var o := (k - 1) * 3.5
			soldier_spots.append([Vector3(sx * cx + o, ft, -cz - fw * 0.5 + 3.2), front])
			soldier_spots.append([Vector3(sx * cx + o, bt, cz - bw * 0.5 + 3.2), front])
	# Ön sur yürüyüş yolu (dişlerin arkasında): 6 asker
	var wt := wr * ROW_H
	for k in 6:
		var x := -30.0 + k * 12.0
		if absf(x) < 4.0:
			x += 5.0
		soldier_spots.append([Vector3(x, wt, -cz + 0.7), front])
	# Yan surlar: 2'şer
	for sx in [-1.0, 1.0]:
		for k in 2:
			soldier_spots.append([Vector3(sx * (cx - 0.7), wt, -12.0 + k * 22.0), front + sx * 0.5])
	# Avlu: 7 asker (kapının arkasında ve ortada)
	var yard := [Vector3(-6, 0, -30), Vector3(6, 0, -30), Vector3(0, 0, -24), Vector3(-18, 0, -10),
		Vector3(18, 0, -8), Vector3(-8, 0, 8), Vector3(10, 0, 14)]
	for p: Vector3 in yard:
		soldier_spots.append([p, front + randf_range(-0.4, 0.4)])


## Kare kule: dört duvar, tepede döşeme, döşeme kenarında mazgallar
func _tower(c: Vector3, w: float, rows: int) -> void:
	var from := _defs.size()
	_tower_blocks(c, w, rows)
	_towers.append({"from": from, "to": _defs.size(), "fallen": false, "center": c})


func _tower_blocks(c: Vector3, w: float, rows: int) -> void:
	var h := w * 0.5
	var t2 := THICK * 0.5
	_wall(c + Vector3(-h, 0, -h + t2), c + Vector3(h, 0, -h + t2), rows, 0.0)
	_wall(c + Vector3(-h, 0, h - t2), c + Vector3(h, 0, h - t2), rows, 0.0)
	_wall(c + Vector3(-h + t2, 0, -h + THICK), c + Vector3(-h + t2, 0, h - THICK), rows, 0.0)
	_wall(c + Vector3(h - t2, 0, -h + THICK), c + Vector3(h - t2, 0, h - THICK), rows, 0.0)
	# Tepe döşemesi: duvarların üstüne oturur (desteği alttaki duvar sırasından alır)
	var top := rows * ROW_H
	var n := maxi(1, roundi(w / BLOCK))
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


## a -> b ekseni boyunca (X ya da Z) duvar; şaşırtmalı örgü, isteğe bağlı kapı.
## outward: dış yön (+1/-1, duvara dik eksende); 0 = mazgal yok (kule duvarı).
func _wall(a: Vector3, b: Vector3, rows: int, outward: float, gate_w := 0.0) -> void:
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	var length := absf((b - a).x if along_x else (b - a).z)
	var n := maxi(1, roundi(length / BLOCK))
	var bl := length / n
	var start := minf(a.x, b.x) if along_x else minf(a.z, b.z)
	var fixed := a.z if along_x else a.x
	var mid := start + length * 0.5
	for r in rows:
		var y := r * ROW_H + ROW_H * 0.5
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
			# Kapı boşluğu: alt 3 sıra
			if gate_w > 0.0 and r < 3 and absf(cc - mid) < gate_w * 0.5:
				continue
			var size := Vector3(c1 - c0, ROW_H, THICK) if along_x else Vector3(THICK, ROW_H, c1 - c0)
			var pos := Vector3(cc, y, fixed) if along_x else Vector3(fixed, y, cc)
			add_block(pos, size, r, "masonry")
	if outward != 0.0:
		# Mazgal dişleri: dış kenarda, aralıklı
		var m := 1.5
		var count := int(length / (m * 2.0))
		var off := (length - (count * 2 - 1) * m) * 0.5
		var edge := fixed + outward * (THICK * 0.5 - 0.5)
		for i in count:
			var cc := start + off + m * 0.5 + i * m * 2.0
			var size := Vector3(m, 1.5, 1.0) if along_x else Vector3(1.0, 1.5, m)
			var y := rows * ROW_H + 0.75
			var pos := Vector3(cc, y, edge) if along_x else Vector3(edge, y, cc)
			add_block(pos, size, rows, "masonry")


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
