extends CharacterBody3D

@export var speed: float = 6.0
@export var jump_velocity: float = 4.5
@export var gravity: float = 18.0
@export var mouse_sensitivity: float = 0.18

@onready var camera_pivot: Node3D = $CameraPivot
@onready var raycast: RayCast3D = $CameraPivot/Camera/RayCast3D
var weapon: Node

func _ready() -> void:
	weapon = preload("res://scripts/weapon.gd").new()
	add_child(weapon)
	weapon.owner = self
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity * 0.01)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity * 0.01)
		camera_pivot.rotation_degrees.x = clamp(camera_pivot.rotation_degrees.x, -85.0, 85.0)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		shoot()
	elif event is InputEventKey and event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta: float) -> void:
	var input_dir = Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0,
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()

	var forward = -global_transform.basis.z
	var right = global_transform.basis.x
	var target_velocity = (right * input_dir.x + forward * input_dir.z) * speed
	velocity.x = target_velocity.x
	velocity.z = target_velocity.z

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	move_and_slide()

func shoot() -> void:
	raycast.force_raycast_update()
	var origin = raycast.global_transform.origin
	var direction = -raycast.global_transform.basis.z
	weapon.fire(origin, direction)
