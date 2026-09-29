extends RefCounted
const AtlasCoverage=preload("res://scripts/atlas_coverage.gd")
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
# Photo coordinates only: body-axis similarity avoids extrapolating body TPS.
static func correspondence(fin: Dictionary, polygon: PackedVector2Array, anchors: Array, targets: Array) -> Dictionary:
	var tail: Vector2=(BodyBaker.vec(anchors[2])+BodyBaker.vec(anchors[3]))*.5
	var ptail: Vector2=(BodyBaker.vec(targets[2])+BodyBaker.vec(targets[3]))*.5
	var axis: Vector2=BodyBaker.vec(anchors[0])-tail
	var paxis: Vector2=BodyBaker.vec(targets[0])-ptail
	var rest:=PackedVector2Array()
	for pair in fin.xy:rest.append((BodyBaker.vec(pair)-tail).rotated(paxis.angle()-axis.angle())*(paxis.length()/axis.length())+ptail)
	if fin.has("projection_guide"):
		rest=PackedVector2Array()
		for pair in fin.projection_guide:rest.append(BodyBaker.vec(pair))
	var guide:=PackedVector2Array()
	for index in fin.boundary:guide.append(rest[index])
	var source:=polygon.duplicate()
	if area(source)*area(guide)<0:source.reverse()
	var matched:=matched_boundary(guide,source)
	var seed:=PackedVector2Array()
	for index in range(fin.xy.size()):
		var p:=Vector2.ZERO
		for j in range(guide.size()):p+=matched[j]*fin.harmonic_weights[index][j]
		seed.append(p)
	var optimized:=arap(fin,rest,seed)
	var repaired:=repair_direct(fin,optimized)
	if not repaired.valid:
		for step in range(1,11):
			var trial:=PackedVector2Array()
			for i in range(seed.size()):trial.append(optimized[i].lerp(seed[i],step/10.0))
			repaired=repair_direct(fin,trial)
			if repaired.valid:break
	if not repaired.valid:return {"error":"Die Flossenkontur erlaubt keine faltenfreie Projektion. Bitte die Kontur genauer setzen."}
	return {"vertices":repaired.vertices,"direct":true,"phase":0.0,"guide_rms_px":0.0,"repair_shift_px":repaired.shift,"method":"boundary constrained local similarity (ARAP)"}

static func nearest_parameter(p: Vector2, polygon: PackedVector2Array, cumulative: PackedFloat32Array) -> float:
	var best:=INF
	var value:=0.0
	for i in range(polygon.size()):
		var edge:=polygon[(i+1)%polygon.size()]-polygon[i]
		var t:=clampf((p-polygon[i]).dot(edge)/maxf(edge.length_squared(),.00001),0,1)
		var d:=p.distance_squared_to(polygon[i]+edge*t)
		if d<best:
			best=d
			value=(cumulative[i]+edge.length()*t)/cumulative[-1]
	return value

# Ordered local matches preserve base/tip positions; isotonic pooling prevents
# reversals. A small arc-length regularizer avoids collapsing at polygon corners.
static func matched_boundary(guide: PackedVector2Array, source: PackedVector2Array) -> PackedVector2Array:
	var gl:=lengths(guide);var sl:=lengths(source)
	var phase:=nearest_parameter(guide[0],source,sl)
	var blocks: Array=[]
	for i in range(guide.size()):
		var expected: float=gl[i]/gl[-1]
		var nearest:=nearest_parameter(guide[i],source,sl)-phase
		nearest+=round(expected-nearest)
		var value:=clampf(nearest,0,1)*.85+expected*.15
		blocks.append([i,i,value,1])
		while blocks.size()>1 and blocks[-2][2]>blocks[-1][2]:
			var b: Array=blocks.pop_back();var a: Array=blocks.pop_back()
			blocks.append([a[0],b[1],(a[2]*a[3]+b[2]*b[3])/(a[3]+b[3]),a[3]+b[3]])
	var matched:=PackedVector2Array();matched.resize(guide.size())
	for block in blocks:
		for i in range(block[0],block[1]+1):matched[i]=along(source,sl,block[2]*.98+(gl[i]/gl[-1])*.02+phase)
	return matched

