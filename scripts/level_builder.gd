# level_builder.gd — parametric tactical arena builder (compact redesign).
#
# Builds ALL level geometry procedurally in _ready(), plus the marker nodes the
# game systems consume:
#   - group "enemy_spawn"    : enemy spawn points (read by enemy_spawner)
#   - group "pickup_point"   : pickup spots         (read by pickup_spawner)
#   - group "tactical_points": tagged map landmarks (read by enemy_director)
#
# Geometry is StaticBody3D + CollisionShape3D + MeshInstance3D so the runtime
# NavMesh (parsed from STATIC COLLIDERS) bakes over it. Builder runs synchronously
# in _ready(); NavBaker bakes deferred, so geometry exists first.
#
# Layout: a COMPACT ~52x52 arena built for constant, readable fights —
#   • central courtyard hub (player start, deliberate cover lanes)
#   • The Keep: a close northern high ground over the courtyard, one ramp (choke)
#   • The Perch: a ladder tower at the south, long sightline across the courtyard
#   • two flank corridors hugging the courtyard (east/west) whose mouths let
#     enemies emerge behind a camped player.
# Compass: -Z north, +Z south, -X west, +X east. Player starts at origin.
extends Node3D

const LADDER_SCRIPT := preload("res://scripts/ladder.gd")

# Reachable high-ground surfaces. Both > 5.0 so enemy.gd perch logic engages.
const KEEP_FLOOR_Y := 5.5
const TOWER_FLOOR_Y := 7.0

var mat: Dictionary = {}

func _ready() -> void:
	_make_materials()
	_build_ground_and_perimeter()
	_build_keep()
	_build_tower()
	_build_flank_corridors()
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

# Sloped walkable ramp connecting two surface points (base → top).
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

# Climbable ladder: Area3D (ladder.gd) on the access face + two visual rails.
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
	m.set_meta("zone", zone)
	m.set_meta("access", access)    # ground approach (ladder/ramp base) used to reach it
	m.set_meta("climb", climb)      # true → reached by ladder; false → walkable (ramp)

# ─── Ground & perimeter ──────────────────────────────────────
func _build_ground_and_perimeter() -> void:
	_solid("Ground", Vector3(0, -0.5, 0), Vector3(56, 1, 56), "grass")
	var h := 8.0
	_solid("WallN", Vector3(0, h * 0.5, -26), Vector3(56, h, 1), "concrete_dark")
	_solid("WallS", Vector3(0, h * 0.5, 26), Vector3(56, h, 1), "concrete_dark")
	_solid("WallE", Vector3(26, h * 0.5, 0), Vector3(1, h, 56), "concrete_dark")
	_solid("WallW", Vector3(-26, h * 0.5, 0), Vector3(1, h, 56), "concrete_dark")

# ─── The Keep (north high ground, overlooks the courtyard) ───
# A raised bunker reached by ONE front ramp (the contested chokepoint). Parapet
# with a central merlon + window gaps facing the courtyard.
func _build_keep() -> void:
	var cz := -17.0
	_solid("KeepFloor", Vector3(0, KEEP_FLOOR_Y - 0.25, cz), Vector3(16, 0.5, 10), "concrete")
	for sx in [-6.0, 6.0]:
		for sz in [cz + 3.0, cz - 3.0]:
			_solid("KeepPillar", Vector3(sx, KEEP_FLOOR_Y * 0.5, sz), Vector3(1.2, KEEP_FLOOR_Y, 1.2), "concrete_dark")
	# Front ramp from courtyard up to the south edge (Z=-12), landing at X=5.
	_ramp_between("KeepRamp", Vector3(5, -0.05, -2.0), Vector3(5, KEEP_FLOOR_Y, -12.5), 5.0, "concrete")
	# Parapet (1.2 above floor). South keeps only a central merlon; the X=5 ramp
	# landing stays open.
	var py := KEEP_FLOOR_Y + 0.6
	_solid("KeepParN", Vector3(0, py, cz - 4.7), Vector3(16, 1.2, 0.5), "concrete")
	_solid("KeepParE", Vector3(7.7, py, cz), Vector3(0.5, 1.2, 10), "concrete")
	_solid("KeepParW", Vector3(-7.7, py, cz), Vector3(0.5, 1.2, 10), "concrete")
	_solid("KeepParS", Vector3(0, py, cz + 4.7), Vector3(6, 1.2, 0.5), "concrete")
	# Ground-floor cover under the platform.
	_solid("KeepCoverA", Vector3(0, 0.85, cz + 1.0), Vector3(4, 1.7, 0.6), "rust")
	_solid("KeepCoverB", Vector3(-4, 0.85, cz - 2.0), Vector3(0.6, 1.7, 4), "rust")

