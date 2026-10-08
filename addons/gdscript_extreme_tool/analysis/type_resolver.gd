@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExCallSiteParser = preload("res://addons/gdscript_extreme_tool/analysis/call_site_parser.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")
const GDSExBuiltinTypes = preload("res://addons/gdscript_extreme_tool/analysis/builtin_types.gd")
const GDSExScriptLibrary = preload("res://addons/gdscript_extreme_tool/analysis/script_library.gd")
const GDSExScriptTypeNames = preload("res://addons/gdscript_extreme_tool/analysis/script_type_names.gd")

const MEMBER_ACCESS: String = "."
const CONNECT_FUNCTION: String = "connect"
const PRELOAD_FUNCTION: String = "preload"
const EMIT_FUNCTION: String = "emit"
const AWAIT_PREFIX: String = "await "
const TERNARY_CONDITION: String = " if "
const TERNARY_ALTERNATIVE: String = " else "
const CAST_OPERATOR: String = " as "
const NEGATION_PREFIXES: Array[String] = ["not ", "!"]
const BOOLEAN_OPERATORS: Array[String] = [" or ", "||", " and ", "&&"]
const COMPARISON_OPERATORS: Array[String] = [" in ", " is ", "==", "!=", "<=", ">=", "<", ">"]
const SHIFT_OPERATORS: Array[String] = ["<<", ">>"]
const ADDITIVE_OPERATORS: String = "+-"
const MULTIPLICATIVE_OPERATORS: String = "*/%"
const FORMAT_OPERATOR: String = "%"
const SIGN_PREFIXES: String = "+-~"
const OPERATOR_NEIGHBOURS: String = "+-*/%<>=!&|^~(,[{:"
const EXPONENT_MARKERS: String = "eE"
const DIGITS: String = "0123456789"
const NODE_PATH_PREFIXES: String = "$%"
const NODE_PATH_SEPARATOR: String = "/"
const POWER_OPERATOR_CHARACTER: String = "*"
const NON_ASSIGNMENT_NEIGHBOURS: String = "=!<>:+-*/%&|^~"
const COMPARISON_NEIGHBOURS: String = "=!<>:"
const COMPOUND_ASSIGNMENT_OPERATORS: String = "+-*/%&|^~ "
const MAX_INHERITANCE_DEPTH: int = 32
const MAX_DEFERRED_DEPTH: int = 16
const NULL_LITERAL: String = "null"
const CONSTRUCTOR_TEMPLATE: String = "%s.new()"
const TYPED_ARRAY_TEMPLATE: String = "Array[%s]"
const ENUM_DEFAULT_VALUE: String = "0"
const SCRIPT_CLASS_NAME: String = "GDScript"

static var _modifiers_pattern := RegEx.create_from_string("^(?:(?:@\\w+(?:\\([^)]*\\))?|static)\\s+)+")
static var _declaration_pattern := RegEx.create_from_string("^(?:var|const)\\s+\\w+(.*)$")
static var _return_pattern := RegEx.create_from_string("^return\\b(.*)$")
static var _condition_pattern := RegEx.create_from_string("^(?:if|elif|while)\\b(.*):$")
static var _for_pattern := RegEx.create_from_string("^for\\s+\\w+\\s*(?::\\s*(.+?))?\\s+in\\s+(.+):$")
static var _identifier_pattern := RegEx.create_from_string("^[A-Za-z_]\\w*$")
static var _deferred_depth: int = 0
static var _global_enum_names: Dictionary[String, bool] = {}
static var _engine_callbacks: Dictionary[String, Dictionary] = {}
static var _guess_count: int = 0


class GDSExMember:
	enum GDSExKind { VARIABLE, FUNCTION, SIGNAL, CLASS, ENUM }

	var kind: GDSExKind = GDSExKind.VARIABLE
	var type: GDSExSymbolIndex.GDSExTypeData
	var param_names: PackedStringArray = []
	var param_types: Array[GDSExSymbolIndex.GDSExTypeData] = []
	var function: GDSExSymbolIndex.GDSExFunctionScope
	var symbol: GDSExSymbolIndex.GDSExVariableSymbol
	var is_constant: bool = false
	var is_class_alias: bool = false
	var script_path: String = ""
	var owner_scope: GDSExSymbolIndex.GDSExClassScope
	var class_scope: GDSExSymbolIndex.GDSExClassScope


class GDSExResolved:
	var type: GDSExSymbolIndex.GDSExTypeData
	var class_scope: GDSExSymbolIndex.GDSExClassScope
	var function: GDSExSymbolIndex.GDSExFunctionScope
	var enum_class: GDSExSymbolIndex.GDSExClassScope
	var enum_name: String = ""
	var is_class_reference: bool = false
	var is_preloaded: bool = false

	func is_known() -> bool:
		return type != null or class_scope != null or enum_class != null


class GDSExChainToken:
	var text: String = ""
	var name: String = ""
	var is_call: bool = false
	var is_indexed: bool = false
	var is_valid: bool = true


