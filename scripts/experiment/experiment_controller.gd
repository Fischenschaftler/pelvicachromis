extends Node
const Setup=preload("res://scripts/experiment/display_setup.gd")
const Readiness=preload("res://scripts/experiment/experiment_readiness.gd")
const Store=preload("res://scripts/sequences/sequence_store.gd")
const Data=preload("res://scripts/sequences/sequence_data.gd")
var viewer: Node3D
var setup=Setup.new()
var view: Control
var output: Window
var request: Dictionary={}
var prepared: Dictionary={}
var prepared_hash: String
var active:=false
var busy:=false
var keys: Dictionary={}
var last_reason: String
var config_override: Resource # Test injection only, never set by production UI.
var poll_elapsed:=0.0
var focus_checks_enabled:=true
func _ready() -> void:
	view=preload("res://scripts/experiment/experimenter_view.gd").new();view.controller=self;add_child(view)
	output=preload("res://scripts/stimulus/stimulus_window_controller.gd").new();add_child(output)
	output.output_event.connect(output_event);output.renderer.stopped.connect(stopped)
	view.message.text=setup.load_setup();view.populate()
	get_window().focus_entered.connect(func():focus_event("EXPERIMENTER_FOCUS_IN"))
	get_window().focus_exited.connect(func():focus_event("EXPERIMENTER_FOCUS_OUT"))
	get_window().close_requested.connect(func():abort("application_closed"))
func open() -> void:
	view.show();view.populate();viewer.get_node("UI").hide();viewer.get_node("ViewerViewport").hide();viewer.get_node("Background").hide()
	invalidate()
func close() -> void:
	if active or busy:return
	output.clear_neutral();output.hide();view.hide();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	viewer.get_node("UI").show();viewer.get_node("ViewerViewport").show();viewer.get_node("Background").show()
func invalidate() -> void:
	prepared={};prepared_hash="";view.start_button.disabled=true
func select_displays() -> void:
	if active or busy:return
	invalidate();setup.experimenter_screen=view.experiment_screen.get_selected_id();setup.stimulus_screen=view.stimulus_screen.get_selected_id();setup.development=view.development.button_pressed;setup.neutral_mode="CENTER_FISH" if view.neutral.selected==1 else "BACKGROUND"
	view.message.text=setup.save_setup()
	if view.message.text.is_empty():
		get_window().current_screen=setup.experimenter_screen
		get_window().position=DisplayServer.screen_get_position(setup.experimenter_screen)+Vector2i(30,30)
		view.message.text="Monitorwahl gespeichert. "+("ENTWICKLUNG: keine wissenschaftliche Präsentation." if setup.development else "Bitte Versuch vorbereiten.")
func make_request() -> Dictionary:
	var result: Dictionary=view.store.load_sequence(view.sequence.get_selected_metadata()) if view.sequence.selected>=0 else {"error":"Bitte Sequenz auswählen."}
	if result.has("error"):return result
	return {"sequence":result.data,"trial_id":"" if view.preview.button_pressed else view.trial.text.strip_edges(),"animal_id":view.animal.text.strip_edges(),"preview":view.preview.button_pressed,"allow_manual_override":view.manual.button_pressed}
func validate_experiment_readiness(candidate: Dictionary) -> Dictionary:
	if candidate.has("error"):return candidate
	return Readiness.validate_experiment_readiness(viewer,setup,candidate,config_override)
func readiness_signature(value: Dictionary) -> String:
	return Data.checksum({"project":value.project_id,"texture":value.texture_hash,"calibration":value.calibration.snapshot(),"config":value.config.snapshot(),"display":value.context})
func prepare() -> bool:
	if active or busy:return false
	if view.experiment_screen.get_selected_id()!=setup.experimenter_screen or view.stimulus_screen.get_selected_id()!=setup.stimulus_screen or view.development.button_pressed!=setup.development or (view.neutral.selected==1)!=(setup.neutral_mode=="CENTER_FISH"):
		view.message.text="Bitte die geänderte Monitorwahl zuerst speichern.";return false
	invalidate();request=make_request();prepared=validate_experiment_readiness(request)
	if not prepared.error.is_empty():view.message.text=prepared.error;prepared={};return false
	busy=true;view.update_locked()
	var error: String=await output.prepare(setup,prepared.pixels,prepared.config.background_color)
	busy=false;view.update_locked()
	if not error.is_empty():view.message.text=error;prepared={};output.neutralize("BACKGROUND");return false
	prepared_hash=Data.checksum(request);view.start_button.disabled=false
	view.summary.text="%s\nVersuch: %s · Tier: %s\nFisch: %s · Sequenz: %s\n%.2f cm · Profil: %s · Hintergrund #%s\nStimulusmonitor %d · %s Pixel · %.3f s · Override %s" % ["ENTWICKLUNG / PREVIEW" if request.preview else "ECHTER VERSUCH",request.trial_id,request.animal_id,prepared.project_name,request.sequence.sequence_name,prepared.config.fish_display_length_cm,prepared.calibration.active_profile,prepared.config.background_color.to_html(false),setup.stimulus_screen,str(prepared.context.screen_size),request.sequence.total_duration_s,"erlaubt" if request.allow_manual_override else "gesperrt"]
	view.message.text="Stimulus bereit. Zusammenfassung prüfen, anschließend Stimulus starten."
	return true
