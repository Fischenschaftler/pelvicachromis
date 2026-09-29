extends "res://scripts/validate_fish_viewer.gd"
const Projector=preload("res://scripts/photo_import/texture_projection.gd")
var importer: Control
var report: Dictionary={"surfaces":[],"all_mesh_surfaces":[],"errors":[]}
func _initialize() -> void:call_deferred("run_test")
func run_test() -> void:
	viewer=load("res://scenes/PhotoImport.tscn").instantiate();root.add_child(viewer);root.size=Vector2i(1400,1050)
	await create_timer(.5).timeout;importer=viewer.get_node("UI/ReferencePhoto")
	var path:=ProjectSettings.globalize_path("res://blender/reference/pelvicachromis_taeniatus_male.jpg")
	importer.load_photo(path)
	while importer.analysis_worker!=null:await create_timer(.05).timeout
	check(importer.canvas.landmarks.size()==12,"Analysis fixture failed")
	if importer.canvas.landmarks.size()!=12:finish();return
	var originals: Dictionary={};var geometry: Dictionary={}
	for mesh in viewer.fish.find_children("*","MeshInstance3D",true,false):
		geometry[mesh]=hash(mesh.mesh.surface_get_arrays(0))
		for i in range(mesh.mesh.get_surface_count()):
			originals[str(mesh.get_instance_id())+":"+str(i)]=mesh.get_active_material(i)
			report.all_mesh_surfaces.append({"mesh":mesh.name,"surface":i,"original_material":mesh.get_active_material(i).resource_name,"receives_generated_atlas":importer.originals.has(mesh)})
			check(mesh.material_override==null,"Unexpected node-wide override: "+mesh.name)
	# Strong regression: a constant cyan photograph must leave NO old RGB anywhere
	# in the reserved body/fin slots, including excluded body roots and deep gaps.
	var synthetic: Image=importer.source.duplicate();synthetic.fill(Color(.08,.75,.85,1))
	var task:=Thread.new();task.start(Projector.generate.bind(synthetic,importer.canvas.landmarks.duplicate(),importer.canvas.points.duplicate(),"left",512,path))
	while task.is_alive():await create_timer(.1).timeout
	var result: Dictionary=task.wait_to_finish()
	check(not result.has("error"),"Synthetic projection: "+str(result.get("error","")))
	if result.has("error"):finish();return
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/body_projection.json"))
	var fins: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/photo_import_projection.json"))
	var slots: Dictionary=body.uv_slots_blender_v.duplicate(true)
	for name in fins.fins:slots[name]=fins.fins[name].slot_blender_v
	var bad_rgb:=0;var bad_alpha:=0;var tested:=0
	for name in slots:
		var slot: Array=slots[name];var size: Vector2i=result.image.get_size()
		for y in range(ceili((1-slot[3])*size.y),floori((1-slot[1])*size.y)):
			for x in range(ceili(slot[0]*size.x),floori(slot[2]*size.x)):
				var c: Color=result.image.get_pixel(x,y);tested+=1
				if Vector3(c.r-.08,c.g-.75,c.b-.85).length()>.018:bad_rgb+=1
				if body.uv_slots_blender_v.has(name) and c.a<.999:bad_alpha+=1
	check(bad_rgb==0,"Original/unfilled RGB remains: "+str(bad_rgb));check(bad_alpha==0,"Body alpha holes: "+str(bad_alpha))
	report.atlas={"tested_pixels":tested,"old_rgb_pixels":bad_rgb,"body_alpha_holes":bad_alpha,"body":result.metadata.body_stats,"fins":result.metadata.stats}
	result.image.save_png("res://godot/diagnostics/atlas_sentinel.png")
	result.image.generate_mipmaps();importer.generated=ImageTexture.create_from_image(result.image)
	for cycle in range(3):
		importer.show_generated();var instances: Dictionary={}
		for mesh in importer.originals:
			for i in range(mesh.mesh.get_surface_count()):
				var material: BaseMaterial3D=mesh.get_active_material(i)
				check(material.albedo_texture==importer.generated,"Texture not replaced: "+mesh.name)
				check(not instances.has(material.get_instance_id()),"Shared runtime material")
				instances[material.get_instance_id()]=true
				check(material!=originals[str(mesh.get_instance_id())+":"+str(i)],"Import material mutated")
				if mesh.name=="Fish_Body":check(material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"Transparent body material")
				if cycle==0:report.surfaces.append({"mesh":mesh.name,"surface":i,"material":material.resource_name,"transparency":material.transparency,"generated":material.albedo_texture==importer.generated})
		importer.show_original()
		for mesh in viewer.fish.find_children("*","MeshInstance3D",true,false):
			for i in range(mesh.mesh.get_surface_count()):check(mesh.get_active_material(i)==originals[str(mesh.get_instance_id())+":"+str(i)],"Original not restored: "+mesh.name)
	importer.show_generated();viewer.orbit.pitch=-.45;viewer.orbit._resize()
	await create_timer(.2).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://godot/diagnostics/atlas_sentinel_view.png")
	# Real reference, unmodified normal workflow.
	importer.generate()
	while importer.worker!=null:await create_timer(.1).timeout
	check(not importer.texture_path.is_empty(),"Real projection failed: "+importer.status.text)
	if not importer.texture_path.is_empty():
		var atlas: Image=importer.generated.get_image();atlas.clear_mipmaps();atlas.save_png("res://godot/diagnostics/generated_atlas_fixed.png")
		var alpha:=Image.create(atlas.get_width(),atlas.get_height(),false,Image.FORMAT_L8)
		for y in range(atlas.get_height()):
			for x in range(atlas.get_width()):
				var a: float=atlas.get_pixel(x,y).a;alpha.set_pixel(x,y,Color(a,a,a))
		alpha.save_png("res://godot/diagnostics/generated_atlas_alpha.png")
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://godot/diagnostics/generated_back_fixed.png")
	importer.show_original();await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://godot/diagnostics/original_back.png")
	importer.show_generated();await create_timer(2.2).timeout
	check(viewer.animation_player.is_playing(),"Swim_Test stopped")
	for mesh in geometry:check(hash(mesh.mesh.surface_get_arrays(0))==geometry[mesh],"Mesh changed")
	for skeleton in viewer.fish.find_children("*","Skeleton3D",true,false):check(skeleton.get_bone_count()==15,"Bone count changed")
	report.swim_test=viewer.animation_player.is_playing();report.generated_texture=importer.texture_path
	var views: Dictionary={"left":Vector2(0,0),"right":Vector2(PI,0),"back":Vector2(.2,-.65),"perspective":Vector2(-.65,.2)}
	for name in views:
		viewer.orbit.yaw=views[name].x;viewer.orbit.pitch=views[name].y;viewer.orbit._resize()
		await create_timer(.15).timeout;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://godot/diagnostics/atlas_final_"+name+".png")
	await legacy_roundtrip()
	finish()
