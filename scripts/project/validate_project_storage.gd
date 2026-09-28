extends "res://scripts/validate_fish_viewer.gd"
const Manager=preload("res://scripts/project/project_manager.gd")
const Data=preload("res://scripts/project/project_data.gd")
var controller: Control
func _initialize() -> void:call_deferred("run_storage")
func run_storage() -> void:
	viewer=load("res://scenes/PhotoImport.tscn").instantiate();root.add_child(viewer);root.size=Vector2i(1400,1000)
	await create_timer(.4).timeout
	controller=viewer.get_node("UI/ReferencePhoto")
	var manager=Manager.new("user://project_storage_tests/"+Crypto.new().generate_random_bytes(8).hex_encode())
	controller.project_manager=manager;controller.project_browser.manager=manager
	check(controller.load_photo(ProjectSettings.globalize_path("res://blender/reference/pelvicachromis_taeniatus_male.jpg")),"Photo load failed")
	var photo_hash:=hash(controller.source.get_data())
	controller.canvas.landmarks=PackedVector2Array([Vector2(700,300),Vector2(660,280)])
	controller.canvas.points=PackedVector2Array([Vector2(60,250),Vector2(730,250)])
	check(controller.save_project("Erster Entwurf"),"Draft save failed: "+controller.last_error)
	var id: String=controller.project_id
	var draft: Dictionary=manager.read_manifest(id).data
	check(FileAccess.file_exists(manager.folder(id)+"/"+draft.photo_path),"Internal photo not saved")
	controller.reset();check(controller.open_project(id),"Draft load failed")
	check(controller.canvas.landmarks.size()==2 and controller.canvas.points.size()==2 and not controller.canvas.closed,"Draft points not restored")
	check(hash(controller.source.get_data())==photo_hash,"Internal photo pixels changed")
	var model: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/photo_import_projection.json"))
	controller.canvas.landmarks.clear()
	for p in model.anchors:controller.canvas.landmarks.append(Vector2(p[0],p[1])*670+Vector2(400,400))
	controller.canvas.points=PackedVector2Array([Vector2(20,200),Vector2(780,200),Vector2(780,650),Vector2(20,650)])
	controller.canvas.closed=true;controller.canvas.mode="mask";controller.side.select(1);controller.resolution.select(1)
	var texture:=Image.new();texture.load_png_from_buffer(FileAccess.get_file_as_bytes("res://textures/pelvicachromis_taeniatus_male_albedo.png"));texture.resize(2048,2048)
	var texture_hash:=hash(texture.get_data());texture.generate_mipmaps();controller.generated=ImageTexture.create_from_image(texture);controller.show_generated()
	# Saving must not need the user's original file after it was loaded.
	controller.source_path="D:/moved-or-missing/fish.jpg"
	check(controller.save_project("Fertiger Fisch"),"Overwrite failed: "+controller.last_error)
	var completed: Dictionary=manager.read_manifest(id).data
	check(completed.created_at==draft.created_at and completed.name=="Fertiger Fisch","Overwrite metadata wrong")
	check(not completed.transform_data.is_empty(),"Alignment not stored")
	controller.reset();check(controller.open_project(id),"Complete load failed")
	check(controller.showing_generated and controller.generated!=null,"Generated material not restored")
	check(controller.canvas.landmarks.size()==12 and controller.canvas.closed and controller.canvas.points.size()==4,"Mask/landmarks not restored")
	var restored: Dictionary=manager.load_project(id)
	var expected_mask: Image=controller.Mask.build(controller.source,controller.canvas.points,0).mask
	var stored_mask: Image=restored.mask;stored_mask.convert(Image.FORMAT_L8)
	check(stored_mask.get_data()==expected_mask.get_data(),"Mask pixels not restored")
	check(controller.canvas.landmarks[0].distance_to(Vector2(model.anchors[0][0],model.anchors[0][1])*670+Vector2(400,400))<.001,"Landmark coordinates changed")
	check(controller.side.selected==1 and controller.resolution.selected==1,"Side/resolution not restored")
	var loaded: Image=controller.generated.get_image();loaded.clear_mipmaps();check(hash(loaded.get_data())==texture_hash,"Texture pixels changed")
	controller.show_original();check(controller.save_project("Fertiger Fisch"),"Original-mode save failed")
	controller.reset();controller.open_project(id);check(not controller.showing_generated and controller.generated!=null,"Original-mode restoration failed")
	controller.show_generated();check(controller.showing_generated,"Generated toggle after load failed")
	await create_timer(2.2).timeout
	check(viewer.animation_player.is_playing() and viewer.animation_player.current_animation_position<2,"Swim_Test after load failed")
	for skeleton in viewer.fish.find_children("*","Skeleton3D",true,false):check(skeleton.get_bone_count()==15,"Skeleton changed")
	await click(viewer.animation_button);check(not viewer.animation_player.is_playing(),"Animation stop failed");await click(viewer.animation_button)
	var center: Vector2=viewer.get_node("ViewerViewport").get_global_rect().get_center()
	mouse(MOUSE_BUTTON_LEFT,true,center);move(center+Vector2(60,25),Vector2(60,25));mouse(MOUSE_BUTTON_LEFT,false,center+Vector2(60,25));check(absf(viewer.orbit.yaw)>.05,"Orbit after load failed")
	var distance: float=viewer.orbit.distance;mouse(MOUSE_BUTTON_WHEEL_UP,true,center);check(viewer.orbit.distance<distance,"Zoom after load failed");await click(viewer.reset_button)
	completed=manager.read_manifest(id).data
	var mask_path: String=manager.folder(id)+"/"+completed.mask_path
	DirAccess.rename_absolute(mask_path,mask_path+".missing")
	var missing: Dictionary=manager.load_project(id);check(not missing.has("error") and missing.warnings.size()==1,"Missing mask not reported/recovered")
	DirAccess.rename_absolute(mask_path+".missing",mask_path)
	var texture_path: String=manager.folder(id)+"/"+completed.generated_texture_path
	DirAccess.rename_absolute(texture_path,texture_path+".missing")
	check(controller.open_project(id) and controller.generated==null and not controller.showing_generated and controller.status.text.contains("Textur fehlt"),"Missing texture not handled")
	DirAccess.rename_absolute(texture_path+".missing",texture_path)
	var photo_path: String=manager.folder(id)+"/"+completed.photo_path
	DirAccess.rename_absolute(photo_path,photo_path+".missing")
	var preserved_name: String=controller.project_name
	check(not controller.open_project(id) and controller.project_name==preserved_name,"Missing photo replaced editor state")
	DirAccess.rename_absolute(photo_path+".missing",photo_path)
	var manifest: String=manager.folder(id)+"/project.json"
	var good:=FileAccess.get_file_as_string(manifest)
	DirAccess.rename_absolute(manifest,manifest+".interrupted")
	check(not manager.load_project(id).has("error"),"Interrupted metadata commit not recovered")
	DirAccess.rename_absolute(manifest+".interrupted",manifest)
	FileAccess.open(manifest,FileAccess.WRITE).store_string("{broken")
	check(manager.load_project(id).has("error"),"Broken JSON accepted")
	var invalid: Dictionary=JSON.parse_string(good);invalid.project_format_version=999
	FileAccess.open(manifest,FileAccess.WRITE).store_string(JSON.stringify(invalid));check(manager.load_project(id).has("error"),"Incompatible version accepted")
	invalid=JSON.parse_string(good);invalid.photo_path="../../external.png"
	FileAccess.open(manifest,FileAccess.WRITE).store_string(JSON.stringify(invalid));check(manager.load_project(id).has("error"),"Unsafe path accepted")
	invalid=JSON.parse_string(good);invalid.landmark_points=[["bad",0]]
	FileAccess.open(manifest,FileAccess.WRITE).store_string(JSON.stringify(invalid));check(manager.load_project(id).has("error"),"Invalid points accepted")
	FileAccess.open(manifest,FileAccess.WRITE).store_string(good)
	controller.open_project(id);controller.show_generated()
	check(controller.save_project("Zweiter Fisch",true),"Save as failed")
	var copy_id: String=controller.project_id;check(copy_id!=id and manager.list_projects().size()==2,"Save as overwrote original")
	controller.project_browser.show_projects();await create_timer(.3).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://godot/diagnostics/project_browser.png")
	controller.project_browser.browser.hide()
	# Browser deletion must require the confirmation dialog.
	controller.project_browser.refresh();controller.project_browser.confirm_delete()
	check(controller.project_browser.delete_dialog.visible and manager.list_projects().size()==2,"Delete did not await confirmation")
	controller.project_browser.delete_dialog.hide();controller.project_browser.delete_confirmed()
	check(manager.list_projects().size()==1,"Confirmed delete failed")
	var remaining: String=manager.list_projects()[0].id
	check(controller.open_project(remaining),"Remaining project missing")
	controller.reset();check(controller.project_id.is_empty() and controller.generated==null and manager.list_projects().size()==1,"Reset deleted saved project")
	check(controller.open_project(remaining),"Reopen after reset failed")
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://godot/diagnostics/project_loaded.png")
	for dimensions in [Vector2i(600,900),Vector2i(480,360)]:
		root.size=dimensions;await create_timer(.2).timeout;check(root.get_visible_rect().encloses(controller.panel.get_global_rect()),"Project UI exceeds window")
	FileAccess.open("res://godot/diagnostics/project_storage_validation.json",FileAccess.WRITE).store_string(JSON.stringify({"errors":errors,"test_root":manager.root,"draft_roundtrip":true,"generated_roundtrip":true,"mask_roundtrip":true,"swim_test":true,"original_photo_dependency":false},"\t"))
	print("PROJECT STORAGE TESTS: ",errors);quit(0 if errors.is_empty() else 1)
