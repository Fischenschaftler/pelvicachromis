extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:root.add_child(preload("res://scripts/stimulus/validate_stimulus.gd").new())
