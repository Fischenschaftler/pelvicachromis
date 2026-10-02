extends SceneTree
func _initialize() -> void:root.add_child(load("res://scripts/stimulus/validate_fish_turning.gd").new())