# ─── The Perch (south ladder tower, long courtyard sightline) ─
func _build_tower() -> void:
	var tx := -12.0
	var tz := 19.0
	_solid("TowerFloor", Vector3(tx, TOWER_FLOOR_Y - 0.2, tz), Vector3(4.5, 0.4, 4.5), "concrete")
	for lx in [tx - 1.8, tx + 1.8]:
		for lz in [tz - 1.8, tz + 1.8]:
			_solid("TowerLeg", Vector3(lx, TOWER_FLOOR_Y * 0.5, lz), Vector3(0.5, TOWER_FLOOR_Y, 0.5), "metal")
	var py := TOWER_FLOOR_Y + 0.5
	_solid("TowerParS", Vector3(tx, py, tz + 2.05), Vector3(4.5, 1.0, 0.4), "metal")
	_solid("TowerParE", Vector3(tx + 2.05, py, tz), Vector3(0.4, 1.0, 4.5), "metal")
	_solid("TowerParW", Vector3(tx - 2.05, py, tz), Vector3(0.4, 1.0, 4.5), "metal")
	# Ladder on the north face (toward the courtyard).
	_ladder("TowerLadder", Vector3(tx, TOWER_FLOOR_Y * 0.5 + 0.5, tz - 2.7), Vector3(1.4, TOWER_FLOOR_Y + 1.0, 1.4))

# ─── Flank corridors (hug the courtyard, mouths feed behind player) ──
func _build_flank_corridors() -> void:
	var h := 4.0
	# West screen wall at X=-16, gaps at Z[-6,-2] and Z[10,14].
	_solid("WAlleyA", Vector3(-16, h * 0.5, -15), Vector3(0.6, h, 18), "brick")  # Z[-24,-6]
	_solid("WAlleyB", Vector3(-16, h * 0.5, 4), Vector3(0.6, h, 12), "brick")    # Z[-2,10]
	_solid("WAlleyC", Vector3(-16, h * 0.5, 19), Vector3(0.6, h, 10), "brick")   # Z[14,24]
	_solid("WAlleyCrate", Vector3(-21, 0.9, 0), Vector3(1.6, 1.8, 1.6), "rust")
	# East screen wall at X=16 (mirror).
	_solid("EAlleyA", Vector3(16, h * 0.5, -15), Vector3(0.6, h, 18), "brick")
	_solid("EAlleyB", Vector3(16, h * 0.5, 4), Vector3(0.6, h, 12), "brick")
	_solid("EAlleyC", Vector3(16, h * 0.5, 19), Vector3(0.6, h, 10), "brick")
	_solid("EAlleyCrate", Vector3(21, 0.9, 0), Vector3(1.6, 1.8, 1.6), "rust")

# ─── Courtyard cover (intentional lanes, not scatter) ────────
func _build_courtyard_cover() -> void:
	# Two crate chevrons framing the central lane (full cover).
	for c in [Vector3(-7, 0.9, -2), Vector3(-9, 0.9, 1), Vector3(-7, 0.9, 4)]:
		_solid("CrateW", c, Vector3(1.8, 1.8, 1.8), "wood")
	for c in [Vector3(7, 0.9, -2), Vector3(9, 0.9, 1), Vector3(7, 0.9, 4)]:
		_solid("CrateE", c, Vector3(1.8, 1.8, 1.8), "wood")
	# Low firing walls (lean-over cover) forming lanes.
	_solid("LowN", Vector3(0, 0.5, -6), Vector3(5, 1.0, 0.5), "concrete")     # faces the keep
	_solid("LowSW", Vector3(-4, 0.5, 11), Vector3(0.5, 1.0, 5), "concrete")
	_solid("LowSE", Vector3(4, 0.5, 11), Vector3(0.5, 1.0, 5), "concrete")
	# Tall pillars flanking the central lane.
	_solid("PillarL", Vector3(-3, 1.5, 3), Vector3(0.8, 3.0, 0.8), "concrete_dark")
	_solid("PillarR", Vector3(3, 1.5, 3), Vector3(0.8, 3.0, 0.8), "concrete_dark")
	# Central monument (sightline break; origin stays clear).
	_solid("Monument", Vector3(0, 0.8, 8), Vector3(3, 1.6, 3), "tile")
	# Cover anchoring each flank mouth so emerging fights have something to hold.
	_solid("MouthW", Vector3(-12, 0.9, 8), Vector3(1.6, 1.8, 1.6), "wood")
	_solid("MouthE", Vector3(12, 0.9, 8), Vector3(1.6, 1.8, 1.6), "wood")

