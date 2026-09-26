extends "res://scripts/validate_fish_viewer.gd"
const Normalizer = preload("res://scripts/fish_normalizer.gd")
var photo: Control
var records: Array = []

func landmark_click(p: Vector2) -> void:
	var panel: Control = photo.landmarks
	photo.photo_scroll.ensure_control_visible(panel.canvas)
	await settle()
	var position: Vector2 = panel.canvas.global_position + panel.canvas.to_display(p)
	move(position, Vector2.ZERO)
	mouse(MOUSE_BUTTON_LEFT, true, position)
	mouse(MOUSE_BUTTON_LEFT, false, position)
	await settle()

func wait_normalized() -> void:
	var deadline := Time.get_ticks_msec() + 120000
	while photo.landmarks.worker != null and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	check(photo.landmarks.worker == null, "Normalization timed out")
	await settle()

func run() -> void:
	viewer = load("res://scenes/Main.tscn").instantiate()
	root.add_child(viewer)
	await settle()
	photo = viewer.get_node("UI/ReferencePhoto")
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string("res://.godot/landmark_fixtures/cases.json"))
	var panel: Control = photo.landmarks
	for item in cases:
		root.size = Vector2i(1600,1100)
		check(photo.load_photo(item.photo), "Photo load failed")
		check(panel.landmark_data.is_empty() and not panel.visible, "New photo retained landmarks")
		photo.mask_image = Image.load_from_file(item.mask)
		photo.current_mask_path = item.mask
		panel.setup(photo.original_image, photo.mask_image, item.photo, item.mask)
		await settle()
		await click(panel.start_button)
		check(panel.status.text.contains("Schnauzenspitze"), "Expected-point prompt missing")
		await landmark_click(Vector2(0,0))
		check(panel.canvas.points.is_empty(), "Background accepted")
		for i in range(6):
			if i == 2:
				root.size = Vector2i(600,900)
				await settle()
			var p := Vector2(item.points[i][0], item.points[i][1])
			await landmark_click(p)
			check(panel.canvas.points.size() == i + 1, "Point missing: %s %d" % [item.name,i])
			if panel.canvas.points.size() == i + 1:
				check(panel.canvas.points[i].distance_to(p) < 0.03, "Original coordinates incorrect after resize")
		check(not panel.confirm_button.disabled, "Six points cannot be confirmed")
		await click(panel.undo_button)
		check(panel.canvas.points.size() == 5 and panel.confirm_button.disabled, "Undo failed")
		await landmark_click(Vector2(item.points[5][0],item.points[5][1]))
		await click(panel.confirm_button)
		await wait_normalized()
		check(not panel.current_normalized_path.is_empty(), "No normalized image: " + panel.status.text)
		if panel.current_normalized_path.is_empty():
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(panel.current_landmark_path))
		check(data.mirrored == (item.name == "left"), "Direction incorrect")
		var p: Dictionary = data.landmarks_normalized_px
		var tail_y: float = (p.tail_upper[1] + p.tail_lower[1]) * 0.5
		var tail_x: float = (p.tail_upper[0] + p.tail_lower[0]) * 0.5
		check(absf(p.snout[1] - tail_y) < 0.001 and p.snout[0] > tail_x, "Normalized axis not horizontal/head right")
		check(p.body_upper[1] < p.body_lower[1], "Normalization flipped fish upside down")
		var normalized := Image.load_from_file(panel.current_normalized_path)
		check(normalized.get_pixel(0,0).a == 0.0, "Transparency missing")
		check(normalized.get_size().x <= 2048 and normalized.get_size().y <= 2048, "Working image too large")
		var eye := Vector2i(roundi(p.eye[0]),roundi(p.eye[1]))
		check(normalized.get_pixelv(eye).a > 0.9, "Eye missing from transformed mask")
		normalized.save_png("res://godot/diagnostics/landmark_%s_normalized.png" % item.name)
		FileAccess.open("res://godot/diagnostics/landmark_%s.json" % item.name,FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
		records.append({"case":item.name,"direction":data.direction,"angle":data.axis_angle_degrees,"length":data.body_length_px,"height":data.body_height_px})
		for dimensions in [Vector2i(1600,1100),Vector2i(600,900),Vector2i(480,360)]:
			root.size = dimensions
			await settle()
			check(root.get_visible_rect().encloses(photo.panel.get_global_rect()),"Panel outside window")
			photo.photo_scroll.ensure_control_visible(panel.canvas)
			await settle()
			if item.name == "large_right" and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://godot/diagnostics/landmark_ui_%dx%d.png" % [dimensions.x, dimensions.y])
			await click(viewer.animation_button)
			check(not viewer.animation_player.is_playing(),"Pause broken")
			await click(viewer.animation_button)
			var center: Vector2 = viewer.get_node("ViewerViewport").get_global_rect().get_center()
			mouse(MOUSE_BUTTON_LEFT,true,center)
			move(center+Vector2(25,10),Vector2(25,10))
			mouse(MOUSE_BUTTON_LEFT,false,center)
			check(absf(viewer.orbit.yaw)>0.01,"Orbit broken")
			var before: float = viewer.orbit.distance
			mouse(MOUSE_BUTTON_WHEEL_UP,true,center)
			check(viewer.orbit.distance < before,"Zoom broken")
			await click(viewer.reset_button)
			check(viewer.orbit.yaw==0.0,"Reset broken")
		await click(panel.reset_button)
		check(panel.canvas.points.is_empty() and panel.current_landmark_path.is_empty() and panel.current_normalized_path.is_empty(),"Landmark reset failed")
	# Stale worker must not reintroduce landmarks after replacing the photo.
	root.size = Vector2i(1600,1100)
	var item: Dictionary = cases[0]
	photo.load_photo(item.photo)
	panel.setup(photo.original_image, Image.load_from_file(item.mask),item.photo,item.mask)
	panel.canvas.points = PackedVector2Array()
	for pair in item.points:
		panel.canvas.points.append(Vector2(pair[0],pair[1]))
	panel.confirm()
	photo.load_photo(cases[4].photo)
	await wait_normalized()
	check(panel.landmark_data.is_empty() and panel.current_normalized_path.is_empty(),"Stale normalized result accepted")
	check(Normalizer.analyze(PackedVector2Array()).has("error"),"Incomplete points accepted")
	var invalid := PackedVector2Array()
	for pair in cases[0].points:invalid.append(Vector2(pair[0],pair[1]))
	var swap := invalid[2]; invalid[2]=invalid[3]; invalid[3]=swap
	check(Normalizer.analyze(invalid).has("error"),"Swapped tail points accepted")
	FileAccess.open("res://godot/diagnostics/landmark_validation.json",FileAccess.WRITE).store_string(JSON.stringify({"errors":errors,"cases":records,"resize_mapping":true,"viewer_controls":true,"stale_result_discarded":true},"\t"))
	print("Landmark tests: ",errors)
	quit(0 if errors.is_empty() else 1)
