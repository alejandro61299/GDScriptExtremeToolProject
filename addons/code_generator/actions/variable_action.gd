@tool
extends "res://addons/code_generator/actions/code_action.gd"

const SymbolIndex = preload("res://addons/code_generator/analysis/symbol_index.gd")
const SourceScanner = preload("res://addons/code_generator/analysis/source_scanner.gd")
const TypeResolver = preload("res://addons/code_generator/analysis/type_resolver.gd")
const Language = preload("res://addons/code_generator/analysis/language.gd")
const Snippet = preload("res://addons/code_generator/editing/snippet.gd")
const Placement = preload("res://addons/code_generator/editing/placement.gd")

const MEMBER_ACCESS : String = "."
const CALL_OPENER : String = "("
const NODE_PATH_PREFIXES : String = "$%"
const ANNOTATION_PREFIX : String = "@"
const NODE_PATH_SEPARATOR : String = "/"
const SPACE : String = " "
const WILDCARD : String = "_"
const VARIABLE_TEMPLATE : String = "var %s"
const TYPED_VARIABLE_TEMPLATE : String = "var %s: %s"

static var _modifiers_pattern := RegEx.create_from_string("^(?:(?:@\\w+(?:\\([^)]*\\))?|static)\\s+)+")
static var _first_word_pattern := RegEx.create_from_string("^\\w+")
static var _parameters_pattern := RegEx.create_from_string("(?:\\bfunc\\b\\s*\\w*|^signal\\s+\\w+)\\s*\\(")


class UndefinedIdentifier:
	var name: String = ""
	var type: SymbolIndex.TypeData


func find_undefined_identifier(context: CodeContext) -> UndefinedIdentifier:
	if context.statement == null:
		return null
	var code := context.statement.code
	var start := context.selection_from
	var end := context.selection_to
	if context.has_selection():
		while start < end and code[start] == SPACE:
			start += 1
		while end > start and code[end - 1] == SPACE:
			end -= 1
	else:
		while start > 0 and SourceScanner.is_identifier_character(code[start - 1]):
			start -= 1
		while end < code.length() and SourceScanner.is_identifier_character(code[end]):
			end += 1
	return find_undefined_identifier_at(code, start, end, context.scope_info)


func find_undefined_identifier_at(code: String, start: int, end: int, scope_info: SymbolIndex.ScopeInfo) -> UndefinedIdentifier:
	var identifier := code.substr(start, end - start)
	if identifier == WILDCARD or not TypeResolver.is_identifier(identifier) or not _is_value(code, start, end):
		return null
	if _declared_names(code).has(identifier) or TypeResolver.is_name_defined(identifier, scope_info):
		return null
	var result := UndefinedIdentifier.new()
	result.name = identifier
	result.type = TypeResolver.expected_value_type(code, start, end, scope_info)
	return result


func declaration_text(identifier: UndefinedIdentifier) -> String:
	var type_text := SymbolIndex.type_to_string(identifier.type)
	if type_text.is_empty():
		return VARIABLE_TEMPLATE % identifier.name
	return TYPED_VARIABLE_TEMPLATE % [identifier.name, type_text]


func _is_value(code: String, start: int, end: int) -> bool:
	if start > 0 and SourceScanner.is_identifier_character(code[start - 1]):
		return false
	if end < code.length() and SourceScanner.is_identifier_character(code[end]):
		return false
	var first_word := _first_word_pattern.search(_modifiers_pattern.sub(code, ""))
	if first_word != null and Language.DECLARATION_STATEMENTS.has(first_word.get_string(0)):
		return false
	var before := start
	while before > 0 and code[before - 1] == SPACE:
		before -= 1
	if before > 0 and not _is_value_after(code, before):
		return false
	var after := SourceScanner.skip_spaces(code, end)
	return after >= code.length() or code[after] != CALL_OPENER


func _is_value_after(code: String, previous_end: int) -> bool:
	var previous := code[previous_end - 1]
	if previous == MEMBER_ACCESS or previous == ANNOTATION_PREFIX or NODE_PATH_PREFIXES.contains(previous):
		return false
	var word_start := previous_end
	while word_start > 0 and (code[word_start - 1] == NODE_PATH_SEPARATOR or SourceScanner.is_identifier_character(code[word_start - 1])):
		word_start -= 1
	if word_start > 0 and NODE_PATH_PREFIXES.contains(code[word_start - 1]):
		return false
	if not SourceScanner.is_identifier_character(previous):
		return true
	word_start = previous_end
	while word_start > 0 and SourceScanner.is_identifier_character(code[word_start - 1]):
		word_start -= 1
	return not Language.DECLARATION_KEYWORDS.has(code.substr(word_start, previous_end - word_start))


func _declared_names(code: String) -> Array:
	var names: Array = []
	for header in _parameters_pattern.search_all(code):
		var open := header.get_end() - 1
		var close := SourceScanner.find_matching_bracket(code, open)
		if close != -1:
			names.append_array(SymbolIndex.parse_func_parameters(code.substr(open + 1, close - open - 1)).keys())
	return names
