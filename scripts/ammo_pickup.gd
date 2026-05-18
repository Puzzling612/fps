extends Area3D

@export var ammo_amount: int = 30
@export var respawn_time: float = 8.0
@export var rotate_speed: float = 1.8
@export var bob_amplitude: float = 0.12
@export var bob_speed: float = 2.2

@onready var visual: Node3D = $Visual
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var respawn_timer: Timer = $RespawnTimer

var _t: float = 0.0
var _base_y: float = 0.0
var _active: bool = true

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	respawn_timer.wait_time = respawn_time
	respawn_timer.one_shot = true
	respawn_timer.timeout.connect(_on_respawn)
	_base_y = visual.position.y

func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	visual.rotate_y(rotate_speed * delta)
	visual.position.y = _base_y + sin(_t * bob_speed) * bob_amplitude

func _on_body_entered(body: Node) -> void:
	if not _active:
		return
	if body == GameManager.player and body.has_method("get") and body.get("weapon") != null:
		var w = body.weapon
		if w.has_method("add_ammo"):
			w.add_ammo(ammo_amount)
			AudioManager.play_reload()
			_hide_and_respawn()

func _hide_and_respawn() -> void:
	_active = false
	visual.visible = false
	collision.disabled = true
	respawn_timer.start()

func _on_respawn() -> void:
	_active = true
	visual.visible = true
	collision.disabled = false
	_t = 0.0
	visual.position.y = _base_y
