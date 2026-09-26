extends RefCounted
## Landmark-constrained thin-plate spline and UV triangle rasterizer. No mesh writes.
static func vec(pair: Array) -> Vector2:
	return Vector2(pair[0], pair[1])

static func radial(a: Vector2, b: Vector2) -> float:
	var r := a.distance_squared_to(b)
	return r * log(maxf(r, 1.0e-12))

static func fit(anchors: Array, targets: Array) -> Array:
	var n := anchors.size()
	var matrix: Array = []
	for row in range(n + 3):
		var values: Array = []
		values.resize(n + 5)
		values.fill(0.0)
		matrix.append(values)
	for i in range(n):
		for j in range(n):
			matrix[i][j] = radial(vec(anchors[i]), vec(anchors[j]))
		matrix[i][n] = 1.0
		matrix[i][n + 1] = anchors[i][0]
		matrix[i][n + 2] = anchors[i][1]
		matrix[n][i] = 1.0
		matrix[n + 1][i] = anchors[i][0]
		matrix[n + 2][i] = anchors[i][1]
		matrix[i][n + 3] = targets[i][0]
		matrix[i][n + 4] = targets[i][1]
	for column in range(n + 3):
		var pivot := column
		for row in range(column + 1, n + 3):
			if absf(matrix[row][column]) > absf(matrix[pivot][column]):
				pivot = row
		if absf(matrix[pivot][column]) < 1.0e-10:
			return []
		var swap: Array = matrix[column]
		matrix[column] = matrix[pivot]
		matrix[pivot] = swap
		var divisor: float = matrix[column][column]
		for j in range(column, n + 5):
			matrix[column][j] /= divisor
		for row in range(n + 3):
			if row == column:
				continue
			var multiplier: float = matrix[row][column]
			for j in range(column, n + 5):
				matrix[row][j] -= multiplier * matrix[column][j]
	var weights: Array = []
	for row in range(n + 3):
		weights.append(Vector2(matrix[row][n + 3], matrix[row][n + 4]))
	return weights

static func warp(p: Vector2, anchors: Array, weights: Array) -> Vector2:
	var n := anchors.size()
	var q: Vector2 = weights[n] + weights[n + 1] * p.x + weights[n + 2] * p.y
	for i in range(n):
		q += weights[i] * radial(p, vec(anchors[i]))
	return q

static func polygon_fill(mask: Image, points: PackedVector2Array, value: float) -> void:
	for y in range(mask.get_height()):
		var intersections: Array[float] = []
		var scan := y + 0.5
		for i in range(points.size()):
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			if (a.y <= scan and b.y > scan) or (b.y <= scan and a.y > scan):
				intersections.append(a.x + (scan - a.y) * (b.x - a.x) / (b.y - a.y))
		intersections.sort()
		for i in range(0, intersections.size() - 1, 2):
			for x in range(clampi(ceili(intersections[i] - 0.5), 0, mask.get_width()), clampi(ceili(intersections[i + 1] - 0.5), 0, mask.get_width())):
				mask.set_pixel(x, y, Color(value, value, value))

