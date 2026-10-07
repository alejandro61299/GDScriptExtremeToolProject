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
var selection_first_line: int = -1
var selection_last_line: int = -1
var indent_unit: String = ""


func _init(editor: CodeEdit) -> void:
	lines = editor.text.split(LINE_SEPARATOR)
	index = GDSExSymbolIndexBuilder.build(lines)
	indent_unit = GDSExIndentation.detect_unit(lines, GDSExIndentation.editor_unit(editor))
	var caret_line := editor.get_caret_line()
	scope_info = GDSExSymbolIndex.get_scope_info_for_line(index, caret_line)
	if lines[caret_line].strip_edges().is_empty():
		scope_info = GDSExSymbolIndex.get_scope_info_for_scope(index, _find_blank_line_scope(caret_line, scope_info.scope), caret_line)
	statement = GDSExSourceScanner.find_statement_at(index.statements, caret_line)
	if statement != null:
		_read_selection(editor)
	_read_selected_lines(editor)


func has_selection() -> bool:
	return selection_from != selection_to


func has_selected_lines() -> bool:
	return selection_first_line != -1


func _find_blank_line_scope(blank_line: int, enclosing_scope: GDSExSymbolIndex.GDSExScopeBase) -> GDSExSymbolIndex.GDSExScopeBase:
	var code_line := blank_line - 1
	while code_line >= 0 and lines[code_line].strip_edges().is_empty():
		code_line -= 1
	if code_line < 0:
		return enclosing_scope
	var indent_length := GDSExIndentation.leading_whitespace(lines[blank_line]).length()
	var indented_scope := GDSExSymbolIndex.get_scope_info_for_line(index, code_line).scope
	while indented_scope.parent != null and indent_length <= GDSExIndentation.leading_whitespace(lines[indented_scope.start_line]).length():
		indented_scope = indented_scope.parent
	return indented_scope if _depth(indented_scope) > _depth(enclosing_scope) else enclosing_scope


func _depth(scope: GDSExSymbolIndex.GDSExScopeBase) -> int:
	var depth := 0
	var current := scope.parent
	while current != null:
		depth += 1
		current = current.parent
	return depth


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


func _read_selected_lines(editor: CodeEdit) -> void:
	if not editor.has_selection():
		return
	selection_first_line = editor.get_selection_from_line()
	selection_last_line = editor.get_selection_to_line()
	if selection_last_line > selection_first_line and editor.get_selection_to_column() == 0:
		selection_last_line -= 1
