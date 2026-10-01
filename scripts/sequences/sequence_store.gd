extends RefCounted
const Data=preload("res://scripts/sequences/sequence_data.gd")
const Paths=preload("res://scripts/storage/portable_paths.gd")
var directory: String
func _init(path: String="") -> void:directory=Paths.data_dir().path_join("sequences") if path.is_empty() else path
func ensure_examples() -> String:
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:return "Sequenzordner ist nicht beschreibbar."
	for name in ["stationary","horizontal_slow","horizontal_fast"]:
		var destination:=directory.path_join("example_"+name+".json")
		if not FileAccess.file_exists(destination):
			var source:=FileAccess.get_file_as_string("res://data/sequence_examples/"+name+".json")
			var file:=FileAccess.open(destination,FileAccess.WRITE)
			if file==null:return "Beispielsequenz kann nicht gespeichert werden."
			file.store_string(source);file.flush()
			if file.get_error()!=OK:return "Beispielsequenz konnte nicht geschrieben werden."
	return ""
func list_sequences() -> Array:
	var result: Array=[];var folder:=DirAccess.open(directory)
	if folder==null:return result
	for name in folder.get_files():
		if name.get_extension().to_lower()!="json":continue
		var record:=load_sequence(name.get_basename())
		result.append({"id":name.get_basename(),"name":record.get("data",{}).get("sequence_name",name+" (ungültig)")})
	result.sort_custom(func(a,b):return a.name<b.name)
	return result
func load_sequence(id: String) -> Dictionary:
	if not Data.safe_id(id):return {"error":"Ungültige Sequenzkennung."}
	var file:=FileAccess.open(directory.path_join(id+".json"),FileAccess.READ)
	if file==null or file.get_length()>1024*1024:return {"error":"Sequenzdatei fehlt oder ist zu groß."}
	var data=JSON.parse_string(file.get_as_text());var error:=Data.validate(data)
	if not error.is_empty():return {"error":error}
	if data.sequence_id!=id:return {"error":"Dateiname und Sequenzkennung stimmen nicht überein."}
	return {"data":data}
func save_sequence(data: Dictionary) -> String:
	var error:=Data.validate(data)
	if not error.is_empty():return error
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:return "Sequenzordner nicht beschreibbar."
	var path:=directory.path_join(data.sequence_id+".json")
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return "Sequenz kann nicht gespeichert werden."
	file.store_string(JSON.stringify(data,"\t"));file.flush();var failed:=file.get_error()!=OK;file.close()
	if failed or DirAccess.rename_absolute(path+".tmp",path)!=OK:return "Sequenz konnte nicht sicher gespeichert werden."
	return ""
func duplicate_sequence(data: Dictionary) -> Dictionary:
	var result:=data.duplicate(true);var fresh:=Data.fresh()
	result.sequence_id=fresh.sequence_id;result.created_at=fresh.created_at;result.updated_at=fresh.updated_at
	result.sequence_name=(data.sequence_name+" – Kopie").left(100)
	return result
