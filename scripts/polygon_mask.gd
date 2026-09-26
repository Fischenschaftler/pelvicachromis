extends RefCounted
## Scanline rasterization at original resolution; pixel centres determine coverage.
static func validation_error(points: PackedVector2Array, size: Vector2i) -> String:
	if points.size() < 3:
		return "Bitte mindestens drei unterschiedliche Punkte setzen."
	var area := 0.0
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		if a.x < 0 or a.y < 0 or a.x > size.x or a.y > size.y:
			return "Die Kontur muss innerhalb des Fotos liegen."
		if a.distance_to(b) < 0.5:
			return "Zwei Konturpunkte liegen zu dicht beieinander. Bitte die Markierung zurücksetzen."
		area += a.cross(b)
		for j in range(i + 1, points.size()):
			if j == i + 1 or (i == 0 and j == points.size() - 1):
				continue
			if Geometry2D.segment_intersects_segment(a, b, points[j], points[(j + 1) % points.size()]) != null:
				return "Die Kontur überschneidet sich. Bitte eine Kontur ohne Kreuzungen setzen."
	if absf(area) < 8 or Geometry2D.triangulate_polygon(points).is_empty():
		return "Die Kontur umschließt keine gültige Fläche. Bitte weitere Punkte setzen oder zurücksetzen."
	return ""

static func build(source: Image, points: PackedVector2Array, revision: int) -> Dictionary:
	var width := source.get_width()
	var height := source.get_height()
	var pixels := PackedByteArray()
	pixels.resize(width * height)
	pixels.fill(0)
	for y in range(height):
		var intersections: Array[float] = []
		var scan := y + 0.5
		for i in range(points.size()):
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			if (a.y <= scan and b.y > scan) or (b.y <= scan and a.y > scan):
				intersections.append(a.x + (scan - a.y) * (b.x - a.x) / (b.y - a.y))
		intersections.sort()
		for i in range(0, intersections.size() - 1, 2):
			var start := clampi(ceili(intersections[i] - 0.5), 0, width)
			var end := clampi(ceili(intersections[i + 1] - 0.5), 0, width)
			for x in range(start, end):
				pixels[y * width + x] = 255
	var mask := Image.create_from_data(width, height, false, Image.FORMAT_L8, pixels)
	# Preview only is reduced; the saved mask retains all original pixels.
	var preview: Image = source.duplicate()
	if maxi(width, height) > 1600:
		var scale := 1600.0 / maxi(width, height)
		preview.resize(maxi(1, roundi(width * scale)), maxi(1, roundi(height * scale)), Image.INTERPOLATE_LANCZOS)
	preview.convert(Image.FORMAT_RGBA8)
	var preview_mask: Image = mask.duplicate()
	preview_mask.resize(preview.get_width(), preview.get_height(), Image.INTERPOLATE_NEAREST)
	var rgba := preview.get_data()
	var alpha := preview_mask.get_data()
	for i in range(alpha.size()):
		rgba[i * 4 + 3] = mini(rgba[i * 4 + 3], alpha[i])
	preview = Image.create_from_data(preview.get_width(), preview.get_height(), false, Image.FORMAT_RGBA8, rgba)
	# Trim only the preview, with a transparent margin. The mask stays full size.
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	var scale_xy := Vector2(preview.get_size()) / Vector2(width, height)
	var start := Vector2i((minimum * scale_xy).floor()) - Vector2i(8, 8)
	var end := Vector2i((maximum * scale_xy).ceil()) + Vector2i(8, 8)
	var region := Rect2i(start, end - start).intersection(Rect2i(Vector2i.ZERO, preview.get_size()))
	preview = preview.get_region(region)
	return {"mask": mask, "preview": preview, "revision": revision}
