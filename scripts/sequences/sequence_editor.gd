extends Control
signal closed
const Data=preload("res://scripts/sequences/sequence_data.gd")
const Store=preload("res://scripts/sequences/sequence_store.gd")
const Runner=preload("res://scripts/sequences/sequence_runner.gd")
var viewer: Node3D
var store=Store.new()
var definition: Dictionary=Data.fresh()
var return_after_trial:=false
var selected_index:=0
var rebuilding:=false
var entries: Array=[]
var saved_list: OptionButton
var name_input: LineEdit
var description_input: LineEdit
var notes_input: LineEdit
var start_mode: OptionButton
var initial_orientation: OptionButton
var start_x: SpinBox
var start_y: SpinBox
var table: Tree
var kind: OptionButton
var duration: SpinBox
var speed: SpinBox
var direction: OptionButton
var orientation: OptionButton
var pos_x: SpinBox
var pos_y: SpinBox
var comment: LineEdit
var trial_id: LineEdit
var animal_id: LineEdit
var override_box: CheckBox
var context_label: Label
var status: Label
var total_label: Label
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background:=ColorRect.new();background.color=Color(.09,.10,.12);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,18)
	add_child(margin)
	var scroll:=ScrollContainer.new();margin.add_child(scroll)
	var box:=VBoxContainer.new();box.custom_minimum_size.x=740;box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",8);scroll.add_child(box)
	label(box,"Versuchssequenzen · F11",24)
	var files:=HBoxContainer.new();box.add_child(files);saved_list=OptionButton.new();saved_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;files.add_child(saved_list)
	button(files,"Laden",load_selected);button(files,"Neu",new_sequence);button(files,"Duplizieren",duplicate_sequence);button(files,"Speichern",save_sequence);button(files,"Zurück (Esc)",close)
	var details:=GridContainer.new();details.columns=2;box.add_child(details)
	name_input=text_field(details,"Name");description_input=text_field(details,"Beschreibung");notes_input=text_field(details,"Notizen")
	var initial:=HBoxContainer.new();box.add_child(initial)
	label(initial,"Start");start_mode=option(initial,["CENTER","LEFT","RIGHT","CUSTOM"]);start_x=number(initial,-10000,10000,.01);start_y=number(initial,-10000,10000,.01)
	label(initial,"Blick");initial_orientation=option(initial,["RIGHT","LEFT"])
	label(box,"Koordinaten: cm ab Bildschirmmitte; +X rechts, +Y oben. CUSTOM nutzt X/Y. Space pausiert, Esc bricht ab.")
	table=Tree.new();table.columns=8;table.column_titles_visible=true;table.hide_root=true;table.custom_minimum_size.y=190;box.add_child(table)
	var headers: Array=["Nr.","Typ","Dauer s","cm/s","Richtung","Position cm","Blick","Kommentar"]
	for i in range(8):table.set_column_title(i,headers[i]);table.set_column_custom_minimum_width(i,40 if i==0 else 85)
	table.item_selected.connect(select_step)
	var tools:=HBoxContainer.new();box.add_child(tools)
	button(tools,"Schritt hinzufügen",add_step);button(tools,"Schritt löschen",delete_step);button(tools,"Nach oben",func():move_step(-1));button(tools,"Nach unten",func():move_step(1))
	var fields:=GridContainer.new();fields.columns=4;box.add_child(fields)
	label(fields,"Typ");kind=option(fields,Data.TYPES);label(fields,"Dauer s");duration=number(fields,0,3600,.001)
	label(fields,"Geschwindigkeit cm/s");speed=number(fields,0,100,.01);label(fields,"Richtung");direction=option(fields,Data.DIRECTIONS.keys())
	label(fields,"Ziel-/Reset-X cm");pos_x=number(fields,-10000,10000,.01);label(fields,"Y cm");pos_y=number(fields,-10000,10000,.01)
	label(fields,"Orientierung");orientation=option(fields,["KEEP","LEFT","RIGHT"]);comment=text_field(fields,"Kommentar")
	kind.item_selected.connect(kind_changed)
	button(box,"Schritt übernehmen",func():apply_form();rebuild())
	total_label=label(box,"")
	duration.value_changed.connect(func(value):
		if selected_index>=0 and selected_index<definition.steps.size():total_label.text="Gesamtdauer: %.3f s · %d Schritte" % [Data.total(definition)-definition.steps[selected_index].duration_s+value,definition.steps.size()])
	label(box,"Versuch vorbereiten",22)
	var ids:=GridContainer.new();ids.columns=2;box.add_child(ids)
	trial_id=text_field(ids,"Versuchs-ID (echter Versuch)");animal_id=text_field(ids,"Versuchstier-ID (optional)")
	override_box=CheckBox.new();override_box.text="Manuellen Eingriff erlauben (WASD, Q/E, R/F, F8; wird protokolliert)";box.add_child(override_box)
	context_label=label(box,"");context_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var actions:=HBoxContainer.new();box.add_child(actions)
	button(actions,"Vorschau / Preview",func():launch(true));button(actions,"Versuch starten",func():launch(false))
	status=label(box,"");status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.modulate=Color(1,.8,.4)
	status.text=store.ensure_examples();reload_list();display_definition()
