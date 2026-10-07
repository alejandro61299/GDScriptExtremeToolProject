@tool
extends RefCounted

const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExBracketGroups = preload("res://addons/gdscript_extreme_tool/analysis/bracket_groups.gd")

const BLANK_CHARACTERS: String = " \t"
const SEPARATOR: String = " "
const NO_SEPARATOR: String = ""


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
			var text := _spacing_between(groups, run_start, offset)
			var raw := lines[piece.line].substr(column, offset - run_start)
			if raw != text and raw.strip_edges().is_empty():
				_add_spacing(spacings, piece.line, column, raw.length(), text)
			continue
		if offset > piece.offset and not BLANK_CHARACTERS.contains(code[offset - 1]) and _needs_separator(groups, offset):
			_add_spacing(spacings, piece.line, column, 0, SEPARATOR)
		offset += 1


static func _spacing_between(groups: GDSExBracketGroups.GDSExGroups, from: int, to: int) -> String:
	if groups.opens_collection(from - 1) or groups.closes_collection(to):
		return NO_SEPARATOR
	match groups.role_at(to):
		GDSExBracketGroups.GDSExRole.ELEMENT_SEPARATOR:
			return NO_SEPARATOR
		GDSExBracketGroups.GDSExRole.KEY_SEPARATOR:
			return SEPARATOR if groups.group_at(to).spaces_keys() else NO_SEPARATOR
	return SEPARATOR


static func _needs_separator(groups: GDSExBracketGroups.GDSExGroups, offset: int) -> bool:
	match groups.role_at(offset - 1):
		GDSExBracketGroups.GDSExRole.ELEMENT_SEPARATOR:
			return not groups.closes_collection(offset)
		GDSExBracketGroups.GDSExRole.KEY_SEPARATOR:
			return true
	return groups.role_at(offset) == GDSExBracketGroups.GDSExRole.KEY_SEPARATOR and groups.group_at(offset).spaces_keys()


static func _add_spacing(spacings: Dictionary[int, Array], line: int, column: int, length: int, text: String) -> void:
	var spacing := GDSExSpacing.new()
	spacing.column = column
	spacing.length = length
	spacing.text = text
	if not spacings.has(line):
		spacings[line] = []
	spacings[line].append(spacing)
