class_name Launcher
extends Node3D
## Fırlatıcı tabanı. Her fırlatıcı bir "istasyon"dur: mermiyi yükler, dokunmatikle
## nişan/güç ayarlanır, fire() ile fiziksel olarak fırlatır.

signal fired(projectile: Projectile)

## Ekranda görünen ad
var title := ""
## Mermi yarıçapı ölçeği (BOYUT ile çarpılır)
var base_radius := 1.0
var loaded: Projectile
## Kamera: istasyonda bakış hedefi ve uzaklık
var view_target: Node3D
var view_distance := 16.0


func _init() -> void:
	view_target = Node3D.new()
	add_child(view_target)


## Mermiyi yerleştir (fırlatıcıya ait çocuk değil, dünyaya eklenir).
func load_projectile(_p: Projectile) -> void:
	pass


## Yuvarlanma çarpışması mı (rampa) yoksa gerçek şekil mi
func rolling() -> bool:
	return false


## Parmak ekrana değdi (fırlatıcı hazırken)
func press() -> void:
	pass


## FIRLAT butonu kullanılıyor mu (sapan: hayır, çek-bırak)
func uses_button() -> bool:
	return true


func drag(_relative: Vector2, _viewport_size: Vector2) -> void:
	pass


## Parmak kalktı: true dönerse fırlatıldı (ör. sapan bırakıldı, hızlı kaydırma)
func release(_swipe_up_speed: float) -> bool:
	return false


func fire(_power := -1.0) -> void:
	pass


## Arayüzde gösterilecek nişan/güç bilgisi
func info() -> String:
	return ""


func hint() -> String:
	return ""


## Fırlatma sonrası her karede (ör. kol animasyonu, lastik) — gerekirse
func is_ready() -> bool:
	return loaded != null and not loaded.launched


# --- Yörünge önizlemesi (sapan/top) ---------------------------------------

var _arc: MultiMeshInstance3D


func _show_arc(origin: Vector3, v0: Vector3) -> void:
	if _arc == null:
		_arc = MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var dot := SphereMesh.new()
		dot.radius = 0.18
		dot.height = 0.36
		dot.radial_segments = 8
		dot.rings = 4
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.85, 0.3)
		dot.material = m
		mm.mesh = dot
		mm.instance_count = 28
		_arc.multimesh = mm
		_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_arc.top_level = true
		add_child(_arc)
	_arc.visible = true
	var g := Vector3(0, -9.81, 0)
	var mm := _arc.multimesh
	for i in mm.instance_count:
		var t := 0.12 * (i + 1)
		var p := origin + v0 * t + 0.5 * g * t * t
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p if p.y > 0.0 else Vector3(0, -100, 0)))


func _hide_arc() -> void:
	if _arc:
		_arc.visible = false


## Basit gövde: statik kutu + doku
static func beam(parent: Node3D, size: Vector3, xf: Transform3D, mat: Material, collide := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = xf
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		body.transform = xf
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		parent.add_child(body)
