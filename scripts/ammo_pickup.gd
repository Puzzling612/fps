extends Area3D

# Typed ammo crate. weapon_id decides both the colour and which weapon it refills:
#   ar → yellow, shotgun → orange, sniper → blue, smg → green.
# The spawner sets weapon_id (to a currently-unlocked weapon) before adding it.

@export var weapon_id: String = "ar"
@export var rotate_speed: float = 1.8
@export var bob_amplitude: float = 0.12
@export var bob_speed: float = 2.2

# One magazine of the matching weapon per crate.
const AMOUNTS := {"ar": 30, "shotgun": 12, "sniper": 10, "smg": 40}
const COLORS := {
	"ar":      Color(0.95, 0.12, 0.10),   # red
	"shotgun": Color(1.00, 0.48, 0.03),   # orange
	"sniper":  Color(0.15, 0.50, 1.00),   # blue
	"smg":     Color(0.20, 0.92, 0.32),   # green
}

@onready var visual: Node3D = $Visual

var _t: float = 0.0
var _base_y: float = 0.0
var _collected: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_base_y = visual.position.y
	_apply_color()

# Re-type an already-spawned crate (used when a new weapon unlocks so existing
# crates immediately reflect the new colour mix).
func set_type(id: String) -> void:
	weapon_id = id
	if is_inside_tree():
		_apply_color()

func _apply_color() -> void:
	var col: Color = COLORS.get(weapon_id, COLORS["ar"])
	var mesh: MeshInstance3D = visual.get_node_or_null("MeshInstance3D")
	if mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.metallic = 0.4
		mat.roughness = 0.3
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 1.8
		mesh.material_override = mat
	var light: OmniLight3D = visual.get_node_or_null("GlowLight")
	if light:
		light.light_color = col

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
		if w.has_method("add_ammo_to"):
			w.add_ammo_to(weapon_id, AMOUNTS.get(weapon_id, 20))
			AudioManager.play_reload()
			_collected = true
			queue_free()
