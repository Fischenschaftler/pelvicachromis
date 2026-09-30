extends "res://scripts/stimulus/validate_stimulus.gd"
var profile_path: String
func _ready() -> void:
	report_filename="display_calibration_validation.json";screenshot_prefix="calibrated_"
	super._ready()
func sample_context(width: int=1920,height: int=1080) -> Dictionary:
	return {"monitor_index":0,"screen_count":1,"screen_size":[width,height],"screen_position":[0,0],"screen_scale":1.0}
func run() -> void:
	profile_path=ProjectSettings.globalize_path("res://.godot/calibration_test_profile.json") if OS.has_feature("editor") else Paths.logs_dir().path_join("calibration_test_profile.json")
	var c:=Calibration.new()
	check(c.configure(48,sample_context()).is_empty(),"Configure manual width")
	check(is_equal_approx(c.pixels_per_cm_x,40) and is_equal_approx(c.physical_screen_height_cm,27),"Pixels/cm and inferred height")
	check(is_equal_approx(c.reference_pixels(10),400),"10 cm ruler")
	var viewport:=Vector2i(1920,1080);var camera_size:=0.24
	var model_length:=0.08
	for cm in [5.0,8.0]:
		c.target_fish_length_cm=cm
		var scale:=c.model_scale(model_length,viewport,viewport,camera_size)
		check(is_equal_approx(scale*model_length*1080/camera_size,cm*40),"Projected fish length "+str(cm))
		var world:=c.cm_to_world_units(cm,viewport,viewport,camera_size)
		check(is_equal_approx(c.world_units_to_cm(world,viewport,viewport,camera_size),cm),"cm/world roundtrip")
		check(is_equal_approx(c.cm_to_world_units(cm,viewport/2,viewport,camera_size),world),"Rendering resolution independent of output pixels")
	check(c.correct_measurement(10,9.7).is_empty(),"Ruler correction accepted")
	check(is_equal_approx(c.reference_pixels(10),400*10.0/9.7),"Correct correction direction")
	check(not c.correct_measurement(10,0).is_empty(),"Zero measurement rejected")
	check(c.save_profile(profile_path).is_empty(),"Save profile")
	var loaded:=Calibration.new();check(loaded.load_profile(profile_path).is_empty(),"Load profile")
	check(is_equal_approx(loaded.pixels_per_cm_x,c.pixels_per_cm_x) and loaded.monitor==c.monitor,"Roundtrip calibration")
	loaded.profiles["FutureMonitor"]=loaded.snapshot();check(loaded.save_profile(profile_path).is_empty(),"Atomic overwrite")
	check(c.load_profile(profile_path).is_empty() and c.profiles.has("FutureMonitor"),"Other profiles preserved")
	check(not c.mismatch(sample_context(3840,2160)).is_empty(),"Resolution mismatch warning")
	var other:=sample_context();other.monitor_index=1
	check(not c.mismatch(other).is_empty(),"Monitor mismatch warning")
	other=sample_context();other.screen_scale=1.5
	check(not c.mismatch(other).is_empty(),"OS scale mismatch warning")
	for resolution in [Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]:
		for width in [48.0,60.0,80.0]:
			c.configure(width,sample_context(resolution.x,resolution.y))
			check(is_equal_approx(c.pixels_per_cm_x,resolution.x/width),"Resolution/width pixels/cm")
			check(is_equal_approx(c.cm_to_world_units(8,resolution,resolution,.24)*resolution.y/.24,8*resolution.x/width),"Resolution/width model projection")
	var legacy:=Config.new()
	check(legacy.apply({"fish_display_length":7.5,"units_per_cm":.01,"stimulus_speed":.05,"max_speed":.10}).is_empty() and legacy.speed_cm_s==5 and legacy.fish_display_length_cm==7.5,"Legacy nominal config migration")
	check(not Config.new().apply({"speed_cm_s":-1}).is_empty(),"Invalid speed rejected")
	var settings:=Config.new();c.configure(48,sample_context());settings.speed_cm_s=5
	settings.apply_calibration(c,viewport,viewport)
	check(is_equal_approx(c.world_units_to_cm(settings.stimulus_speed,viewport,viewport,.24),5),"5 cm/s world conversion")
	check(c.configure(0,sample_context()).length()>0,"Zero width rejected")
	if DisplayServer.get_name()=="headless":finish();return
	root.show();root.size=Vector2i(1400,900)
	viewer=load("res://scenes/PhotoImport.tscn").instantiate();root.add_child(viewer);await wait(.5)
	check(InputMap.action_get_events("display_calibration")[0].physical_keycode==KEY_F10,"F10 binding")
	# Deliberately synthetic dimensions; never save into the real portable calibration file.
	c.configure(60,Calibration.display_context(root));c.target_fish_length_cm=8;c.save_profile(profile_path)
	await viewer.open_display_calibration(profile_path)
	var setup=viewer.calibration_view
	check(setup.active and root.mode==Window.MODE_FULLSCREEN,"Fullscreen calibration setup")
	check(not viewer.get_node("UI").visible,"Setup separated from viewer")
	setup.width_input.value=60;setup.measured_input.value=9.7;setup.correction_button.pressed.emit()
	check(is_equal_approx(setup.calibration.correction_factor,10.0/9.7),"Manual UI correction")
	setup.fish_input.value=5.25
	await wait(.2);await snapshot("stimulus_calibration_setup")
	await RenderingServer.frame_post_draw
	var screenshot:=root.get_texture().get_image()
	var line_y:=roundi(setup.ruler.global_position.y+35)
	var left:=screenshot.get_width();var right: int=-1
	for x in range(screenshot.get_width()):
		var color:=screenshot.get_pixel(x,line_y)
		if color.r>.95 and color.g>.95 and color.b>.95:left=mini(left,x);right=maxi(right,x)
	check(absf((right-left)-setup.ruler.pixel_length)<=3,"Rendered ruler length in actual fullscreen pixels")
	setup.save_button.pressed.emit();check(not setup.active,"Save closes setup")
	check(c.load_profile(profile_path).is_empty() and is_equal_approx(c.target_fish_length_cm,5.25),"Fractional target length persists")
	# F10 keyboard route and Escape must not save or enter a trial.
	event("display_calibration");await wait(.3)
	check(viewer.calibration_view.active,"F10 opens setup")
	event("stimulus_exit");check(not viewer.calibration_view.active,"Esc cancels calibration")
	for cm in [5.0,8.0]:
		var config:=Config.new();config.stop_on_focus_loss=false;config.fullscreen=true
		config.calibration_override=Calibration.new();config.calibration_override.configure(60,Calibration.display_context(root),cm)
		check((await viewer.start_stimulus_session(config)).is_empty(),"Calibrated full-screen trial")
		var stimulus=viewer.stimulus;stimulus.set_physics_process(false)
		var measurement: Dictionary=stimulus.measurement
		check(measurement.total_length>measurement.body_length,"Total length includes caudal fin")
		check(absf(measurement.total_length-.08)<.005,"Actual model total length about 8 cm in native units")
		var left_point: Vector2=stimulus.camera.unproject_position(Vector3(-measurement.total_length*stimulus.display_scale.scale.x*.5,0,0))
		var right_point: Vector2=stimulus.camera.unproject_position(Vector3(measurement.total_length*stimulus.display_scale.scale.x*.5,0,0))
		check(absf(right_point.x-left_point.x-cm*stimulus.calibration.pixels_per_cm_x)<.01,"Camera-projected physical total length "+str(cm))
		var original_camera: Transform3D=stimulus.camera.transform
		stimulus.sample_input=false;stimulus.set_command({"x":1})
		for i in range(180):stimulus._physics_process(1.0/60.0)
		check(is_equal_approx(stimulus.motion.state().speed_cm_s,config.speed_cm_s),"Actual movement rate in cm/s")
		check(stimulus.camera.transform==original_camera,"Calibrated camera stays fixed")
		viewer.reset_stimulus();await wait(.2);await snapshot("stimulus_fish_"+str(int(cm))+"cm")
		var log_path: String=stimulus.last_log_path
		viewer.stop_stimulus_session()
		var first: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(log_path).split("\n")[0])
		check(first.details.calibrated and first.details.calibration.screen_pixel_width>0 and first.details.fish_display_length_cm==cm and first.details.speed_cm_s==config.speed_cm_s,"Calibration metadata in trial log")
		check(first.details.config.screen_width_cm>0 and first.details.config.pixels_per_cm>0,"Calibrated runtime configuration")
		check(first.details.calibration.has("calibration_timestamp") and first.details.calibration.calibration_version==1,"Timestamp/version logged")
	# Wrong monitor is refused before the fish is moved or fullscreen activated.
	var wrong:=Config.new();wrong.calibration_override=Calibration.new();wrong.calibration_override.configure(60,sample_context())
	wrong.calibration_override.monitor.monitor_index=-42
	check(not (await viewer.stimulus.start_stimulus_session(viewer.fish,viewer.animation_player,viewer.swim_animation,{},wrong)).is_empty(),"Reject invalid monitor before trial")
	check(not viewer.stimulus.active,"Mismatch creates no active trial")
	viewer.queue_free();await get_tree().process_frame;viewer=null
	# Run the complete existing stimulus regression after calibration-specific checks.
	await super.run()
