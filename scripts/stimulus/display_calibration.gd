extends RefCounted
## Display pixel coordinates, never monitor-reported DPI, determine physical scaling.
const Paths=preload("res://scripts/storage/portable_paths.gd")
const VERSION=1
var screen_pixel_width:=0
var screen_pixel_height:=0
var physical_screen_width_cm:=0.0
var physical_screen_height_cm:=0.0
var pixels_per_cm_x:=0.0
var pixels_per_cm_y:=0.0
var target_fish_length_cm:=8.0
var correction_factor:=1.0
var calibration_timestamp: String
var monitor: Dictionary={}
var active_profile: String="Display_01"
var profiles: Dictionary={}
static var model_measurements: Dictionary={}
static func portable_path() -> String:return Paths.config_dir().path_join("display_calibration.json")
static func display_context(window: Window) -> Dictionary:
	var screen:=window.current_screen
	var size:=DisplayServer.screen_get_size(screen)
	var position:=DisplayServer.screen_get_position(screen)
	return {"monitor_index":screen,"screen_count":DisplayServer.get_screen_count(),"screen_size":[size.x,size.y],"screen_position":[position.x,position.y],"screen_scale":DisplayServer.screen_get_scale(screen)}
func configure(width_cm: float,context: Dictionary,target_cm: float=8.0) -> String:
	if not is_finite(width_cm) or width_cm<=0 or not is_finite(target_cm) or target_cm<=0:return "Bildschirmbreite und Fischlänge müssen größer als null sein."
	for key in ["screen_size","screen_position"]:
		if not context.get(key) is Array or context[key].size()!=2:return "Ungültige Monitorangaben."
		for value in context[key]:
			if not (value is float or value is int) or not is_finite(value) or value!=round(value):return "Ungültige Monitorpixel."
	for key in ["monitor_index","screen_count","screen_scale"]:
		if not (context.get(key) is float or context.get(key) is int) or not is_finite(context[key]):return "Ungültige Monitoridentifikation."
	if context.screen_size[0]<=0 or context.screen_size[1]<=0 or context.screen_scale<=0 or context.monitor_index<0 or context.monitor_index>=context.screen_count:return "Bildschirmauflösung konnte nicht bestimmt werden."
	physical_screen_width_cm=width_cm;target_fish_length_cm=target_cm
	monitor={"monitor_index":int(context.monitor_index),"screen_count":int(context.screen_count),"screen_size":[int(context.screen_size[0]),int(context.screen_size[1])],"screen_position":[int(context.screen_position[0]),int(context.screen_position[1])],"screen_scale":float(context.screen_scale)}
	screen_pixel_width=int(context.screen_size[0]);screen_pixel_height=int(context.screen_size[1])
	correction_factor=1.0;recalculate()
	return ""
func recalculate() -> void:
	# Height is derived assuming square physical pixels. No independent Y calibration yet.
	physical_screen_height_cm=physical_screen_width_cm*screen_pixel_height/maxf(1,screen_pixel_width)
	pixels_per_cm_x=screen_pixel_width/physical_screen_width_cm*correction_factor if physical_screen_width_cm>0 else 0
	pixels_per_cm_y=pixels_per_cm_x
func correct_measurement(reference_cm: float,measured_cm: float) -> String:
	if not valid() or not is_finite(reference_cm) or not is_finite(measured_cm) or reference_cm<=0 or measured_cm<=0:return "Bitte eine gültige Soll- und Messlänge eingeben."
	var factor:=correction_factor*reference_cm/measured_cm
	if factor<0.1 or factor>10:return "Messkorrektur zu groß. Bitte Bildschirmbreite und Messung prüfen."
	correction_factor=factor;recalculate();return ""
func valid() -> bool:
	return screen_pixel_width>0 and screen_pixel_height>0 and physical_screen_width_cm>0 and is_finite(physical_screen_width_cm) and target_fish_length_cm>0 and is_finite(target_fish_length_cm) and correction_factor>=0.1 and correction_factor<=10 and is_finite(correction_factor)
func mismatch(context: Dictionary) -> String:
	if not valid():return "Keine gültige Bildschirmkalibrierung. Bitte zuerst mit F10 kalibrieren."
	for key in ["monitor_index","screen_count","screen_size","screen_position","screen_scale"]:
		if not monitor.has(key) or monitor[key]!=context.get(key):return "Monitor oder Bildschirmauflösung stimmt nicht mit der gespeicherten Kalibrierung überein. Bitte mit F10 prüfen und neu speichern."
	return ""
func reference_pixels(length_cm: float=10.0) -> float:return length_cm*pixels_per_cm_x
static func pixels_per_world_unit(viewport_pixels: Vector2i,output_pixels: Vector2i,camera_size: float,axis: int=0) -> float:
	if camera_size<=0 or viewport_pixels.x<=0 or viewport_pixels.y<=0 or output_pixels.x<=0 or output_pixels.y<=0:return 0.0
	var render_pixels_per_unit:=viewport_pixels.y/camera_size
	var output_scale:=float(output_pixels.x)/viewport_pixels.x if axis==0 else float(output_pixels.y)/viewport_pixels.y
	return render_pixels_per_unit*output_scale
