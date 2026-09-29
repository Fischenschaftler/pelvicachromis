extends RefCounted
## All writable product data stays beside the exported executable.
const WRITE_ERROR = "Pelvicachromis Studio benötigt Schreibzugriff auf seinen Programmordner. Bitte verschiebe den Ordner an einen beschreibbaren Speicherort, z. B. Dokumente, Desktop oder einen beschreibbaren USB-Stick."
static func application_dir() -> String:
	return resolve_application_dir(OS.has_feature("editor"), OS.get_executable_path(), ProjectSettings.globalize_path("res://"))
static func resolve_application_dir(editor: bool, executable: String, project: String) -> String:
	return project.path_join("dev_portable_data").simplify_path() if editor else executable.get_base_dir()
static func projects_dir() -> String:return application_dir().path_join("projects")
static func data_dir() -> String:return application_dir().path_join("data")
static func config_dir() -> String:return application_dir().path_join("config")
static func logs_dir() -> String:return application_dir().path_join("logs")
static func initialize(base: String = "") -> String:
	if base.is_empty():base=application_dir()
	if FileAccess.file_exists(base):return WRITE_ERROR
	for name in ["projects", "data", "config", "logs"]:
		var directory:=base.path_join(name)
		if DirAccess.make_dir_recursive_absolute(directory)!=OK:return WRITE_ERROR
		var probe:=directory.path_join(".write_probe_"+Crypto.new().generate_random_bytes(8).hex_encode())
		var file:=FileAccess.open(probe,FileAccess.WRITE)
		if file==null:return WRITE_ERROR
		file.store_string("portable");file.flush()
		var failed:=file.get_error()!=OK
		file.close()
		if failed or DirAccess.remove_absolute(probe)!=OK:return WRITE_ERROR
	if OS.has_feature("editor"):
		var ignore:=FileAccess.open(base.path_join(".gdignore"),FileAccess.WRITE)
		if ignore!=null:ignore.close()
	return ""
static func log_message(message: String) -> void:
	var path:=logs_dir().path_join("studio.log")
	var existing:=FileAccess.open(path,FileAccess.READ) if FileAccess.file_exists(path) else null
	var rotate:=existing!=null and existing.get_length()>1024*1024
	if existing!=null:existing.close()
	if rotate:
		DirAccess.remove_absolute(path+".1")
		DirAccess.rename_absolute(path,path+".1")
	var file:=FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file!=null:
		file.seek_end();file.store_line(Time.get_datetime_string_from_system()+" "+message)
