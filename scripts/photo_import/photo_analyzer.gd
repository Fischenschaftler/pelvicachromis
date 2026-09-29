extends RefCounted
## Deliberately conservative local heuristic; outputs suggestions, not labels.
const Mask=preload("res://scripts/polygon_mask.gd")
static func analyze(source: Image, forced_direction: String="") -> Dictionary:
	var image: Image=source.duplicate()
	var factor:=minf(1.0,360.0/maxi(image.get_width(),image.get_height()))
	image.resize(maxi(1,roundi(image.get_width()*factor)),maxi(1,roundi(image.get_height()*factor)),Image.INTERPOLATE_BILINEAR)
	var w:=image.get_width();var h:=image.get_height()
	if w<32 or h<24:return {"error":"Foto zu klein für einen zuverlässigen Vorschlag."}
	var contour:=PackedVector2Array();var best:=INF
	var template: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/anatomical_landmarks_male.json"))
	# First use the original row model. If it fails, test tilted background layers.
	for skew in [0.0,-12.0,12.0,-24.0,24.0]:
		var bitmap:=segment_bitmap(image,deg_to_rad(skew))
		var polygons:=bitmap.opaque_to_polygons(Rect2i(0,0,w,h),1.4)
		for polygon in polygons:
			var area:=0.0;var bounds:=Rect2(polygon[0],Vector2.ZERO)
			for i in range(polygon.size()):area+=polygon[i].cross(polygon[(i+1)%polygon.size()]);bounds=bounds.expand(polygon[i])
			area=absf(area)*.5
			if bounds.size.x<w*.22 or bounds.size.x<bounds.size.y*1.25 or area<w*h*.018 or area>w*h*.65:continue
			if bounds.position.x<=2 or bounds.end.x>=w-2 or bounds.position.y<=2 or bounds.end.y>=h-2:continue
			var fitted:=fit_template(polygon,template,forced_direction)
			var score: float=fitted.error
			if score<best:best=score;contour=polygon
		if skew==0.0 and not contour.is_empty():break
	if contour.is_empty():return {"error":"Kein klar abgegrenzter einzelner Fisch erkannt. Bitte die Kontur manuell zeichnen."}
	var scale_xy:=Vector2(source.get_size())/Vector2(w,h)
	for i in range(contour.size()):contour[i]*=scale_xy
	var middle:=contour.size()/2
	var first:=simplify(contour.slice(0,middle+1),maxf(1.0,source.get_width()*.002))
	var second:=contour.slice(middle);second.append(contour[0])
	second=simplify(second,maxf(1.0,source.get_width()*.002))
	first.remove_at(first.size()-1);second.remove_at(second.size()-1);first.append_array(second)
	if Mask.validation_error(first,source.get_size()).is_empty():contour=first
	if contour.size()>512 or not Mask.validation_error(contour,source.get_size()).is_empty():return {"error":"Kontur unsicher. Bitte manuell markieren."}
	return suggest(source,contour,forced_direction,true)

