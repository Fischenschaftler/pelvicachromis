extends RefCounted
const BodyBaker=preload("res://scripts/body_texture_baker.gd")
const NAMES=["Caudal_Fin","Dorsal_Fin","Anal_Fin"]
static func area(poly: PackedVector2Array) -> float:
	var sum:=0.0
	for i in range(poly.size()):sum+=poly[i].cross(poly[(i+1)%poly.size()])
	return sum*.5
static func lengths(poly: PackedVector2Array) -> PackedFloat32Array:
	var out:=PackedFloat32Array([0.0])
	for i in range(poly.size()):out.append(out[-1]+poly[i].distance_to(poly[(i+1)%poly.size()]))
	return out
static func along(poly: PackedVector2Array, cumulative: PackedFloat32Array, t: float) -> Vector2:
	var distance:=fposmod(t,1.0)*cumulative[-1]
	for i in range(poly.size()):
		if distance<=cumulative[i+1]:return poly[i].lerp(poly[(i+1)%poly.size()],(distance-cumulative[i])/maxf(.00001,cumulative[i+1]-cumulative[i]))
	return poly[0]
static func correspondence(fin: Dictionary, polygon: PackedVector2Array, anchors: Array, weights: Array) -> Dictionary:
	var guide:=PackedVector2Array()
	for index in fin.boundary:guide.append(BodyBaker.warp(BodyBaker.vec(fin.xy[index]),anchors,weights))
	var source:=polygon.duplicate()
	if area(source)*area(guide)<0:source.reverse()
	var gl:=lengths(guide)
	var sl:=lengths(source)
	var best:=INF
	var phase:=0.0
	for step in range(512):
		var offset:=step/512.0
		var cost:=0.0
		for i in range(guide.size()):cost+=guide[i].distance_squared_to(along(source,sl,gl[i]/gl[-1]+offset))
		if cost<best:best=cost;phase=offset
	var matched:=PackedVector2Array()
	for i in range(guide.size()):matched.append(along(source,sl,gl[i]/gl[-1]+phase))
	var candidate:=PackedVector2Array()
	for index in range(fin.xy.size()):
		var p:=BodyBaker.warp(BodyBaker.vec(fin.xy[index]),anchors,weights)
		for j in range(guide.size()):p+=(matched[j]-guide[j])*fin.harmonic_weights[index][j]
		candidate.append(p)
	var repaired:=repair_direct(fin,candidate)
	if repaired.valid:
		return {"vertices":repaired.vertices,"direct":true,"phase":phase,"guide_rms_px":sqrt(best/guide.size()),"repair_shift_px":repaired.shift}
	# Two disk parameterizations avoid folds even for concave photo polygons.
	# Model interior uses positive harmonic weights; the photo uses ear triangles.
	var boundary:=PackedVector2Array()
	var unit_gl:=PackedFloat32Array();var unit_sl:=PackedFloat32Array()
	for length in gl:unit_gl.append(length/gl[-1])
	for length in sl:unit_sl.append(length/sl[-1])
	for i in range(guide.size()):
		var angle:float=TAU*(unit_gl[i]+phase)
		boundary.append(Vector2(cos(angle),sin(angle)))
	var vertices:=PackedVector2Array()
	for row in fin.harmonic_weights:
		var p:=Vector2.ZERO
		for i in range(boundary.size()):p+=boundary[i]*row[i]
		vertices.append(p)
	var circle:=PackedVector2Array()
	for i in range(source.size()):circle.append(Vector2(cos(TAU*unit_sl[i]),sin(TAU*unit_sl[i])))
	return {"vertices":vertices,"direct":false,"repair_shift_px":0.0,"phase":phase,"guide_rms_px":sqrt(best/guide.size()),
		"model_lengths":unit_gl,"source_lengths":unit_sl,"source":source,"circle":circle,
		"triangles":Geometry2D.triangulate_polygon(source)}

