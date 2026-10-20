class_name Caveman
extends Node3D
## Taş devri adamı (rigli model, prosedürel poz). Modlar:
##   idle   : hazır bekleyiş, hafif nefes
##   strain : eğilmiş, elleri kayada, ayaklar yere basıp iter (adım fazı ile yürür)
##   cheer  : kollar havada sevinç
## Konum/yön dışarıdan (Crew) verilir; model yalnız görseldir (çarpışma yok).

var mode := "idle"
## İtme yürüyüşü fazı hızı (rad/sn); 0: yerinde zorlanma
var step_rate := 0.0
var lean := 0.9
var _rig: RigPose
var _t := 0.0
var _phase := 0.0
var _seed := 0.0


func setup(variant: String) -> void:
	var model := Models.instance(variant)
	add_child(model)
	Models.fit(model, 1.85, "height")
	# Daha iri, kaslı yapı
	model.scale *= Vector3(1.12, 1.0, 1.12)
	model.position *= Vector3(1.12, 1.0, 1.12)
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	_rig = RigPose.new(sk, self)
	_seed = randf() * TAU


func _process(delta: float) -> void:
	_t += delta
	_phase += delta * step_rate
	_rig.reset()
	match mode:
		"strain":
			_pose_strain()
		"cheer":
			_pose_cheer()
		_:
			_pose_idle()


func _pose_idle() -> void:
	var b := sin(_t * 1.7 + _seed) * 0.03
	_rig.aim("Spine", "Neck", Vector3(0, 1, 0.08 + b))
	_rig.arm("Left", Vector3(0.28, -1, 0.08), Vector3(0.12, -1, 0.35))
	_rig.arm("Right", Vector3(0.28, -1, 0.08), Vector3(0.12, -1, 0.35))
	_rig.leg("Left", 0.05, 0.08, 0.1)
	_rig.leg("Right", -0.05, 0.08, 0.1)


func _pose_strain() -> void:
	var l := lean + sin(_t * 9.0 + _seed) * 0.02  # zorlanma titremesi
	_rig.turn("Hips", Vector3.RIGHT, l * 0.5)
	_rig.shift("Hips", Vector3(0, -0.14, -0.2))
	_rig.aim("Spine", "Neck", Vector3(0, cos(l), sin(l)))
	_rig.aim("Neck", "Head", Vector3(0, cos(l * 0.35), sin(l * 0.35)))
	# Avuçlar kayada: kollar hafif yukarı, dirsekler bükülü (gövde ağırlığı kollarda)
	_rig.arm("Left", Vector3(0.3, -0.05, 1), Vector3(-0.05, 0.3, 1))
	_rig.arm("Right", Vector3(0.3, -0.05, 1), Vector3(-0.05, 0.3, 1))
	# Bacaklar: ön bacak bükülü, arka bacak gergin ve geride; iterken adım atar
	var s := sin(_phase)
	var walking := step_rate > 0.0
	var amp := 0.3 if walking else 0.0
	var base_l := -0.2 if walking else 0.1
	var base_r := -0.2 if walking else -0.6
	_rig.leg("Left", base_l + amp * s, (0.3 + 0.5 * maxf(0.0, cos(_phase))) if walking else 0.7)
	_rig.leg("Right", base_r - amp * s, (0.3 + 0.5 * maxf(0.0, -cos(_phase))) if walking else 0.08)


func _pose_cheer() -> void:
	var w := sin(_t * 8.0 + _seed) * 0.25
	_rig.aim("Spine", "Neck", Vector3(0, 1, -0.08))
	_rig.arm("Left", Vector3(0.45, 1, 0.1 + w), Vector3(0.15, 1, 0.2))
	_rig.arm("Right", Vector3(0.45, 1, 0.1 - w), Vector3(0.15, 1, 0.2))
	var hop := maxf(0.0, sin(_t * 8.0 + _seed)) * 0.1
	_rig.shift("Hips", Vector3(0, hop, 0))
	_rig.leg("Left", 0.1, 0.2, 0.12)
	_rig.leg("Right", -0.1, 0.2, 0.12)
