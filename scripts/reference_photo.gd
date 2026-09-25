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
	var column := VBoxContainer.new()
	margin.add_child(column)
	picture = TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(picture)
	info = Label.new()
	info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(info)
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
	var largest := maxi(dimensions.x, dimensions.y)
	if largest > MAX_DISPLAY_EDGE:
		var ratio := float(MAX_DISPLAY_EDGE) / largest
		image.resize(maxi(1, roundi(dimensions.x * ratio)), maxi(1, roundi(dimensions.y * ratio)), Image.INTERPOLATE_LANCZOS)
	# Commit state only after successful decoding; failed replacements retain the old photo.
	picture.texture = ImageTexture.create_from_image(image)
	current_photo_path = path.simplify_path()
	original_size = dimensions
	info.text = "%s\nBreite: %d px\nHöhe: %d px" % [path.get_file(), dimensions.x, dimensions.y]
	info.tooltip_text = path.get_file()
	panel.show()
	_layout()
	photo_changed.emit()
	return true

func remove_photo() -> void:
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
			var width := (available.x - 12) * 0.5
			viewport_container.position = Vector2(16, top)
			viewport_container.size = Vector2(width, available.y)
			panel.position = Vector2(28 + width, top)
			panel.size = Vector2(width, available.y)
		else:
			var height := (available.y - 12) * 0.5
			viewport_container.position = Vector2(16, top)
			viewport_container.size = Vector2(available.x, height)
			panel.position = Vector2(16, top + height + 12)
			panel.size = Vector2(available.x, height)
	viewer.orbit.call_deferred("_resize")
