extends RefCounted
const Paths=preload("res://scripts/storage/portable_paths.gd")
var file: FileAccess
var path: String
var start_usec: int
var last_flush:=0.0
var flush_interval:=0.5
func begin(metadata: Dictionary) -> String:
	var folder:=Paths.data_dir().path_join("experiments")
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:return "Versuchsordner kann nicht angelegt werden."
	path=folder.path_join(Time.get_datetime_string_from_system().replace(":","-")+"_"+Crypto.new().generate_random_bytes(8).hex_encode()+".jsonl")
	file=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return "Versuchsprotokoll kann nicht geöffnet werden."
	start_usec=Time.get_ticks_usec()
	metadata=metadata.duplicate(true)
	metadata["started_utc"]=Time.get_datetime_string_from_system(true)+"Z"
	metadata["session_id"]=path.get_file().get_basename()
	return "" if record("session_start",{}, {},0,metadata) else "Versuchsprotokoll kann nicht geschrieben werden."
func record(event: String,state: Dictionary,command: Dictionary,simulation_time: float,extra: Dictionary={}) -> bool:
	if file==null:return false
	var elapsed: float=(Time.get_ticks_usec()-start_usec)/1000000.0
	file.store_line(JSON.stringify({"event":event,"elapsed_seconds":elapsed,"simulation_seconds":simulation_time,"state":state,"command":command,"details":extra}))
	if elapsed-last_flush>=flush_interval or event!="sample":file.flush();last_flush=elapsed
	return file.get_error()==OK
func close() -> void:
	if file!=null:file.flush();file.close();file=null
