extends "res://scripts/validate_fish_viewer.gd"
var importer: Control
var materials: Dictionary={}
var arrays: Dictionary={}
func _initialize() -> void:call_deferred("run_import")
func run_import() -> void:
	viewer=load("res://scenes/PhotoImport.tscn").instantiate();root.add_child(viewer);root.size=Vector2i(1400,1000)
	await create_timer(.5).timeout
	importer=viewer.get_node("UI/ReferencePhoto")
	for node in viewer.fish.find_children("*","MeshInstance3D",true,false):
		for i in range(node.mesh.get_surface_count()):
			materials[String(node.name)+str(i)]=node.get_active_material(i).get_instance_id()
			arrays[String(node.name)+str(i)]=hash(node.mesh.surface_get_arrays(i))
	check(not importer.load_photo("res://project.godot"),"Invalid format accepted")
	var path:=ProjectSettings.globalize_path("res://blender/reference/pelvicachromis_taeniatus_male.jpg")
	check(importer.load_photo(path),"Photo load failed");importer.manual_analysis();importer.align_photo()
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/photo_import_projection.json"))
	var points:=PackedVector2Array()
	for p in config.anchors:points.append(Vector2(p[0],p[1])*670+Vector2(400,400))
	var projector=load("res://scripts/photo_import/texture_projection.gd")
	for factor in [.25,5.0]:
		var scaled:=PackedVector2Array()
		for q in points:scaled.append(q*factor)
		check(not projector.alignment(scaled,config).has("error"),"Small/4000px alignment failed")
	for p in points:
		var pos: Vector2=importer.canvas.to_display(p)
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=pos;importer.canvas._gui_input(event)
	check(importer.canvas.landmarks.size()==12,"Landmark input failed")
	var p: Vector2=importer.canvas.to_display(points[1])
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=p;importer.canvas._gui_input(click)
	var motion:=InputEventMouseMotion.new();motion.position=p+Vector2(2,1);importer.canvas._gui_input(motion)
	check(importer.canvas.landmarks[1].distance_to(points[1])>0,"Landmark drag failed")
	click.pressed=false;importer.canvas._gui_input(click)
	importer.canvas.landmarks=points.duplicate()
	var all:=PackedVector2Array()
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/body_projection.json"))
	for q in body.body_outline:all.append(Vector2(q[0],q[1])*670+Vector2(400,400))
	for fin in config.fins.values():
		for q in fin.xy:all.append(Vector2(q[0],q[1])*670+Vector2(400,400))
	# Slightly expanded manual test silhouette encloses all model-derived landmarks.
	var hull:=Geometry2D.convex_hull(all)
	if hull[0]==hull[-1]:hull.remove_at(hull.size()-1)
	var center:=Vector2(400,400)
	for i in range(hull.size()):hull[i]=(center+(hull[i]-center)*1.04).clamp(Vector2.ONE,Vector2(799,799))
	importer.canvas.points=hull.duplicate();importer.close_mask()
	importer.generate()
	var deadline:=Time.get_ticks_msec()+300000
	while importer.worker!=null and Time.get_ticks_msec()<deadline:await create_timer(.1).timeout
	check(not importer.texture_path.is_empty(),"Texture generation failed: "+importer.status.text)
	if importer.texture_path.is_empty():print(errors);quit(1);return
	check(importer.showing_generated,"Live texture missing")
	var left_path: String=importer.metadata_path
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://godot/diagnostics/photo_import_ui.png")
	for node in viewer.fish.find_children("*","Skeleton3D",true,false):check(node.get_bone_count()==15,"Bone count changed")
	for node in viewer.fish.find_children("*","MeshInstance3D",true,false):
		for i in range(node.mesh.get_surface_count()):check(hash(node.mesh.surface_get_arrays(i))==arrays[String(node.name)+str(i)],"Mesh/skinning changed")
	await create_timer(2.2).timeout
	check(viewer.animation_player.is_playing(),"Swim_Test stopped")
	var center_view: Vector2=viewer.get_node("ViewerViewport").get_global_rect().get_center()
	mouse(MOUSE_BUTTON_LEFT,true,center_view);move(center_view+Vector2(60,25),Vector2(60,25));mouse(MOUSE_BUTTON_LEFT,false,center_view+Vector2(60,25))
	check(absf(viewer.orbit.yaw)>.05,"Orbit input failed")
	var distance: float=viewer.orbit.distance
	mouse(MOUSE_BUTTON_WHEEL_UP,true,center_view);check(viewer.orbit.distance<distance,"Zoom input failed")
	await click(viewer.reset_button);check(viewer.orbit.yaw==0,"Camera reset failed")
	importer.show_original();check(not importer.showing_generated,"Original toggle failed");importer.show_generated()
	# Opposite photo orientation and chosen anatomical side are independent.
	var image: Image=importer.source.duplicate();image.flip_x()
	var flipped_path:="res://.godot/photo_import_right.png";image.save_png(flipped_path)
	check(importer.load_photo(ProjectSettings.globalize_path(flipped_path)),"PNG load failed");importer.manual_analysis();importer.align_photo()
	for i in range(points.size()):points[i].x=800-points[i].x
	for i in range(hull.size()):hull[i].x=800-hull[i].x
	importer.canvas.landmarks=points.duplicate();importer.canvas.points=hull.duplicate();importer.canvas.closed=true;importer.side.select(1);importer.changed()
	importer.generate();deadline=Time.get_ticks_msec()+300000
	while importer.worker!=null and Time.get_ticks_msec()<deadline:await create_timer(.1).timeout
	check(not importer.texture_path.is_empty(),"Right-side generation failed: "+importer.status.text)
	var right_path: String=importer.metadata_path
	if not right_path.is_empty():
		var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(right_path));check(data.photo_side=="right" and data.normalized.mirrored,"Side/orientation metadata wrong")
	for size in [Vector2i(600,900),Vector2i(480,360)]:
		root.size=size;await create_timer(.2).timeout;check(root.get_visible_rect().encloses(importer.panel.get_global_rect()),"Panel exceeds window")
	importer.reset();check(importer.source==null and importer.canvas.landmarks.is_empty() and importer.generated==null,"Reset state failed")
	for node in viewer.fish.find_children("*","MeshInstance3D",true,false):
		for i in range(node.mesh.get_surface_count()):check(node.get_active_material(i).get_instance_id()==materials[String(node.name)+str(i)],"Original material not restored")
	FileAccess.open("res://godot/diagnostics/photo_import_ui_validation.json",FileAccess.WRITE).store_string(JSON.stringify({"errors":errors,"left":left_path,"right":right_path,"bones":15,"live_texture":true},"\t"))
	print("PHOTO IMPORT TESTS: ",errors);quit(0 if errors.is_empty() else 1)
