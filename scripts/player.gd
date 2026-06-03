extends CharacterBody3D

@export var speed: float = 6.0
@export var sprint_multiplier: float = 1.7
@export var jump_velocity: float = 7.2
@export var gravity: float = 18.0
@export var mouse_sensitivity: float = 0.18
# Extra fine-tune on top of FOV-proportional ADS slowdown. 1.0 = pure 1:1
# tracking (mouse-to-world angle stays constant when zoomed); lower = even
# slower while scoped. Drop toward ~0.7 if the sniper still feels twitchy.
@export var ads_sensitivity_multiplier: float = 1.0
@export var max_health: int = 100
@export var max_single_hit: int = 34   # hard cap per hit → never one-shot from full HP

# ─── Throwable grenades ───
@export var grenades_per_wave: int = 3
@export var max_grenades: int = 9
@export var grenade_damage: int = 250
@export var grenade_throw_speed: float = 26.0
var grenades: int = 3

# ─── Melee (V) ───
@export var melee_damage: int = 200      # close-range payoff: one-shots any enemy (max HP 200)
@export var melee_range: float = 3.0
@export var melee_cooldown: float = 0.6
@export var melee_cone_dot: float = 0.5  # ~60° forward cone for the swing
var _melee_cd: float = 0.0

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
const GRENADE_SCENE: PackedScene = preload("res://scenes/Grenade.tscn")

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
	GameManager.player_damaged.connect(_on_player_damaged_shake)
	GameManager.ads_changed.connect(_on_ads_changed_viewmodel)
	GameManager.round_started.connect(_on_round_started_grenades)
	# Each wave grants grenades_per_wave (see _on_round_started_grenades), so start
	# empty — the first wave's round_started fills the initial stock.
	grenades = 0
	GameManager.grenades_changed.emit(grenades)

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
		# Scale sensitivity by zoom: while aiming, slow the look in proportion to
		# the FOV reduction so a given mouse move sweeps the same world angle as
		# hipfire. Big zoom (sniper, FOV 16) → much finer aim for headshots.
		var sens := mouse_sensitivity
		if weapon and weapon.ads:
			sens *= (camera.fov / fov_default) * ads_sensitivity_multiplier
		rotate_y(-event.relative.x * sens * 0.01)
		camera_pivot.rotate_x(-event.relative.y * sens * 0.01)
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

	# ── Weapon switching (number keys + scroll wheel) ──
	if Input.is_action_just_pressed("weapon_1"): weapon.switch_to(0)
	elif Input.is_action_just_pressed("weapon_2"): weapon.switch_to(1)
	elif Input.is_action_just_pressed("weapon_3"): weapon.switch_to(2)
	elif Input.is_action_just_pressed("weapon_4"): weapon.switch_to(3)
	if Input.is_action_just_pressed("weapon_next"): weapon.cycle(1)
	if Input.is_action_just_pressed("weapon_prev"): weapon.cycle(-1)

	# ── Aim-down-sights ──
	var want_ads = Input.is_action_pressed("aim") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	weapon.set_ads(want_ads)

	var sprinting = Input.is_action_pressed("sprint") and input_dir.z > 0.4 and not is_crouching and not weapon.ads
	var speed_mul = crouch_speed_multiplier if is_crouching else (sprint_multiplier if sprinting else 1.0)
	if weapon.ads:
		speed_mul *= 0.6
	var current_speed = speed * speed_mul

	if camera:
		var target_fov = fov_default
		if weapon.ads:
			target_fov = weapon.current_def().ads_fov
		elif sprinting:
			target_fov = fov_sprint
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
		weapon.try_fire(origin, direction, Input.is_action_just_pressed("shoot"))

	if Input.is_action_just_pressed("reload"):
		weapon.start_reload()

	if Input.is_action_just_pressed("throw_grenade"):
		_throw_grenade()

	if _melee_cd > 0.0:
		_melee_cd -= delta
	if Input.is_action_just_pressed("melee"):
		_melee_attack()

# Called by the weapon system on the player's own shots (visuals/recoil).
func fire_feedback(recoil_scale: float, is_headshot: bool) -> void:
	if muzzle_flash:
		muzzle_flash.visible = true
		_muzzle_t = 0.04
	if viewmodel and viewmodel.has_method("add_recoil"):
		viewmodel.add_recoil(recoil_scale)
	if is_headshot:
		add_screen_shake(0.06 * recoil_scale, 0.08)
	else:
		add_screen_shake(0.025 * recoil_scale, 0.06)

