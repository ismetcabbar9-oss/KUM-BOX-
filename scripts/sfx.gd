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
		"rock": _load_set("rock_impact_", 3),
		"brick": _load_set("brick_impact_", 3),
		"concrete": _load_set("brick_impact_", 3),
		"wood": _load_set("wood_impact_", 2),
		"metal": _load_set("wood_impact_", 2),
		"debris": _load_set("debris_", 3),
		"crash": [load(S + "crash_big.wav")],
	}
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
	_ambient.stream = load(S + "wind_loop.wav")
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
		arr.append(load(S + prefix + str(i) + ".wav"))
	return arr


func _physics_process(_delta: float) -> void:
	_played_this_frame = 0


func _play(kind: String, pos: Vector3, volume_db: float, pitch: float) -> void:
	if _played_this_frame >= MAX_PER_FRAME:
		return
	_played_this_frame += 1
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	var set_: Array = _streams[kind]
	p.stream = set_[randi() % set_.size()]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * Engine.time_scale
	p.play()


## strength: çarpışmadaki hız değişimi (m/s).
func impact(kind: String, pos: Vector3, strength: float) -> void:
	var vol := linear_to_db(clampf(strength / 12.0, 0.08, 1.0)) + 4.0
	var pitch := randf_range(0.85, 1.12)
	match kind:
		"metal":
			pitch *= 2.2
		"concrete":
			pitch *= 0.8
		"rock":
			pitch *= 0.9
			vol += 4.0
	_play(kind, pos, vol, pitch)
	if kind == "rock" and strength > 25.0:
		_play("crash", pos, 6.0, randf_range(0.9, 1.05))


func debris(pos: Vector3, strength: float) -> void:
	_play("debris", pos, linear_to_db(clampf(strength / 10.0, 0.1, 0.8)), randf_range(0.8, 1.25))


func set_slow_motion(on: bool) -> void:
	AudioServer.playback_speed_scale = 0.5 if on else 1.0
