extends Node
# Multi-weapon inventory + firing system.
# Holds several WeaponDefs, per-weapon ammo, unlock state, current selection,
# ADS, and pellet/spread/falloff firing. owner == the Player node.

# ─── Weapon definition ───────────────────────────────────────
class WeaponDef extends RefCounted:
	var id: String
	var display_name: String
	var damage: int
	var fire_interval: float
	var magazine_size: int
	var max_reserve: int
	var max_reserve_cap: int
	var reload_time: float
	var pellets: int = 1
	var spread_deg: float = 0.6
	var range: float = 120.0
	var auto: bool = true            # hold to fire vs semi (per-press)
	var ads_fov: float = 0.0         # >0 enables aim-down-sights zoom
	var recoil_scale: float = 1.0
	var scoped: bool = false        # show the circular sniper scope overlay on ADS
	var unlock_wave: int = 1
	# Damage falloff: full <= start, lerps to `min` mult at >= end
	var falloff_start: float = 200.0
	var falloff_end: float = 400.0
	var falloff_min: float = 1.0

	func falloff(d: float) -> float:
		if d <= falloff_start: return 1.0
		if d >= falloff_end: return falloff_min
		var t: float = (d - falloff_start) / maxf(0.001, falloff_end - falloff_start)
		return lerpf(1.0, falloff_min, t)

# ─── State ───────────────────────────────────────────────────
var defs: Array = []
var mag: Dictionary = {}        # id -> magazine count
var reserve: Dictionary = {}    # id -> reserve count
var unlocked: Dictionary = {}   # id -> bool
var current: int = 0

var fire_cooldown: float = 0.0
var is_reloading: bool = false
var reload_remaining: float = 0.0
var ads: bool = false

# A holstered weapon quietly reloads itself after (reload_time + this) seconds,
# so it's topped up by the time you swap back. Kept longer than a manual reload
# so swapping isn't strictly faster than just reloading.
var swap_reload_extra: float = 1.5
var _stow_timers: Dictionary = {}   # weapon id -> seconds left until auto-reload

func _ready() -> void:
	_build_defs()
	for d in defs:
		mag[d.id] = d.magazine_size
		reserve[d.id] = d.max_reserve
		unlocked[d.id] = false
	if not GameManager.round_started.is_connected(unlock_for_round):
		GameManager.round_started.connect(unlock_for_round)
	# Wave 0/1: only the assault rifle is available.
	unlock_for_round(max(1, GameManager.current_round))
	current = 0
	call_deferred("_emit_all")

func _build_defs() -> void:
	var ar := WeaponDef.new()
	ar.id = "ar"; ar.display_name = "ASSAULT RIFLE"
	ar.damage = 25; ar.fire_interval = 0.1
	ar.magazine_size = 120; ar.max_reserve = 360; ar.max_reserve_cap = 600
	ar.reload_time = 2.0; ar.pellets = 1; ar.spread_deg = 0.6; ar.range = 120.0
	ar.auto = true; ar.recoil_scale = 1.0; ar.unlock_wave = 1
	ar.ads_fov = 55.0               # moderate hipfire→ADS zoom
	ar.falloff_start = 35.0; ar.falloff_end = 80.0; ar.falloff_min = 0.7

	var sg := WeaponDef.new()
	sg.id = "shotgun"; sg.display_name = "SHOTGUN"
	sg.damage = 34; sg.fire_interval = 0.8
	sg.magazine_size = 12; sg.max_reserve = 72; sg.max_reserve_cap = 192
	sg.reload_time = 2.6; sg.pellets = 8; sg.spread_deg = 5.0; sg.range = 40.0
	sg.auto = false; sg.recoil_scale = 2.6; sg.unlock_wave = 3
	# Full damage out to 5m, then drops off → close-range one-shot weapon.
	sg.falloff_start = 5.0; sg.falloff_end = 24.0; sg.falloff_min = 0.2

	var sn := WeaponDef.new()
	sn.id = "sniper"; sn.display_name = "SNIPER"
	sn.damage = 150; sn.fire_interval = 1.2
	sn.magazine_size = 10; sn.max_reserve = 50; sn.max_reserve_cap = 120
	sn.reload_time = 3.0; sn.pellets = 1; sn.spread_deg = 0.05; sn.range = 200.0
	sn.auto = false; sn.ads_fov = 16.0; sn.recoil_scale = 3.4; sn.unlock_wave = 5
	sn.scoped = true                # circular scope UI + high zoom
	sn.falloff_start = 200.0; sn.falloff_end = 400.0; sn.falloff_min = 1.0

	var smg := WeaponDef.new()
	smg.id = "smg"; smg.display_name = "SMG"
	smg.damage = 16; smg.fire_interval = 0.066
	smg.magazine_size = 40; smg.max_reserve = 160; smg.max_reserve_cap = 400
	smg.reload_time = 1.8; smg.pellets = 1; smg.spread_deg = 2.2; smg.range = 80.0
	smg.auto = true; smg.recoil_scale = 0.6; smg.unlock_wave = 7
	smg.falloff_start = 18.0; smg.falloff_end = 45.0; smg.falloff_min = 0.5

	defs = [ar, sg, sn, smg]

