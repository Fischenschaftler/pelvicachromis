extends RefCounted
const Paths=preload("res://scripts/storage/portable_paths.gd")
var experimenter_screen:=0
var stimulus_screen:=0
var development:=true
var neutral_mode:="BACKGROUND"
var saved_context: Dictionary={}
var path: String
func _init(custom_path: String="") -> void:
	path=Paths.config_dir().path_join("display_setup.json") if custom_path.is_empty() else custom_path
static func screens() -> Array:
	var result: Array=[]
	for index in range(DisplayServer.get_screen_count()):result.append(context(index))
	return result
static func context(index: int) -> Dictionary:
	if index<0 or index>=DisplayServer.get_screen_count():return {}
	var pixels:=DisplayServer.screen_get_size(index);var origin:=DisplayServer.screen_get_position(index)
	return {"monitor_index":index,"screen_count":DisplayServer.get_screen_count(),"screen_size":[pixels.x,pixels.y],"screen_position":[origin.x,origin.y],"screen_scale":DisplayServer.screen_get_scale(index)}
func load_setup() -> String:
	experimenter_screen=DisplayServer.get_primary_screen();stimulus_screen=1 if DisplayServer.get_screen_count()>1 and experimenter_screen==0 else 0;development=DisplayServer.get_screen_count()<2
	if not FileAccess.file_exists(path):return ""
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>16384:return "Monitorwahl nicht lesbar. Bitte neu auswählen."
	var data=JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("version")!=1:return "Ungültige Monitorwahl."
	for key in ["experimenter_screen","stimulus_screen"]:
		if not (data.get(key) is int or data.get(key) is float) or data[key]!=int(data[key]) or data[key]<0:return "Ungültiger Monitorindex."
	if not data.get("development") is bool or data.get("neutral_mode") not in ["BACKGROUND","CENTER_FISH"] or not data.get("stimulus_context") is Dictionary:return "Ungültige Anzeigeeinstellungen."
	var restored:=normalize_context(data.stimulus_context)
	if restored.is_empty():return "Ungültige gespeicherte Monitoridentifikation."
	experimenter_screen=int(data.experimenter_screen);stimulus_screen=int(data.stimulus_screen);development=data.development;neutral_mode=data.neutral_mode;saved_context=restored
	return ""
static func normalize_context(data: Dictionary) -> Dictionary:
	for key in ["monitor_index","screen_count","screen_scale"]:
		if not (data.get(key) is int or data.get(key) is float) or not is_finite(float(data[key])):return {}
	for key in ["screen_size","screen_position"]:
		if not data.get(key) is Array or data[key].size()!=2:return {}
		for number in data[key]:
			if not (number is int or number is float) or not is_finite(float(number)) or number!=int(number):return {}
	if data.screen_scale<=0 or data.screen_count<1 or data.monitor_index<0 or data.monitor_index>=data.screen_count or data.screen_size[0]<=0 or data.screen_size[1]<=0:return {}
	return {"monitor_index":int(data.monitor_index),"screen_count":int(data.screen_count),"screen_scale":float(data.screen_scale),"screen_size":[int(data.screen_size[0]),int(data.screen_size[1])],"screen_position":[int(data.screen_position[0]),int(data.screen_position[1])]}
func save_setup() -> String:
	if context(experimenter_screen).is_empty() or context(stimulus_screen).is_empty():return "Ausgewählter Monitor fehlt."
	saved_context=context(stimulus_screen)
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return "Monitorwahl kann nicht gespeichert werden."
	file.store_string(JSON.stringify({"version":1,"experimenter_screen":experimenter_screen,"stimulus_screen":stimulus_screen,"development":development,"neutral_mode":neutral_mode,"stimulus_context":saved_context},"\t"));file.flush();var error:=file.get_error();file.close()
	return "" if error==OK and DirAccess.rename_absolute(path+".tmp",path)==OK else "Monitorwahl konnte nicht gespeichert werden."
func validate_selection(preview: bool) -> String:
	if context(experimenter_screen).is_empty() or context(stimulus_screen).is_empty():return "Ausgewählter Monitor nicht vorhanden. Monitorwahl erneut prüfen."
	if saved_context.is_empty():return "Bitte Experimentator- und Stimulusmonitor ausdrücklich auswählen und Monitorwahl speichern."
	if not saved_context.is_empty() and saved_context!=context(stimulus_screen):return "Monitoranordnung hat sich geändert. Monitorwahl erneut bestätigen und Kalibrierung prüfen."
	if not preview and (development or experimenter_screen==stimulus_screen):return "Echter Versuch benötigt zwei getrennte Monitore. Einmonitor-Modus ist nur eine Entwicklungsvorschau."
	return ""
