extends Control
signal stopped(reason: String)
const SequenceData=preload("res://scripts/sequences/sequence_data.gd")
const SequenceRunner=preload("res://scripts/sequences/sequence_runner.gd")
const Paths=preload("res://scripts/storage/portable_paths.gd")
const Config=preload("res://scripts/stimulus/stimulus_config.gd")
const Calibration=preload("res://scripts/stimulus/display_calibration.gd")
const TrialLog=preload("res://scripts/stimulus/stimulus_log.gd")
@onready var viewport: SubViewport=$Presentation/Viewport
@onready var camera: Camera3D=$Presentation/Viewport/World/Camera
@onready var motion: Node3D=$Presentation/Viewport/World/FishMotion
@onready var display_scale: Node3D=$Presentation/Viewport/World/FishMotion/DisplayScale
@onready var center: Node3D=$Presentation/Viewport/World/FishMotion/DisplayScale/FishCenter
var sequence_runner: RefCounted
var sequence_request: Dictionary={}
var old_animation_process: int
var sequence_log_failed:=false
var preview_label: Label
var external_host:=false # Native stimulus window owns focus, cursor and neutral state.
var active:=false
var starting:=false
var sample_input:=true
var external_command: Dictionary={}
var config: Resource
var calibration: RefCounted
var measurement: Dictionary
var display_context: Dictionary
var log_writer: RefCounted
var last_log_path: String
var fish: Node3D
var original_parent: Node
var original_transform: Transform3D
var player: AnimationPlayer
var old_speed: float
var old_phase: float
var old_playing: bool
var old_mouse: int
var old_window_mode: int
var old_window_size: Vector2i
var old_window_position: Vector2i
var fixed_size: Vector2i
var elapsed:=0.0
var sample_elapsed:=0.0
var previous_command: Dictionary={}
func _ready() -> void:
	preload("res://scripts/stimulus/motion_realism.gd").register_inputs()
