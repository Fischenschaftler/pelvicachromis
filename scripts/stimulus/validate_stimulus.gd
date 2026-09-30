extends Node
## Runs in editor and in a separately exported diagnostic release scene.
const Calibration=preload("res://scripts/stimulus/display_calibration.gd")
const Config=preload("res://scripts/stimulus/stimulus_config.gd")
const Paths=preload("res://scripts/storage/portable_paths.gd")
const Manager=preload("res://scripts/project/project_manager.gd")
var report_filename: String="stimulus_validation.json"
var screenshot_prefix: String="stimulus_"
var errors: Array[String]=[]
var checks:=0
var viewer: Node3D
var root: Window
var out: String
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:errors.append(label);push_error(label)
func _ready() -> void:
	root=get_tree().root
	out=ProjectSettings.globalize_path("res://godot/diagnostics") if OS.has_feature("editor") else Paths.logs_dir()
	call_deferred("run")
func wait(seconds: float=0.1) -> void:await get_tree().create_timer(seconds).timeout
func event(action: String) -> void:
	var e:=InputEventAction.new();e.action=action;e.pressed=true;root.push_input(e,true)
func advance(seconds: float,command: Dictionary={}) -> void:
	viewer.stimulus.set_command(command)
	for i in range(roundi(seconds*60)):viewer.stimulus._physics_process(1.0/60.0)
