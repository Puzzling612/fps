extends CharacterBody3D

# ─── Tunables ────────────────────────────────────────────────
@export var max_health: int = 100
@export var score_value: int = 100
@export var headshot_score_bonus: int = 75
@export var headshot_multiplier: float = 3.0
@export var move_speed: float = 3.8
@export var sprint_speed: float = 5.4               # flanking / objective dash
@export var strafe_speed: float = 3.0
@export var attack_damage: int = 8
@export var attack_interval: float = 0.95
@export var attack_range: float = 28.0
@export var preferred_distance: float = 11.0
@export var min_distance: float = 6.0
@export var distance_tolerance: float = 1.5
@export var aim_spread_deg: float = 4.0
@export var strafe_change_interval_min: float = 0.8
@export var strafe_change_interval_max: float = 1.8
@export var jump_velocity: float = 6.5
@export var gravity: float = 18.0
@export var hp_lerp_speed: float = 110.0
@export var slot_reach_distance: float = 2.5
@export var evade_duration: float = 0.55
@export var jump_cooldown: float = 0.6
@export var ladder_climb_speed: float = 4.5

# ─── State machine ───────────────────────────────────────────
enum State { APPROACH, ENGAGE, EVADE, GOTO_OBJECTIVE }
var state: State = State.APPROACH

var health: int
var attack_cooldown: float = 0.0
var strafe_dir: int = 1
var strafe_timer: float = 0.0
var flash_t: float = 0.0
var _displayed_hp: float
var jump_timer: float = 0.0
var evade_timer: float = 0.0
var evade_dir: int = 1

# Director-assigned data
const NO_TARGET := Vector3(1.0e30, 0.0, 0.0)
var slot_position: Vector3 = NO_TARGET
var objective_position: Vector3 = NO_TARGET
var has_objective: bool = false
var role: String = "encircle"   # encircle | flank | objective

# Ladder state (set by ladder.gd via enter/exit_ladder)
var _ladder_count: int = 0
var on_ladder: bool:
	get: return _ladder_count > 0

func enter_ladder() -> void:
	_ladder_count += 1
func exit_ladder() -> void:
	_ladder_count = max(0, _ladder_count - 1)
	# Reaching the top of the ladder consumes the objective.
	if _ladder_count == 0 and has_objective:
		has_objective = false

@onready var model: Node3D = $Model
@onready var hp_bar: Node3D = $HPBar
@onready var hp_sprite: Sprite3D = $HPBar/Sprite3D
@onready var hp_subviewport: SubViewport = $HPBar/SubViewport
@onready var hp_progress: ProgressBar = $HPBar/SubViewport/ProgressBar

var _flash_material: StandardMaterial3D
var _model_meshes: Array[MeshInstance3D] = []

# ─── Setup ───────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	_displayed_hp = float(max_health)
	strafe_dir = 1 if randf() < 0.5 else -1
	strafe_timer = randf_range(strafe_change_interval_min, strafe_change_interval_max)

	_flash_material = StandardMaterial3D.new()
	_flash_material.albedo_color = Color(1, 1, 1, 1)
	_flash_material.emission_enabled = true
	_flash_material.emission = Color(1, 1, 1)
	_flash_material.emission_energy_multiplier = 2.0

	if model:
		_collect_meshes(model)

	if hp_sprite and hp_subviewport:
		hp_sprite.texture = hp_subviewport.get_texture()
	if hp_progress:
		hp_progress.max_value = max_health
		hp_progress.value = max_health

func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		_model_meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child)

func _apply_flash(on: bool) -> void:
	for mi in _model_meshes:
		mi.material_override = _flash_material if on else null

# ─── Director API ────────────────────────────────────────────
func assign_slot(pos: Vector3, new_role: String) -> void:
	slot_position = pos
	role = new_role

func assign_objective(pos: Vector3) -> void:
	objective_position = pos
	has_objective = true
	role = "objective"