func start_stimulus_session(model: Node3D,animation: AnimationPlayer,clip: StringName,metadata: Dictionary={},override: Resource=null,request: Dictionary={}) -> String:
	if active or starting:return "Es läuft bereits ein Stimulusversuch."
	sequence_request=request.duplicate(true);sequence_runner=null;sequence_log_failed=false
	config=Config.new()
	var error: String=config.load_portable() if override==null else config.apply(override.snapshot())
	if not error.is_empty():return error
	calibration=Calibration.new()
	if override!=null and override.calibration_override!=null:
		# Explicit dependency injection for validation; runtime F9 always loads the portable profile.
		var supplied: RefCounted=override.calibration_override
		error=calibration.configure(supplied.physical_screen_width_cm,supplied.monitor,supplied.target_fish_length_cm)
		calibration.correction_factor=supplied.correction_factor;calibration.calibration_timestamp=supplied.calibration_timestamp;calibration.recalculate()
		calibration.active_profile=supplied.active_profile
	else:error=calibration.load_profile()
	if not error.is_empty():return error
	display_context=Calibration.display_context(get_window())
	error=calibration.mismatch(display_context)
	if not error.is_empty():return error
	measurement=Calibration.measure_model(model)
	if measurement.total_length<=0:return "Ungültige Gesamtlänge des Modells."
	starting=true
	fish=model;player=animation;original_parent=fish.get_parent();original_transform=fish.transform
	old_animation_process=player.callback_mode_process
	old_speed=player.speed_scale;old_phase=player.current_animation_position;old_playing=player.is_playing()
	old_mouse=Input.mouse_mode;old_window_mode=get_window().mode;old_window_size=get_window().size;old_window_position=get_window().position
	if config.fullscreen and get_window().mode!=Window.MODE_FULLSCREEN:get_window().mode=Window.MODE_FULLSCREEN
	show()
	if not external_host:Input.mouse_mode=Input.MOUSE_MODE_HIDDEN
	for i in range(6):await get_tree().process_frame
	fixed_size=get_window().size
	var actual: Dictionary=Calibration.display_context(get_window())
	if not calibration.mismatch(actual).is_empty():
		_abort_start();return "Bildschirm während des Starts gewechselt. Bitte mit F10 neu kalibrieren."
	var px_x:=Calibration.pixels_per_world_unit(viewport.size,fixed_size,config.view_height,0)
	var px_y:=Calibration.pixels_per_world_unit(viewport.size,fixed_size,config.view_height,1)
	if px_x<=0 or not is_equal_approx(px_x,px_y):
		_abort_start();return "Die Viewport-Skalierung ist nicht gleichmäßig. Bitte Anzeigeeinstellungen prüfen."
	config.apply_calibration(calibration,viewport.size,fixed_size)
	if not sequence_request.is_empty():
		if not sequence_request.get("sequence") is Dictionary:
			_abort_start();return "Sequenzdefinition fehlt."
		if not sequence_request.get("preview",false) and str(sequence_request.get("trial_id","")).strip_edges().is_empty():
			_abort_start();return "Bitte eine Versuchskennung eingeben."
		var area:=SequenceData.visible_bounds(calibration,fixed_size,config.fish_display_length_cm)
		var validation:=SequenceRunner.preflight(sequence_request.sequence,config,area)
		if not validation.error.is_empty():_abort_start();return validation.error
		sequence_runner=SequenceRunner.new()
	fish.reparent(center,false);fish.transform=Transform3D.IDENTITY
	center.position=-measurement.center
	display_scale.scale=Vector3.ONE*calibration.model_scale(measurement.total_length,viewport.size,fixed_size,config.view_height)
	camera.position=Vector3(0,0,config.plane_depth+config.camera_distance)
	camera.rotation=Vector3.ZERO;camera.size=config.view_height
	camera.far=config.camera_distance+maxf(config.view_height,config.fish_display_length_cm*config.units_per_cm)*2
	camera.make_current()
	var environment: Environment=$Presentation/Viewport/World/Environment.environment
	environment.background_color=config.background_color
	player.play(clip);motion.configure(config,player)
	error=motion.attach_pose(fish)
	if not error.is_empty():
		fish.reparent(original_parent,false);fish.transform=original_transform;player.speed_scale=old_speed;player.seek(old_phase,true)
		if not old_playing:player.pause()
		_abort_start();return error
	elapsed=0;sample_elapsed=0;previous_command={};external_command={}
	var context: Dictionary=metadata.duplicate(true)
	context.merge({"config":config.runtime_snapshot(),"calibrated":true,"calibration":calibration.snapshot(),"fish_display_length_cm":config.fish_display_length_cm,"speed_cm_s":config.speed_cm_s,"model_total_length_world":measurement.total_length,"display_scale":display_scale.scale.x,"world_units_per_cm":config.units_per_cm,"body_length_definition":measurement.definition,"plane":"X/Y; constant Z","position_units":"Godot units","speed_units":"Godot units/second","viewport_pixels":[fixed_size.x,fixed_size.y],"camera_position":[camera.position.x,camera.position.y,camera.position.z],"projection":"orthographic KEEP_HEIGHT","physics_ticks_per_second":Engine.physics_ticks_per_second})
	log_writer=TrialLog.new();log_writer.flush_interval=config.flush_interval
	if sequence_runner!=null:
		player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		sequence_runner.configure(sequence_request.sequence,motion,SequenceData.visible_bounds(calibration,fixed_size,config.fish_display_length_cm),bool(sequence_request.get("allow_manual_override",false)),_sequence_event)
		context["sequence_definition"]=sequence_runner.definition
		context["sequence_sha256"]=sequence_runner.definition_hash
		context["integration_quantum_s"]=SequenceRunner.QUANTUM
		context["max_realtime_gap_s"]=SequenceRunner.MAX_REALTIME_GAP
		log_writer.start_event="SESSION_STARTED"
		log_writer.fixed_fields={"trial_id":sequence_request.get("trial_id",""),"animal_id":sequence_request.get("animal_id",""),"preview":sequence_request.get("preview",false),"active_fish":{"project_id":metadata.get("project_id",""),"project_name":metadata.get("project_name",""),"generated_coloring":metadata.get("generated_coloring",false),"texture_sha256":metadata.get("generated_texture_sha256","")},"fish_display_length_cm":config.fish_display_length_cm,"calibration_profile":calibration.active_profile,"calibration":calibration.snapshot()}
		log_writer.telemetry_provider=sequence_runner.telemetry
		if sequence_request.get("preview",false):log_writer.directory_override=Paths.data_dir().path_join("experiments/previews")
		if preview_label==null and not external_host:
			preview_label=Label.new();preview_label.position=Vector2(16,16);preview_label.text="VORSCHAU / PREVIEW · Leertaste: Pause · Esc: Beenden";preview_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(preview_label)
		if preview_label!=null:preview_label.visible=sequence_request.get("preview",false) and not external_host
	elif preview_label!=null:preview_label.hide()
	if external_host:log_writer.fixed_fields.merge(metadata,true)
	error=log_writer.begin(context);last_log_path=log_writer.path
	starting=false;active=true
	if not error.is_empty():stop_stimulus_session("log_error");return error
	if sequence_runner!=null:sequence_runner.begin(Time.get_ticks_usec()/1000000.0);return ""
	if not log_writer.record("initial_state",motion.state(),{},elapsed):stop_stimulus_session("log_error");return "Versuchsprotokoll nicht beschreibbar."
	return ""
func command_from_input() -> Dictionary:
	return {"x":Input.get_axis("stimulus_left","stimulus_right"),"y":Input.get_axis("stimulus_down","stimulus_up"),"speed":Input.get_axis("stimulus_slower","stimulus_faster"),"facing":Input.get_axis("stimulus_turn_left","stimulus_turn_right"),"pitch":Input.get_axis("stimulus_pitch_down","stimulus_pitch_up"),"boost":Input.is_action_pressed("stimulus_boost")}