func snapshot(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(out.path_join(name.replace("stimulus_",screenshot_prefix)+".png"))==OK,"Screenshot "+name)
func run() -> void:
	root.show();root.size=Vector2i(1400,900)
	viewer=load("res://scenes/PhotoImport.tscn").instantiate();root.add_child(viewer);await wait(.6)
	check(InputMap.action_get_events("stimulus_start")[0].physical_keycode==KEY_F9,"F9 binding")
	check(InputMap.action_get_events("stimulus_reset")[0].physical_keycode==KEY_F8,"F8 binding")
	var photo=viewer.get_node("UI/ReferencePhoto")
	var fixture: String=ProjectSettings.globalize_path("res://dist/PelvicachromisStudio/projects") if OS.has_feature("editor") else Paths.projects_dir()
	photo.project_manager=Manager.new(fixture)
	var entries: Array=photo.project_manager.list_projects()
	check(entries.size()>0,"Saved individual project fixture")
	if entries.is_empty():finish();return
	check(photo.open_project(entries[0].id),"Open project before stimulus")
	var manifest: String=photo.project_manager.folder(photo.project_id).path_join("project.json")
	var manifest_hash:=FileAccess.get_sha256(manifest)
	var count: int=photo.analysis_count
	var material_refs: Array=[]
	for mesh in viewer.fish.find_children("*","MeshInstance3D",true,false):
		for i in range(mesh.get_surface_override_material_count()):material_refs.append([mesh,i,mesh.get_active_material(i)])
	var config:=Config.new();config.fullscreen=false;config.stop_on_focus_loss=false
	config.calibration_override=Calibration.new()
	check(config.calibration_override.configure(60.0,Calibration.display_context(root)).is_empty(),"Synthetic display calibration")
	config.calibration_override.calibration_timestamp="SYNTHETIC TEST ONLY"
	var old_parent: Node=viewer.fish.get_parent()
	var old_transform: Transform3D=viewer.fish.transform
	viewer.animation_player.pause()
	var old_phase: float=viewer.animation_player.current_animation_position
	check((await viewer.start_stimulus_session(config)).is_empty(),"Start stimulus")
	var stimulus=viewer.stimulus;stimulus.sample_input=false;stimulus.set_physics_process(false)
	config=stimulus.config;config.calibration_override=stimulus.calibration
	check(stimulus.active and not viewer.get_node("UI").visible,"Presentation hides all editor UI")
	if DisplayServer.get_name()!="headless":check(Input.mouse_mode==Input.MOUSE_MODE_HIDDEN,"Hidden cursor")
	check(viewer.fish.get_parent()==stimulus.center,"Same fish instance reparented")
	check(stimulus.motion.position==Vector3.ZERO and stimulus.motion.velocity==Vector2.ZERO,"Neutral start")
	check(stimulus.camera.projection==Camera3D.PROJECTION_ORTHOGONAL,"Orthographic camera")
	var camera_transform: Transform3D=stimulus.camera.transform
	var camera_size: float=stimulus.camera.size
	check(viewer.fish.find_children("*","Skeleton3D",true,false)[0].get_bone_count()==15,"15 bones retained")
	check(photo.showing_generated and photo.generated!=null,"Individual generated texture active")
	for item in material_refs:check(item[0].get_active_material(item[1])==item[2],"Exact runtime material retained")
	await snapshot("stimulus_right")
	advance(.2,{"x":1});check(stimulus.motion.velocity.x>0 and stimulus.motion.velocity.x<config.stimulus_speed,"Acceleration")
	advance(2,{"x":1});check(is_equal_approx(stimulus.motion.velocity.x,config.stimulus_speed),"Cruise")
	check(stimulus.motion.animation_rate>config.idle_animation_speed,"Animation coupling")
	advance(.2);check(stimulus.motion.velocity.x>0 and stimulus.motion.velocity.x<config.stimulus_speed,"Deceleration")
	advance(2);check(stimulus.motion.velocity==Vector2.ZERO,"Smooth stop")
	check(is_equal_approx(stimulus.motion.animation_rate,config.idle_animation_speed),"Idle rest animation")
	var phase: float=viewer.animation_player.current_animation_position
	await wait(.2);check(viewer.animation_player.current_animation_position!=phase,"Swim_Test advances")
	viewer.reset_stimulus();advance(1,{"y":1});check(stimulus.motion.position.y>0 and stimulus.motion.position.z==0,"Vertical motion fixed depth")
	advance(1,{"y":-1});check(stimulus.motion.velocity.y<0,"Downward movement")
	viewer.reset_stimulus();advance(.1,{"facing":-1});check(stimulus.motion.yaw>0 and stimulus.motion.yaw<PI,"Smooth reversal")
	advance(3,{"facing":-1});check(is_equal_approx(stimulus.motion.yaw,PI),"Left lateral target")
	await snapshot("stimulus_left")
	advance(3,{"facing":1});check(is_zero_approx(stimulus.motion.yaw),"Right lateral target")
	advance(8,{"x":1,"y":1,"speed":1});check(stimulus.motion.velocity.length()<=config.max_speed+.000001,"Diagonal speed cap")
	check(is_equal_approx(stimulus.motion.stimulus_speed,config.max_speed),"Target speed cap")
	check(stimulus.motion.animation_rate>config.swim_animation_speed,"Fast animation")
	advance(8,{"speed":-1});check(is_equal_approx(stimulus.motion.stimulus_speed,config.min_speed),"Minimum target speed")
	var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_WHEEL_UP;mouse.pressed=true;root.push_input(mouse,true)
	var motion:=InputEventMouseMotion.new();motion.relative=Vector2(100,80);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	check(stimulus.camera.transform==camera_transform and stimulus.camera.size==camera_size,"No camera drift, mouse rotation or zoom")
	event("stimulus_reset");check(stimulus.motion.position==Vector3.ZERO and stimulus.motion.velocity==Vector2.ZERO,"F8 reset")
	stimulus.sample_input=true;Input.action_press("stimulus_left");advance(.4);Input.action_release("stimulus_left")
	check(stimulus.motion.position.x<0,"InputMap direction polling")
	var log_path: String=stimulus.last_log_path
	check(log_path.begins_with(Paths.data_dir().path_join("experiments")),"Portable experiment location")
	event("stimulus_exit");check(not stimulus.active,"Esc stops")
	check(viewer.fish.get_parent()==old_parent and viewer.fish.transform==old_transform,"Original hierarchy and transform restored")
	check(not viewer.animation_player.is_playing() and is_equal_approx(viewer.animation_player.current_animation_position,old_phase),"Viewer animation state restored")
	check(viewer.get_node("UI").visible,"Viewer UI restored")
	var lines:=FileAccess.get_file_as_string(log_path).strip_edges().split("\n")
	check(JSON.parse_string(lines[0]).event=="session_start","Log start")
	check(JSON.parse_string(lines[-1]).event=="session_stop","Log stop")
	var sample:=false;var reset:=false;var previous: float=-1
	for line in lines:
		var record: Dictionary=JSON.parse_string(line)
		check(record.elapsed_seconds>=previous,"Monotonic log time");previous=record.elapsed_seconds
		if record.event=="sample":sample=record.state.has("position") and record.state.has("speed") and record.state.has("animation_speed")
		if record.event=="reset":reset=true
	check(sample and reset,"Log samples and reset")
	check(FileAccess.get_sha256(manifest)==manifest_hash,"Project unchanged by experiment")
	photo.reset();check(photo.open_project(entries[0].id),"Project reopen before next trial")
	check(photo.analysis_count==count,"No automatic reanalysis")
	var first_id: String=photo.project_id
	photo.project_manager=Manager.new(ProjectSettings.globalize_path("res://.godot/stimulus_test_projects") if OS.has_feature("editor") else out.path_join("stimulus_test_projects"))
	check(photo.save_project("Stimuluswechsel",true),"Save second individual project")
	var second_id: String=photo.project_id
	check(second_id!=first_id and photo.open_project(second_id),"Switch project before stimulus")
	photo.show_original();check((await viewer.start_stimulus_session(config)).is_empty(),"Second trial with original coloring")
	var start_record: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(stimulus.last_log_path).split("\n")[0])
	check(start_record.details.project_id==second_id,"Log identifies switched project")
	check(not photo.showing_generated,"Changed coloring used in next trial")
	stimulus.set_physics_process(false);root.size+=Vector2i(20,0);await wait();stimulus._physics_process(.016)
	check(not stimulus.active,"Resize stops trial instead of changing projection")
	photo.show_generated()
	config.fullscreen=DisplayServer.get_name()!="headless"
	check((await viewer.start_stimulus_session(config)).is_empty(),"Fullscreen trial starts")
	if config.fullscreen:check(root.mode==Window.MODE_FULLSCREEN,"Fullscreen window mode")
	stimulus.set_physics_process(false);await wait(.2);await snapshot("stimulus_fullscreen")
	stimulus.config.stop_on_focus_loss=true;stimulus._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not stimulus.active,"Focus loss stops experiment")
	if DisplayServer.get_name()!="headless":check(root.mode==Window.MODE_WINDOWED,"Window mode restored")
	check(FileAccess.get_sha256(manifest)==manifest_hash,"No transient state persisted")
	await snapshot("stimulus_return_to_viewer")
	finish()
func finish() -> void:
	var report: Dictionary={"checks":checks,"errors":errors,"exported":not OS.has_feature("editor"),"renderer":DisplayServer.get_name(),"log_path":viewer.stimulus.last_log_path if viewer!=null and viewer.stimulus!=null else ""}
	var file:=FileAccess.open(out.path_join(report_filename),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));get_tree().quit(0 if errors.is_empty() else 1)
