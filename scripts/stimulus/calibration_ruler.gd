extends Control
var pixel_length:=0.0
var reference_cm:=10.0
func _ready() -> void:custom_minimum_size.y=84;resized.connect(queue_redraw)
func fits() -> bool:return pixel_length>0 and pixel_length/get_global_transform_with_canvas().get_scale().x<=size.x-24
func _draw() -> void:
	if pixel_length<=0:return
	var length:=pixel_length/get_global_transform_with_canvas().get_scale().x
	if not fits():
		draw_string(ThemeDB.fallback_font,Vector2(12,32),"Referenzlinie passt nicht. Kleinere Sollänge wählen.",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.ORANGE);return
	var x: float=(size.x-length)*0.5
	draw_line(Vector2(x,35),Vector2(x+length,35),Color.WHITE,2,false)
	draw_line(Vector2(x,21),Vector2(x,49),Color.WHITE,2,false)
	draw_line(Vector2(x+length,21),Vector2(x+length,49),Color.WHITE,2,false)
	draw_string(ThemeDB.fallback_font,Vector2(x,73),"%.2f cm · %.2f Pixel (zwischen den Strichmitten)" % [reference_cm,pixel_length],HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
