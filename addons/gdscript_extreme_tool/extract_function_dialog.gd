@tool
extends "res://addons/gdscript_extreme_tool/function_name_dialog.gd"

const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExExtractFunction = preload("res://addons/gdscript_extreme_tool/actions/extract_function.gd")

const TITLE : String = "Extract Function"
const EXTRACT_TEXT : String = "Extract"
const MINIMUM_SIZE : Vector2i = Vector2i(560, 0)
const LINE_SEPARATOR : String = "\n"

var signature_label : Label
var call_label : Label

var _context : GDSExCodeContext
var _extraction : GDSExExtractFunction.GDSExExtraction
var _on_plan_ready : Callable


func _init() -> void:
	title = TITLE
	ok_button_text = EXTRACT_TEXT
	min_size = MINIMUM_SIZE
	var content := VBoxContainer.new()
	add_child(content)
	content.add_child(_build_name_row())
	signature_label = _build_code_label()
	content.add_child(signature_label)
	call_label = _build_code_label()
	content.add_child(call_label)
	content.add_child(_build_validation_panel())
	confirmed.connect(_on_confirmed)
	visibility_changed.connect(_focus_name)


func _ready() -> void:
	_use_scaled_size(MINIMUM_SIZE)
	_use_source_font(signature_label)
	_use_source_font(call_label)
	_refresh()


func setup(context : GDSExCodeContext, on_plan_ready : Callable) -> void:
	_context = context
	_extraction = GDSExExtractFunction.analyze(context)
	_on_plan_ready = on_plan_ready
	if _extraction.is_valid():
		name_edit.text = GDSExExtractFunction.default_function_name(_extraction)
	_refresh()


func _refresh() -> void:
	if _extraction == null or not _extraction.is_valid():
		return
	_show_code(signature_label, GDSExExtractFunction.signature(_extraction, name_edit.text))
	_show_code(call_label, LINE_SEPARATOR.join(GDSExExtractFunction.call_lines(_extraction, name_edit.text, _context.lines)))
	_show_name_check(GDSExExtractFunction.check_function_name(_extraction, name_edit.text))


func _on_confirmed() -> void:
	if _name_check != null and not _name_check.is_error():
		_on_plan_ready.call(GDSExExtractFunction.build_plan(_context, name_edit.text))
