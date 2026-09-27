extends "res://scripts/validate_polygon_mask.gd"
var material_ids := {}
var mesh_ids := {}
var surface_hashes := {}

func snap(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	viewer.get_node("ViewerViewport/Viewport").get_texture().get_image().save_png("res://godot/diagnostics/body_%s.png" % name)

func run() -> void:
	viewer=load("res://scenes/Main.tscn").instantiate()
	root.add_child(viewer)
	root.size=Vector2i(1600,1100)
	await settle()
	photo=viewer.get_node("UI/ReferencePhoto")
	var transfer: Control=photo.texture_transfer
	for node in viewer.fish.find_children("*","MeshInstance3D",true,false):
		mesh_ids[node.name]=node.mesh.get_instance_id()
		for i in range(node.mesh.get_surface_count()):
			var key: String=String(node.name)+str(i)
			material_ids[key]=node.get_active_material(i).get_instance_id()
			surface_hashes[key]=hash(node.mesh.surface_get_arrays(i))
	var folder:=ProjectSettings.globalize_path("res://.godot/photo_import_fixtures/")
	check(photo.load_photo(folder+"Großes Fischfoto.jpg"),"JPG load failed")
	await settle()
	await click(photo.mark_button)
	var contour: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://godot/diagnostics/mask_contour.json"))
	for pair in contour.points: await point_click(Vector2(pair[0],pair[1]))
	await click(photo.close_button)
	await wait_mask()
	check(photo.mask_image!=null,"Polygon mask failed")
	var panel: Control=photo.landmarks
	await click(panel.start_button)
	var input: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://godot/diagnostics/landmark_large_right.json"))
	for key in ["snout","eye","tail_upper","tail_lower","body_upper","body_lower"]:
		photo.photo_scroll.ensure_control_visible(panel.canvas)
		await settle()
		var pair: Array=input.landmarks_original_px[key]
		var p: Vector2=panel.canvas.global_position+panel.canvas.to_display(Vector2(pair[0],pair[1]))
		move(p,Vector2.ZERO);mouse(MOUSE_BUTTON_LEFT,true,p);mouse(MOUSE_BUTTON_LEFT,false,p)
		await settle()
	await click(panel.confirm_button)
	var deadline:=Time.get_ticks_msec()+150000
	while panel.worker!=null and Time.get_ticks_msec()<deadline: await create_timer(0.05).timeout
	check(not panel.current_normalized_path.is_empty(),"Normalization failed: "+panel.status.text)
	await settle()
	await click(transfer.transfer_button)
	check(transfer.worker!=null,"Projection did not start: "+transfer.status.text)
	# Viewer remains interactive during background computation.
	var center: Vector2=viewer.get_node("ViewerViewport").get_global_rect().get_center()
	mouse(MOUSE_BUTTON_LEFT,true,center);move(center+Vector2(20,10),Vector2(20,10));mouse(MOUSE_BUTTON_LEFT,false,center)
	check(absf(viewer.orbit.yaw)>0.01,"Orbit blocked during projection")
	await click(viewer.reset_button)
	deadline=Time.get_ticks_msec()+300000
	while transfer.worker!=null and Time.get_ticks_msec()<deadline: await create_timer(0.1).timeout
	check(not transfer.current_generated_path.is_empty(),"Projection failed: "+transfer.status.text)
	if transfer.current_generated_path.is_empty():
		print(errors)
		quit(1)
		return
	check(transfer.showing_generated,"Generated texture not automatically applied")
	check(transfer.last_stats.max_anchor_error_px<0.05,"Landmarks not registered exactly")
	for node in viewer.fish.find_children("*","MeshInstance3D",true,false):
		check(node.mesh.get_instance_id()==mesh_ids[node.name],"Mesh replaced")
		for i in range(node.mesh.get_surface_count()):
			var key: String=String(node.name)+str(i)
			check(hash(node.mesh.surface_get_arrays(i))==surface_hashes[key],"Mesh arrays changed")
			if node.name!="Fish_Body":check(node.get_active_material(i).get_instance_id()==material_ids[key],"Non-body material changed: "+key)
	for node in viewer.fish.find_children("*","Skeleton3D",true,false):check(node.get_bone_count()==15,"Bone count changed")
	check(viewer.animation_player.is_playing(),"Swim_Test stopped")
	await create_timer(2.15).timeout
	check(viewer.animation_player.is_playing() and viewer.animation_player.current_animation_position<2.0,"Swim_Test no longer loops")
	viewer.animation_player.pause()
	viewer.animation_player.seek(0.5,true)
	var fins: Control=photo.fin_transfer
	await settle()
	await click(fins.start_button)
	await RenderingServer.frame_post_draw
	var source_polygons: Dictionary={
		"Caudal_Fin":[[215,369],[116,361],[66,393],[82,469],[142,531],[230,440],[243,436]],
		"Dorsal_Fin":[[550,240],[450,222],[340,246],[270,278],[154,283],[225,350],[240,355],[300,339],[400,289],[480,259]],
		"Anal_Fin":[[254,436],[240,491],[195,571],[330,510],[405,449],[416,437],[355,438]]}
	var data: Dictionary=panel.landmark_data
	var tail:=Vector2(data.tail_midpoint_px[0],data.tail_midpoint_px[1])
	var u:=Vector2(data.basis_u[0],data.basis_u[1]);var v:=Vector2(data.basis_v[0],data.basis_v[1])
	var offset:=Vector2(data.offset_px[0],data.offset_px[1])
	for name in fins.NAMES:
		var points:=PackedVector2Array()
		for pair in source_polygons[name]:
			var original:=Vector2(500+pair[0]*3.75,pair[1]*3.75)
			points.append(Vector2((original-tail).dot(u),(original-tail).dot(v))*data.scale+offset)
		for i in range(points.size()):
			await fin_click(points[i])
			if name=="Caudal_Fin" and i==1:
				await click(fins.close_button)
				check(fins.masks.is_empty(),"Incomplete fin accepted")
				root.size=Vector2i(600,900);await settle()
				if fins.canvas.points.is_empty():
					quit(1);return
				check(fins.canvas.points[0].distance_to(points[0])<.03,"Fin coordinates changed with resize")
		await click(fins.close_button)
		check(fins.masks.has(name),"Fin mask missing: "+name+" "+fins.status.text)
		root.size=Vector2i(1600,1100);await settle()
		if name=="Caudal_Fin":
			fins.select_fin(0);await settle();await click(fins.reset_button)
			check(not fins.masks.has(name),"Individual fin reset failed")
			points.reverse()
			for point in points:await fin_click(point)
			await click(fins.close_button)
	check(fins.masks.size()==3,"Three separate masks not available")
	await click(fins.generate_button)
	deadline=Time.get_ticks_msec()+300000
	while fins.worker!=null and Time.get_ticks_msec()<deadline:await create_timer(.1).timeout
	check(not fins.current_path.is_empty(),"Fin projection failed: "+fins.status.text)
	if fins.current_path.is_empty():
		print(errors);quit(1);return
	check(transfer.combined_fins and transfer.showing_generated,"Combined texture not displayed")
	for node in viewer.fish.find_children("*","MeshInstance3D",true,false):
		check(node.mesh.get_instance_id()==mesh_ids[node.name],"Mesh replaced by fin transfer")
		for i in range(node.mesh.get_surface_count()):
			var key: String=String(node.name)+str(i)
			check(hash(node.mesh.surface_get_arrays(i))==surface_hashes[key],"Mesh arrays changed by fins")
			if node.name not in ["Fish_Body","Caudal_Fin","Dorsal_Fin","Anal_Fin"]:check(node.get_active_material(i).get_instance_id()==material_ids[key],"Protected material changed: "+key)
	for mode in ["original","generated"]:
		await click(transfer.original_button if mode=="original" else transfer.generated_button)
		if mode=="original":
			for node in viewer.fish.find_children("*","MeshInstance3D",true,false):
				for i in range(node.mesh.get_surface_count()):check(node.get_active_material(i).get_instance_id()==material_ids[String(node.name)+str(i)],"Original material not restored")
		viewer.orbit.reset_view();await fin_snap(mode+"_side")
		viewer.orbit.yaw=.55;viewer.orbit.pitch=-.14;viewer.orbit._update_camera()
		await fin_snap(mode+"_oblique")
	for dimensions in [Vector2i(600,900),Vector2i(480,360)]:
		root.size=dimensions;await settle()
		check(root.get_visible_rect().encloses(photo.panel.get_global_rect()),"Fin UI outside window")
		await click(transfer.original_button);await click(transfer.generated_button)
		await click(viewer.reset_button)
		check(viewer.orbit.yaw==0.0,"Reset failed with combined texture")
		center=viewer.get_node("ViewerViewport").get_global_rect().get_center()
		var before: float=viewer.orbit.distance
		mouse(MOUSE_BUTTON_WHEEL_UP,true,center);check(viewer.orbit.distance<before,"Zoom failed")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://godot/diagnostics/fin_ui_%dx%d.png" % [dimensions.x,dimensions.y])
	await click(viewer.animation_button)
	await create_timer(2.2).timeout
	check(viewer.animation_player.is_playing() and viewer.animation_player.current_animation_position<2,"Swim loop failed with combined texture")
	var record: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(fins.metadata_path))
	record["coverage_path"]=fins.coverage_path
	# A new reference invalidates an in-flight bake and its editable masks.
	var last_path: String=fins.current_path
	fins.generate()
	panel.invalidate_result()
	deadline=Time.get_ticks_msec()+300000
	while fins.worker!=null and Time.get_ticks_msec()<deadline:await create_timer(.1).timeout
	check(fins.current_path.is_empty() and fins.masks.is_empty(),"Old fin masks/result survived reference change")
	check(transfer.current_generated_path==last_path,"Stale bake replaced last combined texture")
	photo.remove_photo()
	check(not transfer.showing_generated,"Photo removal did not restore original")
	record["stale_result_discarded"]=true
	record["errors"]=errors
	FileAccess.open("res://godot/diagnostics/fin_transfer_validation.json",FileAccess.WRITE).store_string(JSON.stringify(record,"\t"))
	print("Fin transfer tests: ",errors," stats: ",record.stats)
	quit(0 if errors.is_empty() else 1)

func fin_click(point: Vector2) -> void:
	photo.photo_scroll.ensure_control_visible(photo.fin_transfer.canvas)
	await settle()
	var p: Vector2=photo.fin_transfer.canvas.global_position+photo.fin_transfer.canvas.to_display(point)
	move(p,Vector2.ZERO);mouse(MOUSE_BUTTON_LEFT,true,p);mouse(MOUSE_BUTTON_LEFT,false,p)
	await settle()

func fin_snap(name: String) -> void:
	await settle();await RenderingServer.frame_post_draw
	viewer.get_node("ViewerViewport/Viewport").get_texture().get_image().save_png("res://godot/diagnostics/fin_%s.png" % name)
