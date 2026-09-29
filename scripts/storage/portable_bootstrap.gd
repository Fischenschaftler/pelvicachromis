extends Node
const Paths=preload("res://scripts/storage/portable_paths.gd")
func _ready() -> void:
	var error:=Paths.initialize()
	if error.is_empty():
		Paths.log_message("Start; Projekte: "+Paths.projects_dir())
		return
	# Deferred pause ensures the main scene exists, but no user operation can begin.
	call_deferred("show_storage_error",error)
func show_storage_error(message: String) -> void:
	get_tree().paused=true
	var dialog:=AcceptDialog.new()
	dialog.process_mode=Node.PROCESS_MODE_ALWAYS
	dialog.title="Portabler Speicher nicht beschreibbar"
	dialog.dialog_text=message
	add_child(dialog)
	dialog.confirmed.connect(func(): get_tree().quit(1))
	dialog.canceled.connect(func(): get_tree().quit(1))
	dialog.popup_centered(Vector2i(600,180))
