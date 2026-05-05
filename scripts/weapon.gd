extends Node

@export var damage: int = 25
@export var range: float = 1000.0

func fire(origin: Vector3, direction: Vector3) -> void:
    var space_state = owner.get_world_3d().direct_space_state
    var to = origin + direction.normalized() * range
    var result = space_state.intersect_ray(origin, to, [owner.get_rid()])
    if result:
        var collider = result.collider
        if collider and collider.has_method("take_damage"):
            collider.take_damage(damage)
    AudioManager.play_shot()

