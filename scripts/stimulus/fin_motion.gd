extends RefCounted
## Receives one shared physical-state snapshot; never estimates speed from transforms.
var phase:=0.0
var left:=0.0
var right:=0.0
var passive:=0.0
var offsets: Dictionary={}
func reset() -> void:
	phase=0;left=0;right=0;passive=0;offsets.clear()
func step(dt: float,state: Dictionary,config: Resource) -> void:
	var cruise:=clampf(state.speed_cm_s/config.speed_cm_s,0,1)
	phase=fposmod(phase+dt*config.pectoral_frequency_hz,2.0)
	var wave: float=.5+.5*sin(TAU*phase)
	var base: float=lerpf(config.pectoral_hover_amplitude,config.pectoral_cruise_amplitude,cruise)*wave
	var brake: float=config.pectoral_brake_amplitude*state.braking_amount
	var turn:=clampf(state.turn_rate/config.turn_speed,-1,1)
	var pitch_support: float=config.pectoral_pitch_amplitude*absf(state.pitch_deg)/maxf(config.max_pitch_up_deg,config.max_pitch_down_deg)
	var response:=1-exp(-config.fin_response*dt)
	# Outer fin provides additional drag: positive heading turn -> negative-Z (Left) side.
	left=lerpf(left,base+brake+pitch_support+config.pectoral_turn_amplitude*maxf(0,turn),response)
	right=lerpf(right,base+brake+pitch_support+config.pectoral_turn_amplitude*maxf(0,-turn),response)
	passive=lerpf(passive,config.passive_fin_amplitude*(.35+.65*clampf(state.speed_cm_s/config.max_stimulus_speed_cm_s,0,1))*sin(TAU*phase*.5)+config.passive_fin_amplitude*.25*turn,response)
	offsets={"Pectoral_Fin_Left_2":left,"Pectoral_Fin_Right_2":-right,"Pelvic_Fin_Left_2":passive,"Pelvic_Fin_Right_2":-passive,"Dorsal_01":passive*.3,"Dorsal_02":passive*.55,"Anal_Fin_2":-passive*.4}
func state() -> Dictionary:
	return {"pectoral_left_angle":left,"pectoral_right_angle":right,"fin_phase":phase,"passive_fin_angle":passive}
