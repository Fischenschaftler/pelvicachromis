extends RefCounted
const KEYS := ["snout", "eye", "tail_upper", "tail_lower", "body_upper", "body_lower"]

static func analyze(points: PackedVector2Array) -> Dictionary:
	if points.size() != 6:
		return {"error": "Bitte alle sechs Referenzpunkte setzen."}
	for i in range(6):
		for j in range(i):
			if points[i].distance_to(points[j]) < 1.0:
				return {"error": "Referenzpunkte dürfen nicht identisch sein."}
	var tail := (points[2] + points[3]) * 0.5
	var axis := points[0] - tail
	if axis.length() < 4 or absf(axis.x) < axis.length() * 0.2:
		return {"error": "Schnauze und Schwanzstiel prüfen. Erwartet wird eine seitliche Aufnahme mit erkennbarem Kopf links oder rechts."}
	var u := axis.normalized()
	var mirrored := axis.x < 0
	var v := Vector2(-u.y, u.x) * (-1.0 if mirrored else 1.0)
	var height := (points[5] - points[4]).dot(v)
	if height < 2 or (points[3] - points[2]).dot(v) <= 0:
		return {"error": "Obere und untere Körper- beziehungsweise Schwanzpunkte prüfen."}
	if (points[1] - tail).dot(u) < axis.length() * 0.5:
		return {"error": "Die Augenmitte muss in der vorderen Körperhälfte liegen."}
	var landmarks := {}
	for i in range(6):
		landmarks[KEYS[i]] = [points[i].x, points[i].y]
	return {"schema_version": 1, "landmarks_original_px": landmarks,
		"direction": "head_left" if mirrored else "head_right", "mirrored": mirrored,
		"body_length_px": axis.length(), "body_height_px": height,
		"axis_angle_degrees": rad_to_deg(axis.angle()), "tail_midpoint_px": [tail.x, tail.y],
		"basis_u": [u.x, u.y], "basis_v": [v.x, v.y]}

static func cutout(source: Image, mask: Image) -> Image:
	var image: Image = source.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	var rgba := image.get_data()
	var alpha := mask.get_data()
	for i in range(alpha.size()):
		rgba[i * 4 + 3] = mini(rgba[i * 4 + 3], alpha[i])
	return Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, rgba)

static func normalize(source: Image, mask: Image, points: PackedVector2Array, revision: int) -> Dictionary:
	var data := analyze(points)
	if data.has("error"):
		return {"error": data.error, "revision": revision}
	var image := cutout(source, mask)
	var used := image.get_used_rect()
	if used.size == Vector2i.ZERO:
		return {"error": "Die Freistellung ist leer.", "revision": revision}
	var tail := (points[2] + points[3]) * 0.5
	var u := (points[0] - tail).normalized()
	var v := Vector2(data.basis_v[0], data.basis_v[1])
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in [Vector2(used.position), Vector2(used.end), Vector2(used.position.x, used.end.y), Vector2(used.end.x, used.position.y)]:
		var q := Vector2((p - tail).dot(u), (p - tail).dot(v))
		lo = lo.min(q)
		hi = hi.max(q)
	var span := hi - lo
	var scale := minf(1.0, 2040.0 / maxf(span.x, span.y))
	var dimensions := Vector2i((span * scale).ceil()) + Vector2i(8, 8)
	var offset := Vector2(4, 4) - lo * scale
	var output := Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
	# Inverse affine sampling. Premultiplied alpha avoids background colour fringes.
	for y in range(dimensions.y):
		for x in range(dimensions.x):
			var q := (Vector2(x + 0.5, y + 0.5) - offset) / scale
			var p := tail + u * q.x + v * q.y - Vector2(0.5, 0.5)
			var ix := floori(p.x)
			var iy := floori(p.y)
			var fx := p.x - ix
			var fy := p.y - iy
			var color := Color(0, 0, 0, 0)
			for dy in range(2):
				for dx in range(2):
					if ix + dx < 0 or iy + dy < 0 or ix + dx >= image.get_width() or iy + dy >= image.get_height():
						continue
					var sample := image.get_pixel(ix + dx, iy + dy)
					var weight := (fx if dx == 1 else 1.0 - fx) * (fy if dy == 1 else 1.0 - fy)
					color += Color(sample.r * sample.a, sample.g * sample.a, sample.b * sample.a, sample.a) * weight
			if color.a > 0.00001:
				color.r /= color.a
				color.g /= color.a
				color.b /= color.a
			output.set_pixel(x, y, color)
	data["scale"] = scale
	data["offset_px"] = [offset.x, offset.y]
	data["normalized_size"] = [dimensions.x, dimensions.y]
	data["landmarks_normalized_px"] = {}
	for i in range(6):
		var q := Vector2((points[i] - tail).dot(u), (points[i] - tail).dot(v)) * scale + offset
		data.landmarks_normalized_px[KEYS[i]] = [q.x, q.y]
	return {"image": output, "data": data, "revision": revision}
