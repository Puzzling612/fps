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
@export var attack_range: float = 70.0
@export var preferred_distance: float = 11.0
@export var min_distance: float = 6.0
@export var distance_tolerance: float = 1.5
@export var aim_spread_deg: float = 4.0
@export var strafe_change_interval_min: float = 0.8
@export var strafe_change_interval_max: float = 1.8
@export var jump_velocity: float = 7.5
@export var gravity: float = 18.0
@export var hp_lerp_speed: float = 110.0
@export var slot_reach_distance: float = 2.5
@export var evade_duration: float = 0.55
@export var jump_cooldown: float = 0.35
@export var ladder_climb_speed: float = 5.0

# ─── Enemy types ─────────────────────────────────────────────
enum EnemyType { NORMAL, RUSHER, MARKSMAN, GRENADIER }
@export var enemy_type: EnemyType = EnemyType.NORMAL
const GRENADE_SCENE := preload("res://scenes/Grenade.tscn")

# ─── State machine ───────────────────────────────────────────
enum State { APPROACH, ENGAGE, EVADE, GOTO_OBJECTIVE, COMBAT }
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

# Utility AI (Step 2)
@export var action_reeval_interval: float = 0.35
var combat_action: String = "engage"
var action_timer: float = 0.0
var cover_target: Vector3 = Vector3(1.0e30, 0, 0)
var _director: Node = null

# Behavior Tree (Step 3) — decision layer; movement stays in _physics_process
var _bt: BT.BTNode = null
var _bt_player: Node = null

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
@onready var nav_agent: NavigationAgent3D = $NavAgent

var _flash_material: StandardMaterial3D
var _base_override: StandardMaterial3D = null
var _model_meshes: Array[MeshInstance3D] = []

# ─── Setup ───────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	_displayed_hp = float(max_health)
	strafe_dir = 1 if randf() < 0.5 else -1
	strafe_timer = randf_range(strafe_change_interval_min, strafe_change_interval_max)
	_build_behavior_tree()

	_flash_material = StandardMaterial3D.new()
	_flash_material.albedo_color = Color(1, 1, 1, 1)
	_flash_material.emission_enabled = true
	_flash_material.emission = Color(1, 1, 1)
	_flash_material.emission_energy_multiplier = 2.0

	if model:
		_collect_meshes(model)
	_apply_type_visuals()

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
		mi.material_override = _flash_material if on else _base_override

# Tint + scale the model so each type reads at a glance.
func _apply_type_visuals() -> void:
	var tint: Color
	var scl := 1.0
	match enemy_type:
		EnemyType.RUSHER:    tint = Color(1.0, 0.55, 0.05); scl = 0.85
		EnemyType.MARKSMAN:  tint = Color(0.15, 0.45, 1.0); scl = 1.12
		EnemyType.GRENADIER: tint = Color(0.25, 0.8, 0.25); scl = 1.05
		_:                   return   # NORMAL keeps the default GLB look
	_base_override = StandardMaterial3D.new()
	_base_override.albedo_color = tint
	_base_override.roughness = 0.6
	_base_override.metallic = 0.1
	for mi in _model_meshes:
		mi.material_override = _base_override
	if model:
		model.scale *= scl