static func suggest(source: Image, contour: PackedVector2Array, forced_direction: String="",refine_mask: bool=false) -> Dictionary:
	var template: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/anatomical_landmarks_male.json"))
	var fitted:=fit_template(contour,template,forced_direction)
	var initial:=PackedVector2Array()
	for pair in template.anchors:initial.append(from_template(Vector2(pair[0],pair[1]),fitted))
	var points:=initial.duplicate()
	var confidence: Array=[]
	for i in range(12):confidence.append({"level":"LOW","method":"template","distance":0.0})
	var length: float=fitted.scale.x
	var u: Vector2=fitted.u;var v: Vector2=fitted.v
	var local:=PackedVector2Array()
	for p in contour:local.append(Vector2((p-fitted.origin).dot(u),(p-fitted.origin).dot(v)))
	# Refine snout only near its anatomical prior, against stable contour segments.
	var snout_candidate:=local_snap(initial[0],contour,INF)
	if snout_candidate.distance_to(initial[0])<length*.04:
		points[0]=snout_candidate;confidence[0]={"level":"HIGH","method":"local head contour"}
	var eye:=find_eye(source,contour,initial[1],length)
	if eye.detected:points[1]=eye.position;confidence[1]={"level":"HIGH","method":"pupil size/ring/position contrast"}
	# Peduncle: smoothed axis-perpendicular widths, bounded by template tail region.
	var prior: Vector2=(initial[2]+initial[3])*.5
	var prior_local:=Vector2((prior-fitted.origin).dot(u),(prior-fitted.origin).dot(v))
	var best_x:=prior_local.x;var best_score:=INF;var best_span:=Vector2.ZERO
	for k in range(-18,19):
		var x:=prior_local.x+k*length*.0025
		var s:=body_span(local,x,prior_local.y)
		var width:=0.0
		for offset in [-.008,0.0,.008]:
			var near:=body_span(local,x+float(offset)*length,prior_local.y);width+=near.y-near.x
		width/=3.0
		var rear:=body_span(local,x-length*.12,prior_local.y)
		# A true peduncle is narrow but followed backwards by a broader caudal fan.
		var score:=width+absf(x-prior_local.x)*.35+maxf(0,width-(rear.y-rear.x))*.5
		if width>maxf(length*.035,absf((initial[3]-initial[2]).dot(v))*.65) and width<length*.24 and score<best_score:best_score=score;best_x=x;best_span=s
	if is_finite(best_score):
		points[2]=fitted.origin+u*best_x+v*best_span.x
		points[3]=fitted.origin+u*best_x+v*best_span.y
		confidence[2]={"level":"MEDIUM","method":"smoothed peduncle width + anatomical window"};confidence[3]=confidence[2].duplicate()
		for i in [2,3]:
			if points[i].distance_to(initial[i])>length*.045:points[i]=initial[i];confidence[i]={"level":"LOW","method":"uncertain width; template fallback"}
	# Bounded contour refinement: tips may snap, roots stay close to their prior.
	for i in [4,5,6,7,8,9,10,11]:
		var radius: float=length*(.035 if i in [6,8,10] else .065)
		var candidate:=local_snap(initial[i],contour,radius)
		var moved:=candidate.distance_to(initial[i])
		if moved>0.01 and moved<radius*.98:
			points[i]=initial[i].lerp(candidate,.45) if i in [6,8,10] else candidate
			confidence[i]={"level":"LOW" if i in [6,8,10] or moved>length*.035 else "MEDIUM","method":"template + bounded contour","distance":moved/length}
	# Thin transparent pectoral tissue: anatomical ROI plus weak connected evidence.
	var pectoral:=PackedVector2Array()
	for pair in template.pectoral_region:pectoral.append(from_template(Vector2(pair[0],pair[1]),fitted))
	var refined:=extend_low_contrast_region(source,contour,pectoral) if refine_mask else {"contour":contour,"added":0}
	contour=refined.contour
	var caudal_added:=0
	if refine_mask:
		var caudal_region:=PackedVector2Array()
		for pair in template.caudal_region:caudal_region.append(from_template(Vector2(pair[0],pair[1]),fitted))
		var tail_refined:=extend_low_contrast_region(source,contour,caudal_region,.035)
		contour=tail_refined.contour;caudal_added=tail_refined.added
	var repairs:=plausibility(points,initial,confidence,u,v,length)
	# Place sampling points a small distance inside the polygon, never jump globally.
	for i in range(12):
		var safe:=inside_near(points[i],contour,length*.035)
		if safe.distance_to(points[i])>length*.018:confidence[i].level="LOW"
		points[i]=safe.clamp(Vector2.ZERO,Vector2(source.get_size())-Vector2.ONE)
	repairs.append_array(plausibility(points,initial,confidence,u,v,length))
	return {"fish_contour":contour,"head_direction":"right" if u.x>0 else "left","eye_position":points[1],"suggested_landmarks":points,"template_landmarks":initial,"landmark_confidence":confidence,"template_fit":{"scale":[fitted.scale.x,fitted.scale.y],"angle":u.angle(),"error":fitted.error},"body_height":fitted.scale.y*float(template.body_height),"tail_end":stable_tail_end(contour,u),"pectoral_region":pectoral,"pectoral_confidence":"LOW","pectoral_added_pixels":refined.added,"caudal_added_pixels":caudal_added,"plausibility_repairs":repairs,"confidence":{"contour":"Bitte prüfen","orientation":"Bitte prüfen","eye":"Erkannt – bitte prüfen" if eye.detected else "Template – bitte prüfen","eye_score":eye.score},"axis_start":(points[2]+points[3])*.5,"axis_end":points[0],"eye_detected":eye.detected}

static func from_template(p: Vector2,fit: Dictionary) -> Vector2:
	return fit.origin+fit.u*p.x*fit.scale.x+fit.v*p.y*fit.scale.y