func start() -> String:
	if active or busy:return "Versuch läuft bereits."
	var candidate:=make_request()
	if prepared.is_empty() or candidate.has("error") or Data.checksum(candidate)!=prepared_hash:return fail("Vor dem Start bitte Versuch vorbereiten.")
	var checked:=validate_experiment_readiness(candidate)
	if not checked.error.is_empty():return fail(checked.error)
	if readiness_signature(checked)!=readiness_signature(prepared):return fail("Fisch, Färbung oder Einstellungen wurden seit der Vorbereitung geändert. Bitte erneut vorbereiten.")
	var health: String=output.health()
	if not health.is_empty():return fail(health)
	request=candidate.duplicate(true);prepared=checked;busy=true;keys.clear();view.update_locked();output.clear_neutral()
	var photo=viewer.get_node("UI/ReferencePhoto")
	var metadata: Dictionary={"project_id":photo.project_id,"project_name":photo.project_name,"generated_coloring":photo.showing_generated,"experimenter_screen":setup.experimenter_screen,"experimenter_window_id":get_window().get_window_id(),"display_setup":setup.saved_context,"development":setup.development}
	if photo.showing_generated and FileAccess.file_exists(photo.texture_path):metadata.generated_texture_sha256=FileAccess.get_sha256(photo.texture_path)
	metadata.merge(output.snapshot());metadata.calibration_profile=prepared.calibration.active_profile
	var error: String=await output.renderer.start_stimulus_session(viewer.fish,viewer.animation_player,viewer.swim_animation,metadata,prepared.config,request)
	busy=false
	if not error.is_empty():output.neutralize("BACKGROUND");view.update_locked();return fail(error)
	active=true;output.renderer.sample_input=false
	if focus_checks_enabled and not get_window().has_focus():abort("application_focus_lost");return "Experimentatorfenster hat während des Starts den Fokus verloren."
	output.renderer.log_writer.fixed_fields.merge(metadata,true)
	record("STIMULUS_WINDOW_READY",output.snapshot());view.message.text="Versuch läuft.";view.update_locked();view.start_button.release_focus()
	return ""
func fail(message: String) -> String:view.message.text=message;invalidate();return message
func pause_or_resume() -> void:
	if active:output.renderer.sequence_runner.toggle_pause(Time.get_ticks_usec()/1000000.0)
func abort(reason: String="operator_abort") -> void:
	if active:output.renderer.stop_stimulus_session(reason)
func reset_trial() -> void:
	if busy:return
	if active:abort("operator_reset")
	output.neutralize("BACKGROUND");keys.clear();invalidate();view.live.text="Zurückgesetzt: nächste Sequenz beginnt bei Zeit 0, Position und Animationsphase 0."
func stopped(reason: String) -> void:
	active=false;keys.clear();last_reason=reason
	var normal:=reason in ["sequence_completed","operator_abort","operator_reset","escape"]
	output.neutralize(setup.neutral_mode if normal else "BACKGROUND",viewer.fish,viewer.swim_animation)
	if output.renderer.sequence_runner!=null and not prepared.is_empty():
		view.show_progress(output.renderer.sequence_progress(),output.snapshot())
		view.live.text=view.live.text.replace("Logging: aktiv","Logging: geschlossen")+"\nStimulus im Neutralzustand."
	view.message.text="Versuch beendet: %s\nProtokoll: %s" % [reason,output.renderer.last_log_path];invalidate();view.update_locked()
func record(kind: String,details: Dictionary={}) -> void:
	if active:output.renderer._sequence_event(kind,details)
