extends VBoxContainer
const Canvas = preload("res://scripts/landmark_canvas.gd")
const Normalizer = preload("res://scripts/fish_normalizer.gd")
var canvas: TextureRect
var status: Label
var start_button: Button
var undo_button: Button
var reset_button: Button
var confirm_button: Button
var normalized_preview: TextureRect
var normalized_title: Label
var legend: Label
var source: Image
var mask: Image
var source_path := ""
var mask_path := ""
var landmark_data: Dictionary = {}
var current_landmark_path := ""
var current_normalized_path := ""
var worker: Thread
var revision := 0

func _ready() -> void:
	var row := HFlowContainer.new()
	add_child(row)
	start_button = make_button(row, "Referenzpunkte setzen", start)
	undo_button = make_button(row, "Letzten Punkt entfernen", undo)
	reset_button = make_button(row, "Referenzpunkte zurücksetzen", reset_points)
	confirm_button = make_button(row, "Referenzpunkte bestätigen", confirm)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	canvas = Canvas.new()
	canvas.custom_minimum_size.y = 260
	canvas.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	canvas.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(canvas)
	canvas.landmarks_changed.connect(changed)
	legend = Label.new()
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.text = "1 Schnauzenspitze · 2 Augenmitte · 3 Schwanzansatz oben · 4 Schwanzansatz unten · 5 Körper oben · 6 Körper unten"
	legend.add_theme_font_size_override("font_size", 13)
	add_child(legend)
	normalized_title = Label.new()
	normalized_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	normalized_title.text = "Normalisierte Arbeitskopie · Kopf rechts"
	add_child(normalized_title)
	normalized_preview = TextureRect.new()
	normalized_preview.custom_minimum_size.y = 220
	normalized_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	normalized_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(normalized_preview)
	clear()

func make_button(row: Control, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.add_theme_font_size_override("font_size", 14)
	row.add_child(button)
	button.pressed.connect(action)
	return button

func invalidate_result() -> void:
	revision += 1
	landmark_data = {}
	current_landmark_path = ""
	current_normalized_path = ""
	normalized_preview.texture = null
	normalized_preview.hide()
	normalized_title.hide()

func clear() -> void:
	invalidate_result()
	source = null
	mask = null
	canvas.points.clear()
	canvas.active = false
	canvas.texture = null
	canvas.hide()
	legend.hide()
	hide()

func setup(image: Image, mask_image: Image, photo_path: String, saved_mask_path: String) -> void:
	clear()
	source = image
	mask = mask_image
	source_path = photo_path
	mask_path = saved_mask_path
	# Full-frame reduced display: coordinates still refer to the original image.
	var preview: Image = source.duplicate()
	var preview_mask: Image = mask.duplicate()
	var factor := minf(1.0, 1600.0 / maxi(source.get_width(), source.get_height()))
	preview.resize(maxi(1, roundi(source.get_width() * factor)), maxi(1, roundi(source.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	preview_mask.resize(preview.get_width(), preview.get_height(), Image.INTERPOLATE_NEAREST)
	canvas.texture = ImageTexture.create_from_image(Normalizer.cutout(preview, preview_mask))
	canvas.original_size = source.get_size()
	canvas.mask = mask
	status.text = "Freistellung fertig. Sechs anatomische Referenzpunkte setzen."
	show()
	update_buttons()

func update_buttons() -> void:
	var busy := worker != null
	start_button.disabled = busy
	undo_button.disabled = busy or canvas.points.is_empty()
	reset_button.disabled = busy or canvas.points.is_empty()
	confirm_button.disabled = busy or canvas.points.size() != 6 or not current_landmark_path.is_empty()

func start() -> void:
	if worker != null:
		return
	reset_points()
	canvas.show()
	legend.show()
	canvas.active = true
	changed()
	# Reveal the input canvas in the enclosing scrollable photo panel.
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.call_deferred("ensure_control_visible", canvas)
		ancestor = ancestor.get_parent()

func reset_points() -> void:
	invalidate_result()
	canvas.points.clear()
	canvas.active = true
	canvas.feedback = ""
	canvas.queue_redraw()
	changed()

func undo() -> void:
	if canvas.points.is_empty() or worker != null:
		return
	invalidate_result()
	canvas.points.remove_at(canvas.points.size() - 1)
	canvas.active = true
	canvas.feedback = ""
	canvas.queue_redraw()
	changed()

func changed() -> void:
	var count: int = canvas.points.size()
	status.text = "Punkt %d von 6: %s" % [count + 1, Canvas.LABELS[count]] if count < 6 else "Sechs Punkte gesetzt. Bitte prüfen und bestätigen."
	if not canvas.feedback.is_empty():
		status.text = canvas.feedback + "\n" + status.text
	update_buttons()

func confirm() -> void:
	if worker != null or source == null:
		return
	var data: Dictionary = Normalizer.analyze(canvas.points)
	if data.has("error"):
		status.text = data.error
		return
	invalidate_result()
	canvas.active = false
	worker = Thread.new()
	var error := worker.start(Normalizer.normalize.bind(source, mask, canvas.points.duplicate(), revision))
	if error != OK:
		worker = null
		canvas.active = true
		status.text = "Normalisierung konnte nicht gestartet werden. Bitte erneut bestätigen."
	else:
		status.text = "Arbeitskopie wird normalisiert …"
	update_buttons()

func _process(_delta: float) -> void:
	if worker == null or worker.is_alive():
		return
	var result: Dictionary = worker.wait_to_finish()
	worker = null
	update_buttons()
	if result.revision != revision:
		return
	if result.has("error"):
		status.text = result.error
		return
	var folder := preload("res://scripts/storage/portable_paths.gd").data_dir()+"/normalized"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
		status.text = "Der Ordner für Arbeitskopien konnte nicht angelegt werden."
		return
	var base := "%s/fish_%d_%d" % [folder, Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	if result.image.save_png(base + ".png") != OK:
		status.text = "Die normalisierte Arbeitskopie konnte nicht gespeichert werden."
		return
	var data: Dictionary = result.data
	data["original_photo_path"] = source_path
	data["mask_path"] = mask_path
	data["original_size"] = [source.get_width(), source.get_height()]
	data["normalized_path"] = ProjectSettings.globalize_path(base + ".png")
	var file := FileAccess.open(base + ".json", FileAccess.WRITE)
	if file == null:
		status.text = "Die Referenzpunkte konnten nicht gespeichert werden. Bitte erneut bestätigen."
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var saved := file.get_error() == OK
	file.close()
	if not saved:
		status.text = "Fehler beim Speichern der Referenzpunkte. Bitte erneut bestätigen."
		return
	landmark_data = data
	current_landmark_path = ProjectSettings.globalize_path(base + ".json")
	current_normalized_path = data.normalized_path
	normalized_preview.texture = ImageTexture.create_from_image(result.image)
	normalized_preview.show()
	normalized_title.show()
	status.text = "Gespeichert · Kopf %s · Länge %.1f px · Höhe %.1f px · Achse %.1f°" % ["links" if data.mirrored else "rechts", data.body_length_px, data.body_height_px, data.axis_angle_degrees]
	update_buttons()

func _exit_tree() -> void:
	if worker != null and worker.is_started():
		worker.wait_to_finish()
