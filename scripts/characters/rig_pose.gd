class_name RigPose
extends RefCounted
## İskelete prosedürel poz: kemikleri karakter uzayında verilen yönlere çevirir.
## Karakter uzayı: +Z ileri, +Y yukarı, +X karakterin solu.
## Her karede reset() -> aim()/turn() sırasıyla (ebeveynden çocuğa) çağrılır.

var sk: Skeleton3D
var _to_sk: Basis  # karakter uzayı -> iskelet uzayı (yalnız dönme)
var _ids := {}


func _init(skeleton: Skeleton3D, root: Node3D) -> void:
	sk = skeleton
	var t := Transform3D.IDENTITY
	var n: Node = skeleton
	while n and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	_to_sk = t.basis.orthonormalized().inverse()


## Kemik bul: önek (mixamorig:) ve "_123" sonekleri atılmış adla, büyük/küçük harf duyarsız
func bone(name: String) -> int:
	if _ids.has(name):
		return _ids[name]
	var want := name.to_lower()
	var found := -1
	for i in sk.get_bone_count():
		var b := sk.get_bone_name(i).to_lower()
		for pre in ["mixamorig:", "mixamorig_"]:
			if b.begins_with(pre):
				b = b.substr(pre.length())
		var parts := b.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			b = parts[0]
		if b == want:
			found = i
			break
	_ids[name] = found
	return found


func reset() -> void:
	sk.reset_bone_poses()


func _global(i: int) -> Transform3D:
	var t := sk.get_bone_pose(i)
	var p := sk.get_bone_parent(i)
	while p >= 0:
		t = sk.get_bone_pose(p) * t
		p = sk.get_bone_parent(p)
	return t


func _set_global_basis(i: int, b: Basis) -> void:
	var p := sk.get_bone_parent(i)
	var pb := _global(p).basis if p >= 0 else Basis.IDENTITY
	sk.set_bone_pose_rotation(i, (pb.inverse() * b).get_rotation_quaternion())


## Kemiği (child kemiğine giden yönü) karakter uzayındaki dir yönüne çevir
func aim(bone_name: String, child_name: String, dir: Vector3) -> void:
	var b := bone(bone_name)
	var c := bone(child_name)
	if b < 0 or c < 0:
		return
	var g := _global(b)
	var cur := (g * sk.get_bone_pose(c).origin - g.origin).normalized()
	var want := (_to_sk * dir).normalized()
	if cur.dot(want) > 0.99999 or cur.length() < 0.5:
		return
	_set_global_basis(b, Basis(Quaternion(cur, want)) * g.basis)


## Kemiği karakter uzayındaki eksen etrafında döndür
func turn(bone_name: String, axis: Vector3, angle: float) -> void:
	var b := bone(bone_name)
	if b < 0:
		return
	var g := _global(b)
	_set_global_basis(b, Basis((_to_sk * axis).normalized(), angle) * g.basis)


## Kemiğin konumunu (ebeveyn uzayında, dinlenme konumuna göre) kaydır: karakter uzayında
func shift(bone_name: String, offset: Vector3) -> void:
	var b := bone(bone_name)
	if b < 0:
		return
	var p := sk.get_bone_parent(b)
	var pb := _global(p).basis if p >= 0 else Basis.IDENTITY
	sk.set_bone_pose_position(b, sk.get_bone_rest(b).origin + pb.inverse() * (_to_sk * offset))


## Bacak: kalça açısı (+ ileri), diz bükümü, yana açılma
func leg(side: String, thigh: float, knee: float, spread := 0.06) -> void:
	var sx := 1.0 if side == "Left" else -1.0
	aim(side + "UpLeg", side + "Leg", Vector3(sx * spread, -cos(thigh), sin(thigh)))
	aim(side + "Leg", side + "Foot", Vector3(sx * spread * 0.5, -cos(thigh - knee), sin(thigh - knee)))
	var toe := side + "Toe" if bone(side + "Toe") >= 0 else side + "ToeBase"
	aim(side + "Foot", toe, Vector3(0, -0.25, 1))


## Kol: üst kol ve ön kol yönleri (sol kol için; sağ kol X'te aynalanır)
func arm(side: String, upper: Vector3, fore: Vector3) -> void:
	var m := Vector3(1, 1, 1) if side == "Left" else Vector3(-1, 1, 1)
	aim(side + "Arm", side + "ForeArm", upper * m)
	aim(side + "ForeArm", side + "Hand", fore * m)
