extends RefCounted
## Versioned immutable assets + metadata commit: failed saves cannot mix revisions.
const Data=preload("res://scripts/project/project_data.gd")
const Mask=preload("res://scripts/polygon_mask.gd")
var root: String
func _init(directory: String="user://projects") -> void:root=directory.trim_suffix("/")
func folder(id: String) -> String:return root+"/"+id
func read_manifest(id: String) -> Dictionary:
	if not Data.safe_id(id):return {"error":"Ungültige Projektkennung."}
	var path:=folder(id)+"/project.json"
	# Recover the last completed metadata commit if a rename was interrupted.
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path+".bak"):path+=".bak"
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {"error":"Projektdatei fehlt oder ist nicht lesbar."}
	if file.get_length()>4*1024*1024:return {"error":"Die Projektdatei ist unerwartet groß."}
	var json:=JSON.new()
	if json.parse(file.get_as_text())!=OK:return {"error":"Beschädigte Projektdatei: ungültiges JSON."}
	var error:=Data.validation_error(json.data)
	if not error.is_empty():return {"error":error}
	if json.data.id!=id:return {"error":"Projektkennung und Ordner stimmen nicht überein."}
	return {"data":json.data}
func list_projects() -> Array:
	var result: Array=[]
	var directory:=DirAccess.open(root)
	if directory==null:return result
	for id in directory.get_directories():
		if not Data.safe_id(id):continue
		var record:=read_manifest(id)
		if record.has("error"):result.append({"id":id,"name":"Beschädigtes Projekt "+id.left(8),"updated_at":"","photographed_side":"?","error":record.error})
		else:result.append(record.data)
	result.sort_custom(func(a,b):return a.updated_at>b.updated_at)
	return result
func load_project(id: String) -> Dictionary:
	var record:=read_manifest(id)
	if record.has("error"):return record
	var data: Dictionary=record.data
	var photo_path: String=folder(id)+"/"+data.photo_path
	var photo:=read_image(photo_path)
	if photo==null:return {"error":"Die interne Fotokopie fehlt oder ist beschädigt. Das Projekt wurde nicht geladen."}
	for key in ["landmark_points","mask_points"]:
		for pair in data[key]:
			if pair[0]<0 or pair[1]<0 or pair[0]>photo.get_width() or pair[1]>photo.get_height():return {"error":"Projektpunkte liegen außerhalb des Fotos."}
	if data.mask_closed:
		var error:=Mask.validation_error(Data.points_from_json(data.mask_points),photo.get_size())
		if not error.is_empty():return {"error":"Gespeicherte Maske ist ungültig: "+error}
	var warnings: Array[String]=[]
	var mask: Image=null
	if not data.mask_path.is_empty():
		mask=read_image(folder(id)+"/"+data.mask_path)
		if mask==null or mask.get_size()!=photo.get_size():warnings.append("Maskendatei fehlt oder ist beschädigt. Die gespeicherte Polygonkontur wurde wiederhergestellt.");mask=null
	var texture: Image=null
	if not data.generated_texture_path.is_empty():
		texture=read_image(folder(id)+"/"+data.generated_texture_path)
		if texture==null or texture.get_width()!=texture.get_height() or texture.get_width() not in [2048,4096]:warnings.append("Die generierte Textur fehlt oder ist beschädigt. Originalfärbung wurde aktiviert.");texture=null
	return {"data":data,"photo":photo,"photo_path":photo_path,"mask":mask,"texture":texture,"warnings":warnings}
static func read_image(path: String) -> Image:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>256*1024*1024:return null
	var bytes:=file.get_buffer(file.get_length())
	if bytes.size()<24 or bytes.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10]):return null
	var image:=Image.new()
	if image.load_png_from_buffer(bytes)!=OK or image.is_empty():return null
	return image
