extends Control
const Analyzer=preload("res://scripts/photo_import/photo_analyzer.gd")
const Editor=preload("res://scripts/photo_import/landmark_editor.gd")
const Projector=preload("res://scripts/photo_import/texture_projection.gd")
const Mask=preload("res://scripts/polygon_mask.gd")
const ProjectManager=preload("res://scripts/project/project_manager.gd")
const ProjectData=preload("res://scripts/project/project_data.gd")
const ProjectBrowser=preload("res://scripts/project/project_browser.gd")
var project_manager=ProjectManager.new()
var project_id:=""
var project_name:=""
var transform_data: Dictionary={}
var generation_data: Dictionary={}
var project_browser: VBoxContainer
var viewer: Node3D
var panel: PanelContainer
var scroll: ScrollContainer
var canvas: TextureRect
var status: Label
var side: OptionButton
var resolution: OptionButton
var dialog: FileDialog
var generate_button: Button
var source: Image
var source_path:=""
var texture_path:=""
var metadata_path:=""
var originals: Dictionary={}
var analysis_worker: Thread
var analysis_revision:=-1
var analysis_result: Dictionary={}
var analysis_count:=0
var orientation: OptionButton
var analysis_status: Label
var worker: Thread
var revision:=0
var pending_revision:=0
var generated: ImageTexture
var showing_generated:=false
var last_error:=""
func button(parent: Control,title: String,action: Callable) -> Button:
	var b:=Button.new();b.text=title;parent.add_child(b);b.pressed.connect(action);return b
func _ready() -> void:
	viewer=get_parent().get_parent()
	panel=PanelContainer.new();add_child(panel)
	scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;panel.add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(column)
	var title:=Label.new();title.text="Foto importieren";title.add_theme_font_size_override("font_size",20);column.add_child(title)
	project_browser=ProjectBrowser.new();project_browser.controller=self;project_browser.manager=project_manager;column.add_child(project_browser)
	var row:=HFlowContainer.new();column.add_child(row)
	button(row,"Foto auswählen",choose)
	button(row,"Ausrichten",align_photo)
	generate_button=button(row,"Textur erzeugen",generate)
	button(row,"Zurücksetzen",reset)
	side=OptionButton.new();side.add_item("Linke Fischseite");side.add_item("Rechte Fischseite");column.add_child(side);side.item_selected.connect(func(_i): changed())
	resolution=OptionButton.new();resolution.add_item("2048 × 2048 · schneller");resolution.add_item("4096 × 4096 · Details");column.add_child(resolution)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(status)
	analysis_status=Label.new();analysis_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(analysis_status)
	row=HFlowContainer.new();column.add_child(row)
	orientation=OptionButton.new();orientation.tooltip_text="Kopfseite korrigieren: setzt die zwölf Punktvorschläge neu. Die Kontur bleibt erhalten.";orientation.add_item("Kopf rechts");orientation.add_item("Kopf links");row.add_child(orientation)
	orientation.item_selected.connect(correct_direction)
	button(row,"Manuell beginnen",manual_analysis)
	canvas=Editor.new();canvas.custom_minimum_size.y=330;canvas.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;canvas.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;column.add_child(canvas)
	canvas.landmarks_changed.connect(changed);canvas.contour_changed.connect(changed);canvas.close_requested.connect(close_mask)
	row=HFlowContainer.new();column.add_child(row)
	button(row,"Maske zeichnen / korrigieren",mark)
	button(row,"Kontur schließen",close_mask)
	button(row,"Maske neu zeichnen",func(): canvas.clear_contour();mark())
	button(row,"Letzten Punkt entfernen",undo)
	row=HFlowContainer.new();column.add_child(row)
	button(row,"Originalfärbung",show_original)
	button(row,"Generierte Färbung",show_generated)
	var hint:=Label.new();hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hint.text="1 Foto und fotografierte Seite wählen. 2 Automatische Vorschläge prüfen; Punkte durch Ziehen korrigieren. 3 Fischkontur prüfen oder manuell markieren. 4 Textur erzeugen. Die Gegenseite wird vorläufig aus demselben Foto befüllt.";column.add_child(hint)
	var legend:=Label.new();legend.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	for i in range(Editor.LABELS.size()):legend.text+="%d %s%s" % [i+1,Editor.LABELS[i]," · " if i<11 else ""]
	column.add_child(legend)
	dialog=FileDialog.new();dialog.title="Foto auswählen";dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;dialog.filters=PackedStringArray(["*.jpg,*.jpeg,*.png ; Fischfoto (JPG, JPEG, PNG)"]);add_child(dialog);dialog.file_selected.connect(load_photo)
	get_viewport().size_changed.connect(layout)
	call_deferred("prepare")
	status.text="Ein seitliches Foto auswählen."
