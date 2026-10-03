extends RefCounted
const Setup=preload("res://scripts/experiment/display_setup.gd")
const Calibration=preload("res://scripts/stimulus/display_calibration.gd")
const Config=preload("res://scripts/stimulus/stimulus_config.gd")
const Data=preload("res://scripts/sequences/sequence_data.gd")
const Runner=preload("res://scripts/sequences/sequence_runner.gd")
const Paths=preload("res://scripts/storage/portable_paths.gd")
static func validate_experiment_readiness(viewer: Node,setup: RefCounted,request: Dictionary,override: Resource=null) -> Dictionary:
	var error: String=setup.validate_selection(bool(request.get("preview",false)))
	if not error.is_empty():return {"error":error}
	if viewer.get_window().current_screen!=setup.experimenter_screen:return {"error":"Experimentatorfenster ist nicht auf dem ausgewählten Monitor. Bitte Monitorwahl speichern."}
	if not is_instance_valid(viewer.fish) or viewer.animation_player==null or viewer.swim_animation.is_empty():return {"error":"Fisch oder Schwimmanimation fehlt."}
	var meshes: Array=viewer.fish.find_children("*","MeshInstance3D",true,false)
	var textures:=0
	for mesh in meshes:
		for index in range(mesh.mesh.get_surface_count()):
			var material=mesh.get_active_material(index)
			if material is BaseMaterial3D and material.albedo_texture!=null:textures+=1
	if textures==0:return {"error":"Fischtextur nicht verfügbar."}
	var photo=viewer.get_node("UI/ReferencePhoto")
	if photo.worker!=null or photo.analysis_worker!=null:return {"error":"Bitte Fotoverarbeitung abwarten."}
	if not request.get("preview",false) and (str(photo.project_id).is_empty() or str(request.get("trial_id","")).strip_edges().is_empty()):return {"error":"Fischprojekt und Versuchs-ID sind erforderlich."}
	var config=Config.new()
	error=config.load_portable() if override==null else config.apply(override.snapshot())
	if not error.is_empty():return {"error":error}
	var calibration=Calibration.new()
	if override!=null and override.calibration_override!=null:
		calibration=override.calibration_override # Explicit test injection only.
	else:
		error=calibration.load_profile()
		if not error.is_empty():return {"error":error}
	error=calibration.mismatch(Setup.context(setup.stimulus_screen))
	if not error.is_empty():return {"error":"Stimulusmonitor: "+error}
	config.calibration_override=calibration;config.fullscreen=not setup.development;config.stop_on_focus_loss=false
	var context: Dictionary=Setup.context(setup.stimulus_screen)
	var pixels:=Vector2i(context.screen_size[0],context.screen_size[1])
	if setup.development:pixels=Vector2i(mini(960,pixels.x-80),mini(600,pixels.y-80))
	config.apply_calibration(calibration,pixels,pixels)
	var bounds:=Data.visible_bounds(calibration,pixels,config.fish_display_length_cm)
	error=Data.validate(request.get("sequence"),config.max_stimulus_speed_cm_s)
	if not error.is_empty():return {"error":error}
	error=Runner.preflight(request.sequence,config,bounds).error
	if not error.is_empty():return {"error":error}
	error=Paths.initialize()
	if not error.is_empty():return {"error":error}
	var log_dir:=Paths.data_dir().path_join("experiments/previews" if request.get("preview",false) else "experiments")
	if DirAccess.make_dir_recursive_absolute(log_dir)!=OK:return {"error":"Versuchsordner nicht beschreibbar."}
	var probe:=log_dir.path_join(".readiness_"+Crypto.new().generate_random_bytes(8).hex_encode())
	var file:=FileAccess.open(probe,FileAccess.WRITE)
	if file==null:return {"error":"Versuchslogging nicht möglich."}
	file.store_string("probe");file.flush();error="" if file.get_error()==OK else "Versuchslogging nicht möglich.";file.close();DirAccess.remove_absolute(probe)
	var texture_hash:=FileAccess.get_sha256(photo.texture_path) if photo.showing_generated and FileAccess.file_exists(photo.texture_path) else "original"
	return {"error":error,"config":config,"calibration":calibration,"pixels":pixels,"context":context,"bounds":bounds,"project_name":photo.project_name,"project_id":photo.project_id,"texture_hash":texture_hash}
