class_name Missions
extends RefCounted
## Kuşatma görevleri (aynı kale, farklı hedefler). stars: [3 yıldız için en çok atış, 2 yıldız için]
## Görevler sırayla açılır: bir görev, öncekinden en az 1 yıldız alınınca açılır.
## Kayıt: Progress (user://kaya_save.json)

const LIST := [
	{"id": "bridge", "title": "ASMA KÖPRÜ", "goal": "Asma köprüyü indir", "limit": 6, "stars": [2, 4]},
	{"id": "gate", "title": "KAPI KULELERİ", "goal": "Okçuların durduğu iki kapı kulesini de yık", "limit": 10, "stars": [5, 8]},
	{"id": "breach", "title": "GEDİK", "goal": "Dış ön surda gedik aç (9 taş blok)", "limit": 8, "stars": [3, 5]},
	{"id": "raid", "title": "AVLU BASKINI", "goal": "Kaleden 10 kişiyi etkisiz bırak", "limit": 10, "stars": [5, 8]},
	{"id": "commander", "title": "KOMUTAN", "goal": "Ana kulenin tepesindeki komutanı indir", "limit": 12, "stars": [5, 8]},
	{"id": "flag", "title": "SANCAK", "goal": "Ana kulenin sancağını yere indir", "limit": 12, "stars": [5, 8]},
	{"id": "raze", "title": "YERLE BİR", "goal": "Kalenin %40'ını yık", "limit": 40, "stars": [20, 30]},
]


static func find(id: String) -> Dictionary:
	for m in LIST:
		if m["id"] == id:
			return m
	return {}


## Görev açık mı? (ilki her zaman; sonrakiler öncekinden yıldız alınınca)
static func unlocked(id: String, stars := {}) -> bool:
	if stars.is_empty():
		stars = load_stars()
	for i in LIST.size():
		if LIST[i]["id"] == id:
			return i == 0 or int(stars.get(LIST[i - 1]["id"], 0)) > 0
	return false


## Sıradaki görev: açık olup henüz yıldız alınmamış ilk görev; hepsi bittiyse son görev
static func current() -> String:
	var stars := load_stars()
	for m in LIST:
		if int(stars.get(m["id"], 0)) == 0:
			return m["id"]
	return LIST[-1]["id"]


static func next_of(id: String) -> String:
	for i in LIST.size() - 1:
		if LIST[i]["id"] == id:
			return LIST[i + 1]["id"]
	return ""


static func load_stars() -> Dictionary:
	return Progress.stars()


static func save_stars(id: String, stars: int) -> void:
	Progress.set_stars(id, stars)
