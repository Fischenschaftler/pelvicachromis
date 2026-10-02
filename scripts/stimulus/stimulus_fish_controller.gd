extends Node3D
## Calibrated planar motion with a temporary post-animation pose modifier.
var config: Resource
var animation: AnimationPlayer
var velocity:=Vector2.ZERO
var stimulus_speed:=0.0
var yaw:=0.0
var target_yaw:=0.0
var angular_speed:=0.0
var actual_turn_rate:=0.0
var target_turn_rate:=0.0
var path_turn_rate:=0.0
var turn_bend_amount:=0.0
var animation_rate:=0.0
var turn_modifier: SkeletonModifier3D
var turning:=false
var turn_peak:=0.0
var turn_start_yaw:=0.0
var events: Array=[]
func configure(settings: Resource, player: AnimationPlayer) -> void:
	config=settings;animation=player;reset_stimulus()
func attach_pose(model: Node3D) -> String:
	detach_pose()
	var rigs:=model.find_children("*","Skeleton3D",true,false)
	if rigs.size()!=1:return "Kurvenpose benötigt genau ein bestehendes Skeleton."
	var modifier:=preload("res://scripts/stimulus/turn_pose_modifier.gd").new()
	var error: String=modifier.bind(self,rigs[0])
	if not error.is_empty():modifier.free();return error
	rigs[0].add_child(modifier);turn_modifier=modifier;return ""
func detach_pose() -> void:
	if is_instance_valid(turn_modifier):turn_modifier.active=false;turn_modifier.free()
	turn_modifier=null
func reset_stimulus() -> void:
	position=Vector3(0,0,config.plane_depth);rotation=Vector3.ZERO
	velocity=Vector2.ZERO;yaw=0;target_yaw=0;angular_speed=0
	target_turn_rate=0;actual_turn_rate=0;path_turn_rate=0;turn_bend_amount=0;turning=false;turn_peak=0;events.clear()
	stimulus_speed=config.stimulus_speed;animation_rate=config.idle_animation_speed
	if animation!=null:animation.speed_scale=animation_rate;animation.seek(0.0,true)
func radius_for_speed(speed_cm_s: float) -> float:
	return config.minimum_turn_radius_cm+config.turn_radius_speed_factor*speed_cm_s*speed_cm_s