func clear_objective() -> void:
	has_objective = false

# ─── Process ─────────────────────────────────────────────────
func _process(delta: float) -> void:
	_orient_hp_bar()
	if hp_progress and _displayed_hp > float(health):
		_displayed_hp = max(float(health), _displayed_hp - hp_lerp_speed * delta)
		hp_progress.value = _displayed_hp

func _orient_hp_bar() -> void:
	if not hp_bar: return
	var cam = get_viewport().get_camera_3d()
	if not cam: return
	var to_cam = cam.global_position - hp_bar.global_position
	if Vector3(to_cam.x, 0, to_cam.z).length() < 0.001: return
	hp_bar.look_at(cam.global_position, Vector3.UP)

func _physics_process(delta: float) -> void:
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0:
			_apply_flash(false)
	if attack_cooldown > 0.0: attack_cooldown -= delta
	if jump_timer > 0.0:     jump_timer -= delta
	if evade_timer > 0.0:    evade_timer -= delta

	var player = GameManager.player
	if not is_instance_valid(player) or GameManager.is_game_over:
		velocity.x = 0; velocity.z = 0
		if not is_on_floor(): velocity.y -= gravity * delta
		move_and_slide()
		return

	_update_state(player)

	var to_player: Vector3 = (player as Node3D).global_position - global_position
	to_player.y = 0
	var distance_p: float = to_player.length()
	var forward_to_player: Vector3 = to_player.normalized() if distance_p > 0.001 else -global_transform.basis.z

	# Always face the player (yaw only)
	if forward_to_player.length() > 0.01:
		look_at(global_position + Vector3(forward_to_player.x, 0, forward_to_player.z), Vector3.UP)

	var desired: Vector3 = _compute_desired_movement(forward_to_player, distance_p, delta)
	velocity.x = desired.x
	velocity.z = desired.z

	# Attack while engaging
	if state == State.ENGAGE and attack_cooldown <= 0.0 and distance_p <= attack_range:
		if _has_line_of_sight(player):
			_shoot_at(player)
			attack_cooldown = attack_interval

	# Try to jump over short obstacles while moving
	if jump_timer <= 0.0 and is_on_floor() and Vector2(desired.x, desired.z).length() > 0.5:
		if _should_jump():
			velocity.y = jump_velocity
			jump_timer = jump_cooldown

	# Vertical motion
	if on_ladder:
		# Climb the ladder until we reach the top
		velocity.y = ladder_climb_speed
	elif not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()

# ─── State logic ─────────────────────────────────────────────
func _update_state(player: Node) -> void:
	if evade_timer > 0.0:
		state = State.EVADE
		return
	if has_objective:
		state = State.GOTO_OBJECTIVE
		return
	# Decide between APPROACH and ENGAGE based on slot proximity + LoS
	var distance_p: float = ((player as Node3D).global_position - global_position).length()
	var at_slot := slot_position != NO_TARGET and \
		Vector2(slot_position.x - global_position.x, slot_position.z - global_position.z).length() < slot_reach_distance
	if at_slot and distance_p <= attack_range and _has_line_of_sight(player):
		state = State.ENGAGE
	else:
		state = State.APPROACH

