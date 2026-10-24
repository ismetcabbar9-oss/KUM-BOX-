extends CanvasLayer
## Dokunmatik arayüz: büyük butonlar, hız ve yıkım göstergesi.

signal fire_pressed
signal launcher_pressed
signal ammo_pressed
signal reset_pressed
signal size_pressed
signal slowmo_toggled(on: bool)
signal quality_pressed
signal map_pressed
signal option_pressed
signal mission_selected(id: String)
signal result_action(action: String)

var speed_label: Label
var destroy_label: Label
var size_button: Button
var fire_button: Button
var launcher_button: Button
var ammo_button: Button
var option_button: Button
var info_label: Label
var hint_label: Label
var fps_label: Label
var quality_button: Button
var map_button: Button
var credits_panel: PanelContainer
var missions_panel: PanelContainer
var result_panel: PanelContainer
var mission_label: Label
var _missions_list: VBoxContainer
var _root: Control
var _slowmo := false
var buttons: GridContainer
var hint_box: MarginContainer
var portrait := false
var _stats_spacer: Control


func _ready() -> void:
	var theme := Theme.new()
	theme.default_font_size = 26
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.09, 0.1, 0.62)
	normal.border_color = Color(1, 1, 1, 0.18)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(14)
	normal.set_content_margin_all(18)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.85, 0.55, 0.2, 0.8)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", normal)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", Color(0.95, 0.94, 0.9))
	theme.set_color("font_color", "Label", Color(0.97, 0.96, 0.92))
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	theme.set_constant("outline_size", "Label", 6)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	root.add_child(margin)

	# Sol üst: göstergeler
	var stats := VBoxContainer.new()
	stats.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stats.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(stats)
	_stats_spacer = Control.new()
	_stats_spacer.custom_minimum_size = Vector2(0, 70)
	_stats_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(_stats_spacer)
	speed_label = Label.new()
	speed_label.add_theme_font_size_override("font_size", 40)
	stats.add_child(speed_label)
	destroy_label = Label.new()
	stats.add_child(destroy_label)
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 24)
	info_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	stats.add_child(info_label)
	fps_label = Label.new()
	fps_label.add_theme_font_size_override("font_size", 18)
	stats.add_child(fps_label)

	# Sağ üst: grafik kalitesi + lisanslar
	var top := HBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_SHRINK_END
	top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_theme_constant_override("separation", 10)
	margin.add_child(top)
	var mis := _button(top, "GÖREVLER", func() -> void: missions_panel.visible = not missions_panel.visible)
	mis.custom_minimum_size = Vector2(170, 56)
	mis.add_theme_font_size_override("font_size", 20)
	map_button = _button(top, "HARİTA", func() -> void: map_pressed.emit())
	map_button.custom_minimum_size = Vector2(190, 56)
	map_button.add_theme_font_size_override("font_size", 20)
	quality_button = _button(top, "GRAFİK: ORTA", func() -> void: quality_pressed.emit())
	quality_button.custom_minimum_size = Vector2(200, 56)
	quality_button.add_theme_font_size_override("font_size", 20)
	var lic := _button(top, "LİSANSLAR", func() -> void: credits_panel.visible = not credits_panel.visible)
	lic.custom_minimum_size = Vector2(150, 56)
	lic.add_theme_font_size_override("font_size", 20)

	# Sağ: aksiyon butonları
	buttons = GridContainer.new()
	buttons.columns = 1
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_END
	buttons.size_flags_vertical = Control.SIZE_SHRINK_END
	buttons.add_theme_constant_override("h_separation", 10)
	buttons.add_theme_constant_override("v_separation", 10)
	margin.add_child(buttons)
	fire_button = _button(buttons, "FIRLAT", func() -> void: fire_pressed.emit())
	fire_button.custom_minimum_size = Vector2(250, 104)
	fire_button.add_theme_font_size_override("font_size", 38)
	launcher_button = _button(buttons, "RAMPA", func() -> void: launcher_pressed.emit())
	option_button = _button(buttons, "AYAR", func() -> void: option_pressed.emit())
	ammo_button = _button(buttons, "GRANİT", func() -> void: ammo_pressed.emit())
	size_button = _button(buttons, "ORTA", func() -> void: size_pressed.emit())
	var slow := _button(buttons, "AĞIR ÇEKİM", func() -> void: pass)
	slow.toggle_mode = true
	slow.toggled.connect(func(on: bool) -> void: slowmo_toggled.emit(on))
	_button(buttons, "SIFIRLA", func() -> void: reset_pressed.emit())

	# Alt orta: ipucu
	hint_label = Label.new()
	hint_label.text = "Sağa-sola sürükle: nişan al   •   Yukarı kaydır ya da İT: fırlat"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hint_label.size_flags_vertical = Control.SIZE_SHRINK_END
	hint_label.add_theme_font_size_override("font_size", 24)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_box = MarginContainer.new()
	hint_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_box.add_child(hint_label)
	margin.add_child(hint_box)
	get_viewport().size_changed.connect(_relayout)
	_relayout()

	_root = root
	# Görev metni: üst orta
	mission_label = Label.new()
	mission_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	mission_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mission_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mission_label.offset_top = 100
	mission_label.add_theme_font_size_override("font_size", 24)
	mission_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	mission_label.visible = false
	root.add_child(mission_label)
	missions_panel = _panel(root)
	result_panel = _panel(root)
	_build_missions_panel()

	# Lisans paneli (CC-BY atıfları oyunda gösterilmeli)
	credits_panel = PanelContainer.new()
	credits_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	credits_panel.offset_left = 80
	credits_panel.offset_right = -80
	credits_panel.offset_top = 60
	credits_panel.offset_bottom = -60
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.06, 0.92)
	bg.set_corner_radius_all(16)
	bg.set_content_margin_all(24)
	credits_panel.add_theme_stylebox_override("panel", bg)
	credits_panel.visible = false
	root.add_child(credits_panel)
	var text := RichTextLabel.new()
	text.bbcode_enabled = false
	text.add_theme_font_size_override("normal_font_size", 18)
	text.text = _credits_text()
	text.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventScreenTouch and e.pressed and e.double_tap:
			credits_panel.visible = false)
	credits_panel.add_child(text)
	var close := _button(credits_panel, "KAPAT", func() -> void: credits_panel.visible = false)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.size_flags_vertical = Control.SIZE_SHRINK_END


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(250, 62)
	b.add_theme_font_size_override("font_size", 22)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	b.add_to_group("hud_button")
	parent.add_child(b)
	return b