static func bake(base: Image, photo: Image, landmarks: Dictionary, model: Dictionary) -> Dictionary:
	var targets: Array = []
	for key in model.anchor_names:
		if not landmarks.has("landmarks_normalized_px") or not landmarks.landmarks_normalized_px.has(key):
			return {"error": "Die gespeicherten Referenzpunkte sind unvollständig."}
		targets.append(landmarks.landmarks_normalized_px[key])
	var anchors: Array = model.anchors
	var weights := fit(anchors, targets)
	if weights.is_empty():
		return {"error": "Die Referenzpunkte erlauben keine stabile Körperabbildung."}
	var registration_error := 0.0
	for i in range(anchors.size()):
		registration_error = maxf(registration_error, warp(vec(anchors[i]), anchors, weights).distance_to(vec(targets[i])))
	var outline := PackedVector2Array()
	for pair in model.body_outline:
		outline.append(warp(vec(pair), anchors, weights))
	var body_mask := Image.create(photo.get_width(), photo.get_height(), false, Image.FORMAT_L8)
	polygon_fill(body_mask, outline, 1.0)
	# Conservative exclusions: photo fin roots and overlaid pectoral fins keep baseline skin.
	for name in model.fin_points:
		var points := PackedVector2Array()
		for pair in model.fin_points[name]:
			points.append(warp(vec(pair), anchors, weights))
		# The photo fin may not exactly match the model fin silhouette. Add a
		# conservative body-height-relative guard, especially around pectorals.
		var height: float = landmarks.body_height_px * landmarks.scale
		var guarded := PackedVector2Array()
		var lateral := height * (0.25 if String(name).begins_with("Pectoral") else 0.04)
		var above := height * (0.035 if String(name).begins_with("Pectoral") else 0.04)
		for point in points:
			guarded.append(point + Vector2(-lateral, -above))
			guarded.append(point + Vector2(lateral, -above))
			guarded.append(point + Vector2(-lateral, lateral))
			guarded.append(point + Vector2(lateral, lateral))
		polygon_fill(body_mask, Geometry2D.convex_hull(guarded), 0.0)
	for y in range(photo.get_height()):
		for x in range(photo.get_width()):
			if photo.get_pixel(x, y).a < 0.99:
				body_mask.set_pixel(x, y, Color.BLACK)
	var output: Image = base.duplicate()
	output.convert(Image.FORMAT_RGBA8)
	var coverage := Image.create(output.get_width(), output.get_height(), false, Image.FORMAT_L8)
	var atlas_size := Vector2(output.get_size())
	var written := 0
	var rejected := 0
	var cache := {}
	for tri in model.triangles:
		var uv: Array = tri.uv
		var a := vec(uv[0]) * atlas_size
		var b := vec(uv[1]) * atlas_size
		var c := vec(uv[2]) * atlas_size
		var denominator := (b - a).cross(c - a)
		if absf(denominator) < 0.000001:
			continue
		var sampled: Array[Vector2] = []
		for pair in tri.xy:
			var key := vec(pair)
			if not cache.has(key):
				cache[key] = warp(key, anchors, weights)
			sampled.append(cache[key])
		var before := (vec(tri.xy[1]) - vec(tri.xy[0])).cross(vec(tri.xy[2]) - vec(tri.xy[0]))
		var after := (sampled[1] - sampled[0]).cross(sampled[2] - sampled[0])
		if absf(before) > 1.0e-9 and before * after < -1.0e-7:
			return {"error": "Die Referenzpunkte würden die Körperprojektion falten. Bitte Kopf-, Rücken- und Bauchpunkte prüfen."}
		var low := Vector2i(a.min(b).min(c).floor()).max(Vector2i.ZERO)
		var high := Vector2i(a.max(b).max(c).ceil()).min(output.get_size() - Vector2i.ONE)
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var p := Vector2(x + 0.5, y + 0.5) - a
				var w1 := p.cross(c - a) / denominator
				var w2 := (b - a).cross(p) / denominator
				if w1 < -0.00001 or w2 < -0.00001 or w1 + w2 > 1.00001:
					continue
				var q: Vector2 = sampled[0] * (1 - w1 - w2) + sampled[1] * w1 + sampled[2] * w2
				var ix := floori(q.x - 0.5)
				var iy := floori(q.y - 0.5)
				if ix < 0 or iy < 0 or ix + 1 >= photo.get_width() or iy + 1 >= photo.get_height():
					rejected += 1
					continue
				if body_mask.get_pixel(ix, iy).r < 0.5 or body_mask.get_pixel(ix+1, iy).r < 0.5 or body_mask.get_pixel(ix, iy+1).r < 0.5 or body_mask.get_pixel(ix+1, iy+1).r < 0.5:
					rejected += 1
					continue
				var fx := q.x - 0.5 - ix
				var fy := q.y - 0.5 - iy
				var color := photo.get_pixel(ix, iy).lerp(photo.get_pixel(ix+1, iy), fx).lerp(photo.get_pixel(ix, iy+1).lerp(photo.get_pixel(ix+1, iy+1), fx), fy)
				color.a = output.get_pixel(x, y).a
				output.set_pixel(x, y, color)
				coverage.set_pixel(x, y, Color.WHITE)
				written += 1
	if written < 100:
		return {"error": "Zu wenig gültige Körperfläche. Bitte Freistellung und Referenzpunkte prüfen."}
	return {"image": output, "body_mask": body_mask, "coverage": coverage,
		"stats": {"written_samples": written, "fallback_samples": rejected, "max_anchor_error_px": registration_error,
		"method": "six-landmark thin-plate spline + actual rest-mesh UV triangles", "sides": "same photographed side used for both body islands", "fins": "baseline only"}}
