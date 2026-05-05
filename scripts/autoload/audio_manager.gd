extends Node

@export var shot_sound: AudioStream
@export var reload_sound: AudioStream
@export var hit_sound: AudioStream

func _ready() -> void:
	pass

func play_sound(stream: AudioStream) -> void:
	if not stream:
		return
	var player = AudioStreamPlayer3D.new()
	player.stream = stream
	add_child(player)
	player.play()
	player.connect("finished", Callable(player, "queue_free"))
func play_reload() -> void:
	play_sound(reload_sound)

func play_hit() -> void:
	play_sound(hit_sound)
