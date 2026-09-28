extends RefCounted
## Deliberately conservative local heuristic; outputs suggestions, not labels.
const Mask=preload("res://scripts/polygon_mask.gd")
static func analyze(source: Image, forced_direction: String="") -> Dictionary:
	var image: Image=source.duplicate()
	var factor:=minf(1.0,360.0/maxi(image.get_width(),image.get_height()))
	image.resize(maxi(1,roundi(image.get_width()*factor)),maxi(1,roundi(image.get_height()*factor)),Image.INTERPOLATE_BILINEAR)
	var w:=image.get_width();var h:=image.get_height()
	if w<32 or h<24:return {"error":"Foto zu klein für einen zuverlässigen Vorschlag."}
	var bitmap:=BitMap.new();bitmap.create(Vector2i(w,h))
	# Row-wise border colours accommodate a dark tank above a light substrate.
	for y in range(h):
		var left:=Color(0,0,0);var right:=Color(0,0,0)
		var band:=maxi(2,w/18)
		for x in range(band):left+=image.get_pixel(x,y);right+=image.get_pixel(w-1-x,y)
		left/=float(band);right/=float(band)
		for x in range(1,w-1):
			var c:=image.get_pixel(x,y)
			var dl:=Vector3(c.r-left.r,c.g-left.g,c.b-left.b).length()
			var dr:=Vector3(c.r-right.r,c.g-right.g,c.b-right.b).length()
			var distance:=minf(dl,dr)
			bitmap.set_bit(x,y,c.a>.2 and distance>.19 and (c.v>.26 or c.s>maxf(left.s,right.s)+.12))
	bitmap.grow_mask(2,Rect2i(0,0,w,h));bitmap.grow_mask(-2,Rect2i(0,0,w,h))
	var polygons:=bitmap.opaque_to_polygons(Rect2i(0,0,w,h),1.4)
	var contour:=PackedVector2Array();var best:=0.0
	for polygon in polygons:
		var area:=0.0;var bounds:=Rect2(polygon[0],Vector2.ZERO)
		for i in range(polygon.size()):area+=polygon[i].cross(polygon[(i+1)%polygon.size()]);bounds=bounds.expand(polygon[i])
		area=absf(area)*.5
		if bounds.size.x<w*.22 or bounds.size.x<bounds.size.y*1.25 or area<w*h*.018 or area>w*h*.65:continue
		if bounds.position.x<=2 or bounds.end.x>=w-2 or bounds.position.y<=2 or bounds.end.y>=h-2:continue
		var score:=area*(1.0-bounds.get_center().distance_to(Vector2(w,h)*.5)/Vector2(w,h).length())
		if score>best:best=score;contour=polygon
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
	return suggest(source,contour,forced_direction)

