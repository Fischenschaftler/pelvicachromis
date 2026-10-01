extends RefCounted
## A monotonic clock drives a fixed physical integration lattice, not render-frame counts.
const Data=preload("res://scripts/sequences/sequence_data.gd")
const Motion=preload("res://scripts/stimulus/stimulus_fish_controller.gd")
const QUANTUM=1.0/240.0
const MAX_REALTIME_GAP=0.25
var definition: Dictionary
var definition_hash: String
var motion: Node3D
var bounds: Rect2
var time_s:=0.0
var step_index:=0
var step_start_s:=0.0
var step_end_s:=0.0
var paused:=false
var finished:=false
var completed:=false
var allow_override:=false
var manual: Dictionary={}
var overriding:=false
var event_sink: Callable
var failure: String
var clock_origin:=0.0
var pause_started:=0.0
var paused_seconds:=0.0
var last_clock:=0.0
var next_sample:=0.0
var step_origin_cm:=Vector2.ZERO
var requested_speed:=0.0
var requested_position: Variant=null
var requested_orientation:=0.0
var simulation_only:=false
func configure(data: Dictionary,body: Node3D,area: Rect2,override_allowed: bool=false,sink: Callable=Callable()) -> void:
	definition=data.duplicate(true);definition_hash=Data.checksum(definition);Data.freeze(definition)
	motion=body;bounds=area;allow_override=override_allowed;event_sink=sink
	motion.reset_stimulus()
	var p:=Data.initial_position(definition,bounds);_place(p,definition.initial_state.orientation)
	step_index=0;time_s=0;step_start_s=0;step_end_s=definition.steps[0].duration_s
	_enter_step(false)
func _place(p: Vector2,orientation: String="") -> void:
	motion.position=Vector3(p.x*motion.config.units_per_cm,p.y*motion.config.units_per_cm,motion.config.plane_depth)
	motion.velocity=Vector2.ZERO
	if not orientation.is_empty():
		motion.yaw=PI if orientation=="LEFT" else 0.0;motion.target_yaw=motion.yaw;motion.angular_speed=0;motion.rotation=Vector3(0,motion.yaw,0)
func position_cm() -> Vector2:return Vector2(motion.position.x,motion.position.y)/motion.config.units_per_cm
func _event(name: String,extra: Dictionary={}) -> void:
	if event_sink.is_valid():event_sink.call(name,extra)
func begin(now: float) -> void:
	clock_origin=now;last_clock=now;_event("STEP_STARTED")
	advance_to(0)
func _enter_step(emit: bool=true) -> void:
	var item: Dictionary=definition.steps[step_index]
	if item.step_type=="RESET_POSITION":_place(Vector2(item.start_position_cm[0],item.start_position_cm[1]),item.get("orientation",""))
	if item.step_type in ["HOLD","TURN","RESET_POSITION"]:motion.velocity=Vector2.ZERO
	step_origin_cm=position_cm()
	requested_position=item.get("target_position_cm",[step_origin_cm.x,step_origin_cm.y])
	requested_speed=item.target_speed_cm_s
	if item.has("orientation"):requested_orientation=PI if item.orientation=="LEFT" else 0.0
	elif item.step_type=="MOVE" and item.direction in ["LEFT","RIGHT"]:requested_orientation=PI if item.direction=="LEFT" else 0.0
	else:requested_orientation=motion.target_yaw
	if emit:_event("STEP_STARTED")
func _automatic_command() -> Dictionary:
	var item: Dictionary=definition.steps[step_index]
	var direction: Vector2=Data.DIRECTIONS[item.direction] if item.step_type=="MOVE" else Vector2.ZERO
	var speed: float=item.target_speed_cm_s
	if item.step_type=="MOVE_TO":
		var offset:=Vector2(item.target_position_cm[0],item.target_position_cm[1])-position_cm()
		direction=offset.normalized()
		speed=minf(speed,sqrt(2*motion.config.deceleration_cm_s2*offset.length()))
		if not item.has("orientation") and absf(direction.x)>.000001:requested_orientation=PI if direction.x<0 else 0.0
	return {"x":direction.x,"y":direction.y,"target_speed_cm_s":speed,"facing":-1.0 if requested_orientation>PI*.5 else 1.0}
func _integrate(dt: float) -> void:
	var item: Dictionary=definition.steps[step_index]
	var command:=manual if overriding else _automatic_command()
	var before:=position_cm()
	if not overriding and item.step_type in ["HOLD","TURN","RESET_POSITION"]:motion.velocity=Vector2.ZERO
	motion.step(dt,command)
	if not overriding and item.step_type=="MOVE_TO":
		var goal:=Vector2(item.target_position_cm[0],item.target_position_cm[1])
		var after:=position_cm()
		if after.distance_to(goal)<.0005 or (goal-before).dot(goal-after)<=0:_place(goal)
	if not Data.contains(bounds,position_cm()):
		failure="Schritt %d verlässt den sichtbaren Bereich (inklusive Fischrand)." % (step_index+1)
	if motion.animation!=null:motion.animation.advance(dt)