func _compute_desired_movement(forward_to_player: Vector3, distance_p: float, delta: float) -> Vector3:
	match state:
		State.EVADE:
			var right := Vector3(forward_to_player.z, 0, -forward_to_player.x)
			return right * sprint_speed * float(evade_dir)
		State.GOTO_OBJECTIVE:
			var to_obj := objective_position - global_position
			to_obj.y = 0
			if to_obj.length() < 0.5:
				return Vector3.ZERO
			return to_obj.normalized() * sprint_speed
		State.APPROACH:
			if slot_position != NO_TARGET:
				var to_slot := slot_position - global_position
				to_slot.y = 0
				if to_slot.length() > 0.1:
					var spd: float = sprint_speed if role == "flank" else move_speed
					return to_slot.normalized() * spd
			return forward_to_player * move_speed
		State.ENGAGE:
			strafe_timer -= delta
			if strafe_timer <= 0.0:
				strafe_dir = -strafe_dir
				strafe_timer = randf_range(strafe_change_interval_min, strafe_change_interval_max)
			var right2 := Vector3(forward_to_player.z, 0, -forward_to_player.x)
			var radial: Vector3 = Vector3.ZERO
			if distance_p > preferred_distance + distance_tolerance:
				radial = forward_to_player * (move_speed * 0.5)
			elif distance_p < min_distance:
				radial = -forward_to_player * (move_speed * 0.5)
			return right2 * strafe_speed * float(strafe_dir) + radial
	return Vector3.ZERO

# ─── Movement helpers ────────────────────────────────────────
func _should_jump() -> bool:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001: return false
	forward = forward.normalized()
	var space := get_world_3d().direct_space_state

	# Wall in front at knee height?
	var low_from := global_position + Vector3(0, 0.3, 0)
	var low_to := low_from + forward * 1.0
	var q1 := PhysicsRayQueryParameters3D.create(low_from, low_to)
	q1.exclude = [get_rid()]
	if space.intersect_ray(q1).is_empty():
		return false
	# Top must be reachable (no wall higher than ~1.5m)
	var high_from := global_position + Vector3(0, 1.75, 0)
	var high_to := high_from + forward * 1.0
	var q2 := PhysicsRayQueryParameters3D.create(high_from, high_to)
	q2.exclude = [get_rid()]
	if not space.intersect_ray(q2).is_empty():
		return false
	return true

# ─── Combat ──────────────────────────────────────────────────
func _has_line_of_sight(player: Node) -> bool:
	var from: Vector3 = global_position + Vector3(0, 1.2, 0)
	var to: Vector3 = (player as Node3D).global_position + Vector3(0, 1.0, 0)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var r := space.intersect_ray(q)
	if r.is_empty(): return true
	return r.collider == player

func _shoot_at(player: Node) -> void:
	var from: Vector3 = global_position + Vector3(0, 1.2, 0)
	var target: Vector3 = (player as Node3D).global_position + Vector3(0, 1.0, 0)
	var dir: Vector3 = (target - from).normalized()
	var spread: float = deg_to_rad(aim_spread_deg)
	var basis_z: Vector3 = -dir
	var basis_x: Vector3 = Vector3.UP.cross(basis_z).normalized()
	if basis_x.length() < 0.01: basis_x = Vector3.RIGHT
	var basis_y: Vector3 = basis_z.cross(basis_x).normalized()
	var rx: float = randf_range(-spread, spread)
	var ry: float = randf_range(-spread, spread)
	var spread_dir: Vector3 = (-basis_z + basis_x * tan(rx) + basis_y * tan(ry)).normalized()
	var end: Vector3 = from + spread_dir * attack_range
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, end)
	q.exclude = [get_rid()]
	var r := space.intersect_ray(q)
	var hit_point: Vector3 = end
	if not r.is_empty():
		hit_point = r.position
		if r.collider == player and player.has_method("take_damage"):
			player.take_damage(attack_damage)
	GameManager.weapon_fired.emit(from, hit_point, false, false)

func take_damage(amount: int, is_headshot: bool = false) -> void:
	var actual = int(round(float(amount) * (headshot_multiplier if is_headshot else 1.0)))
	health -= actual
	flash_t = 0.08
	_apply_flash(true)
	# Trigger evasion sidestep
	if evade_timer <= 0.0:
		evade_timer = evade_duration
		evade_dir = -1 if randf() < 0.5 else 1
	if health <= 0:
		var gained = score_value + (headshot_score_bonus if is_headshot else 0)
		GameManager.add_score(gained)
		get_tree().call_group("enemy_spawner", "_on_enemy_died")
		queue_free()
