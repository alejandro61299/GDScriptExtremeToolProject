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


var insertions: Array[Insertion] = []


func insert(point: InsertionPoint, snippet: Snippet) -> void:
	var insertion := Insertion.new()
	insertion.point = point
	insertion.snippet = snippet
	insertions.append(insertion)


func is_empty() -> bool:
	return insertions.is_empty()
