extends CharacterBody3D

@export var speed: float = 6.0
@export var sprint_multiplier: float = 1.7
@export var jump_velocity: float = 7.2
@export var gravity: float = 18.0
@export var mouse_sensitivity: float = 0.18
@export var max_health: int = 100
@export var fov_default: float = 75.0
@export var fov_sprint: float = 86.0
@export var fov_lerp_speed: float = 8.0
@export var ladder_climb_speed: float = 4.5
@export var crouch_speed_multiplier: float = 0.45
@export var crouch_camera_offset: float = -0.5

var _ladder_count: int = 0   # how many ladder areas the player is touching
var on_ladder: bool:
	get: return _ladder_count > 0

func enter_ladder() -> void:
	_ladder_count += 1
func exit_ladder() -> void:
	_ladder_count = max(0, _ladder_count - 1)

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera
@onready var raycast: RayCast3D = $CameraPivot/Camera/RayCast3D
@onready var muzzle_point: Node3D = $CameraPivot/Camera/MuzzlePoint
@onready var muzzle_flash: OmniLight3D = $CameraPivot/Camera/MuzzlePoint/MuzzleLight
@onready var viewmodel: Node3D = $CameraPivot/Camera/Viewmodel

const TRACER_SCENE: PackedScene = preload("res://scenes/Tracer.tscn")

var weapon: Node
var current_health: int
var _muzzle_t: float = 0.0
var is_crouching: bool = false
var _crouch_camera_y: float = 0.0

# Screen shake state
var _shake_strength: float = 0.0
var _shake_duration: float = 0.0
var _shake_max_duration: float = 0.0
var _camera_base_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	current_health = max_health
	GameManager.register_player(self)
	GameManager.player_health_changed.emit(current_health, max_health)
	GameManager.weapon_fired.connect(_on_any_weapon_fired)

	weapon = preload("res://scripts/weapon.gd").new()
	add_child(weapon)
	weapon.owner = self

	if muzzle_flash:
		muzzle_flash.visible = false
	if camera:
		_camera_base_pos = camera.position
		_crouch_camera_y = camera_pivot.position.y
		camera.fov = fov_default

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity * 0.01)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity * 0.01)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _process(delta: float) -> void:
	if _muzzle_t > 0.0:
		_muzzle_t -= delta
		if _muzzle_t <= 0.0 and muzzle_flash:
			muzzle_flash.visible = false

	# Screen shake (position-only so it doesn't break aiming)
	if _shake_duration > 0.0 and camera:
		_shake_duration -= delta
		var k = clamp(_shake_duration / _shake_max_duration, 0.0, 1.0)
		var amt = _shake_strength * k
		camera.position = _camera_base_pos + Vector3(
			randf_range(-amt, amt),
			randf_range(-amt, amt),
			0.0
		)
		if _shake_duration <= 0.0:
			_shake_duration = 0.0
			_shake_strength = 0.0
			camera.position = _camera_base_pos

func _physics_process(delta: float) -> void:
	var input_dir = Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0,
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	)
	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()

	is_crouching = Input.is_action_pressed("crouch") and is_on_floor()
	var target_pivot_y = _crouch_camera_y + (crouch_camera_offset if is_crouching else 0.0)
	camera_pivot.position.y = lerp(camera_pivot.position.y, target_pivot_y, 0.2)

	var sprinting = Input.is_action_pressed("sprint") and input_dir.z > 0.4 and not is_crouching
	var speed_mul = crouch_speed_multiplier if is_crouching else (sprint_multiplier if sprinting else 1.0)
	var current_speed = speed * speed_mul

	if camera:
		var target_fov = fov_sprint if sprinting else fov_default
		camera.fov = lerp(camera.fov, target_fov, clamp(fov_lerp_speed * delta, 0.0, 1.0))

	var forward = -global_transform.basis.z
	var right = global_transform.basis.x
	var target_velocity = (right * input_dir.x + forward * input_dir.z) * current_speed
	velocity.x = target_velocity.x
	velocity.z = target_velocity.z

	if on_ladder:
		# Ladder climb: hold space to go up, release to cling (no gravity).
		# Walking off the ladder area drops the player normally.
		if Input.is_action_pressed("jump"):
			velocity.y = ladder_climb_speed
		else:
			velocity.y = 0.0
	elif not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	move_and_slide()

	if Input.is_action_pressed("shoot") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var origin = raycast.global_transform.origin
		var direction = -raycast.global_transform.basis.z
		weapon.try_fire(origin, direction)

	if Input.is_action_just_pressed("reload"):
		weapon.start_reload()

func _on_any_weapon_fired(from: Vector3, to: Vector3, _hit_enemy: bool, is_headshot: bool) -> void:
	var dist_from_camera = (from - raycast.global_transform.origin).length()
	if dist_from_camera > 0.5:
		# Enemy shot — tracer only.
		_spawn_tracer(from, to)
		return
	# Player shot
	var visual_origin = muzzle_point.global_transform.origin if muzzle_point else from
	_spawn_tracer(visual_origin, to)
	if muzzle_flash:
		muzzle_flash.visible = true
		_muzzle_t = 0.04
	if viewmodel and viewmodel.has_method("add_recoil"):
		viewmodel.add_recoil()
	if is_headshot:
		add_screen_shake(0.07, 0.22)

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var t = TRACER_SCENE.instantiate()
	get_tree().current_scene.add_child(t)
	t.setup(from, to)

func add_screen_shake(strength: float, duration: float) -> void:
	if duration > _shake_duration:
		_shake_duration = duration
		_shake_max_duration = max(duration, 0.001)
	if strength > _shake_strength:
		_shake_strength = strength

func take_damage(amount: int) -> void:
	if GameManager.is_game_over:
		return
	current_health = max(0, current_health - amount)
	GameManager.player_health_changed.emit(current_health, max_health)
	GameManager.player_damaged.emit(amount)
	if current_health <= 0:
		GameManager.game_over()

func heal(amount: int) -> void:
	if GameManager.is_game_over:
		return
	if current_health >= max_health:
		return
	current_health = min(max_health, current_health + amount)
	GameManager.player_health_changed.emit(current_health, max_health)
