extends "res://scripts/stimulus/validate_display_calibration.gd"
const SequenceData=preload("res://scripts/sequences/sequence_data.gd")
const SequenceStore=preload("res://scripts/sequences/sequence_store.gd")
const Runner=preload("res://scripts/sequences/sequence_runner.gd")
const Motion=preload("res://scripts/stimulus/stimulus_fish_controller.gd")
var reproduction: Dictionary={}
func _ready() -> void:
	super._ready();report_filename="sequence_validation.json";screenshot_prefix="sequence_"
func example_all() -> Dictionary:
	var data:=SequenceData.fresh("Alle Schritttypen")
	data.steps=[]
	for type in ["WAIT","MOVE","TURN","MOVE_TO","HOLD","RESET_POSITION","MOVE","WAIT"]:data.steps.append(SequenceData.step(type))
	var durations: Array=[.2,.7,1.7,2.0,.3,0.0,.4,.5]
	for i in range(data.steps.size()):data.steps[i].duration_s=durations[i]
	data.steps[3].target_position_cm=[-1,1];data.steps[3].target_speed_cm_s=4
	data.steps[5].orientation="RIGHT"
	data.steps[6].direction="UP";data.steps[6].target_speed_cm_s=2
	data.total_duration_s=SequenceData.total(data)
	return data
func simulate(data: Dictionary,partitions: Array) -> Dictionary:
	var body:=Motion.new();body.configure(Config.new(),null)
	var runner:=Runner.new();var events: Array=[]
	runner.configure(data,body,Rect2(-40,-25,80,50),false,func(name,extra):
		if name!="sample":events.append({"event":name,"time":runner.time_s,"state":runner.telemetry().duplicate(true),"details":extra}))
	runner.begin(0)
	var t:=0.0;var index:=0
	while not runner.finished:
		t+=partitions[index%partitions.size()];runner.advance_to(t);index+=1
	var result: Dictionary={"events":events,"position":runner.position_cm(),"telemetry":runner.telemetry(),"completed":runner.completed}
	runner.event_sink=Callable();body.free();return result
