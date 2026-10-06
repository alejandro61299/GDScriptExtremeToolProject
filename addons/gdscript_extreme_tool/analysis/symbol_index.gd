@tool
extends RefCounted

const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")

const TYPE_SEPARATOR: String = ","
const INFERRED_ASSIGNMENT: String = ":="
const TYPE_ANNOTATION: String = ":"
const ASSIGNMENT: String = "="
const LAMBDA_PREFIXES: Array[String] = ["func(", "func "]
const NUMBER_SEPARATOR: String = "_"

static var _string_literal_pattern := RegEx.create_from_string("^(&|\\^|r)?[\"']{1,3}\\?*[\"']{1,3}$")
static var _constructor_pattern := RegEx.create_from_string("^([A-Za-z_]\\w*)\\s*[\\(\\.]")


class GDSExTypeData:
	var name: String = ""
	var generics: Array[GDSExTypeData] = []


class GDSExVariableSymbol:
	enum GDSExDeferred { NONE, VALUE, ITERATION }

	var name: String = ""
	var type: GDSExTypeData
	var is_const: bool = false
	var start_line: int = 0
	var end_line: int = 0
	var value_code: String = ""
	var deferred: GDSExDeferred = GDSExDeferred.NONE
	var function: GDSExFunctionScope


class GDSExSignalSymbol:
	var name: String = ""
	var params: Dictionary = {}


class GDSExDeclarationTail:
	var type: GDSExTypeData
	var value: String = ""


class GDSExVariableLookup:
	var is_defined: bool = false
	var type: GDSExTypeData
	var symbol: GDSExVariableSymbol


class GDSExScopeBase:
	var children: Array[GDSExScopeBase] = []
	var locals: Array[GDSExVariableSymbol] = []
	var start_line: int = 0
	var body_start_line: int = -1
	var end_line: int = 0
	var body_indent_text: String = ""
	var parent: GDSExScopeBase:
		get:
			return _parent_reference.get_ref() as GDSExScopeBase if _parent_reference != null else null
	var _parent_reference: WeakRef

	func attach_to(new_parent: GDSExScopeBase) -> void:
		_parent_reference = weakref(new_parent)
		new_parent.children.append(self)

	func enclose_in(enclosing_scope: GDSExScopeBase) -> void:
		_parent_reference = weakref(enclosing_scope)

	func first_contained_line() -> int:
		return start_line

	func accepts_declarations() -> bool:
		return body_start_line != -1

	func find_local(local_name: String, before_line: int) -> GDSExVariableSymbol:
		for index in range(locals.size() - 1, -1, -1):
			var local := locals[index]
			if local.name == local_name and local.start_line < before_line:
				return local
		return null


class GDSExFunctionScope extends GDSExScopeBase:
	var name: String = ""
	var is_lambda: bool = false
	var is_static: bool = false
	var is_inline: bool = false
	var params: Dictionary = {}
	var return_type: GDSExTypeData
	var return_codes: PackedStringArray = []
	var return_lines: PackedInt32Array = []

	func first_contained_line() -> int:
		return body_start_line if is_lambda else start_line


class GDSExBlockScope extends GDSExScopeBase:
	enum GDSExKind { IF, ELIF, ELSE, FOR, WHILE, MATCH, MATCH_BRANCH, PROPERTY, OTHER }

	var kind: GDSExKind = GDSExKind.OTHER

	func first_contained_line() -> int:
		return body_start_line

	func accepts_declarations() -> bool:
		return kind != GDSExKind.MATCH and kind != GDSExKind.PROPERTY


class GDSExClassMember:
	enum GDSExKind { VARIABLE, CONSTANT, SIGNAL, ENUM, FUNCTION, CLASS, ANNOTATION, OTHER }

	var kind: GDSExKind = GDSExKind.VARIABLE
	var name: String = ""
	var modifiers: String = ""
	var start_line: int = 0
	var end_line: int = 0


class GDSExClassScope extends GDSExScopeBase:
	var name: String = ""
	var header_end_line: int = -1
	var members: Array[GDSExClassMember] = []
	var vars: Dictionary = {}
	var functions: Dictionary = {}
	var signals: Dictionary = {}
	var inner_classes: Dictionary = {}
	var extends_line: int = -1
	var inherit_type: GDSExTypeData
	var base_script_path: String = ""

	func accepts_declarations() -> bool:
		return false


class GDSExSymbolIndexData:
	var root: GDSExClassScope
	var statements: Array[GDSExSourceScanner.GDSExStatement] = []


class GDSExScopeInfo:
	var index: GDSExSymbolIndexData
	var line: int = 0
	var scope: GDSExScopeBase
	var class_scope: GDSExClassScope
	var function_scope: GDSExFunctionScope


static func make_type(type_name: String) -> GDSExTypeData:
	var type := GDSExTypeData.new()
	type.name = type_name
	return type


static func get_base_type_name(type: GDSExTypeData) -> String:
	return "" if type == null else type.name


static func type_to_string(type: GDSExTypeData) -> String:
	if type == null:
		return ""
	if type.generics.is_empty():
		return type.name
	var generic_texts := PackedStringArray()
	for generic in type.generics:
		generic_texts.append(type_to_string(generic))
	return "%s[%s]" % [type.name, (TYPE_SEPARATOR + " ").join(generic_texts)]


