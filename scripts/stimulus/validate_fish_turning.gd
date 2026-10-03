extends "res://scripts/experiment/validate_experimenter.gd"
var turn_reproduction: Dictionary={}
func _ready() -> void:
	super._ready();report_filename="turning_validation.json";screenshot_prefix="turning_"
func turning_sequence() -> Dictionary:
	var data:=SequenceData.fresh("Wendemanöver")
	data.steps=[SequenceData.step("MOVE"),SequenceData.step("MOVE"),SequenceData.step("TURN"),SequenceData.step("MOVE_TO"),SequenceData.step("HOLD")]
	data.steps[0].duration_s=2;data.steps[0].target_speed_cm_s=4
	data.steps[1].duration_s=4;data.steps[1].target_speed_cm_s=4;data.steps[1].direction="LEFT"
	data.steps[2].duration_s=2;data.steps[2].orientation="RIGHT"
	data.steps[3].duration_s=8;data.steps[3].target_position_cm=[5,1];data.steps[3].target_speed_cm_s=3
	data.steps[4].duration_s=4;data.total_duration_s=SequenceData.total(data);return data
func trace_turns(partitions: Array) -> Array:
	var body:=Motion.new();body.configure(Config.new(),null)
	var runner:=Runner.new();var trace: Array=[]
	runner.configure(turning_sequence(),body,Rect2(-100,-100,200,200),false,func(event,extra):trace.append({"event":event,"time":runner.time_s,"pose":body.bone_offsets(),"state":body.state(),"extra":extra}))
	runner.begin(0);var t:=0.0;var i:=0
	while not runner.finished:t+=partitions[i%partitions.size()];runner.advance_to(t);i+=1
	runner.event_sink=Callable();body.free();return trace
