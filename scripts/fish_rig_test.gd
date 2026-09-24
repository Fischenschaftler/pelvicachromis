extends Node3D
## Isolated imported-rig preview. No procedural fish motion is added.

var animation_player: AnimationPlayer
var swim_animation: StringName


func _ready() -> void:
	$Camera3D.look_at(Vector3(0.0, 0.001, 0.0), Vector3.UP)
	for node in $Fish.find_children("*", "AnimationPlayer", true, false):
		animation_player = node as AnimationPlayer
		break
	if animation_player == null:
		push_error("Imported fish has no AnimationPlayer.")
		return
	for animation_name in animation_player.get_animation_list():
		if String(animation_name).to_lower().contains("swim"):
			swim_animation = animation_name
			break
	if swim_animation.is_empty():
		push_error("Imported fish has no swim animation.")
		return
	# Set explicitly as well: importers may strip the _Loop suffix from its name.
	animation_player.get_animation(swim_animation).loop_mode = Animation.LOOP_LINEAR
	animation_player.play(swim_animation)
	print("FishRigTest: playing %s (%0.3f seconds)" % [
		swim_animation, animation_player.get_animation(swim_animation).length])
