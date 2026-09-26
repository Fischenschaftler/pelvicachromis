extends VBoxContainer
const Baker = preload("res://scripts/body_texture_baker.gd")
var viewer: Node3D
var landmarks: VBoxContainer
var transfer_button: Button
var original_button: Button
var generated_button: Button
var status: Label
var current_generated_path := ""
var current_body_mask_path := ""
var current_metadata_path := ""
var current_coverage_path := ""
var last_stats: Dictionary = {}
var generated_texture: ImageTexture
var original_materials: Array = []
var body: MeshInstance3D
var worker: Thread
var pending_path := ""
var pending_data: Dictionary = {}
var base_image: Image
var showing_generated := false

func _ready() -> void:
	var row := HFlowContainer.new()
	add_child(row)
	transfer_button = button(row, "Färbung auf 3D Fisch übertragen", generate)
	original_button = button(row, "Originalfärbung", show_original)
	generated_button = button(row, "Generierte Färbung", show_generated)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	hide()
	call_deferred("prepare")

func button(row: Control, title: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = title
	item.add_theme_font_size_override("font_size", 13)
	row.add_child(item)
	item.pressed.connect(action)
	return item

func prepare() -> void:
	for node in viewer.fish.find_children("*", "MeshInstance3D", true, false):
		if node.name == "Fish_Body":
			body = node
			break
	if body == null:
		status.text = "Fish_Body wurde nicht gefunden."
		return
	for surface in range(body.mesh.get_surface_count()):
		original_materials.append({"override":body.get_surface_override_material(surface),"active":body.get_active_material(surface)})
	# Decode the existing atlas without changing its file or imported material.
	var path := "res://textures/pelvicachromis_taeniatus_male_albedo.png"
	base_image = Image.new()
	if FileAccess.file_exists(path):
		if base_image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
			base_image = null
	else:
		var material: BaseMaterial3D = original_materials[0].active
		base_image = material.albedo_texture.get_image()
		if base_image.is_compressed():
			base_image.decompress()

func generate() -> void:
	if worker != null or body == null or base_image == null or landmarks.current_landmark_path.is_empty():
		return
	var model: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/body_projection.json"))
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(landmarks.current_landmark_path))
	if not model is Dictionary or not data is Dictionary:
		status.text = "Projektionsdaten oder Referenzpunkte konnten nicht gelesen werden."
		return
	if FileAccess.get_sha256("res://models/pelvicachromis_taeniatus_male.glb") != model.source_glb_sha256:
		status.text = "Das Modell passt nicht zu den geprüften UV-Daten. Bitte die UV-Zuordnung aktualisieren."
		return
	var photo := Image.new()
	var bytes := FileAccess.get_file_as_bytes(landmarks.current_normalized_path)
	if bytes.is_empty() or photo.load_png_from_buffer(bytes) != OK:
		status.text = "Die normalisierte Arbeitskopie konnte nicht geladen werden."
		return
	pending_path = landmarks.current_landmark_path
	pending_data = data
	worker = Thread.new()
	if worker.start(Baker.bake.bind(base_image, photo, data, model)) != OK:
		worker = null
		status.text = "Texturberechnung konnte nicht gestartet werden."
		return
	status.text = "Körperfärbung wird berechnet … Der Viewer bleibt bedienbar."

func show_original() -> void:
	if body == null:
		return
	for i in range(original_materials.size()):
		body.set_surface_override_material(i, original_materials[i].override)
	showing_generated = false
	status.text = "Originalfärbung aktiv."

func show_generated() -> void:
	if generated_texture == null or body == null:
		return
	for i in range(original_materials.size()):
		var material: BaseMaterial3D = original_materials[i].active.duplicate()
		material.albedo_texture = generated_texture
		body.set_surface_override_material(i, material)
	showing_generated = true
	status.text = "Generierte Körperfärbung aktiv · Flossen, Augen und Mund behalten ihre Originalmaterialien."

func _process(_delta: float) -> void:
	visible = not landmarks.current_landmark_path.is_empty() or generated_texture != null or worker != null
	transfer_button.disabled = worker != null or landmarks.current_landmark_path.is_empty() or base_image == null
	generated_button.disabled = generated_texture == null or showing_generated
	original_button.disabled = not showing_generated
	if worker == null or worker.is_alive():
		return
	var result: Dictionary = worker.wait_to_finish()
	worker = null
	if pending_path != landmarks.current_landmark_path:
		status.text = "Referenz geändert; veraltete Berechnung verworfen."
		return
	if result.has("error"):
		status.text = result.error
		return
	var folder := "user://generated_textures"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
		status.text = "Der Ordner für generierte Texturen konnte nicht angelegt werden."
		return
	var path := "%s/body_%d_%d" % [folder, Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	if result.image.save_png(path + ".png") != OK or result.body_mask.save_png(path + "_body_mask.png") != OK or result.coverage.save_png(path + "_uv_coverage.png") != OK:
		status.text = "Die generierte Textur konnte nicht vollständig gespeichert werden."
		return
	var metadata: Dictionary = result.stats
	metadata["landmarks_path"] = pending_path
	metadata["normalized_path"] = pending_data.normalized_path
	metadata["base_texture"] = "res://textures/pelvicachromis_taeniatus_male_albedo.png"
	metadata["texture_path"] = ProjectSettings.globalize_path(path + ".png")
	var file := FileAccess.open(path + ".json", FileAccess.WRITE)
	if file == null:
		status.text = "Die Projektionsdaten konnten nicht gespeichert werden."
		return
	file.store_string(JSON.stringify(metadata, "\t"))
	file.flush()
	var success := file.get_error() == OK
	file.close()
	if not success:
		status.text = "Fehler beim Speichern der Projektionsdaten."
		return
	current_generated_path = metadata.texture_path
	current_body_mask_path = ProjectSettings.globalize_path(path + "_body_mask.png")
	current_coverage_path = ProjectSettings.globalize_path(path + "_uv_coverage.png")
	current_metadata_path = ProjectSettings.globalize_path(path + ".json")
	last_stats = metadata
	result.image.generate_mipmaps()
	generated_texture = ImageTexture.create_from_image(result.image)
	show_generated()

func _exit_tree() -> void:
	if worker != null and worker.is_started():
		worker.wait_to_finish()
