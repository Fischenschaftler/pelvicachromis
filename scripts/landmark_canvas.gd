extends "res://scripts/photo_polygon.gd"
## Full-photo coordinates even when the texture is downscaled.
signal landmarks_changed
const SHORT_LABELS := ["Schnauzenspitze", "Augenmitte", "Schwanzansatz oben", "Schwanzansatz unten", "Körper oben", "Körper unten"]
const LABELS := ["Schnauzenspitze", "Mittelpunkt des Auges", "Oberer Schwanzflossenansatz am Schwanzstiel", "Unterer Schwanzflossenansatz am Schwanzstiel", "Höchster Körperpunkt ohne Rückenflosse", "Tiefster Körperpunkt ohne Bauch-/Afterflossen"]
var mask: Image
var active := false
var feedback := ""

func _gui_input(event: InputEvent) -> void:
	if not active or texture == null or points.size() >= 6:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		if not image_rect().has_point(event.position):
			return
		var p := to_original(event.position)
		var pixel := Vector2i(p).clamp(Vector2i.ZERO, original_size - Vector2i.ONE)
		# Allow a small edge tolerance for anatomical points on the silhouette.
		var nearby := false
		for y in range(maxi(0, pixel.y - 3), mini(original_size.y, pixel.y + 4)):
			for x in range(maxi(0, pixel.x - 3), mini(original_size.x, pixel.x + 4)):
				if mask.get_pixel(x, y).r > 0.5:
					nearby = true
		if not nearby:
			feedback = "Bitte auf den freigestellten Fisch klicken."
		else:
			for old in points:
				if old.distance_to(p) < 1.0:
					feedback = "Bitte einen anderen Punkt wählen."
					landmarks_changed.emit()
					return
			points.append(p)
			feedback = ""
		queue_redraw()
		landmarks_changed.emit()

func _draw() -> void:
	if texture == null:
		return
	var rect := image_rect()
	var font := ThemeDB.fallback_font
	for i in range(points.size()):
		var p := to_display(points[i])
		draw_circle(p, 6, Color.BLACK)
		draw_circle(p, 4, Color(0.2, 1, 0.85))
		var label := "%d %s" % [i + 1, SHORT_LABELS[i]] if size.x >= 500 else str(i + 1)
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var offsets := [Vector2(10, 26), Vector2(0, -25), Vector2(-160, -16), Vector2(-155, 30), Vector2(-60, -30), Vector2(-35, 42)]
		var target: Vector2 = p + (offsets[i] if size.x >= 500 else Vector2(9, -8))
		var at := Vector2(clampf(target.x, 0, maxf(0, size.x - width)), clampf(target.y, 14, size.y - 2))
		if size.x >= 500:
			draw_line(p, at + Vector2(width * 0.5, -5), Color(0.2, 1, 0.85, 0.65), 1, true)
		draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color.BLACK)
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 1, 0.9))
