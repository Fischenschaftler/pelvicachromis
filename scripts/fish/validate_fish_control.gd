extends "res://scripts/validate_fish_viewer.gd"
const Manager=preload("res://scripts/project/project_manager.gd")
var controller: Node3D
var importer: Control
var report: Dictionary={}
func _initialize() -> void:call_deferred("run_control")
func advance(seconds: float,forward: float=0.0,brake: float=0.0,turn: float=0.0,climb: float=0.0,boost: float=0.0) -> void:
	controller.set_movement_input(forward,brake,turn,climb,boost)
	for i in range(roundi(seconds*60)):
		controller.step_movement(1.0/60.0)
		viewer.chase.follow(1.0/60.0)
func snapshot(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://godot/diagnostics/"+name+".png")
func run_control() -> void:
	viewer=load("res://scenes/PhotoImport.tscn").instantiate();root.add_child(viewer);root.size=Vector2i(1400,1000)
	await create_timer(.6).timeout
	controller=viewer.fish_controller;controller.sample_input=false;controller.set_physics_process(false)
	importer=viewer.get_node("UI/ReferencePhoto")
	var original_transform: Transform3D=viewer.fish.transform
	var animation: Animation=viewer.animation_player.get_animation(viewer.swim_animation)
	var original_animation_hash:=hash(var_to_bytes(animation))
	var skeletons: Array=viewer.fish.find_children("*","Skeleton3D",true,false)
	check(skeletons.size()==1 and skeletons[0].get_bone_count()==15,"15 bones")
	var eye: MeshInstance3D=viewer.fish.find_children("Eye_Left","MeshInstance3D",true,false)[0]
	var tail: MeshInstance3D=viewer.fish.find_children("Caudal_Fin","MeshInstance3D",true,false)[0]
	check((eye.global_transform*eye.mesh.get_aabb().get_center()).x>(tail.global_transform*tail.mesh.get_aabb().get_center()).x,"GLB head +X")
	for action in ["fish_forward","fish_brake","fish_turn_left","fish_turn_right","fish_up","fish_down","fish_boost","fish_control_exit"]:check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(),"InputMap "+action)
	await click(viewer.control_button)
	check(viewer.control_mode and viewer.chase.camera.current and not importer.visible,"Enter mode")
	check(controller.position==Vector3.ZERO and controller.speed==0.0,"Initial neutral state")
	check(viewer.animation_player.is_playing() and viewer.animation_player.speed_scale>0.0,"Hover movement")
	await snapshot("fish_control_idle")
	var idle_rate: float=controller.animation_rate
	advance(.2,1.0)
	check(controller.speed>0 and controller.speed<controller.config.cruise_speed,"Smooth acceleration")
	var initial_speed: float=controller.speed
	advance(2.0,1.0)
	check(is_equal_approx(controller.speed,controller.config.cruise_speed),"Cruise speed")
	check(controller.position.x>0.0 and absf(controller.position.z)<.00001,"Forward local +X")
	check(controller.animation_rate>idle_rate,"Animation speed follows movement")
	check(absf(controller.animation_rate-controller.config.normal_animation_speed)<.05,"Normal animation rate")
	await snapshot("fish_control_forward")
	var coasting_speed: float=controller.speed
	advance(.2)
	check(controller.speed>0 and controller.speed<coasting_speed,"Coast smoothly")
	advance(.3,0.0,1.0)
	check(controller.speed<coasting_speed*.5,"Brake stronger than coast")
	advance(1.0,0.0,1.0);check(controller.speed==0,"Brake to rest")
	advance(.1,1.0,1.0);check(controller.speed==0,"Brake wins over forward")
	var phase: float=viewer.animation_player.current_animation_position
	await create_timer(.3).timeout
	check(viewer.animation_player.current_animation_position!=phase,"Animation never frozen at rest")
	viewer.reset_fish_control();advance(.15,1.0,0.0,1.0)
	check(controller.turn_speed>0 and controller.turn_speed<controller.config.max_turn_speed,"Turn acceleration")
	advance(1.3,1.0,0.0,1.0)
	check(controller.yaw>0 and controller.position.z<0,"Left turn")
	check(absf(controller.bank)<=controller.config.max_bank+.0001,"Subtle bank")
	await snapshot("fish_control_turn")
	var turn_speed: float=controller.turn_speed
	advance(.1,1.0)
	check(controller.turn_speed>0 and controller.turn_speed<turn_speed,"Turn coast")
	advance(1.0,1.0,0.0,-1.0)
	check(controller.turn_speed<0,"Right turn")
	viewer.reset_fish_control();advance(1.0,1.0,0.0,0.0,1.0)
	check(controller.position.y>0 and controller.vertical_speed>0 and controller.pitch>0,"Ascend")
	check(absf(controller.pitch)<=controller.config.max_pitch+.0001,"Pitch bounded")
	advance(1.5,1.0,0.0,0.0,-1.0)
	check(controller.vertical_speed<0 and controller.pitch<0,"Descend")
	viewer.reset_fish_control();advance(5.0,1.0,0.0,0.0,0.0,1.0)
	check(is_equal_approx(controller.speed,controller.config.fast_speed),"Boost")
	check(controller.animation_rate>controller.config.normal_animation_speed,"Fast animation")
	advance(5.0,1.0,0.0,0.0,0.0,1.0)
	check(controller.speed<=controller.config.fast_speed,"Speed cap")
	advance(1.0,1.0,0.0,0.0,1.0,1.0)
	check(controller.velocity.length()<=controller.config.fast_speed+.000001,"Combined boost/climb speed cap")
	var center: Vector3=controller.global_transform*viewer.chase.local_center
	check(viewer.chase.global_position.distance_to(center)<viewer.chase.distance+.02,"Camera follows translated fish")
	check(viewer.chase.camera.global_basis.z.normalized().dot((viewer.chase.global_position-viewer.chase.look_target).normalized())>.99,"Camera aims at fish")
	await snapshot("fish_control_chase_camera")
	var camera_center: Vector2=viewer.get_node("ViewerViewport").get_global_rect().get_center()
	var distance: float=viewer.chase.distance
	mouse(MOUSE_BUTTON_WHEEL_UP,true,camera_center)
	check(viewer.chase.distance<distance,"Chase zoom")
	mouse(MOUSE_BUTTON_LEFT,true,camera_center);move(camera_center+Vector2(70,25),Vector2(70,25));mouse(MOUSE_BUTTON_LEFT,false,camera_center+Vector2(70,25))
	check(absf(viewer.chase.yaw-controller.config.camera_default_yaw)>.1,"Chase orbit drag")
	for i in range(100):mouse(MOUSE_BUTTON_WHEEL_UP,true,camera_center)
	check(viewer.chase.distance>=viewer.chase.radius*controller.config.camera_min_radius_ratio,"Minimum camera distance")
	for i in range(100):mouse(MOUSE_BUTTON_WHEEL_DOWN,true,camera_center)
	check(viewer.chase.distance<=viewer.chase.radius*controller.config.camera_max_radius_ratio,"Maximum camera distance")
	mouse(MOUSE_BUTTON_LEFT,true,camera_center);move(camera_center+Vector2(0,5000),Vector2(0,5000));mouse(MOUSE_BUTTON_LEFT,false,camera_center)
	check(viewer.chase.pitch<=controller.config.camera_max_pitch,"Maximum camera pitch")
	mouse(MOUSE_BUTTON_LEFT,true,camera_center);move(camera_center-Vector2(0,5000),Vector2(0,-5000));mouse(MOUSE_BUTTON_LEFT,false,camera_center)
	check(viewer.chase.pitch>=controller.config.camera_min_pitch,"Minimum camera pitch")
	var position_before: Vector3=controller.position
	await click(viewer.reset_button)
	check(controller.position==position_before and viewer.chase.zoom_ratio==1.0,"Camera reset does not reset fish")
	viewer.reset_fish_control()
	check(controller.position==Vector3.ZERO and controller.rotation.is_equal_approx(Vector3.ZERO) and controller.speed==0 and controller.vertical_speed==0 and controller.turn_speed==0,"Full reset")
	controller.input_suspended=true;controller.sample_input=true
	Input.action_press("fish_forward");controller._physics_process(.1);Input.action_release("fish_forward")
	check(controller.speed==0,"Focus loss suppresses input")
	controller.sample_input=false
	# Poll the real Input Map as well as deterministic analogue values.
	controller.sample_input=true;controller.input_suspended=false;controller.set_physics_process(true)
	Input.action_press("fish_forward");await create_timer(.15).timeout;Input.action_release("fish_forward")
	check(controller.speed>0,"Action polling")
	controller.sample_input=false;controller.set_physics_process(false)
	viewer.animation_player.pause();viewer.end_fish_control()
	check(not viewer.control_mode and viewer.orbit.camera.current and importer.visible,"Exit mode")
	check(viewer.fish.transform==original_transform and controller.transform==controller.neutral_transform,"Imported transform preserved")
	check(viewer.animation_player.speed_scale==1.0,"Viewing animation speed restored")
	# Use two independently saved projects with different textures without changing UV/model.
	var photo:=Image.new();photo.load("res://blender/reference/pelvicachromis_taeniatus_male.jpg")
	var texture:=Image.create(2048,2048,false,Image.FORMAT_RGBA8);texture.fill(Color(.4,.6,.3))
	var manager:=Manager.new(preload("res://scripts/storage/portable_paths.gd").data_dir()+"/fish_control_tests/"+str(Time.get_ticks_usec()))
	importer.project_manager=manager;importer.project_browser.manager=manager
	importer.set_photo_image(photo,"temporary-source.jpg")
	importer.canvas.landmarks=PackedVector2Array([Vector2(736,296),Vector2(669,275)])
	importer.generated=ImageTexture.create_from_image(texture);importer.show_generated()
	check(importer.save_project("Steuerung A"),"Save project A")
	var first_id: String=importer.project_id
	texture.fill(Color(.6,.3,.4));importer.generated=ImageTexture.create_from_image(texture);importer.show_generated()
	check(importer.save_project("Steuerung B",true),"Save project B")
	var second_id: String=importer.project_id
	check(importer.open_project(first_id),"Open A")
	var generated: ImageTexture=importer.generated
	var count: int=importer.analysis_count
	viewer.begin_fish_control();advance(.5,1.0)
	check(importer.generated==generated and importer.showing_generated,"Individual texture retained")
	for node in importer.originals:
		for surface in range(node.mesh.get_surface_count()):check(node.get_active_material(surface).albedo_texture==generated,"Texture surface unchanged "+node.name)
	check(importer.open_project(second_id),"Project change while steering")
	check(importer.analysis_count==count and importer.generated!=null and importer.generated!=generated,"New project texture, no reanalysis")
	advance(.5,1.0)
	check(viewer.control_mode and viewer.animation_player.is_playing(),"New project steerable")
	viewer.end_fish_control();check(importer.showing_generated and importer.project_id==second_id,"Exit preserves new project")
	var manifest: Dictionary=manager.read_manifest(second_id).data
	check(not manifest.has("speed") and not manifest.has("control_mode") and not manifest.has("controller"),"Control state not persisted")
	viewer.animation_player.pause();viewer.begin_fish_control();check(viewer.animation_player.is_playing(),"Control resumes stopped animation")
	viewer.end_fish_control();check(not viewer.animation_player.is_playing(),"Previously paused viewing restored")
	viewer.animation_player.play(viewer.swim_animation);viewer.begin_fish_control()
	var exit_event:=InputEventAction.new();exit_event.action="fish_control_exit";exit_event.pressed=true;root.push_input(exit_event,true)
	check(not viewer.control_mode,"Escape action")
	check(hash(var_to_bytes(animation))==original_animation_hash,"Animation resource unchanged")
	for size in [Vector2i(600,900),Vector2i(480,360)]:
		root.size=size;viewer.begin_fish_control();await create_timer(.2).timeout
		check(root.get_visible_rect().encloses(viewer.get_node("ViewerViewport").get_global_rect()),"Control viewport fits window")
		check(root.get_visible_rect().encloses(viewer.control_button.get_global_rect()),"Control button fits")
		viewer.end_fish_control();await create_timer(.2).timeout
		check(importer.visible,"Photo UI restored after resize")
	report={"errors":errors,"local_forward":"+X","bones":15,"cruise_mps":controller.config.cruise_speed,"fast_mps":controller.config.fast_speed,"initial_acceleration_sample":initial_speed}
	FileAccess.open("res://godot/diagnostics/fish_control_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("FISH CONTROL: ",errors);quit(0 if errors.is_empty() else 1)
