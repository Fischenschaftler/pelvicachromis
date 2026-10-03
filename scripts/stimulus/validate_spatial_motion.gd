extends "res://scripts/stimulus/validate_motion_realism.gd"
var spatial_trace_report: Dictionary={}
func _ready() -> void:
	super._ready();report_filename="spatial_motion_validation.json";screenshot_prefix="spatial_"
func orientation_sequence() -> Dictionary:
	var data:=SequenceData.fresh("Orientierung / Diagnose, kein Standardversuch")
	data.steps=[]
	for angle in [0.0,45.0,90.0,135.0,180.0,0.0]:
		var item:=SequenceData.step("HOLD");item.duration_s=4.0
		item.merge({"target_yaw_deg":angle,"yaw_transition_duration_s":2.0,"yaw_hold_duration_s":2.0,"target_pitch_deg":15.0 if angle==90 else -10.0,"pitch_transition_duration_s":1.0,"pitch_hold_duration_s":2.0,"pitch_return_duration_s":1.0})
		data.steps.append(item)
	data.total_duration_s=SequenceData.total(data);return data
func spatial_trace(parts: Array) -> Array:
	var body:=Motion.new();body.configure(Config.new(),null)
	var runner:=Runner.new();var result: Array=[]
	runner.configure(orientation_sequence(),body,Rect2(-100,-100,200,200),false,func(e,x):result.append([runner.time_s,e,x,body.state(),body.bone_offsets()]))
	runner.begin(0);var t:=0.0;var i:=0
	while not runner.finished:t+=parts[i%parts.size()];runner.advance_to(t);i+=1
	runner.event_sink=Callable();body.free();return result
