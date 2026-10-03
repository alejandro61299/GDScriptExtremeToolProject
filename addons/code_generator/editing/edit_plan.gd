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


var insertions: Array[Insertion] = []
var replacements: Array[Replacement] = []


func insert(point: InsertionPoint, snippet: Snippet) -> void:
	var insertion := Insertion.new()
	insertion.point = point
	insertion.snippet = snippet
	insertions.append(insertion)


func replace(line: int, from_column: int, to_column: int, text: String) -> void:
	var replacement := Replacement.new()
	replacement.line = line
	replacement.from_column = from_column
	replacement.to_column = to_column
	replacement.text = text
	replacements.append(replacement)


func is_empty() -> bool:
	return insertions.is_empty() and replacements.is_empty()
