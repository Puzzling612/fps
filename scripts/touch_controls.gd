# touch_controls.gd — self-contained on-screen controls for touch devices.
#
# Design contract (so this never blocks future gameplay edits):
#  • On NON-touch devices it disables itself in _ready() and does nothing.
#  • It only ever drives the EXISTING input action map (move_*, shoot, aim, jump,
#    reload, throw_grenade, melee, weapon_next, crouch, sprint) via
#    Input.action_press/release, plus player.apply_look() for the view. So any
#    future change to movement/weapons works on mobile automatically as long as
#    the action names stay — no edits to this file required.
#
# Left side  = floating analog move stick. Right side drag = look. Buttons = the
# rest. Fully multi-touch (each finger tracked by its index).
extends CanvasLayer

@export var look_sensitivity: float = 1.0   # multiplies the look drag delta
@export var move_radius: float = 120.0       # stick travel in px before full tilt
@export var ui_alpha: float = 0.30

var _fingers: Dictionary = {}     # finger index -> role ("move" | "look" | button dict)
var _move_active: bool = false
var _joy_origin: Vector2 = Vector2.ZERO
var _look_last: Vector2 = Vector2.ZERO

var _joy_base: Panel = null
var _joy_knob: Panel = null
var _buttons: Array = []          # each: {action, label, mode, state, panel, rect}

func _ready() -> void:
	layer = 3                      # above the HUD
	process_mode = Node.PROCESS_MODE_ALWAYS   # respond to the restart tap while paused
	if not GameManager.touch_mode:
		hide()
		set_process_input(false)
		return
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_layout()

# ─── UI construction ─────────────────────────────────────────
func _round_panel(diam: float, color: Color) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(diam, diam)
	p.size = Vector2(diam, diam)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE   # input is hit-tested manually
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(diam * 0.5))
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, ui_alpha)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _build_ui() -> void:
	_joy_base = _round_panel(move_radius * 2.0, Color(1, 1, 1, ui_alpha * 0.5))
	_joy_base.visible = false
	add_child(_joy_base)
	_joy_knob = _round_panel(move_radius * 0.9, Color(1, 1, 1, ui_alpha))
	_joy_knob.visible = false
	add_child(_joy_knob)

	# id/action/label/mode. mode: hold | toggle | momentary
	var defs := [
		{"action": "shoot", "label": "FIRE", "mode": "hold", "diam": 150.0},
		{"action": "aim", "label": "ADS", "mode": "toggle", "diam": 96.0},
		{"action": "jump", "label": "JMP", "mode": "momentary", "diam": 96.0},
		{"action": "reload", "label": "RLD", "mode": "momentary", "diam": 96.0},
		{"action": "throw_grenade", "label": "NADE", "mode": "momentary", "diam": 96.0},
		{"action": "melee", "label": "MLE", "mode": "momentary", "diam": 96.0},
		{"action": "weapon_next", "label": "WPN", "mode": "momentary", "diam": 96.0},
		{"action": "crouch", "label": "CRO", "mode": "toggle", "diam": 96.0},
	]
	for d in defs:
		var panel := _round_panel(d.diam, Color(0.1, 0.1, 0.12, ui_alpha + 0.15))
		add_child(panel)
		var lbl := Label.new()
		lbl.text = d.label
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(lbl)
		_buttons.append({
			"action": d.action, "label": d.label, "mode": d.mode,
			"state": false, "panel": panel, "diam": d.diam, "rect": Rect2(),
		})

# Position everything for the current screen size (bottom-right cluster + fire).
func _layout() -> void:
	var s: Vector2 = get_viewport().get_visible_rect().size
	# Bottom-right anchored centres for each button (by action).
	var centres := {
		"shoot": Vector2(s.x - 130, s.y - 130),
		"aim": Vector2(s.x - 270, s.y - 150),
		"jump": Vector2(s.x - 130, s.y - 290),
		"reload": Vector2(s.x - 265, s.y - 300),
		"throw_grenade": Vector2(s.x - 395, s.y - 150),
		"melee": Vector2(s.x - 390, s.y - 285),
		"weapon_next": Vector2(s.x - 150, s.y - 440),
		"crouch": Vector2(s.x - 320, s.y - 430),
	}
	for b in _buttons:
		var c: Vector2 = centres.get(b.action, Vector2(s.x * 0.5, s.y * 0.5))
		var diam: float = b.diam
		b.panel.position = c - Vector2(diam, diam) * 0.5
		b.rect = Rect2(b.panel.position, Vector2(diam, diam))

