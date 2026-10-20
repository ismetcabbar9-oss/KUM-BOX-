class_name Building
extends Node3D
## Gerçek bina modeli + önceden kesilmiş DOLU parçalar (tools/fracture_buildings.gd).
##
## Yapısal model:
##  - Bina ayaktayken tüm parçalar statik dondurulmuştur: fizik maliyeti yok, kâğıt gibi
##    dağılmaz. Sağlamken tek mesh çizilir (1 draw call).
##  - strike(): çarpma noktası çevresindeki parçalara enerji dağıtılır; dayanımını aşan
##    parçalar kopar ve darbe yönünde fırlar. Harcanan enerji çarpana geri bildirilir
##    (sağlam bina ağır kayayı durdurur, çürük kulübe delinip geçilir).
##  - Destek kontrolü: zemine bağlı parçalardan komşuluk grafiğinde arama. Yatayda en fazla
##    MAX_SPAN parça "asılı" kalabilir; desteği kopan üst kısımlar kendi ağırlığıyla çöker.

signal broke(building: Building)

const DENSITY := {"concrete": 2000.0, "brick": 1800.0}
## Parça dayanımı: J / m³ (katı hacim). Tuğla betondan zayıf.
const STRENGTH := {"concrete": 55000.0, "brick": 38000.0}
const MAX_SPAN := 2
## Kırılmayan parçaya düşen enerjinin kalıcı hasara dönüşen oranı
const CRACK := 0.55

var chunks: Array[Destructible] = []
var broken := false
var kind := "concrete"
var max_span := float(MAX_SPAN)
## Asılı bir parçanın üstündeki her sıranın ek maliyeti (0 = sınırsız taşıma)
var hang_up := 0.0
var crash_sound := "crash"
var _by_name := {}
var _intact_mesh: MeshInstance3D
var _chunk_meshes: Array[MeshInstance3D] = []
var _support_dirty := false
var _total := 0


func setup(model_name: String, inner_kind: String) -> void:
	name = model_name
	kind = inner_kind
	var src: Node3D = load("res://assets/buildings/%s.scn" % model_name).instantiate()
	_intact_mesh = src.get_node("Intact")
	src.remove_child(_intact_mesh)
	_intact_mesh.owner = null
	add_child(_intact_mesh)
	var holder := src.get_node("Chunks")
	for mi: MeshInstance3D in holder.get_children():
		holder.remove_child(mi)
		mi.owner = null
		var d := Destructible.new()
		d.name = mi.name
		d.position = mi.position
		mi.position = Vector3.ZERO
		mi.visible = false
		d.add_child(mi)
		d.add_hull(mi.get_meta("hull"))
		var vol: float = mi.get_meta("volume")
		d.configure(kind, vol * DENSITY[kind])
		d.layer = mi.get_meta("layer")
		d.neighbors = mi.get_meta("neighbors")
		d.hp = vol * STRENGTH[kind]
		# İkinci kademe kırılma: önceden hesaplanmış yarılar ya da döşeme kutusu
		var halves := []
		for h in mi.get_children():
			if h is MeshInstance3D and h.name.begins_with("half"):
				halves.append({"mesh": h.mesh, "hull": h.get_meta("hull"), "volume": h.get_meta("volume"), "offset": h.position})
		for h in mi.get_children():
			mi.remove_child(h)
			h.free()
		if halves.size() == 2:
			d.make_splittable_halves(halves, STRENGTH[kind] * 0.35)
		elif mi.has_meta("box"):
			d.make_splittable(mi.get_meta("box"), (mi.mesh as BoxMesh).material, STRENGTH[kind] * 0.35)
		d.building = self
		d.make_intact()
		add_child(d)
		chunks.append(d)
		_chunk_meshes.append(mi)
		_by_name[d.name] = d
	src.free()


## Bir noktaya çarpma: çevredeki sağlam bina parçalarına enerji uygular.
## Döner: harcanan (kırılmaya giden) enerji.
static func strike(world: World3D, point: Vector3, energy: float, direction: Vector3, exclude: Object = null) -> float:
	var radius := clampf(0.8 + 0.45 * pow(energy / 10000.0, 1.0 / 3.0), 1.0, 8.0)
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, point)
	q.collision_mask = 2
	if exclude:
		q.exclude = [(exclude as CollisionObject3D).get_rid()]
	var by_building := {}
	for hit in world.direct_space_state.intersect_shape(q, 64):
		var d := hit["collider"] as Destructible
		if d and d.intact and d.building:
			by_building.get_or_add(d.building, []).append(d)
	var used := 0.0
	for b: Building in by_building:
		used += b._apply_damage(point, energy, direction, radius, by_building[b])
	return used


