extends CharacterBody3D

@export var health: int = 100
@export var score_value: int = 100

func take_damage(amount: int) -> void:
    health -= amount
    if health <= 0:
        GameManager.add_score(score_value)
        queue_free()
