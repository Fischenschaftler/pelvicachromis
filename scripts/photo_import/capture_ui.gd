extends SceneTree
var viewer: Node3D
func _initialize() -> void:call_deferred("run")
func run() -> void:
	viewer=load("res://scenes/PhotoImport.tscn").instantiate();root.add_child(viewer);root.size=Vector2i(1400,1000)
	await create_timer(.3).timeout
	var panel: Control=viewer.get_node("UI/ReferencePhoto")
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://godot/diagnostics/photo_import_ui_validation.json"))
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report.left))
	panel.load_photo(data.photo_path)
	for key in panel.Projector.KEYS:panel.canvas.landmarks.append(Vector2(data.landmarks_original_px[key][0],data.landmarks_original_px[key][1]))
	for pair in data.contour_original_px:panel.canvas.points.append(Vector2(pair[0],pair[1]))
	panel.canvas.closed=true;panel.canvas.queue_redraw()
	var image:=Image.load_from_file(data.texture_path);image.generate_mipmaps();panel.generated=ImageTexture.create_from_image(image);panel.show_generated()
	panel.status.text="Foto links · Live-Textur rechts. Punkte ziehen oder Maske korrigieren."
	await create_timer(.3).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://godot/diagnostics/photo_import_ui.png")
	root.size=Vector2i(480,360);await create_timer(.3).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://godot/diagnostics/photo_import_ui_small.png")
	quit()
