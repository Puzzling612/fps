extends Node3D

@export var lifetime: float = 0.06

var _t: float = 0.0
var _mat: StandardMaterial3D

func setup(from: Vector3, to: Vector3) -> void:
	var dist = from.distance_to(to)
	if dist < 0.05:
		queue_free()
		return
	var mid = (from + to) * 0.5
	global_position = mid
	# look_at points -Z toward target; BoxMesh size.z = dist will then extend along that line.
	if (to - from).length() > 0.001:
		# Avoid look_at failing when from-to is parallel to UP
		var up = Vector3.UP
		if abs((to - from).normalized().dot(up)) > 0.99:
			up = Vector3.RIGHT
		look_at(to, up)
	var mi: MeshInstance3D = $MeshInstance3D
	var box := BoxMesh.new()
	box.size = Vector3(0.04, 0.04, dist)
	mi.mesh = box
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.9, 0.4, 1.0)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.8, 0.3)
	_mat.emission_energy_multiplier = 3.0
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = _mat

func _process(delta: float) -> void:
	_t += delta
	var k = clamp(1.0 - _t / lifetime, 0.0, 1.0)
	if _mat:
		_mat.albedo_color.a = k
	if _t >= lifetime:
		queue_free()
