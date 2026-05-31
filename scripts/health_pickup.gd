extends Area3D

@export var heal_amount: int = 40
@export var rotate_speed: float = 1.4
@export var bob_amplitude: float = 0.12
@export var bob_speed: float = 2.2

@onready var visual: Node3D = $Visual

var _t: float = 0.0
var _base_y: float = 0.0
var _collected: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_base_y = visual.position.y

func _process(delta: float) -> void:
	if _collected:
		return
	_t += delta
	visual.rotate_y(rotate_speed * delta)
	visual.position.y = _base_y + sin(_t * bob_speed) * bob_amplitude

func _on_body_entered(body: Node) -> void:
	if _collected:
		return
	if body == GameManager.player and body.has_method("heal"):
		if body.current_health < body.max_health:
			var amt := WaveBalance.heal_amount(max(1, GameManager.current_round))
			body.heal(amt)
			_collected = true
			queue_free()
