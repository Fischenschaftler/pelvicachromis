extends RefCounted
## All time integration belongs to the shared physical step, never the renderer.
var config: Resource
var pitch:=0.0
var pitch_velocity:=0.0
var target_pitch:=0.0
var pitch_input:=0.0
var pitch_state:="NEUTRAL"
var frequency:=1.0
var phase:=0.0
var opening:=0.0
var boost:=false
var effective_speed:=0.0
var events: Array=[]
func reset(settings: Resource) -> void:
	config=settings;pitch=0;pitch_velocity=0;target_pitch=0;pitch_input=0;pitch_state="NEUTRAL"
	frequency=config.operculum_frequency_hz;phase=fposmod(config.operculum_phase,1.0);opening=breath(phase);boost=false;effective_speed=config.speed_cm_s;events.clear()
static func smooth(t: float) -> float:
	t=clampf(t,0,1);return t*t*t*(10+t*(-15+6*t))
static func breath(t: float) -> float:
	if t<.42:return smooth(t/.42)
	if t<.55:return 1.0
	if t<.95:return 1.0-smooth((t-.55)/.4)
	return 0.0
func step(dt: float,command: Dictionary,speed_cm_s: float) -> void:
	pitch_input=clampf(float(command.get("pitch",0)),-1,1)
	var old_state:=pitch_state
	var old_target:=target_pitch
	if command.has("sequence_pitch_deg"):
		target_pitch=float(command.target_pitch_deg);pitch=clampf(float(command.sequence_pitch_deg),-config.max_pitch_down_deg,config.max_pitch_up_deg);pitch_velocity=0
		pitch_state=command.pitch_transition_state
	else:
		target_pitch=config.max_pitch_up_deg if pitch_input>0 else (-config.max_pitch_down_deg if pitch_input<0 else (0.0 if config.pitch_return_to_neutral else pitch))
		var difference:=target_pitch-pitch
		var limit: float=config.pitch_speed_deg_s if pitch_input!=0 else config.pitch_return_speed
		var rate:=signf(difference)*minf(limit,sqrt(2.0*config.pitch_deceleration*absf(difference)))
		pitch_velocity=move_toward(pitch_velocity,rate,(config.pitch_acceleration if absf(rate)>absf(pitch_velocity) else config.pitch_deceleration)*dt)
		var change:=pitch_velocity*dt
		if absf(change)>=absf(difference) and change*difference>=0:pitch=target_pitch;pitch_velocity=0
		else:pitch=clampf(pitch+change,-config.max_pitch_down_deg,config.max_pitch_up_deg)
		pitch_state=("NEUTRAL" if absf(pitch)<.0001 else "HOLD") if absf(pitch-target_pitch)<.0001 else ("RETURNING" if pitch_input==0 else "TRANSITION")
	if old_state=="TRANSITION" and (pitch_state=="HOLD" or (command.has("sequence_pitch_deg") and pitch_state=="RETURNING")):
		events.append({"event":"PITCH_TARGET_REACHED","target_pitch_deg":old_target})
	if old_state!=pitch_state or old_target!=target_pitch:
		events.append({"event":"PITCH_"+pitch_state,"target_pitch_deg":target_pitch,"actual_pitch_deg":pitch})
	var requested: float=command.get("operculum_frequency_hz",config.operculum_frequency_hz)
	requested*=1.0+config.operculum_speed_coupling*clampf(speed_cm_s/config.max_stimulus_speed_cm_s,0,1)
	frequency=lerpf(frequency,requested,1.0-exp(-config.operculum_response*dt))
	phase=fposmod(phase+frequency*dt,1.0);opening=breath(phase)
func state() -> Dictionary:
	return {"target_pitch_deg":target_pitch,"actual_pitch_deg":pitch,"pitch_input":pitch_input,"pitch_transition_state":pitch_state,"boost_active":boost,"boost_multiplier":config.boost_multiplier,"target_speed_cm_s":effective_speed,"operculum_frequency_hz":frequency,"operculum_amplitude":config.operculum_amplitude,"operculum_speed_coupling":config.operculum_speed_coupling,"operculum_phase":phase,"operculum_opening":opening}
static func register_inputs() -> void:
	for action in {"stimulus_pitch_up":KEY_PAGEUP,"stimulus_pitch_down":KEY_PAGEDOWN,"stimulus_boost":KEY_SHIFT}:
		if InputMap.has_action(action):continue
		InputMap.add_action(action)
		var event:=InputEventKey.new();event.physical_keycode={"stimulus_pitch_up":KEY_PAGEUP,"stimulus_pitch_down":KEY_PAGEDOWN,"stimulus_boost":KEY_SHIFT}[action]
		InputMap.action_add_event(action,event)
