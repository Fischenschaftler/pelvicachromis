extends RefCounted
const VERSION=1
const TYPES=["WAIT","MOVE","TURN","MOVE_TO","HOLD","RESET_POSITION"]
const DIRECTIONS={"NONE":Vector2.ZERO,"LEFT":Vector2.LEFT,"RIGHT":Vector2.RIGHT,"UP":Vector2.UP*-1,"DOWN":Vector2.DOWN*-1}
const MAX_DURATION=3600.0
static func fresh(name: String="Neue Sequenz") -> Dictionary:
	var now:=Time.get_datetime_string_from_system(true)+"Z"
	return {"sequence_format_version":VERSION,"sequence_id":Crypto.new().generate_random_bytes(12).hex_encode(),"sequence_name":name,"created_at":now,"updated_at":now,"description":"","notes":"","initial_state":{"start_mode":"CENTER","position_cm":[0.0,0.0],"orientation":"RIGHT"},"steps":[step()],"total_duration_s":5.0}
static func step(kind: String="HOLD") -> Dictionary:
	var result: Dictionary={"step_type":kind,"duration_s":5.0,"target_speed_cm_s":3.0 if kind in ["MOVE","MOVE_TO"] else 0.0,"direction":"RIGHT" if kind=="MOVE" else "NONE","comment":""}
	if kind=="TURN":result.orientation="LEFT"
	if kind=="MOVE_TO":result.target_position_cm=[0.0,0.0]
	if kind=="RESET_POSITION":result.start_position_cm=[0.0,0.0];result.duration_s=0.0
	return result
static func total(definition: Dictionary) -> float:
	var result:=0.0
	for item in definition.steps:result+=float(item.duration_s)
	return result
static func numeric(value: Variant) -> bool:return (value is int or value is float) and is_finite(float(value))
static func point(value: Variant) -> bool:return value is Array and value.size()==2 and numeric(value[0]) and numeric(value[1])
static func safe_id(id: String) -> bool:
	if id.is_empty() or id.length()>80:return false
	for c in id:
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":return false
	return true