func current_def() -> WeaponDef:
	return defs[current]

# ─── Unlocking ───────────────────────────────────────────────
func unlock_for_round(n: int) -> void:
	for d in defs:
		if not unlocked[d.id] and n >= d.unlock_wave:
			unlocked[d.id] = true
			if d.unlock_wave > 1:   # don't announce the starting weapon
				GameManager.weapon_unlocked.emit(d.display_name)

# ─── Switching ───────────────────────────────────────────────
func switch_to(i: int) -> void:
	if i < 0 or i >= defs.size(): return
	if not unlocked[defs[i].id]: return
	if i == current: return
	var old_def: WeaponDef = defs[current]
	current = i
	if is_reloading:
		is_reloading = false
		GameManager.reload_finished.emit()
	fire_cooldown = 0.0
	# The weapon we just holstered starts auto-reloading; the one we drew stops.
	_schedule_stow_reload(old_def)
	_stow_timers.erase(defs[i].id)
	GameManager.weapon_changed.emit(current_def().display_name)
	_emit_ammo()

func _schedule_stow_reload(def: WeaponDef) -> void:
	if mag[def.id] < def.magazine_size and reserve[def.id] > 0:
		_stow_timers[def.id] = def.reload_time + swap_reload_extra
	else:
		_stow_timers.erase(def.id)

func _tick_stow_reloads(delta: float) -> void:
	if _stow_timers.is_empty():
		return
	var cur_id: String = current_def().id
	var done: Array = []
	for id in _stow_timers:
		if id == cur_id:
			done.append(id)   # equipped → normal reload handles it
			continue
		_stow_timers[id] -= delta
		if _stow_timers[id] <= 0.0:
			_silent_reload(id)
			done.append(id)
	for id in done:
		_stow_timers.erase(id)

func _silent_reload(id: String) -> void:
	var def: WeaponDef = null
	for d in defs:
		if d.id == id:
			def = d
			break
	if def == null:
		return
	var to_load: int = min(def.magazine_size - mag[id], reserve[id])
	if to_load <= 0:
		return
	mag[id] += to_load
	reserve[id] -= to_load

func cycle(step: int) -> void:
	var n := defs.size()
	for k in range(1, n + 1):
		var i := (current + step * k) % n
		if i < 0: i += n
		if unlocked[defs[i].id]:
			switch_to(i)
			return

# ─── Firing ──────────────────────────────────────────────────
func _process(delta: float) -> void:
	if fire_cooldown > 0.0:
		fire_cooldown -= delta
	if is_reloading:
		reload_remaining -= delta
		if reload_remaining <= 0.0:
			_finish_reload()
	_tick_stow_reloads(delta)

var _ads_emit_active: bool = false
var _ads_emit_scoped: bool = false

func set_ads(on: bool) -> void:
	ads = on and current_def().ads_fov > 0.0
	var scoped: bool = ads and current_def().scoped
	if ads != _ads_emit_active or scoped != _ads_emit_scoped:
		_ads_emit_active = ads
		_ads_emit_scoped = scoped
		GameManager.ads_changed.emit(ads, scoped)

