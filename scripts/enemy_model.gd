# Mixamo-rigged enemy model.
# Instances one skinned skeleton (Rifle Run.fbx) and merges every Mixamo clip
# into a single AnimationPlayer so enemy.gd can drive walk / run / aim / melee /
# death from the AI state. A rifle mesh is attached to the right-hand bone.
#
# Attach to a Node3D named "Model" inside the Enemy scene.

extends Node3D

# Base provides the visible mesh + skeleton (imported at root_scale 90 → ~1.7 m).
const BASE_FBX := "res://assets/Rifle Run.fbx"

# clip key → source FBX. All share the same 33-bone Mixamo rig, so the single
# "mixamo_com" clip in each file can be retargeted onto the base skeleton.
const SOURCES := {
	"walk":   "res://assets/Walking.fbx",
	"run":    "res://assets/Rifle Run.fbx",
	"aim":    "res://assets/Firing Rifle.fbx",
	"strafe": "res://assets/Rifle Side Step.fbx",
	"melee":  "res://assets/Stabbing.fbx",
	"death":  "res://assets/Rifle Death.fbx",
}
const LOOPED := ["walk", "run", "aim", "strafe"]
# The death clip lies still after collapsing; play it faster so the fall reads
# quickly and the body can be removed soon after.
const DEATH_SPEED := 1.6
const SOURCE_CLIP := "mixamo_com"
const HAND_BONE := "mixamorig_RightHand"

# Speed thresholds (m/s) for picking the locomotion clip.
const RUN_SPEED := 4.6
const MOVE_SPEED := 0.3

var all_meshes: Array[MeshInstance3D] = []

var _anim: AnimationPlayer
var _skel: Skeleton3D
var _weapon_holder: Node3D = null   # gun meshes live here, parented to the hand
var _weapon_kind := "rifle"         # rifle | shotgun | sniper
var _locomotion := "aim"   # looping base state (walk/run/aim)
var _busy := false         # a one-shot (melee) is playing
var _dead := false

func _ready() -> void:
	var base: Node3D = (load(BASE_FBX) as PackedScene).instantiate()
	add_child(base)
	_skel = base.get_node("Skeleton3D")
	_anim = base.get_node("AnimationPlayer")
	_collect_meshes(base)

	# Merge every clip into one library under friendly names.
	var lib := AnimationLibrary.new()
	for key in SOURCES:
		var clip := _load_clip(SOURCES[key])
		if clip == null:
			continue
		clip.loop_mode = Animation.LOOP_LINEAR if key in LOOPED else Animation.LOOP_NONE
		lib.add_animation(key, clip)
	_anim.add_animation_library("e", lib)

	# Strip the Hips world translation so clips animate in place — enemy.gd moves
	# the body via velocity; otherwise the character would slide/snap each loop.
	_anim.root_motion_track = NodePath("Skeleton3D:" + "mixamorig_Hips")
	_anim.animation_finished.connect(_on_anim_finished)

	_attach_rifle()
	_play("aim")

func _load_clip(path: String) -> Animation:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate()
	var ap: AnimationPlayer = inst.get_node_or_null("AnimationPlayer")
	var clip: Animation = null
	if ap and ap.has_animation(SOURCE_CLIP):
		clip = ap.get_animation(SOURCE_CLIP).duplicate()
	inst.queue_free()
	return clip

func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		all_meshes.append(node)
	for c in node.get_children():
		_collect_meshes(c)

# ─── Held weapon ──────────────────────────────────────────────
func _attach_rifle() -> void:
	var bone := _skel.find_bone(HAND_BONE)
	if bone < 0:
		return
	var attach := BoneAttachment3D.new()
	attach.bone_name = HAND_BONE
	_skel.add_child(attach)

	_weapon_holder = Node3D.new()
	attach.add_child(_weapon_holder)
	# Sits in the palm; tuned by eye — adjust if the weapon floats off the hand.
	_weapon_holder.position = Vector3(0.0, 0.02, 0.0)
	_weapon_holder.rotation_degrees = Vector3(0, 90, 0)
	_build_weapon(_weapon_kind)

# Swap the held weapon mesh. kind: "rifle" | "shotgun" | "sniper".
func set_weapon(kind: String) -> void:
	_weapon_kind = kind
	if _weapon_holder:
		_build_weapon(kind)

func _mat(c: Color, m: float, r: float) -> StandardMaterial3D:
	var sm := StandardMaterial3D.new()
	sm.albedo_color = c; sm.metallic = m; sm.roughness = r
	return sm

