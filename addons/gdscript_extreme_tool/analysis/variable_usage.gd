@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExBracketGroups = preload("res://addons/gdscript_extreme_tool/analysis/bracket_groups.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")

const MEMBER_ACCESS: String = "."
const CALL_OPENER: String = "("
const PARAMETER_SEPARATOR: String = ","
const BLOCK_OPENER: String = ":"
const ASSIGNMENT: String = "="
const NODE_PATH_START: String = "$"
const UNIQUE_NODE_START: String = "%"
const NODE_PATH_SEPARATOR: String = "/"
const ANNOTATION_START: String = "@"
const BLANK_CHARACTERS: String = " \t"
const OPERAND_ENDINGS: String = ")]}\"'"
const COMPARISON_PREFIXES: String = "!<>="
const COMPOUND_PREFIXES: String = "+-*/%&|^~"
const REPEATABLE_PREFIXES: String = "*<>"
const NAME_DECLARING_KEYWORDS: Array[String] = ["var", "const", "for"]
const INLINE_BLOCK_KEYWORDS: Array[String] = ["if", "elif", "else", "for", "while", "match", "when"]

static var _identifier_pattern := RegEx.create_from_string("(?<![\\w.])[A-Za-z_]\\w*")
static var _first_word_pattern := RegEx.create_from_string("^\\w+")
static var _last_word_pattern := RegEx.create_from_string("(\\w+)\\s*$")
static var _lambda_header_pattern := RegEx.create_from_string("\\bfunc\\b\\s*\\w*\\s*\\(")
static var _target_pattern := RegEx.create_from_string("^([A-Za-z_]\\w*)\\s*(.*)$")
static var _declaration_pattern := RegEx.create_from_string("^(var|const)\\s+(\\w+)\\s*")


class GDSExOccurrence:
	var name: String = ""
	var statement: GDSExSourceScanner.GDSExStatement
	var offset: int = 0
	var line: int = 0
	var lookup: GDSExSymbolIndex.GDSExVariableLookup


class GDSExAssignment:
	var statement_start: int = 0
	var is_declaration: bool = false
	var keyword: String = ""
	var root_name: String = ""
	var is_plain_target: bool = false
	var is_compound: bool = false
	var is_inferred: bool = false
	var declared_type_text: String = ""
	var operator_start: int = 0
	var operator_end: int = 0
	var value_start: int = 0


class GDSExLambda:
	var open_offset: int = 0
	var close_offset: int = 0
	var end_offset: int = 0
	var parameter_names: PackedStringArray = []


static func find_local_names(function: GDSExSymbolIndex.GDSExScopeBase) -> Dictionary[String, bool]:
	var names: Dictionary[String, bool] = {}
	_collect_local_names(function, names)
	return names


static func find_occurrences(index: GDSExSymbolIndex.GDSExSymbolIndexData, statements: Array[GDSExSourceScanner.GDSExStatement], local_names: Dictionary[String, bool]) -> Array[GDSExOccurrence]:
	var occurrences: Array[GDSExOccurrence] = []
	for statement in statements:
		_collect_occurrences(index, statement, local_names, occurrences)
	return occurrences


static func find_writes(statements: Array[GDSExSourceScanner.GDSExStatement]) -> Dictionary[GDSExSourceScanner.GDSExStatement, GDSExAssignment]:
	var writes: Dictionary[GDSExSourceScanner.GDSExStatement, GDSExAssignment] = {}
	for statement in statements:
		_collect_writes(statement, writes)
	return writes


static func declared_name(code: String) -> String:
	var declaration := _declaration_pattern.search(code)
	return "" if declaration == null else declaration.get_string(2)


static func declared_type_text(code: String) -> String:
	var declaration := _declaration_pattern.search(code)
	return "" if declaration == null else GDSExSymbolIndex.parse_declaration_tail(code, declaration.get_end()).type_text


static func is_call_opener(code: String, open_offset: int) -> bool:
	var before := code.substr(0, open_offset).strip_edges(false, true)
	if before.is_empty():
		return false
	if OPERAND_ENDINGS.contains(before[before.length() - 1]):
		return true
	var word := _last_word_pattern.search(before)
	return word != null and word.get_end(1) == before.length() and not GDSExLanguage.NON_CALL_KEYWORDS.has(word.get_string(1))


static func is_inside_a_typed_group(code: String, groups: GDSExBracketGroups.GDSExGroups, offset: int, from_offset: int) -> bool:
	for group in groups.groups:
		if group.open_offset < from_offset or group.open_offset > offset or group.close_offset < offset:
			continue
		if code[group.open_offset] != CALL_OPENER or is_call_opener(code, group.open_offset):
			return true
	return false


