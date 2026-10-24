class_name BlockStructure
extends Building
## Bloklardan kurulan yapı (kale, ahşap kule, su kulesi, sera...). Building'in yapısal
## modelini kullanır: bloklar statik dondurulmuş başlar, birikimli hasar alır, desteği
## kalmayan kısımlar çöker.
##
## Malzemeler fiziksel olarak farklıdır:
##   stone   : ağır, orta dayanım, kopunca sert darbede ikiye bölünür
##   wood    : hafif, kolay kırılır, kopan kiriş kolayca ikiye kırılır
##   steel   : ağır profil, çok dayanıklı, bölünmez (eğilmeyi taklit etmez)
##   glass   : neredeyse dayanımsız; koptuğu an tuzla buz olur (parçacık + ses)
##   concrete: beton döşeme/kolon
##
## Çizim: sağlam bloklar (şekil, boyut, malzeme) gruplarına göre MultiMesh ile çizilir.

const MATERIALS := {
	"stone": {"kind": "stone", "density": 2300.0, "strength": 14000.0, "split": 9000.0},
	"wood": {"kind": "wood", "density": 650.0, "strength": 9000.0, "split": 2500.0},
	"steel": {"kind": "metal", "density": 1600.0, "strength": 600000.0, "split": 0.0},
	"glass": {"kind": "glass", "density": 2500.0, "strength": 800.0, "split": 0.0},
	"concrete": {"kind": "concrete", "density": 2200.0, "strength": 30000.0, "split": 12000.0},
	# Kesme taş örgü (kale): kopunca BrickPool ile tuğlalara ayrılır
	"masonry": {"kind": "stone", "density": 2300.0, "strength": 8000.0, "split": 0.0},
}
const GAP := 0.03

static var _mat_cache := {}

var _defs: Array[Dictionary] = []
var _groups := {}
var _instance_of := {}  # Destructible -> [MultiMesh, index, mesh, def]
## Taşıyıcı ayaklar: her ayak bir blok listesi. Sağlam ayak sayısı min_columns'un altına
## düşerse yapı devrilir (kalan tüm bloklar serbest kalır).
var columns := {}  # ayak no -> [Destructible]
var min_columns := 0
var _toppled := false
## Örgü bloklarını tuğlalara ayıran havuz (yalnız "masonry" malzemesi)
var brick_pool: BrickPool


static func material(mat_name: String) -> Material:
	if _mat_cache.has(mat_name):
		return _mat_cache[mat_name]
	if mat_name == "masonry":
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/masonry.gdshader")
		var t := "res://assets/textures/rock_boulder_dry_%s_1k.jpg"
		sm.set_shader_parameter("albedo_tex", load(t % "diff"))
		sm.set_shader_parameter("normal_tex", load(t % "nor_gl"))
		sm.set_shader_parameter("arm_tex", load(t % "arm"))
		_mat_cache[mat_name] = sm
		return sm
	var m: StandardMaterial3D
	match mat_name:
		"stone":
			m = _pbr("castle_wall_slates", 0.28, Color(0.92, 0.9, 0.86))
		"wood":
			m = _pbr("rough_wood", 0.7, Color(0.85, 0.78, 0.7))
		"steel":
			m = _pbr("rusty_metal_02", 0.5, Color(0.75, 0.75, 0.78))
			m.metallic = 0.7
		"concrete":
			m = _pbr("rough_concrete", 0.35, Color(0.8, 0.79, 0.76))
		"glass":
			m = StandardMaterial3D.new()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.75, 0.88, 0.92, 0.28)
			m.metallic = 0.2
			m.roughness = 0.05
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[mat_name] = m
	return m


## Tek MeshInstance olarak çizilen örgü bloğu: boyut malzemeye yazılır (boyut başına bir kopya)
static func _masonry_sized(size: Vector3) -> Material:
	var key := "masonry_%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if not _mat_cache.has(key):
		var m := material("masonry").duplicate() as ShaderMaterial
		m.set_shader_parameter("fixed_size", Color(size.x, size.y, size.z, 0.5))
		_mat_cache[key] = m
	return _mat_cache[key]


