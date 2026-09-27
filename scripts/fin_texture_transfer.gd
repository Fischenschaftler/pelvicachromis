extends VBoxContainer
const NAMES=["Caudal_Fin","Dorsal_Fin","Anal_Fin"]
const LABELS=["Schwanzflosse","Rückenflosse","Afterflosse"]
const Canvas=preload("res://scripts/fin_polygon_canvas.gd")
const MaskBuilder=preload("res://scripts/polygon_mask.gd")
const Baker=preload("res://scripts/fin_texture_baker.gd")
var transfer: VBoxContainer
var landmarks: VBoxContainer
var canvas: TextureRect
var selector: OptionButton
var status: Label
var start_button: Button
var close_button: Button
var reset_button: Button
var generate_button: Button
var photo: Image
var polygons: Dictionary={}
var masks: Dictionary={}
var mask_paths: Dictionary={}
var observed_body:=""
var observed_landmarks:=""
var revision:=0
var worker: Thread
var pending_revision:=0
var current_path:=""
var metadata_path:=""
var coverage_path:=""

func _ready() -> void:
	var row:=HFlowContainer.new();add_child(row)
	start_button=make_button(row,"Flossen markieren",start)
	selector=OptionButton.new()
	for label in LABELS:selector.add_item(label)
	row.add_child(selector);selector.item_selected.connect(select_fin)
	close_button=make_button(row,"Kontur schließen",close_contour)
	reset_button=make_button(row,"Flosse zurücksetzen",reset_selected)
	generate_button=make_button(row,"Flossenfärbung übertragen",generate)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(status)
	canvas=Canvas.new();canvas.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	canvas.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	canvas.custom_minimum_size.y=320;add_child(canvas)
	canvas.close_requested.connect(close_contour)
	hide();canvas.hide()

func make_button(row: Control,text: String,action: Callable) -> Button:
	var b:=Button.new();b.text=text;b.add_theme_font_size_override("font_size",13)
	row.add_child(b);b.pressed.connect(action);return b

func clear() -> void:
	selector.select(0)
	revision+=1
	polygons.clear();masks.clear();mask_paths.clear()
	current_path="";metadata_path="";coverage_path=""
	canvas.clear_contour();canvas.saved_polygons={};canvas.texture=null;canvas.hide()
	photo=null
	status.text="Drei Flossen getrennt markieren: Schwanz, Rücken, After."

func start() -> void:
	if worker!=null:return
	if photo==null:
		photo=Image.new()
		if photo.load_png_from_buffer(FileAccess.get_file_as_bytes(landmarks.current_normalized_path))!=OK:
			status.text="Normalisierte Arbeitskopie nicht lesbar.";photo=null;return
		canvas.texture=ImageTexture.create_from_image(photo)
		canvas.original_size=photo.get_size()
	canvas.show()
	select_fin(selector.selected)
	update_minimum_size()
	get_parent().update_minimum_size()
	get_parent().reset_size()
	var parent_node:=get_parent()
	while parent_node!=null:
		if parent_node is ScrollContainer:parent_node.call_deferred("ensure_control_visible",canvas)
		parent_node=parent_node.get_parent()

func select_fin(index: int) -> void:
	selector.select(index)
	canvas.clear_contour()
	canvas.saved_polygons=polygons.duplicate(true)
	var name: String=NAMES[index]
	if polygons.has(name):
		canvas.points=polygons[name].duplicate();canvas.closed=true
		status.text="%s gespeichert. Zum Ändern Flosse zurücksetzen." % LABELS[index]
	else:
		canvas.marking=photo!=null
		status.text="%d/3 · %s: Kontur samt Flossenansatz anklicken; Doppelklick oder Kontur schließen." % [index+1,LABELS[index]]
	canvas.queue_redraw()

func reset_selected() -> void:
	if worker!=null:return
	revision+=1
	var name: String=NAMES[selector.selected]
	polygons.erase(name);masks.erase(name);mask_paths.erase(name)
	select_fin(selector.selected)

