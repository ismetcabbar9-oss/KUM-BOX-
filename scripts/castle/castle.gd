class_name Castle
extends Node3D
## İç içe (konsantrik) kale:
##   - Dış halka: 4 köşe kulesi, 2 yan kule, iki kuleli kapı yapısı + asma köprü, surlar
##   - Hendek (sığ su: içinden geçen mermi yavaşlar)
##   - Dış avlu: kışla, demirhane (bacalı), ahır (ahşap sundurma), depo, kuyu
##   - İç halka: daha yüksek surlar, 4 kule, kapı
##   - Ana kule (donjon): 60 m, iç bölme duvarlı; tepesinde komutan ve sancak
## Her bölüm ayrı bir Fortress (destek grafiği küçük kalır); hepsi tek BrickPool kullanır.
## Yerel koordinat: ön yüz -Z (fırlatıcılara bakar).

const OX := 85.0  # dış halka yarı genişlik
const OZ := 72.0  # dış halka yarı derinlik
const IX := 44.0
const IZ := 36.0
const IC := Vector3(0, 0, 14)  # iç halka merkezi
const KEEP := Vector3(0, 0, 20)
const MOAT_IN := 4.0  # hendeğin dış halkadan uzaklığı
const MOAT_W := 9.0

var parts: Array[Fortress] = []
var pool: BrickPool
## [yerel konum, bakış açısı, rol]
var soldier_spots: Array = []
var bridge: Drawbridge
var flag: Flag
var water_zones: Array[AABB] = []


func build() -> void:
	name = "Kale"
	pool = BrickPool.new()
	pool.name = "Tuglalar"
	pool.setup(BlockStructure.material("masonry"), Vector3(1.5, 1.0, 1.0), "stone", 2300.0)
	add_child(pool)
	_outer()
	_inner()
	_keep()
	_bailey()
	for p in parts:
		p.finalize()
		add_child(p)
	_moat()
	_bridge()
	_flag()


func _part(n: String) -> Fortress:
	var f := Fortress.new()
	f.begin(n, pool)
	parts.append(f)
	return f


## Kule tepesine asker yerleştir (ön kenara yakın, -Z'ye bakar)
func _tower_guards(c: Vector3, w: float, top: float, count: int) -> void:
	for k in count:
		var o := (k - (count - 1) * 0.5) * 3.2
		soldier_spots.append([Vector3(c.x + o, top, c.z - w * 0.5 + 3.0), PI, "guard"])


## Sur yürüyüş yolu boyunca asker (X ekseninde sur)
func _wall_guards(z: float, x0: float, x1: float, y: float, count: int, inward: float) -> void:
	for k in count:
		var x := lerpf(x0, x1, (k + 0.5) / count)
		soldier_spots.append([Vector3(x, y, z + inward * 0.7), PI, "guard"])


func _outer() -> void:
	var f := _part("DisHalka")
	var corner_w := 16.0
	var corner_rows := 8  # 24 m
	var mid_w := 14.0
	var gate_w := 12.0
	var rows := 5  # 15 m sur
	var gx := 11.0  # kapı kulelerinin merkezi
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * OX, 0, sz * OZ)
			var top := f.tower(c, corner_w, corner_rows)
			_tower_guards(c, corner_w, top, 2)
		var mc := Vector3(sx * OX, 0, 0)
		var mt := f.tower(mc, mid_w, 7)
		_tower_guards(mc, mid_w, mt, 2)
		var gc := Vector3(sx * gx, 0, -OZ)
		var gt := f.tower(gc, gate_w, 9)
		_tower_guards(gc, gate_w, gt, 2)
	var ci := OX - corner_w * 0.5
	var gi := gx + gate_w * 0.5
	# Ön sur: iki parça + kapı üstü (kapı kulelerinin arasında, 8 sıra, alt 3 sıra kapı)
	for sx in [-1.0, 1.0]:
		f.wall(Vector3(sx * ci, 0, -OZ), Vector3(sx * gi, 0, -OZ), rows, -1.0)
		_wall_guards(-OZ, sx * gi, sx * ci, rows * f.row_h, 3, 1.0)
	f.wall(Vector3(-(gx - gate_w * 0.5), 0, -OZ), Vector3(gx - gate_w * 0.5, 0, -OZ), 8, -1.0, 10.0, 3)
	# Arka sur
	f.wall(Vector3(-ci, 0, OZ), Vector3(ci, 0, OZ), rows, 1.0)
	# Yan surlar (orta kuleyle ikiye bölünür)
	for sx in [-1.0, 1.0]:
		f.wall(Vector3(sx * OX, 0, -OZ + corner_w * 0.5), Vector3(sx * OX, 0, -mid_w * 0.5), rows, sx)
		f.wall(Vector3(sx * OX, 0, mid_w * 0.5), Vector3(sx * OX, 0, OZ - corner_w * 0.5), rows, sx)