func run() -> void:
	var settings:=Config.new();var body:=Motion.new();body.configure(settings,null)
	body.step(1.0/240,{"yaw":1});check(body.orientation.angle>0 and body.orientation.angle<.01,"Smooth yaw acceleration")
	integrate(body,2,{"yaw":1});check(body.orientation.angle>45,"Manual yaw toward front")
	var start: float=body.orientation.angle;integrate(body,1);check(body.orientation.angle>=start and body.orientation.velocity==0,"Yaw release brakes and holds")
	integrate(body,4,{"yaw":-1});check(body.orientation.angle<0,"Reverse yaw control")
	check(body.position==Vector3.ZERO,"Pure yaw never translates")
	for angle in [0.0,45.0,90.0,135.0,180.0,360.0]:
		body.step(1.0/240,{"sequence_yaw_deg":angle,"target_yaw_deg":angle,"yaw_transition_state":"HOLD","pitch":1})
		check(absf(body.orientation.angle-angle)<.00001,"Yaw range "+str(angle))
		check(absf(body.basis.determinant()-1)<.00001,"Orientation does not rescale")
		if angle==90:check((body.basis*Vector3.RIGHT).z>.99,"90 degrees points head toward camera")
	check(body.realism.pitch>0,"Yaw preserves concurrent pitch")
	settings.operculum_open_ratio=.3;settings.operculum_close_ratio=.5
	check(body.realism.breath(.3,.3,.5)==1 and body.realism.breath(.95,.3,.5)==0,"Independent opening and closing ratios")
	check(settings.apply(settings.snapshot()).is_empty(),"Extended configuration valid")
	var bad:=Config.new();check(not bad.apply({"operculum_open_ratio":.8,"operculum_close_ratio":.5}).is_empty(),"Overlapping breathing phases rejected")
	body.reset_stimulus();integrate(body,1)
	check(body.fins.left>0 and body.fins.right>0,"Hover pectorals active symmetrically")
	check(absf(body.fins.left-body.fins.right)<.00001,"Hover fin symmetry")
	check(absf(body.fins.passive)>0 and absf(body.fins.passive)<settings.passive_fin_amplitude,"Passive fins subtle")
	integrate(body,3,{"x":1});var cruise: float=body.fins.left
	integrate(body,.4,{});check(body.motion_state.braking_amount>0 and body.fins.left>cruise,"Braking opens both pectorals smoothly")
	integrate(body,2,{"x":1});integrate(body,.5,{"x":-1})
	check(absf(body.fins.left-body.fins.right)>.01,"Turn fins asymmetric")
	for key in ["speed_cm_s","target_speed_cm_s","acceleration_cm_s2","turn_rate","target_turn_rate","pitch_deg","target_pitch_deg","yaw_deg","target_yaw_deg","boost_active","braking_amount","operculum_phase","operculum_open_amount"]:check(body.motion_state.has(key),"Central state "+key)
	body.free()
	check(SequenceData.validate(orientation_sequence()).is_empty(),"Yaw and long pitch field names accepted")
	var a:=spatial_trace([1.0/30]);var b:=spatial_trace([.006,.04,1.0/144]);var c:=spatial_trace([1.0/30])
	check(a==b and a==c,"All orientation, gill and fin states reproduce exactly")
	check(a.any(func(row):return row[1]=="YAW_TARGET_REACHED"),"Yaw target event logged")
	spatial_trace_report={"runs":3,"records":a.size(),"identical":a==b and a==c};FileAccess.open(out.path_join("spatial_reproducibility.json"),FileAccess.WRITE).store_string(JSON.stringify(spatial_trace_report,"\t"))
	if DisplayServer.get_name()=="headless":await super.run();return
	root.show();root.size=Vector2i(1200,800)
	viewer=load("res://scenes/PhotoImport.tscn").instantiate();viewer.set_script(preload("res://scripts/sequences/sequence_test_viewer.gd"));root.add_child(viewer);await wait(.6)
	var photo=viewer.get_node("UI/ReferencePhoto")
	photo.project_manager=Manager.new(ProjectSettings.globalize_path("res://dist/PelvicachromisStudio/projects") if OS.has_feature("editor") else Paths.projects_dir())
	var entries: Array=photo.project_manager.list_projects();check(not entries.is_empty(),"Generated photo fixture exists")
	if entries.is_empty():finish();return
	check(photo.open_project(entries[0].id),"Generated photo fixture loaded");photo.show_generated()
	check(photo.generated!=null,"Generated texture loaded")
	settings=viewer.test_config();settings.fullscreen=false
	check((await viewer.start_stimulus_session(settings)).is_empty(),"Spatial motion session starts")
	var stimulus=viewer.stimulus;stimulus.set_physics_process(false);stimulus.sample_input=false
	viewer.animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	check(stimulus.get_node("Presentation/Viewport/World/Environment").environment.ambient_light_source==Environment.AMBIENT_SOURCE_COLOR,"Neutral ambient light, no missing sky")
	var camera_transform: Transform3D=stimulus.camera.transform;var model_scale: Vector3=stimulus.display_scale.scale
	# Development zoom only. The production camera/scale remain unchanged.
	stimulus.camera.size*=.4
	var fish_body: MeshInstance3D=viewer.fish.find_children("Fish_Body","MeshInstance3D",true,false)[0]
	check(fish_body.get_active_material(0).albedo_texture==photo.generated,"Generated atlas survives runtime mesh replacement")
	check(fish_body.get_active_material(0).transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"Body opaque at all yaw angles")
	check(stimulus.motion.gills.interior.nodes.size()==2,"Two gill interior surfaces")
	for node in stimulus.motion.gills.interior.nodes:
		check(node.skin==fish_body.skin and node.get_node(node.skeleton)==fish_body.get_node(fish_body.skeleton),"Gill shares exact skin and skeleton")
		check(node.mesh.blend_shape_mode==Mesh.BLEND_SHAPE_MODE_NORMALIZED,"Gill shape absolute positions, no double translation")
	for angle in [0,45,90,135,180]:
		for pitch in ([0,15,-15] if angle==90 else [0]):
			stimulus.motion.step(1.0/240,{"sequence_yaw_deg":angle,"target_yaw_deg":angle,"yaw_transition_state":"HOLD","sequence_pitch_deg":pitch,"target_pitch_deg":pitch,"pitch_transition_state":"HOLD"})
			viewer.animation_player.seek(.4,true);await wait(.08)
			await snapshot("stimulus_yaw_%d_pitch_%d" % [angle,pitch])
			check(stimulus.motion.position==Vector3.ZERO and stimulus.camera.transform==camera_transform and stimulus.display_scale.scale==model_scale,"Position camera and scale unchanged "+str(angle))
	for amount in [0.0,.5,1.0]:
		stimulus.motion.step(1.0/240,{"sequence_yaw_deg":45,"target_yaw_deg":45,"yaw_transition_state":"HOLD"})
		stimulus.motion.gills.update(amount,settings.operculum_amplitude);await wait(.05);await snapshot("stimulus_gill_"+str(roundi(amount*100)))
		for node in stimulus.motion.gills.interior.nodes:check(node.visible==(amount>0),"Gill visible only when open")
	check(InputMap.action_get_events("stimulus_yaw_left")[0].physical_keycode==KEY_HOME and InputMap.action_get_events("stimulus_yaw_right")[0].physical_keycode==KEY_END,"Independent yaw bindings")
	if OS.get_cmdline_user_args().has("--spatial-video"):await record_diagnostic(stimulus)
	stimulus.stop_stimulus_session("spatial_validation")
	check(viewer.fish.find_children("Gill_Interior*","MeshInstance3D",true,false).is_empty(),"Temporary interiors removed")
	viewer.queue_free();await wait(.2)
	await super.run()
