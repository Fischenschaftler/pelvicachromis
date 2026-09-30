extends Resource
## Physical parameters are converted once per trial using the active display calibration.
const Paths=preload("res://scripts/storage/portable_paths.gd")
var background_color:=Color(0.12,0.12,0.12)
var fish_display_length_cm:=8.0
var speed_cm_s:=4.0
var min_speed_cm_s:=1.0
var max_speed_cm_s:=10.0
var speed_adjustment_cm_s2:=2.5
var acceleration_cm_s2:=3.5
var deceleration_cm_s2:=5.0
var screen_width_cm:=0.0
var screen_height_cm:=0.0
var pixels_per_cm:=0.0
var calibration_timestamp: String
var calibration_version:=0
var calibration_override: RefCounted
var units_per_cm:=0.01 # Runtime result; never treated as physical calibration by itself.
var view_height:=0.24
var plane_depth:=0.0
var camera_distance:=1.0
var stimulus_speed:=0.04
var min_speed:=0.01
var max_speed:=0.10
var speed_adjustment:=0.025
var acceleration:=0.035
var deceleration:=0.05
var turn_speed:=PI
var turn_acceleration:=6.0
var idle_animation_speed:=0.18
var swim_animation_speed:=1.0
var fast_animation_speed:=1.9
var animation_response:=3.0
var log_hz:=20.0
var flush_interval:=0.5
var fullscreen:=true
var stop_on_focus_loss:=true
const FIELDS=["fish_display_length_cm","speed_cm_s","min_speed_cm_s","max_speed_cm_s","speed_adjustment_cm_s2","acceleration_cm_s2","deceleration_cm_s2","view_height","plane_depth","camera_distance","turn_speed","turn_acceleration","idle_animation_speed","swim_animation_speed","fast_animation_speed","animation_response","log_hz","flush_interval","fullscreen","stop_on_focus_loss"]
func snapshot() -> Dictionary:
	var result: Dictionary={"background_color":[background_color.r,background_color.g,background_color.b]}
	for key in FIELDS:result[key]=get(key)
	return result
func apply(values: Dictionary) -> String:
	values=values.duplicate(true)
	# Migrate old nominal 0.01-unit/cm settings in memory; never silently treat them as calibrated.
	var old_unit: float=float(values.get("units_per_cm",0.01))
	if old_unit<=0 or not is_finite(old_unit):return "Ungültige frühere Einheitenskala."
	var legacy: Dictionary={"fish_display_length":"fish_display_length_cm","stimulus_speed":"speed_cm_s","min_speed":"min_speed_cm_s","max_speed":"max_speed_cm_s","speed_adjustment":"speed_adjustment_cm_s2","acceleration":"acceleration_cm_s2","deceleration":"deceleration_cm_s2"}
	for key in legacy:
		if values.has(key):
			if not (values[key] is int or values[key] is float):return "Ungültiger früherer Parameter: "+key
			if not values.has(legacy[key]):values[legacy[key]]=float(values[key])/(1.0 if key=="fish_display_length" else old_unit)
			values.erase(key)
	values.erase("units_per_cm")
	for key in values:
		if key=="background_color":
			var c=values[key]
			if not c is Array or c.size()!=3:return "background_color benötigt drei Werte von 0 bis 1."
			for value in c:
				if not (value is float or value is int) or not is_finite(value) or value<0 or value>1:return "Ungültige Hintergrundfarbe."
			background_color=Color(c[0],c[1],c[2]);continue
		if not key in FIELDS:return "Unbekannter Stimulusparameter: "+str(key)
		if key in ["fullscreen","stop_on_focus_loss"]:
			if not values[key] is bool:return "Ungültiger Schalter: "+key
		else:
			if not (values[key] is float or values[key] is int) or not is_finite(values[key]):return "Ungültige Zahl: "+key
			if key!="plane_depth" and values[key]<=0:return "Wert muss positiv sein: "+key
		set(key,values[key])
	if min_speed_cm_s>speed_cm_s or speed_cm_s>max_speed_cm_s:return "Geschwindigkeiten müssen min <= stimulus <= max erfüllen."
	if idle_animation_speed>swim_animation_speed or swim_animation_speed>fast_animation_speed:return "Animationsgeschwindigkeiten müssen aufsteigend sein."
	if log_hz>240 or camera_distance<0.1 or view_height<0.001:return "Kamera oder Protokollrate außerhalb des gültigen Bereichs."
	return ""
func load_portable() -> String:
	var path:=Paths.config_dir().path_join("stimulus.json")
	if not FileAccess.file_exists(path):
		var file:=FileAccess.open(path,FileAccess.WRITE)
		if file==null:return "Stimuluskonfiguration kann nicht gespeichert werden."
		file.store_string(JSON.stringify(snapshot(),"\t"));file.flush()
		return "" if file.get_error()==OK else "Stimuluskonfiguration konnte nicht geschrieben werden."
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>65536:return "Stimuluskonfiguration nicht lesbar oder zu groß."
	var data=JSON.parse_string(file.get_as_text())
	if not data is Dictionary:return "stimulus.json enthält kein gültiges JSON-Objekt."
	return apply(data)

func apply_calibration(calibration: RefCounted,viewport_pixels: Vector2i,output_pixels: Vector2i) -> void:
	fish_display_length_cm=calibration.target_fish_length_cm
	screen_width_cm=calibration.physical_screen_width_cm;screen_height_cm=calibration.physical_screen_height_cm
	pixels_per_cm=calibration.pixels_per_cm_x;calibration_timestamp=calibration.calibration_timestamp
	calibration_version=calibration.VERSION
	units_per_cm=calibration.cm_to_world_units(1.0,viewport_pixels,output_pixels,view_height)
	stimulus_speed=speed_cm_s*units_per_cm
	min_speed=min_speed_cm_s*units_per_cm;max_speed=max_speed_cm_s*units_per_cm
	speed_adjustment=speed_adjustment_cm_s2*units_per_cm
	acceleration=acceleration_cm_s2*units_per_cm;deceleration=deceleration_cm_s2*units_per_cm

func runtime_snapshot() -> Dictionary:
	var result:=snapshot()
	result.merge({"screen_width_cm":screen_width_cm,"screen_height_cm":screen_height_cm,"pixels_per_cm":pixels_per_cm,"calibration_timestamp":calibration_timestamp,"calibration_version":calibration_version,"world_units_per_cm":units_per_cm})
	return result
