extends "res://scripts/stimulus/validate_fish_turning.gd"
func _ready() -> void:
	super._ready();report_filename="motion_realism_validation.json";screenshot_prefix="motion_realism_"
func integrate(body: Node3D,seconds: float,command: Dictionary={}) -> void:
	for i in range(roundi(seconds*240)):body.step(1.0/240,command)
func realism_sequence() -> Dictionary:
	var data:=SequenceData.fresh("Pitch Boost Gill")
	data.steps=[SequenceData.step("MOVE"),SequenceData.step("TURN"),SequenceData.step("HOLD")]
	data.steps[0].merge({"duration_s":6.0,"target_pitch_deg":20.0,"pitch_transition_s":1.0,"pitch_hold_s":2.0,"pitch_return_s":1.0,"boost":true,"operculum_frequency_hz":1.3},true)
	data.steps[1].duration_s=3;data.steps[2].duration_s=2;data.total_duration_s=11;return data
func realism_trace(parts: Array) -> Array:
	var body:=Motion.new();body.configure(Config.new(),null)
	var runner:=Runner.new();var result: Array=[]
	runner.configure(realism_sequence(),body,Rect2(-100,-100,200,200),false,func(e,x):result.append([runner.time_s,e,x,body.state(),body.bone_offsets()]))
	runner.begin(0);var t:=0.0;var i:=0
	while not runner.finished:t+=parts[i%parts.size()];runner.advance_to(t);i+=1
	runner.event_sink=Callable();body.free();return result