func advance_to(target_time: float) -> void:
	if finished or paused:return
	target_time=minf(target_time,definition.total_duration_s)
	while not finished:
		var next:=minf(time_s+QUANTUM,step_end_s)
		if next>target_time+0.000000001:return
		var dt:=maxf(0,next-time_s)
		if dt>0:_integrate(dt)
		time_s=next
		if not failure.is_empty():abort(failure);return
		if time_s>=step_end_s-.000000001:
			var item: Dictionary=definition.steps[step_index]
			if simulation_only and item.step_type=="MOVE_TO" and position_cm().distance_to(Vector2(item.target_position_cm[0],item.target_position_cm[1]))>.01:
				failure="Schritt %d: MOVE_TO erreicht das Ziel nicht rechtzeitig. Dauer erhöhen." % (step_index+1);abort(failure);return
			_event("STEP_COMPLETED")
			if step_index+1>=definition.steps.size():
				finished=true;completed=true;_event("SESSION_COMPLETED");return
			step_start_s=step_end_s;step_index+=1;step_end_s=step_start_s+definition.steps[step_index].duration_s;_enter_step()
		if time_s>=next_sample:
			_event("sample");next_sample=time_s+1.0/motion.config.log_hz
func tick(now: float,command: Dictionary={}) -> void:
	if finished:return
	if not paused and now-last_clock>MAX_REALTIME_GAP:abort("timing_overrun: mehr als 250 ms ohne Aktualisierung");return
	last_clock=now
	if paused:return
	var active_input:=false
	for key in ["x","y","speed","facing"]:
		if absf(float(command.get(key,0)))>.0001:active_input=true
	var enabled:=allow_override and active_input
	if enabled!=overriding or (enabled and command!=manual):
		overriding=enabled;manual=command.duplicate(true);_event("MANUAL_OVERRIDE",{"active":enabled,"command":manual})
	advance_to(now-clock_origin-paused_seconds)
func toggle_pause(now: float) -> void:
	if finished:return
	if paused:
		paused_seconds+=now-pause_started;paused=false;last_clock=now;_event("RESUMED")
	else:
		tick(now,manual if overriding else {})
		if finished:return
		paused=true;pause_started=now;_event("PAUSED")
func manual_reset() -> void:
	if not allow_override or finished or paused:return
	motion.reset_stimulus();_place(Data.initial_position(definition,bounds),definition.initial_state.orientation)
	_event("MANUAL_OVERRIDE",{"command":"RESET_POSITION","active":true})
func abort(reason: String) -> void:
	if finished:return
	finished=true;completed=false;_event("SESSION_ABORTED",{"reason":reason})
func telemetry() -> Dictionary:
	var item: Dictionary=definition.steps[step_index]
	var p:=position_cm()
	var target: Variant=requested_position
	if item.step_type=="MOVE":
		var ideal: Vector2=step_origin_cm+Data.DIRECTIONS[item.direction]*item.target_speed_cm_s*(time_s-step_start_s)
		target=[ideal.x,ideal.y]
	return {"sequence_id":definition.sequence_id,"sequence_name":definition.sequence_name,"sequence_format_version":definition.sequence_format_version,"sequence_sha256":definition_hash,"sequence_time_s":time_s,"remaining_s":maxf(0,definition.total_duration_s-time_s),"step_index":step_index,"step_type":item.step_type,"target_position_cm":target,"command_speed_cm_s":motion.stimulus_speed/motion.config.units_per_cm,"actual_position_cm":[p.x,p.y],"target_speed_cm_s":requested_speed,"actual_speed_cm_s":0.0 if paused else motion.velocity.length()/motion.config.units_per_cm,"target_orientation":requested_orientation,"actual_orientation":motion.yaw,"animation_rate":0.0 if paused else motion.animation_rate,"control_state":"PAUSED" if paused else ("MANUAL_OVERRIDE" if overriding else ("COMPLETED" if completed else ("ABORTED" if finished else "AUTOMATIC")))}
static func preflight(data: Dictionary,config: Resource,area: Rect2) -> Dictionary:
	var error:=Data.validate(data,config.max_speed_cm_s)
	if not error.is_empty():return {"error":error}
	if area.size.x<=0 or area.size.y<=0:return {"error":"Der Fisch ist größer als der sichtbare Bereich."}
	if not Data.contains(area,Data.initial_position(data,area)):return {"error":"Startposition liegt außerhalb des sichtbaren Bereichs."}
	for item in data.steps:
		for key in ["start_position_cm","target_position_cm"]:
			if item.has(key) and not Data.contains(area,Vector2(item[key][0],item[key][1])):return {"error":"Eine Position liegt außerhalb des sichtbaren Bereichs."}
	var body:=Motion.new();body.configure(config,null)
	var runner=load("res://scripts/sequences/sequence_runner.gd").new()
	runner.configure(data,body,area);runner.simulation_only=true;runner.advance_to(data.total_duration_s)
	var result: Dictionary={"error":runner.failure,"final_position_cm":[runner.position_cm().x,runner.position_cm().y]}
	body.free();return result
