@tool
extends RefCounted

const Snippet = preload("res://addons/code_generator/editing/snippet.gd")


class InsertionPoint:
	var line: int = 0
	var indent_text: String = ""
	var blank_lines_before: int = 0
	var blank_lines_after: int = 0


class Insertion:
	var point: InsertionPoint
	var snippet: Snippet


class Replacement:
	var line: int = 0
	var from_column: int = 0
	var to_column: int = 0
	var text: String = ""


class LineReplacement:
	var first_line: int = 0
	var last_line: int = 0
	var lines: PackedStringArray = []
	var line_map: PackedInt32Array = []


var insertions: Array[Insertion] = []
var replacements: Array[Replacement] = []
var line_replacement: LineReplacement
var revealed_insertion: Insertion


func insert(point: InsertionPoint, snippet: Snippet) -> Insertion:
	var insertion := Insertion.new()
	insertion.point = point
	insertion.snippet = snippet
	insertions.append(insertion)
	return insertion


func reveal(insertion: Insertion) -> void:
	revealed_insertion = insertion


func replace(line: int, from_column: int, to_column: int, text: String) -> void:
	var replacement := Replacement.new()
	replacement.line = line
	replacement.from_column = from_column
	replacement.to_column = to_column
	replacement.text = text
	replacements.append(replacement)


func replace_lines(first_line: int, last_line: int, lines: PackedStringArray, line_map: PackedInt32Array) -> void:
	line_replacement = LineReplacement.new()
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