func set_stats(speed_kmh: float, destroyed: int, total: int) -> void:
	speed_label.text = "%d km/sa" % roundi(speed_kmh)
	var pct := 0.0 if total == 0 else 100.0 * destroyed / total
	destroy_label.text = "Yıkım: %%%d  (%d/%d)" % [roundi(pct), destroyed, total]


## Dikey ekranda butonlar altta 3 sütunlu ızgara, ipucu üstte; yatayda sağda tek sütun.
func _relayout() -> void:
	# Yönlendirmeye göre temel çözünürlük: arayüz her iki yönde de aynı fiziksel boyutta
	var win := get_window()
	var real := win.size
	portrait = real.y > real.x
	var base := Vector2i(720, 1280) if portrait else Vector2i(1280, 720)
	if win.content_scale_size != base:
		win.content_scale_size = base
		return  # boyut değişimi bu fonksiyonu yeniden çağırır
	var vs := get_viewport().get_visible_rect().size
	buttons.columns = 3 if portrait else 1
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if portrait else Control.SIZE_SHRINK_END
	var w := (vs.x - 56.0 - 20.0) / 3.0 if portrait else 250.0
	for b: Button in buttons.get_children():
		b.custom_minimum_size = Vector2(w, 84.0 if b == fire_button else 66.0) if portrait else Vector2(250, 104.0 if b == fire_button else 62.0)
	hint_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if portrait else Control.SIZE_SHRINK_END
	hint_label.custom_minimum_size.x = minf(vs.x - 80.0, 900.0)
	hint_box.add_theme_constant_override("margin_top", 290 if portrait else 0)
	_stats_spacer.visible = portrait


func set_fps(fps: int, extra: String) -> void:
	fps_label.text = "%d FPS  %s" % [fps, extra]


func set_map_name(n: String) -> void:
	map_button.text = n
	map_button.visible = false  # tek harita: buton gereksiz (dikey ekranda yer açar)


