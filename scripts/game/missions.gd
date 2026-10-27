class_name Missions
extends RefCounted
## Kuşatma görevleri (aynı kale, farklı hedefler). stars: [3 yıldız için en çok atış, 2 yıldız için]
## Kayıt: user://kaya_save.json -> {"stars": {görev: yıldız}}

const LIST := [
	{"id": "bridge", "title": "ASMA KÖPRÜ", "goal": "Asma köprüyü indir", "limit": 6, "stars": [2, 4]},
	{"id": "gate", "title": "KAPI KULELERİ", "goal": "Dış kapının iki kulesini de yık", "limit": 10, "stars": [5, 8]},
	{"id": "breach", "title": "GEDİK", "goal": "Dış ön surda gedik aç (9 taş blok)", "limit": 8, "stars": [3, 5]},
	{"id": "raid", "title": "AVLU BASKINI", "goal": "Kaleden 10 kişiyi etkisiz bırak", "limit": 10, "stars": [5, 8]},
	{"id": "commander", "title": "KOMUTAN", "goal": "Ana kuledeki komutanı indir", "limit": 12, "stars": [5, 8]},
	{"id": "flag", "title": "SANCAK", "goal": "Ana kulenin sancağını yere indir", "limit": 12, "stars": [5, 8]},
	{"id": "raze", "title": "YERLE BİR", "goal": "Kalenin %40'ını yık", "limit": 40, "stars": [20, 30]},
]
const SAVE := "user://kaya_save.json"


static func find(id: String) -> Dictionary:
	for m in LIST:
		if m["id"] == id:
			return m
	return {}


static func next_of(id: String) -> String:
	for i in LIST.size() - 1:
		if LIST[i]["id"] == id:
			return LIST[i + 1]["id"]
	return ""


static func load_stars() -> Dictionary:
	var txt := FileAccess.get_file_as_string(SAVE)
	if txt == "":
		return {}
	var d = JSON.parse_string(txt)
	return d.get("stars", {}) if d is Dictionary else {}


static func save_stars(id: String, stars: int) -> void:
	var all := load_stars()
	all[id] = maxi(int(all.get(id, 0)), stars)
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"stars": all}))
