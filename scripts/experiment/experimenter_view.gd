extends Control
const Store=preload("res://scripts/sequences/sequence_store.gd")
const Setup=preload("res://scripts/experiment/display_setup.gd")
var controller: Node
var store=Store.new()
var experiment_screen: OptionButton
var stimulus_screen: OptionButton
var sequence: OptionButton
var development: CheckBox
var neutral: OptionButton
var preview: CheckBox
var manual: CheckBox
var trial: LineEdit
var animal: LineEdit
var summary: Label
var live: Label
var message: Label
var state_preview: Label
var start_button: Button
var pause_button: Button
var locked_controls: Array[Control]=[]
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background:=ColorRect.new();background.color=Color(.075,.085,.10);add_child(background);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin:=MarginContainer.new();add_child(margin);margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+edge,20)
	var scroll:=ScrollContainer.new();margin.add_child(scroll)
	var box:=VBoxContainer.new();box.custom_minimum_size.x=620;box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",10);scroll.add_child(box)
	label(box,"Experimentator · getrennte Stimulusausgabe · F12",24)
	label(box,"Nur dieses Fenster enthält Bedienung und Diagnosen. Stimulusfenster: ausschließlich Fisch und Hintergrund.")
	var displays:=GridContainer.new();displays.columns=2;box.add_child(displays)
	label(displays,"Experimentatormonitor");experiment_screen=OptionButton.new();displays.add_child(experiment_screen)
	label(displays,"Stimulusmonitor");stimulus_screen=OptionButton.new();displays.add_child(stimulus_screen)
	development=check(box,"Einmonitor-Entwicklung (Fenstervorschau, kein wissenschaftlicher Versuch)")
	var row:=HFlowContainer.new();box.add_child(row)
	button(row,"Monitorwahl speichern",controller.select_displays);button(row,"Stimulusfenster testen",controller.test_window);button(row,"Kalibrierung öffnen / prüfen",controller.calibrate)
	var fields:=GridContainer.new();fields.columns=2;box.add_child(fields)
	label(fields,"Neutralausgabe nach Ende/Abbruch");neutral=OptionButton.new();neutral.add_item("Nur Hintergrund");neutral.add_item("Fisch mittig, unbewegt");fields.add_child(neutral)
	label(fields,"Sequenz");sequence=OptionButton.new();fields.add_child(sequence)
	trial=text_field(fields,"Versuchs-ID");animal=text_field(fields,"Versuchstier-ID (optional)")
	preview=check(box,"Vorschau – eigenes Diagnoseprotokoll, keine echte Versuchs-ID")
	manual=check(box,"Manual Override erlauben (WASD / Q E / R F / F8)")
	row=HFlowContainer.new();box.add_child(row);button(row,"Fisch auswählen",controller.select_fish);button(row,"Sequenz bearbeiten",controller.edit_sequence);button(row,"Versuch vorbereiten",controller.prepare)
	summary=label(box,"Bitte Monitorwahl speichern und Versuch vorbereiten.");summary.modulate=Color(.7,.85,1)
	row=HFlowContainer.new();box.add_child(row)
	start_button=button(row,"Stimulus starten",controller.start);start_button.disabled=true
	pause_button=button(row,"Pause / Fortsetzen",controller.pause_or_resume,false)
	var abort_button:=button(row,"VERSUCH ABBRECHEN",controller.abort,false);abort_button.modulate=Color(1,.35,.35)
	button(row,"Versuch zurücksetzen",controller.reset_trial,false);button(row,"Zurück zum Viewer",controller.close)
	live=label(box,"Kein Versuch aktiv.");state_preview=label(box,"Zustandsvorschau (Experimentator): noch kein Stimulus.")
	message=label(box,"");message.modulate=Color(1,.8,.4)
	locked_controls.append_array([experiment_screen,stimulus_screen,sequence,development,neutral,preview,manual,trial,animal])
	for control in [sequence,experiment_screen,stimulus_screen,neutral]:control.item_selected.connect(func(_i):controller.invalidate())
	for control in [development,preview,manual]:control.toggled.connect(func(_v):controller.invalidate())
	for control in [trial,animal]:control.text_changed.connect(func(_v):controller.invalidate())
