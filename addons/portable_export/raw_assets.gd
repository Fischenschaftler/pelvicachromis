@tool
extends EditorExportPlugin
func _get_name() -> String:return "PortableProjectionAssets"
func _export_begin(_features: PackedStringArray,_debug: bool,_path: String,_flags: int) -> void:
	# These are read through FileAccess for hash validation / CPU texture baking.
	# Keep imported scene/texture resources as well; never modify the inputs.
	for path in ["res://models/pelvicachromis_taeniatus_male.glb","res://textures/pelvicachromis_taeniatus_male_albedo.png"]:
		add_file(path,FileAccess.get_file_as_bytes(path),false)