# ─── Configuration (called by spawner before add_child) ──────
func configure(w: int, t: int, d: float) -> void:
	enemy_type = t
	max_health = WaveBalance.enemy_hp(w)
	attack_damage = int(round(WaveBalance.enemy_dmg(w) * d))
	attack_interval = WaveBalance.enemy_interval(w)
	aim_spread_deg = WaveBalance.enemy_spread(w) / sqrt(d)
	headshot_multiplier = WaveBalance.headshot_mult(w)
	match t:
		EnemyType.RUSHER:
			max_health = int(max_health * 0.6)
			move_speed *= 1.5
			sprint_speed *= 1.45
			preferred_distance = 2.5
			min_distance = 1.0
			attack_range = 14.0
			attack_damage = int(round(attack_damage * 1.3))
			attack_interval *= 0.7
		EnemyType.MARKSMAN:
			max_health = int(max_health * 0.9)
			move_speed *= 0.9
			preferred_distance = 24.0
			min_distance = 14.0
			attack_range = 90.0
			attack_damage = int(round(attack_damage * 3.2))
			attack_interval = maxf(2.2, attack_interval * 2.6)
			aim_spread_deg = 0.3
		EnemyType.GRENADIER:
			max_health = int(max_health * 1.0)
			preferred_distance = 16.0
			min_distance = 10.0
			attack_range = 40.0
			attack_interval = maxf(2.4, attack_interval * 2.4)

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
	if action_timer > 0.0:   action_timer -= delta

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

	# Always face the player (yaw only) — even when standing still or in evade
	var face_dir: Vector3 = (player as Node3D).global_position - global_position
	face_dir.y = 0.0
	if face_dir.length() > 0.05:
		look_at(global_position + face_dir.normalized(), Vector3.UP)

	var desired: Vector3 = _compute_desired_movement(forward_to_player, distance_p, delta)
	velocity.x = desired.x
	velocity.z = desired.z

	# Attack when in range and LOS — any state except climbing to objective
	if state != State.GOTO_OBJECTIVE and attack_cooldown <= 0.0 and distance_p <= attack_range:
		if _has_line_of_sight(player):
			if enemy_type == EnemyType.GRENADIER:
				_throw_grenade(player)
			else:
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
func _get_profile() -> PlayerProfile:
	if _director == null or not is_instance_valid(_director):
		var ds := get_tree().get_nodes_in_group("ai_director")
		_director = ds[0] if ds.size() > 0 else null
	if _director and is_instance_valid(_director):
		return _director.current_profile
	return null

func _update_state(player: Node) -> void:
	# The Behavior Tree is the decision layer: it sets `state` / `combat_action`.
	# Movement execution stays in _physics_process / _compute_desired_movement.
	_bt_player = player
	if _bt != null:
		_bt.tick(self)

# ─── Behavior Tree construction ──────────────────────────────
#   Root (Selector)
#   ├── [Seq] evading      → EVADE
#   ├── [Seq] has objective→ GOTO_OBJECTIVE (climb watchtower)
#   ├── [Seq] perched high → ENGAGE (hold & shoot)
#   └── Combat (Utility-driven action selection) — always succeeds
func _build_behavior_tree() -> void:
	_bt = BT.Selector.new([
		BT.Sequence.new([
			BT.Condition.new(_bt_is_evading),
			BT.Action.new(_bt_set_evade),
		]),
		BT.Sequence.new([
			BT.Condition.new(_bt_has_objective),
			BT.Action.new(_bt_set_objective),
		]),
		BT.Sequence.new([
			BT.Condition.new(_bt_is_perched),
			BT.Action.new(_bt_set_perched_engage),
		]),
		BT.Action.new(_bt_combat),
	])

func _bt_is_evading(_a) -> bool:
	return evade_timer > 0.0

func _bt_set_evade(_a) -> int:
	state = State.EVADE
	return BT.SUCCESS

func _bt_has_objective(_a) -> bool:
	return has_objective

func _bt_set_objective(_a) -> int:
	state = State.GOTO_OBJECTIVE
	return BT.SUCCESS

func _bt_is_perched(_a) -> bool:
	if global_position.y <= 5.0:
		return false
	var d: float = ((_bt_player as Node3D).global_position - global_position).length()
	return d <= attack_range and _has_line_of_sight(_bt_player)

func _bt_set_perched_engage(_a) -> int:
	state = State.ENGAGE
	return BT.SUCCESS

