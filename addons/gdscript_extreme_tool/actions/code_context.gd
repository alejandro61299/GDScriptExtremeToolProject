@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSymbolIndexBuilder = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index_builder.gd")
const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExIndentation = preload("res://addons/gdscript_extreme_tool/editing/indentation.gd")

const LINE_SEPARATOR: String = "\n"

var lines: PackedStringArray = []
var index: GDSExSymbolIndex.GDSExSymbolIndexData
var scope_info: GDSExSymbolIndex.GDSExScopeInfo
var statement: GDSExSourceScanner.GDSExStatement
var selection_from: int = -1
var selection_to: int = -1
var indent_unit: String = ""


func _init(editor: CodeEdit) -> void:
	lines = editor.text.split(LINE_SEPARATOR)
	index = GDSExSymbolIndexBuilder.build(lines)
	indent_unit = GDSExIndentation.detect_unit(lines, GDSExIndentation.editor_unit(editor))
	var caret_line := editor.get_caret_line()
	scope_info = GDSExSymbolIndex.get_scope_info_for_line(index, caret_line)
	statement = GDSExSourceScanner.find_statement_at(index.statements, caret_line)
	if statement != null:
		_read_selection(editor)


func has_selection() -> bool:
	return selection_from != selection_to


func _read_selection(editor: CodeEdit) -> void:
	var caret := statement.offset_at(editor.get_caret_line(), editor.get_caret_column())
	selection_from = caret
	selection_to = caret
	if not editor.has_selection():
		return
	var from := statement.offset_at(editor.get_selection_from_line(), editor.get_selection_from_column())
	var to := statement.offset_at(editor.get_selection_to_line(), editor.get_selection_to_column())
	if from != -1 and to != -1:
		selection_from = from
		selection_to = to
