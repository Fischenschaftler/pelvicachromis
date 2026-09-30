extends Node3D
## Imported meshes, materials, rig and animation resources stay untouched.
@onready var orbit: Node3D = $ViewerViewport/Viewport/World/OrbitCamera
@onready var animation_button: Button = $UI/Layout/Bottom/Buttons/Animation
@onready var reset_button: Button = $UI/Layout/Bottom/Buttons/Reset
@onready var fish: Node3D = $ViewerViewport/Viewport/World/FishMotion/Fish
var animation_player: AnimationPlayer
var swim_animation: StringName
@onready var fish_controller: Node3D=$ViewerViewport/Viewport/World/FishMotion
@onready var chase: Node3D=$ViewerViewport/Viewport/World/ChaseCamera
@onready var control_button: Button=$UI/ControlMode
@onready var hint: Label=$UI/Layout/Header/Hint
var stimulus: Control
var stimulus_pending:=false
var control_mode := false
var viewing_animation_playing := true
var viewing_hint := ""
var photo_was_visible := true

func _ready() -> void:
	get_window().min_size = Vector2i(480, 360)
	var bounds := AABB()
	var first := true
	for node in fish.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	orbit.configure(bounds)
	animation_button.pressed.connect(toggle_animation)
	reset_button.pressed.connect(reset_view)
	control_button.pressed.connect(toggle_fish_control)
	get_viewport().size_changed.connect(func(): call_deferred("layout_control"))
	hint.text="Linke Maustaste: drehen · Rad: Zoom · F9: Stimulus"
	viewing_hint=hint.text
	for node in fish.find_children("*", "AnimationPlayer", true, false):
		animation_player = node as AnimationPlayer
		break
	if animation_player != null:
		for clip in animation_player.get_animation_list():
			if String(clip).to_lower() == "swim_test":
				swim_animation = clip
				break
	if animation_player == null or swim_animation.is_empty():
		animation_button.disabled = true
		animation_button.text = "Animation nicht verfügbar"
		push_error("Viewer: imported Swim_Test animation missing")
		return
	if animation_player.get_animation(swim_animation).loop_mode != Animation.LOOP_LINEAR:
		push_error("Viewer: imported Swim_Test must loop")
	animation_player.play(swim_animation)
	fish_controller.configure(animation_player)
	chase.configure(fish_controller,bounds)
	_update_button()

func toggle_animation() -> void:
	if control_mode:return
	if animation_player.is_playing():
		animation_player.pause()
	else:
		animation_player.play(swim_animation)
	_update_button()

func _update_button() -> void:
	animation_button.text = "Animation stoppen" if animation_player.is_playing() else "Animation starten"


func _input(event: InputEvent) -> void:
	if stimulus_pending or (stimulus!=null and stimulus.active):return
	if event.is_action_pressed("stimulus_start") and not event.is_echo():
		start_stimulus_session();get_viewport().set_input_as_handled();return
	if control_mode and event.is_action_pressed("fish_control_exit"):
		end_fish_control();get_viewport().set_input_as_handled();return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		orbit.dragging = false
		chase.dragging = false

func _unhandled_input(event: InputEvent) -> void:
	if stimulus_pending or (stimulus!=null and stimulus.active):return
	# Root UI gets first refusal; only unused events reach the 3D viewport.
	if event is InputEventMouse:
		var area: SubViewportContainer = $ViewerViewport
		if area.get_global_rect().has_point(event.position):
			var local_event: InputEventMouse = event.duplicate()
			local_event.position -= area.global_position
			local_event.global_position = local_event.position
			$ViewerViewport/Viewport.push_input(local_event, true)
			get_viewport().set_input_as_handled()

func toggle_fish_control() -> void:
	if control_mode:end_fish_control()
	else:begin_fish_control()
