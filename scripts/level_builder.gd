# level_builder.gd — parametric multi-zone arena builder.
#
# Builds ALL level geometry (ground, perimeter, compound, tower, flank routes,
# courtyard cover, lamps) procedurally in _ready(), plus the marker nodes the
# game systems consume:
#   - group "enemy_spawn"    : enemy spawn points (read by enemy_spawner)
#   - group "pickup_point"   : pickup spots         (read by pickup_spawner)
#   - group "tactical_points": tagged map landmarks (read by enemy_director)
#
# Geometry is StaticBody3D + CollisionShape3D + MeshInstance3D so the runtime
# NavMesh (parsed from STATIC COLLIDERS, see Main.tscn) bakes over it. The builder
# runs synchronously in _ready(); NavBaker bakes deferred, so geometry exists first.
#
# Compass: -Z = north, +Z = south, -X = west, +X = east. Player starts at origin
# (the courtyard), which is kept clear.
extends Node3D

const LADDER_SCRIPT := preload("res://scripts/ladder.gd")

# Heights of the two reachable high grounds. Both are > 5.0 so enemy.gd's
# perch logic (origin.y > 5.0) engages and they hold position instead of
# jumping off. Reachable surfaces must stay >= ~5.5.
const COMPOUND_FLOOR_Y := 5.5
const TOWER_FLOOR_Y := 7.5

var mat: Dictionary = {}

func _ready() -> void:
	_make_materials()
	_build_ground_and_perimeter()
	_build_compound()
	_build_tower()
	_build_east_alley()
	_build_south_lane()
	_build_courtyard_cover()
	_build_lamps()
	_place_enemy_spawns()
	_place_pickups()
	_place_tactical_points()

# ─── Materials ───────────────────────────────────────────────
func _make_materials() -> void:
	mat["grass"] = _mk(Color(0.28, 0.36, 0.22), 1.0, 0.0)
	mat["concrete"] = _mk(Color(0.72, 0.70, 0.66), 0.85, 0.0)
	mat["concrete_dark"] = _mk(Color(0.42, 0.42, 0.45), 0.78, 0.0)
	mat["metal"] = _mk(Color(0.30, 0.36, 0.42), 0.35, 0.7)
	mat["rust"] = _mk(Color(0.45, 0.28, 0.18), 0.7, 0.3)
	mat["tile"] = _mk(Color(0.84, 0.80, 0.72), 0.55, 0.0)
	mat["wood"] = _mk(Color(0.50, 0.32, 0.18), 0.9, 0.0)
	mat["brick"] = _mk(Color(0.52, 0.28, 0.22), 0.85, 0.0)

func _mk(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

# ─── Geometry helpers ────────────────────────────────────────
# Axis-aligned solid box (collision + mesh). Position is the box CENTER.
func _solid(p_name: String, center: Vector3, size: Vector3, mat_key: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = p_name
	var col := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = size
	col.shape = shp
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat.get(mat_key)
	mi.mesh = bm
	body.add_child(mi)
	body.position = center
	add_child(body)
	return body

# Sloped walkable ramp connecting two surface points (base → top). Width is the
# cross-axis. Built thin; the walkable top face passes through base/top.
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

	var body := StaticBody3D.new()
	body.name = p_name
	var col := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = Vector3(width, thick, length)
	col.shape = shp
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, thick, length)
	bm.material = mat.get(mat_key)
	mi.mesh = bm
	body.add_child(mi)
	body.transform = Transform3D(Basis(xb, yb, zb), center)
	add_child(body)

# Climbable ladder: an Area3D (ladder.gd) spanning ground→platform on the access
# face, plus two visual rails. Anyone with enter/exit_ladder climbs while inside.
func _ladder(p_name: String, area_center: Vector3, area_size: Vector3) -> void:
	var area := Area3D.new()
	area.name = p_name
	area.set_script(LADDER_SCRIPT)
	var col := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = area_size
	col.shape = shp
	area.add_child(col)
	area.position = area_center
	add_child(area)
	# Visual rails (no collision needed; cosmetic)
	var half := area_size.z * 0.5 - 0.1
	for off in [half, -half]:
		var rail := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, area_size.y, 0.1)
		bm.material = mat.get("wood")
		rail.mesh = bm
		rail.position = area_center + Vector3(0, 0, off)
		add_child(rail)

# ─── Markers ─────────────────────────────────────────────────
func _marker(group: String, pos: Vector3) -> Node3D:
	var m := Marker3D.new()
	m.position = pos
	add_child(m)
	m.add_to_group(group)
	return m

