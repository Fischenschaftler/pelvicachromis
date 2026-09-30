extends Control
signal closed
const Calibration=preload("res://scripts/stimulus/display_calibration.gd")
const Ruler=preload("res://scripts/stimulus/calibration_ruler.gd")
var calibration: RefCounted
var config: Resource
var model: Node3D
var storage_path: String
var active:=false
var old_mode: int
var old_size: Vector2i
var old_position: Vector2i
var old_mouse: int
var context: Dictionary
var width_input: SpinBox
var fish_input: SpinBox
var reference_input: SpinBox
var measured_input: SpinBox
var info: Label
var status: Label
var diagnostic: Label
var ruler: Control
var correction_button: Button
var save_button: Button
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background:=ColorRect.new();background.color=Color(.09,.10,.12);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,24)
	add_child(margin)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;margin.add_child(scroll)
	var box:=VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_theme_constant_override("separation",12);scroll.add_child(box)
	var title:=Label.new();title.text="Bildschirmkalibrierung · Versuchssetup";title.add_theme_font_size_override("font_size",26);box.add_child(title)
	var explanation:=Label.new();explanation.text="Miss die sichtbare Bildschirmbreite von Bildkante zu Bildkante, ohne Rahmen.
Prüfe anschließend die Referenzlinie mit einem echten Lineal. Monitor-DPI werden nicht als Maßstab verwendet.";explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(explanation)
	info=Label.new();info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(info)
	width_input=number_row(box,"Sichtbare Bildschirmbreite (cm)",0,500,0.01,0)
	fish_input=number_row(box,"Fisch-Gesamtlänge (cm, einschließlich Schwanzflosse)",.1,100,.01,8)
	reference_input=number_row(box,"Sollänge der Referenzlinie (cm)",1,50,.01,10)
	ruler=Ruler.new();box.add_child(ruler)
	measured_input=number_row(box,"Mit Lineal tatsächlich gemessene Länge (cm)",0,100,.01,0)
	correction_button=Button.new();correction_button.text="Messkorrektur anwenden";correction_button.pressed.connect(correct);box.add_child(correction_button)
	diagnostic=Label.new();diagnostic.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(diagnostic)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.modulate=Color(1,.8,.4);box.add_child(status)
	var buttons:=HBoxContainer.new();box.add_child(buttons)
	save_button=Button.new();save_button.text="Kalibrierung speichern";save_button.pressed.connect(save);buttons.add_child(save_button)
	var cancel:=Button.new();cancel.text="Zurück ohne Speichern (Esc)";cancel.pressed.connect(close);buttons.add_child(cancel)
	width_input.value_changed.connect(func(_v):rebuild())
	fish_input.value_changed.connect(func(v):calibration.target_fish_length_cm=v;refresh())
	reference_input.value_changed.connect(func(_v):refresh())
	measured_input.value_changed.connect(func(_v):refresh())
func number_row(parent: Control,text: String,minimum: float,maximum: float,step: float,value: float) -> SpinBox:
	var row:=HBoxContainer.new();parent.add_child(row)
	var label:=Label.new();label.text=text;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;row.add_child(label)
	var input:=SpinBox.new();input.min_value=minimum;input.max_value=maximum;input.step=step;input.value=value;input.custom_minimum_size.x=150;row.add_child(input)
	return input
func open_calibration(fish: Node3D,settings: Resource,path: String="") -> void:
	model=fish;config=settings;storage_path=path;calibration=Calibration.new()
	old_mode=get_window().mode;old_size=get_window().size;old_position=get_window().position;old_mouse=Input.mouse_mode
	if DisplayServer.get_name()!="headless":get_window().mode=Window.MODE_FULLSCREEN
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;show()
	for i in range(6):await get_tree().process_frame
	context=Calibration.display_context(get_window())
	var error: String=calibration.load_profile(storage_path)
	if error.is_empty():error=calibration.mismatch(context)
	width_input.set_value_no_signal(calibration.physical_screen_width_cm)
	fish_input.set_value_no_signal(calibration.target_fish_length_cm)
	active=true
	if not error.is_empty():
		var entered_width: float=calibration.physical_screen_width_cm
		calibration.monitor=context.duplicate(true)
		if entered_width>0:calibration.configure(entered_width,context,fish_input.value)
	status.text=error
	refresh()
func rebuild() -> void:
	if not active:return
	status.text=calibration.configure(width_input.value,context,fish_input.value)
	if not status.text.is_empty():calibration=Calibration.new()
	measured_input.set_value_no_signal(0)
	refresh()
func correct() -> void:
	if not active or not ruler.fits():return
	status.text=calibration.correct_measurement(reference_input.value,measured_input.value)
	if status.text.is_empty():status.text="Messkorrektur angewendet. Bitte die neue Linie erneut mit dem Lineal prüfen."
	measured_input.set_value_no_signal(0);refresh()
func refresh() -> void:
	if not active:return
	var display: Vector2i=get_window().size
	info.text="Monitor %d · Bildschirm %d × %d Pixel · Vollbild-Viewport %d × %d
%.4f Pixel/cm · Höhe %.2f cm (aus quadratischen Pixeln abgeleitet) · Korrekturfaktor %.6f" % [context.monitor_index+1,context.screen_size[0],context.screen_size[1],display.x,display.y,calibration.pixels_per_cm_x,calibration.physical_screen_height_cm,calibration.correction_factor]
	ruler.pixel_length=calibration.reference_pixels(reference_input.value);ruler.reference_cm=reference_input.value;ruler.queue_redraw()
	var measurement:=Calibration.measure_model(model)
	var world: float=calibration.cm_to_world_units(fish_input.value,display,display,config.view_height)
	diagnostic.text="Diagnose (nur Setup): Zielfisch %.2f cm = %.2f Pixel = %.8f Welteinheiten
Modell-Gesamtlänge %.8f · Camera Size %.4f · Darstellungsfaktor %.6f
Geschwindigkeit %.2f cm/s; Größen beziehen sich auf die gerade Ruheform." % [fish_input.value,calibration.reference_pixels(fish_input.value),world,measurement.total_length,config.view_height,world/measurement.total_length,config.speed_cm_s]
	save_button.disabled=not calibration.valid()
	correction_button.disabled=not calibration.valid() or measured_input.value<=0
func save() -> void:
	if not active:return
	var now:=Calibration.display_context(get_window())
	if now!=context:status.text="Monitor geändert. Bitte Breite neu eingeben.";return
	calibration.monitor=context.duplicate(true)
	status.text=calibration.save_profile(storage_path)
	if status.text.is_empty():close()
func close() -> void:
	if not active:return
	active=false;hide();Input.mouse_mode=old_mouse;get_window().mode=old_mode
	if old_mode==Window.MODE_WINDOWED:get_window().size=old_size;get_window().position=old_position
	closed.emit()
func _process(_delta: float) -> void:
	if not active:return
	var now:=Calibration.display_context(get_window())
	if context!=now:
		context=now;calibration=Calibration.new();width_input.set_value_no_signal(0)
		status.text="Monitor oder Auflösung geändert. Bitte sichtbare Breite erneut eingeben.";refresh()
func _input(event: InputEvent) -> void:
	if not active:return
	if event.is_action_pressed("stimulus_exit"):close();get_viewport().set_input_as_handled()
