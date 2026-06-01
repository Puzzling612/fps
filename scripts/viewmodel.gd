extends Node3D
# First-person weapon viewmodel. Builds 4 distinct gun models procedurally and
# shows the one matching the equipped weapon. Recoil/sway animate the whole rig.

@export var recoil_kick_back: float = 0.05
@export var recoil_kick_up: float = 0.09     # radians of pitch
@export var recoil_kick_side: float = 0.03   # small lateral randomness
@export var decay_speed: float = 14.0
@export var sway_amplitude_y: float = 0.004
@export var sway_amplitude_x: float = 0.003
@export var sway_speed: float = 1.6

# Iron-sight ADS pose for the assault rifle: gun pulled to screen centre so the
# front post lines up through the rear notch. Tunable in the inspector.
@export var ads_lerp_speed: float = 16.0
@export var ar_ads_pos: Vector3 = Vector3(0.0, -0.052, 0.04)

var _base_pos: Vector3
var _base_rot: Vector3
var _recoil_pos: Vector3 = Vector3.ZERO
var _recoil_rot_x: float = 0.0
var _recoil_rot_y: float = 0.0
var _t: float = 0.0

var _models: Dictionary = {}   # display_name -> Node3D
var _current_model: Node3D = null
var _current_name: String = ""

# Iron sights (AR only): shown solely while aiming down sights.
var _ar_sights: Array[MeshInstance3D] = []
var _ads_active: bool = false
var _pose_pos: Vector3 = Vector3.ZERO
var _pose_rot: Vector3 = Vector3.ZERO

# Shared materials
var _mat_body: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_plastic: StandardMaterial3D
var _mat_accent: StandardMaterial3D

func _ready() -> void:
	# Drop any placeholder meshes authored in the scene; we build our own.
	for c in get_children():
		c.queue_free()

	_base_pos = position
	_base_rot = rotation
	_pose_pos = position
	_pose_rot = rotation
	# Resolve ADS depth relative to the model's resting depth.
	ar_ads_pos.z = _base_pos.z + 0.04
	_init_mats()

	_models["ASSAULT RIFLE"] = _build_ar()
	_models["SHOTGUN"] = _build_shotgun()
	_models["SNIPER"] = _build_sniper()
	_models["SMG"] = _build_smg()
	for m in _models.values():
		m.visible = false
		add_child(m)

	if not GameManager.weapon_changed.is_connected(_on_weapon_changed):
		GameManager.weapon_changed.connect(_on_weapon_changed)
	if not GameManager.ads_changed.is_connected(_on_ads_changed):
		GameManager.ads_changed.connect(_on_ads_changed)
	_show("ASSAULT RIFLE")

func _process(delta: float) -> void:
	_t += delta
	var k = clamp(decay_speed * delta, 0.0, 1.0)
	_recoil_pos = _recoil_pos.lerp(Vector3.ZERO, k)
	_recoil_rot_x = lerp(_recoil_rot_x, 0.0, k)
	_recoil_rot_y = lerp(_recoil_rot_y, 0.0, k)

	# Slide between the resting pose and the centred iron-sight pose.
	var ads_k: float = clamp(ads_lerp_speed * delta, 0.0, 1.0)
	var target_pose: Vector3 = ar_ads_pos if _ads_active else _base_pos
	_pose_pos = _pose_pos.lerp(target_pose, ads_k)

	# While aiming, flatten the gun's resting tilt so the barrel/sights point
	# straight down the camera axis (otherwise the front post sits off-centre).
	var target_rot: Vector3 = Vector3.ZERO if _ads_active else _base_rot
	_pose_rot = _pose_rot.lerp(target_rot, ads_k)

	var sway_scale: float = 0.25 if _ads_active else 1.0
	var sway = Vector3(
		sin(_t * sway_speed * 0.7) * sway_amplitude_x,
		sin(_t * sway_speed) * sway_amplitude_y,
		0.0
	) * sway_scale
	position = _pose_pos + _recoil_pos + sway
	rotation = Vector3(_pose_rot.x + _recoil_rot_x, _pose_rot.y + _recoil_rot_y, _pose_rot.z)

func add_recoil(scale: float = 1.0) -> void:
	_recoil_pos.z += recoil_kick_back * scale
	_recoil_rot_x += recoil_kick_up * scale
	_recoil_rot_y += randf_range(-recoil_kick_side, recoil_kick_side) * scale

func _on_weapon_changed(weapon_name: String) -> void:
	_show(weapon_name)

func _show(weapon_name: String) -> void:
	if not _models.has(weapon_name):
		return
	if _current_model:
		_current_model.visible = false
	_current_model = _models[weapon_name]
	_current_model.visible = true
	_current_name = weapon_name

# Iron sights appear only while the AR is aimed down sights (RMB held).
func _on_ads_changed(active: bool, scoped: bool) -> void:
	_ads_active = active and not scoped and _current_name == "ASSAULT RIFLE"
	for s in _ar_sights:
		if is_instance_valid(s):
			s.visible = _ads_active

