@tool
extends RefCounted

const GDSExSnippet = preload("res://addons/gdscript_extreme_tool/editing/snippet.gd")


class GDSExInsertionPoint:
	var line: int = 0
	var indent_text: String = ""
	var blank_lines_before: int = 0
	var blank_lines_after: int = 0


class GDSExInsertion:
	var point: GDSExInsertionPoint
	var snippet: GDSExSnippet


class GDSExReplacement:
	var line: int = 0
	var from_column: int = 0
	var to_column: int = 0
	var text: String = ""


class GDSExLineReplacement:
	var first_line: int = 0
	var last_line: int = 0
	var lines: PackedStringArray = []
	var line_map: PackedInt32Array = []


var insertions: Array[GDSExInsertion] = []
var replacements: Array[GDSExReplacement] = []
var line_replacement: GDSExLineReplacement
var revealed_insertion: GDSExInsertion


func insert(point: GDSExInsertionPoint, snippet: GDSExSnippet) -> GDSExInsertion:
	var insertion := GDSExInsertion.new()
	insertion.point = point
	insertion.snippet = snippet
	insertions.append(insertion)
	return insertion


func reveal(insertion: GDSExInsertion) -> void:
	revealed_insertion = insertion


func replace(line: int, from_column: int, to_column: int, text: String) -> void:
	var replacement := GDSExReplacement.new()
	replacement.line = line
	replacement.from_column = from_column
	replacement.to_column = to_column
	replacement.text = text
	replacements.append(replacement)


func replace_lines(first_line: int, last_line: int, lines: PackedStringArray, line_map: PackedInt32Array) -> void:
	line_replacement = GDSExLineReplacement.new()
	line_replacement.first_line = first_line
	line_replacement.last_line = last_line
	line_replacement.lines = lines
	line_replacement.line_map = line_map


func is_empty() -> bool:
	return insertions.is_empty() and replacements.is_empty() and line_replacement == null


func leaves_current_position() -> bool:
	if revealed_insertion != null:
		return true
	for insertion in insertions:
		if insertion.snippet.has_selection():
			return true
	return false