func _inner() -> void:
	var f := _part("IcHalka")
	var w := 16.0
	var trows := 12  # 36 m
	var rows := 8  # 24 m sur
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := IC + Vector3(sx * IX, 0, sz * IZ)
			var top := f.tower(c, w, trows)
			if sz < 0.0:
				_tower_guards(c, w, top, 3)
	var ci := IX - w * 0.5
	f.wall(IC + Vector3(-ci, 0, -IZ), IC + Vector3(ci, 0, -IZ), rows, -1.0, 8.0, 3)
	_wall_guards(IC.z - IZ, -ci + 4.0, -6.0, rows * f.row_h, 2, 1.0)
	_wall_guards(IC.z - IZ, 6.0, ci - 4.0, rows * f.row_h, 2, 1.0)
	f.wall(IC + Vector3(-ci, 0, IZ), IC + Vector3(ci, 0, IZ), rows, 1.0)
	for sx in [-1.0, 1.0]:
		f.wall(IC + Vector3(sx * IX, 0, -IZ + w * 0.5), IC + Vector3(sx * IX, 0, IZ - w * 0.5), rows, sx)


func _keep() -> void:
	var f := _part("AnaKule")
	var w := 24.0
	var top := f.tower(KEEP, w, 20, true)  # 60 m
	# Komutan + muhafızlar
	soldier_spots.append([KEEP + Vector3(0, top, -w * 0.5 + 3.0), PI, "commander"])
	for o in [-6.0, -3.0, 3.0, 6.0]:
		soldier_spots.append([KEEP + Vector3(o, top, -w * 0.5 + 3.5), PI, "guard"])


## Dış avlu yapıları + iç avluda salon
func _bailey() -> void:
	var b := _part("Avlu")
	b.thick = 1.0
	b.block = 3.0
	b.house(Vector3(-56, 0, -42), Vector3(22, 0, 10), 2, 1)  # kışla
	b.house(Vector3(58, 0, -44), Vector3(12, 0, 9), 2, 2)  # demirhane
	# Demirhane bacası: binanın dış yüzüne bitişik, yerden yükselir
	b.wall(Vector3(64.5, 0, -45.0), Vector3(64.5, 0, -43.0), 4, 0.0)
	b.house(Vector3(-66, 0, 30), Vector3(10, 0, 18), 2, 3)  # depo
	b.house(IC + Vector3(26, 0, 4), Vector3(12, 0, 16), 3, 2)  # salon (iç avlu)
	# Kuyu: alçak taş bilezik
	for k in 4:
		var a := k * PI * 0.5
		b.add_block(Vector3(-22, 0.5, -48) + Vector3(cos(a), 0, sin(a)) * 1.3, Vector3(1.5, 1.0, 0.6), 0, "masonry", {"basis": Basis(Vector3.UP, -a + PI * 0.5)})
	var st := _part("Ahir")
	st.shed(Vector3(68, 0, 32), Vector3(10, 0, 20), 4.0)
	# Avlu askerleri
	for p: Vector3 in [Vector3(-8, 0, -60), Vector3(8, 0, -60), Vector3(-40, 0, -30), Vector3(40, 0, -32),
			Vector3(-20, 0, -42), Vector3(30, 0, -55), Vector3(-6, 0, -16), Vector3(6, 0, -16),
			Vector3(-24, 0, 10), Vector3(22, 0, -6)]:
		soldier_spots.append([p, PI + randf_range(-0.5, 0.5), "guard"])


## Hendek: dış halkanın çevresinde sığ su (asma köprü önden geçer)
func _moat() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	var outer_x := OX + 8.0 + MOAT_IN
	var outer_z := OZ + 8.0 + MOAT_IN
	var rects := [
		Rect2(-outer_x - MOAT_W, -outer_z - MOAT_W, (outer_x + MOAT_W) * 2.0, MOAT_W),  # ön
		Rect2(-outer_x - MOAT_W, outer_z, (outer_x + MOAT_W) * 2.0, MOAT_W),  # arka
		Rect2(-outer_x - MOAT_W, -outer_z, MOAT_W, outer_z * 2.0),  # sol
		Rect2(outer_x, -outer_z, MOAT_W, outer_z * 2.0),  # sağ
	]
	for r: Rect2 in rects:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = r.size
		pm.subdivide_width = int(r.size.x / 6.0)
		pm.subdivide_depth = int(r.size.y / 6.0)
		mi.mesh = pm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(r.get_center().x, 0.06, r.get_center().y)
		add_child(mi)
		water_zones.append(AABB(Vector3(r.position.x, -1.0, r.position.y), Vector3(r.size.x, 2.5, r.size.y)))


func _bridge() -> void:
	bridge = Drawbridge.new()
	# Kapı kulelerinin ön yüzü hizasında menteşe; inince hendeğin üstünü örter
	var hinge_z := -OZ - 6.0
	bridge.setup(Vector3(9.4, 0.6, 2.0 + MOAT_IN + MOAT_W + 1.0), parts[0])
	bridge.position = Vector3(0, 0, hinge_z)
	add_child(bridge)


func _flag() -> void:
	flag = Flag.new()
	var keep: Fortress = parts[2]
	var top := 20 * keep.row_h + 1.0
	flag.position = KEEP + Vector3(0, top, 0)
	add_child(flag)
	flag.attach(keep)


## Tüm bölümlerin sağlam blok oranı (başlangıç toplamına göre)
func intact_ratio() -> float:
	var total := 0
	var ok := 0.0
	for p in parts:
		var r := p.intact_ratio()
		var n: int = p._total
		total += n
		ok += r * n
	return ok / maxf(total, 1)


## Hendek bölgeleri (dünya koordinatında)
func world_water() -> Array[AABB]:
	var out: Array[AABB] = []
	for z in water_zones:
		out.append(global_transform * z)
	return out
