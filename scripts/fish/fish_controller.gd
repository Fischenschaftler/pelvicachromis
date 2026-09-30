extends Node3D
## Moves the imported instance as a whole. No mesh, bone or weight edits.
const Config=preload("res://scripts/fish/fish_movement_config.gd")
var config: Resource=Config.new()
var active := false
var sample_input := true
var speed := 0.0
var vertical_speed := 0.0
var turn_speed := 0.0
var yaw := 0.0
var pitch := 0.0
var bank := 0.0
var velocity := Vector3.ZERO
var animation_rate := 1.0
var animation_player: AnimationPlayer
var neutral_transform := Transform3D.IDENTITY
var input_values := Vector4.ZERO # forward, brake, turn, climb
var boost := 0.0
var input_suspended := false

func configure(player: AnimationPlayer) -> void:
	animation_player=player
	neutral_transform=transform
func begin() -> void:
	active=true
	reset_fish_control()
func end() -> void:
	active=false
	reset_fish_control()
func reset_fish_control() -> void:
	transform=neutral_transform
	speed=config.hover_speed;vertical_speed=0.0;turn_speed=0.0
	yaw=0.0;pitch=0.0;bank=0.0;velocity=Vector3.ZERO
	set_movement_input(0.0,0.0,0.0,0.0,0.0)
	animation_rate=config.idle_animation_speed if active else 1.0
	if animation_player!=null:animation_player.speed_scale=animation_rate
func set_movement_input(forward: float,brake: float,turn: float,climb: float,fast: float) -> void:
	input_values=Vector4(clampf(forward,0.0,1.0),clampf(brake,0.0,1.0),clampf(turn,-1.0,1.0),clampf(climb,-1.0,1.0))
	boost=clampf(fast,0.0,1.0)
func _physics_process(delta: float) -> void:
	if not active:return
	if sample_input:
		if input_suspended:
			set_movement_input(0.0,0.0,0.0,0.0,0.0)
		else:
			set_movement_input(Input.get_action_strength("fish_forward"),Input.get_action_strength("fish_brake"),
				Input.get_axis("fish_turn_right","fish_turn_left"),Input.get_axis("fish_down","fish_up"),Input.get_action_strength("fish_boost"))
	step_movement(delta)
func step_movement(delta: float) -> void:
	if not active:return
	var target_speed: float=lerpf(config.cruise_speed,config.fast_speed,boost)*input_values.x
	var rate: float=config.acceleration if target_speed>speed else config.coast_deceleration
	if input_values.y>0.0:
		target_speed=config.hover_speed;rate=lerpf(config.coast_deceleration,config.brake_deceleration,input_values.y)
	speed=clampf(move_toward(speed,target_speed,rate*delta),config.hover_speed,config.fast_speed)
	var target_turn: float=input_values.z*config.max_turn_speed
	var turn_rate: float=config.turn_acceleration if not is_zero_approx(input_values.z) else config.turn_deceleration
	turn_speed=move_toward(turn_speed,target_turn,turn_rate*delta)
	yaw=wrapf(yaw+turn_speed*delta,-PI,PI)
	var target_vertical: float=input_values.w*config.max_vertical_speed
	var vertical_rate: float=config.vertical_acceleration if not is_zero_approx(input_values.w) else config.vertical_deceleration
	vertical_speed=move_toward(vertical_speed,target_vertical,vertical_rate*delta)
	# The yaw frame supplies heading; climb is separate and pitch is a visual,
	# bounded response to that climb, avoiding double vertical displacement.
	var direction: Vector3=neutral_transform.basis*Basis(Vector3.UP,yaw)*config.local_forward.normalized()
	velocity=(direction*speed+Vector3.UP*vertical_speed).limit_length(config.fast_speed)
	apply_displacement(velocity*delta)
	var response: float=1.0-exp(-config.attitude_response*delta)
	var target_pitch: float=clampf(atan2(vertical_speed,maxf(speed,config.pitch_reference_speed)),-config.max_pitch,config.max_pitch)
	pitch=lerpf(pitch,target_pitch,response)
	bank=lerpf(bank,-turn_speed/config.max_turn_speed*config.max_bank,response)
	# +X forward, +Y up: pitch rotates around local +Z, bank around +X.
	basis=neutral_transform.basis*Basis(Vector3.UP,yaw)*Basis(Vector3.BACK,pitch)*Basis(config.local_forward.normalized(),bank)
	var effective_speed:=velocity.length()
	var target_animation: float
	if effective_speed<=config.cruise_speed:
		target_animation=lerpf(config.idle_animation_speed,config.normal_animation_speed,effective_speed/config.cruise_speed)
	else:
		target_animation=lerpf(config.normal_animation_speed,config.fast_animation_speed,clampf((effective_speed-config.cruise_speed)/(config.fast_speed-config.cruise_speed),0.0,1.0))
	animation_rate=lerpf(animation_rate,target_animation,1.0-exp(-config.animation_response*delta))
	if animation_player!=null:animation_player.speed_scale=animation_rate
func apply_displacement(displacement: Vector3) -> void:
	# Future aquarium limits / collision sweep belong here, not inside the rig.
	position+=displacement
func heading() -> Vector3:
	return (neutral_transform.basis*Basis(Vector3.UP,yaw)*config.local_forward.normalized()).normalized()
func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		input_suspended=true;set_movement_input(0.0,0.0,0.0,0.0,0.0)
	elif what==NOTIFICATION_WM_WINDOW_FOCUS_IN:input_suspended=false
