class_name Progress
extends RefCounted
## Kalıcı ilerleme: puan, fırlatıcı seviyeleri, görev yıldızları (user://kaya_save.json).
##
## Puan: yıkılan blok 1, düşen figür 5, çöken kule 50, inen köprü/sancak 30, görev başarısı
## 20 + yeni kazanılan her yıldız için 100.
## Seviye: her fırlatıcı ayrı yükseltilir. Seviye, atılabilecek en büyük mermi boyutunu açar
## (1: ORTA, 2: BÜYÜK, 3: DEV); mancınıkta karşı ağırlık sınırı da artar.

const SAVE := "user://kaya_save.json"
const MAX_LEVEL := 3
## Seviyeye çıkma bedeli (indeks = hedef seviye)
const COST := [0, 0, 500, 1500]
## Seviyenin açtığı en büyük boyut (main.SIZES indeksi)
const MAX_SIZE := [0, 2, 3, 4]
const SIZE_NAMES := ["", "ORTA", "BÜYÜK", "DEV"]
## Güç çarpanı (hava topu enerjisi, sapan lastiği, roket itkisi)
const POWER := [0.0, 1.0, 1.3, 1.6]
const POWERED := ["cannon", "slingshot", "rocket"]
## Mancınık karşı ağırlık sınırı (ton)
const TREBUCHET_CW := [0, 450.0, 800.0, 1200.0]
const LAUNCHERS := [
	{"id": "ramp", "name": "RAMPA"},
	{"id": "trebuchet", "name": "MANCINIK"},
	{"id": "slingshot", "name": "DEV SAPAN"},
	{"id": "cannon", "name": "HAVA TOPU"},
	{"id": "rocket", "name": "ROKET KIZAĞI"},
]

static var _data := {}
static var _dirty := false


static func _d() -> Dictionary:
	if _data.is_empty():
		var txt := FileAccess.get_file_as_string(SAVE)
		var d = JSON.parse_string(txt) if txt != "" else null
		_data = d if d is Dictionary else {}
		for k in ["stars", "levels"]:
			if not _data.has(k) or not _data[k] is Dictionary:
				_data[k] = {}
		_data["points"] = int(_data.get("points", 0))
	return _data


## Geliştirici testi: kayıt yazılmaz, tüm seviyeler açık
static func _test() -> bool:
	return "--autotest" in OS.get_cmdline_user_args()


static func save() -> void:
	if not _dirty or _test():
		return
	_dirty = false
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_d()))


static func points() -> int:
	return int(_d()["points"])


static func add_points(n: int) -> void:
	if n <= 0:
		return
	_d()["points"] = points() + n
	_dirty = true


static func stars() -> Dictionary:
	return _d()["stars"]


static func set_stars(id: String, st: int) -> void:
	var all := stars()
	all[id] = maxi(int(all.get(id, 0)), st)
	_dirty = true
	save()


static func level(id: String) -> int:
	if _test():
		# Test: --level=N (varsayılan en üst seviye)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--level="):
				return clampi(int(a.get_slice("=", 1)), 1, MAX_LEVEL)
		return MAX_LEVEL
	return clampi(int(_d()["levels"].get(id, 1)), 1, MAX_LEVEL)


static func power(id: String) -> float:
	return POWER[level(id)] if id in POWERED else 1.0


static func max_size(id: String) -> int:
	return MAX_SIZE[level(id)]


## Yükselt: puan yeterliyse seviye artar, puan düşülür
static func upgrade(id: String) -> bool:
	var lv := level(id)
	if lv >= MAX_LEVEL or points() < COST[lv + 1]:
		return false
	_d()["points"] = points() - COST[lv + 1]
	_d()["levels"][id] = lv + 1
	_dirty = true
	save()
	return true


## Bir sonraki seviyenin açıklaması
static func next_text(id: String) -> String:
	var lv := level(id)
	if lv >= MAX_LEVEL:
		return "en üst seviye"
	var t := "%s mermi" % SIZE_NAMES[lv + 1]
	if id == "trebuchet":
		t += ", %d t karşı ağırlık" % roundi(TREBUCHET_CW[lv + 1])
	elif id in POWERED:
		t += ", +%%%d güç" % roundi((POWER[lv + 1] - 1.0) * 100.0)
	return t
