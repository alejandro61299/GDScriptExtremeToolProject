@tool
extends RefCounted

const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExCallSiteParser = preload("res://addons/gdscript_extreme_tool/analysis/call_site_parser.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")

const ANNOTATION_PREFIX: String = "@"
const UNIQUE_NODE_PREFIX: String = "%"
const MINUS_SIGN: String = "-"
const MEMBER_ACCESS: String = "."
const AWAIT_KEYWORD: String = "await"
const BLANK_CHARACTERS: String = " \t"
const OPERAND_ENDINGS: String = ")]}\"'"
const GROUP_OPENERS: String = "([{"
const NODE_PREFIXES: String = "$%"
const LINE_SEPARATOR: String = "\n"
const UNEXTRACTABLE_STATEMENTS: Array[String] = ["signal", "class", "class_name", "extends"]
const ACCESSOR_NAMES: Array[String] = ["get", "set"]

static var _text_pattern := RegEx.create_from_string("(?:(?<![\\w.])r|[&^])?(\"\"\"|'''|\"|')[? ]*\\1")
static var _number_pattern := RegEx.create_from_string("(?<![\\w.])(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|\\d[\\d_]*(?:\\.[\\d_]*)?(?:[eE][+-]?\\d+)?)(?!\\w)")
static var _flag_pattern := RegEx.create_from_string("(?<![\\w.])(?:true|false)(?!\\w)")
static var _node_pattern := RegEx.create_from_string("[$%](?:\"[? ]*\"|'[? ]*'|[A-Za-z_]\\w*(?:/(?:[A-Za-z_]\\w*|\\.\\.))*)")
static var _last_word_pattern := RegEx.create_from_string("(\\w+)\\s*$")
static var _first_word_pattern := RegEx.create_from_string("^(?:(?:@\\w+(?:\\([^)]*\\))?|static)\\s+)*(\\w+)")


class GDSExValue:
	enum GDSExKind { LITERAL, CALL, NODE, GROUP }

	var kind: GDSExKind = GDSExKind.LITERAL
	var statement: GDSExSourceScanner.GDSExStatement
	var start: int = 0
	var end: int = 0
	var code: String = ""
	var call: GDSExCallSiteParser.GDSExCallSite

	func first_position() -> Vector2i:
		return statement.position_at(start)

	func last_position() -> Vector2i:
		return statement.position_at(end)

	func is_on_one_line() -> bool:
		return first_position().x == last_position().x

	func is_whole_statement() -> bool:
		return start == 0 and end == statement.code.length()


static func find(statement: GDSExSourceScanner.GDSExStatement, selection_from: int, selection_to: int) -> GDSExValue:
	if statement == null or selection_from < 0 or selection_to < selection_from or not _can_hold_values(statement):
		return null
	var value := _find_selected(statement, selection_from, selection_to) if selection_from != selection_to else _find_at_caret(statement, selection_from)
	if value == null or value.first_position().x == -1 or value.last_position().x == -1 or _holds_a_block(value):
		return null
	return value


static func find_all(statement: GDSExSourceScanner.GDSExStatement) -> Array[GDSExValue]:
	var values: Array[GDSExValue] = []
	if not _can_hold_values(statement):
		return values
	for node in find_nodes(statement.code):
		values.append(_new_value(GDSExValue.GDSExKind.NODE, statement, node.x, node.y))
	for literal in _find_literals(statement.code):
		values.append(_new_value(GDSExValue.GDSExKind.LITERAL, statement, literal.x, literal.y))
	for call in _find_calls(statement.code):
		values.append(_call_value(statement, call))
	return values.filter(func(value: GDSExValue) -> bool: return value.first_position().x != -1 and value.last_position().x != -1 and not _holds_a_block(value))


static func _can_hold_values(statement: GDSExSourceScanner.GDSExStatement) -> bool:
	if statement.is_abandoned or statement.has_unclosed_text:
		return false
	var first_word := _first_word_pattern.search(statement.code)
	return first_word == null or not UNEXTRACTABLE_STATEMENTS.has(first_word.get_string(1))


static func source_lines(value: GDSExValue, lines: PackedStringArray) -> PackedStringArray:
	var first := value.first_position()
	var last := value.last_position()
	if first.x == last.x:
		return PackedStringArray([lines[first.x].substr(first.y, last.y - first.y)])
	var text := PackedStringArray([lines[first.x].substr(first.y)])
	for line in range(first.x + 1, last.x):
		text.append(lines[line])
	text.append(lines[last.x].substr(0, last.y))
	return text


static func source_text(value: GDSExValue, lines: PackedStringArray) -> String:
	return LINE_SEPARATOR.join(source_lines(value, lines))


static func _find_at_caret(statement: GDSExSourceScanner.GDSExStatement, caret: int) -> GDSExValue:
	var code := statement.code
	for node in find_nodes(code):
		if caret >= node.x and caret <= node.y:
			return _new_value(GDSExValue.GDSExKind.NODE, statement, node.x, node.y)
	for literal in _find_literals(code):
		if caret >= literal.x and caret <= literal.y:
			return _new_value(GDSExValue.GDSExKind.LITERAL, statement, literal.x, literal.y)
	var calls := _find_calls(code)
	var named: GDSExCallSiteParser.GDSExCallSite = null
	var chained: GDSExCallSiteParser.GDSExCallSite = null
	for call in calls:
		var is_on_name := caret >= call.name_offset and caret <= call.open_offset + 1
		var is_on_end := caret == call.close_offset or caret == call.expression_end()
		if (is_on_name or is_on_end) and (named == null or call.name_offset > named.name_offset):
			named = call
		if caret >= call.expression_offset and caret < call.name_offset and (chained == null or call.name_offset < chained.name_offset):
			chained = call
	var found := named if named != null else chained
	return null if found == null else _call_value(statement, found)


