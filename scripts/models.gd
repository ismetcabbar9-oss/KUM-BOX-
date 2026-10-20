class_name Models
extends RefCounted
## Model kütüphanesi: glTF sahnelerini önbellekten örnekler, ölçekler, çarpışma şekli üretir.

static var _scenes := {}
static var _hulls := {}


static func instance(model_name: String) -> Node3D:
	if not _scenes.has(model_name):
		_scenes[model_name] = load("res://assets/models/%s/scene.gltf" % model_name)
	return _scenes[model_name].instantiate()


## Düğüm altındaki tüm mesh'lerin, düğüm uzayındaki sınır kutusu (ağaç dışında da çalışır).
static func local_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var xf := _relative_xform(node, mi)
		var b: AABB = xf * mi.mesh.get_aabb()
		result = b if first else result.merge(b)
		first = false
	return result


static func _relative_xform(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != root and cur is Node3D:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Basitleştirilmiş dışbükey örtü noktaları (düğüm uzayında). Model başına önbelleklenir.
static func hull_points(model_name: String, node: Node3D) -> PackedVector3Array:
	if _hulls.has(model_name):
		return _hulls[model_name]
	var pts := PackedVector3Array()
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var xf := _relative_xform(node, mi)
		var hull := mi.mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
		for p in hull.points:
			pts.append(xf * p)
	_hulls[model_name] = pts
	return pts


## Mesh düğümünü, tabanı orijinde ve hedef boyutta olacak şekilde ölçekler.
## fit: "height" | "max" | "length". Geriye uygulanan ölçek döner.
static func fit(node: Node3D, target: float, mode := "max", center_y := false) -> Vector3:
	var b := local_aabb(node)
	var ref := b.size.y
	if mode == "max":
		ref = maxf(b.size.x, maxf(b.size.y, b.size.z))
	elif mode == "length":
		ref = maxf(b.size.x, b.size.z)
	var s := target / ref
	node.scale = Vector3.ONE * s
	var c := b.get_center()
	node.position = -Vector3(c.x, c.y if center_y else b.position.y, c.z) * s
	return Vector3.ONE * s


static func shadowless(node: Node3D) -> void:
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func visibility(node: Node3D, end: float) -> void:
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = end
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
