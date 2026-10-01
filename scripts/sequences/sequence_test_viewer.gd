extends "res://scripts/fish_viewer.gd"
## Validation-only synthetic monitor; never exported in the production application.
func test_config() -> Resource:
	var config:=preload("res://scripts/stimulus/stimulus_config.gd").new()
	config.stop_on_focus_loss=false
	config.calibration_override=preload("res://scripts/stimulus/display_calibration.gd").new()
	config.calibration_override.configure(100,config.calibration_override.display_context(get_window()))
	config.calibration_override.calibration_timestamp="SYNTHETIC SEQUENCE TEST ONLY"
	return config
func sequence_setup_context() -> Dictionary:
	var config:=test_config();var c: RefCounted=config.calibration_override
	var pixels:=DisplayServer.screen_get_size(get_window().current_screen)
	config.apply_calibration(c,pixels,pixels)
	var photo:=get_node("UI/ReferencePhoto")
	return {"config":config,"calibration":c,"bounds":preload("res://scripts/sequences/sequence_data.gd").visible_bounds(c,pixels,8),"project_id":photo.project_id,"project_name":photo.project_name}
func launch_sequence(request: Dictionary,config_override: Resource=null) -> String:
	return await super.launch_sequence(request,test_config() if config_override==null else config_override)
