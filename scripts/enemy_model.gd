# Procedural humanoid enemy model.
# Attach to a Node3D named "Model" inside the Enemy scene.
# Call set_flash(on, mat) from enemy.gd for the hit-flash effect.

extends Node3D

var all_meshes: Array[MeshInstance3D] = []

var _mat_helmet: StandardMaterial3D
var _mat_visor:  StandardMaterial3D
var _mat_armor:  StandardMaterial3D
var _mat_belt:   StandardMaterial3D
var _mat_pants:  StandardMaterial3D
var _mat_boot:   StandardMaterial3D
var _mat_skin:   StandardMaterial3D

func _ready() -> void:
	_init_mats()
	_build_head()
	_build_torso()
	_build_arm(1.0)
	_build_arm(-1.0)
	_build_leg(1.0)
	_build_leg(-1.0)

func set_flash(on: bool, flash_mat: StandardMaterial3D) -> void:
	for mi in all_meshes:
		mi.material_override = flash_mat if on else null

# ─── Materials ────────────────────────────────────────────────

func _init_mats() -> void:
	_mat_helmet = _mat(Color(0.95, 0.58, 0.05), 0.45, 0.20)
	_mat_armor  = _mat(Color(0.50, 0.06, 0.06), 0.35, 0.50)
	_mat_belt   = _mat(Color(0.88, 0.42, 0.03), 0.40, 0.30)
	_mat_pants  = _mat(Color(0.14, 0.11, 0.17), 0.65, 0.15)
	_mat_boot   = _mat(Color(0.09, 0.07, 0.10), 0.50, 0.30)
	_mat_skin   = _mat(Color(0.88, 0.68, 0.52), 0.70, 0.00)

	_mat_visor = StandardMaterial3D.new()
	_mat_visor.albedo_color = Color(0.05, 0.85, 0.98)
	_mat_visor.emission_enabled = true
	_mat_visor.emission = Color(0.02, 0.72, 0.92)
	_mat_visor.emission_energy_multiplier = 2.5
	_mat_visor.roughness = 0.05

func _mat(c: Color, r: float, m: float) -> StandardMaterial3D:
	var m2 := StandardMaterial3D.new()
	m2.albedo_color = c
	m2.roughness = r
	m2.metallic = m
	return m2

# ─── Body construction ────────────────────────────────────────

func _build_head() -> void:
	# Helmet – slightly oval sphere (Y-scaled 1.06 for realistic head shape)
	var sm := SphereMesh.new()
	sm.radius = 0.162; sm.height = 0.350
	sm.radial_segments = 16; sm.rings = 10
	_mi(sm, _mat_helmet, Vector3(0, 0.635, 0), Vector3(1.0, 1.06, 1.0))

	# Cyan visor bar (emissive glow across eye area)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.268, 0.078, 0.038)
	_mi(bm, _mat_visor, Vector3(0, 0.628, 0.158))

	# Neck – tapered loft (local y 0 = bottom, 0.115 = top)
	_mi(_loft([
		Vector3(0.070, 0.064, 0.000),
		Vector3(0.064, 0.059, 0.055),
		Vector3(0.058, 0.054, 0.115),
	], 10), _mat_skin, Vector3(0, 0.390, 0))

func _build_torso() -> void:
	# Smooth lofted torso: wide hips → narrow waist → broad chest → shoulders
	# Profile Vector3(half_width_x, half_depth_z, absolute_y)
	_mi(_loft([
		Vector3(0.168, 0.175, -0.050),
		Vector3(0.153, 0.160,  0.015),
		Vector3(0.128, 0.140,  0.115),  # waist (narrowest)
		Vector3(0.148, 0.158,  0.215),
		Vector3(0.175, 0.172,  0.315),  # chest
		Vector3(0.190, 0.168,  0.380),
		Vector3(0.195, 0.162,  0.405),  # shoulder line
	], 14), _mat_armor, Vector3.ZERO)

	# Belt accent ring
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.175; cyl.bottom_radius = 0.182
	cyl.height = 0.046; cyl.radial_segments = 14
	_mi(cyl, _mat_belt, Vector3(0, -0.070, 0))

