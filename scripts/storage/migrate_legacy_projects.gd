extends SceneTree
## Explicit development-only copy; never moves or overwrites old projects.
const Manager=preload("res://scripts/project/project_manager.gd")
const Paths=preload("res://scripts/storage/portable_paths.gd")
func _initialize() -> void:
	if not OS.has_feature("editor") or not Paths.initialize().is_empty():quit(1);return
	var old:=Manager.new("user://projects")
	var target:=Manager.new()
	var failed:=false
	for entry in old.list_projects():
		if entry.has("error"):print(entry);failed=true;continue
		if DirAccess.dir_exists_absolute(target.folder(entry.id)):
			print("Bereits vorhanden, übersprungen: ",entry.id);continue
		var loaded:=old.load_project(entry.id)
		if loaded.has("error") or not loaded.get("warnings",[]).is_empty():
			print("Nicht vollständig lesbar: ",entry.id);failed=true;continue
		var result:=target.save_project(loaded.data,loaded.photo,loaded.texture)
		if result.has("error"):print(result.error);failed=true
		else:print("Importiert: ",entry.id)
	quit(1 if failed else 0)
