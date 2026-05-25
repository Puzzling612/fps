# Spawns ammo and health pickups at random points from a pool.
# Maintains a target count of each type; when pickups are collected they free
# themselves and the spawner re-spawns at a different random point after a delay.

extends Node3D

@export var ammo_scene: PackedScene
@export var health_scene: PackedScene
@export var ammo_target_count: int = 5
@export var health_target_count: int = 3
@export var spawn_delay_min: float = 3.0
@export var spawn_delay_max: float = 8.0
@export var check_interval: float = 1.5
@export var min_distance_between: float = 2.5

var spawn_points: Array[Node3D] = []
var _pending_ammo: int = 0
var _pending_health: int = 0
var _check_timer: float = 0.5

func _ready() -> void:
	for child in get_children():
		if child is Marker3D:
			spawn_points.append(child)
	# Defer initial spawn until the scene tree is settled
	call_deferred("_initial_spawn")

func _initial_spawn() -> void:
	for i in ammo_target_count:
		_spawn_one("ammo")
	for i in health_target_count:
		_spawn_one("health")

func _process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = check_interval

	var ammo_alive: int = _count("pickup_ammo")
	var health_alive: int = _count("pickup_health")

	var ammo_needed: int = ammo_target_count - ammo_alive - _pending_ammo
	for i in ammo_needed:
		_pending_ammo += 1
		_schedule_spawn("ammo")

	var health_needed: int = health_target_count - health_alive - _pending_health
	for i in health_needed:
		_pending_health += 1
		_schedule_spawn("health")

func _schedule_spawn(type: String) -> void:
	var delay: float = randf_range(spawn_delay_min, spawn_delay_max)
	await get_tree().create_timer(delay).timeout
	if type == "ammo":
		_pending_ammo = max(0, _pending_ammo - 1)
	else:
		_pending_health = max(0, _pending_health - 1)
	_spawn_one(type)

func _spawn_one(type: String) -> void:
	var scene: PackedScene = ammo_scene if type == "ammo" else health_scene
	if scene == null:
		return
	var free_points := _get_free_points()
	if free_points.is_empty():
		return
	var p: Node3D = free_points.pick_random()
	var pickup: Node = scene.instantiate()
	pickup.add_to_group("pickup_" + type)
	get_tree().current_scene.add_child(pickup)
	if pickup is Node3D:
		(pickup as Node3D).global_position = p.global_position

func _get_free_points() -> Array:
	var occupied: Array = []
	for p in get_tree().get_nodes_in_group("pickup_ammo"):
		if p is Node3D:
			occupied.append((p as Node3D).global_position)
	for p in get_tree().get_nodes_in_group("pickup_health"):
		if p is Node3D:
			occupied.append((p as Node3D).global_position)
	var free: Array = []
	for sp in spawn_points:
		var taken := false
		for o in occupied:
			if sp.global_position.distance_to(o) < min_distance_between:
				taken = true
				break
		if not taken:
			free.append(sp)
	return free

func _count(group_name: String) -> int:
	return get_tree().get_nodes_in_group(group_name).size()