func record_diagnostic(stimulus: Control) -> void:
	var frames:=ProjectSettings.globalize_path("res://.godot/spatial_frames");DirAccess.make_dir_recursive_absolute(frames)
	var label:=Label.new();label.position=Vector2(20,20);label.add_theme_font_size_override("font_size",22);stimulus.add_child(label)
	var stages: Array=[ ["Schweben",5,{}], ["Normaler Swim",3,{"x":1}], ["Beschleunigung / Boost",3,{"x":1,"boost":true}], ["Bremsen",3,{}], ["Linkskurve",3,{"x":-1}], ["Rechtskurve",3,{"x":1}], ["Pitch oben",3,{"pitch":1}], ["Pitch unten",4,{"pitch":-1}], ["Yaw 45 Grad",3,{"target_yaw_deg":45}], ["Frontansicht",3,{"target_yaw_deg":90}], ["Gegenseite",3,{"target_yaw_deg":180}], ["Boost plus Kurve und Pitch",3,{"x":-1,"boost":true,"pitch":1}], ["Neutrale Seitenansicht",4,{"target_yaw_deg":0}] ]
	var index:=0;stimulus.motion.reset_stimulus()
	for stage in stages:
		var yaw_start: float=stimulus.motion.orientation.angle
		for frame in range(int(stage[1])*24):
			for subframe in range(10):
				var command: Dictionary=stage[2].duplicate()
				if command.has("target_yaw_deg"):
					var t:=float(frame*10+subframe+1)/240.0
					command.sequence_yaw_deg=lerpf(yaw_start,command.target_yaw_deg,stimulus.motion.realism.smooth(t/2.0));command.yaw_transition_state="TRANSITION" if t<2 else "HOLD"
				stimulus.motion.step(1.0/240,command);viewer.animation_player.advance(1.0/240)
			stimulus.motion.position=Vector3.ZERO # Pose diagnostic, deliberately centered; not a scientific trial.
			label.text="VISUELLE DIAGNOSE · zentrierte Pose\n%s · %.1f cm/s · Pitch %.1f° · Yaw %.1f°" % [stage[0],stimulus.motion.motion_state.speed_cm_s,stimulus.motion.realism.pitch,stimulus.motion.orientation.angle]
			await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image();image.save_png(frames.path_join("frame_%05d.png" % index));index+=1
			if frame==int(stage[1])*12:image.save_png(out.path_join("spatial_stage_%02d.png" % stages.find(stage)))
	label.queue_free()
	FileAccess.open(out.path_join("spatial_video.json"),FileAccess.WRITE).store_string(JSON.stringify({"fps":24,"frames":index,"stages":stages,"pose_only_centered":true},"\t"))