func _gun_mesh(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh; mi.material_override = mat; mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = rot
	_weapon_holder.add_child(mi)

func _build_weapon(kind: String) -> void:
	for c in _weapon_holder.get_children():
		c.queue_free()
	var metal := _mat(Color(0.09, 0.09, 0.11), 0.6, 0.4)
	var wood  := _mat(Color(0.28, 0.16, 0.07), 0.0, 0.7)
	match kind:
		"shotgun":
			# Short, fat body + stubby twin barrel — reads as a close-range shotgun.
			var bm := BoxMesh.new(); bm.size = Vector3(0.09, 0.12, 0.34)
			_gun_mesh(bm, metal, Vector3(0, 0, -0.04))
			var stock := BoxMesh.new(); stock.size = Vector3(0.06, 0.10, 0.16)
			_gun_mesh(stock, wood, Vector3(0, -0.01, 0.16))
			for off in [-0.025, 0.025]:
				var cm := CylinderMesh.new(); cm.top_radius = 0.022; cm.bottom_radius = 0.022
				cm.height = 0.30; cm.radial_segments = 8
				_gun_mesh(cm, metal, Vector3(off, 0.02, -0.30), Vector3(deg_to_rad(90), 0, 0))
		"sniper":
			# Long thin barrel + scope — reads as a marksman rifle.
			var bm := BoxMesh.new(); bm.size = Vector3(0.06, 0.10, 0.46)
			_gun_mesh(bm, metal, Vector3(0, 0, -0.02))
			var stock := BoxMesh.new(); stock.size = Vector3(0.05, 0.09, 0.18)
			_gun_mesh(stock, wood, Vector3(0, -0.01, 0.20))
			var cm := CylinderMesh.new(); cm.top_radius = 0.013; cm.bottom_radius = 0.013
			cm.height = 0.70; cm.radial_segments = 8
			_gun_mesh(cm, metal, Vector3(0, 0.02, -0.55), Vector3(deg_to_rad(90), 0, 0))
			# Scope: tube on top.
			var sc := CylinderMesh.new(); sc.top_radius = 0.018; sc.bottom_radius = 0.018
			sc.height = 0.14; sc.radial_segments = 8
			_gun_mesh(sc, metal, Vector3(0, 0.075, -0.06), Vector3(deg_to_rad(90), 0, 0))
		_:  # rifle (default)
			var bm := BoxMesh.new(); bm.size = Vector3(0.07, 0.11, 0.5)
			_gun_mesh(bm, metal, Vector3(0, 0, -0.08))
			var cm := CylinderMesh.new(); cm.top_radius = 0.02; cm.bottom_radius = 0.02
			cm.height = 0.45; cm.radial_segments = 8
			_gun_mesh(cm, metal, Vector3(0, 0.02, -0.42), Vector3(deg_to_rad(90), 0, 0))

# ─── Playback ─────────────────────────────────────────────────
func _play(key: String, blend: float = 0.15) -> void:
	if _anim:
		_anim.play("e/" + key, blend)

func _on_anim_finished(_name: StringName) -> void:
	if _dead:
		return
	_busy = false
	_play(_locomotion)

# ─── API called by enemy.gd ───────────────────────────────────

# Pick the locomotion clip from how the enemy moves relative to its facing.
# fwd_speed / lat_speed are the body-local forward and sideways speeds (m/s);
# sideways-dominant motion → the side-step clip. `aim` doubles as the standing
# idle — the enemy holds the rifle on the player whenever it isn't moving.
func set_locomotion(speed: float, fwd_speed: float = 0.0, lat_speed: float = 0.0) -> void:
	if _dead:
		return
	var want := "aim"
	if speed > MOVE_SPEED:
		if absf(lat_speed) > absf(fwd_speed) and absf(lat_speed) > MOVE_SPEED:
			want = "strafe"
		elif speed > RUN_SPEED:
			want = "run"
		else:
			want = "walk"
	_locomotion = want
	if _busy:
		return
	if not _anim.current_animation.ends_with(want):
		_play(want)
	# Sync stride to movement speed so feet don't skate too badly.
	match want:
		"run":    _anim.speed_scale = clampf(speed / 5.4, 0.8, 1.5)
		"walk":   _anim.speed_scale = clampf(speed / 2.4, 0.6, 1.6)
		"strafe": _anim.speed_scale = clampf(speed / 3.0, 0.7, 1.5)
		_:        _anim.speed_scale = 1.0

func play_melee() -> void:
	if _busy or _dead:
		return
	_busy = true
	_anim.speed_scale = 1.0
	_play("melee", 0.06)

func play_death() -> void:
	if _dead:
		return
	_dead = true
	_busy = true
	_anim.speed_scale = DEATH_SPEED
	_play("death", 0.08)

func set_flash(on: bool, flash_mat: StandardMaterial3D) -> void:
	for mi in all_meshes:
		mi.material_override = flash_mat if on else null
