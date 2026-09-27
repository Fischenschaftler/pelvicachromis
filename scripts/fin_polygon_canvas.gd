extends "res://scripts/photo_polygon.gd"
var saved_polygons: Dictionary={}
const COLORS={"Caudal_Fin":Color(1,.8,.2),"Dorsal_Fin":Color(.2,1,.8),"Anal_Fin":Color(1,.4,.8)}
func _draw() -> void:
	for name in saved_polygons:
		var drawn:=PackedVector2Array()
		for p in saved_polygons[name]:drawn.append(to_display(p))
		if drawn.size()<3:continue
		draw_colored_polygon(drawn,Color(COLORS[name],.12))
		drawn.append(drawn[0]);draw_polyline(drawn,COLORS[name],2,true)
	super._draw()