# ─── Touch handling ──────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position, event.relative)
		get_viewport().set_input_as_handled()

func _on_press(index: int, pos: Vector2) -> void:
	# On the end screens, any tap returns to the menu (mirrors ui_accept).
	if GameManager.is_game_over or GameManager.is_won:
		GameManager.restart_game()
		return
	# Buttons first.
	for b in _buttons:
		if b.rect.has_point(pos):
			_fingers[index] = b
			_press_button(b)
			return
	# Left ~45% → move stick (floating). Right side → look.
	var s: Vector2 = get_viewport().get_visible_rect().size
	if pos.x < s.x * 0.45:
		_fingers[index] = "move"
		_move_active = true
		_joy_origin = pos
		_joy_base.position = pos - _joy_base.size * 0.5
		_joy_base.visible = true
		_update_knob(pos)
	else:
		_fingers[index] = "look"
		_look_last = pos

func _on_drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var role = _fingers.get(index, null)
	if role == "move":
		_apply_move(pos)
		_update_knob(pos)
	elif role == "look":
		var player = GameManager.player
		if is_instance_valid(player) and player.has_method("apply_look"):
			player.apply_look(relative * look_sensitivity)
		_look_last = pos

func _on_release(index: int) -> void:
	var role = _fingers.get(index, null)
	if role == "move":
		_clear_move()
	elif typeof(role) == TYPE_DICTIONARY:
		_release_button(role)
	_fingers.erase(index)

# ─── Movement stick ──────────────────────────────────────────
func _apply_move(pos: Vector2) -> void:
	var v: Vector2 = (pos - _joy_origin) / move_radius
	if v.length() > 1.0:
		v = v.normalized()
	# x = strafe (right positive), y = forward (up/-y on screen = forward)
	_set_axis("move_right", "move_left", v.x)
	_set_axis("move_back", "move_forward", v.y)   # screen +y is down → back
	# Full-forward push auto-sprints.
	if v.length() > 0.9 and v.y < -0.4:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")

func _set_axis(pos_action: String, neg_action: String, value: float) -> void:
	if value > 0.05:
		Input.action_press(pos_action, value)
		Input.action_release(neg_action)
	elif value < -0.05:
		Input.action_press(neg_action, -value)
		Input.action_release(pos_action)
	else:
		Input.action_release(pos_action)
		Input.action_release(neg_action)

func _clear_move() -> void:
	_move_active = false
	for a in ["move_right", "move_left", "move_forward", "move_back", "sprint"]:
		Input.action_release(a)
	_joy_base.visible = false
	_joy_knob.visible = false

func _update_knob(pos: Vector2) -> void:
	var off: Vector2 = pos - _joy_origin
	if off.length() > move_radius:
		off = off.normalized() * move_radius
	_joy_knob.position = (_joy_origin + off) - _joy_knob.size * 0.5
	_joy_knob.visible = true

# ─── Buttons ─────────────────────────────────────────────────
func _press_button(b: Dictionary) -> void:
	match b.mode:
		"toggle":
			b.state = not b.state
			if b.state:
				Input.action_press(b.action)
			else:
				Input.action_release(b.action)
			_set_button_lit(b, b.state)
		_:
			Input.action_press(b.action)
			_set_button_lit(b, true)

func _release_button(b: Dictionary) -> void:
	if b.mode == "toggle":
		return   # toggles latch until pressed again
	Input.action_release(b.action)
	_set_button_lit(b, false)

func _set_button_lit(b: Dictionary, on: bool) -> void:
	var sb := b.panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.bg_color = Color(0.9, 0.7, 0.2, 0.6) if on else Color(0.1, 0.1, 0.12, ui_alpha + 0.15)