func step(delta: float, command: Dictionary) -> void:
	if delta<=0:return
	if command.has("target_speed_cm_s"):
		stimulus_speed=clampf(float(command.target_speed_cm_s)*config.units_per_cm,0,config.max_speed)
	else:stimulus_speed=clampf(stimulus_speed+float(command.get("speed",0))*config.speed_adjustment*delta,config.min_speed,config.max_speed)
	var direction:=Vector2(float(command.get("x",0)),float(command.get("y",0))).limit_length()
	var facing: float=float(command.get("facing",0))
	if facing==0:facing=direction.x
	if facing!=0:target_yaw=PI if facing<0 else 0.0
	var difference:=target_yaw-yaw
	var previous_speed:=velocity.length()
	# Reduce thrust while the head is still facing against the requested direction.
	var alignment:=1.0 if direction.x==0 else 0.15+0.85*(1.0-absf(difference)/PI)
	var requested_speed:=direction.length()*stimulus_speed*alignment
	var speed:=move_toward(previous_speed,requested_speed,(config.deceleration if requested_speed<previous_speed else config.acceleration)*delta)
	path_turn_rate=0.0
	if speed>0:
		var heading:=direction.angle() if previous_speed<0.0000001 else velocity.angle()
		if direction.length_squared()>0 and previous_speed>=0.0000001:
			var error:=wrapf(direction.angle()-heading,-PI,PI)
			if absf(error)<.000001:error=0.0
			if absf(absf(error)-PI)<.000001:error=PI if difference>=0 else -PI
			var cm_speed: float=speed/config.units_per_cm
			var limit:=minf(config.turn_speed,cm_speed/radius_for_speed(maxf(previous_speed,speed)/config.units_per_cm))
			var change:=clampf(error,-limit*delta,limit*delta)
			path_turn_rate=change/delta;heading+=change
		velocity=Vector2.from_angle(heading)*speed
	else:velocity=Vector2.ZERO
	position+=Vector3(velocity.x,velocity.y,0)*delta;position.z=config.plane_depth
	var cm_speed: float=speed/config.units_per_cm
	# A stationary fish can pivot. With speed, body yaw is limited by the radius envelope.
	var yaw_limit:=minf(config.turn_speed,maxf(config.turn_speed*exp(-cm_speed),cm_speed/radius_for_speed(cm_speed)))
	target_turn_rate=signf(difference)*minf(yaw_limit,sqrt(2.0*config.turn_acceleration*absf(difference)))
	var old_yaw:=yaw
	angular_speed=move_toward(angular_speed,target_turn_rate,config.turn_acceleration*delta)
	var increment:=angular_speed*delta
	if absf(increment)>=absf(difference) and increment*difference>=0:yaw=target_yaw;angular_speed=0
	else:yaw=clampf(yaw+increment,0,PI)
	var actual: float=(yaw-old_yaw)/delta
	actual_turn_rate=actual
	rotation=Vector3(0,yaw,0)
	var driving_rate:=actual if absf(actual)>=absf(path_turn_rate) else path_turn_rate
	var dynamic_gain: float=1.0+config.turn_bend_speed_gain*clampf(cm_speed/config.max_speed_cm_s,0,1)
	var desired_bend:=clampf(-driving_rate*config.turn_bend_strength*dynamic_gain,-config.max_turn_bend,config.max_turn_bend)
	var response: float=config.turn_bend_response if absf(desired_bend)>absf(turn_bend_amount) else config.turn_bend_recovery
	turn_bend_amount=lerpf(turn_bend_amount,desired_bend,1.0-exp(-response*delta))
	if absf(turn_bend_amount)<.000001 and absf(desired_bend)<.000001:turn_bend_amount=0.0
	if not turning and absf(driving_rate)>.001:
		turning=true;turn_peak=0;turn_start_yaw=old_yaw;events.append({"event":"TURN_STARTED","direction":signf(driving_rate),"start_yaw":old_yaw,"target_yaw":target_yaw})
	if turning:
		turn_peak=maxf(turn_peak,absf(turn_bend_amount))
		if absf(driving_rate)<.001 and absf(turn_bend_amount)<.001:
			events.append({"event":"TURN_COMPLETED","start_yaw":turn_start_yaw,"target_yaw":target_yaw,"actual_yaw":yaw,"maximum_bend":turn_peak});turning=false
	var rate: float=lerpf(config.idle_animation_speed,config.swim_animation_speed,clampf(speed/config.stimulus_speed,0,1))
	if speed>config.stimulus_speed and config.max_speed>config.stimulus_speed:rate=lerpf(config.swim_animation_speed,config.fast_animation_speed,(speed-config.stimulus_speed)/(config.max_speed-config.stimulus_speed))
	animation_rate=move_toward(animation_rate,rate,config.animation_response*delta)
	if animation!=null:animation.speed_scale=animation_rate
func bone_offsets() -> Dictionary:
	var result: Dictionary={};var sum:=0.0
	for value in config.body_bend_weights.values():sum+=float(value)
	for name in config.body_bend_weights:result[name]=turn_bend_amount*config.body_bend_weights[name]/sum
	result["Pectoral_Fin_Left_2"]=config.pectoral_turn_strength*maxf(0,-turn_bend_amount/config.max_turn_bend)
	result["Pectoral_Fin_Right_2"]=-config.pectoral_turn_strength*maxf(0,turn_bend_amount/config.max_turn_bend)
	return result
func turn_state() -> Dictionary:
	var cm_speed: float=velocity.length()/config.units_per_cm
	return {"target_turn_rate":target_turn_rate,"actual_turn_rate":actual_turn_rate,"path_turn_rate":path_turn_rate,"turn_bend_amount":turn_bend_amount,"turn_direction":signf(-turn_bend_amount),"minimum_turn_radius_cm":radius_for_speed(cm_speed),"current_turn_radius_cm":cm_speed/absf(path_turn_rate) if absf(path_turn_rate)>.000001 else null,"turn_peak_bend":turn_peak}
func finish_turn() -> void:
	if turning:
		events.append({"event":"TURN_INTERRUPTED","target_yaw":target_yaw,"actual_yaw":yaw,"maximum_bend":turn_peak});turning=false
func take_turn_events() -> Array:
	var result:=events;events=[];return result
func state() -> Dictionary:
	var result: Dictionary={"position":[position.x,position.y,position.z],"orientation_y_radians":yaw,"target_yaw":target_yaw,"velocity":[velocity.x,velocity.y,0],"speed":velocity.length(),"stimulus_speed":stimulus_speed,"animation_speed":animation_rate,"speed_cm_s":velocity.length()/config.units_per_cm,"target_speed_cm_s":stimulus_speed/config.units_per_cm,"position_cm":[position.x/config.units_per_cm,position.y/config.units_per_cm]}
	result.merge(turn_state());return result
