extends SceneTree
const Baker=preload("res://scripts/body_texture_baker.gd")
var errors: Array[String]=[]
func _initialize() -> void:
	call_deferred("run")
func read_image(path: String) -> Image:
	var image := Image.new()
	image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	return image
func run() -> void:
	var model: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/body_projection.json"))
	var base:=read_image("res://textures/pelvicachromis_taeniatus_male_albedo.png")
	base.resize(512,512)
	base.convert(Image.FORMAT_RGBA8)
	var records: Array=[]
	for name in ["left","down","small"]:
		var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://godot/diagnostics/landmark_%s.json" % name))
		var photo:=read_image("res://godot/diagnostics/landmark_%s_normalized.png" % name)
		photo.convert(Image.FORMAT_RGBA8)
		# Adversarial transparent background must never leak magenta into skin.
		for y in range(photo.get_height()):
			for x in range(photo.get_width()):
				if photo.get_pixel(x,y).a<0.99:photo.set_pixel(x,y,Color(1,0,1,0))
		var result:=Baker.bake(base,photo,data,model)
		if result.has("error"):
			errors.append(name+": "+result.error)
			continue
		var outside_changes:=0
		var magenta:=0
		for y in range(512):
			for x in range(512):
				var c: Color=result.image.get_pixel(x,y)
				if result.coverage.get_pixel(x,y).r<0.5 and c!=base.get_pixel(x,y):outside_changes+=1
				if c.r>.95 and c.b>.95 and c.g<.05:magenta+=1
		if outside_changes>0 or magenta>0:errors.append("Background/fallback corruption: "+name)
		records.append({"case":name,"written":result.stats.written_samples,"outside_changes":outside_changes,"magenta_leaks":magenta})
	FileAccess.open("res://godot/diagnostics/body_projection_edge_cases.json",FileAccess.WRITE).store_string(JSON.stringify({"errors":errors,"cases":records},"\t"))
	print("Projection edge cases: ",errors)
	quit(0 if errors.is_empty() else 1)
