extends SceneTree
## Run as an external script with --main-pack; no repository resources required.
var errors: Array=[]
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var config: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/photo_import_projection.json"))
	check(config is Dictionary,"Projection JSON in pack")
	check(FileAccess.get_sha256("res://models/pelvicachromis_taeniatus_male.glb")==config.source_glb_sha256,"Raw GLB in pack")
	var image:=Image.new()
	check(image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://textures/pelvicachromis_taeniatus_male_albedo.png"))==OK,"Raw albedo in pack")
	var viewer=load("res://scenes/PhotoImport.tscn").instantiate();root.add_child(viewer)
	await create_timer(.5).timeout
	var importer=viewer.get_node("UI/ReferencePhoto")
	check(importer!=null,"Packed controller")
	check(viewer.animation_player.is_playing(),"Packed Swim_Test")
	for skeleton in viewer.fish.find_children("*","Skeleton3D",true,false):check(skeleton.get_bone_count()==15,"Packed skeleton")
	print("EXPORT PACK: ",errors);quit(0 if errors.is_empty() else 1)