# Utility-driven combat node: re-evaluates the chosen action periodically.
func _bt_combat(_a) -> int:
	state = State.COMBAT
	if action_timer <= 0.0:
		action_timer = action_reeval_interval
		var player := _bt_player
		var distance_p: float = ((player as Node3D).global_position - global_position).length()
		var profile := _get_profile()
		if profile == null:
			profile = PlayerProfile.new()
		var has_los := _has_line_of_sight(player)
		var ctx := {
			"distance": distance_p,
			"health_ratio": float(health) / float(max_health),
			"has_los": has_los,
			"in_cover": cover_target.x < 1.0e29 and global_position.distance_to(cover_target) < 1.5,
			"has_flank_slot": slot_position != NO_TARGET,
			"preferred_distance": preferred_distance,
			"min_distance": min_distance,
		}
		var new_action := UtilityScorer.pick_action(ctx, profile)
		if new_action != combat_action:
			combat_action = new_action
			if combat_action == UtilityScorer.COVER or combat_action == UtilityScorer.RETREAT:
				cover_target = _compute_cover_target((player as Node3D).global_position)
	return BT.SUCCESS

func _compute_cover_target(player_pos: Vector3) -> Vector3:
	# Sample directions around the enemy; pick the nearest standing point whose
	# line to the player is blocked by geometry (true cover). Fallback: back off.
	var space := get_world_3d().direct_space_state
	var best := Vector3(1.0e30, 0, 0)
	var best_d := INF
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var cand := global_position + Vector3(cos(ang), 0, sin(ang)) * 3.5
		var eye := cand + Vector3(0, 1.0, 0)
		var q := PhysicsRayQueryParameters3D.create(eye, player_pos + Vector3(0, 1.0, 0))
		q.exclude = [get_rid()]
		var r := space.intersect_ray(q)
		if not r.is_empty() and r.collider != _director:  # LOS blocked → cover
			var d := global_position.distance_to(cand)
			if d < best_d:
				best_d = d
				best = cand
	if best.x > 1.0e29:
		# No cover found: retreat directly away from the player
		var away := (global_position - player_pos)
		away.y = 0
		if away.length() > 0.01:
			best = global_position + away.normalized() * 4.0
	return best

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
			return _nav_dir(objective_position, sprint_speed)
		State.APPROACH:
			if slot_position != NO_TARGET:
				var spd: float = sprint_speed if role == "flank" else move_speed
				return _nav_dir(slot_position, spd)
			return _nav_dir(global_position + forward_to_player * distance_p, move_speed)
		State.ENGAGE:
			# Perched on watchtower — stay still and shoot
			if global_position.y > 5.0:
				return Vector3.ZERO
			return _engage_orbit(forward_to_player, distance_p, delta)
		State.COMBAT:
			return _combat_movement(forward_to_player, distance_p, delta)
	return Vector3.ZERO

# Existing orbit/strafe behaviour, reused by ENGAGE and the STRAFE action.
func _engage_orbit(forward_to_player: Vector3, distance_p: float, delta: float) -> Vector3:
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

# Maps the utility-selected action to actual movement.
func _combat_movement(forward_to_player: Vector3, distance_p: float, delta: float) -> Vector3:
	var player_pos := global_position + forward_to_player * distance_p
	match combat_action:
		UtilityScorer.PUSH:
			return _nav_dir(player_pos, sprint_speed)
		UtilityScorer.RETREAT:
			if cover_target.x < 1.0e29 and global_position.distance_to(cover_target) > 0.6:
				return _nav_dir(cover_target, sprint_speed)
			return -forward_to_player * sprint_speed
		UtilityScorer.COVER:
			if cover_target.x < 1.0e29 and global_position.distance_to(cover_target) > 0.6:
				return _nav_dir(cover_target, move_speed)
			return _engage_orbit(forward_to_player, distance_p, delta)
		UtilityScorer.FLANK:
			if slot_position != NO_TARGET:
				var to_slot := slot_position - global_position
				to_slot.y = 0
				if to_slot.length() > slot_reach_distance:
					return _nav_dir(slot_position, sprint_speed)
			return _engage_orbit(forward_to_player, distance_p, delta)
		UtilityScorer.ENGAGE:
			var slot_mv := _slot_approach()
			if slot_mv != Vector3.ZERO:
				return slot_mv
			# Hold preferred range, minimal strafe
			var radial: Vector3 = Vector3.ZERO
			if distance_p > preferred_distance + distance_tolerance:
				radial = forward_to_player * move_speed
			elif distance_p < min_distance:
				radial = -forward_to_player * move_speed
			return radial
		_:  # STRAFE (default)
			var slot_mv2 := _slot_approach()
			if slot_mv2 != Vector3.ZERO:
				return slot_mv2
			return _engage_orbit(forward_to_player, distance_p, delta)

