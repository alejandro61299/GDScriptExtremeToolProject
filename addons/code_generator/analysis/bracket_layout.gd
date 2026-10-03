@tool
extends RefCounted

const SourceScanner = preload("res://addons/code_generator/analysis/source_scanner.gd")
const Language = preload("res://addons/code_generator/analysis/language.gd")

const ARRAY_OPENING: String = "["
const DICTIONARY_OPENING: String = "{"
const ELEMENT_SEPARATOR: String = ","
const SUBSCRIPTABLE_ENDINGS: String = ")]}\"'"
const INDENT_CHARACTERS: String = " \t"


class LineEdits:
	var comma_columns: PackedInt32Array = []
	var closings: Dictionary[int, Vector2i] = {}
	var opening_columns: PackedInt32Array = []


static func rewrite(statements: Array[SourceScanner.Statement], lines: PackedStringArray) -> Dictionary[int, PackedStringArray]:
	var edits: Dictionary[int, LineEdits] = {}
	for statement in statements:
		_collect_edits(statement, edits)
	var edited_lines := edits.keys()
	edited_lines.sort()
	var rewrites: Dictionary[int, PackedStringArray] = {}
	var opening_indents: Dictionary[Vector2i, String] = {}
	for line: int in edited_lines:
		var rewritten := _rewrite_line(line, lines[line], edits[line], opening_indents)
		if rewritten.size() != 1 or rewritten[0] != lines[line]:
			rewrites[line] = rewritten
	return rewrites


static func _collect_edits(statement: SourceScanner.Statement, edits: Dictionary[int, LineEdits]) -> void:
	var groups: Array[Vector2i] = []
	var open_offsets: PackedInt32Array = []
	for offset in statement.code.length():
		var character := statement.code[offset]
		if SourceScanner.OPENING_BRACKETS.contains(character):
			open_offsets.append(offset)
		elif SourceScanner.CLOSING_BRACKETS.contains(character):
			if open_offsets.is_empty():
				return
			groups.append(Vector2i(open_offsets[open_offsets.size() - 1], offset))
			open_offsets.remove_at(open_offsets.size() - 1)
	if not open_offsets.is_empty():
		return
	for group in groups:
		_add_group_edits(statement, group.x, group.y, edits)


static func _add_group_edits(statement: SourceScanner.Statement, open_offset: int, close_offset: int, edits: Dictionary[int, LineEdits]) -> void:
	var opening := statement.position_at(open_offset)
	var closing := statement.position_at(close_offset)
	if opening.x == closing.x:
		return
	var is_collection := _is_collection_literal(statement.code, open_offset)
	var lambda := _lambda_ending_at(statement, close_offset)
	if not is_collection and lambda == null:
		return
	_edits_of(edits, opening.x).opening_columns.append(opening.y)
	_edits_of(edits, closing.x).closings[closing.y] = opening
	if not is_collection:
		return

	if lambda != null:
		if not lambda.statements.is_empty():
			_add_comma(edits, _code_end(lambda.statements[lambda.statements.size() - 1]))
		return
	var last_offset := close_offset - 1
	while INDENT_CHARACTERS.contains(statement.code[last_offset]):
		last_offset -= 1
	if last_offset != open_offset and statement.code[last_offset] != ELEMENT_SEPARATOR:
		_add_comma(edits, statement.position_at(last_offset) + Vector2i(0, 1))


static func _add_comma(edits: Dictionary[int, LineEdits], position: Vector2i) -> void:
	_edits_of(edits, position.x).comma_columns.append(position.y)


static func _edits_of(edits: Dictionary[int, LineEdits], line: int) -> LineEdits:
	if not edits.has(line):
		edits[line] = LineEdits.new()
	return edits[line]


static func _lambda_ending_at(statement: SourceScanner.Statement, offset: int) -> SourceScanner.Block:
	for index in range(1, statement.pieces.size()):
		if statement.pieces[index].offset != offset:
			continue
		for block in statement.blocks:
			if block.opened_by_function and block.header_line == statement.pieces[index - 1].line:
				return block
	return null


static func _code_end(statement: SourceScanner.Statement) -> Vector2i:
	var last_piece := statement.pieces[statement.pieces.size() - 1]
	var end := Vector2i(last_piece.line, last_piece.column + last_piece.length)
	for block in statement.blocks:
		if block.statements.is_empty():
			continue
		var inner_end := _code_end(block.statements[block.statements.size() - 1])
		if inner_end.x > end.x or (inner_end.x == end.x and inner_end.y > end.y):
			end = inner_end
	return end


static func _is_collection_literal(code: String, open_offset: int) -> bool:
	if code[open_offset] == DICTIONARY_OPENING:
		return true
	if code[open_offset] != ARRAY_OPENING:
		return false
	var index := open_offset - 1
	while index >= 0 and INDENT_CHARACTERS.contains(code[index]):
		index -= 1
	if index < 0:
		return true
	if SUBSCRIPTABLE_ENDINGS.contains(code[index]):
		return false
	if not SourceScanner.is_identifier_character(code[index]):
		return true
	var word_end := index + 1
	while index >= 0 and SourceScanner.is_identifier_character(code[index]):
		index -= 1
	return Language.NON_CALL_KEYWORDS.has(code.substr(index + 1, word_end - index - 1))


static func _rewrite_line(line: int, raw: String, edits: LineEdits, opening_indents: Dictionary[Vector2i, String]) -> PackedStringArray:
	var rewritten := PackedStringArray()
	var closing_columns := edits.closings.keys()
	closing_columns.sort()
	var segment_indent := raw.substr(0, raw.length() - raw.lstrip(INDENT_CHARACTERS).length())
	var segment_start := 0
	for index in closing_columns.size() + 1:
		var is_last_segment := index == closing_columns.size()
		var segment_end: int = raw.length() if is_last_segment else closing_columns[index]
		var text := _with_commas(raw, segment_start, segment_end, edits.comma_columns)
		if not is_last_segment:
			text = text.rstrip(INDENT_CHARACTERS)
		if index > 0:
			segment_indent = opening_indents[edits.closings[closing_columns[index - 1]]]
			rewritten.append(segment_indent + text)
		elif not text.strip_edges().is_empty():
			rewritten.append(text)
		for column in edits.opening_columns:
			if column >= segment_start and column < segment_end:
				opening_indents[Vector2i(line, column)] = segment_indent
		segment_start = segment_end
	return rewritten


static func _with_commas(raw: String, from: int, to: int, comma_columns: PackedInt32Array) -> String:
	var text := raw.substr(from, to - from)
	for column in comma_columns:
		if column > from and column <= to:
			text = text.insert(column - from, ELEMENT_SEPARATOR)
	return text