func _tactical(pos: Vector3, kind: String, zone: String, access: Vector3 = Vector3(1e30, 0, 0), climb: bool = false) -> void:
	var m := _marker("tactical_points", pos)
	m.set_meta("kind", kind)        # HIGH_GROUND | FLANK_ENTRY | CHOKE | OBJECTIVE
	m.set_meta("zone", zone)        # tower | compound | courtyard | alley | south
	m.set_meta("access", access)    # ground approach (ladder/ramp base) for HIGH_GROUND/OBJECTIVE
	m.set_meta("climb", climb)      # true → reached by ladder; false → walkable (ramp)

# ─── Ground & perimeter ──────────────────────────────────────
func _build_ground_and_perimeter() -> void:
	_solid("Ground", Vector3(0, -0.5, 0), Vector3(84, 1, 84), "grass")
	var h := 10.0
	_solid("WallN", Vector3(0, h * 0.5, -41), Vector3(84, h, 1), "concrete_dark")
	_solid("WallS", Vector3(0, h * 0.5, 41), Vector3(84, h, 1), "concrete_dark")
	_solid("WallE", Vector3(41, h * 0.5, 0), Vector3(1, h, 84), "concrete_dark")
	_solid("WallW", Vector3(-41, h * 0.5, 0), Vector3(1, h, 84), "concrete_dark")

# ─── Compound (north): raised fortress / high ground ─────────
# A bunker-pavilion: a 2F platform on pillars, reached by two ramps from the
# courtyard. Parapet cover with window gaps facing south. Strong sniping spot,
# but the two ramps are chokepoints the AI can contest.
func _build_compound() -> void:
	var cz := -28.0  # compound center Z
	# Upper platform (top surface at COMPOUND_FLOOR_Y)
	_solid("CompoundFloor", Vector3(0, COMPOUND_FLOOR_Y - 0.25, cz), Vector3(24, 0.5, 16), "concrete")
	# Support pillars (also ground-floor cover/chokepoints)
	for sx in [-10.0, 10.0]:
		for sz in [cz - 6.0, cz + 6.0]:
			_solid("CompPillar", Vector3(sx, COMPOUND_FLOOR_Y * 0.5, sz), Vector3(1.2, COMPOUND_FLOOR_Y, 1.2), "concrete_dark")
	# Two access ramps from courtyard up to the platform's south edge. Gentle
	# (~24°) and wide; base sinks slightly into the ground and the top overlaps the
	# platform so the NavMesh connects courtyard ↔ 2F. They land at X=±8, where the
	# south parapet is left open (see below) — those landings are the chokepoints.
	var south_edge := cz + 8.0   # = -20
	_ramp_between("CompRampE", Vector3(8, -0.05, south_edge + 11.0), Vector3(8, COMPOUND_FLOOR_Y, south_edge - 0.5), 5.0, "concrete")
	_ramp_between("CompRampW", Vector3(-8, -0.05, south_edge + 11.0), Vector3(-8, COMPOUND_FLOOR_Y, south_edge - 0.5), 5.0, "concrete")
	# Parapet cover on the platform (height 1.2 above floor). The south face keeps
	# only a central merlon (sniper cover with windows on each side); the X=±8 ramp
	# landings stay open so the platform is reachable.
	var py := COMPOUND_FLOOR_Y + 0.6
	_solid("ParapetN", Vector3(0, py, cz - 7.7), Vector3(24, 1.2, 0.5), "concrete")
	_solid("ParapetE", Vector3(11.7, py, cz), Vector3(0.5, 1.2, 16), "concrete")
	_solid("ParapetW", Vector3(-11.7, py, cz), Vector3(0.5, 1.2, 16), "concrete")
	_solid("ParapetS", Vector3(0, py, cz + 7.7), Vector3(10, 1.2, 0.5), "concrete")
	# Ground-floor cover slab pieces under the platform
	_solid("CompCoverA", Vector3(0, 0.85, cz - 2.0), Vector3(4, 1.7, 0.6), "rust")
	_solid("CompCoverB", Vector3(-4, 0.85, cz + 2.0), Vector3(0.6, 1.7, 4), "rust")