func try_fire(origin: Vector3, direction: Vector3, just_pressed: bool) -> void:
	var def := current_def()
	if not def.auto and not just_pressed:
		return
	if is_reloading or fire_cooldown > 0.0:
		return
	if mag[def.id] <= 0:
		start_reload()
		return

	mag[def.id] -= 1
	fire_cooldown = def.fire_interval
	_emit_ammo()

	var space = owner.get_world_3d().direct_space_state
	var muzzle_from: Vector3 = origin
	if owner.muzzle_point:
		muzzle_from = owner.muzzle_point.global_transform.origin

	var any_hit := false
	var any_head := false
	var primary_to: Vector3 = origin + direction * def.range
	var use_spread: float = 0.0 if ads else def.spread_deg

	for p in def.pellets:
		var d := _spread_dir(direction, use_spread)
		var end: Vector3 = origin + d * def.range
		var exclude: Array = [owner.get_rid()]
		var hit_point: Vector3 = end
		var collider = null
		# Area collision is ON so the enemy HeadArea (an Area3D) registers as a
		# headshot. Non-damaging trigger areas (pickups, ladders) are skipped and
		# the ray re-cast past them; solid world bodies still stop the shot.
		for _attempt in 6:
			var q := PhysicsRayQueryParameters3D.create(origin, end)
			q.exclude = exclude
			q.collide_with_areas = true
			var r = space.intersect_ray(q)
			if r.is_empty():
				collider = null
				hit_point = end
				break
			collider = r.collider
			hit_point = r.position
			if collider is Area3D and collider.name != "HeadArea":
				exclude.append(collider.get_rid())   # trigger area → pass through
				continue
			break
		if collider != null:
			var dist: float = origin.distance_to(hit_point)
			var dmg: int = int(round(def.damage * def.falloff(dist)))
			if collider.name == "HeadArea":
				var enemy = collider.get_parent()
				if enemy and enemy.has_method("take_damage"):
					enemy.take_damage(dmg, true)
					any_hit = true; any_head = true
					_spawn_impact(hit_point, true)
			elif collider.has_method("take_damage"):
				collider.take_damage(dmg, false)
				any_hit = true
				_spawn_impact(hit_point, false)
		if p == 0:
			primary_to = hit_point
		# Visual tracer per pellet (from muzzle)
		if owner.has_method("_spawn_tracer"):
			owner._spawn_tracer(muzzle_from, hit_point)

	if owner.has_method("fire_feedback"):
		owner.fire_feedback(def.recoil_scale, any_head)
	GameManager.weapon_fired.emit(muzzle_from, primary_to, any_hit, any_head)
	AudioManager.play_shot()

func _spawn_impact(pos: Vector3, head: bool) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.10
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.15) if head else Color(1.0, 0.85, 0.3)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	mi.global_position = pos
	get_tree().current_scene.add_child(mi)
	get_tree().create_timer(0.08, false, false, true).timeout.connect(mi.queue_free)

func _spread_dir(dir: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.001:
		return dir.normalized()
	var spread := deg_to_rad(spread_deg)
	var basis_z := -dir.normalized()
	var basis_x := Vector3.UP.cross(basis_z)
	if basis_x.length() < 0.01: basis_x = Vector3.RIGHT
	basis_x = basis_x.normalized()
	var basis_y := basis_z.cross(basis_x).normalized()
	var rx := randf_range(-spread, spread)
	var ry := randf_range(-spread, spread)
	return (-basis_z + basis_x * tan(rx) + basis_y * tan(ry)).normalized()

# ─── Reload / ammo ───────────────────────────────────────────
func start_reload() -> void:
	var def := current_def()
	if is_reloading: return
	if reserve[def.id] <= 0: return
	if mag[def.id] >= def.magazine_size: return
	is_reloading = true
	reload_remaining = def.reload_time
	GameManager.reload_started.emit(def.reload_time)
	AudioManager.play_reload()

func _finish_reload() -> void:
	var def := current_def()
	is_reloading = false
	var needed: int = def.magazine_size - mag[def.id]
	var to_load: int = min(needed, reserve[def.id])
	mag[def.id] += to_load
	reserve[def.id] -= to_load
	GameManager.reload_finished.emit()
	_emit_ammo()

func add_ammo(amount: int) -> void:
	if amount <= 0: return
	var def := current_def()
	reserve[def.id] = min(def.max_reserve_cap, reserve[def.id] + amount)
	_emit_ammo()

# Ammo pickups top up the whole arsenal, not just the equipped weapon.
func add_ammo_all(amount: int) -> void:
	if amount <= 0: return
	for d in defs:
		reserve[d.id] = min(d.max_reserve_cap, reserve[d.id] + amount)
	_emit_ammo()

func _emit_ammo() -> void:
	var def := current_def()
	GameManager.ammo_changed.emit(mag[def.id], def.magazine_size, reserve[def.id])

func _emit_all() -> void:
	GameManager.weapon_changed.emit(current_def().display_name)
	_emit_ammo()
