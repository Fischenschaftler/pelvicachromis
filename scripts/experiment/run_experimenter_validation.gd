extends SceneTree
func _initialize() -> void:
	root.add_child(load("res://scripts/experiment/validate_experimenter.gd").new())