func output_event(kind: String,details: Dictionary) -> void:
	record(kind,details)
	if kind=="WINDOW_CLOSE_REQUEST":
		if active:abort("stimulus_window_closed")
		else:output.hide();invalidate()
func focus_event(kind: String) -> void:
	record("FOCUS_EVENT",{"kind":kind});keys.clear()
	if kind=="EXPERIMENTER_FOCUS_OUT" and active and focus_checks_enabled:call_deferred("check_focus")
func check_focus() -> void:
	if active and not get_window().has_focus():abort("application_focus_lost")
func monitor_event(reason: String) -> void:
	if not active:return
	record("DISPLAY_CHANGE_EVENT",{"reason":reason,"window":output.snapshot()});record("CALIBRATION_WARNING",{"reason":reason});abort(reason)
func _process(delta: float) -> void:
	if not active:return
	# Native focus signals may precede the OS focus-state update by a frame.
	if focus_checks_enabled and not get_window().has_focus():
		record("FOCUS_EVENT",{"kind":"EXPERIMENTER_FOCUS_OUT","detected_by":"window_state"});keys.clear();abort("application_focus_lost");return
	if get_window().current_screen!=setup.experimenter_screen:monitor_event("experimenter_monitor_changed");return
	output.renderer.set_command({"x":axis("stimulus_left","stimulus_right"),"y":axis("stimulus_down","stimulus_up"),"speed":axis("stimulus_slower","stimulus_faster"),"facing":axis("stimulus_turn_left","stimulus_turn_right"),"pitch":axis("stimulus_pitch_down","stimulus_pitch_up"),"yaw":axis("stimulus_yaw_left","stimulus_yaw_right"),"boost":keys.get("stimulus_boost",false)})
	var error: String=output.health()
	if not error.is_empty():monitor_event(error);return
	poll_elapsed+=delta
	if poll_elapsed>=.1:
		poll_elapsed=0;view.show_progress(output.renderer.sequence_progress(),output.snapshot())
func axis(negative: String,positive: String) -> float:return float(keys.get(positive,false))-float(keys.get(negative,false))
func _input(event: InputEvent) -> void:
	if not view.visible:return
	if event.is_action_pressed("stimulus_exit"):
		if active:abort("escape")
		elif not busy:close()
		get_viewport().set_input_as_handled();return
	if not active:return
	if event.is_action_pressed("sequence_pause") and not event.is_echo():pause_or_resume()
	if event.is_action_pressed("stimulus_reset") and not event.is_echo():output.renderer.reset_stimulus()
	for action in ["stimulus_left","stimulus_right","stimulus_down","stimulus_up","stimulus_slower","stimulus_faster","stimulus_turn_left","stimulus_turn_right","stimulus_pitch_up","stimulus_pitch_down","stimulus_boost","stimulus_yaw_left","stimulus_yaw_right"]:
		if event.is_action(action):keys[action]=event.is_pressed()
	if event is InputEventKey or event is InputEventAction:get_viewport().set_input_as_handled()
func select_fish() -> void:
	if active or busy:return
	close();viewer.get_node("UI/ReferencePhoto").project_browser.show_projects()
func edit_sequence() -> void:
	if active or busy:return
	close();viewer.open_sequence_editor()
func calibrate() -> void:
	if active or busy:return
	close()
	var window:=get_window();var old_position:=window.position;var old_size:=window.size;var old_screen:=window.current_screen
	window.current_screen=setup.stimulus_screen;window.position=DisplayServer.screen_get_position(setup.stimulus_screen)+Vector2i(20,20)
	await viewer.open_display_calibration()
	if viewer.calibration_view!=null:
		viewer.calibration_view.closed.connect(func():window.current_screen=old_screen;window.position=old_position;window.size=old_size;open(),CONNECT_ONE_SHOT)
func test_window() -> void:
	if active or busy:return
	var context:=Setup.context(setup.stimulus_screen)
	if context.is_empty():view.message.text="Stimulusmonitor fehlt.";return
	busy=true;view.update_locked();invalidate()
	var pixels:=Vector2i(context.screen_size[0],context.screen_size[1])
	if setup.development:pixels=Vector2i(mini(960,pixels.x-80),mini(600,pixels.y-80))
	var error: String=await output.prepare(setup,pixels,Color(.12,.12,.12))
	busy=false;view.update_locked();view.message.text="Fenstertest: nur neutraler Hintergrund. "+str(output.snapshot()) if error.is_empty() else error
func _exit_tree() -> void:
	if active and is_instance_valid(output) and is_instance_valid(output.renderer):abort("application_closed")
