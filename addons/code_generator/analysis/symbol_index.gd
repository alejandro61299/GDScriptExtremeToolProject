@tool
extends RefCounted

const SourceScanner = preload("res://addons/code_generator/analysis/source_scanner.gd")
const Language = preload("res://addons/code_generator/analysis/language.gd")

const TYPE_SEPARATOR: String = ","
const INFERRED_ASSIGNMENT: String = ":="
const TYPE_ANNOTATION: String = ":"
const ASSIGNMENT: String = "="
const LAMBDA_PREFIXES: Array[String] = ["func(", "func "]
const NUMBER_SEPARATOR: String = "_"

static var _string_literal_pattern := RegEx.create_from_string("^(&|\\^|r)?[\"']{1,3}\\?*[\"']{1,3}$")
static var _constructor_pattern := RegEx.create_from_string("^([A-Za-z_]\\w*)\\s*[\\(\\.]")


class TypeData:
	var name: String = ""
	var generics: Array[TypeData] = []


class VariableSymbol:
	enum Deferred { NONE, VALUE, ITERATION }

	var name: String = ""
	var type: TypeData
	var is_const: bool = false
	var start_line: int = 0
	var end_line: int = 0
	var value_code: String = ""
	var deferred: Deferred = Deferred.NONE
	var function: FunctionScope


class SignalSymbol:
	var name: String = ""
	var params: Dictionary = {}


class DeclarationTail:
	var type: TypeData
	var value: String = ""


class VariableLookup:
	var is_defined: bool = false
	var type: TypeData
	var symbol: VariableSymbol


class ScopeBase:
	var children: Array[ScopeBase] = []
	var locals: Array[VariableSymbol] = []
	var start_line: int = 0
	var body_start_line: int = -1
	var end_line: int = 0
	var body_indent_text: String = ""
	var parent: ScopeBase:
		get:
			return _parent_reference.get_ref() as ScopeBase if _parent_reference != null else null
	var _parent_reference: WeakRef

	func attach_to(new_parent: ScopeBase) -> void:
		_parent_reference = weakref(new_parent)
		new_parent.children.append(self)

	func enclose_in(enclosing_scope: ScopeBase) -> void:
		_parent_reference = weakref(enclosing_scope)

	func first_contained_line() -> int:
		return start_line

	func accepts_declarations() -> bool:
		return body_start_line != -1

	func find_local(local_name: String, before_line: int) -> VariableSymbol:
		for index in range(locals.size() - 1, -1, -1):
			var local := locals[index]
			if local.name == local_name and local.start_line < before_line:
				return local
		return null


class FunctionScope extends ScopeBase:
	var name: String = ""
	var is_lambda: bool = false
	var is_static: bool = false
	var is_inline: bool = false
	var params: Dictionary = {}
	var return_type: TypeData
	var return_codes: PackedStringArray = []
	var return_lines: PackedInt32Array = []

	func first_contained_line() -> int:
		return body_start_line if is_lambda else start_line


class BlockScope extends ScopeBase:
	enum Kind { IF, ELIF, ELSE, FOR, WHILE, MATCH, MATCH_BRANCH, PROPERTY, OTHER }

	var kind: Kind = Kind.OTHER

	func first_contained_line() -> int:
		return body_start_line

	func accepts_declarations() -> bool:
		return kind != Kind.MATCH and kind != Kind.PROPERTY


class ClassScope extends ScopeBase:
	var name: String = ""
	var vars: Dictionary = {}
	var methods: Dictionary = {}
	var signals: Dictionary = {}
	var inner_classes: Dictionary = {}
	var extends_line: int = -1
	var inherit_type: TypeData

	func accepts_declarations() -> bool:
		return false


class SymbolIndexData:
	var root: ClassScope
	var statements: Array[SourceScanner.Statement] = []


class ScopeInfo:
	var index: SymbolIndexData
	var line: int = 0
	var scope: ScopeBase
	var class_scope: ClassScope
	var function_scope: FunctionScope


