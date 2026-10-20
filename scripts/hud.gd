extends CanvasLayer
## Dokunmatik arayüz: büyük butonlar, hız ve yıkım göstergesi.

signal push_pressed
signal new_rock_pressed
signal reset_pressed
signal size_pressed
signal slowmo_toggled(on: bool)

var speed_label: Label
var destroy_label: Label
var size_button: Button
var push_button: Button
var hint_label: Label
var _slowmo := false


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
	speed_label = Label.new()
	speed_label.add_theme_font_size_override("font_size", 40)
	stats.add_child(speed_label)
	destroy_label = Label.new()
	stats.add_child(destroy_label)

	# Sağ: aksiyon butonları
	var buttons := VBoxContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_END
	buttons.size_flags_vertical = Control.SIZE_SHRINK_END
	buttons.add_theme_constant_override("separation", 14)
	margin.add_child(buttons)
	push_button = _button(buttons, "İT", func() -> void: push_pressed.emit())
	push_button.custom_minimum_size = Vector2(220, 110)
	push_button.add_theme_font_size_override("font_size", 40)
	_button(buttons, "YENİ KAYA", func() -> void: new_rock_pressed.emit())
	size_button = _button(buttons, "BOYUT: ORTA", func() -> void: size_pressed.emit())
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
	margin.add_child(hint_label)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 72)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func set_stats(speed_kmh: float, destroyed: int, total: int) -> void:
	speed_label.text = "%d km/sa" % roundi(speed_kmh)
	var pct := 0.0 if total == 0 else 100.0 * destroyed / total
	destroy_label.text = "Yıkım: %%%d  (%d/%d)" % [roundi(pct), destroyed, total]


func set_aiming(aiming: bool) -> void:
	hint_label.visible = aiming
	push_button.disabled = not aiming
	push_button.modulate.a = 1.0 if aiming else 0.4


func set_size_name(n: String) -> void:
	size_button.text = "BOYUT: " + n
