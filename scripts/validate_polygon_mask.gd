extends "res://scripts/validate_fish_viewer.gd"
const Builder = preload("res://scripts/polygon_mask.gd")
var photo: Control
var mask_records: Array = []

func point_click(original: Vector2, double_click := false) -> void:
	var point: Vector2 = photo.picture.global_position + photo.picture.to_display(original)
	move(point, Vector2.ZERO)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	event.global_position = point
	event.double_click = double_click
	root.push_input(event,true)
	mouse(MOUSE_BUTTON_LEFT,false,point)
	await settle()

func wait_mask() -> void:
	var deadline := Time.get_ticks_msec()+15000
	while photo.mask_busy and Time.get_ticks_msec()<deadline:
		await create_timer(0.02).timeout
	check(not photo.mask_busy,"Mask calculation timed out")
	await settle()

func shot(name: String) -> void:
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://godot/diagnostics/mask_%s.png" % name)

func run() -> void:
	viewer=load("res://scenes/Main.tscn").instantiate()
	root.add_child(viewer)
	await settle()
	photo=viewer.get_node("UI/ReferencePhoto")
	var folder:=ProjectSettings.globalize_path("res://.godot/photo_import_fixtures/")
	check(photo.load_photo(folder+"Großes Fischfoto.jpg"),"JPG load failed")
	await settle()
	await click(photo.mark_button)
	var margin_point: Vector2 = photo.picture.global_position+Vector2(1,1)
	mouse(MOUSE_BUTTON_LEFT,true,margin_point)
	mouse(MOUSE_BUTTON_LEFT,false,margin_point)
	check(photo.picture.points.is_empty(),"Letterbox click created a point")
	var rectangle:=PackedVector2Array([Vector2(800,600),Vector2(3200,600),Vector2(3200,2400),Vector2(800,2400)])
	await point_click(rectangle[0])
	await point_click(rectangle[1])
	await click(photo.close_button)
	check(photo.current_mask_path.is_empty() and not photo.mask_busy,"Incomplete polygon accepted")
	check(photo.marking_status.text.contains("drei"),"Incomplete polygon feedback missing")
	photo.photo_scroll.scroll_vertical=0
	root.size=Vector2i(600,900)
	await settle()
	for i in range(2):
		check(photo.picture.points[i].distance_to(rectangle[i])<0.02,"Resize changed original coordinates")
	await point_click(rectangle[2])
	await point_click(rectangle[3],true)
	await wait_mask()
	check(not photo.current_mask_path.is_empty(),"Double click did not save mask")
	if photo.mask_image == null:
		print(photo.marking_status.text)
		quit(1)
		return
	var mask: Image=Image.load_from_file(photo.current_mask_path)
	check(mask.get_size()==Vector2i(4000,3000),"Mask not original resolution")
	check(mask.get_pixel(800,600).r==1.0 and mask.get_pixel(799,600).r==0.0,"Left edge mapped incorrectly")
	check(mask.get_pixel(3199,2399).r==1.0 and mask.get_pixel(3200,2400).r==0.0,"Right edge mapped incorrectly")
	check(mask.get_data().count(255)==2400*1800,"Rectangle mask area incorrect")
	var preview: Image=photo.cutout_preview.texture.get_image()
	check(preview.get_pixel(0,0).a==0.0 and preview.get_pixel(preview.get_width()/2,preview.get_height()/2).a==1.0,"Cutout alpha incorrect")
	mask_records.append({"size":[4000,3000],"inside_pixels":mask.get_data().count(255),"path":photo.current_mask_path})
	# Invalid contours must never start a worker or create a mask.
	check(not Builder.validation_error(PackedVector2Array([Vector2(1,1),Vector2(20,20),Vector2(40,40)]),Vector2i(80,60)).is_empty(),"Collinear polygon accepted")
	check(not Builder.validation_error(PackedVector2Array([Vector2(1,1),Vector2(40,40),Vector2(1,40),Vector2(40,1)]),Vector2i(80,60)).is_empty(),"Crossing polygon accepted")
	await click(photo.reset_mark_button)
	check(photo.current_mask_path.is_empty() and photo.picture.points.is_empty() and photo.cutout_preview.texture==null,"Reset failed")
	# A changed photo discards a completed mask as well as an in-flight result.
	await click(photo.mark_button)
	for p in rectangle:await point_click(p)
	await click(photo.close_button)
	check(photo.load_photo(folder+"Hochformat.png"),"PNG load failed")
	await wait_mask()
	check(photo.current_mask_path.is_empty() and photo.picture.points.is_empty(),"Old worker result leaked into new photo")
	await click(photo.mark_button)
	var triangle:=PackedVector2Array([Vector2(100,200),Vector2(500,200),Vector2(300,800)])
	for p in triangle:await point_click(p)
	await click(photo.close_button)
	await wait_mask()
	check(photo.mask_image!=null and photo.mask_image.get_size()==Vector2i(600,1000),"PNG mask dimensions incorrect")
	check(photo.mask_image.get_pixel(300,400).r==1.0 and photo.mask_image.get_pixel(10,10).r==0.0,"PNG mask placement incorrect")
	mask_records.append({"size":[600,1000],"path":photo.current_mask_path})
	check(photo.load_photo(folder+"Klein.jpeg"),"Small JPEG load failed")
	check(photo.current_mask_path.is_empty(),"New photo kept old mask path")
	await settle()
	await click(photo.mark_button)
	for p in [Vector2(10,10),Vector2(70,10),Vector2(40,50)]:await point_click(p)
	await click(photo.close_button)
	await wait_mask()
	check(photo.mask_image.get_size()==Vector2i(80,60),"Small mask size incorrect")
	# Fish-shaped diagnostic on the 4000x3000 image.
	root.size=Vector2i(1600,1100)
	photo.load_photo(folder+"Großes Fischfoto.jpg")
	await settle()
	await click(photo.mark_button)
	var contour:=PackedVector2Array([Vector2(734,294),Vector2(695,260),Vector2(620,240),Vector2(550,240),Vector2(450,222),Vector2(340,246),Vector2(270,278),Vector2(154,283),Vector2(225,350),Vector2(215,369),Vector2(116,361),Vector2(66,393),Vector2(82,469),Vector2(142,531),Vector2(230,440),Vector2(254,436),Vector2(240,491),Vector2(195,571),Vector2(330,510),Vector2(420,437),Vector2(485,420),Vector2(405,511),Vector2(505,470),Vector2(560,413),Vector2(575,455),Vector2(620,439),Vector2(615,396),Vector2(630,372),Vector2(700,331)])
	for p in contour:await point_click(Vector2(500+p.x*3.75,p.y*3.75))
	await click(photo.close_button)
	await wait_mask()
	check(photo.mask_image!=null,"Fish polygon invalid")
	if photo.mask_image!=null:
		photo.mask_image.save_png("res://godot/diagnostics/mask_fish_4000x3000.png")
		photo.cutout_preview.texture.get_image().save_png("res://godot/diagnostics/mask_cutout.png")
		var coords: Array=[]
		for p in photo.picture.points:coords.append([p.x,p.y])
		FileAccess.open("res://godot/diagnostics/mask_contour.json",FileAccess.WRITE).store_string(JSON.stringify({"photo_path":photo.current_photo_path,"points":coords},"\t"))
	for dimensions in [Vector2i(1600,1100),Vector2i(600,900),Vector2i(480,360)]:
		root.size=dimensions
		await settle()
		photo.photo_scroll.scroll_vertical=0
		await settle()
		check(root.get_visible_rect().encloses(photo.panel.get_global_rect()),"Mask panel outside window")
		await shot("%dx%d" % [dimensions.x,dimensions.y])
		await click(viewer.animation_button)
		check(not viewer.animation_player.is_playing(),"Viewer pause failed with mask")
		await click(viewer.animation_button)
		var point: Vector2=viewer.get_node("ViewerViewport").get_global_rect().get_center()
		mouse(MOUSE_BUTTON_LEFT,true,point);move(point+Vector2(20,10),Vector2(20,10));mouse(MOUSE_BUTTON_LEFT,false,point)
		check(absf(viewer.orbit.yaw)>0.01,"Viewer orbit failed with mask")
		await click(viewer.reset_button)
		check(viewer.orbit.yaw==0.0,"Viewer reset failed with mask")
	await click(photo.remove_button)
	check(photo.current_mask_path.is_empty() and photo.picture.points.is_empty(),"Remove retained marking")
	FileAccess.open("res://godot/diagnostics/mask_validation.json",FileAccess.WRITE).store_string(JSON.stringify({"errors":errors,"masks":mask_records,"double_click":true,"resize_mapping":true,"stale_result_discarded":true},"\t"))
	print("Polygon mask tests: ",errors)
	quit(0 if errors.is_empty() else 1)