static func make_type(type_name: String) -> TypeData:
	var type := TypeData.new()
	type.name = type_name
	return type


static func get_base_type_name(type: TypeData) -> String:
	return "" if type == null else type.name


static func type_to_string(type: TypeData) -> String:
	if type == null:
		return ""
	if type.generics.is_empty():
		return type.name
	var generic_texts := PackedStringArray()
	for generic in type.generics:
		generic_texts.append(type_to_string(generic))
	return "%s[%s]" % [type.name, (TYPE_SEPARATOR + " ").join(generic_texts)]


static func parse_type(text: String) -> TypeData:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return null
	var bracket := trimmed.find("[")
	if bracket == -1 or not trimmed.ends_with("]"):
		return make_type(trimmed)
	var type := make_type(trimmed.substr(0, bracket).strip_edges())
	for generic in split_top_level(trimmed.substr(bracket + 1, trimmed.length() - bracket - 2), TYPE_SEPARATOR):
		type.generics.append(parse_type(generic))
	return type


static func split_top_level(text: String, separator: String) -> PackedStringArray:
	var parts := PackedStringArray()
	var depth := 0
	var start := 0
	for index in text.length():
		var character := text[index]
		if SourceScanner.OPENING_BRACKETS.contains(character):
			depth += 1
		elif SourceScanner.CLOSING_BRACKETS.contains(character):
			depth -= 1
		elif character == separator and depth == 0:
			_append_part(parts, text.substr(start, index - start))
			start = index + 1
	_append_part(parts, text.substr(start))
	return parts


static func find_top_level(text: String, character: String, from: int) -> int:
	var depth := 0
	for index in range(from, text.length()):
		var current := text[index]
		if SourceScanner.OPENING_BRACKETS.contains(current):
			depth += 1
		elif SourceScanner.CLOSING_BRACKETS.contains(current):
			depth -= 1
		elif current == character and depth == 0:
			return index
	return -1


static func literal_type(masked_value: String) -> TypeData:
	var text := masked_value.strip_edges()
	if text.is_empty():
		return null
	for lambda_prefix in LAMBDA_PREFIXES:
		if text.begins_with(lambda_prefix):
			return make_type(Language.CALLABLE_TYPE_NAME)
	if text == "null":
		return make_type(Language.OBJECT_TYPE_NAME)
	if text == "true" or text == "false":
		return make_type(Language.BOOLEAN_TYPE_NAME)
	var number := text.replace(NUMBER_SEPARATOR, "")
	if number.is_valid_int() or number.is_valid_hex_number(true):
		return make_type(type_string(TYPE_INT))
	if number.is_valid_float():
		return make_type(type_string(TYPE_FLOAT))
	if _string_literal_pattern.search(text) != null:
		if text.begins_with("&"):
			return make_type(type_string(TYPE_STRING_NAME))
		if text.begins_with("^"):
			return make_type(type_string(TYPE_NODE_PATH))
		return make_type(type_string(TYPE_STRING))
	if text.begins_with("[") and SourceScanner.find_matching_bracket(text, 0) == text.length() - 1:
		return make_type(type_string(TYPE_ARRAY))
	if text.begins_with("{") and SourceScanner.find_matching_bracket(text, 0) == text.length() - 1:
		return make_type(type_string(TYPE_DICTIONARY))
	return null


static func constructed_type(masked_value: String) -> TypeData:
	var constructor_match := _constructor_pattern.search(masked_value.strip_edges())
	if constructor_match != null and Language.is_known_type(constructor_match.get_string(1)):
		return make_type(constructor_match.get_string(1))
	return null


static func parse_func_parameters(params_text: String) -> Dictionary:
	var result := {}
	for param in split_top_level(params_text, TYPE_SEPARATOR):
		var name_end := 0
		while name_end < param.length() and SourceScanner.is_identifier_character(param[name_end]):
			name_end += 1
		if name_end > 0:
			var declaration := parse_declaration_tail(param.substr(name_end))
			result[param.substr(0, name_end)] = declaration.type if declaration.type != null else constructed_type(declaration.value)
	return result