static func suggest(source: Image, contour: PackedVector2Array, forced_direction: String="") -> Dictionary:
	var bounds:=Rect2(contour[0],Vector2.ZERO)
	for p in contour:bounds=bounds.expand(p)
	# A dark compact centre surrounded by a brighter iris is a possible eye.
	var left_height:=span(contour,bounds.position.x+bounds.size.x*.10)
	var right_height:=span(contour,bounds.end.x-bounds.size.x*.10)
	var right:=(right_height.y-right_height.x)<(left_height.y-left_height.x)
	if not forced_direction.is_empty():right=forced_direction=="right"
	var eye:=Vector2.ZERO;var eye_score:=0.0
	var step:=maxf(1.0,bounds.size.x/260.0)
	var radius:=maxf(2.0,bounds.size.x*.017)
	for iy in range(ceili(bounds.position.y/step),floori(bounds.end.y/step)):
		for ix in range(ceili(bounds.position.x/step),floori(bounds.end.x/step)):
			var p:=Vector2(ix,iy)*step
			var rx: float=(p.x-bounds.position.x)/bounds.size.x
			if (rx<.74 if right else rx>.26) or not Geometry2D.is_point_in_polygon(p,contour):continue
			var center:=luma(source,p);var ring:=0.0;var minimum:=1.0
			for j in range(12):
				var q:=p+Vector2.from_angle(j*TAU/12)*radius
				var value:=luma(source,q);ring+=value;minimum=minf(minimum,value)
			var score:=ring/12-center+maxf(0,minimum-center)*.5
			if center<.32 and score>eye_score:eye_score=score;eye=p
	var outline:=PackedVector2Array()
	for p in contour:outline.append(Vector2(p.x if right else -p.x,p.y))
	var xmin:=INF;var xmax:=-INF
	for p in outline:xmin=minf(xmin,p.x);xmax=maxf(xmax,p.x)
	var length:=xmax-xmin
	# Locate the narrow peduncle, excluding the outer caudal edge and head.
	var tip_span:=span(outline,xmax-length*.01)
	var rear_span:=span(outline,xmin+length*.08)
	var rear_center:=(rear_span.x+rear_span.y)*.5
	var front_center:=(tip_span.x+tip_span.y)*.5
	var tx:=xmin+length*.24;var narrow:=INF
	for i in range(22,33):
		var x:=xmin+length*i/100.0;var s:=body_span(outline,x,lerpf(rear_center,front_center,(x-xmin)/length))
		if s.y-s.x<narrow:narrow=s.y-s.x;tx=x
	var tail:=body_span(outline,tx,lerpf(rear_center,front_center,(tx-xmin)/length))
	var snout_span:=span(outline,xmax-length*.006)
	var snout:=Vector2(xmax-length*.009,(snout_span.x+snout_span.y)*.5)
	var tail_center:=Vector2(tx,(tail.x+tail.y)*.5)
	var axis:=(snout-tail_center).normalized()
	# Contour extrema in anatomical longitudinal regions; fin roots remain estimates.
	var caudal_top:=extreme(outline,xmin+length*.015,xmin+length*.18,true,tail.x-length*.025)
	var caudal_bottom:=extreme(outline,xmin+length*.015,xmin+length*.18,false)
	var dorsal_back:=Vector2(xmax,tail.x)
	for p in outline:
		if p.y<tail.x-length*.08 and p.x<dorsal_back.x:dorsal_back=p
	var anal_back:=Vector2(xmax,tail.y)
	for p in outline:
		if p.x>xmin+length*.19 and p.y>tail.y+length*.12 and p.x<anal_back.x:anal_back=p
	var dorsal_x:=xmin+length*.74
	var dorsal_front:=Vector2(dorsal_x,span(outline,dorsal_x).x)
	var anal_x:=xmin+length*.55
	var anal_front:=Vector2(anal_x,body_span(outline,anal_x,lerpf(tail_center.y,snout.y,(anal_x-tx)/(snout.x-tx))).y)
	var pelvic_x:=xmin+length*.75
	var pelvic_base:=Vector2(pelvic_x,span(outline,pelvic_x).y-length*.045)
	var pelvic_tip:=extreme(outline,xmin+length*.49,xmin+length*.72,false)
	var eye_direct:=eye_score>.16 and ((eye.x>bounds.get_center().x)==right)
	var eye_local:=Vector2(eye.x if right else -eye.x,eye.y) if eye_direct else snout-axis*length*.10+Vector2(0,-length*.045)
	var points:=PackedVector2Array([snout,eye_local,Vector2(tx,tail.x),Vector2(tx,tail.y),caudal_top,caudal_bottom,dorsal_front,dorsal_back,anal_front,anal_back,pelvic_base,pelvic_tip])
	# Keep samples inside the contour; never prefill landmarks in background pixels.
	for i in range(points.size()):
		var p:=points[i]
		var found:=false
		for radius_px in [length*.004,length*.008,length*.016]:
			for j in range(16):
				var candidate: Vector2=p+Vector2.from_angle(j*TAU/16)*radius_px
				if safely_inside(Vector2(candidate.x if right else -candidate.x,candidate.y),contour):
					p=candidate;found=true;break
			if found:break
		points[i]=Vector2(p.x if right else -p.x,p.y).clamp(Vector2.ZERO,Vector2(source.get_size())-Vector2.ONE)
	return {"fish_contour":contour,"head_direction":"right" if right else "left","eye_position":points[1],"suggested_landmarks":points,"confidence":{"contour":"Bitte prüfen","orientation":"Bitte prüfen","eye":"Erkannt – bitte prüfen" if eye_direct else "Geschätzt – bitte prüfen","eye_score":eye_score},"axis_start":(points[2]+points[3])*.5,"axis_end":points[0],"eye_detected":eye_direct}

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
static func extreme(contour: PackedVector2Array,start: float,end: float,upper: bool,min_y: float=-INF) -> Vector2:
	var best:=Vector2((start+end)*.5,INF if upper else -INF)
	for i in range(81):
		var x:=lerpf(start,end,i/80.0);var s:=span(contour,x);var y:=s.x if upper else s.y
		if y>=min_y and ((upper and y<best.y) or (not upper and y>best.y)):best=Vector2(x,y)
	if not is_finite(best.y):best.y=span(contour,best.x).x if upper else span(contour,best.x).y
	return best

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
