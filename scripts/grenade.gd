extends Node3D
# Grenadier projectile. Lobbed with launch(); integrates gravity, then explodes
# on ground contact or fuse end, dealing radial damage to the player.

@export var gravity: float = 16.0
@export var blast_radius: float = 4.5
@export var min_falloff: float = 0.25

var velocity: Vector3 = Vector3.ZERO
var fuse: float = 2.0
var damage: int = 20
var hits_player: bool = true   # enemy grenades hurt the player; player grenades hurt enemies
var _armed: bool = false

@onready var mesh: MeshInstance3D = $Mesh

func launch(vel: Vector3, fuse_time: float, dmg: int, hits_player_: bool = true) -> void:
	velocity = vel
	fuse = fuse_time
	damage = dmg
	hits_player = hits_player_
	_armed = true

func _physics_process(delta: float) -> void:
	if not _armed:
		return
	velocity.y -= gravity * delta
	global_position += velocity * delta
	rotate_x(8.0 * delta)
	fuse -= delta
	if fuse <= 0.0 or global_position.y <= 0.15:
		_explode()

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
	# Brief explosion flash
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 6.0
	light.omni_range = blast_radius * 1.5
	get_tree().current_scene.add_child(light)
	light.global_position = global_position
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.25)
	tw.tween_callback(light.queue_free)
	queue_free()