static func _pbr(tex: String, scale: float, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var t := "res://assets/textures/" + tex + "_%s_1k.jpg"
	m.albedo_texture = load(t % "diff")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(t % "nor_gl")
	m.roughness_texture = load(t % "arm")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.ao_enabled = true
	m.ao_texture = load(t % "arm")
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false  # parça dönerken doku yüzeye yapışık
	m.uv1_scale = Vector3.ONE * scale
	return m


## Blok ekle (yerel koordinat). opts: basis, shape ("box"|"cylinder"), density, strength
func add_block(pos: Vector3, size: Vector3, layer: int, mat: String, opts := {}) -> void:
	var d := {"pos": pos, "size": size, "layer": layer, "mat": mat,
		"basis": opts.get("basis", Basis.IDENTITY), "shape": opts.get("shape", "box"),
		"column": opts.get("column", -1)}
	d["density"] = opts.get("density", MATERIALS[mat]["density"])
	d["strength"] = opts.get("strength", MATERIALS[mat]["strength"])
	_defs.append(d)


func _key(d: Dictionary) -> String:
	var s: Vector3 = d["size"]
	return "%s_%s_%.2f_%.2f_%.2f" % [d["shape"], d["mat"], s.x, s.y, s.z]


func _make_mesh(d: Dictionary) -> Mesh:
	var s: Vector3 = d["size"]
	if d["shape"] == "cylinder":
		var cm := CylinderMesh.new()
		cm.top_radius = s.x * 0.5
		cm.bottom_radius = s.x * 0.5
		cm.height = s.y
		cm.radial_segments = 24
		cm.material = material(d["mat"])
		return cm
	var bm := BoxMesh.new()
	bm.size = s - Vector3.ONE * GAP
	bm.material = material(d["mat"])
	return bm


## Tüm blokları oluştur (bloklar eklendikten sonra bir kez çağrılır)
func finalize() -> void:
	for d in _defs:
		var k := _key(d)
		if not _groups.has(k):
			_groups[k] = {"mesh": _make_mesh(d), "count": 0, "next": 0}
		_groups[k]["count"] += 1
	for k in _groups:
		var g: Dictionary = _groups[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true  # örgü gölgelendiricisi için blok boyutu
		mm.mesh = g["mesh"]
		mm.instance_count = g["count"]
		g["mm"] = mm
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if (k as String).contains("glass"):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	var idx := 0
	for d in _defs:
		var size: Vector3 = d["size"]
		var b := Destructible.new()
		b.name = "b%d" % idx
		b.set_meta("def", idx)
		idx += 1
		b.transform = Transform3D(d["basis"], d["pos"])
		if d["shape"] == "cylinder":
			b.add_cylinder(size.x * 0.5, size.y)
		else:
			b.add_box(size - Vector3.ONE * 0.01)
		var vol := size.x * size.y * size.z * (0.785 if d["shape"] == "cylinder" else 1.0)
		var def: Dictionary = MATERIALS[d["mat"]]
		b.configure(def["kind"], vol * float(d["density"]), 0.5 if d["mat"] == "steel" else 0.8)
		b.layer = d["layer"]
		b.hp = vol * float(d["strength"])
		b.set_meta("hp0", b.hp)
		b.building = self
		b.make_intact()
		b.released.connect(_on_block_released)
		add_child(b)
		chunks.append(b)
		_by_name[b.name] = b
		var g: Dictionary = _groups[_key(d)]
		var mm: MultiMesh = g["mm"]
		var i: int = g["next"]
		g["next"] = i + 1
		mm.set_instance_transform(i, b.transform)
		mm.set_instance_custom_data(i, Color(size.x, size.y, size.z, 0.5))
		_instance_of[b] = [mm, i, g["mesh"], d]
		if int(d["column"]) >= 0:
			columns.get_or_add(int(d["column"]), []).append(b)
	_compute_neighbors()


## Tanım indeksindeki blok hâlâ sağlam mı (görev hedefleri için)
func _alive_def(i: int) -> bool:
	var b = _by_name.get("b%d" % i)
	return b != null and is_instance_valid(b) and b.intact


## Komşuluk: uzamsal ızgara ile (döndürülmüş) sınır kutusu kesişimi
func _compute_neighbors() -> void:
	var cell := 5.0
	var grid := {}
	var boxes := {}
	for i in chunks.size():
		var b := chunks[i]
		var d: Dictionary = _defs[i]
		var size: Vector3 = d["size"]
		var bb := (b.transform * AABB(-size * 0.5, size)).grow(0.15)
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


## Çatlak: örgü bloğunun hasar oranı gölgelendiriciye (özel veri w) yazılır; yüzden
## birkaç taş kırıntısı dökülür.
func _on_cracked(b: Destructible, point: Vector3) -> void:
	var info: Array = _instance_of.get(b, [])
	if info.is_empty():
		return
	var d: Dictionary = info[3]
	if d["mat"] != "masonry":
		return
	var hp0: float = b.get_meta("hp0", b.hp)
	var dmg := clampf((1.0 - b.hp / maxf(hp0, 1.0)) * 1.6, 0.0, 1.0)
	var size: Vector3 = d["size"]
	(info[0] as MultiMesh).set_instance_custom_data(info[1], Color(size.x, size.y, size.z, 0.5 + 0.49 * dmg))
	Fx.bricks(point.lerp(b.global_position, 0.3), (point - b.global_position).normalized(), 0.25)


func _on_block_released(b: Destructible) -> void:
	var info: Array = _instance_of.get(b, [])
	if info.is_empty():
		return
	var mm: MultiMesh = info[0]
	mm.set_instance_transform(info[1], Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	_instance_of.erase(b)
	var d: Dictionary = info[3]
	if d["mat"] == "glass":
		# Cam: tuzla buz
		var size: Vector3 = d["size"]
		Fx.glass_shards(b.global_position, size)
		Sfx.glass(b.global_position)
		forget(b)
		b.queue_free()
		return
	var mi := MeshInstance3D.new()
	mi.mesh = info[2]
	b.add_child(mi)
	if d["mat"] == "masonry" and brick_pool:
		var sz: Vector3 = d["size"]
		mi.material_override = _masonry_sized(sz)
		b.set_meta("block_size", sz)
		b.shatter_pool = brick_pool
		return
	var split: float = MATERIALS[d["mat"]]["split"]
	if split > 0.0 and d["shape"] == "box":
		b.make_splittable(d["size"], material(d["mat"]), split)


func _check_support() -> void:
	super()
	if min_columns <= 0 or _toppled:
		return
	var standing := 0
	for c in columns:
		var ok := true
		for b in columns[c]:
			if not is_instance_valid(b) or not b.intact:
				ok = false
				break
		if ok:
			standing += 1
	if standing < min_columns:
		_toppled = true
		# Devrilme: yapının ağırlık merkezi desteksiz kaldı; sağlam kalan her şey düşer.
		# Hafif ortak yanal itki: hepsi aynı yöne yıkılır.
		var lean := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		for b in chunks:
			if is_instance_valid(b) and b.intact:
				b.release(lean * b.mass * (0.3 + b.position.y * 0.08), b.global_position + Vector3.UP)
		Sfx.crash(global_position + Vector3.UP * 8.0, crash_sound)


## Blok yapıları zaten parçalı: "kırık bina" görünümüne geçiş yok
func _break_visual() -> void:
	if not broken:
		broken = true
		broke.emit(self)