func prepare() -> void:
	for node in viewer.fish.find_children("*","MeshInstance3D",true,false):
		if node.name=="Fish_Body" or "Fin" in node.name:
			var entries: Array=[]
			for i in range(node.mesh.get_surface_count()):entries.append({"override":node.get_surface_override_material(i),"active":node.get_active_material(i)})
			originals[node]=entries
	layout()
func layout() -> void:
	var size: Vector2=get_viewport_rect().size
	var viewport: Control=viewer.get_node("ViewerViewport")
	viewport.set_anchors_preset(Control.PRESET_TOP_LEFT)
	if size.x>=850:
		panel.position=Vector2(12,88);panel.size=Vector2(size.x*.46-18,maxf(100,size.y-156))
		viewport.position=Vector2(size.x*.46,85);viewport.size=Vector2(size.x*.54,size.y-145)
	else:
		panel.position=Vector2(8,82);panel.size=Vector2(size.x-16,maxf(100,(size.y-150)*.55))
		viewport.position=Vector2(0,panel.position.y+panel.size.y+5);viewport.size=Vector2(size.x,maxf(80,size.y-viewport.position.y-60))
	canvas.custom_minimum_size.y=clampf(panel.size.y*.65,180,520)
	call_deferred("fit_viewport")
func fit_viewport() -> void:
	await get_tree().process_frame
	# Header and buttons already sit outside this dedicated 3D rectangle.
	viewer.orbit.reserved_height=0.0
	viewer.orbit._resize()
func choose() -> void:
	viewer.orbit.dragging=false;dialog.popup_centered_clamped(Vector2i(850,600),.9)
func fail(message: String) -> bool:
	last_error=message;status.text=message;return false
func load_photo(path: String) -> bool:
	if path.get_extension().to_lower() not in ["jpg","jpeg","png"]:return fail("Bitte JPG, JPEG oder PNG auswählen.")
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return fail("Das Foto ist nicht lesbar.")
	if file.get_length()>64*1024*1024:return fail("Bitte ein Foto unter 64 MB auswählen.")
	var bytes:=file.get_buffer(file.get_length());file.close()
	var png:=path.get_extension().to_lower()=="png"
	if bytes.size()<12 or (png and bytes.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10])) or (not png and (bytes[0]!=255 or bytes[1]!=216)):return fail("Die Bilddatei ist ungültig oder beschädigt.")
	var image:=Image.new()
	var error:=image.load_png_from_buffer(bytes) if png else image.load_jpg_from_buffer(bytes)
	if error!=OK or image.is_empty():return fail("Die Bilddatei konnte nicht gelesen werden.")
	reset();set_photo_image(image,path);align_photo();start_analysis();return true
func set_photo_image(image: Image,path: String) -> void:
	source=image;source_path=path.simplify_path()
	var preview: Image=image.duplicate()
	var factor:=minf(1,1600.0/maxi(image.get_width(),image.get_height()))
	preview.resize(maxi(1,roundi(image.get_width()*factor)),maxi(1,roundi(image.get_height()*factor)))
	canvas.texture=ImageTexture.create_from_image(preview);canvas.original_size=image.get_size()
func changed() -> void:
	if analysis_revision==revision:
		analysis_revision=-1;analysis_status.text="Manuelle Eingabe übernommen; automatischer Vorschlag verworfen."
	revision+=1;canvas.queue_redraw()
	if canvas.landmarks.size()>=4:orientation.select(0 if canvas.landmarks[0].x>(canvas.landmarks[2].x+canvas.landmarks[3].x)*.5 else 1)
	if source==null:return
	if canvas.mode=="landmarks":
		status.text="Punkt %d/12: %s" % [canvas.landmarks.size()+1,Editor.LABELS[canvas.landmarks.size()]] if canvas.landmarks.size()<12 else ("Zwölf Punkte gesetzt. Punkte und Kontur prüfen, dann Textur erzeugen." if canvas.closed else "Zwölf Punkte gesetzt. Bei Bedarf ziehen, dann Fischmaske zeichnen.")
	else:status.text="Konturpunkte ziehen zum Korrigieren." if canvas.closed else "Fisch mit Mausklicks umranden, dann Kontur schließen."
func align_photo() -> void:
	canvas.mode="landmarks";canvas.drag_index=-1;changed()