static func parse_assignment(code: String) -> GDSExAssignment:
	var start := _skip_inline_blocks(code, 0)
	var declaration := _declaration_pattern.search(code.substr(start))
	if declaration != null:
		return _parse_declaration(code, start, declaration)
	var operator_index := _find_assignment_operator(code, start)
	if operator_index == -1:
		return null
	var pattern_end := _find_last_block_opener(code, start, operator_index)
	if pattern_end != -1:
		start = GDSExSourceScanner.skip_spaces(code, pattern_end + 1)
		declaration = _declaration_pattern.search(code.substr(start))
		if declaration != null:
			return _parse_declaration(code, start, declaration)
	var assignment := GDSExAssignment.new()
	assignment.statement_start = start
	assignment.operator_end = operator_index + 1
	assignment.operator_start = _operator_start(code, operator_index)
	assignment.is_compound = assignment.operator_start < operator_index
	assignment.value_start = GDSExSourceScanner.skip_spaces(code, assignment.operator_end)
	var target := _target_pattern.search(code.substr(start, assignment.operator_start - start).strip_edges())
	if target != null and not target.get_string(2).begins_with(CALL_OPENER):
		assignment.root_name = target.get_string(1)
		assignment.is_plain_target = target.get_string(2).is_empty()
	return assignment


static func _collect_local_names(scope: GDSExSymbolIndex.GDSExScopeBase, names: Dictionary[String, bool]) -> void:
	if scope is GDSExSymbolIndex.GDSExClassScope:
		return
	if scope is GDSExSymbolIndex.GDSExFunctionScope:
		for parameter_name: String in (scope as GDSExSymbolIndex.GDSExFunctionScope).params:
			names[parameter_name] = true
	for local in scope.locals:
		names[local.name] = true
	for child in scope.children:
		_collect_local_names(child, names)


static func _collect_occurrences(index: GDSExSymbolIndex.GDSExSymbolIndexData, statement: GDSExSourceScanner.GDSExStatement, local_names: Dictionary[String, bool], occurrences: Array[GDSExOccurrence]) -> void:
	var code := statement.code
	var lambdas := _find_lambdas(statement)
	var groups: GDSExBracketGroups.GDSExGroups = null
	for identifier in _identifier_pattern.search_all(code):
		var name := identifier.get_string()
		var offset := identifier.get_start()
		if not local_names.has(name) or not _is_variable_use(code, offset, identifier.get_end(), lambdas):
			continue
		if code.contains(GDSExBracketGroups.DICTIONARY_OPENING):
			if groups == null:
				groups = GDSExBracketGroups.find(code)
			if _is_dictionary_key(code, groups, offset, identifier.get_end()):
				continue
		var position := statement.position_at(offset)
		var lookup := GDSExSymbolIndex.find_variable(name, GDSExSymbolIndex.get_scope_info_for_line(index, position.x))
		if not lookup.is_defined or lookup.scope is GDSExSymbolIndex.GDSExClassScope:
			continue
		var occurrence := GDSExOccurrence.new()
		occurrence.name = name
		occurrence.statement = statement
		occurrence.offset = offset
		occurrence.line = position.x
		occurrence.lookup = lookup
		occurrences.append(occurrence)
	for block in statement.blocks:
		for inner in block.statements:
			_collect_occurrences(index, inner, local_names, occurrences)


static func _is_variable_use(code: String, start: int, end: int, lambdas: Array[GDSExLambda]) -> bool:
	var previous := start - 1
	while previous >= 0 and BLANK_CHARACTERS.contains(code[previous]):
		previous -= 1
	var next := GDSExSourceScanner.skip_spaces(code, end)
	if next < code.length() and code[next] == CALL_OPENER:
		return false
	if previous >= 0:
		if code[previous] == MEMBER_ACCESS or code[previous] == ANNOTATION_START or _is_inside_node_path(code, start):
			return false
		var word_before := _last_word_pattern.search(code.substr(0, start))
		if word_before != null and NAME_DECLARING_KEYWORDS.has(word_before.get_string(1)):
			return false
	for lambda in lambdas:
		if start > lambda.open_offset and start < lambda.close_offset and (code[previous] == CALL_OPENER or code[previous] == PARAMETER_SEPARATOR):
			return false
		if start > lambda.close_offset and start < lambda.end_offset and lambda.parameter_names.has(code.substr(start, end - start)):
			return false
	return true


static func _is_inside_node_path(code: String, start: int) -> bool:
	var index := start - 1
	while index >= 0 and (code[index] == NODE_PATH_SEPARATOR or GDSExSourceScanner.is_identifier_character(code[index])):
		index -= 1
	if index < 0:
		return false
	if code[index] == NODE_PATH_START:
		return true
	if code[index] != UNIQUE_NODE_START:
		return false
	var before := index - 1
	while before >= 0 and BLANK_CHARACTERS.contains(code[before]):
		before -= 1
	return before < 0 or not (GDSExSourceScanner.is_identifier_character(code[before]) or OPERAND_ENDINGS.contains(code[before]))


static func _is_dictionary_key(code: String, groups: GDSExBracketGroups.GDSExGroups, start: int, end: int) -> bool:
	var next := GDSExSourceScanner.skip_spaces(code, end)
	if next >= code.length() or code[next] != ASSIGNMENT or code.substr(next + 1, 1) == ASSIGNMENT:
		return false
	var group := groups.group_at(start)
	return group != null and code[group.open_offset] == GDSExBracketGroups.DICTIONARY_OPENING


