extends RefCounted
const VERSION:=1
static func points_to_json(points: PackedVector2Array) -> Array:
	var result: Array=[]
	for p in points:result.append([p.x,p.y])
	return result
static func points_from_json(points: Array) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for p in points:result.append(Vector2(p[0],p[1]))
	return result
static func plain(value: Variant) -> Variant:
	if value is Vector2:return [value.x,value.y]
	if value is Dictionary:
		var result: Dictionary={}
		for key in value:result[key]=plain(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value:result.append(plain(item))
		return result
	return value
# Legacy absolute source paths are provenance only, never asset dependencies.
static func portable_metadata(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary={}
		for key in value:
			if key in ["original_photo_path","photo_path","texture_path","metadata_path"]:continue
			result[key]=portable_metadata(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value:result.append(portable_metadata(item))
		return result
	return value
static func safe_id(value: Variant) -> bool:
	if not value is String or value.length()!=32:return false
	for c in value:
		if c not in "0123456789abcdef":return false
	return true
static func asset_name(value: Variant) -> bool:
	return value is String and (value.is_empty() or (value==value.get_file() and value.ends_with(".png") and not value.contains(":") and not value.contains("\\") and not value.contains("/")))
static func validation_error(data: Variant) -> String:
	if not data is Dictionary:return "Die Projektdatei enthält kein gültiges JSON-Objekt."
	if data.get("project_format_version")!=VERSION:return "Diese Projektversion wird nicht unterstützt (erwartet: Version 1)."
	if not safe_id(data.get("id")):return "Die Projektkennung ist ungültig."
	if not data.get("name") is String or data.name.strip_edges().is_empty() or data.name.length()>80:return "Der Projektname ist ungültig."
	for key in ["created_at","updated_at"]:
		if not data.get(key) is String:return "Zeitangaben fehlen im Projekt."
	if data.get("photographed_side") not in ["left","right"] or not (data.get("resolution")==2048 or data.get("resolution")==4096):return "Fischseite oder Ausgabeauflösung ist ungültig."
	for key in ["photo_path","mask_path","generated_texture_path"]:
		if not asset_name(data.get(key)):return "Ungültiger interner Dateipfad: "+key
	if data.photo_path.is_empty():return "Das Projekt enthält keinen Fotopfad."
	for key in ["landmark_points","mask_points"]:
		if not data.get(key) is Array or data[key].size()>(12 if key=="landmark_points" else 512):return "Ungültige Punktliste: "+key
		for point in data[key]:
			if not point is Array or point.size()!=2:return "Ungültige Punktkoordinaten."
			for value in point:
				if not (value is float or value is int) or not is_finite(float(value)):return "Ungültige Punktkoordinaten."
	if not data.get("mask_closed") is bool or not data.get("transform_data") is Dictionary or not data.get("ui_state") is Dictionary:return "Projektzustand ist unvollständig."
	if data.ui_state.get("mode") not in ["landmarks","mask"] or not data.ui_state.get("showing_generated") is bool:return "Ungültiger Oberflächenzustand."
	if data.has("generation_data") and not data.generation_data is Dictionary:return "Ungültige Erzeugungsdaten."
	return ""
