extends "res://scripts/sequences/validate_sequences.gd"
const DisplaySetup=preload("res://scripts/experiment/display_setup.gd")
var exp: Node
func _ready() -> void:
	super._ready();report_filename="experimenter_validation.json";screenshot_prefix="experimenter_"
func run() -> void:
	if DisplayServer.get_name()=="headless":await super.run();return
	root.show();root.size=Vector2i(1400,1050)
	viewer=load("res://scenes/PhotoImport.tscn").instantiate();viewer.set_script(preload("res://scripts/sequences/sequence_test_viewer.gd"));root.add_child(viewer);await wait(.6)
	var photo=viewer.get_node("UI/ReferencePhoto")
	photo.project_manager=Manager.new(ProjectSettings.globalize_path("res://dist/PelvicachromisStudio/projects") if OS.has_feature("editor") else Paths.projects_dir())
	var entries: Array=photo.project_manager.list_projects();check(not entries.is_empty(),"Saved individual fish fixture")
	if entries.is_empty():finish();return
	check(photo.open_project(entries[0].id),"Load individual fish for native output")
	var manifest: String=photo.project_manager.folder(photo.project_id).path_join("project.json");var hash:=FileAccess.get_sha256(manifest)
	viewer.open_experimenter();exp=viewer.experiment;exp.focus_checks_enabled=false
	var fixtures:=ProjectSettings.globalize_path("res://.godot") if OS.has_feature("editor") else out
	exp.setup=DisplaySetup.new(fixtures.path_join("experimenter_display_setup_test.json"));exp.setup.experimenter_screen=root.current_screen;exp.setup.stimulus_screen=root.current_screen;exp.setup.development=true
	check(exp.setup.save_setup().is_empty(),"Save portable monitor selection")
	var restored:=DisplaySetup.new(exp.setup.path);check(restored.load_setup().is_empty() and restored.saved_context==exp.setup.saved_context,"Load display fingerprint")
	exp.config_override=viewer.test_config();exp.view.store=SequenceStore.new(fixtures.path_join("experimenter_sequences"));exp.view.store.ensure_examples()
	var definition:=SequenceData.fresh("Native window validation");definition.steps=[SequenceData.step("HOLD"),SequenceData.step("MOVE")];definition.steps[0].duration_s=.3;definition.steps[1].duration_s=.7;definition.steps[1].target_speed_cm_s=2;definition.total_duration_s=1
	check(exp.view.store.save_sequence(definition).is_empty(),"Native test sequence stored")
	exp.view.populate();select_definition(definition.sequence_id);exp.view.preview.button_pressed=true
	check(exp.output!=root and exp.output.force_native and exp.output.unfocusable,"Two native logically separate windows, output cannot take focus")
	check(exp.validate_experiment_readiness(exp.make_request()).error.is_empty(),"Central readiness succeeds")
	var bad: Dictionary=exp.make_request();bad.preview=false;bad.trial_id="NOT-A-TRIAL"
	check(not exp.validate_experiment_readiness(bad).error.is_empty(),"Single monitor real trial blocked with warning")
	var original_context: Dictionary=exp.setup.saved_context.duplicate(true);exp.setup.saved_context.screen_scale=99
	check(not exp.validate_experiment_readiness(exp.make_request()).error.is_empty(),"Changed monitor scaling rejected")
	exp.setup.saved_context=original_context
	check(await exp.prepare(),"Native window created and prepared")
	check(exp.output.get_window_id()!=root.get_window_id() and exp.output.current_screen==exp.setup.stimulus_screen,"Different native IDs and selected screen")
	check(exp.output.renderer.find_children("*","Label",true,false).is_empty() and exp.output.find_children("*","BaseButton",true,false).is_empty(),"Output contains no labels/buttons including preview")
	check(exp.output.renderer.viewport.gui_disable_input==false or not exp.output.renderer.sample_input,"Stimulus accepts no experimenter input")
	check(await exp.start()=="","Native sequence start")
	var camera_transform: Transform3D=exp.output.renderer.camera.transform;var camera_size: float=exp.output.renderer.camera.size
	await wait(.15);exp.view.show_progress(exp.output.renderer.sequence_progress(),exp.output.snapshot())
	check(exp.view.live.text.contains("Tempo Soll") and exp.view.live.text.contains("Schritt"),"Live read-only telemetry")
	check(exp.view.visible and exp.view.pause_button.disabled==false,"Experimenter remains usable")
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true;root.push_input(wheel,true)
	var drag:=InputEventMouseMotion.new();drag.relative=Vector2(200,80);drag.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(drag,true)
	exp.pause_or_resume();var phase: float=viewer.animation_player.current_animation_position;var t: float=exp.output.renderer.sequence_runner.time_s
	await wait(.15);check(exp.output.renderer.sequence_runner.paused and exp.output.renderer.sequence_runner.time_s==t and viewer.animation_player.current_animation_position==phase,"Native pause freezes time and animation")
	await snapshot("experimenter_console")
	var image: Image=exp.output.get_texture().get_image();check(image.save_png(out.path_join("experimenter_output.png"))==OK,"Native clean output screenshot")
	exp.pause_or_resume();await wait(1.1)
	check(not exp.active and exp.last_reason=="sequence_completed","Native sequence finishes")
	check(exp.output.visible and not exp.output.renderer.visible,"End leaves background only")
	check(exp.output.renderer.camera.transform==camera_transform and exp.output.renderer.camera.size==camera_size,"Operator UI cannot change orthographic camera")
	check(FileAccess.get_sha256(manifest)==hash,"Fish project unchanged")
	var lines:=FileAccess.get_file_as_string(exp.output.renderer.last_log_path).split("\n",false);var events: Array=[]
	for line in lines:
		var data: Dictionary=JSON.parse_string(line);events.append(data.event)
	check(events.has("SESSION_STARTED") and events.has("PAUSED") and events.has("RESUMED") and events.has("SESSION_COMPLETED") and events.has("STIMULUS_WINDOW_READY"),"Native events complete")
	var details: Dictionary=JSON.parse_string(lines[0]).details
	for key in ["experimenter_screen","stimulus_screen","stimulus_resolution","stimulus_window_position","fullscreen_state","calibration_profile","stimulus_window_created","stimulus_window_ready"]:check(details.has(key),"Display metadata "+key)
	definition.steps=[SequenceData.step("HOLD")];definition.steps[0].duration_s=10;definition.total_duration_s=10;exp.view.store.save_sequence(definition)
	check(await exp.prepare(),"Prepare abort test");check(await exp.start()=="","Start abort test");await wait(.1);exp.abort()
	check(not exp.active and exp.last_reason=="operator_abort" and exp.output.visible,"Operator abort neutralizes, windows stay open")
	check(FileAccess.get_file_as_string(exp.output.renderer.last_log_path).contains("SESSION_ABORTED"),"Abort event saved")
	exp.setup.neutral_mode="CENTER_FISH";exp.view.neutral.select(1);check(await exp.prepare(),"Prepare neutral fish test");check(await exp.start()=="","Start neutral fish test");await wait(.1);exp.abort()
	check(is_instance_valid(exp.output.neutral_fish) and exp.output.renderer.visible,"Optional stationary neutral fish")
	exp.reset_trial();check(not is_instance_valid(exp.output.neutral_fish) and exp.prepared.is_empty(),"Reset clears neutral fish and readiness")
	for reason in ["stimulus_monitor_lost","stimulus_display_changed","stimulus_minimized"]:
		check(await exp.prepare(),"Prepare "+reason);check(await exp.start()=="","Start "+reason);exp.monitor_event(reason)
		check(not exp.active and exp.last_reason==reason and not exp.output.renderer.visible,"Safe abort "+reason)
		check(FileAccess.get_file_as_string(exp.output.renderer.last_log_path).contains("DISPLAY_CHANGE_EVENT"),"Display event logged "+reason)
	check(await exp.prepare(),"Prepare focus test");check(await exp.start()=="","Start focus test");exp.focus_event("EXPERIMENTER_FOCUS_OUT");exp.abort("application_focus_lost")
	check(FileAccess.get_file_as_string(exp.output.renderer.last_log_path).contains("FOCUS_EVENT"),"Focus event logged")
	exp.view.manual.button_pressed=true;check(await exp.prepare(),"Prepare manual input from experimenter");check(await exp.start()=="","Start manual input")
	event("stimulus_right");await wait(.15)
	check(exp.output.renderer.motion.position.x>0 and exp.output.renderer.sequence_runner.overriding,"Experimenter keyboard drives permitted override without output focus")
	var release:=InputEventAction.new();release.action="stimulus_right";release.pressed=false;root.push_input(release,true);exp.abort()
	check(FileAccess.get_file_as_string(exp.output.renderer.last_log_path).contains("MANUAL_OVERRIDE"),"Native override logged")
	exp.view.manual.button_pressed=false
	check(await exp.prepare(),"Prepare actual resize test");check(await exp.start()=="","Start actual resize test")
	exp.output.size+=Vector2i(20,0);await wait(.1)
	check(not exp.active and exp.last_reason=="stimulus_resolution_changed","Actual native resize aborts safely")
	check(await exp.prepare(),"Prepare missing-screen monitor check");check(await exp.start()=="","Start missing-screen monitor check")
	exp.output.selected_screen=DisplayServer.get_screen_count();await wait(.1)
	check(not exp.active and exp.last_reason=="stimulus_monitor_lost","Monitor polling detects unavailable index")
	root.grab_focus();await wait(.1)
	check(await exp.prepare(),"Prepare OS focus transfer");check(await exp.start()=="","Start OS focus transfer");exp.focus_checks_enabled=true
	var other:=Window.new();other.visible=false;other.force_native=true;other.size=Vector2i(160,100);root.add_child(other);other.show();other.grab_focus();await wait(.15)
	print("FOCUS_DIAGNOSTIC ",{"active":exp.active,"reason":exp.last_reason,"root_focus":root.has_focus(),"other_focus":other.has_focus(),"log":exp.output.renderer.last_log_path})
	check(not exp.active and exp.last_reason=="application_focus_lost","Actual OS focus transfer aborts")
	exp.focus_checks_enabled=false;exp.abort();other.queue_free();root.grab_focus();await wait(.1)
	# Real OS fullscreen transition; no claim of a physically attached second monitor.
	root.grab_focus();await wait(.1);exp.setup.development=false;await exp.output.prepare(exp.setup,DisplayServer.screen_get_size(root.current_screen),Color(.12,.12,.12))
	check(exp.output.mode==Window.MODE_FULLSCREEN and exp.output.health().is_empty(),"Native fullscreen on available physical monitor")
	check(root.has_focus() and not exp.output.has_focus(),"Fullscreen output leaves experimenter keyboard focus intact")
	exp.output.mouse_entered.emit();check(Input.mouse_mode==Input.MOUSE_MODE_HIDDEN,"Output cursor hidden");exp.output.mouse_exited.emit();check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"Operator cursor restored")
	var changed:=DisplaySetup.context(root.current_screen);changed.screen_size=[640,480];check(exp.output.health(changed)=="stimulus_display_changed","Resolution fingerprint detects simulated change")
	exp.output.mode=Window.MODE_MINIMIZED;await wait(.1);check(exp.output.health()=="stimulus_minimized","Actual minimize detected")
	exp.output.mode=Window.MODE_WINDOWED;exp.close();viewer.queue_free();await wait(.2)
	FileAccess.open(out.path_join("experimenter_hardware.json"),FileAccess.WRITE).store_string(JSON.stringify({"physical_screen_count":DisplayServer.get_screen_count(),"native_windows_tested":true,"native_fullscreen_tested":true,"native_focus_transfer_tested":true,"native_resize_tested":true,"second_physical_monitor_tested":false,"unplug_simulated":true},"\t"))
	await super.run()
func select_definition(id: String) -> void:
	for i in range(exp.view.sequence.item_count):
		if exp.view.sequence.get_item_metadata(i)==id:exp.view.sequence.select(i);return