func set_command(command: Dictionary) -> void:
	# External controller/sequence API; no presentation widgets or project mutation.
	external_command={}
	external_command.boost=bool(command.get("boost",false))
	for key in ["x","y","speed","facing","pitch"]:
		var value: float=float(command.get(key,0))
		external_command[key]=clampf(value,-1,1) if is_finite(value) else 0.0
func _physics_process(delta: float) -> void:
	if not active or sequence_runner!=null:return
	if get_window().size!=fixed_size:stop_stimulus_session("window_resized");return
	if Calibration.display_context(get_window())!=display_context:stop_stimulus_session("monitor_changed");return
	var command: Dictionary=command_from_input() if sample_input else external_command
	motion.step(delta,command);elapsed+=delta;sample_elapsed+=delta
	for turn_event in motion.take_turn_events():
		if not log_writer.record(turn_event.event,motion.state(),command,elapsed,turn_event):stop_stimulus_session("log_error");return
	var event: String="command" if command!=previous_command else "sample"
	if event=="command" or sample_elapsed>=1.0/config.log_hz:
		if not log_writer.record(event,motion.state(),command,elapsed):stop_stimulus_session("log_error");return
		sample_elapsed=0;previous_command=command.duplicate()
func reset_stimulus() -> void:
	if not active:return
	if sequence_runner!=null:sequence_runner.manual_reset();return
	motion.reset_stimulus();external_command={}
	if not log_writer.record("reset",motion.state(),{},elapsed):stop_stimulus_session("log_error")
func stop_stimulus_session(reason: String="operator_stop") -> void:
	if not active:return
	active=false
	if sequence_runner==null:
		motion.finish_turn()
		for turn_event in motion.take_turn_events():log_writer.record(turn_event.event,motion.state(),previous_command,elapsed,turn_event)
	if sequence_runner!=null:
		if reason in ["monitor_changed","window_resized"]:_sequence_event("CALIBRATION_WARNING",{"reason":reason})
		sequence_runner.abort(reason)
	elif not log_writer.record("session_stop",motion.state(),previous_command,elapsed,{"reason":reason}):reason="log_error"
	log_writer.close()
	motion.detach_pose()
	fish.reparent(original_parent,false);fish.transform=original_transform
	player.callback_mode_process=old_animation_process
	player.speed_scale=old_speed;player.seek(old_phase,true)
	if not old_playing:player.pause()
	hide()
	if not external_host:
		Input.mouse_mode=old_mouse;get_window().mode=old_window_mode
		if old_window_mode==Window.MODE_WINDOWED:get_window().size=old_window_size;get_window().position=old_window_position
	stopped.emit(reason)
func _input(event: InputEvent) -> void:
	if not active or external_host:return
	if event.is_action_pressed("stimulus_exit"):stop_stimulus_session("escape")
	elif event.is_action_pressed("sequence_pause") and not event.is_echo() and sequence_runner!=null:sequence_runner.toggle_pause(Time.get_ticks_usec()/1000000.0)
	elif event.is_action_pressed("stimulus_reset"):reset_stimulus()
	get_viewport().set_input_as_handled()
func _notification(what: int) -> void:
	if external_host:return
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and active and config.stop_on_focus_loss:stop_stimulus_session("focus_lost")
	if what==NOTIFICATION_WM_CLOSE_REQUEST and active:stop_stimulus_session("window_closed")
func _exit_tree() -> void:
	if log_writer!=null:log_writer.close()

func _abort_start() -> void:
	starting=false;hide()
	if not external_host:
		Input.mouse_mode=old_mouse;get_window().mode=old_window_mode
		if old_window_mode==Window.MODE_WINDOWED:get_window().size=old_window_size;get_window().position=old_window_position

func _sequence_event(event: String,extra: Dictionary={}) -> void:
	if log_writer==null:return
	if not log_writer.record(event,motion.state(),sequence_runner.manual if sequence_runner.overriding else {},sequence_runner.time_s,extra):sequence_log_failed=true
func _process(_delta: float) -> void:
	if not active or sequence_runner==null:return
	if get_window().size!=fixed_size:stop_stimulus_session("window_resized");return
	if Calibration.display_context(get_window())!=display_context:stop_stimulus_session("monitor_changed");return
	sequence_runner.tick(Time.get_ticks_usec()/1000000.0,command_from_input() if sample_input else external_command)
	if sequence_log_failed:stop_stimulus_session("log_error")
	elif sequence_runner.finished:stop_stimulus_session("sequence_completed" if sequence_runner.completed else "sequence_aborted")
func sequence_progress() -> Dictionary:
	# Future experimenter window/API; never draw this in a real stimulus viewport.
	return sequence_runner.telemetry() if sequence_runner!=null else {}