static func resample(contour: PackedVector2Array,count: int) -> PackedVector2Array:
	var cumulative: Array[float]=[0.0]
	for i in range(contour.size()):cumulative.append(cumulative[-1]+contour[i].distance_to(contour[(i+1)%contour.size()]))
	var out:=PackedVector2Array();var segment:=0
	for i in range(count):
		var distance:=cumulative[-1]*i/count
		while segment<contour.size()-1 and cumulative[segment+1]<distance:segment+=1
		out.append(contour[segment].lerp(contour[(segment+1)%contour.size()],(distance-cumulative[segment])/maxf(.00001,cumulative[segment+1]-cumulative[segment])))
	return out

static func principal_angle(points: PackedVector2Array) -> float:
	var center:=Vector2.ZERO
	for p in points:center+=p
	center/=points.size()
	var xx:=0.0;var xy:=0.0;var yy:=0.0
	for p in points:
		var q:=p-center;xx+=q.x*q.x;xy+=q.x*q.y;yy+=q.y*q.y
	return .5*atan2(2*xy,xx-yy)

static func robust_bounds(points: PackedVector2Array) -> Rect2:
	var xs: Array[float]=[];var ys: Array[float]=[]
	for p in points:xs.append(p.x);ys.append(p.y)
	xs.sort();ys.sort()
	var trim:=maxi(0,points.size()/100)
	return Rect2(Vector2(xs[trim],ys[trim]),Vector2(xs[-1-trim]-xs[trim],ys[-1-trim]-ys[trim]))

static func fit_template(contour: PackedVector2Array,template: Dictionary,forced: String) -> Dictionary:
	var observed:=resample(contour,96)
	var canonical:=PackedVector2Array()
	for p in template.outline:canonical.append(Vector2(p[0],p[1]))
	canonical=resample(canonical,96)
	var bounds:=robust_bounds(canonical)
	var image_angle:=principal_angle(observed);var template_angle:=principal_angle(canonical)
	var best: Dictionary={"error":INF}
	for direction in [1.0,-1.0]:
		if not forced.is_empty() and (forced=="right")!=(direction>0):continue
		for step in range(-4,5):
			var angle: float=image_angle-template_angle*direction+deg_to_rad(step*3)
			var u: Vector2=Vector2.from_angle(angle)*direction;var v:=Vector2(-sin(angle),cos(angle))
			var local:=PackedVector2Array()
			for p in observed:local.append(Vector2(p.dot(u),p.dot(v)))
			var box:=robust_bounds(local)
			var scale:=Vector2(maxf(1,box.size.x/bounds.size.x),maxf(1,box.size.y/bounds.size.y))
			var origin: Vector2=u*(box.position.x-bounds.position.x*scale.x)+v*(box.position.y-bounds.position.y*scale.y)
			var fit: Dictionary={"u":u,"v":v,"scale":scale,"origin":origin}
			var transformed:=PackedVector2Array()
			for p in canonical:transformed.append(from_template(p,fit))
			var distances: Array[float]=[]
			for p in transformed:distances.append(p.distance_squared_to(local_snap(p,contour,INF)))
			for p in observed:distances.append(p.distance_squared_to(local_snap(p,transformed,INF)))
			distances.sort();var cost:=0.0
			# Trim isolated/transparent contour uncertainty, not whole fin regions.
			for i in range(int(distances.size()*.85)):cost+=distances[i]
			cost/=distances.size()*scale.x*scale.x
			if cost<float(best.error):fit.error=cost;best=fit
	return best

static func local_snap(p: Vector2,contour: PackedVector2Array,radius: float) -> Vector2:
	var best:=p;var distance:=radius*radius
	for i in range(contour.size()):
		var q:=Geometry2D.get_closest_point_to_segment(p,contour[i],contour[(i+1)%contour.size()])
		var d:=p.distance_squared_to(q)
		if d<distance:distance=d;best=q
	return best

static func find_eye(image: Image,contour: PackedVector2Array,expected: Vector2,length: float) -> Dictionary:
	var best:=expected;var best_score:=0.0
	var step:=maxf(1,length/250)
	for iy in range(-12,13):
		for ix in range(-12,13):
			var p:=expected+Vector2(ix,iy)*step
			if not Geometry2D.is_point_in_polygon(p,contour):continue
			for relative_radius in [.016,.022,.028]:
				var radius: float=length*relative_radius;var center:=luma(image,p)
				var ring:=0.0;var minimum:=1.0;var positive:=0
				for j in range(12):
					var value:=luma(image,p+Vector2.from_angle(j*TAU/12)*radius)
					ring+=value;minimum=minf(minimum,value)
					if value>center+.1:positive+=1
				# Several bright directions support roundness; position limits tail-spot confusion.
				var score: float=(ring/12-center+maxf(0,minimum-center)*.3)*(positive/12.0)-p.distance_to(expected)/length*.8
				if center<.34 and positive>=8 and score>best_score:best_score=score;best=p
	return {"position":best,"score":best_score,"detected":best_score>.22}

