extends SceneTree
const Analyzer=preload("res://scripts/photo_import/photo_analyzer.gd")
const Data=preload("res://scripts/project/project_data.gd")
const Projector=preload("res://scripts/photo_import/texture_projection.gd")
var errors: Array=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var manifest: Array=JSON.parse_string(FileAccess.get_file_as_string("res://.godot/anatomy_fixtures/manifest.json"))
	var results: Dictionary={}
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/photo_import_projection.json"))
	for fixture in manifest:
		var image:=Image.new();image.load_png_from_buffer(FileAccess.get_file_as_bytes(fixture.path))
		var start:=Time.get_ticks_msec();var result:=Analyzer.analyze(image)
		var entry: Dictionary={"elapsed_ms":Time.get_ticks_msec()-start,"path":fixture.path,"expected":fixture.points}
		if result.has("error"):errors.append(fixture.name+": "+result.error);entry.error=result.error;results[fixture.name]=entry;continue
		var points: PackedVector2Array=result.suggested_landmarks
		if points.size()!=12 or result.landmark_confidence.size()!=12:errors.append(fixture.name+": point count")
		if result.head_direction!=fixture.direction:errors.append(fixture.name+": direction")
		var target:=Data.points_from_json(fixture.points);var length:=target[0].distance_to((target[2]+target[3])*.5)
		var distance: Array=[];var sum:=0.0
		for i in range(12):
			var d:=points[i].distance_to(target[i])/length;distance.append(d);sum+=d
			if d>.10:errors.append(fixture.name+": landmark "+str(i+1)+" excessive error "+str(d))
			if not Geometry2D.is_point_in_polygon(points[i].floor()+Vector2(.5,.5),result.fish_contour):errors.append(fixture.name+": outside mask "+str(i+1))
		if sum/12>.045:errors.append(fixture.name+": mean error")
		if Projector.alignment(points,config).has("error"):errors.append(fixture.name+": unusable alignment")
		if fixture.name=="low_eye_contrast" and result.eye_detected:errors.append("Weak eye should use LOW template fallback")
		if fixture.name=="weak_pelvic_tip" and result.landmark_confidence[11].level!="LOW":errors.append("Missing tip should be LOW")
		entry.mean_relative_error=sum/12;entry.relative_errors=distance
		for key in ["fish_contour","suggested_landmarks","template_landmarks","pectoral_region"]:result[key]=Data.points_to_json(result[key])
		entry.result=Data.plain(result);results[fixture.name]=entry
		print(fixture.name,": error=",sum/12," time=",entry.elapsed_ms)
	FileAccess.open("res://godot/diagnostics/anatomy_variations.json",FileAccess.WRITE).store_string(JSON.stringify({"cases":results,"errors":errors},"\t"))
	print("ANATOMY TESTS: ",errors);quit(0 if errors.is_empty() else 1)
