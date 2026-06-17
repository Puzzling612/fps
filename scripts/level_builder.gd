# level_builder.gd — parametric URBAN tactical arena (PUBG-style interiors).
#
# Builds ALL level geometry in _ready() + the marker nodes the game reads:
#   - group "enemy_spawn"    : enemy spawn points   (enemy_spawner)
#   - group "pickup_point"   : pickup spots          (pickup_spawner)
#   - group "tactical_points": tagged landmarks      (enemy_director)
# Geometry = StaticBody3D + CollisionShape3D + MeshInstance3D so the runtime
# NavMesh (parsed from STATIC COLLIDERS) bakes over it. Builder runs synchronously
# in _ready(); NavBaker bakes deferred, so geometry exists first.
#
# Layout: a ~68x68 urban block — central plaza, two crossing avenues, four
# quadrant buildings, perimeter ring/alleys. Two HERO buildings have real PUBG
# interiors: multiple rooms (doorways), windows (shoot/peek ports), and an
# interior ramp up to a 2F loft (perch high ground). Enemies enter via the doors
# and climb the interior ramp to contest the loft, exactly like the player.
# Compass: -Z north, +Z south, -X west, +X east. Player starts at origin.
extends Node3D

const LADDER_SCRIPT := preload("res://scripts/ladder.gd")
const LOFT_Y := 5.5          # 2F loft surface (>5.0 → enemy perch logic engages)
const WALL_H := 5.0          # building exterior/interior wall height (loft sits above)

var mat: Dictionary = {}
# Per-material SurfaceTool buffers. Every visual box is appended here and the whole
# map is committed to ONE MeshInstance3D per material (~8 draw calls instead of
# ~50). Collision stays as individual StaticBody3D boxes, so navigation/physics/
# bullet hits are unchanged — only the rendering is batched.
var _surf: Dictionary = {}

func _ready() -> void:
	_make_materials()
	_build_ground_and_perimeter()
	_build_avenues()
	_hero_building(-19.0, -19.0, "nw")   # NW apartments (loft high ground)
	_hero_building(19.0, 19.0, "se")     # SE office (loft high ground)
	_shed(19.0, -19.0)                   # NE warehouse (clear/cover)
	_shed(-19.0, 19.0)                   # SW market (clear/cover)
	_build_plaza_cover()
	_build_street_cover()
	_build_lamps()
	_commit_meshes()        # batch all visual geometry into per-material meshes
	_place_enemy_spawns()
	_place_pickups()
	_place_tactical_points()
	_apply_mobile_perf()    # cheaper rendering on touch devices (desktop unchanged)

# ─── Materials ───────────────────────────────────────────────
func _make_materials() -> void:
	mat["grass"] = _mk(Color(0.28, 0.36, 0.22), 1.0, 0.0)
	mat["road"] = _mk(Color(0.30, 0.30, 0.33), 0.95, 0.0)
	mat["concrete"] = _mk(Color(0.72, 0.70, 0.66), 0.85, 0.0)
	mat["concrete_dark"] = _mk(Color(0.42, 0.42, 0.45), 0.78, 0.0)
	mat["metal"] = _mk(Color(0.30, 0.36, 0.42), 0.35, 0.7)
	mat["rust"] = _mk(Color(0.45, 0.28, 0.18), 0.7, 0.3)
	mat["tile"] = _mk(Color(0.84, 0.80, 0.72), 0.55, 0.0)
	mat["wood"] = _mk(Color(0.50, 0.32, 0.18), 0.9, 0.0)
	mat["brick"] = _mk(Color(0.52, 0.28, 0.22), 0.85, 0.0)
	mat["brick2"] = _mk(Color(0.46, 0.42, 0.38), 0.85, 0.0)