# If a director slot is assigned and we're far from it, move there to keep the
# encirclement; returns ZERO when already in position (let orbit/engage run).
func _slot_approach() -> Vector3:
	if slot_position == NO_TARGET:
		return Vector3.ZERO
	var to_slot := slot_position - global_position
	to_slot.y = 0
	if to_slot.length() > slot_reach_distance * 1.5:
		var spd: float = sprint_speed if role == "flank" else move_speed
		return _nav_dir(slot_position, spd)
	return Vector3.ZERO

# ─── NavMesh steering ────────────────────────────────────────
# Returns a horizontal velocity that follows the NavMesh path toward `dest`.
# Falls back to direct steering when no path is available (e.g. before the
# NavMesh finishes baking, or the agent/target is briefly off-mesh).
func _nav_dir(dest: Vector3, speed: float) -> Vector3:
	if nav_agent == null:
		return _direct_dir(dest, speed)
	nav_agent.target_position = dest
	var next: Vector3 = nav_agent.get_next_path_position()
	var d: Vector3 = next - global_position
	d.y = 0.0
	if d.length() < 0.05:
		# No usable path step (not baked yet / arrived) → steer directly.
		return _direct_dir(dest, speed)
	return d.normalized() * speed

func _direct_dir(dest: Vector3, speed: float) -> Vector3:
	var d: Vector3 = dest - global_position
	d.y = 0.0
	if d.length() < 0.1:
		return Vector3.ZERO
	return d.normalized() * speed

# ─── Movement helpers ────────────────────────────────────────
func _should_jump() -> bool:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001: return false
	forward = forward.normalized()
	var space := get_world_3d().direct_space_state

	# Wall in front at knee height (anything blocking forward motion)
	var low_from: Vector3 = global_position + Vector3(0, 0.35, 0)
	var low_to: Vector3 = low_from + forward * 1.1
	var q1 := PhysicsRayQueryParameters3D.create(low_from, low_to)
	q1.exclude = [get_rid()]
	if space.intersect_ray(q1).is_empty():
		return false
	# Top must be reachable (no wall higher than ~2.1m)
	var high_from: Vector3 = global_position + Vector3(0, 2.1, 0)
	var high_to: Vector3 = high_from + forward * 1.1
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
			var dmg := int(round(attack_damage * WaveBalance.falloff(from.distance_to(target))))
			player.take_damage(dmg)
	GameManager.weapon_fired.emit(from, hit_point, false, false)

func _throw_grenade(player: Node) -> void:
	var from: Vector3 = global_position + Vector3(0, 1.4, 0)
	var target: Vector3 = (player as Node3D).global_position
	var to: Vector3 = target - from
	var horiz := Vector3(to.x, 0, to.z)
	var dist := horiz.length()
	var g := GRENADE_SCENE.instantiate()
	get_tree().current_scene.add_child(g)
	g.global_position = from
	# Ballistic lob: pick a flight time scaled by distance, solve vertical speed.
	var grav: float = g.gravity if g.get("gravity") != null else 16.0
	var t: float = clampf(dist / 14.0, 0.5, 2.2)
	var vy: float = (to.y + 0.5 * grav * t * t) / t
	var vxz: Vector3 = (horiz / t) if t > 0.001 else Vector3.ZERO
	if g.has_method("launch"):
		g.launch(vxz + Vector3.UP * vy, t + 0.15, attack_damage)
	GameManager.weapon_fired.emit(from, target, false, false)

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
		get_tree().call_group("ai_director", "report_kill")
		queue_free()
