@tool
extends "res://addons/gdscript_extreme_tool/function_name_dialog.gd"

const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExExtractVariable = preload("res://addons/gdscript_extreme_tool/actions/extract_variable.gd")
const GDSExEditApplier = preload("res://addons/gdscript_extreme_tool/editing/edit_applier.gd")

const TITLE : String = "Extract Variable"
const EXTRACT_TEXT : String = "Extract"
const WHERE_TEXT : String = "Where"
const OPTIONS_TEXT : String = "Options"
const RESULT_TEXT : String = "Result"
const MINIMUM_SIZE : Vector2i = Vector2i(680, 520)
const LABEL_MINIMUM_WIDTH : float = 64.0
const CHANGED_LINE_OPACITY : float = 0.18
const MESSAGE_SEPARATOR : String = "\n• "
const LINE_SEPARATOR : String = "\n"

var where_buttons : Dictionary[GDSExExtractVariable.GDSExPlace, Button] = {}
var option_buttons : Dictionary[GDSExExtractVariable.GDSExOption, Button] = {}
var result_preview : CodeEdit

var _context : GDSExCodeContext
var _extraction : GDSExExtractVariable.GDSExExtraction
var _choice : GDSExExtractVariable.GDSExChoice
var _on_plan_ready : Callable
var _has_typed_a_name : bool = false


func _init() -> void:
	title = TITLE
	ok_button_text = EXTRACT_TEXT
	min_size = MINIMUM_SIZE
	var content := VBoxContainer.new()
	add_child(content)
	content.add_child(_build_name_row())
	content.add_child(_build_where_row())
	content.add_child(_build_options_row())
	result_preview = _add_code_preview(content, RESULT_TEXT)
	content.add_child(_build_validation_panel())
	validation_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirmed.connect(_on_confirmed)
	visibility_changed.connect(_focus_name)


func _ready() -> void:
	_use_scaled_size(MINIMUM_SIZE)
	_style_code_preview(result_preview)
	for place in where_buttons:
		_style_filter_button(where_buttons[place])
	for option in option_buttons:
		_style_filter_button(option_buttons[option])
	_refresh()


func setup(context : GDSExCodeContext, on_plan_ready : Callable) -> void:
	_context = context
	_on_plan_ready = on_plan_ready
	_extraction = GDSExExtractVariable.analyze(context)
	if _extraction == null:
		return
	_choice = GDSExExtractVariable.default_choice(_extraction)
	name_edit.text = GDSExExtractVariable.default_name(_extraction, _choice)
	_refresh()


func get_choice() -> GDSExExtractVariable.GDSExChoice:
	return _choice


func _build_where_row() -> Control:
	var row := _build_labelled_row(WHERE_TEXT)
	for place in GDSExExtractVariable.PLACES:
		where_buttons[place] = _add_toggle(row, GDSExExtractVariable.PLACE_LABELS[place], _on_place_toggled.bind(place))
	return row


func _build_options_row() -> Control:
	var row := _build_labelled_row(OPTIONS_TEXT)
	for option in GDSExExtractVariable.OPTIONS:
		option_buttons[option] = _add_toggle(row, GDSExExtractVariable.OPTION_LABELS[option], _on_option_toggled.bind(option))
	return row


func _build_labelled_row(label_text : String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = LABEL_MINIMUM_WIDTH
	row.add_child(label)
	return row


func _add_toggle(row : HBoxContainer, button_text : String, on_toggled : Callable) -> Button:
	var button := Button.new()
	button.text = button_text
	button.toggle_mode = true
	button.toggled.connect(on_toggled)
	row.add_child(button)
	return button


func _refresh() -> void:
	if _extraction == null or _choice == null:
		return
	for place in where_buttons:
		var state := GDSExExtractVariable.place_state(_extraction, place)
		var button := where_buttons[place]
		button.visible = state.is_shown
		button.disabled = not state.is_usable()
		button.tooltip_text = state.reason
		button.set_pressed_no_signal(place == _choice.place)
	for option in option_buttons:
		var state := GDSExExtractVariable.option_state(_extraction, _choice, option)
		var button := option_buttons[option]
		button.disabled = not state.is_enabled()
		button.tooltip_text = state.reason
		button.set_pressed_no_signal(_choice.has(option))
	_show_result()
	_show_checks()


func _show_result() -> void:
	var plan := GDSExExtractVariable.build_plan_for(_extraction, _choice, name_edit.text, _context.indent_unit)
	result_preview.text = LINE_SEPARATOR.join(_context.lines)
	result_preview.clear_undo_history()
	GDSExEditApplier.apply(result_preview, plan)
	var used_line := result_preview.get_caret_line()
	var declaration_lines := GDSExExtractVariable.declaration_lines(_extraction, _choice, name_edit.text)
	var declared_line := GDSExExtractVariable.find_declared_line(result_preview.text.split(LINE_SEPARATOR), declaration_lines[0], used_line)
	var mark_color := Color(_editor_color(ACCENT_COLOR, ACCENT_FALLBACK_COLOR), CHANGED_LINE_OPACITY)
	result_preview.deselect()
	result_preview.set_line_background_color(used_line, mark_color)
	for line in range(declared_line, mini(declared_line + declaration_lines.size(), result_preview.get_line_count())):
		result_preview.set_line_background_color(line, mark_color)
	result_preview.set_line_as_center_visible.call_deferred(mini(declared_line, result_preview.get_line_count() - 1))


func _show_checks() -> void:
	var check := GDSExExtractVariable.check_name(_extraction, _choice, name_edit.text)
	var warnings := GDSExExtractVariable.find_warnings(_extraction, _choice)
	if check.is_error() or warnings.is_empty():
		_show_name_check(check)
		return
	var messages := PackedStringArray()
	if check.level == GDSExFunctionNameCheck.GDSExNameCheck.GDSExLevel.WARNING:
		messages.append(check.message)
	messages.append_array(warnings)
	_show_name_check(GDSExFunctionNameCheck.warning(MESSAGE_SEPARATOR.join(messages)))


func _propose_a_name() -> void:
	if not _has_typed_a_name:
		name_edit.text = GDSExExtractVariable.default_name(_extraction, _choice)


func _on_place_toggled(is_pressed : bool, place : GDSExExtractVariable.GDSExPlace) -> void:
	if is_pressed:
		_choice = GDSExExtractVariable.choice_for_place(_extraction, place, _choice)
		_propose_a_name()
	_refresh()


func _on_option_toggled(is_pressed : bool, option : GDSExExtractVariable.GDSExOption) -> void:
	_choice = GDSExExtractVariable.choice_with_option(_extraction, _choice, option, is_pressed)
	_propose_a_name()
	_refresh()


func _on_name_changed(_new_text : String) -> void:
	_has_typed_a_name = true
	_refresh()


func _on_confirmed() -> void:
	if _extraction != null and _name_check != null and not _name_check.is_error():
		_on_plan_ready.call(GDSExExtractVariable.build_plan_for(_extraction, _choice, name_edit.text, _context.indent_unit))
