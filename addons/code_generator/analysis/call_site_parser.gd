@tool
extends RefCounted

const SourceScanner = preload("res://addons/code_generator/analysis/source_scanner.gd")
const Language = preload("res://addons/code_generator/analysis/language.gd")

const CALL_OPENER: String = "("
const MEMBER_ACCESS: String = "."
const ARGUMENT_SEPARATOR: String = ","
const NODE_PATH_PREFIXES: String = "$%"
const NODE_PATH_SEPARATOR: String = "/"
const STRING_PREFIXES: String = "&^r$%"
const QUOTES: String = "\"'"
const SPACES: String = " \t"
const DIGITS: String = "0123456789"


class Argument:
	var text: String = ""
	var offset: int = 0
	var length: int = 0


class CallSite:
	var name: String = ""
	var receiver: String = ""
	var expression_offset: int = 0
	var name_offset: int = 0
	var open_offset: int = 0
	var close_offset: int = 0
	var arguments: Array[Argument] = []
	var parent: CallSite
	var parent_argument_index: int = -1

	func expression_end() -> int:
		return close_offset + 1

	func name_end() -> int:
		return name_offset + name.length()


static func parse(code: String) -> Array[CallSite]:
	var calls: Array[CallSite] = []
	for offset in code.length():
		if code[offset] != CALL_OPENER:
			continue
		var call := _read_call(code, offset)
		if call != null:
			calls.append(call)
	for call in calls:
		_link_parent(call, calls)
	return calls


static func split_arguments(code: String, from: int, to: int) -> Array[Argument]:
	var arguments: Array[Argument] = []
	var depth := 0
	var start := from
	for index in range(from, to):
		var character := code[index]
		if SourceScanner.OPENING_BRACKETS.contains(character):
			depth += 1
		elif SourceScanner.CLOSING_BRACKETS.contains(character):
			depth -= 1
		elif character == ARGUMENT_SEPARATOR and depth == 0:
			_append_argument(arguments, code, start, index)
			start = index + 1
	_append_argument(arguments, code, start, to)
	return arguments


static func _read_call(code: String, open_offset: int) -> CallSite:
	var name_end := _skip_spaces_backwards(code, open_offset)
	var name_start := _identifier_start(code, name_end)
	if name_start == name_end or DIGITS.contains(code[name_start]):
		return null
	var name := code.substr(name_start, name_end - name_start)
	if Language.NON_CALL_KEYWORDS.has(name) or _previous_word(code, name_start) == SourceScanner.FUNCTION_KEYWORD:
		return null
	var call := CallSite.new()
	call.name = name
	call.name_offset = name_start
	call.open_offset = open_offset
	call.close_offset = SourceScanner.find_matching_bracket(code, open_offset)
	if call.close_offset == -1:
		call.close_offset = code.length()
	call.expression_offset = chain_start(code, name_start)
	call.receiver = code.substr(call.expression_offset, name_start - call.expression_offset).strip_edges().trim_suffix(MEMBER_ACCESS).strip_edges()
	call.arguments = split_arguments(code, open_offset + 1, call.close_offset)
	return call


static func _link_parent(call: CallSite, calls: Array[CallSite]) -> void:
	for candidate in calls:
		if candidate == call:
			continue
		if call.expression_offset <= candidate.open_offset or call.expression_offset >= candidate.close_offset:
			continue
		if call.parent == null or candidate.open_offset > call.parent.open_offset:
			call.parent = candidate
	if call.parent == null:
		return
	for index in call.parent.arguments.size():
		var argument := call.parent.arguments[index]
		if call.expression_offset >= argument.offset and call.expression_offset < argument.offset + argument.length:
			call.parent_argument_index = index


static func chain_start(code: String, name_start: int) -> int:
	var start := name_start
	while true:
		var access_end := _skip_spaces_backwards(code, start)
		if access_end == 0 or code[access_end - 1] != MEMBER_ACCESS:
			break
		var primary_end := _skip_spaces_backwards(code, access_end - 1)
		var primary_start := _primary_start(code, primary_end)
		if primary_start == primary_end:
			break
		start = primary_start
	return start


static func _primary_start(code: String, end: int) -> int:
	var start := end
	while start > 0:
		var character := code[start - 1]
		if SourceScanner.CLOSING_BRACKETS.contains(character):
			var open := _matching_open_bracket(code, start - 1)
			if open == -1:
				return start
			start = open
		elif SourceScanner.is_identifier_character(character):
			return _node_path_start(code, _identifier_start(code, start))
		elif QUOTES.contains(character):
			return _string_start(code, start)
		else:
			return start
	return start


static func _matching_open_bracket(code: String, close_index: int) -> int:
	var depth := 0
	for index in range(close_index, -1, -1):
		var character := code[index]
		if SourceScanner.CLOSING_BRACKETS.contains(character):
			depth += 1
		elif SourceScanner.OPENING_BRACKETS.contains(character):
			depth -= 1
			if depth == 0:
				return index
	return -1


static func _node_path_start(code: String, identifier_start: int) -> int:
	var index := identifier_start
	while index > 0 and (code[index - 1] == NODE_PATH_SEPARATOR or SourceScanner.is_identifier_character(code[index - 1])):
		index -= 1
	if index > 0 and NODE_PATH_PREFIXES.contains(code[index - 1]):
		return index - 1
	return identifier_start


static func _string_start(code: String, end: int) -> int:
	var quote := code[end - 1]
	var index := end
	while index > 0 and code[index - 1] == quote:
		index -= 1
	while index > 0 and code[index - 1] == SourceScanner.STRING_FILLER:
		index -= 1
	while index > 0 and code[index - 1] == quote:
		index -= 1
	if index > 0 and STRING_PREFIXES.contains(code[index - 1]):
		index -= 1
	return index


static func _append_argument(arguments: Array[Argument], code: String, from: int, to: int) -> void:
	var raw := code.substr(from, to - from)
	var text := raw.strip_edges()
	if text.is_empty():
		return
	var argument := Argument.new()
	argument.text = text
	argument.offset = from + raw.length() - raw.strip_edges(true, false).length()
	argument.length = text.length()
	arguments.append(argument)


static func _skip_spaces_backwards(code: String, index: int) -> int:
	while index > 0 and SPACES.contains(code[index - 1]):
		index -= 1
	return index


static func _identifier_start(code: String, end: int) -> int:
	var start := end
	while start > 0 and SourceScanner.is_identifier_character(code[start - 1]):
		start -= 1
	return start


static func _previous_word(code: String, index: int) -> String:
	var end := _skip_spaces_backwards(code, index)
	var start := _identifier_start(code, end)
	return code.substr(start, end - start)
