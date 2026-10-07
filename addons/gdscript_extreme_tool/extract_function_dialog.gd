@tool
extends "res://addons/gdscript_extreme_tool/function_name_dialog.gd"

const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExExtractFunction = preload("res://addons/gdscript_extreme_tool/actions/extract_function.gd")

const TITLE : String = "Extract Function"
const EXTRACT_TEXT : String = "Extract"
const RESULT_TEXT : String = "Result"
const CALLER_TEXT : String = "Changed function"
const MINIMUM_SIZE : Vector2i = Vector2i(680, 560)
const CALL_LINE_OPACITY : float = 0.18

var form_button : OptionButton
var function_preview : CodeEdit
var caller_preview : CodeEdit

var _context : GDSExCodeContext
var _alternatives : Array[GDSExExtractFunction.GDSExExtraction] = []
var _on_plan_ready : Callable


func _init() -> void:
	title = TITLE
	ok_button_text = EXTRACT_TEXT
	min_size = MINIMUM_SIZE
	var content := VBoxContainer.new()
	add_child(content)
	content.add_child(_build_name_row())
	content.add_child(_build_form_row())
	function_preview = _add_code_preview(content, FUNCTION_TEXT)
	caller_preview = _add_code_preview(content, CALLER_TEXT)
	content.add_child(_build_validation_panel())
	confirmed.connect(_on_confirmed)
	visibility_changed.connect(_focus_name)


func _ready() -> void:
	_use_scaled_size(MINIMUM_SIZE)
	_style_code_preview(function_preview)
	_style_code_preview(caller_preview)
	_refresh()


func setup(context : GDSExCodeContext, on_plan_ready : Callable) -> void:
	_context = context
	_on_plan_ready = on_plan_ready
	_alternatives = GDSExExtractFunction.find_alternatives(context)
	form_button.clear()
	for alternative in _alternatives:
		form_button.add_item(GDSExExtractFunction.form_label(alternative))
	form_button.disabled = _alternatives.size() < 2
	if get_selected_alternative().is_valid():
		name_edit.text = GDSExExtractFunction.default_function_name(get_selected_alternative())
	_refresh()


func get_selected_alternative() -> GDSExExtractFunction.GDSExExtraction:
	return _alternatives[maxi(0, form_button.selected)]


func _build_form_row() -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = RESULT_TEXT
	row.add_child(label)
	form_button = OptionButton.new()
	form_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_button.item_selected.connect(_on_form_selected)
	row.add_child(form_button)
	return row


func _refresh() -> void:
	if _alternatives.is_empty() or not get_selected_alternative().is_valid():
		return
	var extraction := get_selected_alternative()
	function_preview.text = GDSExExtractFunction.function_text(extraction, _context, name_edit.text)
	caller_preview.text = GDSExExtractFunction.caller_text(extraction, _context, name_edit.text)
	_mark_call_lines(extraction)
	_show_name_check(GDSExExtractFunction.check_function_name(extraction, name_edit.text))


func _mark_call_lines(extraction : GDSExExtractFunction.GDSExExtraction) -> void:
	var first_line := GDSExExtractFunction.caller_call_line(extraction)
	var line_count := GDSExExtractFunction.call_lines(extraction, name_edit.text, _context.lines).size()
	var mark_color := Color(_editor_color(ACCENT_COLOR, ACCENT_FALLBACK_COLOR), CALL_LINE_OPACITY)
	for line in range(first_line, mini(first_line + line_count, caller_preview.get_line_count())):
		caller_preview.set_line_background_color(line, mark_color)
	caller_preview.set_line_as_center_visible.call_deferred(mini(first_line, caller_preview.get_line_count() - 1))


func _on_form_selected(_selected_index : int) -> void:
	_refresh()


func _on_confirmed() -> void:
	if _name_check != null and not _name_check.is_error():
		_on_plan_ready.call(GDSExExtractFunction.build_plan_for(get_selected_alternative(), _context, name_edit.text))
