extends Node3D
## Imported meshes, materials, rig and animation resources stay untouched.
@onready var orbit: Node3D = $OrbitCamera
@onready var animation_button: Button = $UI/Layout/Bottom/Buttons/Animation
@onready var reset_button: Button = $UI/Layout/Bottom/Buttons/Reset
var animation_player: AnimationPlayer
var swim_animation: StringName

func _ready() -> void:
	get_window().min_size = Vector2i(480, 360)
	var bounds := AABB()
	var first := true
	for node in $Fish.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	orbit.configure(bounds)
	animation_button.pressed.connect(toggle_animation)
	reset_button.pressed.connect(orbit.reset_view)
	for node in $Fish.find_children("*", "AnimationPlayer", true, false):
		animation_player = node as AnimationPlayer
		break
	if animation_player != null:
		for clip in animation_player.get_animation_list():
			if String(clip).to_lower() == "swim_test":
				swim_animation = clip
				break
	if animation_player == null or swim_animation.is_empty():
		animation_button.disabled = true
		animation_button.text = "Animation nicht verfügbar"
		push_error("Viewer: imported Swim_Test animation missing")
		return
	if animation_player.get_animation(swim_animation).loop_mode != Animation.LOOP_LINEAR:
		push_error("Viewer: imported Swim_Test must loop")
	animation_player.play(swim_animation)
	_update_button()

func toggle_animation() -> void:
	if animation_player.is_playing():
		animation_player.pause()
	else:
		animation_player.play(swim_animation)
	_update_button()

func _update_button() -> void:
	animation_button.text = "Animation stoppen" if animation_player.is_playing() else "Animation starten"