# ─── Tower (west): sniper high ground via ladder ─────────────
func _build_tower() -> void:
	var tx := -30.0
	var tz := -2.0
	# Platform (top at TOWER_FLOOR_Y)
	_solid("TowerFloor", Vector3(tx, TOWER_FLOOR_Y - 0.2, tz), Vector3(5, 0.4, 5), "concrete")
	# Legs
	for lx in [tx - 2.0, tx + 2.0]:
		for lz in [tz - 2.0, tz + 2.0]:
			_solid("TowerLeg", Vector3(lx, TOWER_FLOOR_Y * 0.5, lz), Vector3(0.5, TOWER_FLOOR_Y, 0.5), "metal")
	# Parapet cover on N/S/W edges; east (ladder side) left open
	var py := TOWER_FLOOR_Y + 0.5
	_solid("TowerParN", Vector3(tx, py, tz - 2.3), Vector3(5, 1.0, 0.4), "metal")
	_solid("TowerParS", Vector3(tx, py, tz + 2.3), Vector3(5, 1.0, 0.4), "metal")
	_solid("TowerParW", Vector3(tx - 2.3, py, tz), Vector3(0.4, 1.0, 5), "metal")
	# Ladder on the east (courtyard-facing) face
	var ladder_x := tx + 2.7   # just east of the platform east edge
	_ladder("TowerLadder", Vector3(ladder_x, TOWER_FLOOR_Y * 0.5 + 0.5, tz), Vector3(1.4, TOWER_FLOOR_Y + 1.0, 1.4))

# ─── East alley (flank route) ────────────────────────────────
# An inner screen wall hides the east lane from a courtyard player. Two gaps let
# enemies cross north↔south concealed, then emerge into the courtyard behind them.
func _build_east_alley() -> void:
	var x := 22.0
	var h := 4.0
	# Wall segments leaving gaps at Z in [-8,-4] and [10,16]
	_solid("AlleyW1", Vector3(x, h * 0.5, -19), Vector3(0.6, h, 22), "brick")  # Z[-30,-8]
	_solid("AlleyW2", Vector3(x, h * 0.5, 3), Vector3(0.6, h, 14), "brick")    # Z[-4,10]
	_solid("AlleyW3", Vector3(x, h * 0.5, 23), Vector3(0.6, h, 14), "brick")   # Z[16,30]
	# A little hard cover inside the lane
	_solid("AlleyCoverA", Vector3(30, 0.85, -10), Vector3(1.6, 1.7, 1.6), "rust")
	_solid("AlleyCoverB", Vector3(32, 0.85, 16), Vector3(1.6, 1.7, 1.6), "rust")

# ─── South lane (flank route) ────────────────────────────────
func _build_south_lane() -> void:
	var z := 24.0
	var h := 4.0
	# Wall segments leaving gaps at X in [-10,-6] and [8,14]
	_solid("SouthW1", Vector3(-22, h * 0.5, z), Vector3(24, h, 0.6), "brick")  # X[-34,-10]
	_solid("SouthW2", Vector3(-1, h * 0.5, z), Vector3(14, h, 0.6), "brick")   # X[-6,8]
	_solid("SouthW3", Vector3(24, h * 0.5, z), Vector3(20, h, 0.6), "brick")   # X[14,34]
	_solid("SouthCoverA", Vector3(-15, 0.85, 30), Vector3(1.6, 1.7, 1.6), "rust")
	_solid("SouthCoverB", Vector3(16, 0.85, 30), Vector3(1.6, 1.7, 1.6), "rust")

# ─── Courtyard cover (rusher killzone) ───────────────────────
func _build_courtyard_cover() -> void:
	# Crates (full-cover blocks)
	for c in [Vector3(-8, 0.9, -2), Vector3(8, 0.9, 2), Vector3(-3, 0.9, 10), Vector3(13, 0.9, 12), Vector3(-13, 0.9, 6)]:
		_solid("Crate", c, Vector3(1.8, 1.8, 1.8), "wood")
	# Low walls (lean-over cover)
	_solid("LowWallA", Vector3(0, 0.5, 6), Vector3(4, 1.0, 0.5), "concrete")
	_solid("LowWallB", Vector3(-6, 0.5, 16), Vector3(0.5, 1.0, 4), "concrete")
	_solid("LowWallC", Vector3(6, 0.5, -6), Vector3(4, 1.0, 0.5), "concrete")
	# Tall thin pillars (quick lateral cover)
	_solid("Pillar1", Vector3(3, 1.5, 2), Vector3(0.8, 3.0, 0.8), "concrete_dark")
	_solid("Pillar2", Vector3(-10, 1.5, 12), Vector3(0.8, 3.0, 0.8), "concrete_dark")
	# Central monument (mid-field landmark)
	_solid("Monument", Vector3(0, 0.8, -4), Vector3(3, 1.6, 3), "tile")