func save_project(state: Dictionary, photo: Image, texture: Image=null) -> Dictionary:
	if photo==null:return {"error":"Bitte zuerst ein Foto auswählen."}
	var name: String=state.get("name","").strip_edges()
	if name.is_empty() or name.length()>80:return {"error":"Bitte einen Projektnamen mit 1 bis 80 Zeichen eingeben."}
	var id: String=state.get("id","")
	if id.is_empty():id=Crypto.new().generate_random_bytes(16).hex_encode()
	if not Data.safe_id(id):return {"error":"Ungültige Projektkennung."}
	var previous:=read_manifest(id) if DirAccess.dir_exists_absolute(folder(id)) else {}
	if previous.has("error"):return {"error":"Das bestehende Projekt ist beschädigt. Bitte Speichern unter verwenden."}
	var now:=Time.get_datetime_string_from_system(true)+"Z"
	var stamp:=Crypto.new().generate_random_bytes(8).hex_encode()
	var data: Dictionary=state.duplicate(true)
	data.merge({"project_format_version":Data.VERSION,"id":id,"name":name,"created_at":previous.get("data",{}).get("created_at",now),"updated_at":now,"photo_path":"photo_"+stamp+".png","mask_path":"","generated_texture_path":""},true)
	if data.mask_closed:data.mask_path="mask_"+stamp+".png"
	if texture!=null:data.generated_texture_path="generated_albedo_"+stamp+".png"
	var error:=Data.validation_error(data)
	if not error.is_empty():return {"error":error}
	if data.mask_closed:
		error=Mask.validation_error(Data.points_from_json(data.mask_points),photo.get_size())
		if not error.is_empty():return {"error":"Maske vor dem Speichern korrigieren oder erneut öffnen: "+error}
	if DirAccess.make_dir_recursive_absolute(folder(id))!=OK:return {"error":"Projektordner konnte nicht angelegt werden."}
	if photo.save_png(folder(id)+"/"+data.photo_path)!=OK:return {"error":"Fotokopie konnte nicht gespeichert werden."}
	if texture!=null and texture.save_png(folder(id)+"/"+data.generated_texture_path)!=OK:return {"error":"Textur konnte nicht gespeichert werden."}
	if data.mask_closed:
		var mask: Image=Mask.build(photo,Data.points_from_json(data.mask_points),0).mask
		if mask.save_png(folder(id)+"/"+data.mask_path)!=OK:return {"error":"Maske konnte nicht gespeichert werden."}
	var path:=folder(id)+"/project.json"
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return {"error":"Projektdatei ist nicht schreibbar."}
	file.store_string(JSON.stringify(data,"\t"));file.flush();var failed:=file.get_error()!=OK;file.close()
	if failed:return {"error":"Projektdatei konnte nicht vollständig geschrieben werden."}
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path+".bak"):
		if DirAccess.rename_absolute(path+".bak",path)!=OK:return {"error":"Letzter gültiger Stand konnte nicht wiederhergestellt werden."}
	if FileAccess.file_exists(path+".bak") and DirAccess.remove_absolute(path+".bak")!=OK:return {"error":"Vorige Sicherung ist nicht schreibbar."}
	if FileAccess.file_exists(path) and DirAccess.rename_absolute(path,path+".bak")!=OK:return {"error":"Voriger Projektstand konnte nicht gesichert werden."}
	if DirAccess.rename_absolute(path+".tmp",path)!=OK:
		if FileAccess.file_exists(path+".bak"):DirAccess.rename_absolute(path+".bak",path)
		return {"error":"Neuer Projektstand konnte nicht aktiviert werden."}
	return {"data":data}
func delete_project(id: String) -> Dictionary:
	if not Data.safe_id(id) or not DirAccess.dir_exists_absolute(folder(id)):return {"error":"Projekt wurde nicht gefunden."}
	# Recoverable removal; never traverse paths supplied by the project JSON.
	if DirAccess.make_dir_recursive_absolute(root+"/.trash")!=OK:return {"error":"Papierkorb ist nicht beschreibbar."}
	var destination:=root+"/.trash/"+id+"_"+str(Time.get_ticks_usec())
	if DirAccess.rename_absolute(folder(id),destination)!=OK:return {"error":"Projekt konnte nicht gelöscht werden."}
	return {"trash_path":destination}
