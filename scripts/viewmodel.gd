extends Node3D

@export var recoil_kick_back: float = 0.05
@export var recoil_kick_up: float = 0.09  # radians of pitch
@export var recoil_kick_side: float = 0.03  # small lateral randomness
@export var decay_speed: float = 14.0
@export var sway_amplitude_y: float = 0.004
@export var sway_amplitude_x: float = 0.003
@export var sway_speed: float = 1.6

var _base_pos: Vector3
var _base_rot: Vector3
var _recoil_pos: Vector3 = Vector3.ZERO
var _recoil_rot_x: float = 0.0
var _recoil_rot_y: float = 0.0
var _t: float = 0.0

func _ready() -> void:
	_base_pos = position
	_base_rot = rotation

func _process(delta: float) -> void:
	_t += delta
	var k = clamp(decay_speed * delta, 0.0, 1.0)
	_recoil_pos = _recoil_pos.lerp(Vector3.ZERO, k)
	_recoil_rot_x = lerp(_recoil_rot_x, 0.0, k)
	_recoil_rot_y = lerp(_recoil_rot_y, 0.0, k)

	# Subtle idle sway
	var sway = Vector3(
		sin(_t * sway_speed * 0.7) * sway_amplitude_x,
		sin(_t * sway_speed) * sway_amplitude_y,
		0.0
	)

	position = _base_pos + _recoil_pos + sway
	rotation = Vector3(
		_base_rot.x + _recoil_rot_x,
		_base_rot.y + _recoil_rot_y,
		_base_rot.z
	)

func add_recoil() -> void:
	_recoil_pos.z += recoil_kick_back
	_recoil_rot_x += recoil_kick_up
	_recoil_rot_y += randf_range(-recoil_kick_side, recoil_kick_side)
