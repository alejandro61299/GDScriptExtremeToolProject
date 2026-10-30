@tool
extends RefCounted

const GDSExCliSession = preload("res://addons/gdscript_extreme_tool/cli/cli_session.gd")
const GDSExCliLineMap = preload("res://addons/gdscript_extreme_tool/cli/cli_line_map.gd")

const SCRIPT_SUFFIX: String = ".gd"
const PART_SEPARATOR: String = ":"
const STANDARD_INPUT: String = "-"
const LINES_PATTERN: String = "^(\\d+)(?:-(\\d+))?(?::(.*))?$"
const SEARCH_DISTANCE: int = 20
const LISTED_LINES_LIMIT: int = 8
const LINE_LIST_SEPARATOR: String = ", "
const NOT_NEAR_MESSAGE: String = "'%s' is not on line %d of %s or within %d lines of it. Line %d is: %s"
const NOT_FOUND_MESSAGE: String = "'%s' is not in %s"
const AMBIGUOUS_MESSAGE: String = "'%s' appears %d times in %s, on lines %s. Add the line: %s:%d:%s"
const EQUALLY_NEAR_MESSAGE: String = "'%s' is on lines %d and %d of %s, at the same distance from line %d. Write one of those lines."
const OCCURRENCE_MESSAGE: String = "'%s' appears %d times on line %d of %s, not %d."
const TOO_FEW_MESSAGE: String = "'%s' appears %d times in %s, not %d."
const PAST_END_MESSAGE: String = "Line %d is past the end of %s, which has %d lines."
const REMOVED_LINE_MESSAGE: String = "Line %d of %s was removed by an earlier command."
const BACKWARD_RANGE_MESSAGE: String = "The range %d-%d goes backwards."
const MOVED_NOTE: String = "found on line %d"
const WORD_SEPARATOR: String = " "
const TAB: String = "\t"

static var _lines_pattern: RegEx = RegEx.create_from_string(LINES_PATTERN)


class GDSExTarget:
	var written: String = ""
	var path: String = ""
	var first_line: int = -1
	var last_line: int = -1
	var text: String = ""

	func is_standard_input() -> bool:
		return path == STANDARD_INPUT

	func has_lines() -> bool:
		return first_line != -1

	func has_range() -> bool:
		return first_line != -1 and last_line != first_line

	func has_text() -> bool:
		return not text.is_empty()

	func is_whole_script() -> bool:
		return not has_lines() and not has_text()


class GDSExPosition:
	var line: int = -1
	var from_column: int = 0
	var to_column: int = 0
	var first_line: int = -1
	var last_line: int = -1
	var note: String = ""
	var error: String = ""
	var allows_caret: bool = false

	func has_selection() -> bool:
		return to_column > from_column or last_line > first_line

	func selection_attempts() -> Array[bool]:
		if not has_selection():
			return [false]
		return [true, false] if allows_caret else [true]


static func parse(written: String) -> GDSExTarget:
	var target := GDSExTarget.new()
	target.written = written
	if written == STANDARD_INPUT:
		target.path = STANDARD_INPUT
		return target
	var suffix_end := _script_suffix_end(written)
	if suffix_end == -1:
		target.path = written
		return target
	target.path = written.substr(0, suffix_end)
	var rest := written.substr(suffix_end)
	if rest.is_empty():
		return target
	rest = rest.trim_prefix(PART_SEPARATOR)
	var lines_match := _lines_pattern.search(rest)
	if lines_match == null:
		target.text = rest
		return target
	target.first_line = lines_match.get_string(1).to_int() - 1
	target.last_line = lines_match.get_string(2).to_int() - 1 if not lines_match.get_string(2).is_empty() else target.first_line
	target.text = lines_match.get_string(3)
	return target


static func locate(target: GDSExTarget, document: GDSExCliSession.GDSExDocument, nth: int) -> GDSExPosition:
	var position := GDSExPosition.new()
	if target.has_lines():
		var first := _current_line(target.first_line, document, position)
		if not position.error.is_empty():
			return position
		if target.has_range():
			if target.last_line < target.first_line:
				position.error = BACKWARD_RANGE_MESSAGE % [target.first_line + 1, target.last_line + 1]
				return position
			var last := _current_line(target.last_line, document, position)
			if not position.error.is_empty():
				return position
			position.first_line = first
			position.last_line = last
			position.line = first
			position.to_column = document.lines[last].length()
			return position
		if not target.has_text():
			position.line = first
			position.first_line = first
			position.last_line = first
			position.from_column = _first_code_column(document.lines[first])
			position.to_column = position.from_column
			return position
		return _find_near(target, document, first, nth, position)
	if target.has_text():
		return _find_anywhere(target, document, nth, position)
	position.line = 0
	return position