static func repair_direct(fin: Dictionary, input: PackedVector2Array) -> Dictionary:
	var points:=input.duplicate()
	var total:=0.0
	for tri in fin.triangles:
		var a:=BodyBaker.vec(fin.uv[tri[0]]);var b:=BodyBaker.vec(fin.uv[tri[1]]);var c:=BodyBaker.vec(fin.uv[tri[2]])
		total+=(b-a).cross(c-a)*(points[tri[1]]-points[tri[0]]).cross(points[tri[2]]-points[tri[0]])
	var boundary: Array=fin.boundary
	var shift:=0.0
	for iteration in range(80):
		var repaired:=false
		for tri in fin.triangles:
			var a:=BodyBaker.vec(fin.uv[tri[0]]);var b:=BodyBaker.vec(fin.uv[tri[1]]);var c:=BodyBaker.vec(fin.uv[tri[2]])
			var direction:=signf((b-a).cross(c-a)*total)
			var area_now:float=(points[tri[1]]-points[tri[0]]).cross(points[tri[2]]-points[tri[0]])*direction
			if area_now>=-.01:continue
			var chosen:=-1
			for i in range(3):
				if not boundary.has(tri[i]):chosen=i;break
			if chosen<0:return {"valid":false}
			var index:int=tri[chosen]
			var origin:Vector2=points[tri[(chosen+1)%3]]
			var edge:Vector2=points[tri[(chosen+2)%3]]-origin
			var normal:=Vector2(-edge.y,edge.x)*direction
			points[index]+=normal*(.02-area_now)/maxf(.00001,normal.length_squared())
			shift=maxf(shift,points[index].distance_to(input[index]))
			if shift>10:return {"valid":false}
			repaired=true
		if not repaired:return {"valid":true,"vertices":points,"shift":shift}
	return {"valid":false}

static func chord_radius(t: float, cumulative: PackedFloat32Array) -> float:
	var i:=clampi(cumulative.bsearch(t)-1,0,cumulative.size()-2)
	return cos(PI*(cumulative[i+1]-cumulative[i]))/cos(TAU*t-PI*(cumulative[i]+cumulative[i+1]))

static func source_point(p: Vector2, mapping: Dictionary) -> Vector2:
	var t:=fposmod(p.angle()/TAU,1.0)
	var scale:=chord_radius(t,mapping.source_lengths)/chord_radius(fposmod(t-mapping.phase,1.0),mapping.model_lengths)
	var q:=p*scale
	var triangles: PackedInt32Array=mapping.triangles
	for i in range(0,triangles.size(),3):
		var ia:=triangles[i];var ib:=triangles[i+1];var ic:=triangles[i+2]
		var a:Vector2=mapping.circle[ia];var b:Vector2=mapping.circle[ib];var c:Vector2=mapping.circle[ic]
		var den:float=(b-a).cross(c-a)
		var u:float=(q-a).cross(c-a)/den;var v:float=(b-a).cross(q-a)/den
		if u>=-.00001 and v>=-.00001 and u+v<=1.00001:
			return mapping.source[ia]*(1-u-v)+mapping.source[ib]*u+mapping.source[ic]*v
	return Vector2(-100,-100)

static func sample(photo: Image, mask: Image, p: Vector2) -> Color:
	var ix:=floori(p.x-.5);var iy:=floori(p.y-.5)
	var fx:=p.x-.5-ix;var fy:=p.y-.5-iy
	var sum:=Color(0,0,0,0);var valid:=0.0
	for dy in range(2):
		for dx in range(2):
			var x:=ix+dx;var y:=iy+dy
			if x<0 or y<0 or x>=photo.get_width() or y>=photo.get_height():continue
			if mask.get_pixel(x,y).r<.5:continue
			var c:=photo.get_pixel(x,y)
			if c.a<=.001:continue
			var w:float=(fx if dx==1 else 1-fx)*(fy if dy==1 else 1-fy)
			sum+=Color(c.r*c.a,c.g*c.a,c.b*c.a,c.a)*w
			valid+=w
	if sum.a>.00001:
		return Color(sum.r/sum.a,sum.g/sum.a,sum.b/sum.a,sum.a/maxf(valid,.00001))
	# At the geometric boundary use only a nearby valid mask pixel, never background.
	for radius in range(1,5):
		for y in range(maxi(0,iy-radius),mini(photo.get_height(),iy+radius+1)):
			for x in range(maxi(0,ix-radius),mini(photo.get_width(),ix+radius+1)):
				if mask.get_pixel(x,y).r>.5 and photo.get_pixel(x,y).a>.001:return photo.get_pixel(x,y)
	return Color(0,0,0,0)

