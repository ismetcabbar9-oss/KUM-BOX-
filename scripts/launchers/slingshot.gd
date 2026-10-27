class_name Slingshot
extends Launcher
## Dev sapan: mermi parmakla geri çekilir; bırakınca iki lastik Hooke yasasıyla
## (F = k·x) mermiyi dinlenme noktasına doğru hızlandırır, mermi noktayı geçince lastik
## ayrılır. Hız fizikten gelir: ağır mermi daha yavaş gider.
##
## Kontrol: çek-bırak. Parmak ekrana değince keseden tutulur; aşağı/yana sürükleyerek
## geri çekilir (ters yöne nişan). Parmak kalkınca, çekme mesafesine göre kendiliğinden atar.
## Çok az çekilip bırakılırsa atış iptal olur, kese yerine döner.

const REST := Vector3(0, 5.0, 0)
const POST_X := 3.3
const K := 45000.0  # N/m (iki lastik toplamı; mermi ölçeğiyle büyür)
const MAX_PULL := 9.0
const MIN_PULL := 1.6
const REST_PULL := Vector3(0, -0.2, -0.8)

var pull := REST_PULL
var pulling := false
var _spring_body: Projectile
var _spring_time := 0.0
var _bands: Array[MeshInstance3D] = []
var _pouch: MeshInstance3D
var _k_scale := 1.0


func _init() -> void:
	super()
	title = "DEV SAPAN"
	id = "slingshot"
	base_radius = 0.6
	view_distance = 18.0


func _ready() -> void:
	var steel := WorldBuilder.pbr("rusty_metal_02", 0.6, Color(0.8, 0.8, 0.8), false)
	var wood := WorldBuilder.pbr("rough_wood", 0.5, Color(0.9, 0.85, 0.8), false)
	# Y çatal: iki eğik direk + taban
	for sx in [-1.0, 1.0]:
		var a := Vector3(sx * 1.2, 0.0, 0.0)
		var b := Vector3(sx * POST_X, REST.y + 0.6, 0.0)
		beam(self, Vector3(0.5, 0.5, a.distance_to(b)), Transform3D(Basis.looking_at((b - a).normalized(), Vector3.FORWARD), (a + b) * 0.5), steel)
	beam(self, Vector3(3.0, 0.6, 0.6), Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)), steel)
	beam(self, Vector3(4.0, 0.4, 3.0), Transform3D(Basis.IDENTITY, Vector3(0, 0.2, -1.0)), wood)
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.12, 0.1, 0.09)
	rubber.roughness = 0.7
	for i in 2:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09
		cm.bottom_radius = 0.09
		cm.height = 1.0
		cm.radial_segments = 8
		mi.mesh = cm
		mi.material_override = rubber
		mi.top_level = true
		add_child(mi)
		_bands.append(mi)
	_pouch = MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.3, 0.9, 0.25)
	_pouch.mesh = pm
	_pouch.material_override = rubber
	_pouch.top_level = true
	add_child(_pouch)
	view_target.position = REST + Vector3(0, -1.0, -3.0)


func _post_top(side: float) -> Vector3:
	return to_global(Vector3(side * POST_X, REST.y + 0.6, 0.0))


func load_projectile(p: Projectile) -> void:
	loaded = p
	pull = REST_PULL
	pulling = false
	# Lastik sertliği mermi ölçeğiyle büyür (büyük mermi için büyük sapan hissi)
	_k_scale = pow(p.radius / base_radius, 3.0)
	_place()


func _place() -> void:
	loaded.global_transform = Transform3D(global_transform.basis, to_global(REST + pull))
	loaded.reset_physics_interpolation()
	_update_preview()


func _launch_speed() -> Vector3:
	# Enerji korunumu: ½kx² = ½mv²  ->  v = x·√(k/m)
	var x := pull.length()
	var v := x * sqrt(K * _k_scale * power / loaded.mass) * 0.92
	return global_transform.basis * (-pull.normalized() * v)


func _update_preview() -> void:
	if is_ready() and pulling and pull.length() >= MIN_PULL:
		_show_arc(to_global(REST), _launch_speed())
	else:
		_hide_arc()


func uses_button() -> bool:
	return false


func press() -> void:
	if is_ready():
		pulling = true


func drag(relative: Vector2, vs: Vector2) -> void:
	if not is_ready() or not pulling:
		return
	# Ekran boyutundan bağımsız: ekran yüksekliğinin ~%45'i = tam gerilim
	var k := MAX_PULL / (minf(vs.x, vs.y) * 0.45)
	pull.x = clampf(pull.x - relative.x * k * 0.55, -4.5, 4.5)
	pull.z = clampf(pull.z - relative.y * k, -MAX_PULL, -0.8)
	pull.y = clampf(pull.y - relative.y * k * 0.4, -3.5, 1.0)
	if pull.length() > MAX_PULL:
		pull = pull.normalized() * MAX_PULL
	_place()


func release(_swipe: float) -> bool:
	if not is_ready() or not pulling:
		return false
	pulling = false
	if pull.length() < MIN_PULL:
		pull = REST_PULL
		_place()
		return false
	fire()
	return true


func fire(_power := -1.0) -> void:
	if not is_ready() or pull.length() < MIN_PULL:
		return
	var p := loaded
	pulling = false
	_hide_arc()
	p.launch(Vector3.ZERO)
	_spring_body = p
	_spring_time = 0.0
	Sfx.play("sling", to_global(REST), 2.0)
	fired.emit(p)


func _physics_process(delta: float) -> void:
	if _spring_body == null or not is_instance_valid(_spring_body):
		_spring_body = null
		return
	_spring_time += delta
	var rest := to_global(REST)
	var x := rest - _spring_body.global_position
	var fwd := -(global_transform.basis * pull.normalized())
	# Mermi dinlenme noktasını geçti -> lastik ayrılır
	if x.dot(fwd) <= 0.0 or _spring_time > 1.0:
		_spring_body = null
		return
	_spring_body.apply_central_force(x * K * _k_scale * power)


func _process(_delta: float) -> void:
	var pouch_pos := to_global(REST)
	if is_ready():
		pouch_pos = loaded.global_position - global_transform.basis * (-pull.normalized()) * loaded.radius
	elif _spring_body:
		pouch_pos = _spring_body.global_position
	_pouch.global_transform = Transform3D(global_transform.basis, pouch_pos)
	for i in 2:
		var a := _post_top(-1.0 if i == 0 else 1.0)
		var d := pouch_pos - a
		var band := _bands[i]
		band.global_transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.FORWARD) * Basis(Vector3.RIGHT, PI * 0.5), a + d * 0.5)
		band.scale = Vector3(1, d.length(), 1)


func info() -> String:
	var pct := roundi(clampf((pull.length() - REST_PULL.length()) / (MAX_PULL - REST_PULL.length()), 0.0, 1.0) * 100.0)
	return "Gerilim %d%%" % pct if pulling else "Parmağını koy ve geri çek"


func hint() -> String:
	return "Geri çek (aşağı), yönü yana ayarla, bırak: atar"
