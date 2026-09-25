extends SceneTree
## Run with --path . --script res://scripts/validate_fish_import.gd.
## Headless checks skinning; a rendered run also writes five actual viewport PNGs.

var errors: Array[String] = []
var initial_points: Dictionary = {}
var vertex_motion: Dictionary = {}
var last_points: Dictionary = {}


func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
		push_error(message)


func _initialize() -> void:
	call_deferred("run_test")


func skin_bounds(instance: MeshInstance3D, skeleton: Skeleton3D) -> AABB:
	var skin: Skin = instance.skin
	var transforms: Array[Transform3D] = []
	for bind in range(skin.get_bind_count()):
		var bone: int = skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(bind))
		transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
	var result := AABB()
	var first := true
	var points := PackedVector3Array()
	for surface in range(instance.mesh.get_surface_count()):
		var arrays: Array = instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		check(uvs.size() == vertices.size(), "%s: missing UV coordinates" % instance.name)
		for uv in uvs:
			check(uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0,
				"%s: UV outside atlas" % instance.name)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		check(bones.size() == vertices.size() * 4, "%s: expected four skin slots" % instance.name)
		for vertex in range(vertices.size()):
			var point := Vector3.ZERO
			var total := 0.0
			for slot in range(4):
				var index: int = vertex * 4 + slot
				var weight: float = weights[index]
				if weight > 0.0:
					point += (transforms[bones[index]] * vertices[vertex]) * weight
					total += weight
			check(absf(total - 1.0) < 0.0002, "%s: weights not normalized" % instance.name)
			points.append(point)
			if first:
				result = AABB(point, Vector3.ZERO)
				first = false
			else:
				result = result.expand(point)
	if not initial_points.has(instance.name):
		initial_points[instance.name] = points
		vertex_motion[instance.name] = 0.0
	else:
		var start: PackedVector3Array = initial_points[instance.name]
		for index in range(points.size()):
			vertex_motion[instance.name] = maxf(vertex_motion[instance.name], points[index].distance_to(start[index]))
	last_points[instance.name] = points
	return result


func vec(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])


func run_test() -> void:
	var packed: PackedScene = load("res://scenes/FishRigTest.tscn")
	if packed == null:
		quit(1)
		return
	var scene: Node3D = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var skeletons: Array[Node] = scene.find_children("*", "Skeleton3D", true, false)
	var meshes: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
	check(skeletons.size() == 1, "Expected one Skeleton3D")
	check(meshes.size() == 11, "Expected eleven mesh objects")
	if skeletons.is_empty() or scene.animation_player == null:
		quit(1)
		return
	var skeleton := skeletons[0] as Skeleton3D
	var player: AnimationPlayer = scene.animation_player
	var clip: StringName = scene.swim_animation
	var animation: Animation = player.get_animation(clip)
	check(skeleton.get_bone_count() == 15, "Expected 15 imported bones")
	check(player.is_playing(), "Swim clip did not autoplay")
	check(absf(animation.length - 2.0) < 0.0001, "Swim duration is not two seconds")
	check(animation.loop_mode == Animation.LOOP_LINEAR, "Swim clip is not looping")
	for name in player.get_animation_list():
		check(not String(name).contains("Rig_Test_Pose"), "Test pose was accidentally exported")
	var textured_meshes := 0
	for node in meshes:
		var mesh := node as MeshInstance3D
		var found := false
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material != null and material.albedo_texture != null:
				check(material.albedo_texture.get_width() == 4096, "Expected 4096 photo atlas")
				found = true
		check(found, "%s: photo material missing" % mesh.name)
		if found:
			textured_meshes += 1
	check(textured_meshes == 11, "Expected eleven photo textured meshes")
	player.pause()
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://blender/diagnostics/glb_export_validation.json"))
	var reference: Dictionary = source["blender_skin_bounds"]
	var max_difference := 0.0
	var captured: Array[String] = []
	var graphical: bool = DisplayServer.get_name() != "headless"
	var sample_index := 0
	for time_text in ["0.0", "0.5", "1.0", "1.5", "2.0"]:
		player.seek(float(time_text), true)
		await process_frame
		for node in meshes:
			var mesh := node as MeshInstance3D
			check(mesh.skin != null, "%s has no Skin" % mesh.name)
			if mesh.skin == null:
				continue
			var bounds: AABB = skin_bounds(mesh, skeleton)
			var expected: Dictionary = reference[time_text][String(mesh.name)]
			var difference: float = maxf(bounds.position.distance_to(vec(expected["min"])),
				bounds.end.distance_to(vec(expected["max"])))
			max_difference = maxf(max_difference, difference)
			check(difference < 0.00002, "%s at %ss differs from Blender by %f m" % [mesh.name, time_text, difference])
		if graphical:
			await RenderingServer.frame_post_draw
			var image: Image = root.get_texture().get_image()
			var filename: String = "res://blender/diagnostics/godot_swim_%02d.png" % sample_index
			check(image.save_png(filename) == OK, "Could not save screenshot")
			captured.append(filename)
			if sample_index == 1:
				check(image.save_png("res://godot/diagnostics/photo_texture_test.png") == OK, "Photo screenshot failed")
		sample_index += 1
	check(float(vertex_motion.get("Fish_Body", 0.0)) > 0.0001, "Body does not move")
	check(float(vertex_motion.get("Caudal_Fin", 0.0)) > 0.0001, "Caudal fin does not move")
	for name in ["Eye_Left", "Eye_Right", "Mouth"]:
		check(float(vertex_motion.get(name, 1.0)) < 0.00001, "%s slips relative to stable head" % name)
	var seam_error := 0.0
	for name in initial_points:
		var initial: PackedVector3Array = initial_points[name]
		var final: PackedVector3Array = last_points[name]
		for index in range(initial.size()):
			seam_error = maxf(seam_error, initial[index].distance_to(final[index]))
	check(seam_error < 0.000001, "Loop has a discontinuity in skinned vertices")
	# Exercise ordinary engine-driven playback for two full loops, not just seeks.
	player.play(clip)
	player.seek(0.0, true)
	await create_timer(4.1).timeout
	var playback_position: float = player.current_animation_position
	check(player.is_playing() and playback_position < 0.5, "Two automatic loops did not complete")
	var report := {"godot_version": Engine.get_version_info().string,
		"meshes": meshes.size(), "bones": skeleton.get_bone_count(),
		"animations": Array(player.get_animation_list()), "playing_clip": String(clip),
		"duration_seconds": animation.length, "autoplay": true, "loop": true,
		"uv_coordinates_on_all_surfaces": true, "photo_textured_meshes": textured_meshes,
		"max_blender_bounds_difference_m": max_difference, "vertex_motion_m": vertex_motion,
		"loop_seam_error_m": seam_error, "automatic_playback_seconds": 4.1,
		"position_after_two_loops": playback_position,
		"screenshots": captured, "errors": errors}
	var suffix := "visual" if graphical else "headless"
	var file := FileAccess.open("res://blender/diagnostics/godot_validation_%s.json" % suffix, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