# Local/global ARAP minimizes local shear and concentration of texture area.
# No mesh coordinates, UVs or deformation weights are changed.
static func arap(fin: Dictionary, rest: PackedVector2Array, seed: PackedVector2Array) -> PackedVector2Array:
	var points:=seed.duplicate()
	var links: Array=[];links.resize(points.size())
	for i in range(links.size()):links[i]={}
	for ids in fin.triangles:
		for k in range(3):
			var a: int=ids[k];var b: int=ids[(k+1)%3];var c: int=ids[(k+2)%3]
			var u:=rest[a]-rest[c];var v:=rest[b]-rest[c]
			var weight:=maxf(.001,u.dot(v)/maxf(.001,absf(u.cross(v))))*.5
			links[a][b]=float(links[a].get(b,0.0))+weight
			links[b][a]=float(links[b].get(a,0.0))+weight
	var boundary: Array=fin.boundary
	var rotations:=PackedFloat32Array();rotations.resize(points.size())
	for iteration in range(32):
		for i in range(points.size()):
			var dot:=0.0;var cross:=0.0
			for j in links[i]:
				var r:=rest[i]-rest[j];var q:=points[i]-points[j]
				dot+=links[i][j]*r.dot(q);cross+=links[i][j]*r.cross(q)
			rotations[i]=atan2(cross,dot)
		for sweep in range(12):
			for i in range(points.size()):
				if boundary.has(i):continue
				var sum:=Vector2.ZERO;var weight_sum:=0.0
				for j in links[i]:
					var r:=rest[i]-rest[j]
					var target: Vector2=points[j]+(r.rotated(rotations[i])+r.rotated(rotations[j]))*.5
					sum+=target*links[i][j];weight_sum+=links[i][j]
				points[i]=sum/weight_sum
	return points

static func repair_direct(fin: Dictionary, input: PackedVector2Array) -> Dictionary:
	var points:=input.duplicate()
	var total:=0.0
	for tri in fin.triangles:
		var a:=BodyBaker.vec(fin.uv[tri[0]]);var b:=BodyBaker.vec(fin.uv[tri[1]]);var c:=BodyBaker.vec(fin.uv[tri[2]])
		total+=(b-a).cross(c-a)*(points[tri[1]]-points[tri[0]]).cross(points[tri[2]]-points[tri[0]])
	var boundary: Array=fin.boundary
	var shift:=0.0
	for iteration in range(600):
		var repaired:=false
		for tri in fin.triangles:
			var a:=BodyBaker.vec(fin.uv[tri[0]]);var b:=BodyBaker.vec(fin.uv[tri[1]]);var c:=BodyBaker.vec(fin.uv[tri[2]])
			var direction:=signf((b-a).cross(c-a)*total)
			var area_now:float=(points[tri[1]]-points[tri[0]]).cross(points[tri[2]]-points[tri[0]])*direction
			if area_now>=-.01:continue
			var gradients: Array=[]
			var norm:=0.0
			for k in range(3):
				var edge:=points[tri[(k+2)%3]]-points[tri[(k+1)%3]]
				var g:=Vector2(-edge.y,edge.x)*direction if not boundary.has(tri[k]) else Vector2.ZERO
				gradients.append(g);norm+=g.length_squared()
			if norm<.00001:return {"valid":false}
			for k in range(3):
				points[tri[k]]+=gradients[k]*(.02-area_now)/norm
				shift=maxf(shift,points[tri[k]].distance_to(input[tri[k]]))
			if shift>50:return {"valid":false}
			repaired=true
		if not repaired:return {"valid":true,"vertices":points,"shift":shift}
	return {"valid":false}

