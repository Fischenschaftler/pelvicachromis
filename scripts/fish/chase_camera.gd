extends Node3D
## Independent camera: smoothed position, target and look rotation.
@onready var camera: Camera3D=$Camera3D
var controller: Node3D
var config: Resource
var active := false
var dragging := false
var yaw := 0.0
var pitch := 0.0
var zoom_ratio := 1.0
var radius := 0.045
var fit_distance := 0.18
var distance := 0.18
var local_center := Vector3.ZERO
var look_target := Vector3.ZERO
func _ready() -> void:get_viewport().size_changed.connect(resize)
func configure(movement: Node3D,bounds: AABB) -> void:
	controller=movement;config=movement.config
	local_center=bounds.get_center();radius=bounds.size.length()*0.5
	resize()
func resize() -> void:
	if config==null:return
	var size:=get_viewport().get_visible_rect().size
	var vertical_angle:=deg_to_rad(camera.fov)*0.5
	var horizontal_angle:=atan(tan(vertical_angle)*size.x/maxf(size.y,1.0))
	fit_distance=maxf(radius*config.camera_default_radius_ratio,radius/sin(minf(vertical_angle,horizontal_angle)*config.camera_fit_margin))
	update_distance()
func update_distance() -> void:
	distance=clampf(fit_distance*zoom_ratio,radius*config.camera_min_radius_ratio,radius*config.camera_max_radius_ratio)
func begin() -> void:
	active=true;camera.make_current();reset_view()
func end() -> void:active=false;dragging=false
func reset_view() -> void:
	dragging=false;yaw=config.camera_default_yaw;pitch=config.camera_default_pitch;zoom_ratio=1.0
	resize();follow(0.0,true)
func _physics_process(delta: float) -> void:
	if active:follow(delta)
func follow(delta: float,snap: bool=false) -> void:
	var heading: Vector3=controller.heading()
	var side:=heading.cross(Vector3.UP).normalized()
	var target: Vector3=controller.global_transform*local_center
	var horizontal: Vector3=-heading*cos(yaw)+side*sin(yaw)
	var desired: Vector3=target+(horizontal*cos(pitch)+Vector3.UP*sin(pitch))*distance
	var response: float=1.0 if snap else 1.0-exp(-config.camera_response*delta)
	global_position=global_position.lerp(desired,response)
	look_target=look_target.lerp(target,response)
	var desired_basis:=Transform3D(Basis.IDENTITY,global_position).looking_at(look_target,Vector3.UP).basis
	var rotation_response: float=1.0 if snap else 1.0-exp(-config.camera_rotation_response*delta)
	global_basis=Basis(global_basis.get_rotation_quaternion().slerp(desired_basis.get_rotation_quaternion(),rotation_response))
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:dragging=false
func _unhandled_input(event: InputEvent) -> void:
	if not active:return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT and event.pressed:dragging=true
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_ratio=clampf(zoom_ratio*(config.camera_zoom_step if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/config.camera_zoom_step),config.camera_min_zoom_ratio,config.camera_max_zoom_ratio)
			update_distance()
		else:return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging:
		yaw=wrapf(yaw-event.relative.x*config.camera_mouse_sensitivity,-PI,PI)
		pitch=clampf(pitch+event.relative.y*config.camera_mouse_sensitivity,config.camera_min_pitch,config.camera_max_pitch)
		get_viewport().set_input_as_handled()
func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:dragging=false
