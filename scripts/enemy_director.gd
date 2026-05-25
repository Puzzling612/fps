# Tactical director: coordinates enemies around the player.
# - Distributes them in slots around the player (encirclement).
# - Tags slots behind the player's view as "flank" → those enemies sprint.
# - Periodically assigns one enemy a watchtower-seizing objective.

extends Node

@export var slot_count: int = 8
@export var slot_radius: float = 12.0
@export var reassign_interval: float = 1.0
@export var ladder_base: Vector3 = Vector3(-15.5, 0.0, -30.0)  # entry to ladder
@export var watchtower_top: Vector3 = Vector3(-18.0, 8.3, -30.0)
@export var objective_reassign_interval: float = 6.0
@export var min_enemies_before_objective: int = 3

var _reassign_timer: float = 0.5
var _objective_timer: float = 2.0
var _objective_enemy: WeakRef = null

func _process(delta: float) -> void:
	if GameManager.is_game_over:
		return
	_reassign_timer -= delta
	_objective_timer -= delta
	if _reassign_timer <= 0.0:
		_reassign_timer = reassign_interval
		_reassign_slots()
	if _objective_timer <= 0.0:
		_objective_timer = objective_reassign_interval
		_try_assign_objective()

# ─── Encirclement: slot allocation ──────────────────────────
func _reassign_slots() -> void:
	var player = GameManager.player
	if not is_instance_valid(player):
		return
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return

	var player_pos: Vector3 = player.global_position
	var view_forward: Vector3 = -player.global_transform.basis.z
	view_forward.y = 0
	if view_forward.length() < 0.001:
		view_forward = Vector3.FORWARD
	view_forward = view_forward.normalized()

	# Build slot positions around the player
	var slots: Array[Vector3] = []
	for i in slot_count:
		var ang: float = TAU * float(i) / float(slot_count)
		slots.append(player_pos + Vector3(cos(ang) * slot_radius, 0, sin(ang) * slot_radius))

	# Only consider enemies that have NO active objective
	var active: Array = []
	for e in enemies:
		if not is_instance_valid(e): continue
		if e.get("has_objective"): continue
		active.append(e)

	# Greedy assignment: each slot picks the nearest unassigned enemy
	var assigned := {}
	for slot in slots:
		var best: Node = null
		var best_d: float = INF
		for e in active:
			if assigned.has(e): continue
			var d: float = (e as Node3D).global_position.distance_to(slot)
			if d < best_d:
				best_d = d
				best = e
		if best:
			assigned[best] = slot
			# Determine role: if the slot is behind the player view, it's a flank position
			var to_slot: Vector3 = slot - player_pos
			to_slot.y = 0
			var dir_to_slot: Vector3 = to_slot.normalized() if to_slot.length() > 0.001 else Vector3.FORWARD
			var dot: float = view_forward.dot(dir_to_slot)
			var role: String = "flank" if dot < -0.15 else "encircle"
			best.assign_slot(slot, role)

# ─── Watchtower objective ───────────────────────────────────
func _try_assign_objective() -> void:
	if _objective_enemy != null and _objective_enemy.get_ref():
		return  # someone is already pursuing the objective
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.size() < min_enemies_before_objective:
		return
	# Pick the enemy currently nearest to the ladder base (most efficient route)
	var best: Node = null
	var best_d: float = INF
	for e in enemies:
		if not is_instance_valid(e): continue
		if e.get("has_objective"): continue
		var d: float = (e as Node3D).global_position.distance_to(ladder_base)
		if d < best_d:
			best_d = d
			best = e
	if best == null: return
	best.assign_objective(ladder_base)
	_objective_enemy = weakref(best)