func close_contour() -> void:
	if photo==null or not canvas.marking or worker!=null:return
	var points: PackedVector2Array=canvas.points.duplicate()
	if points.size()>3 and points[0].distance_to(points[-1])<.5:points.remove_at(points.size()-1)
	var problem: String=MaskBuilder.validation_error(points,photo.get_size())
	if not problem.is_empty():status.text=problem;return
	var result: Dictionary=MaskBuilder.build(photo,points,revision)
	var mask: Image=result.mask
	var count:=0
	for y in range(mask.get_height()):
		for x in range(mask.get_width()):
			if photo.get_pixel(x,y).a<=.001:mask.set_pixel(x,y,Color.BLACK)
			elif mask.get_pixel(x,y).r>.5:count+=1
	if count<16:status.text="Die Kontur enthält zu wenig freigestellte Flossenfläche.";return
	var folder:="user://fin_masks"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))!=OK:status.text="Maskenordner nicht beschreibbar.";return
	var name: String=NAMES[selector.selected]
	var path:="%s/%s_%d.png" % [folder,name,Time.get_ticks_usec()]
	if mask.save_png(path)!=OK:status.text="Flossenmaske konnte nicht gespeichert werden.";return
	var coords: Array=[]
	for p in points:coords.append([p.x,p.y])
	var file:=FileAccess.open(path.get_basename()+".json",FileAccess.WRITE)
	if file==null:status.text="Konturdaten konnten nicht gespeichert werden.";return
	file.store_string(JSON.stringify({"fin":name,"normalized_path":landmarks.current_normalized_path,"landmarks_path":landmarks.current_landmark_path,"body_texture_path":transfer.body_texture_path,"points_normalized_px":coords,"mask_path":ProjectSettings.globalize_path(path)},"\t"));file.close()
	polygons[name]=points;masks[name]=mask;mask_paths[name]=ProjectSettings.globalize_path(path)
	revision+=1
	if selector.selected<2:select_fin(selector.selected+1)
	else:
		select_fin(selector.selected)
		status.text="Alle drei Masken gespeichert. Flossenfärbung übertragen."

func generate() -> void:
	if worker!=null or masks.size()!=3 or transfer.worker!=null:return
	var model: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/body_projection.json"))
	var fins: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/fin_projection.json"))
	if FileAccess.get_sha256("res://models/pelvicachromis_taeniatus_male.glb")!=fins.source_glb_sha256:status.text="Modell und Flossen-UV-Daten stimmen nicht überein.";return
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(landmarks.current_landmark_path))
	var base:=Image.new()
	if base.load_png_from_buffer(FileAccess.get_file_as_bytes(transfer.body_texture_path))!=OK:status.text="Körpertextur nicht lesbar.";return
	pending_revision=revision
	worker=Thread.new();transfer.fin_busy=true
	if worker.start(Baker.bake.bind(base,photo,data,model,fins.fins,polygons.duplicate(true),masks.duplicate()))!=OK:
		worker=null;transfer.fin_busy=false;status.text="Flossenberechnung konnte nicht gestartet werden.";return
	status.text="Drei Flossen werden projiziert …"

func _process(_delta: float) -> void:
	if observed_body!=transfer.body_texture_path or observed_landmarks!=landmarks.current_landmark_path:
		observed_body=transfer.body_texture_path;observed_landmarks=landmarks.current_landmark_path;clear()
	visible=not observed_body.is_empty() and not observed_landmarks.is_empty() and observed_landmarks==transfer.body_landmark_path
	start_button.disabled=worker!=null
	selector.disabled=worker!=null
	reset_button.disabled=worker!=null or photo==null
	close_button.disabled=worker!=null or not canvas.marking
	generate_button.disabled=worker!=null or masks.size()!=3 or transfer.worker!=null
	if worker==null or worker.is_alive():return
	var result: Dictionary=worker.wait_to_finish();worker=null;transfer.fin_busy=false
	if pending_revision!=revision:return
	if result.has("error"):status.text=result.error;return
	var folder:="user://generated_textures"
	var path:="%s/combined_%d_%d" % [folder,Time.get_unix_time_from_system(),Time.get_ticks_usec()]
	if result.image.save_png(path+".png")!=OK or result.coverage.save_png(path+"_fin_coverage.png")!=OK:status.text="Gesamttextur konnte nicht gespeichert werden.";return
	var records: Dictionary={}
	for name in NAMES:
		var coords: Array=[]
		for p in polygons[name]:coords.append([p.x,p.y])
		records[name]={"points_normalized_px":coords,"mask_path":mask_paths[name]}
	var metadata: Dictionary={"body_texture_path":transfer.body_texture_path,"landmarks_path":observed_landmarks,"normalized_path":landmarks.current_normalized_path,"texture_path":ProjectSettings.globalize_path(path+".png"),"fins":records,"stats":result.stats}
	var file:=FileAccess.open(path+".json",FileAccess.WRITE)
	if file==null:status.text="Projektionsdaten konnten nicht gespeichert werden.";return
	file.store_string(JSON.stringify(metadata,"\t"));file.flush()
	var success:=file.get_error()==OK;file.close()
	if not success:status.text="Projektionsdaten konnten nicht gespeichert werden.";return
	current_path=metadata.texture_path;metadata_path=ProjectSettings.globalize_path(path+".json");coverage_path=ProjectSettings.globalize_path(path+"_fin_coverage.png")
	transfer.install_combined(result.image,current_path,metadata_path)
	status.text="Körper, Schwanz-, Rücken- und Afterflosse aktiv. Andere Bereiche unverändert."

func _exit_tree() -> void:
	if worker!=null and worker.is_started():worker.wait_to_finish()