# Nearest valid source coordinates are propagated across the mask's bounding box.
# This fills UV edge coverage without borrowing the old atlas or outside colours.
# Only the free lower anal edge is eligible. Reject a strip only when it
# continues the observed exterior colour up to a sustained interior edge.
# No brightness threshold: genuine pale edges with exterior contrast survive.
static func edge_mask(photo: Image, mask: Image, polygon: PackedVector2Array, original: Image=null, data: Dictionary={}) -> Dictionary:
	var refined: Image=mask.duplicate()
	var rejected:=0
	var direction:=signf(area(polygon))
	var limit:=clampi(roundi(sqrt(absf(area(polygon)))*.045),6,24)
	for i in range(polygon.size()):
		var a:=polygon[i];var b:=polygon[(i+1)%polygon.size()]
		var edge:=b-a
		var inward:=Vector2(-edge.y,edge.x).normalized()*direction
		if inward.y>-.35:continue
		for step in range(1,ceili(edge.length())):
			var p:=a+edge.normalized()*step
			var exterior:=Vector2i((p-inward*3).floor())
			var first:=Vector2i((p+inward).floor())
			if not Rect2i(Vector2i.ZERO,photo.get_size()).has_point(exterior) or not Rect2i(Vector2i.ZERO,photo.get_size()).has_point(first):continue
			var outside:=photo.get_pixelv(exterior);var start:=photo.get_pixelv(first)
			if original!=null and outside.a<.95:
				var local: Vector2=(Vector2(exterior)+Vector2(.5,.5)-BodyBaker.vec(data.offset_px))/float(data.scale)
				var q:=Vector2i((BodyBaker.vec(data.tail_midpoint_px)+BodyBaker.vec(data.basis_u)*local.x+BodyBaker.vec(data.basis_v)*local.y).floor())
				if Rect2i(Vector2i.ZERO,original.get_size()).has_point(q):outside=original.get_pixelv(q)
			if outside.a<.95 or start.a<.95:continue
			var background:=Vector3(outside.r,outside.g,outside.b)
			if Vector3(start.r,start.g,start.b).distance_to(background)>.12:continue
			var cut:=0
			for distance in range(2,limit):
				var sustained:=true
				for k in range(3):
					var q:=Vector2i((p+inward*(distance+k)).floor())
					if not Rect2i(Vector2i.ZERO,photo.get_size()).has_point(q) or mask.get_pixelv(q).r<.5:sustained=false;break
					var c:=photo.get_pixelv(q)
					if c.a<.95 or Vector3(c.r,c.g,c.b).distance_to(background)<.25:sustained=false;break
				if sustained:cut=distance;break
			if cut==0:continue
			for distance in range(cut):
				var q:=Vector2i((p+inward*distance).floor())
				if Rect2i(Vector2i.ZERO,photo.get_size()).has_point(q) and refined.get_pixelv(q).r>.5:
					refined.set_pixelv(q,Color.BLACK);rejected+=1
	return {"mask":refined,"rejected":rejected}

static func valid_lookup(photo: Image, mask: Image, polygon: PackedVector2Array) -> Dictionary:
	var lo:=polygon[0];var hi:=lo
	for p in polygon:lo=lo.min(p);hi=hi.max(p)
	var origin:=Vector2i(lo.floor())-Vector2i(32,32)
	var size:=Vector2i((hi-lo).ceil())+Vector2i(65,65)
	var nearest:=PackedInt32Array();nearest.resize(size.x*size.y);nearest.fill(-1)
	var width:=photo.get_width()
	for y in range(size.y):
		for x in range(size.x):
			var p:=origin+Vector2i(x,y)
			if p.x<0 or p.y<0 or p.x>=width or p.y>=photo.get_height():continue
			if mask.get_pixelv(p).r>.5 and photo.get_pixelv(p).a>.001:nearest[y*size.x+x]=p.y*width+p.x
	for pass_index in range(2):
		var step:=1 if pass_index==0 else -1
		for yy in range(size.y):
			var y:=yy if step==1 else size.y-1-yy
			for xx in range(size.x):
				var x:=xx if step==1 else size.x-1-xx
				var index:=y*size.x+x
				var p:=origin+Vector2i(x,y)
				var best:=INF
				if nearest[index]>=0:best=Vector2(p-Vector2i(nearest[index]%width,nearest[index]/width)).length_squared()
				for delta in [Vector2i(-step,0),Vector2i(-step,-step),Vector2i(0,-step),Vector2i(step,-step)]:
					var q: Vector2i=Vector2i(x,y)+delta
					if q.x<0 or q.y<0 or q.x>=size.x or q.y>=size.y:continue
					var candidate:=nearest[q.y*size.x+q.x]
					if candidate<0:continue
					var distance:=Vector2(p-Vector2i(candidate%width,candidate/width)).length_squared()
					if distance<best:best=distance;nearest[index]=candidate
	return {"origin":origin,"size":size,"nearest":nearest}

