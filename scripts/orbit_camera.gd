extends Node3D
## UI-consumed events never start a camera drag.
@export var rotation_sensitivity: float = 0.005
@onready var camera: Camera3D = $Camera3D
var dragging := false
var yaw := 0.0
var pitch := 0.0
var distance := 0.16
var radius := 0.045
var zoom_ratio := 1.0
var fit_distance := 0.16
var half_extent := Vector3(0.04, 0.022, 0.006)
const PITCH_LIMIT := 1.25

func _ready() -> void:
	get_viewport().size_changed.connect(_resize)

func configure(bounds: AABB) -> void:
	position = bounds.get_center()
	radius = bounds.size.length() * 0.5
	half_extent = bounds.size * 0.5
	reset_view()

func reset_view() -> void:
	dragging = false
	yaw = 0.0
	pitch = 0.0
	zoom_ratio = 1.0
	_resize()

func _resize() -> void:
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var tangent := tan(deg_to_rad(camera.fov) * 0.5)
	var usable_height := maxf(0.40, (size.y - 180.0) / size.y)
	fit_distance = maxf(half_extent.x / (tangent * aspect * 0.82),
		half_extent.y / (tangent * usable_height * 0.90)) + half_extent.z
	fit_distance = maxf(fit_distance, radius * 1.65)
	_update_camera()

func _input(event: InputEvent) -> void:
	# Release is needed even when the pointer crosses a UI button.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			dragging = true
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 0.90 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.90
			zoom_ratio = clampf(zoom_ratio * factor, 0.45, 3.0)
			_update_camera()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging:
		yaw = wrapf(yaw - event.relative.x * rotation_sensitivity, -PI, PI)
		pitch = clampf(pitch - event.relative.y * rotation_sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
		_update_camera()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		dragging = false

func _update_camera() -> void:
	distance = maxf(radius * 1.45, fit_distance * zoom_ratio)
	rotation = Vector3(pitch, yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, distance)
