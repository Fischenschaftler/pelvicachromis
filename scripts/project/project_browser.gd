extends VBoxContainer
## Project selection/name dialogs are separate from photo editing and persistence.
var controller: Control
var manager: RefCounted
var label: Label
var save_button: Button
var save_as_button: Button
var name_dialog: ConfirmationDialog
var name_field: LineEdit
var browser: Window
var list: ItemList
var delete_dialog: ConfirmationDialog
var browser_message: Label
var entries: Array=[]
var save_as:=false
var delete_id:=""
func _ready() -> void:
	var storage:=Label.new();storage.text="Portable Projekte · Backup durch Kopieren des Programmordners";storage.tooltip_text=manager.root;storage.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(storage)
	var row:=HFlowContainer.new();add_child(row)
	save_button=make_button(row,"Projekt speichern",func(): request_save(false))
	save_as_button=make_button(row,"Speichern unter",func(): request_save(true))
	make_button(row,"Projekt öffnen",show_projects)
	label=Label.new();label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(label)
	name_dialog=ConfirmationDialog.new();name_dialog.title="Projektname";add_child(name_dialog)
	name_field=LineEdit.new();name_field.placeholder_text="Name des Fischprojekts";name_field.max_length=80;name_field.custom_minimum_size=Vector2(280,40);name_dialog.add_child(name_field)
	name_dialog.confirmed.connect(func(): controller.save_project(name_field.text,save_as))
	browser=Window.new();browser.hide();browser.title="Gespeicherte Foto-Projekte";browser.min_size=Vector2i(320,280);browser.transient=true;browser.exclusive=true;add_child(browser);browser.close_requested.connect(browser.hide)
	var background:=PanelContainer.new();browser.add_child(background);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin:=MarginContainer.new();background.add_child(margin)
	for edge in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+edge,10)
	var column:=VBoxContainer.new();column.custom_minimum_size=Vector2(290,200);margin.add_child(column)
	var info:=Label.new();info.text="Öffnen ersetzt den aktuellen Arbeitsstand.\nUngespeicherte Änderungen vorher speichern.";info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(info);browser_message=info
	list=ItemList.new();list.custom_minimum_size=Vector2(280,100);list.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(list);list.item_activated.connect(func(_index): open_selected())
	row=HFlowContainer.new();column.add_child(row);make_button(row,"Öffnen",open_selected);make_button(row,"Projekt löschen",confirm_delete);make_button(row,"Schließen",browser.hide)
	delete_dialog=ConfirmationDialog.new();delete_dialog.title="Projekt löschen";add_child(delete_dialog);delete_dialog.confirmed.connect(delete_confirmed)
func make_button(parent: Control,title: String,action: Callable) -> Button:
	var button:=Button.new();button.text=title;parent.add_child(button);button.pressed.connect(action);return button
func _process(_delta: float) -> void:
	save_button.disabled=controller.source==null or controller.worker!=null
	save_as_button.disabled=save_button.disabled
	label.text="Projekt: "+(controller.project_name if not controller.project_id.is_empty() else "noch nicht gespeichert")
func request_save(as_new: bool) -> void:
	save_as=as_new
	if not as_new and not controller.project_id.is_empty():controller.save_project(controller.project_name,false);return
	name_field.text=controller.project_name if not controller.project_name.is_empty() else controller.source_path.get_file().get_basename()
	name_dialog.popup_centered_clamped(Vector2i(420,140),.9);name_field.grab_focus();name_field.select_all()
func show_projects() -> void:
	refresh();browser_message.text="Öffnen ersetzt den aktuellen Arbeitsstand.\nUngespeicherte Änderungen vorher speichern.";browser.popup_centered_clamped(Vector2i(620,420),.95)
func refresh() -> void:
	entries=manager.list_projects();list.clear()
	for data in entries:
		var text:="%s · %s · %s" % [data.name,"links" if data.photographed_side=="left" else ("rechts" if data.photographed_side=="right" else "?"),data.updated_at.replace("T"," ").trim_suffix("Z")]
		list.add_item(text);list.set_item_tooltip(list.item_count-1,data.get("error",text))
	if list.item_count>0:list.select(0)
func selected_id() -> String:
	var selected:=list.get_selected_items()
	return "" if selected.is_empty() else entries[selected[0]].id
func open_selected() -> void:
	var id:=selected_id()
	if id.is_empty():return
	if controller.open_project(id):browser.hide()
	else:browser_message.text=controller.last_error
func confirm_delete() -> void:
	delete_id=selected_id()
	if delete_id.is_empty():return
	delete_dialog.dialog_text="Projekt „%s“ aus der Liste entfernen?\nEs wird in den lokalen Projekt-Papierkorb verschoben." % entries[list.get_selected_items()[0]].name
	delete_dialog.popup_centered_clamped(Vector2i(460,180),.9)
func delete_confirmed() -> void:
	var result: Dictionary=manager.delete_project(delete_id)
	if result.has("error"):controller.fail(result.error);browser_message.text=result.error;return
	if controller.project_id==delete_id:controller.reset()
	refresh();controller.status.text="Projekt in den lokalen Papierkorb verschoben."
