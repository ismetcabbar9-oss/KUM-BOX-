class_name Fortress
extends Building
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
const STONE_DENSITY := 2300.0
## J/m³: 4×2.5×3 m blok ≈ 0.4 MJ (birikimli hasarla delinir)
const STONE_STRENGTH := 14000.0
const GAP := 0.04  # harç aralığı (görsel)

var _material: StandardMaterial3D
var _defs: Array[Dictionary] = []  # {pos, size, layer}
var _groups := {}  # boyut anahtarı -> {mm: MultiMesh, mesh: BoxMesh, count}
var _instance_of := {}  # Destructible -> [MultiMesh, index]


func setup_castle() -> void:
	name = "Kale"
	kind = "concrete"
	# Taş örgü: oyuğun üstünde 1-2 sıra kemer gibi tutunur, daha yukarısı çöker
	max_span = 1.6
	hang_up = 0.6
	crash_sound = "stone_crash"
	_material = StandardMaterial3D.new()
	var t := "res://assets/textures/castle_wall_slates_%s_1k.jpg"
	_material.albedo_texture = load(t % "diff")
	_material.normal_enabled = true
	_material.normal_texture = load(t % "nor_gl")
	_material.roughness_texture = load(t % "arm")
	_material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	_material.ao_enabled = true
	_material.ao_texture = load(t % "arm")
	_material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	_material.uv1_triplanar = true
	_material.uv1_world_triplanar = false
	_material.uv1_scale = Vector3.ONE * 0.28
	_material.albedo_color = Color(0.92, 0.9, 0.86)

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
	_build_bodies()


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
			_defs.append({"pos": pos, "size": size, "layer": r})
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
			_defs.append({"pos": pos, "size": size, "layer": rows})


func _key(size: Vector3) -> String:
	return "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]


func _build_bodies() -> void:
	# Boyut gruplarına göre MultiMesh
	for d in _defs:
		var k := _key(d["size"])
		if not _groups.has(k):
			var bm := BoxMesh.new()
			bm.size = (d["size"] as Vector3) - Vector3.ONE * GAP
			bm.material = _material
			_groups[k] = {"mesh": bm, "count": 0}
		_groups[k]["count"] += 1
	for k in _groups:
		var g: Dictionary = _groups[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g["mesh"]
		mm.instance_count = g["count"]
		g["mm"] = mm
		g["next"] = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
	# Gövdeler
	var idx := 0
	for d in _defs:
		var size: Vector3 = d["size"]
		var b := Destructible.new()
		b.name = "b%d" % idx
		idx += 1
		b.position = d["pos"]
		b.add_box(size - Vector3.ONE * 0.01)
		var vol := size.x * size.y * size.z
		b.configure("stone", vol * STONE_DENSITY)
		b.layer = d["layer"]
		b.hp = vol * STONE_STRENGTH
		b.building = self
		b.make_intact()
		b.released.connect(_on_block_released)
		add_child(b)
		chunks.append(b)
		_by_name[b.name] = b
		var g: Dictionary = _groups[_key(size)]
		var mm: MultiMesh = g["mm"]
		var i: int = g["next"]
		g["next"] = i + 1
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, d["pos"]))
		_instance_of[b] = [mm, i, g["mesh"]]
	_compute_neighbors()


## Komşuluk: uzamsal ızgara ile sınır kutusu kesişimi (O(n) yakınında)
func _compute_neighbors() -> void:
	var cell := 5.0
	var grid := {}
	var boxes := {}
	for b in chunks:
		var bb := AABB(b.position - (b.get_child(0) as CollisionShape3D).shape.size * 0.5, (b.get_child(0) as CollisionShape3D).shape.size).grow(0.15)
		boxes[b] = bb
		var c0 := Vector3i((bb.position / cell).floor())
		var c1 := Vector3i((bb.end / cell).floor())
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				for z in range(c0.z, c1.z + 1):
					grid.get_or_add(Vector3i(x, y, z), []).append(b)
	for b in chunks:
		var found := {}
		var bb: AABB = boxes[b]
		var c0 := Vector3i((bb.position / cell).floor())
		var c1 := Vector3i((bb.end / cell).floor())
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				for z in range(c0.z, c1.z + 1):
					for o in grid.get(Vector3i(x, y, z), []):
						if o != b and not found.has(o) and bb.intersects(boxes[o]):
							found[o] = true
		var nbs := PackedStringArray()
		for o in found:
			nbs.append(o.name)
		b.neighbors = nbs


func _on_block_released(b: Destructible) -> void:
	var info: Array = _instance_of.get(b, [])
	if info.is_empty():
		return
	var mm: MultiMesh = info[0]
	mm.set_instance_transform(info[1], Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	var mi := MeshInstance3D.new()
	mi.mesh = info[2]
	b.add_child(mi)
	_instance_of.erase(b)
	if OS.get_cmdline_user_args().has("--debug-strike"):
		var p0 := b.global_position
		for f in 20:
			await get_tree().physics_frame
		print("   blok %s freeze=%s uyku=%s v=%s yer değişimi=%.2f kütle=%.0f" % [b.name, b.freeze, b.sleeping, b.linear_velocity.snapped(Vector3.ONE * 0.01), b.global_position.distance_to(p0), b.mass])


## Kale tek parça bir yapı: "kırık bina" görünümüne geçiş yok (bloklar zaten ayrı)
func _break_visual() -> void:
	if not broken:
		broken = true
		broke.emit(self)
