extends RefCounted
## Fill a reserved UV slot from generated samples only. Never sample the baseline.
## Full-slot extension also supplies filtering/mipmap padding outside mesh triangles.
static func fill_slot(image: Image, coverage: Image, slot: Array, opaque: bool, fallback: Color) -> Dictionary:
	var size:=image.get_size()
	var lo:=Vector2i(floori(slot[0]*size.x),floori((1-slot[3])*size.y)).max(Vector2i.ZERO)
	var hi:=Vector2i(ceili(slot[2]*size.x),ceili((1-slot[1])*size.y)).min(size)
	var width:=hi.x-lo.x;var height:=hi.y-lo.y
	var seen:=PackedByteArray();seen.resize(width*height)
	var queue:=PackedInt32Array();queue.resize(width*height)
	var tail:=0;var head:=0;var seeds:=0
	for y in range(height):
		for x in range(width):
			var p:=lo+Vector2i(x,y);var index:=y*width+x
			if coverage.get_pixelv(p).r>.5:
				seen[index]=1;queue[tail]=index;tail+=1;seeds+=1
	if seeds==0:
		if opaque:fallback.a=1.0
		image.fill_rect(Rect2i(lo,hi-lo),fallback)
		return {"seed_pixels":0,"extended_pixels":width*height,"fallback":"generated body mean"}
	while head<tail:
		var index:=queue[head];head+=1
		var x:=index%width;var y:=index/width
		var p:=lo+Vector2i(x,y);var color:=image.get_pixelv(p)
		if opaque:color.a=1.0;image.set_pixelv(p,color)
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var q: Vector2i=Vector2i(x,y)+delta
			if q.x<0 or q.y<0 or q.x>=width or q.y>=height:continue
			var next: int=q.y*width+q.x
			if seen[next]!=0:continue
			seen[next]=1;queue[tail]=next;tail+=1
			image.set_pixelv(lo+q,color)
	return {"seed_pixels":seeds,"extended_pixels":tail-seeds,"fallback":"nearest generated neighbour"}