func begin_fish_control() -> void:
	if control_mode or animation_player==null or stimulus_pending or (stimulus!=null and stimulus.active):return
	var photo:=get_node_or_null("UI/ReferencePhoto")
	if photo!=null:
		# Do not hide a modal or a still-running photo worker.
		for window in photo.find_children("*","Window",true,false):
			if window.visible:return
		if photo.get("worker")!=null or photo.get("analysis_worker")!=null:return
		photo_was_visible=photo.visible;photo.hide()
	var focus:=get_viewport().gui_get_focus_owner()
	if focus!=null:focus.release_focus()
	viewing_animation_playing=animation_player.is_playing()
	control_mode=true
	fish_controller.begin();chase.begin()
	orbit.dragging=false
	animation_player.play(swim_animation)
	animation_button.disabled=true;animation_button.text="Schwimmtempo automatisch"
	control_button.text="Steuerung beenden"
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hint.text="W Vorwärts · S Bremsen · A / D Drehen · Q / E Tiefer / höher · Shift Schneller · Esc Beenden\nLinke Maustaste: Kamera drehen · Mausrad: zoomen"
	call_deferred("layout_control")
func end_fish_control() -> void:
	if not control_mode:return
	control_mode=false
	fish_controller.end();chase.end();orbit.camera.make_current();orbit.reset_view()
	animation_button.disabled=false
	if viewing_animation_playing:animation_player.play(swim_animation)
	else:animation_player.pause()
	_update_button();control_button.text="Fisch steuern"
	hint.autowrap_mode=TextServer.AUTOWRAP_OFF;hint.text=viewing_hint
	var photo:=get_node_or_null("UI/ReferencePhoto")
	if photo!=null:
		photo.visible=photo_was_visible
		if photo.has_method("layout"):photo.call("layout")
func reset_view() -> void:
	if control_mode:chase.reset_view()
	else:orbit.reset_view()
func reset_fish_control() -> void:
	fish_controller.reset_fish_control()
	if control_mode:chase.reset_view()
func layout_control() -> void:
	if not control_mode:return
	await get_tree().process_frame
	if not control_mode:return
	var area: Control=$ViewerViewport
	area.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var size:=get_viewport().get_visible_rect().size
	var top:=hint.get_global_rect().end.y+8.0
	area.position=Vector2(0,top);area.size=Vector2(size.x,maxf(80.0,size.y-top-64.0))
	chase.resize()

func start_stimulus_session(config_override: Resource=null) -> String:
	if stimulus_pending or (stimulus!=null and stimulus.active):return "Stimulus bereits aktiv."
	if animation_player==null:return "Schwimmanimation fehlt."
	var photo:=get_node_or_null("UI/ReferencePhoto")
	if photo!=null:
		for window in photo.find_children("*","Window",true,false):
			if window.visible:return "Bitte zuerst den geöffneten Dialog schließen."
		if photo.get("worker")!=null or photo.get("analysis_worker")!=null:return "Bitte die Fotoverarbeitung abwarten."
	if control_mode:end_fish_control()
	stimulus_pending=true
	if stimulus==null:
		stimulus=preload("res://scenes/StimulusMode.tscn").instantiate()
		add_child(stimulus);stimulus.hide();stimulus.stopped.connect(_stimulus_stopped)
	var metadata: Dictionary={}
	if photo!=null:
		metadata={"project_id":photo.get("project_id"),"project_name":photo.get("project_name"),"generated_coloring":photo.get("showing_generated")}
		var texture_path: String=photo.get("texture_path")
		if photo.get("showing_generated") and FileAccess.file_exists(texture_path):metadata["generated_texture_sha256"]=FileAccess.get_sha256(texture_path)
	var focus:=get_viewport().gui_get_focus_owner()
	if focus!=null:focus.release_focus()
	orbit.dragging=false;chase.dragging=false
	$UI.hide();$ViewerViewport.hide();$Background.hide()
	var error: String=await stimulus.start_stimulus_session(fish,animation_player,swim_animation,metadata,config_override)
	stimulus_pending=false
	if not error.is_empty():
		_stimulus_stopped("start_failed")
		if photo!=null:photo.call("fail",error)
	return error
func stop_stimulus_session() -> void:
	if stimulus!=null:stimulus.stop_stimulus_session()
func reset_stimulus() -> void:
	if stimulus!=null:stimulus.reset_stimulus()
func _stimulus_stopped(reason: String) -> void:
	$UI.show();$ViewerViewport.show();$Background.show()
	if reason=="log_error":
		var photo:=get_node_or_null("UI/ReferencePhoto")
		if photo!=null:photo.call("fail","Versuch beendet: Protokoll konnte nicht geschrieben werden.")