static func validate(data: Variant,max_speed: float=100.0) -> String:
	if not data is Dictionary:return "Sequenz muss ein JSON-Objekt sein."
	if data.get("sequence_format_version")!=VERSION:return "Nicht unterstützte Sequenzversion."
	if not data.get("sequence_id") is String or not safe_id(data.sequence_id):return "Ungültige Sequenzkennung."
	for key in ["sequence_name","created_at","updated_at","description"]:
		if not data.get(key) is String:return "Pflichtfeld fehlt: "+key
	if data.sequence_name.strip_edges().is_empty() or data.sequence_name.length()>100:return "Sequenzname benötigt 1 bis 100 Zeichen."
	if not data.get("notes","") is String:return "Notizen müssen Text sein."
	var initial=data.get("initial_state")
	if not initial is Dictionary or initial.get("start_mode") not in ["CENTER","LEFT","RIGHT","CUSTOM"] or initial.get("orientation") not in ["LEFT","RIGHT"]:return "Ungültiger Startzustand."
	if not point(initial.get("position_cm")):return "Startposition benötigt X und Y in cm."
	if not data.get("steps") is Array or data.steps.is_empty() or data.steps.size()>500:return "Eine Sequenz benötigt 1 bis 500 Schritte."
	for i in range(data.steps.size()):
		var item=data.steps[i];var prefix: String="Schritt %d: " % (i+1)
		if not item is Dictionary or item.get("step_type") not in TYPES:return prefix+"Unbekannter Schritttyp."
		if not numeric(item.get("duration_s")) or item.duration_s<0 or item.duration_s>MAX_DURATION:return prefix+"Ungültige Dauer."
		if not numeric(item.get("target_speed_cm_s")) or item.target_speed_cm_s<0 or item.target_speed_cm_s>max_speed:return prefix+"Geschwindigkeit außerhalb der zulässigen Grenzen."
		if item.get("direction") not in DIRECTIONS:return prefix+"Ungültige Richtung."
		if item.step_type!="MOVE" and item.direction!="NONE":return prefix+"Richtung nur bei MOVE verwenden; sonst NONE."
		if item.has("boost") and not item.boost is bool:return prefix+"Boost benötigt true/false."
		if item.has("operculum_frequency_hz") and (not numeric(item.operculum_frequency_hz) or item.operculum_frequency_hz<=0 or item.operculum_frequency_hz>5):return prefix+"Atemfrequenz muss >0 und <=5 Hz sein."
		if item.has("target_pitch_deg"):
			if not numeric(item.target_pitch_deg) or absf(item.target_pitch_deg)>45:return prefix+"Pitch außerhalb ±45°."
			for field in ["pitch_transition_s","pitch_hold_s","pitch_return_s"]:
				if not numeric(item.get(field)) or item[field]<0:return prefix+"Pitch benötigt gültige Übergangs-, Halte- und Rückkehrdauer."
			if item.pitch_transition_s<=0 or item.pitch_return_s<=0 or item.pitch_transition_s+item.pitch_hold_s+item.pitch_return_s>item.duration_s+.000001:return prefix+"Pitch-Zyklus passt nicht in die Schrittdauer. Übergang/Rückkehr müssen positiv sein."
		elif item.has("pitch_transition_s") or item.has("pitch_hold_s") or item.has("pitch_return_s"):return prefix+"Pitch-Dauern benötigen einen Zielwinkel."
		if item.has("orientation") and item.orientation not in ["LEFT","RIGHT"]:return prefix+"Ungültige Orientierung."
		if not item.get("comment","") is String:return prefix+"Kommentar muss Text sein."
		if item.step_type=="MOVE" and (item.direction=="NONE" or item.target_speed_cm_s<=0):return prefix+"MOVE benötigt Richtung und positive Geschwindigkeit."
		if item.step_type=="MOVE_TO" and (not point(item.get("target_position_cm")) or item.target_speed_cm_s<=0):return prefix+"MOVE_TO benötigt Zielposition und positive Geschwindigkeit."
		if item.step_type=="TURN" and not item.has("orientation"):return prefix+"TURN benötigt eine Orientierung."
		if item.step_type not in ["MOVE","MOVE_TO"] and item.target_speed_cm_s!=0:return prefix+"Dieser Schritttyp benötigt Geschwindigkeit 0."
		if item.has("target_position_cm") and (item.step_type!="MOVE_TO" or not point(item.target_position_cm)):return prefix+"Zielposition nur bei MOVE_TO verwenden."
		if item.has("start_position_cm") and (not point(item.start_position_cm) or (i!=0 and item.step_type!="RESET_POSITION")):return prefix+"Positionssprünge nur am Start oder in RESET_POSITION."
		if item.step_type=="RESET_POSITION" and not point(item.get("start_position_cm")):return prefix+"RESET_POSITION benötigt eine Position."
	var duration:=total(data)
	if duration<=0 or duration>MAX_DURATION:return "Gesamtdauer muss zwischen 0 und 3600 Sekunden liegen."
	if not numeric(data.get("total_duration_s")) or absf(data.total_duration_s-duration)>0.000001:return "Gesamtdauer stimmt nicht mit den Schritten überein."
	return ""
static func freeze(value: Variant) -> void:
	if value is Dictionary:
		for item in value.values():freeze(item)
		value.make_read_only()
	elif value is Array:
		for item in value:freeze(item)
		value.make_read_only()
static func checksum(data: Dictionary) -> String:return JSON.stringify(JSON.parse_string(JSON.stringify(data)),"",true).sha256_text()
static func visible_bounds(calibration: RefCounted,pixels: Vector2i,length_cm: float) -> Rect2:
	# Conservative circular margin keeps the whole fish visible during a turn.
	var half:=Vector2(pixels.x/calibration.pixels_per_cm_x,pixels.y/calibration.pixels_per_cm_y)*.5
	var margin:=Vector2.ONE*(length_cm*.5+.2)
	return Rect2(-half+margin,(half-margin)*2)
static func contains(bounds: Rect2,p: Vector2) -> bool:return p.x>=bounds.position.x-.001 and p.x<=bounds.end.x+.001 and p.y>=bounds.position.y-.001 and p.y<=bounds.end.y+.001
static func initial_position(data: Dictionary,bounds: Rect2) -> Vector2:
	var initial: Dictionary=data.initial_state
	var result:=Vector2.ZERO
	if initial.start_mode=="LEFT":result.x=bounds.position.x
	elif initial.start_mode=="RIGHT":result.x=bounds.end.x
	elif initial.start_mode=="CUSTOM":result=Vector2(initial.position_cm[0],initial.position_cm[1])
	if data.steps[0].has("start_position_cm"):result=Vector2(data.steps[0].start_position_cm[0],data.steps[0].start_position_cm[1])
	return result