static func sample(photo: Image, mask: Image, p: Vector2, lookup: Dictionary) -> Color:
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
	var q: Vector2i=(Vector2i(p.floor())-lookup.origin).clamp(Vector2i.ZERO,lookup.size-Vector2i.ONE)
	var index: int=lookup.nearest[q.y*lookup.size.x+q.x]
	if index>=0:return photo.get_pixel(index%photo.get_width(),index/photo.get_width())
	return Color(0,0,0,0)

static func bake(base: Image, photo: Image, data: Dictionary, model: Dictionary, fins: Dictionary, polygons: Dictionary, masks: Dictionary) -> Dictionary:
	var targets: Array=[]
	for key in model.anchor_names:targets.append(data.landmarks_normalized_px[key])
	var weights:=BodyBaker.fit(model.anchors,targets)
	if weights.is_empty():return {"error":"Die Referenzpunkte erlauben keine stabile Flossenzuordnung."}
	var output: Image=base.duplicate();output.convert(Image.FORMAT_RGBA8)
	var coverage:=Image.create(base.get_width(),base.get_height(),false,Image.FORMAT_L8)
	var report: Dictionary={}
	# Original photo is read only as exterior context, never as texture source.
	var original: Image=null
	if data.has("original_photo_path") and FileAccess.file_exists(data.original_photo_path):
		original=Image.new()
		if original.load(data.original_photo_path)!=OK:original=null
	for name in fins:
		var fin: Dictionary=fins[name]
		var mapping:=correspondence(fin,polygons[name],model.anchors,targets)
		if mapping.has("error"):return {"error":name+": "+mapping.error}
		var sampling: Dictionary=edge_mask(photo,masks[name],polygons[name],original,data) if name=="Anal_Fin" else {"mask":masks[name],"rejected":0}
		var lookup:=valid_lookup(photo,sampling.mask,polygons[name])
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
					var color:=sample(photo,sampling.mask,q,lookup)
					if color.a<=.001:missed+=1;continue
					# Only authored fin transparency is intentional; cutout alpha is sampling validity.
					color.a=base.get_pixel(x,y).a
					output.set_pixel(x,y,color)
					fin_coverage.set_pixel(x,y,Color.WHITE)
					coverage.set_pixel(x,y,Color.WHITE)
					written+=1
		if folded>0:return {"error":"Die Kontur von %s verursacht %d gefaltete Teilflächen. Bitte den Umriss glätten und erneut markieren." % [name,folded]}
		if written<100 or float(missed)/maxi(1,written+missed)>.1:return {"error":"Zu wenig gültige Fotofläche für %s. Bitte Maske und Freistellung prüfen." % name}
		# Extend every unfilled pixel, including gaps deeper than the old 16px band.
		# Slots are disjoint, so neighbouring body/fin/eye islands cannot contaminate it.
		var fill_report:=AtlasCoverage.fill_slot(output,fin_coverage,fin.slot_blender_v,false,Color(0,0,0,0))
		report[name]={"atlas_fill":fill_report,"edge_pixels_rejected":sampling.rejected,"written":written,"fallback":missed,"folded_triangles":folded,"phase":mapping.phase,"guide_rms_px":mapping.guide_rms_px,"mapping":mapping.method,"repair_shift_px":mapping.repair_shift_px}
	return {"image":output,"coverage":coverage,"stats":report}
