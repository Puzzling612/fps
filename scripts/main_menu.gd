extends Control

const MIN_WAVE := 1
const MAX_WAVE := 20

var _selected_wave: int = 1
var _wave_label: Label
var _intel_panel: Control = null

# Enemy roster: color swatch matches the in-game tint set in enemy.gd.
const ENEMY_INTEL := [
	{
		"name": "STANDARD",
		"color": Color(0.7, 0.7, 0.72),
		"desc": "균형형. 적당한 체력·사거리로 포위해 들어온다. 웨이브 1+",
	},
	{
		"name": "RUSHER (주황)",
		"color": Color(1.0, 0.55, 0.05),
		"desc": "작고 빠르다. 체력은 약하지만 근접까지 달려들어 압박. 웨이브 2+",
	},
	{
		"name": "MARKSMAN (파랑)",
		"color": Color(0.15, 0.45, 1.0),
		"desc": "느리지만 원거리에서 정밀 저격. 한 방이 아프다 — 엄폐 필수. 웨이브 4+",
	},
	{
		"name": "GRENADIER (초록)",
		"color": Color(0.25, 0.8, 0.25),
		"desc": "수류탄을 던져 엄폐를 강제한다. 한곳에 머물지 말 것. 웨이브 6+",
	},
]

func _ready() -> void:
	# Returning from gameplay leaves the mouse captured — restore the cursor.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.custom_minimum_size = Vector2(360, 0)
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "FPS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	vbox.add_child(title)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(gap)

	# New Game button
	var new_btn := _make_button("NEW GAME", _on_new_game)
	vbox.add_child(new_btn)

	# Wave selector row
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	var left_btn := _make_button("<", _dec_wave)
	left_btn.custom_minimum_size = Vector2(50, 50)
	hbox.add_child(left_btn)

	_wave_label = Label.new()
	_wave_label.text = "WAVE 1"
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wave_label.custom_minimum_size = Vector2(200, 50)
	_wave_label.add_theme_font_size_override("font_size", 28)
	hbox.add_child(_wave_label)

	var right_btn := _make_button(">", _inc_wave)
	right_btn.custom_minimum_size = Vector2(50, 50)
	hbox.add_child(right_btn)

	# Start at selected wave button
	var start_btn := _make_button("START WAVE", _on_start)
	vbox.add_child(start_btn)

	# Enemy roster / intel
	var intel_btn := _make_button("GUIDE", _toggle_intel)
	vbox.add_child(intel_btn)

	_build_intel_panel()

# ─── Enemy intel overlay ─────────────────────────────────────
func _build_intel_panel() -> void:
	_intel_panel = Control.new()
	_intel_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intel_panel.visible = false
	add_child(_intel_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.05, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intel_panel.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intel_panel.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(620, 0)
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var header := Label.new()
	header.text = "GUIDE"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 44)
	vbox.add_child(header)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(gap)

	for e in ENEMY_INTEL:
		vbox.add_child(_make_intel_row(e))

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(gap2)

	var back_btn := _make_button("BACK", _toggle_intel)
	back_btn.custom_minimum_size = Vector2(620, 52)
	vbox.add_child(back_btn)

func _make_intel_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var swatch := ColorRect.new()
	swatch.color = e["color"]
	swatch.custom_minimum_size = Vector2(40, 40)
	row.add_child(swatch)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)

	var name_lbl := Label.new()
	name_lbl.text = e["name"]
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", e["color"])
	text.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = e["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 17)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.custom_minimum_size = Vector2(540, 0)
	text.add_child(desc_lbl)

	return row

func _toggle_intel() -> void:
	if _intel_panel:
		_intel_panel.visible = not _intel_panel.visible

func _make_button(label: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(300, 56)
	btn.pressed.connect(callback)
	return btn

func _dec_wave() -> void:
	_selected_wave = max(MIN_WAVE, _selected_wave - 1)
	_wave_label.text = "WAVE %d" % _selected_wave

func _inc_wave() -> void:
	_selected_wave = min(MAX_WAVE, _selected_wave + 1)
	_wave_label.text = "WAVE %d" % _selected_wave

func _on_new_game() -> void:
	GameManager.launch_game(1)

func _on_start() -> void:
	GameManager.launch_game(_selected_wave)
