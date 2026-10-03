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
# Runtime pose/steering parameters; radians, seconds and physical centimetres.
var turn_bend_strength:=0.6
var turn_bend_response:=6.0
var turn_bend_recovery:=4.0
var max_turn_bend:=0.95
var minimum_turn_radius_cm:=1.5
var turn_radius_speed_factor:=0.05
var turn_bend_speed_gain:=0.25
var pectoral_turn_strength:=0.07
var body_bend_weights: Dictionary={"Body_01":0.02,"Body_02":0.06,"Body_03":0.12,"Body_04":0.19,"Tail_01":0.24,"Tail_02":0.27,"Tail_Fin":0.10}
var max_pitch_up_deg:=25.0
var max_pitch_down_deg:=25.0
var pitch_speed_deg_s:=30.0
var pitch_acceleration:=60.0
var pitch_deceleration:=90.0
var pitch_return_speed:=18.0
var pitch_return_to_neutral:=true
var boost_multiplier:=2.5
var max_stimulus_speed_cm_s:=20.0
var operculum_frequency_hz:=1.0
var operculum_amplitude:=0.00035
var operculum_phase:=0.0
var operculum_speed_coupling:=0.15
var operculum_response:=2.0
var yaw_speed_deg_s:=45.0
var yaw_acceleration:=90.0
var yaw_deceleration:=120.0
var operculum_open_ratio:=0.42
var operculum_close_ratio:=0.4
var pectoral_frequency_hz:=1.2
var pectoral_hover_amplitude:=0.14
var pectoral_cruise_amplitude:=0.045
var pectoral_brake_amplitude:=0.28
var pectoral_turn_amplitude:=0.14
var pectoral_pitch_amplitude:=0.025
var passive_fin_amplitude:=0.035
var fin_response:=5.0
var idle_animation_speed:=0.18
var swim_animation_speed:=1.0
var fast_animation_speed:=1.9
var animation_response:=3.0
var log_hz:=20.0
var flush_interval:=0.5
var fullscreen:=true
var stop_on_focus_loss:=true
const FIELDS=["yaw_speed_deg_s","yaw_acceleration","yaw_deceleration","operculum_open_ratio","operculum_close_ratio","pectoral_frequency_hz","pectoral_hover_amplitude","pectoral_cruise_amplitude","pectoral_brake_amplitude","pectoral_turn_amplitude","pectoral_pitch_amplitude","passive_fin_amplitude","fin_response","max_pitch_up_deg","max_pitch_down_deg","pitch_speed_deg_s","pitch_acceleration","pitch_deceleration","pitch_return_speed","pitch_return_to_neutral","boost_multiplier","max_stimulus_speed_cm_s","operculum_frequency_hz","operculum_amplitude","operculum_phase","operculum_speed_coupling","operculum_response","turn_bend_strength","turn_bend_response","turn_bend_recovery","max_turn_bend","minimum_turn_radius_cm","turn_radius_speed_factor","turn_bend_speed_gain","pectoral_turn_strength","body_bend_weights","fish_display_length_cm","speed_cm_s","min_speed_cm_s","max_speed_cm_s","speed_adjustment_cm_s2","acceleration_cm_s2","deceleration_cm_s2","view_height","plane_depth","camera_distance","turn_speed","turn_acceleration","idle_animation_speed","swim_animation_speed","fast_animation_speed","animation_response","log_hz","flush_interval","fullscreen","stop_on_focus_loss"]
func snapshot() -> Dictionary:
	var result: Dictionary={"background_color":[background_color.r,background_color.g,background_color.b]}
	for key in FIELDS:result[key]=get(key).duplicate(true) if get(key) is Dictionary else get(key)
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
		if key=="body_bend_weights":
			if not values[key] is Dictionary or values[key].size()!=body_bend_weights.size():return "Gewichte für alle sieben Körper-Bones erforderlich."
			var sum:=0.0
			for bone in body_bend_weights:
				var weight=values[key].get(bone)
				if not (weight is float or weight is int) or not is_finite(weight) or weight<0:return "Ungültiges Bone-Gewicht: "+bone
				sum+=weight
			if sum<=0:return "Mindestens ein Körpergewicht muss positiv sein."
			body_bend_weights=values[key].duplicate(true);continue
		if key=="background_color":
			var c=values[key]
			if not c is Array or c.size()!=3:return "background_color benötigt drei Werte von 0 bis 1."
			for value in c:
				if not (value is float or value is int) or not is_finite(value) or value<0 or value>1:return "Ungültige Hintergrundfarbe."
			background_color=Color(c[0],c[1],c[2]);continue
		if not key in FIELDS:return "Unbekannter Stimulusparameter: "+str(key)
		if key in ["fullscreen","stop_on_focus_loss","pitch_return_to_neutral"]:
			if not values[key] is bool:return "Ungültiger Schalter: "+key
		else:
			if not (values[key] is float or values[key] is int) or not is_finite(values[key]):return "Ungültige Zahl: "+key
			if key in ["turn_bend_strength","turn_bend_speed_gain","pectoral_turn_strength","operculum_amplitude","operculum_phase","operculum_speed_coupling","pectoral_hover_amplitude","pectoral_cruise_amplitude","pectoral_brake_amplitude","pectoral_turn_amplitude","pectoral_pitch_amplitude","passive_fin_amplitude"]:
				if values[key]<0:return "Wert darf nicht negativ sein: "+key
			elif key!="plane_depth" and values[key]<=0:return "Wert muss positiv sein: "+key
		set(key,values[key])
	if operculum_open_ratio+operculum_close_ratio>.95 or yaw_speed_deg_s>180 or yaw_acceleration>720 or yaw_deceleration>720:return "Orientierung oder Atemphasen außerhalb der Grenzen."
	if pectoral_hover_amplitude+pectoral_brake_amplitude+pectoral_turn_amplitude+pectoral_pitch_amplitude>.8 or pectoral_cruise_amplitude>pectoral_hover_amplitude or passive_fin_amplitude>.1:return "Flossenamplituden außerhalb der Grenzen."
	if max_pitch_up_deg>45 or max_pitch_down_deg>45 or operculum_amplitude>.0007 or operculum_frequency_hz>5 or operculum_speed_coupling>1 or boost_multiplier<1 or max_stimulus_speed_cm_s<max_speed_cm_s:return "Pitch, Atmung oder Boost außerhalb des sicheren Bereichs."
	if max_turn_bend>1.2 or pectoral_turn_strength>0.2 or turn_bend_speed_gain>1.0:return "Kurvenpose überschreitet die zulässigen Grenzen."
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
