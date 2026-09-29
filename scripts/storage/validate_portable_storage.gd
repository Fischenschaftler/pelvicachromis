extends "res://scripts/photo_import/validate_auto_photo_analysis.gd"
const Paths=preload("res://scripts/storage/portable_paths.gd")
const Manager=preload("res://scripts/project/project_manager.gd")
func copy_tree(source: String,destination: String) -> void:
	check(DirAccess.make_dir_recursive_absolute(destination)==OK,"Copy directory")
	var directory:=DirAccess.open(source)
	for file in directory.get_files():check(DirAccess.copy_absolute(source.path_join(file),destination.path_join(file))==OK,"Copy file "+file)
	for child in directory.get_directories():
		if not directory.is_link(child):copy_tree(source.path_join(child),destination.path_join(child))
func finish() -> void:
	check(Paths.resolve_application_dir(true,"C:/Godot/godot.exe","D:/work")=="D:/work/dev_portable_data","Editor path")
	check(Paths.resolve_application_dir(false,"E:/USB/Fisch/PelvicachromisStudio.exe","res://")=="E:/USB/Fisch","EXE path")
	var blocked:=Paths.data_dir().path_join("not_a_directory")
	FileAccess.open(blocked,FileAccess.WRITE).store_string("test")
	check(not Paths.initialize(blocked).is_empty(),"Unwritable storage accepted")
	var destination:=ProjectSettings.globalize_path("res://.godot/portable_relocation/"+str(Time.get_ticks_usec()))
	copy_tree(Paths.application_dir(),destination)
	var relative: String=importer.project_manager.root.trim_prefix(Paths.application_dir()+"/")
	var relocated:=Manager.new(destination.path_join(relative))
	var id: String=importer.project_id
	var before: Dictionary=importer.project_manager.load_project(id)
	var after:=relocated.load_project(id)
	check(not after.has("error"),"Relocated project load")
	if not after.has("error"):
		for key in ["photo","mask","texture"]:
			check(before[key]!=null and after[key]!=null and before[key].get_data()==after[key].get_data(),"Relocated "+key)
		check(before.data.landmark_points==after.data.landmark_points,"Relocated landmarks")
		var json:=FileAccess.get_file_as_string(relocated.folder(id)+"/project.json")
		check(not json.contains(":/") and not json.contains(":\\"),"Absolute path in manifest")
		var count: int=importer.analysis_count
		importer.project_manager=relocated;importer.project_browser.manager=relocated
		check(importer.open_project(id) and importer.generated!=null,"Relocated viewer")
		check(importer.analysis_count==count,"Relocated project reanalysed")
		importer.show_original();check(not importer.showing_generated,"Relocated original")
		importer.show_generated();check(importer.showing_generated,"Relocated generated")
		await create_timer(2.1).timeout
		check(viewer.animation_player.is_playing(),"Relocated Swim_Test")
		var center: Vector2=viewer.get_node("ViewerViewport").get_global_rect().get_center()
		mouse(MOUSE_BUTTON_LEFT,true,center);move(center+Vector2(50,20),Vector2(50,20));mouse(MOUSE_BUTTON_LEFT,false,center+Vector2(50,20))
		check(absf(viewer.orbit.yaw)>.05,"Relocated orbit")
		var distance: float=viewer.orbit.distance;mouse(MOUSE_BUTTON_WHEEL_UP,true,center);check(viewer.orbit.distance<distance,"Relocated zoom")
		await click(viewer.reset_button)
		check(importer.save_project("Portable Kopie"),"Relocated save")
		check(not relocated.delete_project(id).has("error"),"Relocated delete")
	reports["relocated_to"]=destination;reports.errors=errors
	FileAccess.open("res://godot/diagnostics/portable_storage_validation.json",FileAccess.WRITE).store_string(JSON.stringify(reports,"\t"))
	print("PORTABLE STORAGE: ",errors);quit(0 if errors.is_empty() else 1)
