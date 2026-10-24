extends Node3D
## Kale mancınığı kalibrasyonu: her (karşı ağırlık, mermi kütlesi) için bırakma anındaki konum ve
## hız (mancınık yerel uzayında) ölçülür -> assets/data/trebuchet_castle.json
## Nişan yardımı bu tablodan yörüngeyi önceden çizer.
## Çalıştırma: godot --headless --path . --fixed-fps 60 res://tools/dev/calibrate_trebuchet.tscn

const CW := [30.0, 60.0, 100.0, 150.0, 200.0, 250.0, 300.0, 350.0, 400.0, 500.0, 650.0, 800.0, 1000.0, 1200.0]
const MASS := [300.0, 800.0, 2000.0, 5000.0, 12000.0, 30000.0, 60000.0]

var _got := false
var _rec := []


func _ready() -> void:
	WorldBuilder.build_ground(self)
	var tb := Trebuchet.new()
	Main_config(tb)
	tb.position = Vector3(0, 55, -24)
	add_child(tb)
	tb.released.connect(func(p: Projectile) -> void:
		_got = true
		var lp := tb.global_transform.affine_inverse() * p.global_position
		var lv := tb.global_transform.basis.inverse() * p.linear_velocity
		_rec = [lp.x, lp.y, lp.z, lv.x, lv.y, lv.z])
	var data := []
	for cw in CW:
		var row := []
		for m in MASS:
			tb.counterweight_t = cw
			tb.cw.mass = cw * 1000.0
			var p := Projectile.new()
			p.setup("granite", 1.0, false)
			add_child(p)
			p.mass = m
			tb.load_projectile(p)
			for k in 3:
				await get_tree().physics_frame
			_got = false
			tb.fire()
			for k in 300:
				await get_tree().physics_frame
				if _got:
					break
			row.append(_rec if _got else [])
			print("cw=%5.0f t  kütle=%6.0f kg  -> %s" % [cw, m, str(_rec) if _got else "BIRAKMADI"])
			p.queue_free()
			await get_tree().physics_frame
		data.append(row)
	var f := FileAccess.open("res://assets/data/trebuchet_castle.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"cw": CW, "mass": MASS, "data": data}))
	f.close()
	print("kaydedildi")
	get_tree().quit()


## main.gd'deki kale mancınığıyla aynı yapı
static func Main_config(tb: Trebuchet) -> void:
	tb.max_counterweight = 1200.0
	tb.base_radius = 1.0
	tb.pivot_h = 15.0
	tb.l_long = 23.0
	tb.release_deg = 55.0
