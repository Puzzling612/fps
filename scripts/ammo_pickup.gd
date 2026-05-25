extends Area3D

@export var ammo_amount: int = 30
@export var rotate_speed: float = 1.8
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
	if body == GameManager.player and body.has_method("get") and body.get("weapon") != null:
		var w = body.weapon
		if w.has_method("add_ammo"):
			w.add_ammo(ammo_amount)
			AudioManager.play_reload()
			_collected = true
			queue_free()
