extends Node3D

@export var rotation_sensitivity: float = 0.005
@export var zoom_step: float = 0.4
@export var min_distance: float = 2.5
@export var max_distance: float = 10.0
@export var min_pitch: float = -1.2
@export var max_pitch: float = 1.2

@onready var camera: Camera3D = $Camera3D

var dragging: bool = false
var yaw: float = 0.35
var pitch: float = -0.12
var distance: float = 5.0


func _ready() -> void:
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance - zoom_step, min_distance, max_distance)
			_update_camera()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance + zoom_step, min_distance, max_distance)
			_update_camera()
	elif event is InputEventMouseMotion and dragging:
		yaw -= event.relative.x * rotation_sensitivity
		pitch = clampf(pitch - event.relative.y * rotation_sensitivity, min_pitch, max_pitch)
		_update_camera()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		dragging = false


func _update_camera() -> void:
	rotation = Vector3(pitch, yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, distance)