func label(parent: Node,text: String,font_size: int=16) -> Label:
	var result:=Label.new();result.text=text;result.add_theme_font_size_override("font_size",font_size);parent.add_child(result);return result
func button(parent: Node,text: String,callback: Callable) -> Button:
	var result:=Button.new();result.text=text;result.pressed.connect(callback);parent.add_child(result);return result
func option(parent: Node,items: Array) -> OptionButton:
	var result:=OptionButton.new()
	for text in items:result.add_item(str(text))
	parent.add_child(result);return result
func number(parent: Node,minimum: float,maximum: float,step: float) -> SpinBox:
	var result:=SpinBox.new();result.min_value=minimum;result.max_value=maximum;result.step=step;result.custom_minimum_size.x=105;parent.add_child(result);return result
func text_field(parent: Node,title: String) -> LineEdit:
	label(parent,title);var result:=LineEdit.new();result.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(result);return result
func select_text(control: OptionButton,text: String) -> void:
	for i in range(control.item_count):
		if control.get_item_text(i)==text:control.select(i);return
func reload_list() -> void:
	entries=store.list_sequences();saved_list.clear()
	for item in entries:saved_list.add_item(item.name)
func display_definition() -> void:
	name_input.text=definition.sequence_name;description_input.text=definition.description;notes_input.text=definition.get("notes","")
	select_text(start_mode,definition.initial_state.start_mode);select_text(initial_orientation,definition.initial_state.orientation)
	start_x.value=definition.initial_state.position_cm[0];start_y.value=definition.initial_state.position_cm[1]
	selected_index=0;rebuild()
func rebuild() -> void:
	rebuilding=true;table.clear();var root:=table.create_item()
	for i in range(definition.steps.size()):
		var s: Dictionary=definition.steps[i];var row:=table.create_item(root);row.set_metadata(0,i)
		var position= s.get("target_position_cm",s.get("start_position_cm",[]))
		var cells: Array=[str(i+1),s.step_type,str(s.duration_s),str(s.target_speed_cm_s),s.direction,str(position),s.get("orientation","KEEP"),s.get("comment","")]
		for column in range(8):row.set_text(column,cells[column])
		if i==selected_index:row.select(0)
	rebuilding=false;show_form();total_label.text="Gesamtdauer: %.3f s · %d Schritte" % [Data.total(definition),definition.steps.size()]
func show_form() -> void:
	if selected_index<0 or selected_index>=definition.steps.size():return
	var item: Dictionary=definition.steps[selected_index]
	select_text(kind,item.step_type);duration.value=item.duration_s;speed.value=item.target_speed_cm_s;select_text(direction,item.direction);select_text(orientation,item.get("orientation","KEEP"));comment.text=item.get("comment","")
	var p: Array=item.get("target_position_cm",item.get("start_position_cm",[0,0]));pos_x.value=p[0];pos_y.value=p[1]
func select_step() -> void:
	if rebuilding or table.get_selected()==null:return
	var index:=int(table.get_selected().get_metadata(0));apply_form();selected_index=index;rebuild()
func kind_changed(_index: int) -> void:
	var type:=kind.get_item_text(kind.selected)
	speed.value=3 if type in ["MOVE","MOVE_TO"] else 0
	select_text(direction,"RIGHT" if type=="MOVE" else "NONE")
	if type=="TURN" and orientation.selected==0:select_text(orientation,"LEFT")
	if type=="RESET_POSITION":duration.value=0