static func resolve_expression_type(expression: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExTypeData:
	return resolve_expression(expression, scope_info).type


static func resolve_expression(expression: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	var text := _unwrap(expression)
	if text.is_empty():
		return GDSExResolved.new()
	var literal := GDSExSymbolIndex.literal_type(text)
	if literal != null:
		return _resolved_type(literal, scope_info)
	var operation := _resolve_operation(text, scope_info)
	if operation != null:
		return operation
	var resolved := _resolve_chain(text, scope_info)
	if resolved.type != null and resolved.type.name == GDSExLanguage.SIGNAL_TYPE_NAME and expression.strip_edges().begins_with(AWAIT_PREFIX):
		return GDSExResolved.new()
	return resolved


static func resolve_self(scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	var resolved := GDSExResolved.new()
	resolved.class_scope = scope_info.class_scope
	resolved.type = _class_type(scope_info.class_scope)
	return resolved


static func find_member(owner: GDSExResolved, member_name: String) -> GDSExMember:
	if owner.class_scope != null:
		return find_class_member(owner.class_scope, member_name)
	if owner.type == null:
		return null
	if GDSExLanguage.is_builtin_type(owner.type.name):
		return _find_builtin_member(owner.type, member_name)
	var global_script := _load_script(GDSExScriptLibrary.find_global_class_path(owner.type.name))
	if global_script != null:
		return _find_script_member(global_script, member_name)
	return _find_engine_member(owner.type.name, member_name)


static func count_guesses_from_other_scripts() -> int:
	return _guess_count


static func find_class_member(class_scope: GDSExSymbolIndex.GDSExClassScope, member_name: String) -> GDSExMember:
	var current := class_scope
	for depth in MAX_INHERITANCE_DEPTH:
		var member := _find_own_member(current, member_name)
		if member != null:
			return member
		var base_class := GDSExScriptTypeNames.find_base_class(current)
		if base_class == null:
			member = _find_member_of_an_unread_base(current, member_name)
			if member != null:
				member.owner_scope = current
			return member
		current = base_class
	return null


static func resolve_signal(expression: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExMember:
	var tokens := _split_chain(expression.strip_edges())
	if tokens.is_empty():
		return null
	var signal_name := tokens[tokens.size() - 1]
	tokens.remove_at(tokens.size() - 1)
	var owner := resolve_self(scope_info) if tokens.is_empty() else resolve_expression(MEMBER_ACCESS.join(tokens), scope_info)
	var member := find_member(owner, signal_name)
	return _exported_member(member, scope_info) if member != null and member.kind == GDSExMember.GDSExKind.SIGNAL else null


static func is_function_defined(function_name: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> bool:
	if function_name == GDSExLanguage.SUPER_KEYWORD or GDSExLanguage.GLOBAL_FUNCTIONS.has(function_name):
		return true
	if GDSExLanguage.is_known_type(function_name):
		return true
	if GDSExSymbolIndex.find_class(GDSExSymbolIndex.find_root_class(scope_info.class_scope), function_name) != null:
		return true
	return find_class_member(scope_info.class_scope, function_name) != null


static func is_engine_callback(class_scope: GDSExSymbolIndex.GDSExClassScope, function_name: String) -> bool:
	var type_name := engine_base_type(class_scope)
	if not _engine_callbacks.has(type_name):
		var callbacks: Dictionary = {}
		if ClassDB.class_exists(type_name):
			for function in ClassDB.class_get_method_list(type_name):
				if function["flags"] & METHOD_FLAG_VIRTUAL != 0:
					callbacks[function["name"]] = true
		_engine_callbacks[type_name] = callbacks
	return _engine_callbacks[type_name].has(function_name)


static func engine_base_type(class_scope: GDSExSymbolIndex.GDSExClassScope) -> String:
	var root := GDSExSymbolIndex.find_root_class(class_scope)
	var current := class_scope
	for depth in MAX_INHERITANCE_DEPTH:
		var base_name := _base_class_name(current)
		var base_class := GDSExSymbolIndex.find_class(root, base_name) if current.base_script_path.is_empty() else null
		if base_class == null or base_class == current:
			var base_script := _load_script(current.base_script_path if not current.base_script_path.is_empty() else GDSExScriptLibrary.find_global_class_path(base_name))
			return base_name if base_script == null else String(base_script.get_instance_base_type())
		current = base_class
	return GDSExLanguage.DEFAULT_SCRIPT_BASE


static func is_function_of_every_script(function_name: String) -> bool:
	return ClassDB.class_has_method(SCRIPT_CLASS_NAME, function_name)


static func type_seen_from(type: GDSExSymbolIndex.GDSExTypeData, written_in: GDSExSymbolIndex.GDSExScopeInfo, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExTypeData:
	if type == null or written_in.class_scope == scope_info.class_scope:
		return type
	return _translated_type(type, written_in, scope_info)


static func value_type_seen_from(value: GDSExResolved, written_in: GDSExSymbolIndex.GDSExScopeInfo, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExTypeData:
	if written_in.class_scope == scope_info.class_scope:
		return value.type
	if _is_an_instance_named_by_less_than_its_class(value, written_in):
		var class_name_there := GDSExScriptTypeNames.name_of_class(value.class_scope, scope_info.class_scope, written_in.class_scope)
		if not class_name_there.is_empty():
			return GDSExSymbolIndex.make_type(class_name_there)
	return type_seen_from(value.type, written_in, scope_info)


static func _is_an_instance_named_by_less_than_its_class(value: GDSExResolved, written_in: GDSExSymbolIndex.GDSExScopeInfo) -> bool:
	if value.class_scope == null or value.is_class_reference:
		return false
	if value.type == null:
		return true
	return value.type.generics.is_empty() and find_type_class(value.type.name, written_in) != value.class_scope


static func is_identifier(text: String) -> bool:
	return _identifier_pattern.search(text) != null


static func function_return_type(function: GDSExSymbolIndex.GDSExFunctionScope, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExTypeData:
	if function.return_type != null:
		return function.return_type
	if function.return_codes.is_empty() or _deferred_depth >= MAX_DEFERRED_DEPTH:
		return null
	_deferred_depth += 1
	var common: GDSExSymbolIndex.GDSExTypeData = null
	var function_index := GDSExSymbolIndex.find_index(function)
	if function_index == null:
		function_index = scope_info.index
	for index in function.return_codes.size():
		var line := function.return_lines[index]
		var return_scope := GDSExSymbolIndex.get_scope_info_for_scope(function_index, function, line) if function.is_inline else GDSExSymbolIndex.get_scope_info_for_line(function_index, line)
		var returned := resolve_expression_type(function.return_codes[index], return_scope)
		if returned == null or (common != null and GDSExSymbolIndex.type_to_string(common) != GDSExSymbolIndex.type_to_string(returned)):
			common = null
			break
		common = returned
	_deferred_depth -= 1
	return common


static func is_global_enum(identifier: String) -> bool:
	if _global_enum_names.is_empty():
		for enum_name: String in GDSExBuiltinTypes.GLOBAL_CONSTANTS.values():
			_global_enum_names[enum_name] = true
	return _global_enum_names.has(identifier)


static func is_name_defined(identifier: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> bool:
	if GDSExLanguage.LITERAL_KEYWORDS.has(identifier) or GDSExLanguage.NON_CALL_KEYWORDS.has(identifier) or GDSExLanguage.MATH_CONSTANTS.has(identifier):
		return true
	if GDSExSymbolIndex.find_variable(identifier, scope_info).is_defined or is_function_defined(identifier, scope_info):
		return true
	if GDSExBuiltinTypes.GLOBAL_CONSTANTS.has(identifier) or is_global_enum(identifier) or Engine.has_singleton(identifier):
		return true
	var outer_class := scope_info.class_scope.parent
	while outer_class is GDSExSymbolIndex.GDSExClassScope:
		var outer_member := find_class_member(outer_class as GDSExSymbolIndex.GDSExClassScope, identifier)
		if outer_member != null and outer_member.is_constant:
			return true
		outer_class = outer_class.parent
	return GDSExLanguage.is_project_global(identifier)


static func expected_type(statement_code: String, call: GDSExCallSiteParser.GDSExCallSite, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExTypeData:
	var expression := statement_code.substr(call.expression_offset, call.expression_end() - call.expression_offset)
	var known_type := _expected_type(statement_code, expression, call.parent, call.parent_argument_index, scope_info)
	return known_type if known_type != null else GDSExSymbolIndex.make_type(GDSExLanguage.VARIANT_TYPE_NAME)


static func expected_value_type(statement_code: String, start: int, end: int, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExTypeData:
	var expression := statement_code.substr(start, end - start)
	var parent: GDSExCallSiteParser.GDSExCallSite = null
	for call in GDSExCallSiteParser.parse(statement_code):
		if start > call.open_offset and end <= call.close_offset and (parent == null or call.open_offset > parent.open_offset):
			parent = call
	var argument_index := -1
	if parent != null:
		for index in parent.arguments.size():
			var argument := parent.arguments[index]
			if start >= argument.offset and start < argument.offset + argument.length:
				argument_index = index
	var known_type := _expected_type(statement_code, expression, parent, argument_index, scope_info)
	if known_type == null and parent == null:
		known_type = _assigned_type(statement_code, expression, scope_info)
	if known_type == null or known_type.name == GDSExLanguage.VOID_TYPE_NAME or known_type.name == GDSExLanguage.VARIANT_TYPE_NAME:
		return null
	return known_type


static func default_variable_value(type: GDSExSymbolIndex.GDSExTypeData, scope_info: GDSExSymbolIndex.GDSExScopeInfo = null) -> String:
	var type_name := GDSExSymbolIndex.get_base_type_name(type)
	if is_enum_type(type_name, scope_info):
		return ENUM_DEFAULT_VALUE
	if type_name == GDSExLanguage.OBJECT_TYPE_NAME or not GDSExLanguage.is_builtin_type(type_name):
		return NULL_LITERAL
	var value := default_value_text(type)
	return NULL_LITERAL if value.is_empty() else value


static func default_value_text(type: GDSExSymbolIndex.GDSExTypeData, scope_info: GDSExSymbolIndex.GDSExScopeInfo = null) -> String:
	var type_name := GDSExSymbolIndex.get_base_type_name(type)
	if type_name == GDSExLanguage.VOID_TYPE_NAME:
		return ""
	if type_name == GDSExLanguage.VARIANT_TYPE_NAME:
		return NULL_LITERAL
	if is_enum_type(type_name, scope_info):
		return ENUM_DEFAULT_VALUE
	for builtin_type in TYPE_MAX:
		if type_string(builtin_type) != type_name:
			continue
		if builtin_type == TYPE_NIL or builtin_type == TYPE_OBJECT:
			break
		var default_holder := Array([], builtin_type, &"", null)
		default_holder.resize(1)
		return var_to_str(default_holder[0])
	if ClassDB.class_exists(type_name) and not ClassDB.can_instantiate(type_name):
		return NULL_LITERAL
	return CONSTRUCTOR_TEMPLATE % type_name


static func is_enum_type(type_name: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> bool:
	if type_name.is_empty() or GDSExLanguage.is_known_type(type_name):
		return false
	if is_global_enum(type_name) or GDSExLanguage.is_known_type(type_name.get_slice(MEMBER_ACCESS, 0)):
		return true
	if scope_info == null or find_type_class(type_name, scope_info) != null:
		return false
	var enum_name := type_name.get_slice(MEMBER_ACCESS, type_name.get_slice_count(MEMBER_ACCESS) - 1)
	return _find_enum_class(type_name, enum_name, scope_info, false) != null


static func _expected_type(statement_code: String, expression: String, parent: GDSExCallSiteParser.GDSExCallSite, argument_index: int, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExTypeData:
	if parent != null:
		return _expected_argument_type(parent, argument_index, expression, scope_info)
	return _expected_statement_type(statement_code, expression, scope_info)


static func _assigned_type(statement_code: String, expression: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExTypeData:
	var code := _modifiers_pattern.sub(statement_code, "")
	var from := 0
	while true:
		var index := GDSExSymbolIndex.find_top_level(code, GDSExSymbolIndex.ASSIGNMENT, from)
		if index <= 0:
			return null
		var is_followed := index + 1 < code.length() and code[index + 1] == GDSExSymbolIndex.ASSIGNMENT
		if not is_followed and not COMPARISON_NEIGHBOURS.contains(code[index - 1]):
			if code.substr(0, index).rstrip(COMPOUND_ASSIGNMENT_OPERATORS) != expression:
				return null
			return resolve_expression_type(code.substr(index + 1), scope_info)
		from = index + (2 if is_followed else 1)
	return null


static func _expected_argument_type(parent: GDSExCallSiteParser.GDSExCallSite, index: int, expression: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExTypeData:
	if index == -1 or not _is_whole(parent.arguments[index].text, expression):
		return null
	if not parent.receiver.is_empty() and (parent.name == CONNECT_FUNCTION or parent.name == EMIT_FUNCTION):
		var signal_member := resolve_signal(parent.receiver, scope_info)
		if signal_member != null:
			if parent.name == CONNECT_FUNCTION:
				return GDSExSymbolIndex.make_type(GDSExLanguage.CALLABLE_TYPE_NAME) if index == 0 else null
			return signal_member.param_types[index] if index < signal_member.param_types.size() else null
	var member: GDSExMember
	if parent.receiver.is_empty():
		member = find_class_member(scope_info.class_scope, parent.name)
	else:
		member = find_member(resolve_expression(parent.receiver, scope_info), parent.name)
	if member == null or member.kind != GDSExMember.GDSExKind.FUNCTION or index >= member.param_types.size():
		return null
	return _exported_member(member, scope_info).param_types[index]


static func _expected_statement_type(statement_code: String, expression: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExTypeData:
	var code := _modifiers_pattern.sub(statement_code, "")
	if _is_whole(code, expression):
		return GDSExSymbolIndex.make_type(GDSExLanguage.VOID_TYPE_NAME)

	var declaration_match := _declaration_pattern.search(code)
	if declaration_match != null:
		var declaration := GDSExSymbolIndex.parse_declaration_tail(declaration_match.get_string(1))
		return declaration.type if _is_whole(declaration.value, expression) else null

	var return_match := _return_pattern.search(code)
	if return_match != null:
		if _is_whole(return_match.get_string(1), expression) and scope_info.function_scope != null:
			return scope_info.function_scope.return_type
		return null

	var condition_match := _condition_pattern.search(code)
	if condition_match != null:
		if _is_boolean_operand(condition_match.get_string(1), expression):
			return GDSExSymbolIndex.make_type(GDSExLanguage.BOOLEAN_TYPE_NAME)
		return null

	var for_match := _for_pattern.search(code)
	if for_match != null:
		if not _is_whole(for_match.get_string(2), expression):
			return null
		if for_match.get_string(1).is_empty():
			return GDSExSymbolIndex.make_type(GDSExLanguage.ARRAY_TYPE_NAME)
		return GDSExSymbolIndex.parse_type(TYPED_ARRAY_TEMPLATE % for_match.get_string(1))

	var assignment := _find_assignment(code)
	if assignment != -1 and _is_whole(code.substr(assignment + 1), expression):
		return resolve_expression_type(code.substr(0, assignment), scope_info)
	return null


static func _find_assignment(code: String) -> int:
	var from := 0
	while true:
		var index := GDSExSymbolIndex.find_top_level(code, GDSExSymbolIndex.ASSIGNMENT, from)
		if index <= 0:
			return -1
		var is_followed := index + 1 < code.length() and code[index + 1] == GDSExSymbolIndex.ASSIGNMENT
		if not is_followed and not NON_ASSIGNMENT_NEIGHBOURS.contains(code[index - 1]):
			return index
		from = index + (2 if is_followed else 1)
	return -1


static func _is_whole(container: String, expression: String) -> bool:
	return _unwrap(container) == expression


static func _unwrap(text: String) -> String:
	var result := text.strip_edges()
	if result.begins_with(AWAIT_PREFIX):
		result = result.substr(AWAIT_PREFIX.length()).strip_edges()
	while result.begins_with("(") and GDSExSourceScanner.find_matching_bracket(result, 0) == result.length() - 1:
		result = result.substr(1, result.length() - 2).strip_edges()
	return result


static func _is_boolean_operand(condition: String, expression: String) -> bool:
	var text := _unwrap(condition)
	for operator in BOOLEAN_OPERATORS:
		var operands := _split_at_operator(text, operator)
		if operands.size() > 1:
			for operand in operands:
				if _is_boolean_operand(operand, expression):
					return true
			return false
	for negation in NEGATION_PREFIXES:
		if text.begins_with(negation):
			return _is_boolean_operand(text.substr(negation.length()), expression)
	return text == expression


static func _split_at_operator(text: String, operator: String) -> PackedStringArray:
	var operands := PackedStringArray()
	var start := 0
	var index := _find_text(text, operator, 0)
	while index != -1:
		operands.append(text.substr(start, index - start))
		start = index + operator.length()
		index = _find_text(text, operator, start)
	operands.append(text.substr(start))
	return operands


static func _find_text(text: String, needle: String, from: int) -> int:
	var depth := 0
	for index in range(0, text.length()):
		var character := text[index]
		if GDSExSourceScanner.OPENING_BRACKETS.contains(character):
			depth += 1
		elif GDSExSourceScanner.CLOSING_BRACKETS.contains(character):
			depth -= 1
		elif depth == 0 and index >= from and text.substr(index, needle.length()) == needle:
			return index
	return -1


static func _resolve_operation(text: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	var condition := _find_text(text, TERNARY_CONDITION, 0)
	var alternative := _find_text(text, TERNARY_ALTERNATIVE, condition + 1) if condition != -1 else -1
	if alternative != -1:
		var first_text := text.substr(0, condition).strip_edges()
		var second_text := text.substr(alternative + TERNARY_ALTERNATIVE.length()).strip_edges()
		var first := resolve_expression(first_text, scope_info)
		var second := resolve_expression(second_text, scope_info)
		if _same_type(first, second) or (second_text == NULL_LITERAL and _is_an_object(first)):
			return first
		return second if first_text == NULL_LITERAL and _is_an_object(second) else GDSExResolved.new()

	for operator in BOOLEAN_OPERATORS:
		if _find_text(text, operator, 0) != -1:
			return _resolved_name(GDSExLanguage.BOOLEAN_TYPE_NAME, scope_info)
	if text.begins_with(NEGATION_PREFIXES[0]):
		return _resolved_name(GDSExLanguage.BOOLEAN_TYPE_NAME, scope_info)
	for operator in SHIFT_OPERATORS:
		if _find_text(text, operator, 0) != -1:
			return _resolved_name(GDSExLanguage.INTEGER_TYPE_NAME, scope_info)
	for operator in COMPARISON_OPERATORS:
		if _find_text(text, operator, 0) != -1:
			return _resolved_name(GDSExLanguage.BOOLEAN_TYPE_NAME, scope_info)
	if text.begins_with(NEGATION_PREFIXES[1]):
		return _resolved_name(GDSExLanguage.BOOLEAN_TYPE_NAME, scope_info)

	var cast := _find_text(text, CAST_OPERATOR, 0)
	if cast != -1:
		return _resolved_type(GDSExSymbolIndex.parse_type(text.substr(cast + CAST_OPERATOR.length())), scope_info)

	for operators in [ADDITIVE_OPERATORS, MULTIPLICATIVE_OPERATORS]:
		var index := _find_last_binary_operator(text, operators)
		if index != -1:
			var left := resolve_expression(text.substr(0, index).rstrip(MULTIPLICATIVE_OPERATORS), scope_info)
			var right := resolve_expression(text.substr(index + 1), scope_info)
			return _arithmetic_result(left, right, text[index])

	if SIGN_PREFIXES.contains(text[0]):
		return resolve_expression(text.substr(1), scope_info)
	return null


static func _find_last_binary_operator(text: String, operators: String) -> int:
	var depth := 0
	for index in range(text.length() - 1, 0, -1):
		var character := text[index]
		if GDSExSourceScanner.CLOSING_BRACKETS.contains(character):
			depth += 1
		elif GDSExSourceScanner.OPENING_BRACKETS.contains(character):
			depth -= 1
		elif depth == 0 and operators.contains(character) and _is_binary_position(text, index):
			return index
	return -1


static func _is_binary_position(text: String, index: int) -> bool:
	var previous := index - 1
	while previous >= 0 and text[previous] == " ":
		previous -= 1
	if previous < 0:
		return false
	var before := text[previous]
	if EXPONENT_MARKERS.contains(before) and previous > 0 and DIGITS.contains(text[previous - 1]):
		return false
	if text[index] == POWER_OPERATOR_CHARACTER and before == POWER_OPERATOR_CHARACTER:
		return true
	if text[index] == NODE_PATH_SEPARATOR and _is_inside_node_path(text, index):
		return false
	return not OPERATOR_NEIGHBOURS.contains(before)


static func _is_inside_node_path(text: String, index: int) -> bool:
	var start := index
	while start > 0 and (text[start - 1] == NODE_PATH_SEPARATOR or GDSExSourceScanner.is_identifier_character(text[start - 1])):
		start -= 1
	return start > 0 and NODE_PATH_PREFIXES.contains(text[start - 1])


static func _arithmetic_result(left: GDSExResolved, right: GDSExResolved, operator: String) -> GDSExResolved:
	if left.type == null or right.type == null:
		return GDSExResolved.new()
	var left_name := GDSExSymbolIndex.type_to_string(left.type)
	var right_name := GDSExSymbolIndex.type_to_string(right.type)
	if left_name == right_name:
		return left
	if left_name == GDSExLanguage.STRING_TYPE_NAME and operator == FORMAT_OPERATOR:
		return left
	var numbers: Array[String] = [GDSExLanguage.INTEGER_TYPE_NAME, GDSExLanguage.FLOAT_TYPE_NAME]
	if numbers.has(left_name) and numbers.has(right_name):
		var result := GDSExResolved.new()
		result.type = GDSExSymbolIndex.make_type(GDSExLanguage.FLOAT_TYPE_NAME)
		return result
	if numbers.has(right_name):
		return left
	if numbers.has(left_name):
		return right
	return GDSExResolved.new()


static func _is_an_object(resolved: GDSExResolved) -> bool:
	if resolved.type == null or resolved.is_class_reference:
		return false
	return resolved.class_scope != null or ClassDB.class_exists(resolved.type.name)


static func _same_type(first: GDSExResolved, second: GDSExResolved) -> bool:
	return first.type != null and second.type != null and GDSExSymbolIndex.type_to_string(first.type) == GDSExSymbolIndex.type_to_string(second.type)


static func _resolve_chain(text: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	var tokens := _split_chain(text)
	if tokens.is_empty():
		return GDSExResolved.new()
	var current := _resolve_first_token(tokens[0], scope_info)
	for index in range(1, tokens.size()):
		if not current.is_known():
			break
		current = _resolve_member_token(current, tokens[index], scope_info)
	return current


static func _split_chain(text: String) -> PackedStringArray:
	return GDSExSymbolIndex.split_top_level(text, MEMBER_ACCESS)


static func _parse_token(token_text: String) -> GDSExChainToken:
	var token := GDSExChainToken.new()
	token.text = token_text.strip_edges()
	var name_end := 0
	while name_end < token.text.length() and GDSExSourceScanner.is_identifier_character(token.text[name_end]):
		name_end += 1
	token.name = token.text.substr(0, name_end)
	var rest := token.text.substr(name_end).strip_edges()
	token.is_call = rest.begins_with("(")
	token.is_indexed = rest.ends_with("]")
	while not rest.is_empty() and not token.name.is_empty():
		var close := GDSExSourceScanner.find_matching_bracket(rest, 0) if GDSExSourceScanner.OPENING_BRACKETS.contains(rest[0]) else -1
		if close == -1:
			token.is_valid = false
			break
		rest = rest.substr(close + 1).strip_edges()
	return token


static func _resolve_first_token(token_text: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	var token := _parse_token(token_text)
	if not token.is_valid:
		return GDSExResolved.new()
	var resolved: GDSExResolved
	if token.name.is_empty():
		resolved = _resolve_nameless(token.text, scope_info)
	elif token.is_call:
		resolved = _resolve_bare_call(token.name, scope_info)
	elif token.name == GDSExLanguage.SELF_KEYWORD:
		resolved = resolve_self(scope_info)
	else:
		resolved = _resolve_identifier(token.name, scope_info)
	return _indexed(resolved, scope_info) if token.is_indexed and not token.name.is_empty() else resolved


static func _resolve_nameless(text: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	if text.is_empty():
		return GDSExResolved.new()
	if NODE_PATH_PREFIXES.contains(text[0]):
		return _resolved_name(GDSExLanguage.NODE_TYPE_NAME, scope_info)
	if text.begins_with("(") and GDSExSourceScanner.find_matching_bracket(text, 0) == text.length() - 1:
		return resolve_expression(text, scope_info)
	return _resolved_type(GDSExSymbolIndex.literal_type(text), scope_info)


static func _resolve_bare_call(function_name: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	if GDSExLanguage.is_builtin_type(function_name):
		return _resolved_name(function_name, scope_info)
	if GDSExLanguage.GLOBAL_FUNCTIONS.has(function_name):
		var returned := _resolved_return(GDSExSymbolIndex.make_type(GDSExLanguage.GLOBAL_FUNCTIONS[function_name]), scope_info)
		returned.is_preloaded = function_name == PRELOAD_FUNCTION
		return returned
	var member := find_class_member(scope_info.class_scope, function_name)
	if member != null and member.kind == GDSExMember.GDSExKind.FUNCTION:
		return _resolved_member(member, true, scope_info)
	return GDSExResolved.new()


static func _resolve_identifier(identifier: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	var variable := GDSExSymbolIndex.find_variable(identifier, scope_info)
	var declaring_class := variable.scope as GDSExSymbolIndex.GDSExClassScope
	if declaring_class != null and GDSExScriptTypeNames.declares_enum(declaring_class, identifier):
		return _enum_reference(declaring_class, identifier)
	if variable.is_defined:
		return _resolve_symbol(variable.symbol, variable.type, scope_info)
	var member := find_class_member(scope_info.class_scope, identifier)
	if member != null:
		return _resolved_member(member, false, scope_info)
	var resolved := GDSExResolved.new()
	var file_class := GDSExSymbolIndex.find_class(GDSExSymbolIndex.find_root_class(scope_info.class_scope), identifier)
	var global_class_path := GDSExScriptLibrary.find_global_class_path(identifier)
	if file_class != null:
		resolved.class_scope = file_class
		resolved.type = GDSExSymbolIndex.make_type(identifier)
		resolved.is_class_reference = true
	elif not global_class_path.is_empty():
		resolved.class_scope = _find_script_class(global_class_path)
		resolved.type = GDSExSymbolIndex.make_type(identifier)
		resolved.is_class_reference = true
	elif GDSExLanguage.is_known_type(identifier) or Engine.has_singleton(identifier):
		resolved.type = GDSExSymbolIndex.make_type(identifier)
		resolved.is_class_reference = true
	elif GDSExLanguage.MATH_CONSTANTS.has(identifier):
		resolved.type = GDSExSymbolIndex.make_type(GDSExLanguage.MATH_CONSTANTS[identifier])
	return resolved


static func _resolve_symbol(symbol: GDSExSymbolIndex.GDSExVariableSymbol, known_type: GDSExSymbolIndex.GDSExTypeData, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	if symbol != null and symbol.is_script_alias:
		return _class_alias(symbol.name, symbol.script_path)
	if symbol == null or symbol.deferred == GDSExSymbolIndex.GDSExVariableSymbol.GDSExDeferred.NONE:
		var resolved := _resolved_type(known_type, scope_info)
		if symbol != null:
			resolved.function = symbol.function
		return resolved
	if _deferred_depth >= MAX_DEFERRED_DEPTH:
		return GDSExResolved.new()
	_deferred_depth += 1
	var declaration_scope := GDSExSymbolIndex.get_scope_info_for_line(scope_info.index, symbol.start_line)
	var value := resolve_expression(symbol.value_code, declaration_scope)
	_deferred_depth -= 1
	if symbol.deferred == GDSExSymbolIndex.GDSExVariableSymbol.GDSExDeferred.ITERATION:
		return _iterated(value, scope_info)
	return value


static func _resolve_member_token(owner: GDSExResolved, token_text: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	var token := _parse_token(token_text)
	if not token.is_valid or token.name.is_empty():
		return GDSExResolved.new()
	var resolved := GDSExResolved.new()
	if owner.enum_class != null and not token.is_call and not token.is_indexed:
		var enum_type_name := GDSExScriptTypeNames.name_of_enum(owner.enum_name, owner.enum_class, scope_info.class_scope)
		return resolved if enum_type_name.is_empty() else _resolved_name(enum_type_name, scope_info)
	if owner.enum_class != null:
		owner = _resolved_name(GDSExLanguage.DICTIONARY_TYPE_NAME, scope_info)
	if owner.function != null and token.is_call and GDSExLanguage.CALLABLE_INVOCATIONS.has(token.name):
		var home := _home_scope_info(owner.function, scope_info)
		resolved = _exported(_resolved_return(function_return_type(owner.function, home), home), home, scope_info)
	elif owner.function != null and token.is_call and GDSExLanguage.CALLABLE_BINDINGS.has(token.name):
		resolved = owner
	elif token.is_call and token.name == GDSExLanguage.CONSTRUCTOR_NAME:
		if owner.is_class_reference:
			resolved.type = owner.type
			resolved.class_scope = owner.class_scope
	else:
		var member := find_member(owner, token.name)
		if member != null:
			resolved = _resolved_member(member, token.is_call, scope_info)
			if resolved.is_class_reference and owner.is_class_reference and owner.type != null:
				resolved.type = GDSExSymbolIndex.make_type(owner.type.name + MEMBER_ACCESS + token.name)
		elif owner.is_class_reference and owner.class_scope == null and GDSExLanguage.is_builtin_type(owner.type.name):
			resolved.type = _builtin_constant_type(owner.type.name, token)
	return _indexed(resolved, scope_info) if token.is_indexed else resolved


static func _builtin_constant_type(type_name: String, token: GDSExChainToken) -> GDSExSymbolIndex.GDSExTypeData:
	if token.is_call:
		return GDSExSymbolIndex.make_type(type_name)
	var constant_type: String = GDSExBuiltinTypes.CONSTANTS.get(type_name, {}).get(token.name, "")
	if constant_type.is_empty():
		return null
	return GDSExSymbolIndex.make_type(GDSExLanguage.INTEGER_TYPE_NAME if constant_type.contains(MEMBER_ACCESS) else constant_type)


static func _enum_reference(declaring_class: GDSExSymbolIndex.GDSExClassScope, enum_name: String) -> GDSExResolved:
	var reference := GDSExResolved.new()
	reference.enum_class = declaring_class
	reference.enum_name = enum_name
	return reference


static func _class_alias(alias_name: String, script_path: String) -> GDSExResolved:
	var alias := GDSExResolved.new()
	alias.type = GDSExSymbolIndex.make_type(alias_name)
	alias.class_scope = _find_script_class(script_path)
	alias.is_class_reference = true
	return alias


static func _resolved_member(member: GDSExMember, is_call: bool, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	var home := _home_scope_info(member.owner_scope, scope_info)
	var resolved := _resolved_member_at_home(member, is_call, home)
	if home.index != scope_info.index and _is_guessed(member, is_call):
		_guess_count += 1
	return _exported(resolved, _written_scope_info(member.owner_scope, home), scope_info)


static func _resolved_member_at_home(member: GDSExMember, is_call: bool, home: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	if member.is_class_alias:
		return _class_alias(member.type.name, member.script_path)
	match member.kind:
		GDSExMember.GDSExKind.ENUM:
			return _enum_reference(member.owner_scope, member.symbol.name)
		GDSExMember.GDSExKind.CLASS:
			var reference := GDSExResolved.new()
			reference.type = GDSExSymbolIndex.make_type(member.class_scope.name)
			reference.class_scope = member.class_scope
			reference.is_class_reference = true
			return reference
		GDSExMember.GDSExKind.SIGNAL:
			return _resolved_name(GDSExLanguage.SIGNAL_TYPE_NAME, home)
		GDSExMember.GDSExKind.FUNCTION:
			if is_call:
				var return_type := member.type
				if return_type == null and member.function != null:
					return_type = function_return_type(member.function, home)
				return _resolved_return(return_type, home)
			var reference := _resolved_name(GDSExLanguage.CALLABLE_TYPE_NAME, home)
			reference.function = member.function
			return reference
	if member.symbol != null:
		return _resolve_symbol(member.symbol, member.type, home)
	return _resolved_type(member.type, home)


static func _is_guessed(member: GDSExMember, is_call: bool) -> bool:
	if member.symbol != null and member.symbol.is_untyped:
		return true
	return is_call and member.kind == GDSExMember.GDSExKind.FUNCTION and member.type == null and member.function != null


static func _find_member_of_an_unread_base(class_scope: GDSExSymbolIndex.GDSExClassScope, member_name: String) -> GDSExMember:
	var base_name := _base_class_name(class_scope)
	var base_script := _load_script(class_scope.base_script_path if not class_scope.base_script_path.is_empty() else GDSExScriptLibrary.find_global_class_path(base_name))
	return _find_engine_member(base_name, member_name) if base_script == null else _find_script_member(base_script, member_name)


static func _home_scope_info(scope: GDSExSymbolIndex.GDSExScopeBase, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExScopeInfo:
	var home_index := GDSExSymbolIndex.find_index(scope) if scope != null else null
	if home_index == null or home_index == scope_info.index:
		return scope_info
	return GDSExSymbolIndex.get_scope_info_for_scope(home_index, scope, scope.start_line)


static func _written_scope_info(owner_scope: GDSExSymbolIndex.GDSExClassScope, home: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExScopeInfo:
	if owner_scope == null or owner_scope == home.class_scope or not GDSExSymbolIndex.is_declared_in(owner_scope, home.index):
		return home
	return GDSExSymbolIndex.get_scope_info_for_scope(home.index, owner_scope, owner_scope.start_line)


static func _exported(resolved: GDSExResolved, written_in: GDSExSymbolIndex.GDSExScopeInfo, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	if resolved.type == null or written_in.class_scope == scope_info.class_scope:
		return resolved
	var translated_type := _translated_type(resolved.type, written_in, scope_info)
	if translated_type == resolved.type:
		return resolved
	var exported := GDSExResolved.new()
	exported.type = translated_type
	exported.function = resolved.function
	exported.is_class_reference = resolved.is_class_reference
	if resolved.class_scope != null:
		exported.class_scope = GDSExScriptTypeNames.find_own_class(resolved.class_scope, scope_info.class_scope)
	return exported


static func _exported_member(member: GDSExMember, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExMember:
	var written_in := _written_scope_info(member.owner_scope, _home_scope_info(member.owner_scope, scope_info))
	if written_in.class_scope == scope_info.class_scope:
		return member
	var exported := GDSExMember.new()
	exported.kind = member.kind
	exported.type = _translated_type(member.type, written_in, scope_info)
	exported.param_names = member.param_names
	for param_type in member.param_types:
		exported.param_types.append(_translated_type(param_type, written_in, scope_info))
	exported.function = member.function
	exported.symbol = member.symbol
	exported.is_constant = member.is_constant
	exported.owner_scope = member.owner_scope
	return exported


static func _translated_type(type: GDSExSymbolIndex.GDSExTypeData, written_in: GDSExSymbolIndex.GDSExScopeInfo, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExTypeData:
	if type == null:
		return null
	var translated := GDSExSymbolIndex.make_type(_translated_name(type.name, written_in, scope_info))
	var has_changed := translated.name != type.name
	for generic in type.generics:
		var translated_generic := _translated_type(generic, written_in, scope_info)
		if translated_generic == null:
			return null
		translated.generics.append(translated_generic)
		has_changed = has_changed or translated_generic != generic
	if translated.name.is_empty():
		return null
	return translated if has_changed else type


static func _translated_name(type_name: String, written_in: GDSExSymbolIndex.GDSExScopeInfo, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> String:
	if _is_written_the_same_everywhere(type_name):
		return type_name
	var is_another_script := written_in.index != scope_info.index
	var enum_name := ""
	var named_class := find_type_class(type_name, written_in)
	if named_class == null:
		enum_name = type_name.get_slice(MEMBER_ACCESS, type_name.get_slice_count(MEMBER_ACCESS) - 1)
		named_class = _find_enum_class(type_name, enum_name, written_in, false)
	if named_class == null:
		return "" if is_another_script else type_name
	if _means_the_same(type_name, enum_name, named_class, scope_info):
		return type_name
	if enum_name.is_empty():
		return GDSExScriptTypeNames.name_of_class(named_class, scope_info.class_scope, written_in.class_scope)
	return GDSExScriptTypeNames.name_of_enum(enum_name, named_class, scope_info.class_scope, written_in.class_scope)


static func _find_enum_class(type_name: String, enum_name: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo, is_strict: bool) -> GDSExSymbolIndex.GDSExClassScope:
	if enum_name == type_name:
		var declaring_class := GDSExScriptTypeNames.find_declaring_class(enum_name, scope_info.class_scope)
		return declaring_class if declaring_class != null and GDSExScriptTypeNames.declares_enum(declaring_class, enum_name) else null
	var owner_name := type_name.trim_suffix(MEMBER_ACCESS + enum_name)
	var owner_class := _find_visible_class(owner_name, scope_info) if is_strict else find_type_class(owner_name, scope_info)
	return null if owner_class == null else GDSExScriptTypeNames.find_enum_class(enum_name, owner_class)


static func _means_the_same(type_name: String, enum_name: String, named_class: GDSExSymbolIndex.GDSExClassScope, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> bool:
	var seen_class := _find_visible_class(type_name, scope_info) if enum_name.is_empty() else _find_enum_class(type_name, enum_name, scope_info, true)
	if seen_class == null:
		return false
	return GDSExScriptTypeNames.find_own_class(seen_class, scope_info.class_scope) == GDSExScriptTypeNames.find_own_class(named_class, scope_info.class_scope)


static func _find_visible_class(type_name: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExClassScope:
	var names := type_name.split(MEMBER_ACCESS)
	var found := _find_script_class(GDSExScriptLibrary.find_global_class_path(names[0]))
	var declaring_class := GDSExScriptTypeNames.find_declaring_class(names[0], scope_info.class_scope) if found == null else null
	if declaring_class != null:
		found = _find_inner_class(declaring_class, names[0])
	for index in range(1, names.size()):
		if found == null:
			return null
		found = _find_inner_class(found, names[index])
	return found


static func _is_written_the_same_everywhere(type_name: String) -> bool:
	if GDSExLanguage.is_known_type(type_name.get_slice(MEMBER_ACCESS, 0)):
		return true
	if type_name.contains(MEMBER_ACCESS):
		return false
	return type_name == GDSExLanguage.VOID_TYPE_NAME or is_global_enum(type_name) or not GDSExScriptLibrary.find_global_class_path(type_name).is_empty()


static func _resolved_return(type: GDSExSymbolIndex.GDSExTypeData, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	if type != null and type.name == GDSExLanguage.VOID_TYPE_NAME:
		return GDSExResolved.new()
	return _resolved_type(type, scope_info)


static func _resolved_name(type_name: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	return _resolved_type(GDSExSymbolIndex.make_type(type_name), scope_info)


static func _resolved_type(type: GDSExSymbolIndex.GDSExTypeData, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	var resolved := GDSExResolved.new()
	resolved.type = type
	if type != null:
		resolved.class_scope = find_type_class(type.name, scope_info)
	return resolved


static func find_type_class(type_name: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExClassScope:
	var names := type_name.split(MEMBER_ACCESS)
	var found := _find_named_class(names[0], scope_info)
	for index in range(1, names.size()):
		if found == null:
			return null
		found = _find_inner_class(found, names[index])
	return found


static func _find_named_class(type_name: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExClassScope:
	if GDSExLanguage.is_known_type(type_name):
		return null
	var global_class := _find_script_class(GDSExScriptLibrary.find_global_class_path(type_name))
	if global_class != null:
		return global_class
	var file_class := GDSExSymbolIndex.find_class(GDSExSymbolIndex.find_root_class(scope_info.class_scope), type_name)
	if file_class != null:
		return file_class
	var variable := GDSExSymbolIndex.find_variable(type_name, scope_info)
	if variable.is_defined:
		return _find_script_class(variable.symbol.script_path) if variable.symbol != null else null
	var member := find_class_member(scope_info.class_scope, type_name)
	if member == null:
		return null
	if member.kind == GDSExMember.GDSExKind.CLASS:
		return member.class_scope
	return _find_script_class(member.symbol.script_path if member.symbol != null else member.script_path)


static func _find_inner_class(class_scope: GDSExSymbolIndex.GDSExClassScope, inner_name: String) -> GDSExSymbolIndex.GDSExClassScope:
	for candidate in GDSExScriptTypeNames.class_and_bases(class_scope):
		if candidate.inner_classes.has(inner_name):
			return candidate.inner_classes[inner_name]
		var constant: GDSExSymbolIndex.GDSExVariableSymbol = candidate.vars.get(inner_name)
		if constant != null:
			return _find_script_class(constant.script_path)
	return null


static func _find_script_class(script_path: String) -> GDSExSymbolIndex.GDSExClassScope:
	var script_index := GDSExScriptLibrary.find_index(script_path)
	return null if script_index == null else script_index.root


static func _indexed(resolved: GDSExResolved, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	if resolved.type == null:
		return GDSExResolved.new()
	if not resolved.type.generics.is_empty():
		return _resolved_type(resolved.type.generics[resolved.type.generics.size() - 1], scope_info)
	var element: String = GDSExBuiltinTypes.INDEXING.get(resolved.type.name, "")
	if element.is_empty() or element == GDSExLanguage.VARIANT_TYPE_NAME:
		return GDSExResolved.new()
	return _resolved_name(element, scope_info)


static func _iterated(resolved: GDSExResolved, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExResolved:
	if resolved.type == null:
		return GDSExResolved.new()
	if not resolved.type.generics.is_empty():
		return _resolved_type(resolved.type.generics[0], scope_info)
	if resolved.type.name == GDSExLanguage.INTEGER_TYPE_NAME or resolved.type.name == GDSExLanguage.FLOAT_TYPE_NAME:
		return _resolved_type(resolved.type, scope_info)
	return _indexed(resolved, scope_info)


static func _class_type(class_scope: GDSExSymbolIndex.GDSExClassScope) -> GDSExSymbolIndex.GDSExTypeData:
	return GDSExSymbolIndex.make_type(class_scope.name if not class_scope.name.is_empty() else _base_class_name(class_scope))


static func _base_class_name(class_scope: GDSExSymbolIndex.GDSExClassScope) -> String:
	if class_scope.inherit_type == null:
		return GDSExLanguage.DEFAULT_SCRIPT_BASE
	return class_scope.inherit_type.name


static func _variable_member(type: GDSExSymbolIndex.GDSExTypeData) -> GDSExMember:
	var member := GDSExMember.new()
	member.type = type
	return member


static func _symbol_member(symbol: GDSExSymbolIndex.GDSExVariableSymbol) -> GDSExMember:
	var member := _variable_member(symbol.type)
	member.symbol = symbol
	member.is_constant = symbol.is_const
	return member


static func _find_own_member(class_scope: GDSExSymbolIndex.GDSExClassScope, member_name: String) -> GDSExMember:
	var member: GDSExMember = null
	if class_scope.functions.has(member_name):
		member = _function_member(class_scope.functions[member_name][0])
	elif class_scope.vars.has(member_name):
		member = _symbol_member(class_scope.vars[member_name])
		if GDSExScriptTypeNames.declares_enum(class_scope, member_name):
			member.kind = GDSExMember.GDSExKind.ENUM
	elif class_scope.signals.has(member_name):
		member = _signal_member(class_scope.signals[member_name])
	elif class_scope.inner_classes.has(member_name):
		member = GDSExMember.new()
		member.kind = GDSExMember.GDSExKind.CLASS
		member.class_scope = class_scope.inner_classes[member_name]
	if member != null:
		member.owner_scope = class_scope
	return member


static func _constant_member(type: GDSExSymbolIndex.GDSExTypeData) -> GDSExMember:
	var member := _variable_member(type)
	member.is_constant = true
	return member


static func _function_member(function: GDSExSymbolIndex.GDSExFunctionScope) -> GDSExMember:
	var member := GDSExMember.new()
	member.kind = GDSExMember.GDSExKind.FUNCTION
	member.type = function.return_type
	member.function = function
	_add_params(member, function.params)
	return member


static func _signal_member(symbol: GDSExSymbolIndex.GDSExSignalSymbol) -> GDSExMember:
	var member := GDSExMember.new()
	member.kind = GDSExMember.GDSExKind.SIGNAL
	_add_params(member, symbol.params)
	return member


static func _add_params(member: GDSExMember, params: Dictionary) -> void:
	for param_name: String in params:
		member.param_names.append(param_name)
		member.param_types.append(params[param_name])


static func _find_builtin_member(type: GDSExSymbolIndex.GDSExTypeData, member_name: String) -> GDSExMember:
	var functions: Dictionary = GDSExBuiltinTypes.FUNCTIONS.get(type.name, {})
	if functions.has(member_name):
		var signature: PackedStringArray = (functions[member_name] as String).split(GDSExBuiltinTypes.SIGNATURE_SEPARATOR)
		var member := GDSExMember.new()
		member.kind = GDSExMember.GDSExKind.FUNCTION
		member.type = GDSExSymbolIndex.make_type(signature[0])
		for argument_type in signature[1].split(GDSExBuiltinTypes.ARGUMENT_SEPARATOR, false):
			member.param_names.append("")
			member.param_types.append(GDSExSymbolIndex.make_type(argument_type))
		_apply_generics(member, type, member_name)
		return member
	var members: Dictionary = GDSExBuiltinTypes.MEMBERS.get(type.name, {})
	if members.has(member_name):
		return _variable_member(GDSExSymbolIndex.make_type(members[member_name]))
	return null


static func _apply_generics(member: GDSExMember, type: GDSExSymbolIndex.GDSExTypeData, member_name: String) -> void:
	if type.generics.is_empty():
		return
	var is_array := type.name == GDSExLanguage.ARRAY_TYPE_NAME
	var returns := GDSExLanguage.ARRAY_RETURNS if is_array else GDSExLanguage.DICTIONARY_RETURNS
	var params := GDSExLanguage.ARRAY_PARAMS if is_array else GDSExLanguage.DICTIONARY_PARAMS
	if returns.has(member_name):
		member.type = _substitute_generics(returns[member_name], type)
	if params.has(member_name):
		var templates: Array = params[member_name]
		for index in mini(templates.size(), member.param_types.size()):
			member.param_types[index] = _substitute_generics(templates[index], type)


static func _substitute_generics(template: String, type: GDSExSymbolIndex.GDSExTypeData) -> GDSExSymbolIndex.GDSExTypeData:
	var first := GDSExSymbolIndex.type_to_string(type.generics[0])
	var last := GDSExSymbolIndex.type_to_string(type.generics[type.generics.size() - 1])
	var text := template.replace(GDSExLanguage.ELEMENT_PLACEHOLDER, first).replace(GDSExLanguage.KEY_PLACEHOLDER, first).replace(GDSExLanguage.VALUE_PLACEHOLDER, last)
	return GDSExSymbolIndex.parse_type(text)


static func _load_script(path: String) -> Script:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Script


static func _find_script_member(script: Script, member_name: String) -> GDSExMember:
	for function in script.get_script_method_list():
		if function["name"] == member_name:
			return _engine_callable_member(GDSExMember.GDSExKind.FUNCTION, function)
	for signal_info in script.get_script_signal_list():
		if signal_info["name"] == member_name:
			return _engine_callable_member(GDSExMember.GDSExKind.SIGNAL, signal_info)
	for property in script.get_script_property_list():
		if property["name"] == member_name and property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			return _variable_member(_type_from_info(property, false))
	var current := script
	while current != null:
		var constants := current.get_script_constant_map()
		if constants.has(member_name):
			var is_class_alias: bool = constants[member_name] is Script
			var constant := _constant_member(GDSExSymbolIndex.make_type(member_name) if is_class_alias else _type_of_value(constants[member_name]))
			constant.is_class_alias = is_class_alias
			if is_class_alias:
				constant.script_path = (constants[member_name] as Script).resource_path
			return constant
		current = current.get_base_script()
	return _find_engine_member(script.get_instance_base_type(), member_name)


static func _type_of_value(value: Variant) -> GDSExSymbolIndex.GDSExTypeData:
	if value is Object:
		return GDSExSymbolIndex.make_type((value as Object).get_class())
	return GDSExSymbolIndex.make_type(type_string(typeof(value)))


static func _find_engine_member(type_name: String, member_name: String) -> GDSExMember:
	if not ClassDB.class_exists(type_name):
		return null
	for function in ClassDB.class_get_method_list(type_name):
		if function["name"] == member_name:
			return _engine_callable_member(GDSExMember.GDSExKind.FUNCTION, function)
	if ClassDB.class_has_signal(type_name, member_name):
		return _engine_callable_member(GDSExMember.GDSExKind.SIGNAL, ClassDB.class_get_signal(type_name, member_name))
	for property in ClassDB.class_get_property_list(type_name):
		if property["name"] == member_name:
			return _variable_member(_type_from_info(property, false))
	if ClassDB.class_has_integer_constant(type_name, member_name) or ClassDB.class_has_enum(type_name, member_name):
		return _constant_member(GDSExSymbolIndex.make_type(GDSExLanguage.INTEGER_TYPE_NAME))
	return null


static func _engine_callable_member(kind: GDSExMember.GDSExKind, info: Dictionary) -> GDSExMember:
	var member := GDSExMember.new()
	member.kind = kind
	if kind == GDSExMember.GDSExKind.FUNCTION:
		member.type = _type_from_info(info["return"], true)
	for argument: Dictionary in info["args"]:
		member.param_names.append(argument["name"])
		member.param_types.append(_type_from_info(argument, false))
	return member


static func _type_from_info(info: Dictionary, is_return: bool) -> GDSExSymbolIndex.GDSExTypeData:
	var type: int = info.get("type", TYPE_NIL)
	var hint: int = info.get("hint", PROPERTY_HINT_NONE)
	var hint_string: String = info.get("hint_string", "")
	var object_class := String(info.get("class_name", &""))
	if type == TYPE_OBJECT:
		if not object_class.is_empty():
			return GDSExSymbolIndex.make_type(object_class)
		if hint == PROPERTY_HINT_RESOURCE_TYPE and is_identifier(hint_string):
			return GDSExSymbolIndex.make_type(hint_string)
		return GDSExSymbolIndex.make_type(GDSExLanguage.OBJECT_TYPE_NAME)
	if type == TYPE_NIL:
		var is_variant: bool = info.get("usage", 0) & PROPERTY_USAGE_NIL_IS_VARIANT != 0
		return GDSExSymbolIndex.make_type(GDSExLanguage.VOID_TYPE_NAME if is_return and not is_variant else GDSExLanguage.VARIANT_TYPE_NAME)
	if type == TYPE_ARRAY and hint == PROPERTY_HINT_ARRAY_TYPE and is_identifier(hint_string):
		return GDSExSymbolIndex.parse_type(TYPED_ARRAY_TEMPLATE % hint_string)
	return GDSExSymbolIndex.make_type(type_string(type))
