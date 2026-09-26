extends SceneTree
## Real viewport event routing, buttons, resizing, animation and GPU screenshots.
var errors: Array[String] = []
var viewer: Node3D
var captures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func settle() -> void:
	for i in range(4):
		await process_frame
func mouse(button: int, pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = point
	event.global_position = point
	root.push_input(event, true)
func move(point: Vector2, delta: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = delta
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)
func click(button: Button) -> void:
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
		ancestor = ancestor.get_parent()
	await settle()
	var point := button.get_global_rect().get_center()
	move(point, Vector2.ZERO)
	mouse(MOUSE_BUTTON_LEFT, true, point)
	mouse(MOUSE_BUTTON_LEFT, false, point)
	await settle()
func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := "res://godot/diagnostics/viewer_%s.png" % label
		check(root.get_texture().get_image().save_png(path) == OK, "Screenshot failed")
		captures.append(path)
func run() -> void:
	viewer = load("res://scenes/Main.tscn").instantiate()
	root.add_child(viewer)
	await settle()
	var orbit: Node3D = viewer.orbit
	var player: AnimationPlayer = viewer.animation_player
	check(player != null and player.is_playing(), "Autoplay failed")
	check(viewer.swim_animation == &"Swim_Test", "Wrong animation")
	check(orbit.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Camera is not perspective")
	var point := root.get_visible_rect().size * 0.5
	var initial_distance: float = orbit.distance
	mouse(MOUSE_BUTTON_LEFT, true, point)
	move(point + Vector2(80, 40), Vector2(80, 40))
	mouse(MOUSE_BUTTON_LEFT, false, point + Vector2(80, 40))
	check(absf(orbit.yaw) > 0.1 and absf(orbit.pitch) > 0.1, "Mouse orbit failed")
	check(not orbit.dragging, "Mouse release failed")
	await capture("orbit")
	mouse(MOUSE_BUTTON_WHEEL_UP, true, point)
	check(orbit.distance < initial_distance, "Zoom in failed")
	for i in range(100):
		mouse(MOUSE_BUTTON_WHEEL_UP, true, point)
	check(orbit.distance >= orbit.radius * 1.45, "Unsafe near zoom")
	for i in range(100):
		mouse(MOUSE_BUTTON_WHEEL_DOWN, true, point)
	check(is_equal_approx(orbit.zoom_ratio, 3.0), "Far zoom limit failed")
	mouse(MOUSE_BUTTON_LEFT, true, point)
	move(point, Vector2(100000, 100000))
	check(absf(orbit.pitch) <= orbit.PITCH_LIMIT and absf(orbit.yaw) <= PI, "Angle limits failed")
	mouse(MOUSE_BUTTON_LEFT, false, viewer.reset_button.get_global_rect().get_center())
	check(not orbit.dragging, "Release over UI leaves dragging active")
	await click(viewer.reset_button)
	check(orbit.yaw == 0.0 and orbit.pitch == 0.0 and orbit.zoom_ratio == 1.0, "Reset button failed")
	await click(viewer.animation_button)
	check(not player.is_playing(), "Pause button failed")
	var paused: float = player.current_animation_position
	await create_timer(0.15).timeout
	check(is_equal_approx(paused, player.current_animation_position), "Paused animation advances")
	check(orbit.yaw == 0.0 and not orbit.dragging, "UI click moved camera")
	await click(viewer.animation_button)
	check(player.is_playing(), "Resume button failed")
	await create_timer(2.15).timeout
	check(player.is_playing() and player.current_animation_position < 2.0, "Animation does not loop")
	for size in [Vector2i(1280, 800), Vector2i(600, 900), Vector2i(480, 360)]:
		root.size = size
		await settle()
		await click(viewer.reset_button)
		var rect := root.get_visible_rect()
		for button in [viewer.reset_button, viewer.animation_button]:
			check(rect.encloses(button.get_global_rect()), "UI outside window at %s" % size)
		for node in viewer.fish.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			for corner in range(8):
				var world: Vector3 = mesh.global_transform * mesh.get_aabb().get_endpoint(corner)
				check(not orbit.camera.is_position_behind(world), "Fish behind camera")
				check(rect.has_point(orbit.camera.unproject_position(world)), "Fish clipped at %s" % size)
		await capture("%dx%d" % [size.x, size.y])
	var report := {"errors": errors, "screenshots": captures, "animation": String(viewer.swim_animation),
		"mouse_orbit_zoom_limits_ui_reset_resize_tested": true}
	FileAccess.open("res://godot/diagnostics/viewer_validation.json", FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
