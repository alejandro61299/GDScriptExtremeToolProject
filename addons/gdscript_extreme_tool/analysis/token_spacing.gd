@tool
extends RefCounted

const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExBracketGroups = preload("res://addons/gdscript_extreme_tool/analysis/bracket_groups.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")

const BLANK_CHARACTERS: String = " \t"
const SEPARATOR: String = " "
const NO_SEPARATOR: String = ""
const ELEMENT_SEPARATOR: String = ","
const MEMBER_ACCESS: String = "."
const ATTACHABLE_OPENINGS: String = "(["
const FUNCTION_KEYWORD: String = "func"


class GDSExSpacing:
	var column: int = 0
	var length: int = 0
	var text: String = ""


static func tidy(statements: Array[GDSExSourceScanner.GDSExStatement], lines: PackedStringArray, line_ranges: Array[Vector2i]) -> PackedStringArray:
	var spacings: Dictionary[int, Array] = {}
	var code_ends: Dictionary[int, int] = {}
	for statement in statements:
		var groups := _find_groups(statement.code)
		for piece in statement.pieces:
			_find_untidy_spacings(statement.code, groups, piece, lines, spacings)
			code_ends[piece.line] = maxi(code_ends.get(piece.line, 0), piece.column + piece.length)
	var tidied := lines.duplicate()
	for line: int in spacings:
		var line_spacings: Array = spacings[line]
		line_spacings.sort_custom(func(first: GDSExSpacing, second: GDSExSpacing) -> bool: return first.column > second.column)
		for spacing: GDSExSpacing in line_spacings:
			tidied[line] = tidied[line].substr(0, spacing.column) + spacing.text + tidied[line].substr(spacing.column + spacing.length)
	for line_range in line_ranges:
		for line in range(line_range.x, line_range.y + 1):
			if code_ends.get(line, 0) < lines[line].length() and not lines[line].strip_edges().is_empty():
				tidied[line] = tidied[line].rstrip(BLANK_CHARACTERS)
	return tidied


static func _find_groups(code: String) -> GDSExBracketGroups.GDSExGroups:
	if GDSExBracketGroups.has_collection_brackets(code):
		return GDSExBracketGroups.find(code)
	return GDSExBracketGroups.GDSExGroups.new()


static func _find_untidy_spacings(code: String, groups: GDSExBracketGroups.GDSExGroups, piece: GDSExSourceScanner.GDSExPiece, lines: PackedStringArray, spacings: Dictionary[int, Array]) -> void:
	var piece_end := piece.offset + piece.length
	var offset := piece.offset
	while offset < piece_end:
		var run_start := offset
		while offset < piece_end and BLANK_CHARACTERS.contains(code[offset]):
			offset += 1
		var column := piece.column + run_start - piece.offset
		if offset > run_start:
			var text := _spacing_between(code, groups, piece, run_start, offset)
			var raw := lines[piece.line].substr(column, offset - run_start)
			if raw != text and raw.strip_edges().is_empty():
				_add_spacing(spacings, piece.line, column, raw.length(), text)
			continue
		if offset > piece.offset and not BLANK_CHARACTERS.contains(code[offset - 1]) and _needs_separator(code, groups, piece, offset):
			_add_spacing(spacings, piece.line, column, 0, SEPARATOR)
		offset += 1


static func _spacing_between(code: String, groups: GDSExBracketGroups.GDSExGroups, piece: GDSExSourceScanner.GDSExPiece, from: int, to: int) -> String:
	var previous := code[from - 1]
	var next := code[to]
	if previous == GDSExBracketGroups.DICTIONARY_OPENING and next == GDSExBracketGroups.DICTIONARY_CLOSING:
		return NO_SEPARATOR
	if previous == GDSExBracketGroups.DICTIONARY_OPENING:
		return _brace_padding(groups.group_at(from), piece)
	if next == GDSExBracketGroups.DICTIONARY_CLOSING:
		return _brace_padding(groups.group_at(to), piece)
	if GDSExSourceScanner.OPENING_BRACKETS.contains(previous) or GDSExSourceScanner.CLOSING_BRACKETS.contains(next) or next == ELEMENT_SEPARATOR:
		return NO_SEPARATOR
	if ATTACHABLE_OPENINGS.contains(next) and _attaches_bracket(code, from):
		return NO_SEPARATOR
	return SEPARATOR


static func _needs_separator(code: String, groups: GDSExBracketGroups.GDSExGroups, piece: GDSExSourceScanner.GDSExPiece, offset: int) -> bool:
	var previous := code[offset - 1]
	var next := code[offset]
	if previous == GDSExBracketGroups.DICTIONARY_OPENING or next == GDSExBracketGroups.DICTIONARY_CLOSING:
		var is_empty := previous == GDSExBracketGroups.DICTIONARY_OPENING and next == GDSExBracketGroups.DICTIONARY_CLOSING
		return not is_empty and _is_padded(groups.group_at(offset), piece)
	if previous == ELEMENT_SEPARATOR:
		return not GDSExSourceScanner.CLOSING_BRACKETS.contains(next)
	if groups.role_at(offset - 1) == GDSExBracketGroups.GDSExRole.KEY_SEPARATOR or groups.role_at(offset) == GDSExBracketGroups.GDSExRole.KEY_SEPARATOR:
		return true
	return ATTACHABLE_OPENINGS.contains(next) and _ends_with_keyword(code, offset) and not _attaches_bracket(code, offset)


static func _brace_padding(group: GDSExBracketGroups.GDSExGroup, piece: GDSExSourceScanner.GDSExPiece) -> String:
	return SEPARATOR if group == null or _is_padded(group, piece) else NO_SEPARATOR


static func _is_padded(group: GDSExBracketGroups.GDSExGroup, piece: GDSExSourceScanner.GDSExPiece) -> bool:
	if group == null or group.is_enum:
		return false
	return group.open_offset >= piece.offset and group.close_offset < piece.offset + piece.length


static func _attaches_bracket(code: String, token_end: int) -> bool:
	var last := code[token_end - 1]
	if GDSExBracketGroups.SUBSCRIPTABLE_ENDINGS.contains(last):
		return true
	if not GDSExSourceScanner.is_identifier_character(last):
		return false
	return not _ends_with_keyword(code, token_end) or _word_ending_at(code, token_end) == FUNCTION_KEYWORD


static func _ends_with_keyword(code: String, token_end: int) -> bool:
	var word := _word_ending_at(code, token_end)
	var word_start := token_end - word.length()
	if word.is_empty() or (word_start > 0 and code[word_start - 1] == MEMBER_ACCESS):
		return false
	return GDSExLanguage.NON_CALL_KEYWORDS.has(word)


static func _word_ending_at(code: String, token_end: int) -> String:
	var word_start := token_end
	while word_start > 0 and GDSExSourceScanner.is_identifier_character(code[word_start - 1]):
		word_start -= 1
	return code.substr(word_start, token_end - word_start)


static func _add_spacing(spacings: Dictionary[int, Array], line: int, column: int, length: int, text: String) -> void:
	var spacing := GDSExSpacing.new()
	spacing.column = column
	spacing.length = length
	spacing.text = text
	if not spacings.has(line):
		spacings[line] = []
	spacings[line].append(spacing)
