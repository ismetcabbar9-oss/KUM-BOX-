class_name Building
extends Node3D
## Gerçek bina modeli + önceden kesilmiş parçalar (tools/fracture_buildings.gd).
## Sağlamken tek mesh çizilir (az draw call). Herhangi bir parça uyandığında bina
## "kırılır": tek mesh gizlenir, parçaların mesh'leri görünür olur.

signal broke(building: Building)

const DENSITY := 420.0

var chunks: Array[Destructible] = []
var broken := false
var _intact: MeshInstance3D
var _chunk_meshes: Array[MeshInstance3D] = []


func setup(model_name: String) -> void:
	name = model_name
	var src: Node3D = load("res://assets/buildings/%s.scn" % model_name).instantiate()
	_intact = src.get_node("Intact")
	src.remove_child(_intact)
	_intact.owner = null
	add_child(_intact)
	for mi: MeshInstance3D in src.get_node("Chunks").get_children():
		var d := Destructible.new()
		d.position = mi.position
		var box: Vector3 = mi.get_meta("box")
		d.add_box(box)
		src.get_node("Chunks").remove_child(mi)
		mi.owner = null
		mi.position = Vector3.ZERO
		mi.visible = false
		d.add_child(mi)
		_chunk_meshes.append(mi)
		d.configure("concrete", box.x * box.y * box.z * DENSITY)
		d.woke.connect(_on_chunk_woke)
		add_child(d)
		chunks.append(d)
	src.free()


func _on_chunk_woke(body: Destructible) -> void:
	if broken:
		return
	broken = true
	_intact.visible = false
	for mi in _chunk_meshes:
		mi.visible = true
	Sfx.glass(body.global_position)
	Sfx.crash(body.global_position)
	broke.emit(self)