func label(parent: Node,text: String,size: int=16) -> Label:
	var item:=Label.new();item.text=text;item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;item.add_theme_font_size_override("font_size",size)
	if parent is GridContainer:item.custom_minimum_size.x=230
	parent.add_child(item);return item
func button(parent: Node,text: String,action: Callable,lock: bool=true) -> Button:
	var item:=Button.new();item.text=text;item.pressed.connect(action);parent.add_child(item)
	if lock:locked_controls.append(item)
	return item
func check(parent: Node,text: String) -> CheckBox:
	var item:=CheckBox.new();item.text=text;parent.add_child(item);return item
func text_field(parent: Node,text: String) -> LineEdit:
	label(parent,text);var item:=LineEdit.new();item.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(item);return item
func populate() -> void:
	experiment_screen.clear();stimulus_screen.clear()
	for item in Setup.screens():
		var caption: String="Monitor %d · %d×%d · Position %s · Skalierung %.2f" % [item.monitor_index,item.screen_size[0],item.screen_size[1],str(item.screen_position),item.screen_scale]
		experiment_screen.add_item(caption,item.monitor_index);stimulus_screen.add_item(caption,item.monitor_index)
	experiment_screen.select(experiment_screen.get_item_index(controller.setup.experimenter_screen));stimulus_screen.select(stimulus_screen.get_item_index(controller.setup.stimulus_screen))
	development.set_pressed_no_signal(controller.setup.development);preview.set_pressed_no_signal(controller.setup.development);neutral.select(1 if controller.setup.neutral_mode=="CENTER_FISH" else 0)
	store.ensure_examples();sequence.clear()
	for item in store.list_sequences():sequence.add_item(item.name);sequence.set_item_metadata(sequence.item_count-1,item.id)
	update_locked()
func update_locked() -> void:
	var lock: bool=controller.active or controller.busy
	for item in locked_controls:
		if item is BaseButton:item.disabled=lock
		elif item is LineEdit:item.editable=not lock
	pause_button.disabled=not controller.active
	start_button.disabled=lock or controller.prepared.is_empty()
func show_progress(state: Dictionary,window: Dictionary) -> void:
	if state.is_empty():return
	var runner=controller.output.renderer.sequence_runner
	live.text="%s · Schritt %d/%d: %s\nGesamt %.3f s · Schritt %.3f s · Rest %.3f s\nTempo Soll %.3f / Ist %.3f cm/s\nPosition Soll %s / Ist %s cm\nOrientierung Soll %.1f° / Ist %.1f°\nFenster: %s · Logging: %s\nMonitor %d · Fenster-ID %d · Viewport %s · Vollbild %s · Kalibrierung %s" % [state.control_state,state.step_index+1,runner.definition.steps.size(),state.step_type,state.sequence_time_s,state.sequence_time_s-runner.step_start_s,state.remaining_s,state.target_speed_cm_s,state.actual_speed_cm_s,str(state.target_position_cm),str(state.actual_position_cm),rad_to_deg(state.target_orientation),rad_to_deg(state.actual_orientation),"bereit" if window.stimulus_window_ready else "NICHT BEREIT","aktiv" if not controller.output.renderer.sequence_log_failed else "FEHLER",window.stimulus_screen,window.stimulus_window_id,str(window.stimulus_viewport_size),str(window.fullscreen_state),controller.prepared.calibration.active_profile]
	state_preview.text="Zustandsvorschau (keine zweite 3D-Berechnung): Fisch bei (%.2f, %.2f) cm · %s · Animation %.2f×" % [state.actual_position_cm[0],state.actual_position_cm[1],"←" if cos(state.actual_orientation)<0 else "→",state.animation_rate]
