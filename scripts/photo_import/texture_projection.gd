extends RefCounted
const Body=preload("res://scripts/body_texture_baker.gd")
const Fin=preload("res://scripts/fin_texture_baker.gd")
const Mask=preload("res://scripts/polygon_mask.gd")
const Normalizer=preload("res://scripts/fish_normalizer.gd")
const KEYS=["snout","eye","tail_upper","tail_lower","caudal_upper","caudal_lower","dorsal_front","dorsal_back","anal_front","anal_back","pelvic_base","pelvic_tip"]
static func alignment(points: PackedVector2Array, config: Dictionary) -> Dictionary:
	if points.size()!=12:return {"error":"Bitte alle zwölf Referenzpunkte setzen."}
	for i in range(12):
		for j in range(i):
			if points[i].distance_to(points[j])<1:return {"error":"Referenzpunkte müssen unterscheidbar sein."}
	var tail: Vector2=(points[2]+points[3])*.5
	var axis:=points[0]-tail
	if axis.length()<12 or absf(axis.x)<axis.length()*.3:return {"error":"Bitte eine seitliche Aufnahme und korrekte Schnauzen-/Schwanzpunkte verwenden."}
	var u:=axis.normalized();var v:=Vector2(-u.y,u.x)*(-1 if u.x<0 else 1)
	if (points[3]-points[2]).dot(v)<=1 or (points[5]-points[4]).dot(v)<=1:return {"error":"Obere und untere Schwanzpunkte prüfen."}
	if (points[1]-tail).dot(u)<axis.length()*.45:return {"error":"Das Auge muss in der vorderen Körperhälfte liegen."}
	var targets: Array=[]
	for p in points:targets.append([p.x,p.y])
	var fit:=Body.fit(config.anchors,targets)
	if fit.is_empty():return {"error":"Diese Referenzpunkte erlauben keine stabile Ausrichtung."}
	return {"weights":fit,"targets":targets,"tail":tail,"u":u,"v":v,"length":axis.length()}
static func generate(source: Image, points: PackedVector2Array, contour: PackedVector2Array, side: String, resolution: int, path: String) -> Dictionary:
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/photo_import_projection.json"))
	var model: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/body_projection.json"))
	if FileAccess.get_sha256("res://models/pelvicachromis_taeniatus_male.glb")!=config.source_glb_sha256:return {"error":"UV-Daten passen nicht zum Modell."}
	var aligned:=alignment(points,config)
	if aligned.has("error"):return aligned
	var error:=Mask.validation_error(contour,source.get_size())
	if not error.is_empty():return {"error":error}
	var mask: Image=Mask.build(source,contour,0).mask
	for p in points:
		if not Rect2i(Vector2i.ZERO,source.get_size()).has_point(Vector2i(p)) or mask.get_pixelv(Vector2i(p)).r<.5:return {"error":"Alle Referenzpunkte müssen innerhalb der Fischkontur liegen."}
	# Existing six-point normalizer receives body extrema estimated by the twelve
	# anchors. No photo-specific coordinates or filenames participate.
	var six:=PackedVector2Array([points[0],points[1],points[2],points[3]])
	for i in [4,5]:six.append(Body.warp(Body.vec(model.anchors[i]),config.anchors,aligned.weights))
	var norm:=Normalizer.normalize(source,mask,six,0)
	if norm.has("error"):return norm
	var data: Dictionary=norm.data
	data["original_photo_path"]=path
	var normalized: Array=[]
	for p in points:
		var q: Vector2=Vector2((p-aligned.tail).dot(aligned.u),(p-aligned.tail).dot(aligned.v))*data.scale+Body.vec(data.offset_px)
		normalized.append([q.x,q.y])
	var fit:=Body.fit(config.anchors,normalized)
	model.anchors=config.anchors.duplicate(true);model.anchor_names=KEYS.duplicate()
	data.landmarks_normalized_px={}
	for i in range(12):data.landmarks_normalized_px[KEYS[i]]=normalized[i]
	var base:=Image.new()
	if base.load_png_from_buffer(FileAccess.get_file_as_bytes("res://textures/pelvicachromis_taeniatus_male_albedo.png"))!=OK:return {"error":"Basistextur fehlt."}
	base.resize(resolution,resolution,Image.INTERPOLATE_LANCZOS)
	var body:=Body.bake(base,norm.image,data,model)
	if body.has("error"):return body
	var fins: Dictionary=config.fins.duplicate(true)
	var polygons: Dictionary={};var masks: Dictionary={}
	for name in fins:
		var fin: Dictionary=fins[name]
		# Explicit single-photo fallback: opposite paired fin samples the visible
		# side's planar coordinates, while retaining its own distinct UV island.
		var visible_name: String=name
		fin.xy=fin.projection_xy.duplicate(true)
		if name.begins_with("Pelvic_") or name.begins_with("Pectoral_"):
			visible_name=name.get_slice("_",0)+"_Fin_"+("Left" if side=="left" else "Right")
			fin.xy=config.fins[visible_name].projection_xy.duplicate(true)
		fin["projection_guide"]=[]
		for xy in fin.xy:
			var q:=Body.warp(Body.vec(xy),config.anchors,fit)
			fin.projection_guide.append([q.x,q.y])
		var polygon:=PackedVector2Array()
		for index in fin.boundary:polygon.append(Body.vec(fin.projection_guide[index]))
		if Geometry2D.triangulate_polygon(polygon).is_empty():return {"error":"Die Ausrichtung faltet die Flosse %s. Bitte Referenzpunkte korrigieren." % name}
		polygons[name]=polygon
		var fm:=Image.create(norm.image.get_width(),norm.image.get_height(),false,Image.FORMAT_L8)
		Body.polygon_fill(fm,polygon,1)
		for y in range(fm.get_height()):
			for x in range(fm.get_width()):
				if norm.image.get_pixel(x,y).a<=.001:fm.set_pixel(x,y,Color.BLACK)
		masks[name]=fm
	var result:=Fin.bake(body.image,norm.image,data,model,fins,polygons,masks)
	if result.has("error"):return result
	var root:="user://photo_import/%d_%d" % [Time.get_unix_time_from_system(),Time.get_ticks_usec()]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))!=OK:return {"error":"Benutzerordner nicht beschreibbar."}
	var photo_path:=root+"/normalized.png";var texture_path:=root+"/albedo.png"
	if norm.image.save_png(photo_path)!=OK or mask.save_png(root+"/mask.png")!=OK or result.image.save_png(texture_path)!=OK:return {"error":"Bilder konnten nicht gespeichert werden."}
	var metadata: Dictionary={"schema_version":2,"photo_side":side,"photo_path":path,"landmarks_original_px":{},"normalized":data,"resolution":resolution,"texture_path":ProjectSettings.globalize_path(texture_path),"body_uv_slots":model.uv_slots_blender_v,"primary_body_island":side,"fallback_body_island":"right" if side=="left" else "left","opposite_side_fallback":"same photograph reflected in separate side UV island","paired_fin_fallback":"visible fin copied to distinct opposite UV island","stats":result.stats}
	for i in range(12):metadata.landmarks_original_px[KEYS[i]]=[points[i].x,points[i].y]
	metadata["contour_original_px"]=[]
	for p in contour:metadata.contour_original_px.append([p.x,p.y])
	var file:=FileAccess.open(root+"/project.json",FileAccess.WRITE)
	if file==null:return {"error":"Projektinformationen nicht schreibbar."}
	file.store_string(JSON.stringify(metadata,"\t"));file.close()
	return {"image":result.image,"metadata":metadata,"path":texture_path,"metadata_path":root+"/project.json"}