static func inside_near(p: Vector2,contour: PackedVector2Array,radius: float) -> Vector2:
	if safely_inside(p,contour):return p
	for k in range(1,9):
		for j in range(24):
			var q:=p+Vector2.from_angle(j*TAU/24)*radius*k/8.0
			if safely_inside(q,contour):return q
	for k in range(1,9):
		for j in range(32):
			var q:=p+Vector2.from_angle(j*TAU/32)*radius*k/8.0
			if Geometry2D.is_point_in_polygon(q.floor()+Vector2(.5,.5),contour):return q
	return p

static func plausibility(points: PackedVector2Array,prior: PackedVector2Array,confidence: Array,u: Vector2,v: Vector2,length: float) -> Array:
	var repaired: Array=[]
	# Every rule is evaluated in the anatomical frame, also for mirrored/tilted fish.
	var tests: Array=[[0,1,u,.03],[1,6,u,.04],[2,4,u,.06],[3,5,u,.06],[10,8,u,.04],[8,6,v,.08],[10,6,v,.08],[3,2,v,.025],[5,4,v,.08]]
	for rule in tests:
		var a: int=rule[0];var b: int=rule[1];var axis: Vector2=rule[2]
		if (points[a]-points[b]).dot(axis)<float(rule[3])*length:
			for i in [a,b]:points[i]=prior[i];confidence[i]={"level":"LOW","method":"anatomical rule fallback"};repaired.append(i)
	var tail: Vector2=(points[2]+points[3])*.5
	for i in [6,8,10]:
		var height: float=(points[i]-tail).dot(v)
		if (i==6 and height>-length*.03) or (i!=6 and height<length*.03):
			points[i]=prior[i];confidence[i]={"level":"LOW","method":"body-side rule fallback"};repaired.append(i)
	return repaired

static func extend_low_contrast_region(source: Image,contour: PackedVector2Array,region: PackedVector2Array,threshold: float=.085) -> Dictionary:
	var image: Image=source.duplicate();var factor:=minf(1,360.0/maxi(image.get_width(),image.get_height()))
	image.resize(maxi(1,roundi(image.get_width()*factor)),maxi(1,roundi(image.get_height()*factor)))
	var scale:=Vector2(image.get_size())/Vector2(source.get_size())
	var small:=PackedVector2Array();var roi:=PackedVector2Array()
	for p in contour:small.append(p*scale)
	for p in region:roi.append(p*scale)
	var mask: Image=Mask.build(image,small,0).mask
	var bounds:=Rect2(roi[0],Vector2.ZERO)
	for p in roi:bounds=bounds.expand(p)
	var low:=Vector2i(bounds.position.floor()).max(Vector2i.ONE);var high:=Vector2i(bounds.end.ceil()).min(image.get_size()-Vector2i.ONE)
	var added:=0
	for iteration in range(80):
		var additions: Array[Vector2i]=[]
		for y in range(low.y,high.y):
			var background:=image.get_pixel(1,y).lerp(image.get_pixel(image.get_width()-2,y),.5)
			for x in range(low.x,high.x):
				if mask.get_pixel(x,y).r>.5 or not Geometry2D.is_point_in_polygon(Vector2(x+.5,y+.5),roi):continue
				var c:=image.get_pixel(x,y)
				if c.a<.1 or Vector3(c.r-background.r,c.g-background.g,c.b-background.b).length()<threshold:continue
				if mask.get_pixel(x-1,y).r>.5 or mask.get_pixel(x+1,y).r>.5 or mask.get_pixel(x,y-1).r>.5 or mask.get_pixel(x,y+1).r>.5:additions.append(Vector2i(x,y))
		for p in additions:mask.set_pixelv(p,Color.WHITE);added+=1
		if additions.is_empty():break
	if added==0:return {"contour":contour,"added":0}
	var bitmap:=BitMap.new();bitmap.create(image.get_size())
	for y in range(image.get_height()):
		for x in range(image.get_width()):bitmap.set_bit(x,y,mask.get_pixel(x,y).r>.5)
	var polygons:=bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO,image.get_size()),1.4)
	var largest:=PackedVector2Array();var area:=0.0
	for polygon in polygons:
		var sum:=0.0
		for i in range(polygon.size()):sum+=polygon[i].cross(polygon[(i+1)%polygon.size()])
		if absf(sum)>area:area=absf(sum);largest=polygon
	for i in range(largest.size()):largest[i]/=scale
	if largest.size()>512 or not Mask.validation_error(largest,source.get_size()).is_empty():return {"contour":contour,"added":0}
	return {"contour":largest,"added":added}

