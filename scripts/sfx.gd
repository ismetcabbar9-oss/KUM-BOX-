extends Node
## Ses yöneticisi: 3D ses havuzu, bus/efekt kurulumu, kare başına ses sınırı.

const POOL_SIZE := 28
const MAX_PER_FRAME := 5
const S := "res://assets/sounds/"

var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _played_this_frame := 0
var _streams := {}
var _ambient: AudioStreamPlayer


func _ready() -> void:
	_setup_buses()
	_streams = {
		"rock": _load_set("rock_impact_", 6),
		"concrete": _load_set("concrete_impact_", 7),
		"wood": _load_set("wood_impact_", 5),
		"metal": _load_set("metal_impact_", 3),
		"debris": _load_set("debris_", 6),
		"crash": _load_set("crash_big_", 3),
		"glass": _load_set("glass_", 3),
		"explosion": _load_set("explosion_", 3),
		"catapult": _load_set("catapult_", 2),
		"sling": _load_set("sling_", 3),
		"cannon": _load_set("cannon_", 2),
		"creak": _load_set("creak_", 2),
		"stone_crash": _load_set("stone_crash_", 2),
		"rocket_ignite": _load_set("rocket_ignite_", 1),
		"chain": _load_set("chain_", 2),
		"beep": _load_set("beep_", 1),
		"horn": _load_set("horn_", 2),
		"scream": _load_set("scream_", 8),
		"yell": _load_set("yell_", 6),
		"arrow_whoosh": _load_set("arrow_whoosh_", 3),
		"arrow_hit": _load_set("arrow_hit_", 3),
		"anvil": _load_set("anvil_", 3),
	}
	# Tuğla ve taş da beton kayıtlarını kullanır (perde farkıyla)
	_streams["brick"] = _streams["concrete"]
	_streams["stone"] = _streams["concrete"]
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 12.0
		p.max_distance = 400.0
		p.attenuation_filter_cutoff_hz = 6000.0
		p.attenuation_filter_db = -12.0
		add_child(p)
		_pool.append(p)
	_ambient = AudioStreamPlayer.new()
	_ambient.stream = load(S + "ambient_loop.ogg")
	_ambient.bus = "Ambient"
	_ambient.volume_db = -14.0
	add_child(_ambient)
	_ambient.play()


func _setup_buses() -> void:
	if AudioServer.get_bus_index("SFX") != -1:
		return
	# Master: sınırlayıcı -> patlamalarda bozulma olmasın
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)
	AudioServer.add_bus()
	var sfx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(sfx, "SFX")
	AudioServer.set_bus_send(sfx, "Master")
	var comp := AudioEffectCompressor.new()
	comp.threshold = -16.0
	comp.ratio = 3.0
	AudioServer.add_bus_effect(sfx, comp)
	# Açık alan yankısı: kısa, düşük ıslaklık
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.55
	rev.damping = 0.6
	rev.wet = 0.18
	rev.dry = 1.0
	rev.predelay_msec = 40.0
	AudioServer.add_bus_effect(sfx, rev)
	AudioServer.add_bus()
	var amb := AudioServer.bus_count - 1
	AudioServer.set_bus_name(amb, "Ambient")
	AudioServer.set_bus_send(amb, "Master")


func _load_set(prefix: String, count: int) -> Array:
	var arr := []
	for i in count:
		var path := S + prefix + str(i) + ".ogg"
		if ResourceLoader.exists(path):
			arr.append(load(path))
	return arr


## Tek dosyalık ses (döngüler): yoksa null.
func stream(name: String) -> AudioStream:
	var path := S + name + ".ogg"
	return load(path) if ResourceLoader.exists(path) else null


## Adlandırılmış ses setinden çal (fırlatıcı sesleri vb.).
func play(set_name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	_play(set_name, pos, volume_db, pitch * randf_range(0.95, 1.05))


func explosion(pos: Vector3) -> void:
	_played_this_frame = 0
	_play("explosion", pos, 8.0, randf_range(0.9, 1.05))
	_play("crash", pos, 2.0, randf_range(0.8, 0.95))


func _physics_process(_delta: float) -> void:
	_played_this_frame = 0


func _play(kind: String, pos: Vector3, volume_db: float, pitch: float) -> void:
	if _played_this_frame >= MAX_PER_FRAME:
		return
	_played_this_frame += 1
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	var set_: Array = _streams.get(kind, [])
	if set_.is_empty():
		return
	p.stream = set_[randi() % set_.size()]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * Engine.time_scale
	p.play()


## strength: çarpışmadaki hız değişimi (m/s).
func impact(kind: String, pos: Vector3, strength: float) -> void:
	var vol := linear_to_db(clampf(strength / 12.0, 0.08, 1.0)) + 4.0
	var pitch := randf_range(0.88, 1.1)
	match kind:
		"stone":
			pitch *= 0.75
		"brick":
			pitch *= 1.1
		"rock":
			vol += 4.0
	_play(kind, pos, vol, pitch)
	if kind == "rock" and strength > 25.0:
		crash(pos)


func crash(pos: Vector3, set_name := "crash") -> void:
	_play(set_name, pos, 4.0, randf_range(0.9, 1.05))


func glass(pos: Vector3) -> void:
	_play("glass", pos, -2.0, randf_range(0.9, 1.1))


func debris(pos: Vector3, strength: float) -> void:
	_play("debris", pos, linear_to_db(clampf(strength / 10.0, 0.1, 0.8)), randf_range(0.8, 1.25))


func set_slow_motion(on: bool) -> void:
	AudioServer.playback_speed_scale = 0.5 if on else 1.0
