extends "res://scripts/photo_polygon.gd"
## All editable coordinates refer to the original photo, including after resize.
signal landmarks_changed
const LABELS=["Schnauzenspitze","Augenmitte","Schwanzstiel oben","Schwanzstiel unten","Schwanzflosse oben","Schwanzflosse unten","Rückenflosse vorne","Rückenflosse hinten","Afterflosse vorne","Afterflosse hinten","Bauchflossenansatz","Bauchflossenspitze"]
var landmarks:=PackedVector2Array()
var landmark_confidence: Array=[]
var mode:="landmarks"
var drag_index:=-1
var locked:=false
func _gui_input(event: InputEvent) -> void:
	if locked or texture==null:return
	var array: PackedVector2Array=landmarks if mode=="landmarks" else points
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if not event.pressed:drag_index=-1;return
		for i in range(array.size()):
			if to_display(array[i]).distance_to(event.position)<11:
				drag_index=i;accept_event();return
		if mode=="mask":
			if not closed:super._gui_input(event)
			return
		if image_rect().has_point(event.position) and landmarks.size()<12:
			landmarks.append(to_original(event.position))
			if landmark_confidence.size()==landmarks.size()-1:landmark_confidence.append({"level":"MANUAL","method":"user input"})
			landmarks_changed.emit();queue_redraw();accept_event()
	elif event is InputEventMouseMotion and drag_index>=0:
		var p:=to_original(event.position).clamp(Vector2.ZERO,Vector2(original_size)-Vector2.ONE)
		if mode=="landmarks":
			landmarks[drag_index]=p
			if drag_index<landmark_confidence.size():landmark_confidence[drag_index]={"level":"MANUAL","method":"user correction"}
			landmarks_changed.emit()
		else:points[drag_index]=p;contour_changed.emit()
		queue_redraw();accept_event()
func _draw() -> void:
	super._draw()
	if texture==null:return
	for i in range(landmarks.size()):
		var p:=to_display(landmarks[i])
		draw_circle(p,5,Color.CYAN)
		if i<landmark_confidence.size() and landmark_confidence[i].get("level","")=="LOW":draw_arc(p,8,0,TAU,24,Color(1,.78,.3),1.5,true)
		var text:=str(i+1) if drag_index!=i else "%d %s" % [i+1,LABELS[i]]
		var text_width:=ThemeDB.fallback_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
		var pos: Vector2=Vector2(clampf(p.x+7,0,maxf(0,size.x-text_width-3)),clampf(p.y-6,14,size.y-2))
		draw_string_outline(ThemeDB.fallback_font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,3,Color.BLACK)
		draw_string(ThemeDB.fallback_font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