# ─── Materials ───────────────────────────────────────────────
func _init_mats() -> void:
	_mat_body = _mat(Color(0.16, 0.16, 0.18), 0.42, 0.6)
	_mat_dark = _mat(Color(0.06, 0.06, 0.07), 0.55, 0.3)
	_mat_plastic = _mat(Color(0.09, 0.09, 0.10), 0.75, 0.0)
	_mat_accent = _mat(Color(0.55, 0.32, 0.06), 0.4, 0.4)

func _mat(c: Color, r: float, m: float) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c; mt.roughness = r; mt.metallic = m
	return mt

# ─── Mesh helpers ────────────────────────────────────────────
func _box(parent: Node3D, size: Vector3, mat: StandardMaterial3D, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	parent.add_child(mi)

func _cyl(parent: Node3D, radius: float, height: float, mat: StandardMaterial3D, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = radius; cm.bottom_radius = radius; cm.height = height
	cm.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	parent.add_child(mi)

# ─── Weapon models ───────────────────────────────────────────
func _build_ar() -> Node3D:
	var g := Node3D.new()
	_box(g, Vector3(0.07, 0.06, 0.42), _mat_body, Vector3(0, 0, -0.02))
	_box(g, Vector3(0.06, 0.085, 0.14), _mat_plastic, Vector3(0, 0, 0.24))
	_box(g, Vector3(0.045, 0.17, 0.055), _mat_plastic, Vector3(0, -0.115, 0.085), Vector3(-10, 0, 0))
	_box(g, Vector3(0.046, 0.13, 0.04), _mat_dark, Vector3(0, -0.1, -0.02))
	_box(g, Vector3(0.022, 0.022, 0.16), _mat_dark, Vector3(0, 0.005, -0.27))
	# ── Iron sights (centreline, hidden until ADS) ──
	var front := _sight_box(g, Vector3(0.005, 0.034, 0.005), Vector3(0, 0.052, -0.23))
	var rear_l := _sight_box(g, Vector3(0.005, 0.028, 0.005), Vector3(-0.013, 0.05, 0.12))
	var rear_r := _sight_box(g, Vector3(0.005, 0.028, 0.005), Vector3(0.013, 0.05, 0.12))
	_ar_sights = [front, rear_l, rear_r]
	for s in _ar_sights:
		s.visible = false
	return g

# Like _box but returns the node so we can keep a reference (used for iron sights).
func _sight_box(parent: Node3D, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = _mat_dark
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_shotgun() -> Node3D:
	var g := Node3D.new()
	# Thicker, shorter receiver
	_box(g, Vector3(0.085, 0.08, 0.38), _mat_body, Vector3(0, 0, 0.0))
	_box(g, Vector3(0.07, 0.10, 0.16), _mat_plastic, Vector3(0, -0.005, 0.25))     # stock
	_box(g, Vector3(0.05, 0.16, 0.06), _mat_plastic, Vector3(0, -0.11, 0.10), Vector3(-8, 0, 0))  # grip
	# Wide barrel + pump under it
	_cyl(g, 0.03, 0.34, _mat_dark, Vector3(0, 0.018, -0.28), Vector3(90, 0, 0))
	_box(g, Vector3(0.05, 0.035, 0.12), _mat_accent, Vector3(0, -0.035, -0.18))     # pump fore-end
	return g

func _build_sniper() -> Node3D:
	var g := Node3D.new()
	# Long slim receiver + long thin barrel
	_box(g, Vector3(0.06, 0.06, 0.5), _mat_body, Vector3(0, 0, 0.02))
	_box(g, Vector3(0.055, 0.09, 0.18), _mat_plastic, Vector3(0, -0.01, 0.30))      # stock
	_box(g, Vector3(0.045, 0.16, 0.05), _mat_plastic, Vector3(0, -0.11, 0.12), Vector3(-10, 0, 0))  # grip
	_box(g, Vector3(0.05, 0.13, 0.045), _mat_dark, Vector3(0, -0.1, 0.02))          # mag
	_cyl(g, 0.014, 0.42, _mat_dark, Vector3(0, 0.012, -0.42), Vector3(90, 0, 0))    # long barrel
	# Scope: tube on risers
	_cyl(g, 0.028, 0.20, _mat_dark, Vector3(0, 0.09, -0.05), Vector3(90, 0, 0))
	_box(g, Vector3(0.02, 0.05, 0.02), _mat_dark, Vector3(0, 0.055, -0.13))
	_box(g, Vector3(0.02, 0.05, 0.02), _mat_dark, Vector3(0, 0.055, 0.03))
	return g

func _build_smg() -> Node3D:
	var g := Node3D.new()
	# Compact small body, short barrel, angled mag
	_box(g, Vector3(0.06, 0.07, 0.26), _mat_body, Vector3(0, 0, 0.0))
	_box(g, Vector3(0.05, 0.07, 0.10), _mat_dark, Vector3(0, 0, 0.17))              # short stock
	_box(g, Vector3(0.045, 0.15, 0.05), _mat_plastic, Vector3(0, -0.10, 0.05), Vector3(-8, 0, 0))   # grip
	_box(g, Vector3(0.04, 0.17, 0.038), _mat_dark, Vector3(0, -0.13, -0.03), Vector3(18, 0, 0))     # curved-ish mag
	_cyl(g, 0.016, 0.10, _mat_dark, Vector3(0, 0.008, -0.19), Vector3(90, 0, 0))   # stubby barrel
	return g
