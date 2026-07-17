extends Node3D
# Grenadier projectile. Lobbed with launch(); integrates gravity, then explodes
# on ground contact or fuse end, dealing radial damage to the player.

@export var gravity: float = 16.0
@export var blast_radius: float = 5.6
@export var min_falloff: float = 0.25
@export var wall_bounce_damping: float = 0.6  # 벽에 튕길 때 속도 유지 비율

var velocity: Vector3 = Vector3.ZERO
var fuse: float = 2.0
var damage: int = 20
var hits_player: bool = true   # enemy grenades hurt the player; player grenades hurt enemies
var _armed: bool = false
var _resting: bool = false     # enemy grenade landed: sitting on the ground, fuse burning
var _beep_t: float = 0.0

# Enemy grenades must be REACTABLE: they land, sit beeping for at least this
# long, then blow. (Player grenades keep detonating on ground contact.)
const REST_MIN_FUSE := 0.9

@onready var mesh: MeshInstance3D = $Mesh

func launch(vel: Vector3, fuse_time: float, dmg: int, hits_player_: bool = true) -> void:
	velocity = vel
	fuse = fuse_time
	damage = dmg
	hits_player = hits_player_
	_armed = true
	if hits_player:
		# HUD danger marker tracks this group.
		add_to_group("enemy_grenade")

func _physics_process(delta: float) -> void:
	if not _armed:
		return
	fuse -= delta

	# Landed enemy grenade: sit on the spot, beep + pulse until the fuse blows.
	if _resting:
		_beep_t -= delta
		if _beep_t <= 0.0:
			_beep_t = 0.22
			AudioManager.play_beep_at(global_position)
			if mesh:
				mesh.scale = Vector3.ONE * (1.5 if mesh.scale.x < 1.2 else 1.0)
		if fuse <= 0.0:
			_explode()
		return

	velocity.y -= gravity * delta
	var motion: Vector3 = velocity * delta
	var next_pos: Vector3 = global_position + motion
	rotate_x(velocity.length() * delta * 2.0)

	# Bounce off walls (vertical static geometry). On the ground / any near-
	# horizontal surface: PLAYER grenades detonate on impact (unchanged), ENEMY
	# grenades come to rest and burn their fuse so the player can react/escape.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position, next_pos)
	var r := space.intersect_ray(q)
	if not r.is_empty() and r.collider is StaticBody3D:
		var n: Vector3 = r.normal
		if absf(n.y) < 0.55:
			# Wall: reflect the velocity and keep flying.
			global_position = r.position + n * 0.06
			velocity = (velocity - 2.0 * velocity.dot(n) * n) * wall_bounce_damping
		else:
			global_position = r.position + Vector3(0, 0.08, 0)
			if hits_player:
				_rest()
			else:
				_explode()
			return
	else:
		global_position = next_pos

	# Safety net for the flat ground plane.
	if global_position.y <= 0.15:
		global_position.y = 0.15
		if hits_player:
			_rest()
		else:
			_explode()
		return
	if fuse <= 0.0:
		_explode()

func _rest() -> void:
	_resting = true
	velocity = Vector3.ZERO
	fuse = maxf(fuse, REST_MIN_FUSE)
	AudioManager.play_beep_at(global_position)

func _explode() -> void:
	_armed = false
	if hits_player:
		var p = GameManager.player
		if is_instance_valid(p) and p.has_method("take_damage"):
			var d: float = global_position.distance_to((p as Node3D).global_position)
			if d <= blast_radius:
				var f: float = clampf(1.0 - d / blast_radius, min_falloff, 1.0)
				p.take_damage(int(round(damage * f)), true, global_position)
	else:
		# Player grenade: FULL damage (no distance falloff) to every enemy inside
		# the blast → one-shots anything in radius regardless of wave HP scaling.
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or not e.has_method("take_damage"):
				continue
			var d: float = global_position.distance_to((e as Node3D).global_position)
			if d <= blast_radius:
				e.take_damage(damage, false)
	# Explosion VFX + positional boom.
	FX.explosion(get_tree().current_scene, global_position, blast_radius)
	AudioManager.play_explosion_at(global_position)
	queue_free()