static func parse_type(text: String) -> GDSExTypeData:
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
		if GDSExSourceScanner.OPENING_BRACKETS.contains(character):
			depth += 1
		elif GDSExSourceScanner.CLOSING_BRACKETS.contains(character):
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
		if GDSExSourceScanner.OPENING_BRACKETS.contains(current):
			depth += 1
		elif GDSExSourceScanner.CLOSING_BRACKETS.contains(current):
			depth -= 1
		elif current == character and depth == 0:
			return index
	return -1


static func literal_type(masked_value: String) -> GDSExTypeData:
	var text := masked_value.strip_edges()
	if text.is_empty():
		return null
	for lambda_prefix in LAMBDA_PREFIXES:
		if text.begins_with(lambda_prefix):
			return make_type(GDSExLanguage.CALLABLE_TYPE_NAME)
	if text == "null":
		return make_type(GDSExLanguage.OBJECT_TYPE_NAME)
	if text == "true" or text == "false":
		return make_type(GDSExLanguage.BOOLEAN_TYPE_NAME)
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
	if text.begins_with("[") and GDSExSourceScanner.find_matching_bracket(text, 0) == text.length() - 1:
		return make_type(type_string(TYPE_ARRAY))
	if text.begins_with("{") and GDSExSourceScanner.find_matching_bracket(text, 0) == text.length() - 1:
		return make_type(type_string(TYPE_DICTIONARY))
	return null


static func constructed_type(masked_value: String) -> GDSExTypeData:
	var constructor_match := _constructor_pattern.search(masked_value.strip_edges())
	if constructor_match != null and GDSExLanguage.is_known_type(constructor_match.get_string(1)):
		return make_type(constructor_match.get_string(1))
	return null


static func parse_func_parameters(params_text: String) -> Dictionary:
	var result := {}
	for param in split_top_level(params_text, TYPE_SEPARATOR):
		var name_end := 0
		while name_end < param.length() and GDSExSourceScanner.is_identifier_character(param[name_end]):
			name_end += 1
		if name_end > 0:
			var declaration := parse_declaration_tail(param.substr(name_end))
			result[param.substr(0, name_end)] = declaration.type if declaration.type != null else constructed_type(declaration.value)
	return result


static func parse_declaration_tail(tail: String) -> GDSExDeclarationTail:
	var result := GDSExDeclarationTail.new()
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


static func get_scope_info_for_line(index: GDSExSymbolIndexData, line: int) -> GDSExScopeInfo:
	return get_scope_info_for_scope(index, _find_innermost_scope(index.root, line), line)


static func get_scope_info_for_scope(index: GDSExSymbolIndexData, scope: GDSExScopeBase, line: int) -> GDSExScopeInfo:
	var info := GDSExScopeInfo.new()
	info.index = index
	info.line = line
	info.scope = scope
	var current := info.scope
	while current != null:
		if current is GDSExFunctionScope and info.function_scope == null:
			info.function_scope = current
		if current is GDSExClassScope and info.class_scope == null:
			info.class_scope = current
		current = current.parent
	return info


static func find_variable(variable_name: String, scope_info: GDSExScopeInfo) -> GDSExVariableLookup:
	var lookup := GDSExVariableLookup.new()
	var current := scope_info.scope
	var is_current_class := true
	while current != null and not lookup.is_defined:
		if current is GDSExClassScope:
			var member: GDSExVariableSymbol = (current as GDSExClassScope).vars.get(variable_name)
			if member != null and (is_current_class or member.is_const):
				lookup.is_defined = true
				lookup.type = member.type
				lookup.symbol = member
			is_current_class = false
		elif current is GDSExFunctionScope and (current as GDSExFunctionScope).params.has(variable_name):
			lookup.is_defined = true
			lookup.type = (current as GDSExFunctionScope).params[variable_name]
		else:
			var local := current.find_local(variable_name, scope_info.line)
			if local != null:
				lookup.is_defined = true
				lookup.type = local.type
				lookup.symbol = local
		current = current.parent
	return lookup


static func find_root_class(class_scope: GDSExClassScope) -> GDSExClassScope:
	var current := class_scope
	while current.parent is GDSExClassScope:
		current = current.parent as GDSExClassScope
	return current


static func find_class(root: GDSExClassScope, type_name: String) -> GDSExClassScope:
	if type_name.is_empty():
		return null
	if root.name == type_name:
		return root
	for inner_name: String in root.inner_classes:
		var found := find_class(root.inner_classes[inner_name], type_name)
		if found != null:
			return found
	return null


static func find_top_level_function(scope_info: GDSExScopeInfo) -> GDSExFunctionScope:
	var current: GDSExScopeBase = scope_info.function_scope
	var top_level: GDSExFunctionScope = null
	while current != null and not current is GDSExClassScope:
		if current is GDSExFunctionScope:
			top_level = current as GDSExFunctionScope
		current = current.parent
	return top_level


static func _find_innermost_scope(scope: GDSExScopeBase, line: int) -> GDSExScopeBase:
	for child in scope.children:
		if line >= child.first_contained_line() and line <= child.end_line:
			return _find_innermost_scope(child, line)
	return scope


static func _append_part(parts: PackedStringArray, part: String) -> void:
	var trimmed := part.strip_edges()
	if not trimmed.is_empty():
		parts.append(trimmed)