func mark() -> void:
	if source==null:return
	canvas.mode="mask";canvas.marking=true;canvas.drag_index=-1;changed()
func close_mask() -> void:
	if source==null:return
	var error:=Mask.validation_error(canvas.points,source.get_size())
	if not error.is_empty():fail(error);return
	canvas.closed=true;canvas.marking=false;changed();status.text="Maske geschlossen. Punkte bleiben verschiebbar. Textur kann erzeugt werden."
func undo() -> void:
	if canvas.mode=="landmarks" and not canvas.landmarks.is_empty():canvas.landmarks.remove_at(canvas.landmarks.size()-1)
	elif canvas.mode=="mask" and not canvas.points.is_empty():canvas.points.remove_at(canvas.points.size()-1);canvas.closed=false;canvas.marking=true
	changed()
func generate() -> void:
	if worker!=null or source==null or analysis_revision==revision:return
	if not canvas.closed:fail("Bitte zuerst die Fischkontur schließen.");return
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/photo_import_projection.json"))
	var check:=Projector.alignment(canvas.landmarks,config)
	if check.has("error"):fail(check.error);return
	var error:=Mask.validation_error(canvas.points,source.get_size())
	if not error.is_empty():fail(error);return
	pending_revision=revision;worker=Thread.new();canvas.locked=true
	var started:=worker.start(Projector.generate.bind(source.duplicate(),canvas.landmarks.duplicate(),canvas.points.duplicate(),"left" if side.selected==0 else "right",2048 if resolution.selected==0 else 4096,source_path))
	if started!=OK:worker=null;canvas.locked=false;fail("Berechnung konnte nicht gestartet werden.");return
	status.text="Maske, Ausrichtung und Textur werden lokal berechnet … Der 3D Viewer bleibt bedienbar."
func _process(_delta: float) -> void:
	poll_analysis()
	generate_button.disabled=worker!=null or source==null or analysis_revision==revision
	if worker==null or worker.is_alive():return
	var result: Dictionary=worker.wait_to_finish();worker=null;canvas.locked=false
	if pending_revision!=revision:return
	if result.has("error"):fail(result.error);return
	result.image.generate_mipmaps();generated=ImageTexture.create_from_image(result.image)
	texture_path=result.path;metadata_path=result.metadata_path;generation_data=result.metadata.duplicate(true)
	show_generated();status.text="Textur aktiv. Gegenseite vorläufig gespiegelt; verdeckte paarige Flossen verwenden die sichtbare Seite."
func show_original() -> void:
	for node in originals:
		for i in range(originals[node].size()):node.set_surface_override_material(i,originals[node][i].override)
	showing_generated=false
func show_generated() -> void:
	if generated==null:return
	for node in originals:
		for i in range(originals[node].size()):
			var material: BaseMaterial3D=originals[node][i].active.duplicate()
			material.albedo_texture=generated;node.set_surface_override_material(i,material)
	showing_generated=true
func reset() -> void:
	analysis_revision=-1;analysis_result={};analysis_status.text="";orientation.select(0)
	project_id="";project_name="";transform_data={};generation_data={}
	side.select(0);resolution.select(0);canvas.mode="landmarks"
	revision+=1;show_original();source=null;source_path="";texture_path="";metadata_path="";generated=null;last_error=""
	canvas.texture=null;canvas.landmarks.clear();canvas.clear_contour();canvas.drag_index=-1;canvas.locked=false
	status.text="Ein seitliches Foto auswählen."
func _exit_tree() -> void:
	if analysis_worker!=null and analysis_worker.is_started():analysis_worker.wait_to_finish()
	if worker!=null and worker.is_started():worker.wait_to_finish()

func save_project(name: String,as_new: bool=false) -> bool:
	if worker!=null or analysis_revision==revision:return fail("Bitte das Ende der Berechnung abwarten.")
	if source==null:return fail("Bitte zuerst ein Foto auswählen.")
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/photo_import_projection.json"))
	var aligned:=Projector.alignment(canvas.landmarks,config)
	transform_data={} if aligned.has("error") else ProjectData.plain(aligned)
	var state: Dictionary={"id":"" if as_new else project_id,"name":name,"photographed_side":"left" if side.selected==0 else "right","resolution":2048 if resolution.selected==0 else 4096,"landmark_points":ProjectData.points_to_json(canvas.landmarks),"mask_points":ProjectData.points_to_json(canvas.points),"mask_closed":canvas.closed,"transform_data":transform_data,"generation_data":generation_data.duplicate(true),"original_photo_path":source_path,"ui_state":{"mode":canvas.mode,"showing_generated":showing_generated}}
	var image: Image=null
	if generated!=null:
		image=generated.get_image()
		if image.is_compressed():image.decompress()
		image.clear_mipmaps()
	var result: Dictionary=project_manager.save_project(state,source,image)
	if result.has("error"):return fail(result.error)
	project_id=result.data.id;project_name=result.data.name
	status.text="Projekt „%s“ gespeichert." % project_name;last_error="";return true
