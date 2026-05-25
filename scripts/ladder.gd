# Ladder trigger: anyone with enter_ladder/exit_ladder methods (player or enemy)
# can climb by being inside this area.
extends Area3D

func _ready() -> void:
	body_entered.connect(_on_entered)
	body_exited.connect(_on_exited)

func _on_entered(body: Node) -> void:
	if body.has_method("enter_ladder"):
		body.enter_ladder()

func _on_exited(body: Node) -> void:
	if body.has_method("exit_ladder"):
		body.exit_ladder()