# ─── Lamps ───────────────────────────────────────────────────
func _build_lamps() -> void:
	for p in [Vector3(14, 4, 8), Vector3(-14, 4, 8), Vector3(14, 4, -12), Vector3(-14, 4, -12)]:
		_lamp(p, Color(1.0, 0.85, 0.6), 16.0, 2.0)
	_lamp(Vector3(0, 5, -28), Color(0.8, 0.85, 1.0), 18.0, 2.5)   # over compound
	_lamp(Vector3(-30, 9, -2), Color(0.7, 0.85, 1.0), 12.0, 3.0)  # over tower

func _lamp(pos: Vector3, color: Color, rng: float, energy: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.omni_range = rng
	l.light_energy = energy
	add_child(l)

# ─── Marker placement ────────────────────────────────────────
func _place_enemy_spawns() -> void:
	var pts := [
		Vector3(34, 0.5, -34), Vector3(34, 0.5, 34),   # east alley ends
		Vector3(0, 0.5, 38), Vector3(-34, 0.5, 36),    # south lane
		Vector3(-39, 0.5, -2), Vector3(-38, 0.5, 18),  # west / behind tower
		Vector3(0, 0.5, -39), Vector3(-10, 0.5, -38), Vector3(10, 0.5, -38),  # behind compound
		Vector3(38, 0.5, 0),                            # east mid
	]
	for p in pts:
		_marker("enemy_spawn", p)

func _place_pickups() -> void:
	var pts := [
		Vector3(-30, TOWER_FLOOR_Y + 0.2, -2),                 # tower top (sniper bait)
		Vector3(0, COMPOUND_FLOOR_Y + 0.2, -28), Vector3(8, COMPOUND_FLOOR_Y + 0.2, -24),  # compound 2F
		Vector3(0, 0.7, 4), Vector3(-10, 0.7, 0), Vector3(10, 0.7, 8), Vector3(0, 0.7, 16), # courtyard
		Vector3(30, 0.7, -10), Vector3(30, 0.7, 18), Vector3(30, 0.7, 2),                   # alley
		Vector3(-15, 0.7, 30), Vector3(15, 0.7, 30),           # south lane
		Vector3(-34, 0.7, 12), Vector3(-34, 0.7, -14),         # west
		Vector3(0, 0.7, -33),                                  # compound ground
		Vector3(36, 0.7, -36), Vector3(-36, 0.7, 36), Vector3(36, 0.7, 36),  # corners
	]
	for p in pts:
		_marker("pickup_point", p)

func _place_tactical_points() -> void:
	# High grounds. Tower is reached by ladder (climb=true → objective is its base);
	# the compound 2F is walkable up a ramp (climb=false → objective is the platform).
	_tactical(Vector3(-30, TOWER_FLOOR_Y, -2), "HIGH_GROUND", "tower", Vector3(-27, 0.5, -2), true)
	_tactical(Vector3(0, COMPOUND_FLOOR_Y, -28), "HIGH_GROUND", "compound", Vector3(8, 0.5, -12), false)
	# Objective (seize the tower) reuses the ladder base.
	_tactical(Vector3(-30, TOWER_FLOOR_Y, -2), "OBJECTIVE", "tower", Vector3(-27, 0.5, -2), true)
	# Flank entries: courtyard-side mouths of concealed routes
	_tactical(Vector3(20, 0.5, -6), "FLANK_ENTRY", "alley", Vector3(34, 0.5, -34))
	_tactical(Vector3(20, 0.5, 12), "FLANK_ENTRY", "alley", Vector3(34, 0.5, 34))
	_tactical(Vector3(-8, 0.5, 22), "FLANK_ENTRY", "south", Vector3(-34, 0.5, 36))
	_tactical(Vector3(10, 0.5, 22), "FLANK_ENTRY", "south", Vector3(0, 0.5, 38))
	_tactical(Vector3(-20, 0.5, 8), "FLANK_ENTRY", "west", Vector3(-38, 0.5, 18))
	_tactical(Vector3(0, 0.5, -19), "FLANK_ENTRY", "compound", Vector3(0, 0.5, -39))
	# Chokepoints
	_tactical(Vector3(-27, 0.5, -2), "CHOKE", "tower")
	_tactical(Vector3(8, 0.5, -14), "CHOKE", "compound")
	_tactical(Vector3(-8, 0.5, -14), "CHOKE", "compound")