func run() -> void:
	var data:=example_all();var config:=Config.new();var area:=Rect2(-40,-25,80,50)
	check(SequenceData.validate(data,10).is_empty(),"All step types schema")
	check(absf(data.total_duration_s-5.8)<.000001,"Total duration")
	var store:=SequenceStore.new(ProjectSettings.globalize_path("res://.godot/sequence_tests") if OS.has_feature("editor") else Paths.logs_dir().path_join("sequence_tests"))
	check(store.ensure_examples().is_empty(),"Install portable examples")
	check(store.list_sequences().size()>=3,"Three examples")
	check(store.save_sequence(data).is_empty(),"Save sequence")
	var loaded:=store.load_sequence(data.sequence_id);check(not loaded.has("error"),"Load sequence")
	check(SequenceData.checksum(loaded.data)==SequenceData.checksum(data),"JSON roundtrip definition hash")
	var copy:=store.duplicate_sequence(data);check(copy.sequence_id!=data.sequence_id and copy.steps==data.steps,"Duplicate independently")
	check(store.save_sequence(copy).is_empty(),"Save copy")
	check(store.load_sequence("../escape").has("error"),"Reject unsafe filename")
	var bad:=data.duplicate(true);bad.steps[1].duration_s=-1;check(not SequenceData.validate(bad).is_empty(),"Reject negative duration")
	bad=data.duplicate(true);bad.steps[1].direction="BACK";check(not SequenceData.validate(bad).is_empty(),"Reject invalid direction")
	bad=data.duplicate(true);bad.steps[1].target_speed_cm_s=11;check(not SequenceData.validate(bad,10).is_empty(),"Speed limit validation")
	bad=data.duplicate(true);bad.steps[3].erase("target_position_cm");check(not SequenceData.validate(bad).is_empty(),"Missing MOVE_TO target")
	bad=data.duplicate(true);bad.steps[4].start_position_cm=[0,0];check(not SequenceData.validate(bad).is_empty(),"Reject implicit teleport")
	check(Runner.preflight(data,config,area).error.is_empty(),"Preflight all types")
	bad=data.duplicate(true);bad.steps[3].target_position_cm=[500,0];check(not Runner.preflight(bad,config,area).error.is_empty(),"Reject offscreen target")
	bad=data.duplicate(true);bad.steps[3].duration_s=.01;bad.total_duration_s=SequenceData.total(bad);check(not Runner.preflight(bad,config,area).error.is_empty(),"MOVE_TO must reach target in time")
	var fast: Dictionary=store.load_sequence("example_horizontal_fast").data
	check(not Runner.preflight(fast,config,Rect2(-20,-10,40,20)).error.is_empty(),"Fast example rejected on small monitor")
	check(Runner.preflight(fast,config,area).error.is_empty(),"Fast example on sufficient monitor")
	var a:=simulate(data,[1.0/30.0]);var b:=simulate(data,[1.0/144.0,.019,.006,.04]);var repeat:=simulate(data,[1.0/30.0])
	check(a.completed and b.completed,"Complete two varied-rate runs")
	check(a.events==b.events and a.events==repeat.events,"Identical step starts/ends and target trajectories")
	check(a.position.distance_to(b.position)<.000001 and a.position.distance_to(repeat.position)<.000001,"Identical final position")
	reproduction={"definition_sha256":SequenceData.checksum(data),"runs":3,"render_intervals_s":[[1.0/30.0],[1.0/144.0,.019,.006,.04],[1.0/30.0]],"final_position_delta_cm":a.position.distance_to(b.position),"step_time_delta_s":0.0 if a.events==b.events else -1.0,"integration_quantum_s":Runner.QUANTUM,"final_position_cm":[a.position.x,a.position.y]}
	FileAccess.open(out.path_join("sequence_reproducibility.json"),FileAccess.WRITE).store_string(JSON.stringify(reproduction,"\t"))
	var body:=Motion.new();body.configure(config,null);var runner:=Runner.new();var names: Array=[]
	runner.configure(data,body,area,true,func(name,_extra):names.append(name));runner.begin(0)
	var checksum: String=runner.definition_hash;data.steps[0].duration_s=99
	check(runner.definition.steps[0].duration_s==.2 and runner.definition_hash==checksum,"Frozen deep copy")
	runner.tick(.05,{"x":-1});check(runner.position_cm().x<0 and names.has("MANUAL_OVERRIDE"),"Allowed manual override")
	runner.toggle_pause(.06);var p:=runner.position_cm();var time: float=runner.time_s
	runner.tick(1.0,{"x":1});check(runner.position_cm()==p and runner.time_s==time and runner.telemetry().actual_speed_cm_s==0,"Pause freezes time/movement")
	runner.toggle_pause(1.06);runner.tick(1.11);check(runner.time_s>time and names.has("RESUMED"),"Resume time")
	runner.manual_reset();check(runner.position_cm()==Vector2.ZERO,"Logged manual reset")
	runner.abort("test");check(names.has("SESSION_ABORTED") and runner.finished,"Controlled abort")
	body.free()
	body=Motion.new();body.configure(config,null);runner=Runner.new();runner.configure(example_all(),body,area);runner.begin(0);runner.tick(.05,{"x":-1})
	check(runner.position_cm()==Vector2.ZERO and not runner.overriding,"Locked input ignored")
	runner.tick(1);check(runner.finished and not runner.completed,"Abort excessive real-time stall");body.free()
	if DisplayServer.get_name()=="headless":finish();return
	root.show();root.size=Vector2i(1400,1000)
	viewer=load("res://scenes/PhotoImport.tscn").instantiate();viewer.set_script(preload("res://scripts/sequences/sequence_test_viewer.gd"));root.add_child(viewer);await wait(.6)
	var photo=viewer.get_node("UI/ReferencePhoto")
	photo.project_manager=Manager.new(ProjectSettings.globalize_path("res://dist/PelvicachromisStudio/projects") if OS.has_feature("editor") else Paths.projects_dir())
	var projects: Array=photo.project_manager.list_projects();check(not projects.is_empty(),"Individual fish fixture")
	if projects.is_empty():finish();return
	check(photo.open_project(projects[0].id),"Open individual fish")
	var manifest: String=photo.project_manager.folder(photo.project_id).path_join("project.json");var project_hash:=FileAccess.get_sha256(manifest)
	check(InputMap.action_get_events("sequence_editor")[0].physical_keycode==KEY_F11,"F11 binding")
	event("sequence_editor");await wait();check(viewer.sequence_editor.visible,"F11 opens editor")
	var editor=viewer.sequence_editor;editor.store=store;editor.reload_list()
	editor.new_sequence();editor.name_input.text="UI Sequenz";editor.add_step();editor.move_step(-1);editor.delete_step();check(editor.definition.steps.size()==1,"Add/reorder/delete")
	editor.duration.value=.5;editor.save_sequence();check(editor.status.text.begins_with("Sequenz gespeichert"),"Editor save")
	var original_id: String=editor.definition.sequence_id;editor.duplicate_sequence();check(editor.definition.sequence_id!=original_id,"Editor duplicate")
	editor.save_sequence();editor.load_selected();check(not editor.definition.steps.is_empty(),"Editor load")
	await snapshot("stimulus_editor")
	editor.close()
	var short:=SequenceData.fresh("Realtime test");short.steps=[SequenceData.step("HOLD"),SequenceData.step("MOVE"),SequenceData.step("WAIT")]
	for item in short.steps:item.duration_s=.25
	short.total_duration_s=SequenceData.total(short)
	var materials: Array=[]
	for mesh in viewer.fish.find_children("*","MeshInstance3D",true,false):
		for i in range(mesh.mesh.get_surface_count()):materials.append([mesh,i,mesh.get_active_material(i)])
	var old_process: int=viewer.animation_player.callback_mode_process
	var request: Dictionary={"sequence":short,"trial_id":"AUTOMATED_TEST","animal_id":"SYNTHETIC","preview":false,"allow_manual_override":false}
	check((await viewer.launch_sequence(request)).is_empty(),"Start real sequence presentation")
	var stimulus=viewer.stimulus;check(stimulus.sequence_runner!=null and not stimulus.preview_label.visible,"Real stimulus has no preview UI")
	check(viewer.animation_player.callback_mode_process==AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,"Deterministic animation stepping")
	var camera: Transform3D=stimulus.camera.transform;var log_path: String=stimulus.last_log_path
	await snapshot("stimulus_real")
	var deadline:=Time.get_ticks_msec()+5000
	while stimulus.active and Time.get_ticks_msec()<deadline:await wait(.05)
	check(not stimulus.active and stimulus.sequence_runner.completed,"Real-time completion")
	check(stimulus.camera.transform==camera,"Fixed sequence camera")
	check(viewer.animation_player.callback_mode_process==old_process,"Restore viewer animation processing")
	var lines:=FileAccess.get_file_as_string(log_path).strip_edges().split("\n");var events: Array=[]
	for line in lines:
		var row: Dictionary=JSON.parse_string(line);events.append(row.event)
		for key in ["sequence_id","step_index","step_type","target_position_cm","actual_position_cm","target_speed_cm_s","actual_speed_cm_s","target_orientation","actual_orientation","animation_rate","active_fish","fish_display_length_cm","calibration_profile","control_state"]:check(row.has(key),"Log field "+key)
	var first: Dictionary=JSON.parse_string(lines[0]);check(first.details.sequence_sha256==SequenceData.checksum(first.details.sequence_definition),"Embedded immutable sequence hash")
	check(events[0]=="SESSION_STARTED" and events[-1]=="SESSION_COMPLETED" and events.count("STEP_STARTED")==3 and events.count("STEP_COMPLETED")==3,"Sequence lifecycle events")
	for item in materials:check(item[0].get_active_material(item[1])==item[2],"Individual materials retained")
	request.preview=true;request.trial_id="";check((await viewer.launch_sequence(request)).is_empty(),"Preview without trial ID")
	check(stimulus.preview_label.visible and stimulus.last_log_path.contains("/previews/"),"Clearly separate preview logging")
	event("sequence_pause");var paused_time: float=stimulus.sequence_runner.time_s;var paused_phase: float=viewer.animation_player.current_animation_position;await wait(.15)
	check(viewer.animation_player.current_animation_position==paused_phase,"Pause freezes animation phase")
	check(stimulus.sequence_runner.paused and stimulus.sequence_runner.time_s==paused_time,"Space pauses sequence")
	await snapshot("stimulus_preview")
	event("sequence_pause");await wait(.05);event("stimulus_exit")
	check(not stimulus.active,"Esc aborts preview without closing app")
	lines=FileAccess.get_file_as_string(stimulus.last_log_path).strip_edges().split("\n")
	check(JSON.parse_string(lines[-1]).event=="SESSION_ABORTED","Abort closes log")
	check(FileAccess.get_sha256(manifest)==project_hash,"Fish project untouched")
	viewer.queue_free();await get_tree().process_frame;viewer=null
	await super.run()
