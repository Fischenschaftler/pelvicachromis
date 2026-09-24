extends Node3D

@export var swim_speed: float = 1.1
@export var sideways_amplitude: float = 0.08
@export var yaw_amplitude: float = 0.055
@export var roll_amplitude: float = 0.025

var elapsed: float = 0.0
var rest_position: Vector3
var rest_rotation: Vector3


func _ready() -> void:
	rest_position = position
	rest_rotation = rotation


func _process(delta: float) -> void:
	elapsed += delta * swim_speed
	position = rest_position + Vector3(0.0, 0.0, sin(elapsed) * sideways_amplitude)
	rotation = rest_rotation + Vector3(
		0.0,
		sin(elapsed + 0.5) * yaw_amplitude,
		sin(elapsed * 0.7) * roll_amplitude
	)
