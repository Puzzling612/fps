extends CharacterBody3D

@export var max_health: int = 100
@export var score_value: int = 100
@export var headshot_score_bonus: int = 75
@export var headshot_multiplier: float = 3.0
@export var move_speed: float = 3.5
@export var strafe_speed: float = 2.8
@export var attack_damage: int = 8
@export var attack_interval: float = 1.1
@export var attack_range: float = 28.0
@export var preferred_distance: float = 11.0
@export var min_distance: float = 6.0
@export var distance_tolerance: float = 1.5
@export var aim_spread_deg: float = 4.0
@export var strafe_change_interval_min: float = 0.9
@export var strafe_change_interval_max: float = 2.0
@export var gravity: float = 18.0
@export var hp_lerp_speed: float = 110.0

var health: int
var attack_cooldown: float = 0.0
var strafe_dir: int = 1
var strafe_timer: float = 0.0
var flash_t: float = 0.0
var _displayed_hp: float

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var hp_bar: Node3D = $HPBar
@onready var hp_sprite: Sprite3D = $HPBar/Sprite3D
@onready var hp_subviewport: SubViewport = $HPBar/SubViewport
@onready var hp_progress: ProgressBar = $HPBar/SubViewport/ProgressBar

var _flash_material: StandardMaterial3D

func _ready() -> void:
	health = max_health
	_displayed_hp = float(max_health)
	strafe_dir = 1 if randf() < 0.5 else -1
	strafe_timer = randf_range(strafe_change_interval_min, strafe_change_interval_max)

	_flash_material = StandardMaterial3D.new()
	_flash_material.albedo_color = Color(1, 1, 1, 1)
	_flash_material.emission_enabled = true
	_flash_material.emission = Color(1, 1, 1)
	_flash_material.emission_energy_multiplier = 2.0

	# Link the subviewport's texture to the sprite
	if hp_sprite and hp_subviewport:
		hp_sprite.texture = hp_subviewport.get_texture()
	if hp_progress:
		hp_progress.max_value = max_health
		hp_progress.value = max_health

func _process(delta: float) -> void:
	_orient_hp_bar()
	# Smooth HP bar shrinkage so the player can see the damage
	if hp_progress and _displayed_hp > float(health):
		_displayed_hp = max(float(health), _displayed_hp - hp_lerp_speed * delta)
		hp_progress.value = _displayed_hp

func _orient_hp_bar() -> void:
	if not hp_bar:
		return
	var cam = get_viewport().get_camera_3d()
	if not cam:
		return
	var to_cam = cam.global_position - hp_bar.global_position
	if Vector3(to_cam.x, 0, to_cam.z).length() < 0.001:
		return
	hp_bar.look_at(cam.global_position, Vector3.UP)

func _physics_process(delta: float) -> void:
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0 and mesh_instance:
			mesh_instance.material_override = null

	if attack_cooldown > 0.0:
		attack_cooldown -= delta

	var player = GameManager.player
	if not is_instance_valid(player) or GameManager.is_game_over:
		velocity.x = 0
		velocity.z = 0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var distance = to_player.length()
	var forward: Vector3 = Vector3.ZERO
	if distance > 0.001:
		forward = to_player / distance

	if forward.length() > 0.01:
		var look_target = global_position + forward
		look_at(look_target, Vector3.UP)

	var desired: Vector3 = Vector3.ZERO
	if distance > preferred_distance + distance_tolerance:
		desired = forward * move_speed
	elif distance < min_distance:
		desired = -forward * move_speed
	else:
		strafe_timer -= delta
		if strafe_timer <= 0.0:
			strafe_dir = -strafe_dir
			strafe_timer = randf_range(strafe_change_interval_min, strafe_change_interval_max)
		var right = Vector3(forward.z, 0, -forward.x)
		desired = right * strafe_speed * float(strafe_dir)

	velocity.x = desired.x
	velocity.z = desired.z

	if distance <= attack_range and attack_cooldown <= 0.0 and _has_line_of_sight(player):
		_shoot_at(player)
		attack_cooldown = attack_interval

	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()

func _has_line_of_sight(player: Node) -> bool:
	var from = global_position + Vector3(0, 1.2, 0)
	var to = player.global_position + Vector3(0, 1.0, 0)
	var space = get_world_3d().direct_space_state
	var q = PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var r = space.intersect_ray(q)
	if r.is_empty():
		return true
	return r.collider == player

func _shoot_at(player: Node) -> void:
	var from = global_position + Vector3(0, 1.2, 0)
	var target = player.global_position + Vector3(0, 1.0, 0)
	var dir = (target - from).normalized()
	var spread = deg_to_rad(aim_spread_deg)
	var basis_z = -dir
	var basis_x = Vector3.UP.cross(basis_z).normalized()
	if basis_x.length() < 0.01:
		basis_x = Vector3.RIGHT
	var basis_y = basis_z.cross(basis_x).normalized()
	var rx = randf_range(-spread, spread)
	var ry = randf_range(-spread, spread)
	var spread_dir = (-basis_z + basis_x * tan(rx) + basis_y * tan(ry)).normalized()
	var end = from + spread_dir * attack_range

	var space = get_world_3d().direct_space_state
	var q = PhysicsRayQueryParameters3D.create(from, end)
	q.exclude = [get_rid()]
	var r = space.intersect_ray(q)
	var hit_point = end
	if not r.is_empty():
		hit_point = r.position
		if r.collider == player and player.has_method("take_damage"):
			player.take_damage(attack_damage)
	GameManager.weapon_fired.emit(from, hit_point, false, false)

func take_damage(amount: int, is_headshot: bool = false) -> void:
	var actual = int(round(float(amount) * (headshot_multiplier if is_headshot else 1.0)))
	health -= actual
	flash_t = 0.08
	if mesh_instance:
		mesh_instance.material_override = _flash_material
	# Note: _displayed_hp lerps DOWN toward `health` in _process for visible animation.
	if health <= 0:
		var gained = score_value + (headshot_score_bonus if is_headshot else 0)
		GameManager.add_score(gained)
		get_tree().call_group("enemy_spawner", "_on_enemy_died")
		queue_free()