func _apply_damage(point: Vector3, energy: float, direction: Vector3, radius: float, hits: Array) -> float:
	hits.sort_custom(func(a: Destructible, b: Destructible) -> bool:
		return a.global_position.distance_squared_to(point) < b.global_position.distance_squared_to(point))
	var used := 0.0
	var spent := 0.0  # enerji dağıtımı için (çatlak + kırılma)
	var cracked := 0
	var dir := direction.normalized() if direction.length_squared() > 0.001 else Vector3.DOWN
	for d: Destructible in hits:
		if not d.intact:
			continue
		var dist := d.global_position.distance_to(point)
		var share := (energy - spent) * clampf(1.15 - dist / (radius * 1.6), 0.15, 1.0)
		if share < d.hp:
			# Birikimli hasar: kırılmayan parça çatlar (dayanımı azalır), enerjinin bir
			# kısmını emer. Aynı yere tekrar tekrar vurmak sonunda deler.
			var absorbed := share * CRACK
			d.hp -= absorbed
			spent += absorbed
			used += absorbed * 0.3  # çatlatmak mermiyi az yavaşlatır
			cracked += 1
			continue
		_break_visual()
		used += d.hp
		spent += d.hp
		# Artan enerji parçaya hız olarak geçer (en fazla ~18 m/s)
		var extra := maxf(share - d.hp, 0.0)
		var kick := minf(sqrt(2.0 * extra / d.mass), 18.0) * 0.6
		var spread := (d.global_position - point).normalized() * 0.35
		d.release((dir + spread).normalized() * d.mass * kick, point)
		Fx.dust(d.global_position, 1.4)
		Fx.rubble(d.global_position, dir, 1.0)
		if spent >= energy * 0.95:
			break
	if OS.get_cmdline_user_args().has("--debug-strike"):
		print("  darbe: E=%.2f MJ r=%.1f isabet=%d kopan=%d çatlak=%d kullanılan=%.2f MJ" % [energy / 1e6, radius, hits.size(), chunks.filter(func(c: Destructible) -> bool: return not c.intact).size(), cracked, used / 1e6])
	if cracked > 0:
		Fx.dust(point, 1.0)
	if used > 0.0:
		Sfx.debris(point, 10.0)
		if used > 400000.0:
			Sfx.crash(point, crash_sound)
		_mark_support_dirty()
	return used


func _break_visual() -> void:
	if broken:
		return
	broken = true
	_intact_mesh.visible = false
	for mi in _chunk_meshes:
		mi.visible = true
	Sfx.glass(global_position + Vector3.UP * 4.0)
	broke.emit(self)


func _mark_support_dirty() -> void:
	if not _support_dirty:
		_support_dirty = true
		_check_support.call_deferred()


## 0-1 BFS: zeminden yukarı çıkmak bedava, yatay/aşağı her adım 1. MAX_SPAN'dan
## uzaktaki ya da hiç bağlantısı kalmayan sağlam parçalar serbest kalır.
func _check_support() -> void:
	_support_dirty = false
	# Etiket düzeltmeli arama (küçük grafik): maliyet = "asılılık".
	#  - zemindeki parça: 0
	#  - yana ya da aşağı adım: +1
	#  - yukarı adım: desteği tam olan (0) parçadan bedava, asılı parçadan +hang_up
	#    (asılı bir bloğun üstüne binen her sıra yükü artırır: büyük oyuğun üstü çöker)
	var cost := {}
	var queue: Array[Destructible] = []
	for d in chunks:
		if d.intact and d.layer == 0:
			cost[d] = 0.0
			queue.append(d)
	var head := 0
	while head < queue.size():
		var c: Destructible = queue[head]
		head += 1
		var cc: float = cost[c]
		for nn in c.neighbors:
			var n: Destructible = _by_name.get(nn)
			if n == null or not n.intact:
				continue
			var step := 1.0
			if n.layer > c.layer:
				step = 0.0 if cc == 0.0 else hang_up
			var nc := cc + step
			if nc > max_span:
				continue
			if not cost.has(n) or nc < cost[n] - 0.001:
				cost[n] = nc
				queue.append(n)
	var fell := 0
	for d in chunks:
		if d.intact and not cost.has(d):
			# Hafif rastgele gecikmeli düşüş: çöküş tek blok gibi değil, parça parça
			d.release(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * d.mass * 0.4, d.global_position + Vector3.UP)
			fell += 1
	if fell > 6:
		Sfx.crash(global_position + Vector3.UP * 6.0, crash_sound)


## Bölünen/silinen parçayı listelerden çıkar
func forget(d: Destructible) -> void:
	chunks.erase(d)
	_by_name.erase(d.name)


func intact_ratio() -> float:
	if _total == 0:
		_total = chunks.size()
	var n := 0
	for d in chunks:
		if d.intact:
			n += 1
	return float(n) / maxf(_total, 1)
