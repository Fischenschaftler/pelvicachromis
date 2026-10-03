extends RefCounted
## Independent presentation orientation. Positive degrees turn the snout toward +Z (camera).
var active:=false
var angle:=0.0
var target:=0.0
var velocity:=0.0
var actual_rate:=0.0
var transition:="FOLLOW_HEADING"
var events: Array=[]
func reset() -> void:
	active=false;angle=0;target=0;velocity=0;actual_rate=0;transition="FOLLOW_HEADING";events.clear()
func step(dt: float,command: Dictionary,heading_rad: float,config: Resource) -> void:
	var input:=clampf(float(command.get("yaw",0)),-1,1)
	var old:=angle;var previous:=transition;var previous_target:=target
	if not active:
		angle=-rad_to_deg(heading_rad);target=angle
		if input!=0 or command.has("sequence_yaw_deg"):active=true;old=angle
	if not active:actual_rate=(angle-old)/dt;return
	if command.has("sequence_yaw_deg"):
		angle=float(command.sequence_yaw_deg);target=float(command.target_yaw_deg);velocity=0;transition=command.yaw_transition_state
	else:
		var wanted: float=input*config.yaw_speed_deg_s
		velocity=move_toward(velocity,wanted,(config.yaw_acceleration if absf(wanted)>absf(velocity) else config.yaw_deceleration)*dt)
		angle+=velocity*dt
		# Manual target is the deterministic braking endpoint, not an arbitrary distant angle.
		target=angle+signf(velocity)*velocity*velocity/(2*config.yaw_deceleration)
		transition="HOLD" if absf(velocity)<.000001 else "TRANSITION"
	actual_rate=(angle-old)/dt
	if previous!=transition or (command.has("sequence_yaw_deg") and previous_target!=target):
		events.append({"event":"YAW_"+transition,"actual_yaw_deg":angle,"target_yaw_deg":target})
		if transition=="HOLD":events.append({"event":"YAW_TARGET_REACHED","actual_yaw_deg":angle})
func state() -> Dictionary:
	return {"actual_yaw_deg":angle,"target_yaw_deg":target,"yaw_speed_deg_s":actual_rate,"yaw_transition_state":transition,"independent_yaw":active}
