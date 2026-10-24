class_name MissionRunner
extends Node
## Etkin görevi yürütür: atışları sayar, hedefi yoklar, başarı/başarısızlıkta sonucu gösterir.

signal finished(success: bool, stars: int)

var mission := {}
var shots := 0
var done := false
var castle: Castle
var crowd: Crowd
var hud: Node
var _poll := 0.0
var _settle := 0.0
var _last: Projectile


func start(m: Dictionary, c: Castle, cr: Crowd, h: Node) -> void:
	mission = m
	castle = c
	crowd = cr
	hud = h
	_refresh()


func on_fired(p: Projectile) -> void:
	if done:
		return
	shots += 1
	_last = p
	_settle = 0.0
	_refresh()


func _refresh() -> void:
	hud.set_mission_text("%s — %s\nAtış %d / %d   %s" % [mission["title"], mission["goal"], shots, mission["limit"], progress()])


## Hedefin ilerleme metni (varsa)
func progress() -> String:
	match mission["id"]:
		"gate":
			return "Yıkılan kule: %d / 2" % _gate_towers_down()
		"breach":
			return "Gedik: %d / 12 blok" % _breach_blocks()
		"raid":
			return "Etkisiz: %d / 20" % (crowd.figures.size() - crowd.alive_count())
		"raze":
			return "Yıkım: %%%d / %%40" % roundi((1.0 - castle.intact_ratio()) * 100.0)
	return ""


func _met() -> bool:
	match mission["id"]:
		"bridge":
			return castle.bridge._down
		"gate":
			return _gate_towers_down() >= 2
		"breach":
			return _breach_blocks() >= 12
		"raid":
			return crowd.figures.size() - crowd.alive_count() >= 20
		"commander":
			for s in crowd.figures:
				if s.role == "commander":
					return not s.alive
			return false
		"flag":
			return castle.flag.down
		"raze":
			return castle.intact_ratio() <= 0.6
	return false


func _gate_towers_down() -> int:
	var n := 0
	for t: Dictionary in castle.parts[0]._towers:
		var c: Vector3 = t["center"]
		if absf(c.z + Castle.OZ) < 1.0 and absf(absf(c.x) - 11.0) < 1.0 and t["fallen"]:
			n += 1
	return n


## Dış ön surun (kapı kuleleri ile köşe kuleleri arası) alt 3 sırasında kopan bloklar
func _breach_blocks() -> int:
	var n := 0
	var part: Fortress = castle.parts[0]
	for i in part._defs.size():
		var d: Dictionary = part._defs[i]
		var p: Vector3 = d["pos"]
		if d["layer"] <= 2 and absf(p.z + Castle.OZ) < 2.0 and absf(p.x) > 17.0 and absf(p.x) < Castle.OX - 8.0:
			if not part._alive_def(i):
				n += 1
	return n


func _process(delta: float) -> void:
	if done or mission.is_empty():
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.4
	_refresh()
	if _met():
		_finish(true)
		return
	if shots >= int(mission["limit"]):
		# Son mermi durulunca (ya da 12 sn sonra) başarısız
		_settle += 0.4
		var still := not is_instance_valid(_last) or _last.linear_velocity.length() < 0.5
		if (still and _settle > 4.0) or _settle > 12.0:
			_finish(false)


func _finish(success: bool) -> void:
	done = true
	var st := 0
	if success:
		var s: Array = mission["stars"]
		st = 3 if shots <= int(s[0]) else (2 if shots <= int(s[1]) else 1)
		Missions.save_stars(mission["id"], st)
	finished.emit(success, st)
	hud.show_result(mission, success, st, shots)