func cm_to_world_units(cm: float,viewport_pixels: Vector2i,output_pixels: Vector2i,camera_size: float,axis: int=0) -> float:
	var ppw:=pixels_per_world_unit(viewport_pixels,output_pixels,camera_size,axis)
	return cm*(pixels_per_cm_x if axis==0 else pixels_per_cm_y)/ppw if ppw>0 else 0.0
func world_units_to_cm(units: float,viewport_pixels: Vector2i,output_pixels: Vector2i,camera_size: float,axis: int=0) -> float:
	var ppcm:=pixels_per_cm_x if axis==0 else pixels_per_cm_y
	return units*pixels_per_world_unit(viewport_pixels,output_pixels,camera_size,axis)/ppcm if ppcm>0 else 0.0
func model_scale(model_length: float,viewport_pixels: Vector2i,output_pixels: Vector2i,camera_size: float) -> float:
	return cm_to_world_units(target_fish_length_cm,viewport_pixels,output_pixels,camera_size)/model_length if model_length>0 else 0.0
static func measure_model(model: Node3D) -> Dictionary:
	var id:=model.get_instance_id()
	if model_measurements.has(id):return model_measurements[id]
	var total:=AABB();var first:=true;var vertex_count:=0;var body:=AABB()
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		var local: Transform3D=model.global_transform.affine_inverse()*mesh.global_transform
		var local_bounds:=AABB();var local_first:=true
		for surface in range(mesh.mesh.get_surface_count()):
			var vertices: PackedVector3Array=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point:=local*vertex
				if first:total=AABB(point,Vector3.ZERO);first=false
				else:total=total.expand(point)
				if local_first:local_bounds=AABB(point,Vector3.ZERO);local_first=false
				else:local_bounds=local_bounds.expand(point)
				vertex_count+=1
		if mesh.name=="Fish_Body":body=local_bounds
	var result: Dictionary={"total_length":total.size.x,"body_length":body.size.x,"center":total.get_center(),"bounds":total,"vertex_count":vertex_count,"definition":"Total Length: rest mesh snout to outer caudal tip, X extent"}
	model_measurements[id]=result
	return result
func snapshot() -> Dictionary:
	return {"calibration_version":VERSION,"calibration_timestamp":calibration_timestamp,"screen_pixel_width":screen_pixel_width,"screen_pixel_height":screen_pixel_height,"physical_screen_width_cm":physical_screen_width_cm,"physical_screen_height_cm":physical_screen_height_cm,"height_method":"inferred_square_pixels","pixels_per_cm_x":pixels_per_cm_x,"pixels_per_cm_y":pixels_per_cm_y,"correction_factor":correction_factor,"target_fish_length_cm":target_fish_length_cm,"monitor":monitor.duplicate(true)}
func load_profile(path: String="") -> String:
	if path.is_empty():path=portable_path()
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return "Keine Bildschirmkalibrierung gespeichert. Bitte zuerst F10 öffnen."
	if file.get_length()>262144:return "Kalibrierungsdatei ist zu groß."
	var data=JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("version")!=VERSION or not data.get("profiles") is Dictionary or not data.get("active_profile") is String:return "Ungültiges Kalibrierungsformat. Bitte mit F10 neu kalibrieren."
	var profile=data.profiles.get(data.active_profile)
	if not profile is Dictionary or not profile.get("monitor") is Dictionary:return "Aktives Kalibrierprofil fehlt."
	for key in ["physical_screen_width_cm","target_fish_length_cm","correction_factor","screen_pixel_width","screen_pixel_height"]:
		var value=profile.get(key)
		if not (value is int or value is float) or not is_finite(value) or value<=0:return "Ungültiger Kalibrierwert: "+key
	if profile.get("calibration_version")!=VERSION or not profile.get("calibration_timestamp") is String:return "Ungültige Kalibrierversion oder Zeitangabe."
	var context: Dictionary=profile.monitor
	if not context.get("screen_size") is Array or context.screen_size.size()!=2:return "Ungültige Monitorauflösung."
	if context.screen_size!=[profile.screen_pixel_width,profile.screen_pixel_height]:return "Widersprüchliche Monitorauflösung."
	var error:=configure(profile.physical_screen_width_cm,context,profile.target_fish_length_cm)
	if not error.is_empty():return error
	correction_factor=profile.correction_factor;recalculate()
	if not valid():return "Ungültige Messkorrektur."
	calibration_timestamp=profile.calibration_timestamp;active_profile=data.active_profile;profiles=data.profiles.duplicate(true)
	return ""
func save_profile(path: String="") -> String:
	if not valid():return "Bitte zuerst die sichtbare Bildschirmbreite eingeben."
	if path.is_empty():path=portable_path()
	calibration_timestamp=Time.get_datetime_string_from_system(true)+"Z"
	profiles[active_profile]=snapshot()
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return "Kalibrierung kann nicht gespeichert werden."
	file.store_string(JSON.stringify({"version":VERSION,"active_profile":active_profile,"profiles":profiles},"\t"));file.flush()
	var error:=file.get_error();file.close()
	if error!=OK or DirAccess.rename_absolute(path+".tmp",path)!=OK:return "Kalibrierung konnte nicht sicher gespeichert werden."
	return ""
