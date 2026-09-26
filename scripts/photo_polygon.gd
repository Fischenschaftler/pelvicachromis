extends TextureRect
## Points are stored in original image pixels, never in widget coordinates.
signal close_requested
signal contour_changed
var original_size := Vector2i.ZERO
var points := PackedVector2Array()
var marking := false
var closed := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)

func image_rect() -> Rect2:
	if texture == null:
		return Rect2()
	var dimensions := texture.get_size()
	var factor := minf(size.x / dimensions.x, size.y / dimensions.y)
	var drawn := dimensions * factor
	return Rect2((size - drawn) * 0.5, drawn)

func to_original(local_point: Vector2) -> Vector2:
	var rect := image_rect()
	return (local_point - rect.position) / rect.size * Vector2(original_size)

func to_display(original_point: Vector2) -> Vector2:
	var rect := image_rect()
	return rect.position + original_point / Vector2(original_size) * rect.size

func clear_contour() -> void:
	points.clear()
	marking = false
	closed = false
	queue_redraw()
	contour_changed.emit()

func _gui_input(event: InputEvent) -> void:
	if not marking or texture == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		if not image_rect().has_point(event.position):
			return # Ignore letterboxing; it is not part of the photo.
		var point := to_original(event.position)
		if points.is_empty() or to_display(points[-1]).distance_to(event.position) > 3.0:
			if points.size() < 512:
				points.append(point)
		queue_redraw()
		contour_changed.emit()
		if event.double_click:
			close_requested.emit()

func _draw() -> void:
	if texture == null or points.is_empty():
		return
	var drawn := PackedVector2Array()
	for point in points:
		drawn.append(to_display(point))
	if closed and drawn.size() >= 3:
		draw_colored_polygon(drawn, Color(0.1, 0.8, 0.6, 0.15))
		drawn.append(drawn[0])
	if drawn.size() > 1:
		draw_polyline(drawn, Color(1, 0.8, 0.18), 2.0, true)
	for point in points:
		draw_circle(to_display(point), 4.0, Color(1, 0.85, 0.2))
