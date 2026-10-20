class_name RampLauncher
extends Launcher
## Beton rampa istasyonu. Rampa türü değiştirilebilir (AYAR butonu):
##   KLASİK       : 55 m, dikten yataya yumuşak iniş
##   KAYAK ATLAMA : 62 m dik iniş, sonunda 10° yukarı kalkış dudağı: kaya havalanır
##   S-KIVRIM     : yatışlı S virajları
##   SPİRAL       : 72 m'den 1.25 tur sarmal iniş, ardından düz çıkış
##   TEPELİ       : dalgalı iniş: tepelerde kaya havalanır
## Kaya rampanın başındaki düz platformda bekler; yana sürüklenerek hizalanır.

const TYPES := ["KLASİK", "KAYAK ATLAMA", "S-KIVRIM", "SPİRAL", "TEPELİ"]
const WIDTH := 14.0
const PLATFORM := 14.0

static var type_index := 0

var aim := 0.0
var _body: StaticBody3D
var _pts := PackedVector3Array()
var _start_i := 0


func _init() -> void:
	super()
	title = "RAMPA"
	base_radius = 2.0
	view_distance = 16.0


func _ready() -> void:
	_build()


func rolling() -> bool:
	return true


func option_label() -> String:
	return "RAMPA: " + TYPES[type_index]


func cycle_option() -> void:
	type_index = (type_index + 1) % TYPES.size()
	_build()


func _build() -> void:
	if _body:
		_body.queue_free()
	var res := _path(type_index)
	_pts = res[0]
	var wall: float = res[2]
	_body = WorldBuilder.build_path_ramp(self, _pts, res[1], WIDTH, wall)
	# Kaya platformun ortasında bekler
	var acc := 0.0
	_start_i = 0
	for i in range(1, _pts.size()):
		acc += _pts[i].distance_to(_pts[i - 1])
		if acc >= PLATFORM * 0.5:
			_start_i = i
			break


## Hermite eğrisi: (x, y, eğim) anahtar noktaları arasında yumuşak profil
static func _hermite(keys: Array, x: float) -> float:
	for k in keys.size() - 1:
		var a: Array = keys[k]
		var b: Array = keys[k + 1]
		if x <= b[0] or k == keys.size() - 2:
			var h: float = b[0] - a[0]
			var t := clampf((x - a[0]) / h, 0.0, 1.0)
			var t2 := t * t
			var t3 := t2 * t
			return (2 * t3 - 3 * t2 + 1) * a[1] + (t3 - 2 * t2 + t) * h * a[2] + (-2 * t3 + 3 * t2) * b[1] + (t3 - t2) * h * b[2]
	return keys[-1][1]