static func _find_lambdas(statement: GDSExSourceScanner.GDSExStatement) -> Array[GDSExLambda]:
	var lambdas: Array[GDSExLambda] = []
	var code := statement.code
	for header in _lambda_header_pattern.search_all(code):
		var lambda := GDSExLambda.new()
		lambda.open_offset = header.get_end() - 1
		lambda.close_offset = GDSExSourceScanner.find_matching_bracket(code, lambda.open_offset)
		if lambda.close_offset == -1:
			continue
		lambda.parameter_names = PackedStringArray(GDSExSymbolIndex.parse_func_parameters(code.substr(lambda.open_offset + 1, lambda.close_offset - lambda.open_offset - 1)).keys())
		lambda.end_offset = _lambda_end(code, lambda.close_offset)
		lambdas.append(lambda)
	return lambdas


static func _lambda_end(code: String, close_offset: int) -> int:
	var header_end := GDSExSymbolIndex.find_top_level(code, BLOCK_OPENER, close_offset + 1)
	if header_end == -1:
		return close_offset
	var depth := 0
	for index in range(header_end + 1, code.length()):
		var character := code[index]
		if GDSExSourceScanner.OPENING_BRACKETS.contains(character):
			depth += 1
		elif GDSExSourceScanner.CLOSING_BRACKETS.contains(character):
			depth -= 1
			if depth < 0:
				return index
		elif character == PARAMETER_SEPARATOR and depth == 0:
			return index
	return code.length()


static func _collect_writes(statement: GDSExSourceScanner.GDSExStatement, writes: Dictionary[GDSExSourceScanner.GDSExStatement, GDSExAssignment]) -> void:
	var assignment := parse_assignment(statement.code)
	if assignment != null:
		writes[statement] = assignment
	for block in statement.blocks:
		if block.opened_by_function:
			continue
		for inner in block.statements:
			_collect_writes(inner, writes)


static func _parse_declaration(code: String, start: int, declaration: RegExMatch) -> GDSExAssignment:
	var assignment := GDSExAssignment.new()
	assignment.statement_start = start
	assignment.is_declaration = true
	assignment.keyword = declaration.get_string(1)
	assignment.root_name = declaration.get_string(2)
	assignment.is_plain_target = true
	var tail := GDSExSymbolIndex.parse_declaration_tail(code, start + declaration.get_end())
	if not tail.has_value():
		return null
	assignment.is_inferred = tail.is_inferred
	assignment.operator_start = tail.operator_start
	assignment.operator_end = tail.operator_end
	assignment.value_start = tail.value_start
	assignment.declared_type_text = tail.type_text
	return assignment


static func _skip_inline_blocks(code: String, from: int) -> int:
	var start := from
	while true:
		var word := _first_word_pattern.search(code.substr(start))
		if word == null or not INLINE_BLOCK_KEYWORDS.has(word.get_string()):
			return start
		var opener := _find_block_opener(code, start)
		if opener == -1:
			return start
		start = GDSExSourceScanner.skip_spaces(code, opener + 1)
	return start


static func _find_block_opener(code: String, from: int) -> int:
	var index := GDSExSymbolIndex.find_top_level(code, BLOCK_OPENER, from)
	while index != -1 and code.substr(index + 1, 1) == ASSIGNMENT:
		index = GDSExSymbolIndex.find_top_level(code, BLOCK_OPENER, index + 1)
	return index


static func _find_last_block_opener(code: String, from: int, before: int) -> int:
	var last := -1
	var index := _find_block_opener(code, from)
	while index != -1 and index < before:
		last = index
		index = _find_block_opener(code, index + 1)
	return last


static func _find_assignment_operator(code: String, from: int) -> int:
	var index := GDSExSymbolIndex.find_top_level(code, ASSIGNMENT, from)
	while index != -1:
		var is_comparison := code.substr(index + 1, 1) == ASSIGNMENT
		if index > 0 and COMPARISON_PREFIXES.contains(code[index - 1]):
			is_comparison = is_comparison or code[index - 1] == ASSIGNMENT or index < 2 or code[index - 2] != code[index - 1] or not REPEATABLE_PREFIXES.contains(code[index - 1])
		if index > 0 and code[index - 1] == BLOCK_OPENER:
			return -1
		if not is_comparison:
			return index
		index = GDSExSymbolIndex.find_top_level(code, ASSIGNMENT, index + (2 if code.substr(index + 1, 1) == ASSIGNMENT else 1))
	return -1


static func _operator_start(code: String, operator_index: int) -> int:
	var start := operator_index
	if start > 0 and (COMPOUND_PREFIXES.contains(code[start - 1]) or REPEATABLE_PREFIXES.contains(code[start - 1])):
		start -= 1
		if start > 0 and code[start - 1] == code[start] and REPEATABLE_PREFIXES.contains(code[start]):
			start -= 1
	return start
