extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:root.add_child(preload("res://scripts/sequences/validate_sequences.gd").new())