func run() -> void:
	var settings:=Config.new();var body:=Motion.new();body.configure(settings,null)
	integrate(body,.1,{"pitch":1});check(body.realism.pitch>0 and body.realism.pitch<1,"Smooth pitch acceleration")
	integrate(body,3,{"pitch":1});check(is_equal_approx(body.realism.pitch,25) and body.position==Vector3.ZERO,"Pitch upper limit without translation")
	check((body.basis*Vector3.RIGHT).y>0,"Positive pitch lifts snout")
	body.yaw=PI;body.target_yaw=PI;integrate(body,.1,{"pitch":1});check((body.basis*Vector3.RIGHT).y>0,"Positive pitch lifts left-facing snout too")
	integrate(body,4);check(absf(body.realism.pitch)<.001,"Smooth neutral return")
	integrate(body,4,{"pitch":-1});check(is_equal_approx(body.realism.pitch,-25),"Lower pitch limit")
	settings.pitch_return_to_neutral=false;var held: float=body.realism.pitch;integrate(body,1);check(is_equal_approx(body.realism.pitch,held),"Configurable pitch hold")
	check(body.take_turn_events().any(func(e):return e.event=="PITCH_HOLD"),"Pitch target reached event")
	settings.pitch_return_to_neutral=true;body.reset_stimulus()
	integrate(body,2,{"x":1});var base_speed: float=body.velocity.length()/settings.units_per_cm;var base_rate: float=body.animation_rate
	body.step(1.0/240,{"x":1,"boost":true});check(body.velocity.length()/settings.units_per_cm<base_speed+.1,"Boost accelerates smoothly")
	integrate(body,5,{"x":1,"boost":true});check(is_equal_approx(body.velocity.length()/settings.units_per_cm,10),"4 cm/s times boost 2.5 = 10 cm/s")
	check(body.animation_rate>base_rate and body.animation_rate<=settings.fast_animation_speed,"Boost animation rate bounded")
	check(body.radius_for_speed(10)>body.radius_for_speed(4),"Boost increases turn radius")
	check(body.realism.frequency>settings.operculum_frequency_hz,"Speed-coupled breathing")
	integrate(body,8,{"x":1,"boost":true,"target_speed_cm_s":20});check(is_equal_approx(body.velocity.length()/settings.units_per_cm,20),"Absolute speed cap")
	body.step(1.0/240,{"x":1,"target_speed_cm_s":4});check(body.velocity.length()/settings.units_per_cm>19,"Boost release decelerates smoothly")
	integrate(body,5,{"x":1,"target_speed_cm_s":4});check(is_equal_approx(body.velocity.length()/settings.units_per_cm,4),"Normal speed restored")
	settings.operculum_speed_coupling=0;body.reset_stimulus();integrate(body,3,{"boost":true,"x":1})
	check(is_equal_approx(body.realism.frequency,1) and minf(body.realism.phase,1.0-body.realism.phase)<.00001,"Constant deterministic breathing frequency and phase")
	check(body.realism.breath(0)==0 and body.realism.breath(.5)==1 and body.realism.breath(.98)==0,"Smooth breath open/hold/close curve")
	check(settings.apply(settings.snapshot()).is_empty(),"New configuration roundtrip")
	var bad:=Config.new();check(not bad.apply({"operculum_amplitude":.1}).is_empty(),"Unsafe amplitude rejected")
	check(SequenceData.validate(realism_sequence()).is_empty(),"Optional sequence fields accepted")
	var timed:=Motion.new();timed.configure(Config.new(),null);var runner:=Runner.new();runner.configure(realism_sequence(),timed,Rect2(-100,-100,200,200));runner.begin(0)
	runner.advance_to(.5);check(absf(timed.realism.pitch-10)<.0001,"Timed pitch midpoint")
	runner.advance_to(2);check(absf(timed.realism.pitch-20)<.0001,"Timed pitch hold")
	runner.advance_to(4.1);check(absf(timed.realism.pitch)<.0001,"Timed return neutral")
	timed.free()
	var arrival:=SequenceData.fresh("Boost arrival");arrival.steps=[SequenceData.step("MOVE_TO")];arrival.steps[0].duration_s=8;arrival.steps[0].target_position_cm=[10,0];arrival.steps[0].boost=true;arrival.total_duration_s=8
	check(Runner.preflight(arrival,settings,Rect2(-100,-100,200,200)).error.is_empty(),"Boost MOVE_TO brakes before arrival")
	var invalid:=realism_sequence();invalid.steps[0].pitch_return_s=20;check(not SequenceData.validate(invalid).is_empty(),"Incomplete pitch cycle rejected")
	invalid=realism_sequence();invalid.steps[0].target_pitch_deg=30;check(not Runner.preflight(invalid,settings,Rect2(-100,-100,200,200)).error.is_empty(),"Configured sequence pitch bounds enforced")
	body.free()
	var a:=realism_trace([1.0/30]);var b:=realism_trace([.006,.04,1.0/144]);var c:=realism_trace([1.0/30])
	check(a==b and a==c,"Pitch/breath/boost/turn deterministic across frame partitions")
	for event_name in ["PITCH_TRANSITION","PITCH_TARGET_REACHED","PITCH_HOLD","PITCH_RETURNING","PITCH_NEUTRAL"]:
		check(a.any(func(row):return row[1]==event_name),"Sequence event "+event_name)
	FileAccess.open(out.path_join("motion_realism_reproducibility.json"),FileAccess.WRITE).store_string(JSON.stringify({"runs":3,"records":a.size(),"identical":a==b and a==c},"\t"))
	if DisplayServer.get_name()=="headless":await super.run();return
	root.show();root.size=Vector2i(1400,950)
	viewer=load("res://scenes/PhotoImport.tscn").instantiate();viewer.set_script(preload("res://scripts/sequences/sequence_test_viewer.gd"));root.add_child(viewer);await wait(.6)
	var mesh_node: MeshInstance3D=viewer.fish.find_children("Fish_Body","MeshInstance3D",true,false)[0]
	var original: Mesh=mesh_node.mesh;var skin: Skin=mesh_node.skin
	settings=viewer.test_config();settings.fullscreen=false
	check((await viewer.start_stimulus_session(settings)).is_empty(),"Realism runtime attaches")
	var stimulus=viewer.stimulus;stimulus.set_physics_process(false);stimulus.sample_input=false
	check(mesh_node.mesh!=original and mesh_node.mesh.get_blend_shape_count()==2,"Private left/right gill blendshapes")
	check(mesh_node.skin==skin and stimulus.motion.gills.affected_vertices>20,"Existing skin and sufficient local geometry")
	for surface in range(original.get_surface_count()):
		var old:=original.surface_get_arrays(surface);var current:=mesh_node.mesh.surface_get_arrays(surface)
		for slot in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_BONES,Mesh.ARRAY_WEIGHTS,Mesh.ARRAY_INDEX]:check(old[slot]==current[slot],"Base arrays unchanged "+str(slot))
		for shape in mesh_node.mesh.surface_get_blend_shape_arrays(surface):
			var vertices: PackedVector3Array=shape[Mesh.ARRAY_VERTEX];var base: PackedVector3Array=old[Mesh.ARRAY_VERTEX]
			var safe:=true
			for i in range(base.size()):
				if vertices[i].x!=base[i].x or vertices[i].y!=base[i].y or absf(vertices[i].z-base[i].z)>.000701:safe=false
			check(safe,"Gill displacement only lateral and bounded")
	for name in ["neutral","pitch_up","pitch_down","gills_closed","gills_open","normal_speed","boost_speed","boost_turn","boost_pitch"]:
		stimulus.motion.reset_stimulus()
		var original_camera_size: float=stimulus.camera.size
		var cmd: Dictionary={}
		if name=="pitch_up":cmd.pitch=1
		if name=="pitch_down":cmd.pitch=-1
		if name.begins_with("boost") or name=="normal_speed":cmd={"x":1,"boost":name.begins_with("boost")}
		if name=="boost_pitch":cmd.pitch=1
		integrate(stimulus.motion,3,cmd)
		if name=="boost_turn":integrate(stimulus.motion,.8,{"x":-1,"boost":true,"pitch":1})
		stimulus.motion.position=Vector3.ZERO # diagnostic framing only, not production movement
		if name.begins_with("gills"):
			stimulus.camera.size=original_camera_size*.35
			stimulus.motion.basis=Basis(Vector3.UP,.7);stimulus.motion.gills.update(1 if name=="gills_open" else 0,settings.operculum_amplitude)
		await wait(.12);await snapshot("stimulus_"+name)
		stimulus.camera.size=original_camera_size
	check(InputMap.action_get_events("stimulus_pitch_up")[0].physical_keycode==KEY_PAGEUP,"Conflict-free pitch binding")
	Input.action_press("stimulus_boost");Input.action_press("stimulus_pitch_up")
	check(stimulus.command_from_input().boost and stimulus.command_from_input().pitch==1,"Manual input reads boost and pitch")
	Input.action_release("stimulus_boost");Input.action_release("stimulus_pitch_up")
	stimulus.stop_stimulus_session("realism_test");check(mesh_node.mesh==original and mesh_node.skin==skin,"Imported body restored exactly on exit")
	viewer.queue_free();await wait(.3)
	await super.run()
