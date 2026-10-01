extends Window
## Native output surface. Never parent an experimenter widget into this window.
signal output_event(kind: String,details: Dictionary)
const Setup=preload("res://scripts/experiment/display_setup.gd")
var renderer: Control
var backdrop: ColorRect
var selected_screen: int
var expected_context: Dictionary={}
var expected_size:=Vector2i.ZERO
var expected_fullscreen:=false
var neutral_fish: Node3D
func _init() -> void:
	visible=false;force_native=true;transient=false;exclusive=false;unfocusable=true;title="Pelvicachromis Stimulus"
func _ready() -> void:
	backdrop=ColorRect.new();backdrop.color=Color(.12,.12,.12);backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(backdrop);backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	renderer=preload("res://scenes/StimulusMode.tscn").instantiate();renderer.external_host=true;renderer.sample_input=false;add_child(renderer);renderer.hide()
	close_requested.connect(func():output_event.emit("WINDOW_CLOSE_REQUEST",{}))
	focus_entered.connect(func():output_event.emit("STIMULUS_FOCUS_IN",{}))
	focus_exited.connect(func():output_event.emit("STIMULUS_FOCUS_OUT",{}))
	mouse_entered.connect(func():Input.mouse_mode=Input.MOUSE_MODE_HIDDEN)
	mouse_exited.connect(func():Input.mouse_mode=Input.MOUSE_MODE_VISIBLE)
func prepare(setup: RefCounted,pixels: Vector2i,color: Color) -> String:
	clear_neutral();backdrop.color=color;selected_screen=setup.stimulus_screen;expected_context=Setup.context(selected_screen)
	if expected_context.is_empty():return "Stimulusmonitor fehlt."
	expected_fullscreen=not setup.development;mode=Window.MODE_WINDOWED;current_screen=selected_screen
	size=pixels;position=DisplayServer.screen_get_position(selected_screen)+Vector2i(40,40)
	if setup.development:
		var usable:=DisplayServer.screen_get_usable_rect(selected_screen)
		var operator_window:=get_tree().root
		var beside:=Vector2i(operator_window.position.x+operator_window.size.x+20,operator_window.position.y)
		if usable.encloses(Rect2i(beside,size)):position=beside
	show()
	if expected_fullscreen:mode=Window.MODE_FULLSCREEN
	for i in range(6):await get_tree().process_frame
	# Windows can activate a window during the fullscreen transition despite NO_FOCUS.
	# Restore the operator before any trial starts; never focus the output for controls.
	if expected_fullscreen:
		get_tree().root.grab_focus()
		for i in range(3):await get_tree().process_frame
	expected_size=size
	if get_window_id()==DisplayServer.INVALID_WINDOW_ID:return "Natives Stimulusfenster konnte nicht erzeugt werden."
	return health()
func health(current: Dictionary={}) -> String:
	if not visible:return "stimulus_hidden"
	if mode==Window.MODE_MINIMIZED:return "stimulus_minimized"
	if current.is_empty():current=Setup.context(selected_screen)
	if current.is_empty():return "stimulus_monitor_lost"
	if current!=expected_context:return "stimulus_display_changed"
	if current_screen!=selected_screen:return "stimulus_wrong_monitor"
	if size!=expected_size:return "stimulus_resolution_changed"
	if expected_fullscreen and mode!=Window.MODE_FULLSCREEN:return "stimulus_fullscreen_lost"
	if renderer.active and renderer.viewport.size!=size:return "stimulus_viewport_changed"
	return ""
func snapshot() -> Dictionary:
	return {"stimulus_window_created":get_window_id()!=DisplayServer.INVALID_WINDOW_ID,"stimulus_window_ready":health().is_empty(),"stimulus_screen":selected_screen,"stimulus_resolution":[size.x,size.y],"stimulus_window_position":[position.x,position.y],"fullscreen_state":mode==Window.MODE_FULLSCREEN,"stimulus_window_id":get_window_id(),"stimulus_viewport_size":[renderer.viewport.size.x,renderer.viewport.size.y]}
func clear_neutral() -> void:
	if is_instance_valid(neutral_fish):neutral_fish.free()
	neutral_fish=null
func neutralize(mode_name: String,model: Node3D=null,clip: StringName=&"") -> void:
	clear_neutral();renderer.hide()
	if mode_name=="CENTER_FISH" and model!=null and not expected_context.is_empty() and health().is_empty():
		neutral_fish=model.duplicate();renderer.center.add_child(neutral_fish);neutral_fish.transform=Transform3D.IDENTITY
		renderer.motion.position=Vector3(0,0,renderer.config.plane_depth);renderer.motion.rotation=Vector3.ZERO
		for player in neutral_fish.find_children("*","AnimationPlayer",true,false):
			player.play(clip);player.seek(0,true);player.pause()
		renderer.show()
	update_cursor()
func update_cursor() -> void:
	if not visible:return
	var over_output:=DisplayServer.get_window_at_screen_position(DisplayServer.mouse_get_position())==get_window_id()
	Input.mouse_mode=Input.MOUSE_MODE_HIDDEN if over_output else Input.MOUSE_MODE_VISIBLE
func _process(_delta: float) -> void:update_cursor()
func _exit_tree() -> void:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