func _mk(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

# ─── Geometry helpers ────────────────────────────────────────
# Collision body (no per-box MeshInstance — the visual box is batched via _mesh_box).
func _solid(p_name: String, center: Vector3, size: Vector3, mat_key: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = p_name
	var col := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = size
	col.shape = shp
	body.add_child(col)
	body.position = center
	add_child(body)
	_mesh_box(mat_key, Transform3D(Basis(), center), size)
	return body

# Append a box's visual geometry into the per-material batch.
func _mesh_box(mat_key: String, xform: Transform3D, size: Vector3) -> void:
	var st: SurfaceTool = _surf.get(mat_key)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surf[mat_key] = st
	var bm := BoxMesh.new()
	bm.size = size
	st.append_from(bm, 0, xform)

# Commit every per-material batch to a single MeshInstance3D.
func _commit_meshes() -> void:
	for key in _surf.keys():
		var st: SurfaceTool = _surf[key]
		st.set_material(mat.get(key))
		var mi := MeshInstance3D.new()
		mi.name = "Merged_" + key
		mi.mesh = st.commit()
		add_child(mi)
	_surf.clear()

# Visual-only flat quad (no collision; batched like everything else).
func _decal(p_name: String, center: Vector3, size: Vector3, mat_key: String) -> void:
	_mesh_box(mat_key, Transform3D(Basis(), center), size)

# Wall along an axis with doorway gaps left open.
# axis "x": wall varies along X at fixed Z. axis "z": varies along Z at fixed X.
# gaps: Array[Vector2(gap_lo, gap_hi)] in axis coords (sorted, within [lo,hi]).
func _wall_with_gaps(p_name: String, axis: String, fixed: float, lo: float, hi: float, gaps: Array, h: float, mat_key: String, thick: float = 0.4) -> void:
	var edges: Array = [lo]
	for g in gaps:
		edges.append(g.x)
		edges.append(g.y)
	edges.append(hi)
	var i := 0
	while i + 1 < edges.size():
		var a: float = edges[i]
		var b: float = edges[i + 1]
		if b - a > 0.05:
			var c := (a + b) * 0.5
			var l := b - a
			if axis == "x":
				_solid(p_name, Vector3(c, h * 0.5, fixed), Vector3(l, h, thick), mat_key)
			else:
				_solid(p_name, Vector3(fixed, h * 0.5, c), Vector3(thick, h, l), mat_key)
		i += 2

# Wall with a continuous horizontal window slot: solid sill (0..1.0) + header
# (2.2..h). The Y[1.0,2.2] gap passes bullets/sightlines; the 1.0 sill (> nav
# max_climb 0.6) blocks walking — so windows are firing ports, not passages.
func _window_wall(p_name: String, axis: String, fixed: float, lo: float, hi: float, h: float, mat_key: String, thick: float = 0.4) -> void:
	var c := (lo + hi) * 0.5
	var l := hi - lo
	var sill := 1.0
	var lintel := 2.2
	if axis == "x":
		_solid(p_name, Vector3(c, sill * 0.5, fixed), Vector3(l, sill, thick), mat_key)
		_solid(p_name, Vector3(c, (lintel + h) * 0.5, fixed), Vector3(l, h - lintel, thick), mat_key)
	else:
		_solid(p_name, Vector3(fixed, sill * 0.5, c), Vector3(thick, sill, l), mat_key)
		_solid(p_name, Vector3(fixed, (lintel + h) * 0.5, c), Vector3(thick, h - lintel, l), mat_key)

# Sloped walkable ramp connecting base → top.
func _ramp_between(p_name: String, base: Vector3, top: Vector3, width: float, mat_key: String) -> void:
	var delta := top - base
	var length := delta.length()
	if length < 0.01:
		return
	var thick := 0.4
	var zb := delta.normalized()
	var xb := Vector3.UP.cross(zb)
	if xb.length() < 0.001:
		xb = Vector3.RIGHT
	xb = xb.normalized()
	var yb := zb.cross(xb).normalized()
	var center := (base + top) * 0.5 - yb * (thick * 0.5)
	var xform := Transform3D(Basis(xb, yb, zb), center)
	var body := StaticBody3D.new()
	body.name = p_name
	var col := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = Vector3(width, thick, length)
	col.shape = shp
	body.add_child(col)
	body.transform = xform
	add_child(body)
	_mesh_box(mat_key, xform, Vector3(width, thick, length))

# ─── Markers ─────────────────────────────────────────────────
func _marker(group: String, pos: Vector3) -> Node3D:
	var m := Marker3D.new()
	m.position = pos
	add_child(m)
	m.add_to_group(group)
	return m

func _tactical(pos: Vector3, kind: String, zone: String, access: Vector3 = Vector3(1e30, 0, 0), climb: bool = false) -> void:
	var m := _marker("tactical_points", pos)
	m.set_meta("kind", kind)
	m.set_meta("zone", zone)
	m.set_meta("access", access)
	m.set_meta("climb", climb)

# ─── Ground / perimeter / avenues ────────────────────────────
func _build_ground_and_perimeter() -> void:
	_solid("Ground", Vector3(0, -0.5, 0), Vector3(72, 1, 72), "grass")
	var h := 9.0
	_solid("WallN", Vector3(0, h * 0.5, -34), Vector3(72, h, 1), "concrete_dark")
	_solid("WallS", Vector3(0, h * 0.5, 34), Vector3(72, h, 1), "concrete_dark")
	_solid("WallE", Vector3(34, h * 0.5, 0), Vector3(1, h, 72), "concrete_dark")
	_solid("WallW", Vector3(-34, h * 0.5, 0), Vector3(1, h, 72), "concrete_dark")

func _build_avenues() -> void:
	# Visual road strips for readable flow (flush to ground).
	_decal("AveNS", Vector3(0, 0.02, 0), Vector3(11, 0.04, 68), "road")
	_decal("AveEW", Vector3(0, 0.02, 0), Vector3(68, 0.04, 11), "road")

# ─── HERO building (PUBG-style: rooms, windows, interior ramp → 2F loft) ──
func _hero_building(cx: float, cz: float, _zone: String) -> void:
	var hx := 8.0
	var hz := 7.0
	var x0 := cx - hx
	var x1 := cx + hx
	var z0 := cz - hz
	var z1 := cz + hz
	# Exterior walls (h=WALL_H). Doors on S/E/W (multi-entry), windows on N.
	_wall_with_gaps("HB_S", "x", z1, x0, x1, [Vector2(cx - 1.75, cx + 1.75)], WALL_H, "brick")
	_wall_with_gaps("HB_E", "z", x1, z0, z1, [Vector2(cz - 1.75, cz + 1.75)], WALL_H, "brick")
	_wall_with_gaps("HB_W", "z", x0, z0, z1, [Vector2(cz - 1.75, cz + 1.75)], WALL_H, "brick")
	_window_wall("HB_N", "x", z0, x0, x1, WALL_H, "brick")
	# Interior wall splitting N/S rooms; CENTER doorway aligned with the central ramp.
	_wall_with_gaps("HB_Int", "x", cz, x0, x1, [Vector2(cx - 2.5, cx + 2.5)], WALL_H, "brick2")
	# Ground-floor cover (room clearing), kept off the central ramp lane.
	_solid("HB_CoverN", Vector3(cx + 5, 0.9, cz - 4), Vector3(1.6, 1.8, 1.6), "wood")
	_solid("HB_CoverS", Vector3(cx + 4, 0.5, cz + 3), Vector3(3, 1.0, 0.5), "rust")
	# Interior ramp up the building's CENTER axis (X=cx): the S door, ramp and 2F
	# loft are all aligned, with 8m clear to the E/W walls — so the nav agent walks
	# straight in and up without snagging a wall corner.
	_ramp_between("HB_Ramp", Vector3(cx, 0.0, cz + 4), Vector3(cx, LOFT_Y, cz - 3), 3.5, "concrete")
	# 2F loft (north side, centered, 8×4), above the 5.0 walls → sightlines over the
	# street. Parapet on N (street) + E/W edges; S edge open where the ramp lands.
	_solid("HB_Loft", Vector3(cx, LOFT_Y - 0.2, cz - 5), Vector3(8, 0.4, 4), "concrete")
	_solid("HB_LoftParN", Vector3(cx, LOFT_Y + 0.5, cz - 7), Vector3(8, 1.0, 0.4), "metal")
	_solid("HB_LoftParE", Vector3(cx + 4, LOFT_Y + 0.5, cz - 5), Vector3(0.4, 1.0, 4), "metal")
	_solid("HB_LoftParW", Vector3(cx - 4, LOFT_Y + 0.5, cz - 5), Vector3(0.4, 1.0, 4), "metal")

# ─── SHED (single-story clear/cover space, multi-entry, open top) ────────
func _shed(cx: float, cz: float) -> void:
	var hx := 8.0
	var hz := 7.0
	var x0 := cx - hx
	var x1 := cx + hx
	var z0 := cz - hz
	var z1 := cz + hz
	var h := 4.0
	# Doors on the two plaza-facing sides; windows on the outer two.
	var south_door := [Vector2(cx - 2.0, cx + 2.0)]
	var west_door := [Vector2(cz - 2.0, cz + 2.0)]
	_wall_with_gaps("SH_S", "x", z1, x0, x1, south_door, h, "brick2")
	_wall_with_gaps("SH_W", "z", x0, z0, z1, west_door, h, "brick2")
	_window_wall("SH_N", "x", z0, x0, x1, h, "brick2")
	_window_wall("SH_E", "z", x1, z0, z1, h, "brick2")
	# Interior shelving / stalls as cover.
	_solid("SH_Shelf1", Vector3(cx - 2, 0.9, cz - 3), Vector3(5, 1.8, 0.6), "wood")
	_solid("SH_Shelf2", Vector3(cx + 3, 0.9, cz + 1), Vector3(0.6, 1.8, 5), "wood")
	_solid("SH_Crate", Vector3(cx - 3, 0.75, cz + 3), Vector3(1.5, 1.5, 1.5), "rust")

# ─── Plaza & street cover (cover-to-cover) ───────────────────
func _build_plaza_cover() -> void:
	_solid("Kiosk", Vector3(0, 1.25, 3), Vector3(3, 2.5, 3), "tile")        # central sightline break
	_solid("PlanterA", Vector3(-5, 0.5, -2), Vector3(3, 1.0, 1.2), "concrete")
	_solid("PlanterB", Vector3(5, 0.5, 4), Vector3(3, 1.0, 1.2), "concrete")
	_solid("PlazaCrate1", Vector3(-3, 0.75, 6), Vector3(1.5, 1.5, 1.5), "wood")
	_solid("PlazaCrate2", Vector3(4, 0.75, -4), Vector3(1.5, 1.5, 1.5), "wood")

func _build_street_cover() -> void:
	# Staggered cover along the avenues for cover-to-cover advances.
	var spots := [
		Vector3(0, 0.5, -16), Vector3(-3, 0.75, -22), Vector3(3, 0.5, -28),     # N avenue
		Vector3(0, 0.5, 16), Vector3(3, 0.75, 22), Vector3(-3, 0.5, 28),        # S avenue
		Vector3(-16, 0.5, 0), Vector3(-22, 0.75, 3), Vector3(-28, 0.5, -3),     # W avenue
		Vector3(16, 0.5, 0), Vector3(22, 0.75, -3), Vector3(28, 0.5, 3),        # E avenue
	]
	var i := 0
	for s in spots:
		if int(s.y * 100) == 75:   # the y=0.75 ones are crates (full cover)
			_solid("StCrate%d" % i, s, Vector3(1.5, 1.5, 1.5), "rust")
		else:                       # y=0.5 ones are low walls (lean-over)
			var sz := Vector3(3.5, 1.0, 0.5) if absf(s.x) < absf(s.z) else Vector3(0.5, 1.0, 3.5)
			_solid("StWall%d" % i, s, sz, "concrete")
		i += 1

# ─── Lamps ───────────────────────────────────────────────────
# Kept to 4 fill lights (was 6) — each real-time light costs in GL Compatibility.
func _build_lamps() -> void:
	for p in [Vector3(10, 5, 10), Vector3(-10, 5, 10), Vector3(10, 5, -10), Vector3(-10, 5, -10)]:
		_lamp(p, Color(1.0, 0.85, 0.6), 18.0, 2.0)

func _lamp(pos: Vector3, color: Color, rng: float, energy: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.omni_range = rng
	l.light_energy = energy
	add_child(l)

# ─── Mobile perf (touch devices only; desktop quality unchanged) ─────────────
func _apply_mobile_perf() -> void:
	if not GameManager.touch_mode:
		return
	# Render 3D at ~0.67 resolution then upscale — the biggest win on high-DPI phones.
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 0.67
	var main := get_parent()
	if main == null:
		return
	# Drop the full-screen glow pass and the directional shadow map (both heavy on
	# mobile GPUs); keep them on desktop.
	var we := main.get_node_or_null("WorldEnvironment")
	if we and we.environment:
		we.environment.glow_enabled = false
	var dl := main.get_node_or_null("DirectionalLight3D")
	if dl:
		dl.shadow_enabled = false

# ─── Marker placement ────────────────────────────────────────
func _place_enemy_spawns() -> void:
	var pts := [
		Vector3(0, 0.5, -32), Vector3(0, 0.5, 32),       # N/S avenue ends
		Vector3(-32, 0.5, 0), Vector3(32, 0.5, 0),        # W/E avenue ends
		Vector3(-16, 0.5, -32), Vector3(16, 0.5, -32),    # north alley mouths
		Vector3(-16, 0.5, 32), Vector3(16, 0.5, 32),      # south alley mouths
		Vector3(-32, 0.5, 16), Vector3(32, 0.5, -16),     # ring road
	]
	for p in pts:
		_marker("enemy_spawn", p)

func _place_pickups() -> void:
	var pts := [
		Vector3(0, 0.7, 6), Vector3(-6, 0.7, -3), Vector3(6, 0.7, 3),     # plaza
		Vector3(-19, LOFT_Y + 0.2, -24), Vector3(19, LOFT_Y + 0.2, 14),  # hero lofts (centered on north side)
		Vector3(-19, 0.7, -16), Vector3(19, 0.7, 16),                    # hero interiors
		Vector3(19, 0.7, -19), Vector3(-19, 0.7, 19),                    # shed interiors
		Vector3(0, 0.7, -24), Vector3(0, 0.7, 24),                       # avenues
		Vector3(-28, 0.7, 0), Vector3(28, 0.7, 0),                       # avenue ends
		Vector3(-30, 0.7, -30),                                          # ring corner
	]
	for p in pts:
		_marker("pickup_point", p)

func _place_tactical_points() -> void:
	# Hero lofts = high grounds reached by the interior ramp (walkable → climb=false,
	# objective is the loft point; nav routes door→room→ramp→loft). access = in
	# front of the building's south door.
	_tactical(Vector3(-19, LOFT_Y, -24), "HIGH_GROUND", "nw", Vector3(-19, 0.5, -10), false)
	_tactical(Vector3(19, LOFT_Y, 14), "HIGH_GROUND", "se", Vector3(19, 0.5, 10), false)
	_tactical(Vector3(-19, LOFT_Y, -24), "OBJECTIVE", "nw", Vector3(-19, 0.5, -10), false)
	# Flank entries: building side doors + alley mouths near the plaza. access =
	# a far point so the picked enemy routes the long concealed way around.
	_tactical(Vector3(-11, 0.5, -19), "FLANK_ENTRY", "nw", Vector3(-32, 0.5, 0))   # NW east door
	_tactical(Vector3(11, 0.5, 19), "FLANK_ENTRY", "se", Vector3(32, 0.5, 0))      # SE west door
	_tactical(Vector3(11, 0.5, -19), "FLANK_ENTRY", "ne", Vector3(32, 0.5, 0))     # NE west door
	_tactical(Vector3(-11, 0.5, 19), "FLANK_ENTRY", "sw", Vector3(-32, 0.5, 0))    # SW east door
	_tactical(Vector3(0, 0.5, -14), "FLANK_ENTRY", "north", Vector3(0, 0.5, -32))  # north avenue
	_tactical(Vector3(0, 0.5, 14), "FLANK_ENTRY", "south", Vector3(0, 0.5, 32))    # south avenue
	# Chokepoints
	_tactical(Vector3(-19, 0.5, -12), "CHOKE", "nw")
	_tactical(Vector3(19, 0.5, 12), "CHOKE", "se")