static func parse_declaration_tail(tail: String) -> DeclarationTail:
	var result := DeclarationTail.new()
	var text := tail.strip_edges()
	var type_text := ""
	if text.begins_with(INFERRED_ASSIGNMENT):
		result.value = text.substr(INFERRED_ASSIGNMENT.length()).strip_edges()
	elif text.begins_with(TYPE_ANNOTATION):
		var assignment := find_top_level(text, ASSIGNMENT, 1)
		var accessor := find_top_level(text, TYPE_ANNOTATION, 1)
		var type_end := text.length()
		if assignment != -1:
			type_end = assignment
		if accessor != -1 and accessor < type_end:
			type_end = accessor
		type_text = text.substr(1, type_end - 1).strip_edges()
		if assignment != -1 and assignment == type_end:
			result.value = text.substr(assignment + 1).strip_edges()
	elif text.begins_with(ASSIGNMENT):
		result.value = text.substr(ASSIGNMENT.length()).strip_edges()
	result.type = literal_type(result.value) if type_text.is_empty() else parse_type(type_text)
	return result


static func get_scope_info_for_line(index: SymbolIndexData, line: int) -> ScopeInfo:
	return get_scope_info_for_scope(index, _find_innermost_scope(index.root, line), line)


static func get_scope_info_for_scope(index: SymbolIndexData, scope: ScopeBase, line: int) -> ScopeInfo:
	var info := ScopeInfo.new()
	info.index = index
	info.line = line
	info.scope = scope
	var current := info.scope
	while current != null:
		if current is FunctionScope and info.function_scope == null:
			info.function_scope = current
		if current is ClassScope and info.class_scope == null:
			info.class_scope = current
		current = current.parent
	return info


static func find_variable(variable_name: String, scope_info: ScopeInfo) -> VariableLookup:
	var lookup := VariableLookup.new()
	var current := scope_info.scope
	var is_current_class := true
	while current != null and not lookup.is_defined:
		if current is ClassScope:
			var member: VariableSymbol = (current as ClassScope).vars.get(variable_name)
			if member != null and (is_current_class or member.is_const):
				lookup.is_defined = true
				lookup.type = member.type
				lookup.symbol = member
			is_current_class = false
		elif current is FunctionScope and (current as FunctionScope).params.has(variable_name):
			lookup.is_defined = true
			lookup.type = (current as FunctionScope).params[variable_name]
		else:
			var local := current.find_local(variable_name, scope_info.line)
			if local != null:
				lookup.is_defined = true
				lookup.type = local.type
				lookup.symbol = local
		current = current.parent
	return lookup


static func find_root_class(class_scope: ClassScope) -> ClassScope:
	var current := class_scope
	while current.parent is ClassScope:
		current = current.parent as ClassScope
	return current


static func find_class(root: ClassScope, type_name: String) -> ClassScope:
	if type_name.is_empty():
		return null
	if root.name == type_name:
		return root
	for inner_name: String in root.inner_classes:
		var found := find_class(root.inner_classes[inner_name], type_name)
		if found != null:
			return found
	return null


static func find_top_level_function(scope_info: ScopeInfo) -> FunctionScope:
	var current: ScopeBase = scope_info.function_scope
	var top_level: FunctionScope = null
	while current != null and not current is ClassScope:
		if current is FunctionScope:
			top_level = current as FunctionScope
		current = current.parent
	return top_level


static func _find_innermost_scope(scope: ScopeBase, line: int) -> ScopeBase:
	for child in scope.children:
		if line >= child.first_contained_line() and line <= child.end_line:
			return _find_innermost_scope(child, line)
	return scope


static func _append_part(parts: PackedStringArray, part: String) -> void:
	var trimmed := part.strip_edges()
	if not trimmed.is_empty():
		parts.append(trimmed)
