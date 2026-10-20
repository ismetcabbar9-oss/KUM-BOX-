class_name Crew
extends Node3D
## Fırlatıcı ekibi: iki taş devri adamı. Etkin fırlatıcının istediği yerde ve pozda durur
## (Launcher.crew_spots / crew_mode); fırlatmadan sonra sevinir.

var men: Array[Caveman] = []
var launcher: Launcher
var _cheer := 0.0


func _ready() -> void:
	for v in ["caveman_a", "caveman_b"]:
		var c := Caveman.new()
		c.setup(v)
		add_child(c)
		men.append(c)


func attach(l: Launcher) -> void:
	launcher = l
	_cheer = 0.0
	_place(true)


func on_fired() -> void:
	_cheer = 2.5


func _process(delta: float) -> void:
	if launcher == null:
		return
	if _cheer > 0.0:
		_cheer -= delta
		for i in men.size():
			men[i].mode = "cheer"
			men[i].step_rate = 0.0
		if _cheer <= 0.0 and not launcher.is_ready():
			for m in men:
				m.mode = "idle"
		return
	if launcher.loaded and (launcher.is_ready() or launcher.crew_mode() == "strain"):
		_place(false)


func _place(_snap: bool) -> void:
	var spots: Array = launcher.crew_spots()
	var mode := launcher.crew_mode()
	for i in men.size():
		if i >= spots.size():
			men[i].visible = false
			continue
		men[i].visible = true
		men[i].global_transform = spots[i]
		men[i].mode = mode
		men[i].step_rate = launcher.crew_step_rate()