func _build_arm(side: float) -> void:
	var x := side * 0.272
	# Shoulder cap sphere
	_mi(_sphere(0.090), _mat_armor, Vector3(x,  0.405, 0.0))
	# Upper arm
	_mi(_capsule(0.072, 0.330), _mat_armor, Vector3(x,  0.237, 0.0))
	# Elbow joint sphere
	_mi(_sphere(0.068), _mat_armor, Vector3(x,  0.068, 0.0))
	# Forearm (thinner)
	_mi(_capsule(0.058, 0.295), _mat_armor, Vector3(x, -0.073, 0.0))
	# Hand (slightly flattened sphere)
	_mi(_sphere(0.054), _mat_skin, Vector3(x, -0.235, 0.0), Vector3(0.88, 1.0, 0.68))

func _build_leg(side: float) -> void:
	var x := side * 0.118
	# Hip joint sphere
	_mi(_sphere(0.098), _mat_pants, Vector3(x, -0.062, 0.0))
	# Thigh
	_mi(_capsule(0.108, 0.355), _mat_pants, Vector3(x, -0.242, 0.0))
	# Knee joint sphere
	_mi(_sphere(0.090), _mat_pants, Vector3(x, -0.422, 0.0))
	# Calf – lofted (thicker in the middle, local y 0=ankle, top=knee)
	_mi(_loft([
		Vector3(0.070, 0.068, 0.000),
		Vector3(0.078, 0.075, 0.090),
		Vector3(0.092, 0.088, 0.190),   # widest point of calf
		Vector3(0.086, 0.082, 0.280),
		Vector3(0.088, 0.085, 0.345),   # knee connection
	], 12), _mat_pants, Vector3(x, -0.770, 0.0))
	# Boot (slightly wider in Z for toe shape)
	_mi(_loft([
		Vector3(0.085, 0.138, 0.000),
		Vector3(0.082, 0.130, 0.028),
		Vector3(0.078, 0.110, 0.062),
	], 12), _mat_boot, Vector3(x, -0.790, 0.018))

# ─── Mesh factories ───────────────────────────────────────────

func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r; s.height = r * 2.0
	s.radial_segments = 12; s.rings = 8
	return s

func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r; c.height = h
	c.radial_segments = 10; c.rings = 4
	return c

func _mi(mesh: Mesh, mat: Material, pos: Vector3,
		scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	if scl != Vector3.ONE:
		mi.scale = scl
	add_child(mi)
	all_meshes.append(mi)
	return mi

# ─── Lofted mesh ──────────────────────────────────────────────
# Generates a closed elliptical-cross-section surface.
# profile: Array of Vector3(half_width_x, half_depth_z, y_position)
func _loft(profile: Array, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()

	# Build a ring of vertices for each profile level
	var rings: Array = []
	for lv in n:
		var rx: float = profile[lv].x
		var rz: float = profile[lv].y
		var y:  float = profile[lv].z
		var ring: Array[Vector3] = []
		for s in sides:
			var a := TAU * float(s) / float(sides)
			ring.append(Vector3(cos(a) * rx, y, sin(a) * rz))
		rings.append(ring)

	# Quad strips between adjacent rings
	for lv in range(n - 1):
		for s in sides:
			var ns := (s + 1) % sides
			var v00: Vector3 = rings[lv][s]
			var v01: Vector3 = rings[lv][ns]
			var v10: Vector3 = rings[lv + 1][s]
			var v11: Vector3 = rings[lv + 1][ns]
			st.add_vertex(v00); st.add_vertex(v10); st.add_vertex(v01)
			st.add_vertex(v01); st.add_vertex(v10); st.add_vertex(v11)

	# Bottom cap
	var bot := Vector3(0.0, profile[0].z, 0.0)
	for s in sides:
		st.add_vertex(bot)
		st.add_vertex(rings[0][s])
		st.add_vertex(rings[0][(s + 1) % sides])

	# Top cap
	var top := Vector3(0.0, profile[n - 1].z, 0.0)
	for s in sides:
		st.add_vertex(top)
		st.add_vertex(rings[n - 1][(s + 1) % sides])
		st.add_vertex(rings[n - 1][s])

	st.generate_normals()
	return st.commit()
