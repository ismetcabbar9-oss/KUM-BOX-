extends SceneTree
## Mixamo iskeletleri arasında animasyon aktarma (pişirme).
## Kemikler ad tabanına göre eşlenir ("mixamorig_LeftArm_37" -> "LeftArm"). Eksenleri ve ölçekleri
## farklı iskeletler için dönüş dünya uzayında aktarılır:
##   D(b)   = G_kaynak(b, t) · R_kaynak(b)⁻¹     (bağlama pozuna göre dünya dönüşü)
##   G_h(b) = D(b) · R_hedef(b)
##   yerel  = G_h(ebeveyn)⁻¹ · G_h(b)
## Kalça yalnız dikeyde (boy oranıyla ölçekli) hareket eder; yerinde (in-place) animasyon.
## Çıktı: assets/anims/<hedef>.res (AnimationLibrary)
##
## Çalıştırma: godot --headless --path . -s res://tools/retarget_anims.gd

const FPS := 30.0
## Başka iskeletten aktarılan animasyonlarda yalnız gövde kemikleri (parmak/yüz izleri atlanır:
## kalabalıkta animasyon maliyeti ~3 kat düşer)
const CORE := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
const JOBS := [
	# [hedef model, kaynak model, [[kaynak animasyon, yeni ad, döngü], ...]]
	["soldier", "anim_donor", [["male_Idle", "idle", true], ["male_Walk", "walk", true], ["male_Run", "run", true], ["male_Death", "death", false], ["male_Attack", "attack", true]]],
	["archer", "anim_donor", [["male_Walk", "walk", true], ["male_Run", "run", true], ["male_Death", "death", false]]],
	["archer", "archer", [["mixamo_com", "shoot", true]]],
	["peasant", "peasant", [["Walk cycle", "walk", true]]],
	["peasant", "peasant_idle", [["Idle", "idle", true]]],
	["peasant", "peasant_swing", [["USwing", "swing", true]]],
	["peasant", "anim_donor", [["male_Run", "run", true], ["male_Death", "death", false]]],
]


class Rig:
	var root: Node3D
	var sk: Skeleton3D
	var ap: AnimationPlayer
	var path_basis: Basis  # iskelet -> model kökü (yalnız dönüş)
	var path_scale := 1.0
	var by_base := {}  # taban ad -> kemik indeksi

	func _init(scene: Node3D) -> void:
		root = scene
		sk = scene.find_children("*", "Skeleton3D", true, false)[0]
		var aps := scene.find_children("*", "AnimationPlayer", true, false)
		ap = aps[0] if aps.size() > 0 else null
		var t := Transform3D.IDENTITY
		var n: Node = sk
		while n and n != root:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		path_basis = t.basis.orthonormalized()
		path_scale = t.basis.get_scale().x
		for i in sk.get_bone_count():
			by_base[base_name(sk.get_bone_name(i))] = i

	## CAT/Biped kemik adları -> Mixamo taban adları
	const ALIAS := {
		"Pelvis": "Hips", "Spine1": "Spine", "Spine3": "Spine1", "Ribcage": "Spine2",
		"Neck1": "Neck", "LCollarbone": "LeftShoulder", "LUpperarm": "LeftArm",
		"LForearm": "LeftForeArm", "LPalm": "LeftHand", "RCollarbone": "RightShoulder",
		"RUpperarm": "RightArm", "RForearm": "RightForeArm", "RPalm": "RightHand",
		"LThigh": "LeftUpLeg", "LCalf": "LeftLeg", "LFoot": "LeftFoot",
		"RThigh": "RightUpLeg", "RCalf": "RightLeg", "RFoot": "RightFoot",
	}
	static var cat_mode := false

	static func base_name(b: String) -> String:
		b = b.replace("mixamorig:", "").replace("mixamorig_", "")
		var parts := b.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			b = parts[0]
		if b.begins_with("Peasant"):
			b = b.substr(7)
			if cat_mode:
				return ALIAS.get(b, "cat_" + b)
		return b

	## Model uzayında kemik dünya dönüşü (pozdan ya da dinlenmeden)
	func global_rot(i: int, rest: bool) -> Quaternion:
		var q := Quaternion.IDENTITY
		var b := i
		while b >= 0:
			var local := sk.get_bone_rest(b).basis if rest else Basis(sk.get_bone_pose_rotation(b))
			q = Quaternion(local.orthonormalized()) * q
			b = sk.get_bone_parent(b)
		return Quaternion(path_basis) * q

	## Model uzayında kemik konumu (ölçekli)
	func global_pos(i: int, rest: bool) -> Vector3:
		var t := Transform3D.IDENTITY
		var b := i
		while b >= 0:
			var local := sk.get_bone_rest(b) if rest else Transform3D(Basis(sk.get_bone_pose_rotation(b)).scaled(sk.get_bone_pose_scale(b)), sk.get_bone_pose_position(b))
			t = local * t
			b = sk.get_bone_parent(b)
		var full := Transform3D(path_basis.scaled(Vector3.ONE * path_scale), Vector3.ZERO) * t
		return full.origin


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/anims"))
	var libs := {}
	for job in JOBS:
		var target_name: String = job[0]
		var src_name: String = job[1]
		Rig.cat_mode = target_name == "peasant" and src_name == "anim_donor"
		var tgt_scene: Node3D = load("res://assets/models/%s/scene.gltf" % target_name).instantiate()
		var src_scene: Node3D = load("res://assets/models/%s/scene.gltf" % src_name).instantiate()
		root.add_child(tgt_scene)
		root.add_child(src_scene)
		var tgt := Rig.new(tgt_scene)
		var src := Rig.new(src_scene)
		var lib: AnimationLibrary = libs.get(target_name, AnimationLibrary.new())
		libs[target_name] = lib
		for spec in job[2]:
			var anim := _bake(src, tgt, spec[0], spec[2])
			if anim:
				lib.add_animation(spec[1], anim)
				print("%s <- %s.%s : %s (%.2f sn, %d iz)" % [target_name, src_name, spec[0], spec[1], anim.length, anim.get_track_count()])
		tgt_scene.queue_free()
		src_scene.queue_free()
	for k in libs:
		var err := ResourceSaver.save(libs[k], "res://assets/anims/%s.res" % k)
		print("kaydedildi: assets/anims/%s.res (%s)" % [k, error_string(err)])
	quit()