func apply_form() -> void:
	if selected_index<0 or selected_index>=definition.steps.size():return
	var item: Dictionary={"step_type":kind.get_item_text(kind.selected),"duration_s":duration.value,"target_speed_cm_s":speed.value,"direction":direction.get_item_text(direction.selected),"comment":comment.text}
	if orientation.selected!=0:item.orientation=orientation.get_item_text(orientation.selected)
	if item.step_type=="MOVE_TO":item.target_position_cm=[pos_x.value,pos_y.value]
	if item.step_type=="RESET_POSITION":item.start_position_cm=[pos_x.value,pos_y.value]
	elif selected_index==0 and definition.steps[selected_index].has("start_position_cm"):
		item.start_position_cm=definition.steps[selected_index].start_position_cm.duplicate()
	definition.steps[selected_index]=item
func collect() -> void:
	apply_form();definition.sequence_name=name_input.text.strip_edges();definition.description=description_input.text;definition.notes=notes_input.text
	definition.initial_state={"start_mode":start_mode.get_item_text(start_mode.selected),"position_cm":[start_x.value,start_y.value],"orientation":initial_orientation.get_item_text(initial_orientation.selected)}
	definition.total_duration_s=Data.total(definition);definition.updated_at=Time.get_datetime_string_from_system(true)+"Z"
func add_step() -> void:
	apply_form();definition.steps.append(Data.step());selected_index=definition.steps.size()-1;rebuild()
func delete_step() -> void:
	if selected_index<0 or definition.steps.is_empty():return
	definition.steps.remove_at(selected_index);selected_index=mini(selected_index,definition.steps.size()-1);rebuild()
func move_step(offset: int) -> void:
	apply_form();var target:=selected_index+offset
	if selected_index<0 or target<0 or target>=definition.steps.size():return
	var item: Dictionary=definition.steps[selected_index];definition.steps.remove_at(selected_index);definition.steps.insert(target,item);selected_index=target;rebuild()
func new_sequence() -> void:definition=Data.fresh();display_definition();status.text="Neue, noch nicht gespeicherte Sequenz."
func duplicate_sequence() -> void:collect();definition=store.duplicate_sequence(definition);display_definition();status.text="Kopie mit eigener Kennung erstellt. Zum Behalten speichern."
func load_selected() -> void:
	if saved_list.selected<0:return
	var result:=store.load_sequence(entries[saved_list.selected].id)
	if result.has("error"):status.text=result.error;return
	definition=result.data;display_definition();status.text="Sequenz geladen."
func validate_context() -> String:
	var error:=Data.validate(definition)
	if not error.is_empty():return error
	var context: Dictionary=viewer.sequence_setup_context()
	if context.has("error"):return context.error
	return Runner.preflight(definition,context.config,context.bounds).error
func save_sequence() -> void:
	collect();status.text=validate_context()
	if not status.text.is_empty():return
	status.text=store.save_sequence(definition)
	if status.text.is_empty():status.text="Sequenz gespeichert: "+store.directory;reload_list();rebuild()
func refresh_context() -> void:
	var context: Dictionary=viewer.sequence_setup_context()
	if context.has("error"):context_label.text=context.error;return
	context_label.text="Fisch: %s · Profil: %s · Gesamtlänge: %.2f cm · Hintergrund: #%s
Alle Positionen werden vor dem Start einschließlich Fischrand geprüft. Vorschau trägt eine sichtbare PREVIEW-Kennung; echte Versuche bleiben ohne UI." % [context.project_name,context.calibration.active_profile,context.config.fish_display_length_cm,context.config.background_color.to_html(false)]
func launch(preview: bool) -> void:
	collect();status.text=validate_context()
	if not status.text.is_empty():return
	if not preview and trial_id.text.strip_edges().is_empty():status.text="Bitte eine Versuchs-ID eingeben.";return
	var error: String=await viewer.launch_sequence({"sequence":definition,"trial_id":"PREVIEW" if preview else trial_id.text.strip_edges(),"animal_id":animal_id.text.strip_edges(),"preview":preview,"allow_manual_override":override_box.button_pressed})
	if not error.is_empty():status.text=error
func show_result(reason: String,path: String) -> void:status.text="Versuch beendet: "+reason+"\nProtokoll: "+path;refresh_context()
func close() -> void:hide();closed.emit()
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("stimulus_exit"):close();get_viewport().set_input_as_handled()
