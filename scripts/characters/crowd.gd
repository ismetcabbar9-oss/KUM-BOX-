class_name Crowd
extends Node
## Kale halkı: figürleri kurar, animasyonlarını mesafeye göre seyrek ilerletir, alarmı yönetir
## (borazan, kalabalık bağırışı, kaçışma), okçuların atışlarını hedefe yönlendirir.

## Darbe/patlama alarmı buradan duyurulur (Building.strike, Projectile.explode)
static var inst: Crowd

const MAX_ARROWS := 40
## Animasyon güncelleme sıklığı (kare aralığı) mesafeye göre
const ANIM_STEPS := [[30.0, 1], [70.0, 2], [140.0, 4], [260.0, 8]]

var figures: Array[Soldier] = []
var castle: Castle
var camera: Camera3D
## Okçuların hedefi (etkin fırlatıcının çevresi)
var target := Vector3.ZERO
var _frame := 0
var _acc := PackedFloat32Array()
var _arrows: Array[Arrow] = []
var _horn_cd := 0.0
var _yell_cd := 0.0
var _scream_cd := 0.0
var _arrow_cd := 0.0
var _crowd_player: AudioStreamPlayer3D
var _alarm_t := 0.0
var _anvil: Array[Soldier] = []
var _anvil_t := 0.0


func _init() -> void:
	inst = self


func build(c: Castle) -> void:
	castle = c
	for spot in c.soldier_spots:
		var s := _spawn(spot[3], spot[2], Transform3D(Basis(Vector3.UP, spot[1]), c.to_global(spot[0])))
		s.begin_stand()
	for r in c.routes:
		var pts := PackedVector3Array()
		for p in r["pts"]:
			pts.append(c.to_global(p))
		for k in r["count"]:
			var s := _spawn(r["kind"], r["role"], Transform3D(Basis.IDENTITY, pts[0]))
			# Halkada eşit aralıklı başlangıç; git-gelde rastgele uç
			s.begin_route(pts, r["loop"], int(float(k) / r["count"] * pts.size()) if r["loop"] else randi() % pts.size())
	for w in c.work_spots:
		var s := _spawn(w[4], "worker", Transform3D(Basis(Vector3.UP, w[1]), c.to_global(w[0])))
		s.begin_work(w[2])
		if w[2] == "swing" and w[0].x > 0.0:
			_anvil.append(s)
	_acc.resize(figures.size())
	_crowd_player = AudioStreamPlayer3D.new()
	_crowd_player.stream = Sfx.stream("crowd_loop")
	_crowd_player.bus = "SFX"
	_crowd_player.unit_size = 60.0
	_crowd_player.max_distance = 600.0
	_crowd_player.volume_db = -80.0
	add_child(_crowd_player)
	_crowd_player.global_position = c.to_global(Vector3(0, 10, -30))


func _spawn(kind: String, role: String, xf: Transform3D) -> Soldier:
	var s := Soldier.new()
	s.setup(kind)
	s.role = role
	s.crowd = self
	add_child(s)
	s.global_transform = xf
	s.died.connect(_on_died)
	figures.append(s)
	return s


func stats() -> String:
	var c := {}
	for f in figures:
		var k: String = Soldier.St.keys()[f.state]
		c[k] = c.get(k, 0) + 1
	return str(c) + " ok=%d" % _arrows.size()


func alive_count() -> int:
	return figures.filter(func(s: Soldier) -> bool: return s.alive).size()


var prof_anim := 0
var prof_n := 0


