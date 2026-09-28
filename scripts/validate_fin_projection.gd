extends SceneTree
const New=preload("res://scripts/fin_texture_baker.gd")
var Old: Script
const Body=preload("res://scripts/body_texture_baker.gd")
func _initialize() -> void:
	var output: Array=[]
	var root_path:=ProjectSettings.globalize_path("res://").trim_suffix("/")
	var code:=OS.execute("git",["-c","safe.directory="+root_path,"-C",root_path,"show","bcb52a8:scripts/fin_texture_baker.gd"],output)
	if code!=0:push_error("Cannot read baseline commit bcb52a8");quit(1);return
	FileAccess.open("res://.godot/old_fin_baker.gd",FileAccess.WRITE).store_string(output[0])
	Old=load("res://.godot/old_fin_baker.gd")
	var record: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://godot/diagnostics/fin_before/fin_transfer_validation.json"))
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(record.landmarks_path))
	var model: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/body_projection.json"))
	var fins: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/fin_projection.json"))
	var targets: Array=[]
	for key in model.anchor_names:targets.append(data.landmarks_normalized_px[key])
	var weights:=Body.fit(model.anchors,targets)
	var result: Dictionary={}
	var photo:=Image.load_from_file(record.normalized_path)
	var original:=Image.load_from_file(data.original_photo_path)
	for name in fins.fins:
		var fin: Dictionary=fins.fins[name]
		var polygon:=PackedVector2Array()
		for p in record.fins[name].points_normalized_px:polygon.append(Body.vec(p))
		if name=="Anal_Fin":
			var mask:=Image.load_from_file(record.fins[name].mask_path)
			var corrected:=New.edge_mask(photo,mask,polygon,original,data)
			corrected.mask.save_png("res://godot/diagnostics/fin_anal_sampling_mask.png")
			print("Anal edge rejected pixels: ",corrected.rejected)
		var old: Dictionary=Old.correspondence(fin,polygon,model.anchors,weights)
		var now:=New.correspondence(fin,polygon,model.anchors,targets)
		if now.has("error"):print(name,now);quit(1);return
		var previous: Array=[];var current: Array=[]
		for i in range(now.vertices.size()):
			var p: Vector2=old.vertices[i] if old.direct else Old.source_point(old.vertices[i],old)
			previous.append([p.x,p.y])
			p=now.vertices[i];current.append([p.x,p.y])
		result[name]={"before":previous,"after":current}
	FileAccess.open("res://godot/diagnostics/fin_projection_coordinates.json",FileAccess.WRITE).store_string(JSON.stringify(result))
	quit()
