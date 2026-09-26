extends Control
## Reference image display only; no analysis and no changes to fish assets.
signal photo_changed
var current_photo_path := ""
var original_size := Vector2i.ZERO
var last_error := ""
var select_button: Button
var remove_button: Button
var dialog: FileDialog
var error_dialog: AcceptDialog
var panel: PanelContainer
var picture: TextureRect
const PolygonCanvas = preload("res://scripts/photo_polygon.gd")
const MaskBuilder = preload("res://scripts/polygon_mask.gd")
var original_image: Image
var current_mask_path := ""
var mask_image: Image
var cutout_preview: TextureRect
var preview_title: Label
var mark_button: Button
var close_button: Button
var reset_mark_button: Button
var marking_status: Label
var photo_scroll: ScrollContainer
var mask_worker: Thread
var mask_revision := 0
var mask_busy := false
var info: Label
var viewer: Node3D
var viewport_container: SubViewportContainer
const MAX_FILE_BYTES := 64 * 1024 * 1024
const MAX_DISPLAY_EDGE := 2048

func _ready() -> void:
	viewer = get_parent().get_parent()
	viewport_container = viewer.get_node("ViewerViewport")
	select_button = Button.new()
	select_button.text = "Fischfoto auswählen"
	select_button.custom_minimum_size = Vector2(185, 38)
	add_child(select_button)
	select_button.pressed.connect(_choose)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	photo_scroll = ScrollContainer.new()
	photo_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(photo_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	photo_scroll.add_child(column)
	picture = PolygonCanvas.new()
	picture.custom_minimum_size.y = 220
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(picture)
	info = Label.new()
	info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(info)
	var marking_buttons := HFlowContainer.new()
	column.add_child(marking_buttons)
	mark_button = Button.new()
	mark_button.text = "Fisch markieren"
	marking_buttons.add_child(mark_button)
	mark_button.pressed.connect(start_marking)
	close_button = Button.new()
	close_button.text = "Kontur schließen"
	marking_buttons.add_child(close_button)
	close_button.pressed.connect(close_contour)
	reset_mark_button = Button.new()
	reset_mark_button.text = "Markierung zurücksetzen"
	marking_buttons.add_child(reset_mark_button)
	reset_mark_button.pressed.connect(reset_marking)
	close_button.disabled = true
	marking_status = Label.new()
	marking_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(marking_status)
	preview_title = Label.new()
	preview_title.text = "Freigestellter Fisch"
	column.add_child(preview_title)
	cutout_preview = TextureRect.new()
	cutout_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cutout_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cutout_preview.custom_minimum_size.y = 220
	column.add_child(cutout_preview)
	preview_title.hide()
	cutout_preview.hide()
	picture.connect("close_requested", close_contour)
	picture.connect("contour_changed", _contour_changed)
	remove_button = Button.new()
	remove_button.text = "Foto entfernen"
	column.add_child(remove_button)
	remove_button.pressed.connect(remove_photo)
	panel.hide()
	dialog = FileDialog.new()
	dialog.title = "Fischfoto auswählen"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.jpg,*.jpeg,*.png,*.webp ; Fischfotos (JPG, JPEG, PNG, WEBP)"])
	add_child(dialog)
	dialog.file_selected.connect(load_photo)
	error_dialog = AcceptDialog.new()
	error_dialog.title = "Foto konnte nicht geladen werden"
	add_child(error_dialog)
	get_viewport().size_changed.connect(_layout)
	call_deferred("_layout")

func _choose() -> void:
	viewer.orbit.dragging = false
	dialog.popup_centered_clamped(Vector2i(850, 600), 0.9)

func _fail(message: String) -> bool:
	last_error = message
	error_dialog.dialog_text = message
	error_dialog.popup_centered_clamped(Vector2i(440, 170), 0.9)
	return false

func load_photo(path: String) -> bool:
	last_error = ""
	var extension := path.get_extension().to_lower()
	if not path.is_absolute_path() or extension not in ["jpg", "jpeg", "png", "webp"]:
		return _fail("Bitte eine JPG-, JPEG-, PNG- oder WEBP-Datei auswählen.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Die Datei ist nicht lesbar. Bitte Speicherort und Zugriffsrechte prüfen.")
	if file.get_length() > MAX_FILE_BYTES:
		return _fail("Das Foto ist größer als 64 MB. Bitte eine kleinere Bilddatei auswählen.")
	var bytes := file.get_buffer(file.get_length())
	file.close()
	# Reject obvious invalid files before invoking a decoder.
	var signature_ok := false
	if bytes.size() >= 12:
		if extension in ["jpg", "jpeg"]:
			signature_ok = bytes[0] == 255 and bytes[1] == 216 and bytes[2] == 255
		elif extension == "png":
			signature_ok = bytes.slice(0, 8) == PackedByteArray([137,80,78,71,13,10,26,10])
		else:
			signature_ok = bytes.slice(0,4).get_string_from_ascii() == "RIFF" and bytes.slice(8,12).get_string_from_ascii() == "WEBP"
	if not signature_ok:
		return _fail("Die Bilddatei ist ungültig oder beschädigt. Bitte ein anderes Foto auswählen.")
	var image := Image.new()
	var result: Error
	match extension:
		"jpg", "jpeg": result = image.load_jpg_from_buffer(bytes)
		"png": result = image.load_png_from_buffer(bytes)
		"webp": result = image.load_webp_from_buffer(bytes)
	if result != OK or image.is_empty():
		return _fail("Die Bilddatei konnte nicht gelesen werden. Sie ist möglicherweise beschädigt.")
	var dimensions := image.get_size()
	original_image = image.duplicate()
	reset_marking()
	var largest := maxi(dimensions.x, dimensions.y)
	if largest > MAX_DISPLAY_EDGE:
		var ratio := float(MAX_DISPLAY_EDGE) / largest
		image.resize(maxi(1, roundi(dimensions.x * ratio)), maxi(1, roundi(dimensions.y * ratio)), Image.INTERPOLATE_LANCZOS)
	# Commit state only after successful decoding; failed replacements retain the old photo.
	picture.texture = ImageTexture.create_from_image(image)
	current_photo_path = path.simplify_path()
	original_size = dimensions
	picture.set("original_size", dimensions)
	info.text = "%s\nBreite: %d px\nHöhe: %d px" % [path.get_file(), dimensions.x, dimensions.y]
	info.tooltip_text = path.get_file()
	panel.show()
	_layout()
	photo_changed.emit()
	return true

func remove_photo() -> void:
	reset_marking()
	original_image = null
	picture.set("original_size", Vector2i.ZERO)
	picture.texture = null
	current_photo_path = ""
	original_size = Vector2i.ZERO
	info.text = ""
	panel.hide()
	_layout()
	photo_changed.emit()

func _layout() -> void:
	var window_size := get_viewport().get_visible_rect().size
	select_button.position = Vector2(window_size.x - 205, 20) if window_size.x >= 800 or not current_photo_path.is_empty() else Vector2(20, 80)
	select_button.size = Vector2(185, 38)
	if window_size.x < 800 and not current_photo_path.is_empty():
		select_button.position.y = 12
	var title: Label = viewer.get_node("UI/Layout/Header/Title")
	title.add_theme_font_size_override("font_size", 18 if window_size.x < 800 and not current_photo_path.is_empty() else 22)
	viewport_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	if current_photo_path.is_empty():
		viewport_container.position = Vector2.ZERO
		viewport_container.size = window_size
		viewer.orbit.reserved_height = 180.0
	else:
		var top := 96.0 if window_size.x >= 800 else 88.0
		var available := Vector2(window_size.x - 32, maxf(160, window_size.y - top - 74))
		viewer.orbit.reserved_height = 0.0
		if window_size.x >= 800 or window_size.y < 600:
			var width := (available.x - 12) * (0.40 if window_size.x < 800 else 0.5)
			viewport_container.position = Vector2(16, top)
			viewport_container.size = Vector2(width, available.y)
			panel.position = Vector2(28 + width, top)
			panel.size = Vector2(available.x - 12 - width, available.y)
		else:
			var height := (available.y - 12) * 0.5
			viewport_container.position = Vector2(16, top)
			viewport_container.size = Vector2(available.x, height)
			panel.position = Vector2(16, top + height + 12)
			panel.size = Vector2(available.x, height)
	viewer.orbit.call_deferred("_resize")


func reset_marking() -> void:
	mask_revision += 1 # Invalidates results still being calculated for an older photo.
	current_mask_path = ""
	mask_image = null
	picture.call("clear_contour")
	cutout_preview.texture = null
	cutout_preview.hide()
	preview_title.hide()
	marking_status.text = ""
	close_button.disabled = true

func start_marking() -> void:
	if original_image == null or mask_busy:
		return
	reset_marking()
	picture.set("marking", true)
	marking_status.text = "Kontur anklicken. Doppelklick oder Kontur schließen beendet die Markierung."
	close_button.disabled = false
	photo_scroll.set_deferred("scroll_vertical", 0)

func _contour_changed() -> void:
	if picture.get("marking"):
		marking_status.text = "%d Punkte · Doppelklick oder Kontur schließen" % picture.get("points").size()

func close_contour() -> void:
	if original_image == null or mask_busy or not picture.get("marking"):
		return
	var points: PackedVector2Array = picture.get("points")
	if points.size() > 3 and points[0].distance_to(points[-1]) < 0.5:
		points.remove_at(points.size() - 1)
		picture.set("points", points)
	var problem: String = MaskBuilder.validation_error(points, original_size)
	if not problem.is_empty():
		marking_status.text = problem
		return
	picture.set("closed", true)
	picture.set("marking", false)
	picture.queue_redraw()
	marking_status.text = "Maske wird berechnet …"
	mask_busy = true
	mark_button.disabled = true
	close_button.disabled = true
	mask_worker = Thread.new()
	var result := mask_worker.start(MaskBuilder.build.bind(original_image, points.duplicate(), mask_revision))
	if result != OK:
		mask_busy = false
		mark_button.disabled = false
		mask_worker = null
		marking_status.text = "Maskenberechnung konnte nicht gestartet werden. Bitte erneut markieren."

func _process(_delta: float) -> void:
	if mask_worker == null or mask_worker.is_alive():
		return
	var result: Dictionary = mask_worker.wait_to_finish()
	mask_worker = null
	mask_busy = false
	mark_button.disabled = false
	if result["revision"] != mask_revision:
		return
	var directory := "user://masks"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		marking_status.text = "Der Maskenordner konnte nicht angelegt werden."
		return
	var path := "%s/fish_mask_%d_%d.png" % [directory, Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	var generated: Image = result["mask"]
	if generated.save_png(path) != OK:
		marking_status.text = "Die Maskendatei konnte nicht gespeichert werden."
		return
	mask_image = generated
	current_mask_path = ProjectSettings.globalize_path(path)
	cutout_preview.texture = ImageTexture.create_from_image(result["preview"])
	preview_title.show()
	cutout_preview.show()
	marking_status.text = "Maske gespeichert · %d × %d Pixel" % [original_size.x, original_size.y]

func _exit_tree() -> void:
	if mask_worker != null and mask_worker.is_started():
		mask_worker.wait_to_finish()