# ─── Lamps ───────────────────────────────────────────────────
func _build_lamps() -> void:
	for p in [Vector3(10, 4, 6), Vector3(-10, 4, 6), Vector3(10, 4, -10), Vector3(-10, 4, -10)]:
		_lamp(p, Color(1.0, 0.85, 0.6), 15.0, 2.0)
	_lamp(Vector3(0, 5, -17), Color(0.8, 0.85, 1.0), 14.0, 2.5)   # over the keep
	_lamp(Vector3(-12, 8, 19), Color(0.7, 0.85, 1.0), 11.0, 3.0)  # over the tower

func _lamp(pos: Vector3, color: Color, rng: float, energy: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.omni_range = rng
	l.light_energy = energy
	add_child(l)

# ─── Marker placement ────────────────────────────────────────
func _place_enemy_spawns() -> void:
	# All ~22-26m from origin so the first wave engages in ~5-6s; the alley-end
	# spawns feed the flank corridors.
	var pts := [
		Vector3(-22, 0.5, -22), Vector3(-22, 0.5, 22),   # west corridor ends
		Vector3(22, 0.5, -22), Vector3(22, 0.5, 22),      # east corridor ends
		Vector3(0, 0.5, -24), Vector3(-6, 0.5, -24),      # behind the keep
		Vector3(-24, 0.5, 2), Vector3(24, 0.5, 2),        # perimeter mid
	]
	for p in pts:
		_marker("enemy_spawn", p)

func _place_pickups() -> void:
	var pts := [
		Vector3(0, 0.7, 8), Vector3(-8, 0.7, -2), Vector3(8, 0.7, 2),   # courtyard
		Vector3(0, KEEP_FLOOR_Y + 0.2, -17), Vector3(5, KEEP_FLOOR_Y + 0.2, -19),  # keep 2F
		Vector3(-12, TOWER_FLOOR_Y + 0.2, 19),                          # tower top
		Vector3(-21, 0.7, -10), Vector3(-21, 0.7, 14),                  # west corridor
		Vector3(21, 0.7, -10), Vector3(21, 0.7, 14),                    # east corridor
		Vector3(0, 0.7, -22),                                           # behind keep
		Vector3(8, 0.7, 22),                                            # south
	]
	for p in pts:
		_marker("pickup_point", p)

func _place_tactical_points() -> void:
	# High grounds. Keep = walkable ramp (objective is the platform); Tower =
	# ladder (objective is its base).
	_tactical(Vector3(0, KEEP_FLOOR_Y, -17), "HIGH_GROUND", "keep", Vector3(5, 0.5, -2), false)
	_tactical(Vector3(-12, TOWER_FLOOR_Y, 19), "HIGH_GROUND", "tower", Vector3(-12, 0.5, 15), true)
	_tactical(Vector3(-12, TOWER_FLOOR_Y, 19), "OBJECTIVE", "tower", Vector3(-12, 0.5, 15), true)
	# Flank entries: courtyard-side mouths of the concealed corridors; access =
	# the corridor's far (spawn) end so the picked enemy routes through the lane.
	_tactical(Vector3(-15, 0.5, -4), "FLANK_ENTRY", "west", Vector3(-22, 0.5, -22))
	_tactical(Vector3(-15, 0.5, 12), "FLANK_ENTRY", "west", Vector3(-22, 0.5, 22))
	_tactical(Vector3(15, 0.5, -4), "FLANK_ENTRY", "east", Vector3(22, 0.5, -22))
	_tactical(Vector3(15, 0.5, 12), "FLANK_ENTRY", "east", Vector3(22, 0.5, 22))
	_tactical(Vector3(0, 0.5, -11), "FLANK_ENTRY", "keep", Vector3(0, 0.5, -24))
	# Chokepoints
	_tactical(Vector3(5, 0.5, -2), "CHOKE", "keep")
	_tactical(Vector3(-12, 0.5, 15), "CHOKE", "tower")