func finish() -> void:
	report.errors=errors;FileAccess.open("res://godot/diagnostics/atlas_replacement_validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ATLAS REPLACEMENT TESTS: ",errors);quit(0 if errors.is_empty() else 1)

func legacy_roundtrip() -> void:
	# Reopen a previously saved pre-fix integration project, preserving its original.
	var legacy_root:="user://auto_analysis_tests"
	var selected:=""
	if DirAccess.dir_exists_absolute(legacy_root):
		for run in DirAccess.get_directories_at(legacy_root):
			for id in DirAccess.get_directories_at(legacy_root+"/"+run):
				var path:=legacy_root+"/"+run+"/"+id+"/project.json"
				if not FileAccess.file_exists(path):continue
				var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
				if data is Dictionary and not String(data.get("generated_texture_path","")).is_empty() and int(data.get("generation_data",{}).get("atlas_fill_version",0))<1:selected=path;break
			if not selected.is_empty():break
	check(not selected.is_empty(),"Existing pre-fix project fixture missing")
	if selected.is_empty():return
	var folder:=selected.get_base_dir();importer.project_manager.root=folder.get_base_dir()
	var count: int=importer.analysis_count
	check(importer.open_project(folder.get_file()),"Legacy project open failed")
	check(importer.analysis_count==count,"Legacy project reanalysed")
	importer.generate()
	while importer.worker!=null:await create_timer(.1).timeout
	check(int(importer.generation_data.get("atlas_fill_version",0))==1,"Legacy regeneration failed")
	check(importer.save_project("Atlas-Abschlussprüfung",true),"Regenerated legacy save failed")
	var id: String=importer.project_id;var texture: Image=importer.generated.get_image();texture.clear_mipmaps()
	var checksum:=hash(texture.get_data());importer.reset()
	check(importer.open_project(id),"Regenerated project reopen failed")
	texture=importer.generated.get_image();texture.clear_mipmaps()
	check(hash(texture.get_data())==checksum and importer.showing_generated,"Generated texture roundtrip failed")
	check(importer.analysis_count==count,"Saved project reanalysed")
	viewer.orbit.yaw=.2;viewer.orbit.pitch=-.65;viewer.orbit._resize()
	await create_timer(.2).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://godot/diagnostics/atlas_final_legacy.png")
	report.legacy={"source":selected,"saved_copy":importer.project_manager.folder(id),"regenerated":int(importer.generation_data.get("atlas_fill_version",0))==1,"texture_hash_preserved":hash(texture.get_data())==checksum,"analysis_count_unchanged":importer.analysis_count==count}