func open_project(id: String) -> bool:
	# Fully load and validate before replacing the current editor state.
	var result: Dictionary=project_manager.load_project(id)
	if result.has("error"):return fail(result.error)
	var data: Dictionary=result.data
	reset();set_photo_image(result.photo,result.photo_path)
	project_id=id;project_name=data.name
	side.select(0 if data.photographed_side=="left" else 1)
	resolution.select(0 if data.resolution==2048 else 1)
	canvas.landmarks=ProjectData.points_from_json(data.landmark_points)
	if canvas.landmarks.size()>=4:orientation.select(0 if canvas.landmarks[0].x>(canvas.landmarks[2].x+canvas.landmarks[3].x)*.5 else 1)
	canvas.points=ProjectData.points_from_json(data.mask_points)
	canvas.closed=data.mask_closed;canvas.mode=data.ui_state.mode
	canvas.marking=canvas.mode=="mask" and not canvas.closed;canvas.queue_redraw()
	transform_data=data.transform_data.duplicate(true)
	generation_data=data.get("generation_data",{}).duplicate(true)
	metadata_path=project_manager.folder(id)+"/project.json"
	if result.texture!=null:
		result.texture.generate_mipmaps();generated=ImageTexture.create_from_image(result.texture)
		texture_path=project_manager.folder(id)+"/"+data.generated_texture_path
		if data.ui_state.showing_generated:show_generated()
	status.text="Projekt „%s“ geladen." % project_name
	if canvas.mode=="landmarks" and canvas.landmarks.size()<12:status.text+="\nNächster Punkt: "+Editor.LABELS[canvas.landmarks.size()]
	if not result.warnings.is_empty():status.text+="\n"+"\n".join(result.warnings)
	last_error="";return true

func start_analysis() -> void:
	# At most one bounded analysis task; a new photo discards the previous result.
	if analysis_worker!=null:analysis_worker.wait_to_finish()
	analysis_worker=Thread.new();analysis_revision=revision;analysis_count+=1
	analysis_status.text="Foto wird lokal analysiert … Manuelle Eingaben haben Vorrang."
	if analysis_worker.start(Analyzer.analyze.bind(source.duplicate()))!=OK:
		analysis_worker=null;analysis_revision=-1;analysis_status.text="Analyse nicht verfügbar. Bitte manuell markieren.";mark()
func poll_analysis() -> void:
	if analysis_worker==null or analysis_worker.is_alive():return
	var result: Dictionary=analysis_worker.wait_to_finish();analysis_worker=null
	var current:=analysis_revision==revision;analysis_revision=-1
	if not current:return
	if result.has("error"):
		analysis_status.text=result.error;mark();return
	apply_suggestion(result)
func apply_suggestion(result: Dictionary) -> void:
	analysis_result=result
	canvas.points=result.fish_contour.duplicate();canvas.closed=true;canvas.marking=false
	canvas.landmarks=result.suggested_landmarks.duplicate();canvas.mode="landmarks"
	orientation.select(0 if result.head_direction=="right" else 1)
	changed()
	analysis_status.text="Kontur automatisch vorgeschlagen. Alle Punkte und Flossenansätze bitte prüfen. Auge: "+result.confidence.eye+"."
func manual_analysis() -> void:
	# Cancels adoption of any pending result, without waiting for the worker.
	analysis_revision=-1;analysis_result={};canvas.landmarks.clear();canvas.clear_contour();mark()
	analysis_status.text="Manuelle Markierung aktiv. Danach mit Ausrichten die zwölf Punkte setzen."
func correct_direction(index: int) -> void:
	if source==null:return
	analysis_revision=-1
	if canvas.points.size()<3:
		analysis_status.text="Kopfseite gewählt. Schnauze und Auge bitte manuell setzen.";return
	# Only an explicit orientation correction proposes a new landmark set.
	# The user's edited mask is preserved; ordinary Ausrichten never resets points.
	var result:=Analyzer.suggest(source,canvas.points,"right" if index==0 else "left")
	apply_suggestion(result)
