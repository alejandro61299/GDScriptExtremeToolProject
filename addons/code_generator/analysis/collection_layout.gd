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
	var closing_columns: PackedInt32Array = []
	var closing_openings: PackedInt32Array = []
	var opening_offsets: Dictionary[int, int] = {}


static func rewrite(statement: SourceScanner.Statement, lines: PackedStringArray) -> Dictionary[int, PackedStringArray]:
	var rewrites: Dictionary[int, PackedStringArray] = {}
	if statement == null or not statement.blocks.is_empty():
		return rewrites
	var edits := _collect_edits(statement)
	var opening_indents: Dictionary[int, String] = {}
	for piece in statement.pieces:
		if not edits.has(piece.line):
			continue
		var rewritten := _rewrite_line(lines[piece.line], edits[piece.line], opening_indents)
		if rewritten.size() != 1 or rewritten[0] != lines[piece.line]:
			rewrites[piece.line] = rewritten
	return rewrites


static func _collect_edits(statement: SourceScanner.Statement) -> Dictionary[int, LineEdits]:
	var edits: Dictionary[int, LineEdits] = {}
	var open_offsets: PackedInt32Array = []
	for offset in statement.code.length():
		var character := statement.code[offset]
		if SourceScanner.OPENING_BRACKETS.contains(character):
			open_offsets.append(offset)
		elif SourceScanner.CLOSING_BRACKETS.contains(character):
			if open_offsets.is_empty():
				return {}
			var open_offset := open_offsets[open_offsets.size() - 1]
			open_offsets.remove_at(open_offsets.size() - 1)
			_add_collection_edits(statement, open_offset, offset, edits)
	if not open_offsets.is_empty():
		return {}
	return edits


static func _add_collection_edits(statement: SourceScanner.Statement, open_offset: int, close_offset: int, edits: Dictionary[int, LineEdits]) -> void:
	var opening := statement.position_at(open_offset)
	var closing := statement.position_at(close_offset)
	if opening.x == closing.x or not _is_collection_literal(statement.code, open_offset):
		return
	_edits_of(edits, opening.x).opening_offsets[opening.y] = open_offset
	var closing_edits := _edits_of(edits, closing.x)
	closing_edits.closing_columns.append(closing.y)
	closing_edits.closing_openings.append(open_offset)

	var last_offset := close_offset - 1
	while INDENT_CHARACTERS.contains(statement.code[last_offset]):
		last_offset -= 1
	if last_offset == open_offset or statement.code[last_offset] == ELEMENT_SEPARATOR:
		return
	var last_element_end := statement.position_at(last_offset)
	_edits_of(edits, last_element_end.x).comma_columns.append(last_element_end.y + 1)


static func _edits_of(edits: Dictionary[int, LineEdits], line: int) -> LineEdits:
	if not edits.has(line):
		edits[line] = LineEdits.new()
	return edits[line]


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


static func _rewrite_line(raw: String, edits: LineEdits, opening_indents: Dictionary[int, String]) -> PackedStringArray:
	var rewritten := PackedStringArray()
	var segment_indent := raw.substr(0, raw.length() - raw.lstrip(INDENT_CHARACTERS).length())
	var segment_start := 0
	for index in edits.closing_columns.size() + 1:
		var is_last_segment := index == edits.closing_columns.size()
		var segment_end := raw.length() if is_last_segment else edits.closing_columns[index]
		var text := _with_commas(raw, segment_start, segment_end, edits.comma_columns)
		if not is_last_segment:
			text = text.rstrip(INDENT_CHARACTERS)
		if index > 0:
			segment_indent = opening_indents[edits.closing_openings[index - 1]]
			rewritten.append(segment_indent + text)
		elif not text.strip_edges().is_empty():
			rewritten.append(text)
		for column: int in edits.opening_offsets:
			if column >= segment_start and column < segment_end:
				opening_indents[edits.opening_offsets[column]] = segment_indent
		segment_start = segment_end
	return rewritten


static func _with_commas(raw: String, from: int, to: int, comma_columns: PackedInt32Array) -> String:
	var text := raw.substr(from, to - from)
	for column in comma_columns:
		if column > from and column <= to:
			text = text.insert(column - from, ELEMENT_SEPARATOR)
	return text