func _bake(src: Rig, tgt: Rig, anim_name: String, loop: bool) -> Animation:
	if not src.ap.has_animation(anim_name):
		push_error("animasyon yok: " + anim_name)
		return null
	var a := src.ap.get_animation(anim_name)
	src.ap.play(anim_name)
	# Eşlenen kemikler (hedef sırası: ebeveyn önce)
	var pairs := []  # [hedef indeks, kaynak indeks]
	var same := src.root.scene_file_path.get_base_dir() == tgt.root.scene_file_path.get_base_dir() or src.sk.get_bone_count() == tgt.sk.get_bone_count()
	for i in tgt.sk.get_bone_count():
		var base := Rig.base_name(tgt.sk.get_bone_name(i))
		var fine := false
		for pat in ["Digit", "Thumb", "Index", "Middle", "Ring", "Pinky", "HeadBone", "Eye", "_End", "HeadTop"]:
			if base.contains(pat):
				fine = true
		if src.by_base.has(base) and not fine and (same or base in CORE):
			pairs.append([i, src.by_base[base]])
	var src_rest := {}
	var tgt_rest := {}
	for p in pairs:
		src_rest[p[1]] = src.global_rot(p[1], true)
		tgt_rest[p[0]] = tgt.global_rot(p[0], true)
	var out := Animation.new()
	out.length = a.length
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var ap_root := tgt.ap.get_node(tgt.ap.root_node)
	var sk_path := String(ap_root.get_path_to(tgt.sk))
	var tracks := {}
	for p in pairs:
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath(sk_path + ":" + tgt.sk.get_bone_name(p[0])))
		tracks[p[0]] = tr
	var hips_t: int = tgt.by_base.get("Hips", -1)
	var hips_s: int = src.by_base.get("Hips", -1)
	var pos_tr := -1
	var src_h := src.global_pos(hips_s, true).y
	var tgt_h := tgt.global_pos(hips_t, true).y
	if hips_t >= 0 and hips_s >= 0:
		pos_tr = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(pos_tr, NodePath(sk_path + ":" + tgt.sk.get_bone_name(hips_t)))
	var frames := maxi(2, int(ceil(a.length * FPS)) + 1)
	for f in frames:
		var t := minf(f / FPS, a.length)
		src.ap.seek(t, true)
		var mapped := {}
		for p in pairs:
			var d: Quaternion = src.global_rot(p[1], false) * src_rest[p[1]].inverse()
			mapped[p[0]] = d * tgt_rest[p[0]]
		# Tüm hedef kemiklerin dünya dönüşü (ebeveyn önce): eşlenmeyen kemik dinlenme yerel
		# dönüşüyle animasyonlu ebeveyni izler
		var g_t := {}
		for i in tgt.sk.get_bone_count():
			var par := tgt.sk.get_bone_parent(i)
			var pg: Quaternion = g_t[par] if g_t.has(par) else Quaternion(tgt.path_basis)
			if mapped.has(i):
				g_t[i] = mapped[i]
				out.rotation_track_insert_key(tracks[i], t, (pg.inverse() * g_t[i]).normalized())
			else:
				g_t[i] = pg * Quaternion(tgt.sk.get_bone_rest(i).basis.orthonormalized())
		if pos_tr >= 0:
			# Kalça: yalnız dikey salınım, boy oranıyla ölçekli (yerinde animasyon)
			var dy := (src.global_pos(hips_s, false).y - src_h) / maxf(src_h, 0.001) * tgt_h
			var par := tgt.sk.get_bone_parent(hips_t)
			var pb := tgt.global_rot(par, true) if par >= 0 else Quaternion(tgt.path_basis)
			var local_dy := (pb.inverse() * Vector3(0, dy, 0)) / maxf(_chain_scale(tgt, par), 0.0001)
			out.position_track_insert_key(pos_tr, t, tgt.sk.get_bone_rest(hips_t).origin + local_dy)
	return out


## Ebeveyn kemiğe kadar birikmiş ölçek (yol ölçeği × kemik dinlenme ölçekleri)
func _chain_scale(r: Rig, i: int) -> float:
	var s := r.path_scale
	var b := i
	while b >= 0:
		s *= r.sk.get_bone_rest(b).basis.get_scale().x
		b = r.sk.get_bone_parent(b)
	return s
