extends Control
signal stopped(reason: String)
const Config=preload("res://scripts/stimulus/stimulus_config.gd")
const TrialLog=preload("res://scripts/stimulus/stimulus_log.gd")
@onready var viewport: SubViewport=$Presentation/Viewport
@onready var camera: Camera3D=$Presentation/Viewport/World/Camera
@onready var motion: Node3D=$Presentation/Viewport/World/FishMotion
@onready var display_scale: Node3D=$Presentation/Viewport/World/FishMotion/DisplayScale
@onready var center: Node3D=$Presentation/Viewport/World/FishMotion/DisplayScale/FishCenter
var active:=false
var starting:=false
var sample_input:=true
var external_command: Dictionary={}
var config: Resource
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
func start_stimulus_session(model: Node3D,animation: AnimationPlayer,clip: StringName,metadata: Dictionary={},override: Resource=null) -> String:
	if active or starting:return "Es läuft bereits ein Stimulusversuch."
	config=Config.new()
	var error: String=config.load_portable() if override==null else config.apply(override.snapshot())
	if not error.is_empty():return error
	var bodies:=model.find_children("Fish_Body","MeshInstance3D",true,false)
	if bodies.size()!=1:return "Fish_Body fehlt oder ist nicht eindeutig."
	var body: MeshInstance3D=bodies[0]
	var bounds: AABB=(model.global_transform.affine_inverse()*body.global_transform)*body.get_aabb()
	if bounds.size.x<=0:return "Ungültige Körperlänge."
	starting=true
	fish=model;player=animation;original_parent=fish.get_parent();original_transform=fish.transform
	old_speed=player.speed_scale;old_phase=player.current_animation_position;old_playing=player.is_playing()
	old_mouse=Input.mouse_mode;old_window_mode=get_window().mode;old_window_size=get_window().size;old_window_position=get_window().position
	if config.fullscreen:get_window().mode=Window.MODE_FULLSCREEN
	show();Input.mouse_mode=Input.MOUSE_MODE_HIDDEN
	for i in range(6):await get_tree().process_frame
	fixed_size=get_window().size
	fish.reparent(center,false);fish.transform=Transform3D.IDENTITY
	center.position=-bounds.get_center()
	display_scale.scale=Vector3.ONE*config.fish_display_length*config.units_per_cm/bounds.size.x
	camera.position=Vector3(0,0,config.plane_depth+config.camera_distance)
	camera.rotation=Vector3.ZERO;camera.size=config.view_height
	camera.far=config.camera_distance+maxf(config.view_height,config.fish_display_length*config.units_per_cm)*2
	camera.make_current()
	var environment: Environment=$Presentation/Viewport/World/Environment.environment
	environment.background_color=config.background_color
	player.play(clip);motion.configure(config,player)
	elapsed=0;sample_elapsed=0;previous_command={};external_command={}
	var context: Dictionary=metadata.duplicate(true)
	context.merge({"config":config.snapshot(),"calibrated":false,"body_length_definition":"Fish_Body X extent, excludes caudal fin","plane":"X/Y; constant Z","position_units":"Godot units","speed_units":"Godot units/second","viewport_pixels":[fixed_size.x,fixed_size.y],"camera_position":[camera.position.x,camera.position.y,camera.position.z],"projection":"orthographic KEEP_HEIGHT","physics_ticks_per_second":Engine.physics_ticks_per_second})
	log_writer=TrialLog.new();log_writer.flush_interval=config.flush_interval
	error=log_writer.begin(context);last_log_path=log_writer.path
	starting=false;active=true
	if not error.is_empty():stop_stimulus_session("log_error");return error
	if not log_writer.record("initial_state",motion.state(),{},elapsed):stop_stimulus_session("log_error");return "Versuchsprotokoll nicht beschreibbar."
	return ""
func command_from_input() -> Dictionary:
	return {"x":Input.get_axis("stimulus_left","stimulus_right"),"y":Input.get_axis("stimulus_down","stimulus_up"),"speed":Input.get_axis("stimulus_slower","stimulus_faster"),"facing":Input.get_axis("stimulus_turn_left","stimulus_turn_right")}
func set_command(command: Dictionary) -> void:
	# External controller/sequence API; no presentation widgets or project mutation.
	external_command={}
	for key in ["x","y","speed","facing"]:
		var value: float=float(command.get(key,0))
		external_command[key]=clampf(value,-1,1) if is_finite(value) else 0.0
func _physics_process(delta: float) -> void:
	if not active:return
	if get_window().size!=fixed_size:stop_stimulus_session("window_resized");return
	var command: Dictionary=command_from_input() if sample_input else external_command
	motion.step(delta,command);elapsed+=delta;sample_elapsed+=delta
	var event: String="command" if command!=previous_command else "sample"
	if event=="command" or sample_elapsed>=1.0/config.log_hz:
		if not log_writer.record(event,motion.state(),command,elapsed):stop_stimulus_session("log_error");return
		sample_elapsed=0;previous_command=command.duplicate()
func reset_stimulus() -> void:
	if not active:return
	motion.reset_stimulus();external_command={}
	if not log_writer.record("reset",motion.state(),{},elapsed):stop_stimulus_session("log_error")
func stop_stimulus_session(reason: String="operator_stop") -> void:
	if not active:return
	active=false
	if not log_writer.record("session_stop",motion.state(),previous_command,elapsed,{"reason":reason}):reason="log_error"
	log_writer.close()
	fish.reparent(original_parent,false);fish.transform=original_transform
	player.speed_scale=old_speed;player.seek(old_phase,true)
	if not old_playing:player.pause()
	hide();Input.mouse_mode=old_mouse
	get_window().mode=old_window_mode
	if old_window_mode==Window.MODE_WINDOWED:get_window().size=old_window_size;get_window().position=old_window_position
	stopped.emit(reason)
func _input(event: InputEvent) -> void:
	if not active:return
	if event.is_action_pressed("stimulus_exit"):stop_stimulus_session("escape")
	elif event.is_action_pressed("stimulus_reset"):reset_stimulus()
	get_viewport().set_input_as_handled()
func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and active and config.stop_on_focus_loss:stop_stimulus_session("focus_lost")
	if what==NOTIFICATION_WM_CLOSE_REQUEST and active:stop_stimulus_session("window_closed")
func _exit_tree() -> void:
	if log_writer!=null:log_writer.close()
