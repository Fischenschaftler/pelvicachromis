extends Node3D
## Screen-space movement only. No imported mesh, bone or animation resource is edited.
var config: Resource
var animation: AnimationPlayer
var velocity:=Vector2.ZERO
var stimulus_speed:=0.0
var yaw:=0.0
var target_yaw:=0.0
var angular_speed:=0.0
var animation_rate:=0.0
func configure(settings: Resource, player: AnimationPlayer) -> void:
	config=settings;animation=player;reset_stimulus()
func reset_stimulus() -> void:
	position=Vector3(0,0,config.plane_depth);rotation=Vector3.ZERO
	velocity=Vector2.ZERO;yaw=0;target_yaw=0;angular_speed=0
	stimulus_speed=config.stimulus_speed;animation_rate=config.idle_animation_speed
	animation.speed_scale=animation_rate
	animation.seek(0.0,true)
func step(delta: float, command: Dictionary) -> void:
	stimulus_speed=clampf(stimulus_speed+float(command.get("speed",0))*config.speed_adjustment*delta,config.min_speed,config.max_speed)
	var direction:=Vector2(float(command.get("x",0)),float(command.get("y",0))).limit_length()
	var target:=direction*stimulus_speed
	var slowing:=target.length()<velocity.length() or target.dot(velocity)<0
	velocity=velocity.move_toward(target,(config.deceleration if slowing else config.acceleration)*delta).limit_length(config.max_speed)
	position+=Vector3(velocity.x,velocity.y,0)*delta
	position.z=config.plane_depth
	var facing: float=float(command.get("facing",0))
	if facing==0:facing=direction.x
	if facing!=0:target_yaw=PI if facing<0 else 0.0
	var difference:=target_yaw-yaw
	var desired:=signf(difference)*minf(config.turn_speed,sqrt(2.0*config.turn_acceleration*absf(difference)))
	angular_speed=move_toward(angular_speed,desired,config.turn_acceleration*delta)
	var increment:=angular_speed*delta
	if absf(increment)>=absf(difference) and increment*difference>=0:
		yaw=target_yaw;angular_speed=0
	else:yaw=clampf(yaw+increment,0,PI)
	rotation=Vector3(0,yaw,0)
	var speed:=velocity.length()
	var rate: float=lerpf(config.idle_animation_speed,config.swim_animation_speed,clampf(speed/config.stimulus_speed,0,1))
	if speed>config.stimulus_speed and config.max_speed>config.stimulus_speed:
		rate=lerpf(config.swim_animation_speed,config.fast_animation_speed,(speed-config.stimulus_speed)/(config.max_speed-config.stimulus_speed))
	animation_rate=move_toward(animation_rate,rate,config.animation_response*delta)
	animation.speed_scale=animation_rate
func state() -> Dictionary:
	return {"position":[position.x,position.y,position.z],"orientation_y_radians":yaw,"target_yaw":target_yaw,"velocity":[velocity.x,velocity.y,0],"speed":velocity.length(),"stimulus_speed":stimulus_speed,"animation_speed":animation_rate,"speed_cm_s":velocity.length()/config.units_per_cm,"target_speed_cm_s":stimulus_speed/config.units_per_cm,"position_cm":[position.x/config.units_per_cm,position.y/config.units_per_cm]}