func run() -> void:
	var settings:=Config.new();var body:=Motion.new();body.configure(settings,null)
	var dt:=1.0/240.0
	for i in range(720):body.step(dt,{"x":1})
	check(body.turn_bend_amount==0,"Straight movement adds zero bend")
	check(body.radius_for_speed(6)>body.radius_for_speed(3),"Faster movement increases minimum radius")
	var previous:=0.0;var peak:=0.0;var max_jump:=0.0;var y_offset:=false;var radius_ok:=true
	for i in range(1200):
		body.step(dt,{"x":-1});peak=maxf(peak,absf(body.turn_bend_amount));max_jump=maxf(max_jump,absf(body.turn_bend_amount-previous));previous=body.turn_bend_amount
		if absf(body.position.y)>.005:y_offset=true
		var state: Dictionary=body.turn_state()
		if state.current_turn_radius_cm!=null and state.current_turn_radius_cm+0.00001<state.minimum_turn_radius_cm:radius_ok=false
	check(peak>.2 and peak<=settings.max_turn_bend,"Visible left bend within maximum")
	check(max_jump<.04,"Smooth build and no instantaneous bend jump")
	check(radius_ok and y_offset,"180 degree reversal follows radius-limited planar arc")
	check(absf(body.yaw-PI)<.01 and body.position.z==settings.plane_depth,"Controlled left orientation and constant depth")
	for i in range(1800):body.step(dt,{"x":-1})
	check(absf(body.turn_bend_amount)<.00001,"Smooth complete recovery after turn")
	var positive_bend:=false
	for i in range(1600):body.step(dt,{"x":1});positive_bend=positive_bend or body.turn_bend_amount>.2
	check(positive_bend and body.yaw<.01,"Mirrored right turn")
	var logs:=body.take_turn_events();check(logs.any(func(e):return e.event=="TURN_STARTED") and logs.any(func(e):return e.event=="TURN_COMPLETED"),"Turn begin/end events")
	body.reset_stimulus();body.step(dt,{"facing":-1});check(body.yaw>0 and body.yaw<PI and body.position==Vector3.ZERO,"Stationary TURN retains position")
	var copy:=Config.new();check(copy.apply(settings.snapshot()).is_empty(),"Turn config roundtrip")
	var invalid:=settings.snapshot();invalid.max_turn_bend=5;check(not copy.apply(invalid).is_empty(),"Reject implausible bend")
	invalid=settings.snapshot();invalid.body_bend_weights.Body_01=-1;check(not copy.apply(invalid).is_empty(),"Reject invalid body weight")
	body.free()
	var a:=trace_turns([1.0/30]);var b:=trace_turns([1.0/144,.019,.006,.04]);var c:=trace_turns([1.0/30])
	check(a==b and a==c,"Repeated offsets, yaw, radius, time and position identical")
	check(Runner.preflight(turning_sequence(),settings,Rect2(-100,-100,200,200)).error.is_empty(),"TURN/MOVE_TO with curved motion validated")
	turn_reproduction={"runs":3,"records_per_run":a.size(),"identical":a==b and a==c,"maximum_difference":0 if a==b and a==c else -1,"quantum_s":dt,"peak_bend_rad":peak,"max_step_bend_change_rad":max_jump,"last_state":a[-1].state}
	FileAccess.open(out.path_join("turning_reproducibility.json"),FileAccess.WRITE).store_string(JSON.stringify(turn_reproduction,"\t"))
	if DisplayServer.get_name()=="headless":finish();return
	root.show();root.size=Vector2i(1400,950)
	viewer=load("res://scenes/PhotoImport.tscn").instantiate();viewer.set_script(preload("res://scripts/sequences/sequence_test_viewer.gd"));root.add_child(viewer);await wait(.6)
	var rig: Skeleton3D=viewer.fish.find_children("*","Skeleton3D",true,false)[0]
	var original_modifiers: Array=rig.find_children("*","SkeletonModifier3D",true,false).map(func(node):return node.get_class())
	var rests: Array=[]
	for i in range(rig.get_bone_count()):rests.append(rig.get_bone_rest(i))
	var clip: Animation=viewer.animation_player.get_animation(viewer.swim_animation);var original_tracks:=clip.get_track_count()
	settings=viewer.test_config();settings.fullscreen=false
	check((await viewer.start_stimulus_session(settings)).is_empty(),"Manual stimulus with additive skeleton modifier starts")
	var stimulus=viewer.stimulus;stimulus.set_physics_process(false);stimulus.sample_input=false
	viewer.animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var model_scale: Vector3=stimulus.display_scale.scale
	check(is_instance_valid(stimulus.motion.turn_modifier) and rig.get_bone_count()==15,"Uses existing 15-bone skeleton")
	var cases: Dictionary={"straight":0.0,"left_light":-.25,"left_strong":-.85,"right_light":.25,"right_strong":.85}
	for name in cases:
		stimulus.motion.turn_bend_amount=cases[name];stimulus.motion.rotation.y=.65
		viewer.animation_player.seek(.4,true);await wait(.08)
		var modifier=stimulus.motion.turn_modifier
		check(modifier.last_base.size()==14,"Modifier evaluated after animation: "+name)
		var offsets: Dictionary=stimulus.motion.bone_offsets()
		for bone in modifier.indices:
			var expected: Quaternion=(modifier.last_base[bone]*Quaternion(modifier.local_axes[bone],offsets.get(bone,0.0))).normalized()
			check(absf(expected.dot(modifier.last_final[bone]))>.999999,"Additive quaternion "+name+" "+bone)
		var captured: Dictionary=modifier.last_final.duplicate(true);await wait(.1)
		check(captured==modifier.last_final,"No accumulated offsets: "+name)
		await snapshot("turning_"+name)
	stimulus.motion.reset_stimulus()
	for i in range(180):stimulus.motion.step(dt,{"facing":-1});viewer.animation_player.advance(dt)
	await wait(.05);var first: Quaternion=stimulus.motion.turn_modifier.last_base.Tail_02
	viewer.animation_player.advance(.25);await wait(.05)
	check(absf(first.dot(stimulus.motion.turn_modifier.last_base.Tail_02))<.99999,"Swim_Test wave continues underneath bend")
	await snapshot("turning_swim_and_bend")
	check(stimulus.display_scale.scale==model_scale,"Calibrated model scale unchanged")
	for i in range(rig.get_bone_count()):check(rig.get_bone_rest(i)==rests[i],"Rest unchanged "+rig.get_bone_name(i))
	check(clip.get_track_count()==original_tracks,"Imported animation tracks unchanged")
	viewer.stop_stimulus_session()
	# Godot recreates its implicit PhysicalBoneSimulator when reparenting the skeleton.
	var remaining: Array=rig.find_children("*","SkeletonModifier3D",true,false).map(func(node):return node.get_class())
	check(stimulus.motion.turn_modifier==null and remaining==original_modifiers,"Runtime pose layer removed, original rig helper classes retained")
	viewer.queue_free();await wait(.2)
	await super.run()
