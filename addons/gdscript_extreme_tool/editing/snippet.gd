@tool
extends RefCounted


class GDSExLine:
	var indent: int = 0
	var text: String = ""


var lines: Array[GDSExLine] = []
var selection_line: int = -1
var selection_from: int = 0
var selection_to: int = 0


func add_line(indent: int, text: String) -> void:
	var line := GDSExLine.new()
	line.indent = indent
	line.text = text
	lines.append(line)


func select_line(line_index: int) -> void:
	select(line_index, 0, lines[line_index].text.length())


func select(line_index: int, from_column: int, to_column: int) -> void:
	selection_line = line_index
	selection_from = from_column
	selection_to = to_column


func has_selection() -> bool:
	return selection_line != -1