func _on_player_damaged_shake(_amount: int) -> void:
	add_screen_shake(0.12, 0.12)

# ─── Melee ───────────────────────────────────────────────────
# A quick forward swing: hits the nearest enemy inside a short cone. High damage
# (one-shots) as a reward for the risk of closing in; no ammo cost.
func _melee_attack() -> void:
	if _melee_cd > 0.0 or GameManager.is_game_over:
		return
	_melee_cd = melee_cooldown
	var cam_xf := camera.global_transform
	var origin := cam_xf.origin
	var fwd := -cam_xf.basis.z
	var best: Node = null
	var best_d := melee_range
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var to: Vector3 = ((e as Node3D).global_position + Vector3(0, 1.0, 0)) - origin
		var d := to.length()
		if d > melee_range:
			continue
		if fwd.dot(to / maxf(0.001, d)) < melee_cone_dot:
			continue
		if d < best_d:
			best_d = d
			best = e
	if best and best.has_method("take_damage"):
		best.take_damage(melee_damage, false)
	# Swing feedback even on a whiff.
	add_screen_shake(0.12, 0.14)
	if viewmodel and viewmodel.has_method("play_melee"):
		viewmodel.play_melee()
	AudioManager.play_shot()

func _on_ads_changed_viewmodel(_active: bool, scoped: bool) -> void:
	# Tuck the gun model away while looking down the sniper scope.
	if viewmodel:
		viewmodel.visible = not scoped

# ─── Grenades ────────────────────────────────────────────────
func _on_round_started_grenades(_n: int) -> void:
	# Resupply each wave (carries a little over, up to the cap).
	grenades = min(max_grenades, grenades + grenades_per_wave)
	GameManager.grenades_changed.emit(grenades)

func _throw_grenade() -> void:
	if grenades <= 0 or GameManager.is_game_over:
		return
	grenades -= 1
	GameManager.grenades_changed.emit(grenades)

	var g := GRENADE_SCENE.instantiate()
	get_tree().current_scene.add_child(g)
	var cam_xf := camera.global_transform
	var dir := -cam_xf.basis.z
	g.global_position = cam_xf.origin + dir * 0.6
	# Lob along the look direction with a slight upward arc; damages enemies only.
	var vel := dir * grenade_throw_speed + Vector3.UP * 4.0
	g.launch(vel, 2.5, grenade_damage, false)

func _on_any_weapon_fired(from: Vector3, to: Vector3, _hit_enemy: bool, _is_headshot: bool) -> void:
	# Player's own shots: tracers + feedback are handled by the weapon system.
	var dist_from_camera = (from - raycast.global_transform.origin).length()
	if dist_from_camera <= 2.0:
		return
	# Enemy shot — draw its tracer.
	_spawn_tracer(from, to)

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

func take_damage(amount: int, heavy: bool = false, from_pos: Vector3 = Vector3(INF, INF, INF)) -> void:
	if GameManager.is_game_over:
		return
	amount = mini(amount, max_single_hit)
	current_health = max(0, current_health - amount)
	GameManager.player_health_changed.emit(current_health, max_health)
	GameManager.player_damaged.emit(amount)
	# Tell the HUD which way the hit came from (horizontal angle, 0 = front).
	if from_pos.x < INF:
		var to := from_pos - global_position
		to.y = 0.0
		if to.length() > 0.01:
			var fwd := -global_transform.basis.z
			var rgt := global_transform.basis.x
			GameManager.player_hit_dir.emit(atan2(rgt.dot(to), fwd.dot(to)))
	if heavy:
		# Explosions hit much harder than bullets — heavier shake + a dedicated
		# signal the HUD uses for a stronger vignette/flash.
		add_screen_shake(0.30, 0.34)
		GameManager.player_explosion_hit.emit(amount)
	if current_health <= 0:
		GameManager.game_over()

func heal(amount: int) -> void:
	if GameManager.is_game_over:
		return
	if current_health >= max_health:
		return
	current_health = min(max_health, current_health + amount)
	GameManager.player_health_changed.emit(current_health, max_health)