static func luma(image: Image,p: Vector2) -> float:
	var c:=image.get_pixel(clampi(roundi(p.x),0,image.get_width()-1),clampi(roundi(p.y),0,image.get_height()-1))
	return c.r*.2126+c.g*.7152+c.b*.0722
static func span(contour: PackedVector2Array,x: float) -> Vector2:
	var low:=INF;var high:=-INF
	for i in range(contour.size()):
		var a:=contour[i];var b:=contour[(i+1)%contour.size()]
		if (a.x<=x and b.x>x) or (b.x<=x and a.x>x):
			var y:=lerpf(a.y,b.y,(x-a.x)/(b.x-a.x));low=minf(low,y);high=maxf(high,y)
	if not is_finite(low):
		var nearest:=contour[0]
		for p in contour:
			if absf(p.x-x)<absf(nearest.x-x):nearest=p
		return Vector2(nearest.y,nearest.y)
	return Vector2(low,high)
static func body_span(contour: PackedVector2Array,x: float,center_y: float) -> Vector2:
	var hits: Array[float]=[]
	for i in range(contour.size()):
		var a:=contour[i];var b:=contour[(i+1)%contour.size()]
		if (a.x<=x and b.x>x) or (b.x<=x and a.x>x):hits.append(lerpf(a.y,b.y,(x-a.x)/(b.x-a.x)))
	hits.sort()
	var best:=span(contour,x);var distance:=INF
	for i in range(0,hits.size()-1,2):
		var d:=absf(clampf(center_y,hits[i],hits[i+1])-center_y)
		if d<distance:distance=d;best=Vector2(hits[i],hits[i+1])
	return best


static func simplify(points: PackedVector2Array,tolerance: float) -> PackedVector2Array:
	if points.size()<3:return points
	var distance:=0.0;var split:=0
	for i in range(1,points.size()-1):
		var closest:=Geometry2D.get_closest_point_to_segment(points[i],points[0],points[-1])
		var d:=points[i].distance_to(closest)
		if d>distance:distance=d;split=i
	if distance<=tolerance:return PackedVector2Array([points[0],points[-1]])
	var a:=simplify(points.slice(0,split+1),tolerance)
	var b:=simplify(points.slice(split),tolerance);a.remove_at(a.size()-1);a.append_array(b);return a

static func safely_inside(p: Vector2,polygon: PackedVector2Array) -> bool:
	# Raster masks use pixel centres. Stay clear of the boundary by a full pixel.
	for offset in [Vector2.ZERO,Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		if not Geometry2D.is_point_in_polygon(p.floor()+Vector2(.5,.5)+offset,polygon):return false
	return true


static func stable_tail_end(contour: PackedVector2Array,u: Vector2) -> Vector2:
	var samples:=resample(contour,160)
	var ordered: Array[Vector2]=[]
	for p in samples:ordered.append(p)
	ordered.sort_custom(func(a: Vector2,b: Vector2):return a.dot(u)<b.dot(u))
	var point:=Vector2.ZERO
	for i in range(4):point+=ordered[i]
	return point/4.0

static func segment_bitmap(image: Image,skew: float) -> BitMap:
	var w:=image.get_width();var h:=image.get_height()
	var left: Array[Color]=[];var right: Array[Color]=[]
	var band:=maxi(2,w/18)
	for y in range(h):
		var a:=Color(0,0,0);var b:=Color(0,0,0)
		for x in range(band):a+=image.get_pixel(x,y);b+=image.get_pixel(w-1-x,y)
		left.append(a/float(band));right.append(b/float(band))
	var bitmap:=BitMap.new();bitmap.create(image.get_size())
	for y in range(h):
		for x in range(1,w-1):
			var a:=left[clampi(roundi(y+(x-band*.5)*tan(skew)),0,h-1)]
			var b:=right[clampi(roundi(y+(x-w+band*.5)*tan(skew)),0,h-1)]
			var c:=image.get_pixel(x,y)
			var distance:=minf(Vector3(c.r-a.r,c.g-a.g,c.b-a.b).length(),Vector3(c.r-b.r,c.g-b.g,c.b-b.b).length())
			bitmap.set_bit(x,y,c.a>.2 and distance>.19 and (c.v>.26 or c.s>maxf(a.s,b.s)+.12))
	bitmap.grow_mask(2,Rect2i(0,0,w,h));bitmap.grow_mask(-2,Rect2i(0,0,w,h));return bitmap
