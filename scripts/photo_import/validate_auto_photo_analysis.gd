extends "res://scripts/validate_fish_viewer.gd"
const Analyzer=preload("res://scripts/photo_import/photo_analyzer.gd")
const Data=preload("res://scripts/project/project_data.gd")
const Mask=preload("res://scripts/polygon_mask.gd")
var importer: Control
var reports: Dictionary={}
func _initialize() -> void:call_deferred("run_analysis")
func wait_analysis() -> void:
	var deadline:=Time.get_ticks_msec()+15000
	while importer.analysis_worker!=null and Time.get_ticks_msec()<deadline:await create_timer(.05).timeout
	check(importer.analysis_worker==null,"Analysis timed out")
func record(name: String,result: Dictionary) -> void:
	var data:=result.duplicate(true)
	if data.has("fish_contour"):data.fish_contour=Data.points_to_json(data.fish_contour)
	if data.has("suggested_landmarks"):data.suggested_landmarks=Data.points_to_json(data.suggested_landmarks)
	for key in ["template_landmarks","pectoral_region"]:
		if data.has(key):data[key]=Data.points_to_json(data[key])
	reports[name]=Data.plain(data)
func run_analysis() -> void:
	viewer=load("res://scenes/PhotoImport.tscn").instantiate();root.add_child(viewer);root.size=Vector2i(1400,1050)
	await create_timer(.5).timeout
	importer=viewer.get_node("UI/ReferencePhoto")
	importer.project_manager.root=preload("res://scripts/storage/portable_paths.gd").projects_dir()+"/auto_analysis_tests/"+str(Time.get_ticks_usec())
	var path:=ProjectSettings.globalize_path("res://blender/reference/pelvicachromis_taeniatus_male.jpg")
	check(importer.load_photo(path),"Photo failed")
	await wait_analysis()
	var result: Dictionary=importer.analysis_result.duplicate(true);record("right",result)
	check(result.get("head_direction","")=="right","Right orientation")
	check(result.get("eye_detected",false),"Eye detection")
	check(importer.canvas.landmarks.size()==12 and importer.canvas.closed,"Suggestions incomplete")
	if importer.canvas.landmarks.size()!=12:finish();return
	check(importer.canvas.landmarks[1].distance_to(Vector2(669,275))<12,"Eye localisation")
	check(Mask.validation_error(importer.canvas.points,importer.source.get_size()).is_empty(),"Invalid auto contour")
	var mask: Image=Mask.build(importer.source,importer.canvas.points,0).mask
	for p in importer.canvas.landmarks:check(mask.get_pixelv(Vector2i(p)).r>.5,"Landmark outside mask: "+str(p))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://godot/diagnostics/auto_photo_editor.png")
	var source: Image=importer.source.duplicate()
	var original_points: PackedVector2Array=importer.canvas.landmarks.duplicate()
	# Every landmark must remain draggable, including all fin roots and tips.
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT
	var move_event:=InputEventMouseMotion.new()
	for i in range(12):
		click.pressed=true;click.position=importer.canvas.to_display(original_points[i]);importer.canvas._gui_input(click)
		move_event.position=click.position+Vector2(2,1);importer.canvas._gui_input(move_event);click.pressed=false;importer.canvas._gui_input(click)
		var corrected: Vector2=importer.canvas.landmarks[i]
		check(corrected!=original_points[i],"Drag failed for landmark "+str(i+1))
		check(importer.canvas.landmark_confidence[i].level=="MANUAL","Confidence not cleared after drag")
		importer.align_photo();check(importer.canvas.landmarks[i]==corrected,"Align discarded correction "+str(i+1))
		# Restore boundary points after testing; retain the safe eye correction.
		if i!=1:importer.canvas.landmarks[i]=original_points[i]
	var last_point: Vector2=importer.canvas.landmarks[-1]
	importer.undo();check(importer.canvas.landmark_confidence.size()==11,"Undo left stale confidence")
	click.pressed=true;click.position=importer.canvas.to_display(last_point);importer.canvas._gui_input(click);click.pressed=false;importer.canvas._gui_input(click)
	check(importer.canvas.landmarks.size()==12 and importer.canvas.landmark_confidence[-1].level=="MANUAL","Manual replacement confidence")
	# Mask remains editable after recognition.
	importer.mark();click.position=importer.canvas.to_display(importer.canvas.points[0]);click.pressed=true;importer.canvas._gui_input(click)
	move_event.position=click.position+Vector2(.5,0);importer.canvas._gui_input(move_event);click.pressed=false;importer.canvas._gui_input(click)
	importer.align_photo()
	check(importer.save_project("Automatischer Vorschlag"),"Save failed: "+importer.last_error)
	var id: String=importer.project_id;var saved_points: PackedVector2Array=importer.canvas.landmarks.duplicate();var saved_mask: PackedVector2Array=importer.canvas.points.duplicate()
	var count: int=importer.analysis_count
	importer.reset();check(importer.open_project(id),"Open failed")
	check(importer.analysis_count==count and importer.analysis_worker==null,"Saved project reanalysed")
	check(importer.canvas.landmark_confidence.is_empty(),"Old confidence leaked into saved project")
	check(importer.canvas.landmarks==saved_points and importer.canvas.points==saved_mask,"Saved corrections lost")
	# Reversed direction is explicitly editable without modifying photograph/contour.
	importer.correct_direction(1);check(importer.analysis_result.head_direction=="left","Manual direction failed")
	check(importer.canvas.points==saved_mask,"Direction correction changed mask")
	importer.open_project(id)
	importer.generate()
	var deadline:=Time.get_ticks_msec()+300000
	while importer.worker!=null and Time.get_ticks_msec()<deadline:await create_timer(.1).timeout
	check(importer.generated!=null,"Texture from automatic suggestions: "+importer.status.text)
	if importer.generated!=null:
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://godot/diagnostics/auto_photo_generated.png")
		importer.show_original();check(not importer.showing_generated,"Original toggle")
		importer.show_generated();check(importer.showing_generated,"Generated toggle")
		check(importer.save_project("Automatischer Vorschlag"),"Generated project save failed")
		var generated_path: String=importer.texture_path
		var before_reopen: int=importer.analysis_count
		importer.reset();check(importer.open_project(id),"Generated project reopen failed")
		check(importer.generated!=null and importer.showing_generated,"Saved generated appearance missing")
		check(importer.analysis_count==before_reopen,"Generated project was reanalysed")
		check(not generated_path.is_empty(),"Generated texture path missing")
		# Actual photo-generated texture must survive movement and return to editing.
		var appearance: ImageTexture=importer.generated
		var project_before: String=importer.project_id
		viewer.begin_fish_control();Input.action_press("fish_forward")
		await create_timer(.3).timeout;Input.action_release("fish_forward")
		check(viewer.control_mode and viewer.fish_controller.speed>0,"Generated fish movement")
		check(importer.generated==appearance and importer.showing_generated,"Photo texture lost in steering")
		viewer.end_fish_control()
		check(importer.visible and importer.project_id==project_before and importer.generated==appearance,"Editing/project restoration after steering")
	for skeleton in viewer.fish.find_children("*","Skeleton3D",true,false):check(skeleton.get_bone_count()==15,"Bone count")
	await create_timer(2.2).timeout;check(viewer.animation_player.is_playing(),"Swim_Test")
	var center: Vector2=viewer.get_node("ViewerViewport").get_global_rect().get_center()
	mouse(MOUSE_BUTTON_LEFT,true,center);move(center+Vector2(60,20),Vector2(60,20));mouse(MOUSE_BUTTON_LEFT,false,center+Vector2(60,20));check(absf(viewer.orbit.yaw)>.05,"Orbit")
	var distance: float=viewer.orbit.distance;mouse(MOUSE_BUTTON_WHEEL_UP,true,center);check(viewer.orbit.distance<distance,"Zoom")
	await click(viewer.reset_button);check(viewer.orbit.yaw==0,"Reset camera")
	for size in [Vector2i(600,900),Vector2i(480,360)]:
		root.size=size;await create_timer(.2).timeout;check(root.get_visible_rect().encloses(importer.panel.get_global_rect()),"Small window overflow")
	var mirrored: Image=source.duplicate();mirrored.flip_x();var mirror:=Analyzer.analyze(mirrored);record("left",mirror)
	check(mirror.get("head_direction","")=="left","Left orientation")
	check(mirror.get("suggested_landmarks",[]).size()==12,"Left landmarks")
	var large: Image=source.get_region(Rect2i(0,100,800,600));large.resize(4000,3000)
	var big:=Analyzer.analyze(large);record("large",big)
	check(big.get("head_direction","")=="right","4000x3000 analysis")
	if big.has("eye_position"):check(big.eye_position.distance_to(Vector2(669,175)*5)<65,"Original pixel conversion")
	var small: Image=source.duplicate();small.resize(200,200);var tiny:=Analyzer.analyze(small);record("small",tiny)
	check(tiny.get("suggested_landmarks",[]).size()==12,"Small photo analysis")
	var blank:=Image.create(320,240,false,Image.FORMAT_RGB8);blank.fill(Color(.3,.3,.3));check(Analyzer.analyze(blank).has("error"),"Blank detection did not fail")
	var blank_path:=preload("res://scripts/storage/portable_paths.gd").data_dir()+"/blank_analysis.png";blank.save_png(blank_path)
	check(importer.load_photo(ProjectSettings.globalize_path(blank_path)),"Blank photo load")
	await wait_analysis();check(importer.canvas.mode=="mask" and importer.canvas.landmarks.is_empty(),"Manual fallback")
	check(importer.load_photo(path),"Reload");await wait_analysis();check(importer.canvas.landmarks.size()==12,"Reset/reload analysis")
	# New photo/manual input must win over a late worker result.
	importer.load_photo(path);importer.manual_analysis();importer.align_photo();importer.canvas.landmarks.append(Vector2(100,100));importer.changed()
	await wait_analysis();check(importer.canvas.landmarks==PackedVector2Array([Vector2(100,100)]),"Late analysis overwrote manual data")
	importer.load_photo(path);importer.open_project(id);await wait_analysis();check(importer.canvas.landmarks==saved_points,"Late analysis overwrote project")
	finish()
func finish() -> void:
	reports.errors=errors
	FileAccess.open("res://godot/diagnostics/auto_photo_analysis.json",FileAccess.WRITE).store_string(JSON.stringify(reports,"\t"))
	print("AUTO PHOTO ANALYSIS: ",errors);quit(0 if errors.is_empty() else 1)