## Döner: [noktalar, yatış açıları, duvar yüksekliği]
func _path(kind: int) -> Array:
	var pts := PackedVector3Array()
	var banks := PackedFloat32Array()
	var lift := 0.03
	var wall := 2.2
	var max_bank := 0.42
	match kind:
		0:  # KLASİK
			var z := 0.0
			while z <= 189.0:
				pts.append(Vector3(0, WorldBuilder.ramp_height(z, 55.0, PLATFORM, 150.0) + lift, z))
				z += 1.7
		1:  # KAYAK ATLAMA
			var keys := [[0.0, 62.0, 0.0], [PLATFORM, 62.0, 0.0], [70.0, 20.0, -0.8], [112.0, 6.5, 0.0], [134.0, 10.0, 0.18]]
			var z := 0.0
			while z <= 134.0:
				pts.append(Vector3(0, _hermite(keys, z), z))
				z += 1.5
		2:  # S-KIVRIM
			for i in 9:
				pts.append(Vector3(0, 55.0 + lift, i * PLATFORM / 8.0 - PLATFORM))
			var steps := 130
			for i in range(1, steps + 1):
				var t := float(i) / steps
				var x := 24.0 * sin(TAU * t) * (1.0 - t)
				pts.append(Vector3(x, 55.0 * pow(1.0 - t, 2.0) + lift, t * 189.0))
			wall = 3.2
		3:  # SPİRAL: merkez (R, ·, cz); θ artarak -π/2'de (0, ·, cz) noktasına +Z yönünde varır
			var r := 24.0
			var cz := 70.0
			var turns := 1.25
			var th0 := -PI * 0.5 - turns * TAU
			var start := Vector3(r + r * sin(th0), 72.0, cz + r * cos(th0))
			var t0 := Vector3(r * cos(th0), 0, -r * sin(th0)).normalized()
			for i in 9:
				pts.append(start - t0 * (PLATFORM * (8 - i) / 8.0) + Vector3.UP * lift)
			var steps := 160
			for i in range(1, steps + 1):
				var u := float(i) / steps
				var th := lerpf(th0, -PI * 0.5, u)
				pts.append(Vector3(r + r * sin(th), lerpf(72.0, 20.0, u) + lift, cz + r * cos(th)))
			var keys := [[cz, 20.0, -52.0 / (r * turns * TAU)], [189.0, 0.0, 0.0]]
			var z := cz + 1.6
			while z <= 189.0:
				pts.append(Vector3(0, _hermite(keys, z) + lift, z))
				z += 1.6
			wall = 5.0
			max_bank = 0.68
		4:  # TEPELİ
			var z := 0.0
			while z <= 189.0:
				var base := WorldBuilder.ramp_height(z, 55.0, PLATFORM, 150.0)
				var t := clampf((z - PLATFORM) / 175.0, 0.0, 1.0)
				var bump := 4.5 * sin(t * PI * 5.0) * sin(t * PI) if z > PLATFORM else 0.0
				pts.append(Vector3(0, base + bump + lift, z))
				z += 1.4
	# Yatış: yatay eğriliğe göre içe eğim (sınırlı)
	for i in pts.size():
		var a := pts[maxi(i - 2, 0)]
		var b := pts[i]
		var c := pts[mini(i + 2, pts.size() - 1)]
		var d1 := Vector2(b.x - a.x, b.z - a.z)
		var d2 := Vector2(c.x - b.x, c.z - b.z)
		var turn := d1.angle_to(d2) if d1.length() > 0.01 and d2.length() > 0.01 else 0.0
		var dist := maxf((d1.length() + d2.length()) * 0.5, 0.01)
		var curvature := turn / dist
		banks.append(clampf(-curvature * 18.0, -max_bank, max_bank))
	# Yatışı yumuşat
	var smooth := PackedFloat32Array(banks)
	for i in banks.size():
		var sum := 0.0
		var cnt := 0
		for k in range(maxi(i - 4, 0), mini(i + 5, banks.size())):
			sum += banks[k]
			cnt += 1
		smooth[i] = sum / cnt
	return [pts, smooth, wall]


func _frame_at(i: int) -> Array:
	var t := (_pts[mini(i + 1, _pts.size() - 1)] - _pts[maxi(i - 1, 0)]).normalized()
	var s := Vector3.UP.cross(t).normalized()
	return [t, s]


func load_projectile(p: Projectile) -> void:
	loaded = p
	aim = clampf(aim, -_limit(), _limit())
	_place()


func _place() -> void:
	var f := _frame_at(_start_i)
	var t: Vector3 = f[0]
	var s: Vector3 = f[1]
	var pos := _pts[_start_i] + s * aim + Vector3.UP * loaded.radius * 1.05
	loaded.global_transform = Transform3D(Basis.looking_at(t, Vector3.UP).rotated(Vector3.UP, PI), to_global(pos))
	loaded.reset_physics_interpolation()
	view_target.position = _pts[_start_i] + s * aim + Vector3.UP * loaded.radius


func heading() -> float:
	var t: Vector3 = _frame_at(_start_i)[0]
	return atan2(t.x, t.z)


func _limit() -> float:
	var r := loaded.radius if loaded else base_radius
	return WIDTH * 0.5 - r - 0.2


func drag(relative: Vector2, _vs: Vector2) -> void:
	if not is_ready():
		return
	aim = clampf(aim - relative.x * 0.02, -_limit(), _limit())
	_place()


func release(swipe_up_speed: float) -> bool:
	if swipe_up_speed > 0.0 and is_ready():
		fire(clampf(4.0 + swipe_up_speed * 6.0, 4.0, 20.0))
		return true
	return false


func fire(power := -1.0) -> void:
	if not is_ready():
		return
	if power < 0.0:
		power = 9.0
	var p := loaded
	var f := _frame_at(_start_i)
	var t: Vector3 = f[0]
	var s: Vector3 = f[1]
	# Yuvarlanma: ω = v × (yukarı) / r  ->  ekseni yan vektör
	p.launch(t * power, s * power / p.radius)
	fired.emit(p)


func hint() -> String:
	return "Sağa-sola sürükle: hizala   •   Yukarı kaydır ya da FIRLAT   •   AYAR: rampa türü"
