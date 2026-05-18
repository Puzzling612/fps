extends Node

@export var damage: int = 25
@export var range: float = 1000.0
@export var magazine_size: int = 30
@export var max_reserve: int = 90
@export var max_reserve_cap: int = 240
@export var fire_interval: float = 0.1
@export var reload_time: float = 2.0

var magazine: int
var reserve: int
var fire_cooldown: float = 0.0
var is_reloading: bool = false
var reload_remaining: float = 0.0

func _ready() -> void:
	magazine = magazine_size
	reserve = max_reserve
	_emit_ammo()

func _process(delta: float) -> void:
	if fire_cooldown > 0.0:
		fire_cooldown -= delta
	if is_reloading:
		reload_remaining -= delta
		if reload_remaining <= 0.0:
			_finish_reload()

func try_fire(origin: Vector3, direction: Vector3) -> void:
	if is_reloading or fire_cooldown > 0.0:
		return
	if magazine <= 0:
		start_reload()
		return
	magazine -= 1
	fire_cooldown = fire_interval
	_emit_ammo()

	var space_state = owner.get_world_3d().direct_space_state
	var to_far = origin + direction.normalized() * range
	var query = PhysicsRayQueryParameters3D.create(origin, to_far)
	query.exclude = [owner.get_rid()]
	var result = space_state.intersect_ray(query)
	var hit_point: Vector3 = to_far
	var hit_enemy := false
	var is_headshot := false
	if result:
		hit_point = result.position
		var collider = result.collider
		if collider and collider.has_method("take_damage"):
			# Headshot detection: top hemisphere of capsule (local y > 0.3)
			var local_y = result.position.y - collider.global_position.y
			is_headshot = local_y > 0.3
			collider.take_damage(damage, is_headshot)
			hit_enemy = true
	GameManager.weapon_fired.emit(origin, hit_point, hit_enemy, is_headshot)
	AudioManager.play_shot()

func start_reload() -> void:
	if is_reloading:
		return
	if reserve <= 0:
		return
	if magazine >= magazine_size:
		return
	is_reloading = true
	reload_remaining = reload_time
	GameManager.reload_started.emit(reload_time)
	AudioManager.play_reload()

func _finish_reload() -> void:
	is_reloading = false
	var needed = magazine_size - magazine
	var to_load = min(needed, reserve)
	magazine += to_load
	reserve -= to_load
	GameManager.reload_finished.emit()
	_emit_ammo()

func add_ammo(amount: int) -> void:
	if amount <= 0:
		return
	reserve = min(max_reserve_cap, reserve + amount)
	_emit_ammo()

func _emit_ammo() -> void:
	GameManager.ammo_changed.emit(magazine, magazine_size, reserve)