static func bake(base: Image, photo: Image, data: Dictionary, model: Dictionary, fins: Dictionary, polygons: Dictionary, masks: Dictionary) -> Dictionary:
	var targets: Array=[]
	for key in model.anchor_names:targets.append(data.landmarks_normalized_px[key])
	var weights:=BodyBaker.fit(model.anchors,targets)
	if weights.is_empty():return {"error":"Die Referenzpunkte erlauben keine stabile Flossenzuordnung."}
	var output: Image=base.duplicate();output.convert(Image.FORMAT_RGBA8)
	var coverage:=Image.create(base.get_width(),base.get_height(),false,Image.FORMAT_L8)
	var report: Dictionary={}
	for name in NAMES:
		var fin: Dictionary=fins[name]
		var mapping:=correspondence(fin,polygons[name],model.anchors,weights)
		var vertices: PackedVector2Array=mapping.vertices
		var sign_sum:=0.0
		for ids in fin.triangles:
			var a:=BodyBaker.vec(fin.uv[ids[0]]);var b:=BodyBaker.vec(fin.uv[ids[1]]);var c:=BodyBaker.vec(fin.uv[ids[2]])
			sign_sum+=(b-a).cross(c-a)*(vertices[ids[1]]-vertices[ids[0]]).cross(vertices[ids[2]]-vertices[ids[0]])
		var written:=0;var missed:=0;var folded:=0
		var fin_coverage:=Image.create(base.get_width(),base.get_height(),false,Image.FORMAT_L8)
		for ids in fin.triangles:
			var a:=BodyBaker.vec(fin.uv[ids[0]])*Vector2(base.get_size())
			var b:=BodyBaker.vec(fin.uv[ids[1]])*Vector2(base.get_size())
			var c:=BodyBaker.vec(fin.uv[ids[2]])*Vector2(base.get_size())
			var den:float=(b-a).cross(c-a)
			var det:float=(vertices[ids[1]]-vertices[ids[0]]).cross(vertices[ids[2]]-vertices[ids[0]])
			if det*signf(den*sign_sum) < -.01:folded+=1
			if absf(den)<.00001:continue
			var lo:=Vector2i(a.min(b).min(c).floor()).max(Vector2i.ZERO)
			var hi:=Vector2i(a.max(b).max(c).ceil()).min(base.get_size()-Vector2i.ONE)
			for y in range(lo.y,hi.y+1):
				for x in range(lo.x,hi.x+1):
					var p:=Vector2(x+.5,y+.5)-a
					var u:=p.cross(c-a)/den;var v:float=(b-a).cross(p)/den
					if u<-.00001 or v<-.00001 or u+v>1.00001:continue
					var q:Vector2=vertices[ids[0]]*(1-u-v)+vertices[ids[1]]*u+vertices[ids[2]]*v
					var color:=sample(photo,masks[name],q if mapping.direct else source_point(q,mapping))
					if color.a<=.001:missed+=1;continue
					color.a*=base.get_pixel(x,y).a
					output.set_pixel(x,y,color)
					fin_coverage.set_pixel(x,y,Color.WHITE)
					coverage.set_pixel(x,y,Color.WHITE)
					written+=1
		if folded>0:return {"error":"Die Kontur von %s verursacht %d gefaltete Teilflächen. Bitte den Umriss glätten und erneut markieren." % [name,folded]}
		if written<100 or float(missed)/maxi(1,written+missed)>.1:return {"error":"Zu wenig gültige Fotofläche für %s. Bitte Maske und Freistellung prüfen." % name}
		# Padding is limited to this fin's reserved atlas slot; no other islands change.
		var slot: Array=fin.slot_blender_v
		var rect:=Rect2i(Vector2i(ceili(slot[0]*base.get_width()),ceili((1-slot[3])*base.get_height())),Vector2i.ZERO)
		rect.end=Vector2i(floori(slot[2]*base.get_width()),floori((1-slot[1])*base.get_height()))
		for pass_index in range(4):
			var additions: Array=[]
			for y in range(rect.position.y+1,rect.end.y-1):
				for x in range(rect.position.x+1,rect.end.x-1):
					if fin_coverage.get_pixel(x,y).r>.5:continue
					for delta in [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]:
						if fin_coverage.get_pixel(x+delta.x,y+delta.y).r>.5:
							additions.append([Vector2i(x,y),output.get_pixel(x+delta.x,y+delta.y)])
							break
			for entry in additions:
				output.set_pixelv(entry[0],entry[1]);fin_coverage.set_pixelv(entry[0],Color.WHITE);coverage.set_pixelv(entry[0],Color.WHITE)
		report[name]={"written":written,"fallback":missed,"folded_triangles":folded,"phase":mapping.phase,"guide_rms_px":mapping.guide_rms_px,"mapping":"harmonic displacement" if mapping.direct else "triangulated disk","repair_shift_px":mapping.repair_shift_px}
	return {"image":output,"coverage":coverage,"stats":report}