func _process(delta: float) -> void:
	_frame += 1
	var t0 := Time.get_ticks_usec()
	var cam_pos := camera.global_position if camera else Vector3.ZERO
	# Animasyon LOD: yakındakiler her kare, uzaktakiler seyrek (biriken süreyle)
	for i in figures.size():
		var s := figures[i]
		_acc[i] += delta
		var d := s.global_position.distance_to(cam_pos)
		var every := 16
		for st in ANIM_STEPS:
			if d < st[0]:
				every = st[1]
				break
		if (_frame + i) % every == 0:
			s.anim_tick(_acc[i])
			prof_n += 1
			_acc[i] = 0.0
	prof_anim += Time.get_ticks_usec() - t0
	_horn_cd -= delta
	_yell_cd -= delta
	_scream_cd -= delta
	_arrow_cd -= delta
	# Alarm sonrası kalabalık uğultusu yükselip söner
	_alarm_t -= delta
	var want := -6.0 if _alarm_t > 0.0 else -80.0
	if want > -60.0 and not _crowd_player.playing:
		_crowd_player.play()
	_crowd_player.volume_db = lerpf(_crowd_player.volume_db, want, clampf(delta * (1.5 if want > -60.0 else 0.4), 0.0, 1.0))
	if _crowd_player.playing and _crowd_player.volume_db < -70.0 and _alarm_t <= 0.0:
		_crowd_player.stop()
	# Demirci: çekiç vuruşları
	_anvil_t -= delta
	if _anvil_t <= 0.0:
		_anvil_t = randf_range(0.9, 1.3)
		for s in _anvil:
			if s.alive and s.state == Soldier.St.WORK and s.global_position.distance_to(cam_pos) < 120.0:
				Sfx.play("anvil", s.global_position + Vector3.UP, -6.0)


## Darbe/çöküş/patlama: yakındaki halk kaçışır, borazan çalar, bağırışlar yükselir
func alarm(point: Vector3, energy: float) -> void:
	if castle == null:
		return
	_alarm_t = 18.0
	if _horn_cd <= 0.0:
		_horn_cd = 30.0
		Sfx.play("horn", castle.to_global(Vector3(0, 62, 20)), 10.0)
	var r := clampf(25.0 + energy / 1e6 * 4.0, 25.0, 70.0)
	var local_danger := castle.to_local(point)
	var yelled := 0
	for s in figures:
		if not s.alive:
			continue
		var d := s.global_position.distance_to(point)
		if d > r:
			continue
		if s.global_position.y - castle.global_position.y < 1.0:
			s.panic(_world_path(castle.flee_path(castle.to_local(s.global_position), local_danger)))
		if yelled < 2 and _yell_cd <= 0.0:
			yelled += 1
			Sfx.play("yell", s.global_position + Vector3.UP * 1.6, 2.0, randf_range(0.9, 1.1))
	if yelled > 0:
		_yell_cd = 0.6


func _world_path(local: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in local:
		out.append(castle.to_global(p))
	return out


func _on_died(s: Soldier) -> void:
	if _scream_cd <= 0.0:
		_scream_cd = 0.35
		Sfx.play("scream", s.global_position + Vector3.UP * 1.5, 4.0, randf_range(0.85, 1.15))


## Okçu oku bıraktı: hedefe (etkin fırlatıcı çevresi) balistik atış
func archer_shot(s: Soldier) -> void:
	if _arrow_cd > 0.0:
		return
	_arrow_cd = 0.35
	if _arrows.size() >= MAX_ARROWS:
		var old: Arrow = _arrows.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	_arrows = _arrows.filter(func(a: Arrow) -> bool: return is_instance_valid(a))
	var start := s.global_position + Vector3.UP * 1.5 + s.global_transform.basis.z * 0.6
	var aim := target + Vector3(randf_range(-14, 14), 0, randf_range(-18, 10))
	var v := _ballistic(start, aim, deg_to_rad(randf_range(32.0, 42.0)))
	if v == Vector3.ZERO:
		return
	var a := Arrow.new()
	a.velocity = v
	add_child(a)
	a.global_position = start
	_arrows.append(a)
	if camera and s.global_position.distance_to(camera.global_position) < 90.0:
		Sfx.play("arrow_whoosh", start, -2.0)


## Verilen yükselme açısıyla start -> aim isabeti için hız vektörü (yoksa sıfır)
static func _ballistic(start: Vector3, aim: Vector3, angle: float) -> Vector3:
	var flat := Vector3(aim.x - start.x, 0, aim.z - start.z)
	var d := flat.length()
	var h := aim.y - start.y
	var denom := 2.0 * pow(cos(angle), 2.0) * (d * tan(angle) - h)
	if denom <= 0.0 or d < 1.0:
		return Vector3.ZERO
	var speed := sqrt(9.81 * d * d / denom)
	if speed > 90.0:
		return Vector3.ZERO  # menzil dışı
	return flat / d * speed * cos(angle) + Vector3.UP * speed * sin(angle)
