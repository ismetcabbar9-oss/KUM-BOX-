class_name Fortress
extends BlockStructure
## Dev taş kale: surlar, dört köşe kulesi, donjon (iç kale), kapı, mazgallar.
##
## Her taş blok bir Destructible'dır ve Building'in yapısal modelini kullanır
## (statik dondurulmuş, birikimli hasar, destek grafiği). Taş betondan dayanıklı:
## tek atış birkaç blok koparır, kale ancak 20-30 iyi atışta yıkılır.
##
## Çizim: sağlam bloklar boyutlarına göre gruplanıp MultiMesh ile çizilir (yüzlerce blok
## ≈ birkaç draw call). Kopan blok MultiMesh'ten gizlenir, kendi MeshInstance'ını alır.

const ROW_H := 2.5
const THICK := 3.0
const BLOCK := 4.0



func setup_castle() -> void:
	name = "Kale"
	kind = "concrete"
	# Taş örgü: oyuğun üstünde 1-2 sıra kemer gibi tutunur, daha yukarısı çöker
	max_span = 1.6
	hang_up = 0.6
	crash_sound = "stone_crash"
	# Yerel koordinat: kale merkezi orijinde, ön yüz -Z (fırlatıcılara bakar)
	var tw := 12.0  # kule genişliği
	var cx := 37.0
	var cz := 32.0
	# Köşe kuleleri (8 sıra = 20 m)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_tower(Vector3(sx * cx, 0, sz * cz), tw, 8)
	# Surlar (6 sıra = 15 m), ön surda kapı
	var inner := cx - tw * 0.5
	_wall(Vector3(-inner, 0, -cz), Vector3(inner, 0, -cz), 6, true, 8.0)
	_wall(Vector3(-inner, 0, cz), Vector3(inner, 0, cz), 6, true)
	var innz := cz - tw * 0.5
	_wall(Vector3(-cx, 0, -innz), Vector3(-cx, 0, innz), 6, true)
	_wall(Vector3(cx, 0, -innz), Vector3(cx, 0, innz), 6, true)
	# Donjon (10 sıra = 25 m)
	_tower(Vector3(0, 0, 6.0), 18.0, 10)
	finalize()


## Kare kule: dört duvar, tepede mazgal
func _tower(c: Vector3, w: float, rows: int) -> void:
	var h := w * 0.5
	var t2 := THICK * 0.5
	_wall(c + Vector3(-h, 0, -h + t2), c + Vector3(h, 0, -h + t2), rows, true)
	_wall(c + Vector3(-h, 0, h - t2), c + Vector3(h, 0, h - t2), rows, true)
	_wall(c + Vector3(-h + t2, 0, -h + THICK), c + Vector3(-h + t2, 0, h - THICK), rows, true)
	_wall(c + Vector3(h - t2, 0, -h + THICK), c + Vector3(h - t2, 0, h - THICK), rows, true)


## a -> b ekseni boyunca (X ya da Z) duvar; şaşırtmalı örgü, isteğe bağlı kapı ve mazgal.
func _wall(a: Vector3, b: Vector3, rows: int, merlons: bool, gate_w := 0.0) -> void:
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
			add_block(pos, size, r, "stone")
	if merlons:
		# Mazgal dişleri: dış kenarda, aralıklı
		var m := 1.8
		var count := int(length / (m * 2.0))
		var off := (length - (count * 2 - 1) * m) * 0.5
		for i in count:
			var cc := start + off + m * 0.5 + i * m * 2.0
			var size := Vector3(m, 1.6, 1.2) if along_x else Vector3(1.2, 1.6, m)
			var y := rows * ROW_H + 0.8
			var pos := Vector3(cc, y, fixed) if along_x else Vector3(fixed, y, cc)
			add_block(pos, size, rows, "stone")
