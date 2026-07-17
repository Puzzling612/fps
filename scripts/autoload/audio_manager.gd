# AudioManager — procedural sound effects, no audio assets required.
#
# The project ships no .wav/.ogg files, so every clip is SYNTHESIZED once at
# startup into an AudioStreamWAV (16-bit PCM). Exported stream vars remain as
# optional overrides: drop real assets in later and they take priority.
#
# Two playback paths:
#   • play_shot()/play_reload()/play_hit()  → non-positional (the player's own
#     sounds — always full volume in both ears).
#   • play_*_at(pos)                        → AudioStreamPlayer3D at a world
#     position, so enemy fire / grenades / explosions PAN and attenuate with
#     distance — you can hear WHERE the threat is.
extends Node

@export var shot_sound: AudioStream
@export var reload_sound: AudioStream
@export var hit_sound: AudioStream

const MIX_RATE := 22050

var _player_shot: AudioStream
var _enemy_shot: AudioStream
var _reload: AudioStream
var _hurt: AudioStream
var _explosion: AudioStream
var _beep: AudioStream

func _ready() -> void:
	_player_shot = shot_sound if shot_sound else _synth_shot(0.10, 900.0)
	_enemy_shot = _synth_shot(0.14, 500.0)   # deeper, longer crack → reads as hostile
	_reload = reload_sound if reload_sound else _synth_clicks()
	_hurt = hit_sound if hit_sound else _synth_thud()
	_explosion = _synth_explosion()
	_beep = _synth_beep()

# ─── Public API ──────────────────────────────────────────────
func play_shot() -> void:
	_play_2d(_player_shot, -8.0)

func play_reload() -> void:
	_play_2d(_reload, -10.0)

func play_hit() -> void:
	_play_2d(_hurt, -4.0)

func play_shot_at(pos: Vector3) -> void:
	_play_3d(_enemy_shot, pos, 2.0)

func play_explosion_at(pos: Vector3) -> void:
	_play_3d(_explosion, pos, 6.0)

func play_beep_at(pos: Vector3) -> void:
	_play_3d(_beep, pos, 0.0)

# Back-compat with the old exported-stream API.
func play_sound(stream: AudioStream) -> void:
	_play_2d(stream, -8.0)

# ─── Playback helpers ────────────────────────────────────────
func _play_2d(stream: AudioStream, vol_db: float) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _play_3d(stream: AudioStream, pos: Vector3, vol_db: float) -> void:
	if stream == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = vol_db
	p.unit_size = 14.0            # audible across the arena, still attenuates
	p.max_distance = 90.0
	scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

# ─── Synthesis (16-bit mono PCM) ─────────────────────────────
func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav

# Gunshot: noise burst with fast exponential decay + a low "thump" underneath.
func _synth_shot(dur: float, thump_hz: float) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := expf(-t * 55.0)
		var noise := randf_range(-1.0, 1.0) * env
		var thump := sin(TAU * thump_hz * t) * expf(-t * 90.0) * 0.6
		s[i] = clampf(noise * 0.8 + thump, -1.0, 1.0)
	return _make_wav(s)

# Reload: two mechanical clicks.
func _synth_clicks() -> AudioStreamWAV:
	var n := int(0.22 * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		for start in [0.0, 0.13]:
			if t >= start:
				v += randf_range(-1.0, 1.0) * expf(-(t - start) * 300.0) * 0.7
		s[i] = clampf(v, -1.0, 1.0)
	return _make_wav(s)

# Hurt: low body thud.
func _synth_thud() -> AudioStreamWAV:
	var n := int(0.12 * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		s[i] = clampf(sin(TAU * 85.0 * t) * expf(-t * 40.0) + randf_range(-0.3, 0.3) * expf(-t * 60.0), -1.0, 1.0)
	return _make_wav(s)

# Explosion: long low rumble (integrated noise) with slow decay.
func _synth_explosion() -> AudioStreamWAV:
	var n := int(0.7 * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var acc := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		acc = clampf(acc + randf_range(-1.0, 1.0) * 0.25, -1.0, 1.0)   # brownish noise
		var env := expf(-t * 7.0)
		s[i] = clampf((acc * 0.9 + sin(TAU * 55.0 * t) * 0.4) * env, -1.0, 1.0)
	return _make_wav(s)

# Grenade warning tick.
func _synth_beep() -> AudioStreamWAV:
	var n := int(0.07 * MIX_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		s[i] = sin(TAU * 1250.0 * t) * expf(-t * 30.0) * 0.7
	return _make_wav(s)

func expf(x: float) -> float:
	return exp(x)