func set_quality_name(n: String) -> void:
	quality_button.text = "GRAFİK: " + n


func is_over_ui(pos: Vector2) -> bool:
	if credits_panel.visible or missions_panel.visible or result_panel.visible:
		return true
	for b in get_tree().get_nodes_in_group("hud_button"):
		if (b as Control).get_global_rect().has_point(pos):
			return true
	return false


func _credits_text() -> String:
	var out := "KAYA YUVARLA — Lisanslar\n\n"
	for path in ["res://assets/models/CREDITS_MODELS.md", "res://assets/sounds/CREDITS_SOUNDS.md"]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			out += f.get_as_text().replace("# ", "").replace("**", "").replace("`", "") + "\n"
	out += "Dokular ve gökyüzü: Poly Haven (CC0).\nMotor: Godot Engine (MIT), Jolt Physics (MIT).\n"
	return out


func set_ready(ready: bool, hint: String, button_active := true) -> void:
	fire_button.text = ("FIRLAT" if button_active else "ÇEK-BIRAK") if ready else "YÜKLE"
	fire_button.disabled = ready and not button_active
	hint_label.text = hint
	hint_label.visible = ready and hint != ""


## Fırlatma sonrası ikinci işlev (ör. vinç zinciri): buton KES olur
func set_flight(hint: String) -> void:
	fire_button.text = "KES"
	fire_button.disabled = false
	hint_label.text = hint
	hint_label.visible = true


func set_info(text: String) -> void:
	info_label.text = text


func set_option(text: String) -> void:
	option_button.text = text
	option_button.visible = text != ""


func set_launcher_name(n: String) -> void:
	launcher_button.text = n


func set_ammo_name(n: String) -> void:
	ammo_button.text = n


func set_size_name(n: String) -> void:
	size_button.text = "BOYUT: " + n


func _panel(root: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.06, 0.93)
	bg.border_color = Color(1.0, 0.8, 0.4, 0.5)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(18)
	bg.set_content_margin_all(26)
	p.add_theme_stylebox_override("panel", bg)
	p.visible = false
	root.add_child(p)
	return p


func _title(parent: Control, text: String, size := 34) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


## Görev listesi: her görev bir buton (kazanılmış yıldızlarla) + serbest oyun
func _build_missions_panel() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	missions_panel.add_child(box)
	_title(box, "KUŞATMA GÖREVLERİ")
	_missions_list = VBoxContainer.new()
	_missions_list.add_theme_constant_override("separation", 8)
	box.add_child(_missions_list)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_button(row, "SERBEST OYUN", func() -> void: mission_selected.emit(""))
	_button(row, "KAPAT", func() -> void: missions_panel.visible = false)
	refresh_missions()


func refresh_missions() -> void:
	for c in _missions_list.get_children():
		c.queue_free()
	var stars := Missions.load_stars()
	for m in Missions.LIST:
		var st := int(stars.get(m["id"], 0))
		var txt := "%s   %s   (en çok %d atış)" % ["★".repeat(st) + "☆".repeat(3 - st), m["title"], m["limit"]]
		var b := _button(_missions_list, txt, func() -> void: mission_selected.emit(m["id"]))
		b.custom_minimum_size = Vector2(620, 60)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = m["goal"]


func set_mission_text(t: String) -> void:
	mission_label.text = t
	mission_label.visible = t != ""


## Görev sonucu: yıldızlar + tekrar / sonraki / serbest
func show_result(m: Dictionary, success: bool, stars: int, shots: int) -> void:
	for c in result_panel.get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	result_panel.add_child(box)
	_title(box, ("GÖREV BAŞARILI" if success else "GÖREV BAŞARISIZ"), 40)
	_title(box, m["title"] + " — " + m["goal"], 24)
	if success:
		var st := _title(box, "★".repeat(stars) + "☆".repeat(3 - stars), 72)
		st.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
		_title(box, "%d atışta" % shots, 26)
	else:
		_title(box, "Atış hakkın bitti", 26)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	_button(row, "TEKRAR", func() -> void: result_action.emit("retry"))
	if success and Missions.next_of(m["id"]) != "":
		_button(row, "SONRAKİ GÖREV", func() -> void: result_action.emit("next"))
	_button(row, "SERBEST OYUN", func() -> void: result_action.emit("free"))
	result_panel.visible = true
