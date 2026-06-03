class_name FX
extends RefCounted

# Code-only one-shot visual effects. Each spawns self-freeing nodes into the
# scene so callers (grenade.gd, enemy.gd) don't need dedicated .tscn files.

# ─── Grenade explosion ───────────────────────────────────────
static func explosion(root: Node, pos: Vector3, radius: float, color: Color = Color(1.0, 0.6, 0.2)) -> void:
	if root == null or not is_instance_valid(root):
		return

	# Punchy flash that fades fast.
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 10.0
	light.omni_range = radius * 2.4
	root.add_child(light)
	light.global_position = pos
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.35).set_ease(Tween.EASE_OUT)
	lt.tween_callback(light.queue_free)

	# Expanding fireball shell.
	var shell := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	shell.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.88, 0.45, 0.95)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell.material_override = mat
	shell.scale = Vector3.ONE * 0.3
	root.add_child(shell)
	shell.global_position = pos
	var st := shell.create_tween()
	st.set_parallel(true)
	st.tween_property(shell, "scale", Vector3.ONE * radius * 1.3, 0.32).set_ease(Tween.EASE_OUT)
	st.tween_property(mat, "albedo_color:a", 0.0, 0.32)
	st.tween_property(mat, "emission_energy_multiplier", 0.0, 0.32)
	st.chain().tween_callback(shell.queue_free)

	# Expanding ground shockwave ring.
	_ring(root, pos, radius * 1.6, color)
	# Fiery spark/debris burst.
	_burst(root, pos, color, 36, radius * 4.0, 0.7, 0.18)
	# Lingering smoke puff.
	_smoke(root, pos, radius * 0.6)

# ─── Enemy death burst ───────────────────────────────────────
static func death_burst(root: Node, pos: Vector3, color: Color = Color(0.85, 0.2, 0.2)) -> void:
	if root == null or not is_instance_valid(root):
		return

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = 4.0
	root.add_child(light)
	light.global_position = pos
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.25).set_ease(Tween.EASE_OUT)
	lt.tween_callback(light.queue_free)

	# Chunky scatter of body-colored bits + a quick white spark pop.
	_burst(root, pos, color, 24, 6.0, 0.9, 0.16)
	_burst(root, pos, Color(1, 1, 1), 12, 7.0, 0.35, 0.07)
	_ring(root, pos, 2.2, color)

# ─── Internals ───────────────────────────────────────────────
static func _burst(root: Node, pos: Vector3, color: Color, amount: int, speed: float, lifetime: float, size: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = true

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.35
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -12.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color = color
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = color
	dmat.emission_enabled = true
	dmat.emission = color
	dmat.emission_energy_multiplier = 3.0
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = dmat
	p.draw_pass_1 = quad

	root.add_child(p)
	p.global_position = pos
	_free_after(root, p, lifetime + 0.4)

static func _smoke(root: Node, pos: Vector3, scale_max: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 1.1
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = true

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.4
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, 1.5, 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = scale_max * 1.5
	pm.scale_max = scale_max * 3.0
	pm.color = Color(0.18, 0.16, 0.15, 0.7)
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.16, 0.15, 0.14, 0.55)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = smat
	p.draw_pass_1 = quad

	root.add_child(p)
	p.global_position = pos + Vector3(0, 0.3, 0)
	_free_after(root, p, 1.6)

static func _ring(root: Node, pos: Vector3, max_radius: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.35
	torus.outer_radius = 0.5
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.8)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.scale = Vector3.ONE * 0.2
	root.add_child(ring)
	ring.global_position = pos + Vector3(0, 0.15, 0)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(max_radius, max_radius * 0.4, max_radius), 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(ring.queue_free)

static func _free_after(root: Node, node: Node, secs: float) -> void:
	var tree := root.get_tree()
	if tree == null:
		node.queue_free()
		return
	var timer := tree.create_timer(secs)
	timer.timeout.connect(node.queue_free)