static func _find_selected(statement: GDSExSourceScanner.GDSExStatement, selection_from: int, selection_to: int) -> GDSExValue:
	var code := statement.code
	var from := selection_from
	var to := selection_to
	while from < to and BLANK_CHARACTERS.contains(code[from]):
		from += 1
	while to > from and BLANK_CHARACTERS.contains(code[to - 1]):
		to -= 1
	if from == to:
		return null
	for node in find_nodes(code):
		if node.x == from and node.y == to:
			return _new_value(GDSExValue.GDSExKind.NODE, statement, from, to)
	for literal in _find_literals(code):
		if literal.x == from and literal.y == to:
			return _new_value(GDSExValue.GDSExKind.LITERAL, statement, from, to)
	for call in _find_calls(code):
		if call.expression_offset == from and call.expression_end() == to:
			return _call_value(statement, call)
	if _is_a_group(code, from, to):
		return _new_value(GDSExValue.GDSExKind.GROUP, statement, from, to)
	return null


static func _find_calls(code: String) -> Array[GDSExCallSiteParser.GDSExCallSite]:
	var calls: Array[GDSExCallSiteParser.GDSExCallSite] = []
	for call in GDSExCallSiteParser.parse(code):
		if call.close_offset >= code.length():
			continue
		if call.name_offset > 0 and code[call.name_offset - 1] == ANNOTATION_PREFIX:
			continue
		if call.name == GDSExLanguage.SUPER_KEYWORD or _is_an_accessor(code, call):
			continue
		if _previous_word(code, call.expression_offset) == AWAIT_KEYWORD and not _is_followed_by_a_member(code, call.expression_end()):
			continue
		calls.append(call)
	return calls


static func _is_an_accessor(code: String, call: GDSExCallSiteParser.GDSExCallSite) -> bool:
	if call.name_offset != 0 or not ACCESSOR_NAMES.has(call.name):
		return false
	var next := GDSExSourceScanner.skip_spaces(code, call.expression_end())
	return next < code.length() and code[next] == GDSExSourceScanner.BLOCK_OPENER


static func _find_literals(code: String) -> Array[Vector2i]:
	var literals: Array[Vector2i] = []
	for text in _text_pattern.search_all(code):
		if text.get_start() == 0 or not NODE_PREFIXES.contains(code[text.get_start() - 1]):
			literals.append(Vector2i(text.get_start(), text.get_end()))
	for number in _number_pattern.search_all(code):
		literals.append(Vector2i(_signed_start(code, number.get_start()), number.get_end()))
	for flag in _flag_pattern.search_all(code):
		literals.append(Vector2i(flag.get_start(), flag.get_end()))
	return literals


static func find_nodes(code: String) -> Array[Vector2i]:
	var nodes: Array[Vector2i] = []
	for node in _node_pattern.search_all(code):
		if code[node.get_start()] == UNIQUE_NODE_PREFIX and _follows_an_operand(code, node.get_start()):
			continue
		nodes.append(Vector2i(node.get_start(), node.get_end()))
	return nodes


static func _signed_start(code: String, number_start: int) -> int:
	if number_start == 0 or code[number_start - 1] != MINUS_SIGN:
		return number_start
	return number_start if _follows_an_operand(code, number_start - 1) else number_start - 1


static func _follows_an_operand(code: String, offset: int) -> bool:
	var before := code.substr(0, offset).strip_edges(false, true)
	if before.is_empty():
		return false
	var last := before[before.length() - 1]
	if OPERAND_ENDINGS.contains(last):
		return true
	if not GDSExSourceScanner.is_identifier_character(last):
		return false
	return not GDSExLanguage.NON_CALL_KEYWORDS.has(_previous_word(code, offset))


static func _previous_word(code: String, offset: int) -> String:
	var word := _last_word_pattern.search(code.substr(0, offset))
	return "" if word == null else word.get_string(1)


static func _is_followed_by_a_member(code: String, offset: int) -> bool:
	var next := GDSExSourceScanner.skip_spaces(code, offset)
	return next < code.length() and code[next] == MEMBER_ACCESS


static func _is_a_group(code: String, from: int, to: int) -> bool:
	if not GROUP_OPENERS.contains(code[from]) or GDSExSourceScanner.find_matching_bracket(code, from) != to - 1:
		return false
	return not _follows_an_operand(code, from)


static func _holds_a_block(value: GDSExValue) -> bool:
	var first_line := value.first_position().x
	var last_line := value.last_position().x
	for block in value.statement.blocks:
		if block.opened_by_function and block.header_line >= first_line and block.last_line < last_line:
			return true
	return false


static func _call_value(statement: GDSExSourceScanner.GDSExStatement, call: GDSExCallSiteParser.GDSExCallSite) -> GDSExValue:
	var value := _new_value(GDSExValue.GDSExKind.CALL, statement, call.expression_offset, call.expression_end())
	value.call = call
	return value


static func _new_value(kind: GDSExValue.GDSExKind, statement: GDSExSourceScanner.GDSExStatement, start: int, end: int) -> GDSExValue:
	var value := GDSExValue.new()
	value.kind = kind
	value.statement = statement
	value.start = start
	value.end = end
	value.code = statement.code.substr(start, end - start)
	return value