static func _current_line(written_line: int, document: GDSExCliSession.GDSExDocument, position: GDSExPosition) -> int:
	if written_line >= document.original_lines.size() or written_line < 0:
		position.error = PAST_END_MESSAGE % [written_line + 1, document.display_path, document.code_line_count()]
		return -1
	var line := document.current_line(written_line)
	if line == GDSExCliLineMap.REMOVED:
		position.error = REMOVED_LINE_MESSAGE % [written_line + 1, document.display_path]
	return line


static func _find_near(target: GDSExTarget, document: GDSExCliSession.GDSExDocument, line: int, nth: int, position: GDSExPosition) -> GDSExPosition:
	for distance in SEARCH_DISTANCE + 1:
		var above := line - distance
		var below := line + distance
		var has_above := above >= 0 and document.lines[above].contains(target.text)
		var has_below := distance > 0 and below < document.lines.size() and document.lines[below].contains(target.text)
		if has_above and has_below:
			position.error = EQUALLY_NEAR_MESSAGE % [target.text, above + 1, below + 1, document.display_path, line + 1]
			return position
		if has_above or has_below:
			var found_line := above if has_above else below
			if distance > 0:
				position.note = MOVED_NOTE % (found_line + 1)
			return _select_occurrence(target, document, found_line, nth, position)
	position.error = NOT_NEAR_MESSAGE % [target.text, line + 1, document.display_path, SEARCH_DISTANCE, line + 1, document.lines[line].strip_edges()]
	return position


static func _find_anywhere(target: GDSExTarget, document: GDSExCliSession.GDSExDocument, nth: int, position: GDSExPosition) -> GDSExPosition:
	var found_lines := PackedInt32Array()
	var occurrences: Array[Vector2i] = []
	for line in document.lines.size():
		var column := document.lines[line].find(target.text)
		if column != -1:
			found_lines.append(line)
		while column != -1:
			occurrences.append(Vector2i(line, column))
			column = document.lines[line].find(target.text, column + 1)
	if occurrences.is_empty():
		position.error = NOT_FOUND_MESSAGE % [target.text, document.display_path]
		return position
	if nth > 0:
		if nth > occurrences.size():
			position.error = TOO_FEW_MESSAGE % [target.text, occurrences.size(), document.display_path, nth]
			return position
		return _select(occurrences[nth - 1], target.text, position)
	if occurrences.size() > 1:
		position.error = AMBIGUOUS_MESSAGE % [target.text, occurrences.size(), document.display_path, _listed_lines(found_lines), document.display_path, found_lines[0] + 1, target.text]
		return position
	return _select(occurrences[0], target.text, position)


static func _select_occurrence(target: GDSExTarget, document: GDSExCliSession.GDSExDocument, line: int, nth: int, position: GDSExPosition) -> GDSExPosition:
	var columns := PackedInt32Array()
	var column := document.lines[line].find(target.text)
	while column != -1:
		columns.append(column)
		column = document.lines[line].find(target.text, column + 1)
	var wanted := maxi(nth, 1)
	if wanted > columns.size():
		position.error = OCCURRENCE_MESSAGE % [target.text, columns.size(), line + 1, document.display_path, wanted]
		return position
	return _select(Vector2i(line, columns[wanted - 1]), target.text, position)


static func _select(occurrence: Vector2i, text: String, position: GDSExPosition) -> GDSExPosition:
	position.line = occurrence.x
	position.first_line = occurrence.x
	position.last_line = occurrence.x
	position.from_column = occurrence.y
	position.to_column = occurrence.y + text.length()
	position.allows_caret = not text.contains(WORD_SEPARATOR) and not text.contains(TAB)
	return position


static func _listed_lines(lines: PackedInt32Array) -> String:
	var listed := PackedStringArray()
	for index in mini(lines.size(), LISTED_LINES_LIMIT):
		listed.append(str(lines[index] + 1))
	return LINE_LIST_SEPARATOR.join(listed)


static func _first_code_column(line: String) -> int:
	return line.length() - line.strip_edges(true, false).length()


static func _script_suffix_end(written: String) -> int:
	var search_from := 0
	while true:
		var found := written.find(SCRIPT_SUFFIX, search_from)
		if found == -1:
			return -1
		var end := found + SCRIPT_SUFFIX.length()
		if end == written.length() or written[end] == PART_SEPARATOR:
			return end
		search_from = found + 1
	return -1
