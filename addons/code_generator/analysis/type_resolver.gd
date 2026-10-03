@tool
extends RefCounted

const SymbolIndex = preload("res://addons/code_generator/analysis/symbol_index.gd")
const SourceScanner = preload("res://addons/code_generator/analysis/source_scanner.gd")
const CallSiteParser = preload("res://addons/code_generator/analysis/call_site_parser.gd")
const Language = preload("res://addons/code_generator/analysis/language.gd")

const MEMBER_ACCESS: String = "."
const CONNECT_METHOD: String = "connect"
const EMIT_METHOD: String = "emit"
const AWAIT_PREFIX: String = "await "
const NEGATION_PREFIXES: Array[String] = ["not ", "!"]
const BOOLEAN_OPERATORS: Array[String] = [" and ", " or ", "&&", "||"]
const NODE_PATH_PREFIXES: String = "$%"
const NON_ASSIGNMENT_NEIGHBOURS: String = "=!<>:+-*/%&|^~"
const MAX_INHERITANCE_DEPTH: int = 32
const NULL_LITERAL: String = "null"
const CONSTRUCTOR_TEMPLATE: String = "%s.new()"
const TYPED_ARRAY_TEMPLATE: String = "Array[%s]"

static var _modifiers_pattern := RegEx.create_from_string("^(?:(?:@\\w+(?:\\([^)]*\\))?|static)\\s+)+")
static var _declaration_pattern := RegEx.create_from_string("^(?:var|const)\\s+\\w+(.*)$")
static var _return_pattern := RegEx.create_from_string("^return\\b(.*)$")
static var _condition_pattern := RegEx.create_from_string("^(?:if|elif|while)\\b(.*):$")
static var _identifier_pattern := RegEx.create_from_string("^[A-Za-z_]\\w*$")


class Member:
	enum Kind { VARIABLE, METHOD, SIGNAL }

	var kind: Kind = Kind.VARIABLE
	var type: SymbolIndex.TypeData
	var param_names: PackedStringArray = []
	var param_types: Array[SymbolIndex.TypeData] = []


class Resolved:
	var type: SymbolIndex.TypeData
	var class_scope: SymbolIndex.ClassScope
	var is_class_reference: bool = false

	func is_known() -> bool:
		return type != null or class_scope != null


class ChainToken:
	var text: String = ""
	var name: String = ""
	var is_call: bool = false
	var is_indexed: bool = false


static func resolve_expression_type(expression: String, scope_info: SymbolIndex.ScopeInfo) -> SymbolIndex.TypeData:
	return resolve_expression(expression, scope_info).type


static func resolve_expression(expression: String, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	var text := _unwrap(expression)
	var literal := SymbolIndex.literal_type(text)
	if literal != null:
		return _resolved_type(literal, scope_info)
	var tokens := _split_chain(text)
	if tokens.is_empty():
		return Resolved.new()
	var current := _resolve_first_token(tokens[0], scope_info)
	for index in range(1, tokens.size()):
		if not current.is_known():
			break
		current = _resolve_member_token(current, tokens[index], scope_info)
	return current


static func resolve_self(scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	var resolved := Resolved.new()
	resolved.class_scope = scope_info.class_scope
	resolved.type = _class_type(scope_info.class_scope)
	return resolved


static func find_member(owner: Resolved, member_name: String, scope_info: SymbolIndex.ScopeInfo) -> Member:
	if owner.class_scope != null:
		return find_class_member(owner.class_scope, member_name)
	if owner.type != null:
		return _find_engine_member(owner.type.name, member_name)
	return null


static func find_class_member(class_scope: SymbolIndex.ClassScope, member_name: String) -> Member:
	var root := SymbolIndex.find_root_class(class_scope)
	var current := class_scope
	for depth in MAX_INHERITANCE_DEPTH:
		if current.methods.has(member_name):
			return _method_member(current.methods[member_name][0])
		if current.vars.has(member_name):
			return _variable_member((current.vars[member_name] as SymbolIndex.VariableSymbol).type)
		if current.signals.has(member_name):
			return _signal_member(current.signals[member_name])
		var base_name := _base_class_name(current)
		var base_class := SymbolIndex.find_class(root, base_name)
		if base_class == null or base_class == current:
			return _find_engine_member(base_name, member_name)
		current = base_class
	return null


static func resolve_signal(expression: String, scope_info: SymbolIndex.ScopeInfo) -> Member:
	var tokens := _split_chain(expression.strip_edges())
	if tokens.is_empty():
		return null
	var signal_name := tokens[tokens.size() - 1]
	tokens.remove_at(tokens.size() - 1)
	var owner := resolve_self(scope_info) if tokens.is_empty() else resolve_expression(MEMBER_ACCESS.join(tokens), scope_info)
	var member := find_member(owner, signal_name, scope_info)
	return member if member != null and member.kind == Member.Kind.SIGNAL else null


static func is_function_defined(function_name: String, scope_info: SymbolIndex.ScopeInfo) -> bool:
	if function_name == Language.SUPER_KEYWORD or Language.GLOBAL_FUNCTIONS.has(function_name):
		return true
	if Language.is_known_type(function_name):
		return true
	if SymbolIndex.find_class(SymbolIndex.find_root_class(scope_info.class_scope), function_name) != null:
		return true
	return find_class_member(scope_info.class_scope, function_name) != null


static func is_identifier(text: String) -> bool:
	return _identifier_pattern.search(text) != null


static func expected_type(statement_code: String, call: CallSiteParser.CallSite, scope_info: SymbolIndex.ScopeInfo) -> SymbolIndex.TypeData:
	var expression := statement_code.substr(call.expression_offset, call.expression_end() - call.expression_offset)
	var known_type := _expected_argument_type(call, expression, scope_info) if call.parent != null else _expected_statement_type(statement_code, expression, scope_info)
	return known_type if known_type != null else SymbolIndex.make_type(Language.VARIANT_TYPE_NAME)


static func default_value_text(type: SymbolIndex.TypeData) -> String:
	var type_name := SymbolIndex.get_base_type_name(type)
	if type_name == Language.VOID_TYPE_NAME:
		return ""
	if type_name == Language.VARIANT_TYPE_NAME:
		return NULL_LITERAL
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


static func _expected_argument_type(call: CallSiteParser.CallSite, expression: String, scope_info: SymbolIndex.ScopeInfo) -> SymbolIndex.TypeData:
	var parent := call.parent
	var index := call.parent_argument_index
	if index == -1 or not _is_whole(parent.arguments[index].text, expression):
		return null
	if not parent.receiver.is_empty() and (parent.name == CONNECT_METHOD or parent.name == EMIT_METHOD):
		var signal_member := resolve_signal(parent.receiver, scope_info)
		if signal_member != null:
			if parent.name == CONNECT_METHOD:
				return SymbolIndex.make_type(Language.CALLABLE_TYPE_NAME) if index == 0 else null
			return signal_member.param_types[index] if index < signal_member.param_types.size() else null
	var member: Member
	if parent.receiver.is_empty():
		member = find_class_member(scope_info.class_scope, parent.name)
	else:
		member = find_member(resolve_expression(parent.receiver, scope_info), parent.name, scope_info)
	if member == null or member.kind != Member.Kind.METHOD or index >= member.param_types.size():
		return null
	return member.param_types[index]


static func _expected_statement_type(statement_code: String, expression: String, scope_info: SymbolIndex.ScopeInfo) -> SymbolIndex.TypeData:
	var code := _modifiers_pattern.sub(statement_code, "")
	if _is_whole(code, expression):
		return SymbolIndex.make_type(Language.VOID_TYPE_NAME)

	var declaration_match := _declaration_pattern.search(code)
	if declaration_match != null:
		var declaration := SymbolIndex.parse_declaration_tail(declaration_match.get_string(1))
		return declaration.type if _is_whole(declaration.value, expression) else null

	var return_match := _return_pattern.search(code)
	if return_match != null:
		if _is_whole(return_match.get_string(1), expression) and scope_info.function_scope != null:
			return scope_info.function_scope.return_type
		return null

	var condition_match := _condition_pattern.search(code)
	if condition_match != null:
		if _is_boolean_operand(condition_match.get_string(1), expression):
			return SymbolIndex.make_type(Language.BOOLEAN_TYPE_NAME)
		return null

	var assignment := _find_assignment(code)
	if assignment != -1 and _is_whole(code.substr(assignment + 1), expression):
		return resolve_expression_type(code.substr(0, assignment), scope_info)
	return null


static func _find_assignment(code: String) -> int:
	var from := 0
	while true:
		var index := SymbolIndex.find_top_level(code, SymbolIndex.ASSIGNMENT, from)
		if index <= 0:
			return -1
		var is_followed := index + 1 < code.length() and code[index + 1] == SymbolIndex.ASSIGNMENT
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
	while result.begins_with("(") and SourceScanner.find_matching_bracket(result, 0) == result.length() - 1:
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
	var depth := 0
	var start := 0
	var index := 0
	while index < text.length():
		var character := text[index]
		if SourceScanner.OPENING_BRACKETS.contains(character):
			depth += 1
		elif SourceScanner.CLOSING_BRACKETS.contains(character):
			depth -= 1
		elif depth == 0 and text.substr(index, operator.length()) == operator:
			operands.append(text.substr(start, index - start))
			index += operator.length()
			start = index
			continue
		index += 1
	operands.append(text.substr(start))
	return operands


static func _split_chain(text: String) -> PackedStringArray:
	return SymbolIndex.split_top_level(text, MEMBER_ACCESS)


static func _parse_token(token_text: String) -> ChainToken:
	var token := ChainToken.new()
	token.text = token_text.strip_edges()
	var name_end := 0
	while name_end < token.text.length() and SourceScanner.is_identifier_character(token.text[name_end]):
		name_end += 1
	token.name = token.text.substr(0, name_end)
	var rest := token.text.substr(name_end).strip_edges()
	token.is_call = rest.begins_with("(")
	token.is_indexed = rest.ends_with("]")
	return token


static func _resolve_first_token(token_text: String, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	var token := _parse_token(token_text)
	var resolved := Resolved.new()
	if token.name.is_empty():
		if not token.text.is_empty() and NODE_PATH_PREFIXES.contains(token.text[0]):
			resolved.type = SymbolIndex.make_type(Language.NODE_TYPE_NAME)
		return resolved
	if token.is_call:
		resolved = _resolve_bare_call(token.name, scope_info)
	elif token.name == Language.SELF_KEYWORD:
		resolved = resolve_self(scope_info)
	else:
		resolved = _resolve_identifier(token.name, scope_info)
	return _indexed(resolved, scope_info) if token.is_indexed else resolved


static func _resolve_bare_call(function_name: String, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	if Language.is_builtin_type(function_name):
		return _resolved_type(SymbolIndex.make_type(function_name), scope_info)
	if Language.GLOBAL_FUNCTIONS.has(function_name):
		return _resolved_return(SymbolIndex.make_type(Language.GLOBAL_FUNCTIONS[function_name]), scope_info)
	var member := find_class_member(scope_info.class_scope, function_name)
	if member != null and member.kind == Member.Kind.METHOD:
		return _resolved_return(member.type, scope_info)
	return Resolved.new()


static func _resolve_identifier(identifier: String, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	var variable := SymbolIndex.find_variable(identifier, scope_info)
	if variable.is_defined:
		return _resolved_type(variable.type, scope_info)
	var member := find_class_member(scope_info.class_scope, identifier)
	if member != null:
		return _resolved_member(member, false, scope_info)
	var resolved := Resolved.new()
	var file_class := SymbolIndex.find_class(SymbolIndex.find_root_class(scope_info.class_scope), identifier)
	if file_class != null:
		resolved.class_scope = file_class
		resolved.type = SymbolIndex.make_type(identifier)
		resolved.is_class_reference = true
	elif Language.is_known_type(identifier) or Engine.has_singleton(identifier):
		resolved.type = SymbolIndex.make_type(identifier)
		resolved.is_class_reference = true
	return resolved


static func _resolve_member_token(owner: Resolved, token_text: String, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	var token := _parse_token(token_text)
	var resolved := Resolved.new()
	if token.is_call and token.name == Language.CONSTRUCTOR_NAME:
		resolved.type = owner.type
		resolved.class_scope = owner.class_scope
	elif owner.is_class_reference and owner.class_scope == null and Language.is_builtin_type(owner.type.name):
		resolved.type = owner.type
	else:
		var member := find_member(owner, token.name, scope_info)
		if member != null:
			resolved = _resolved_member(member, token.is_call, scope_info)
	return _indexed(resolved, scope_info) if token.is_indexed else resolved


static func _resolved_member(member: Member, is_call: bool, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	match member.kind:
		Member.Kind.SIGNAL:
			return _resolved_type(SymbolIndex.make_type(Language.SIGNAL_TYPE_NAME), scope_info)
		Member.Kind.METHOD:
			if is_call:
				return _resolved_return(member.type, scope_info)
			return _resolved_type(SymbolIndex.make_type(Language.CALLABLE_TYPE_NAME), scope_info)
	return _resolved_type(member.type, scope_info)


static func _resolved_return(type: SymbolIndex.TypeData, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	if type != null and type.name == Language.VOID_TYPE_NAME:
		return Resolved.new()
	return _resolved_type(type, scope_info)


static func _resolved_type(type: SymbolIndex.TypeData, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	var resolved := Resolved.new()
	resolved.type = type
	if type != null:
		resolved.class_scope = SymbolIndex.find_class(SymbolIndex.find_root_class(scope_info.class_scope), type.name)
	return resolved


static func _indexed(resolved: Resolved, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	if resolved.type == null or resolved.type.generics.is_empty():
		return Resolved.new()
	return _resolved_type(resolved.type.generics[resolved.type.generics.size() - 1], scope_info)


static func _class_type(class_scope: SymbolIndex.ClassScope) -> SymbolIndex.TypeData:
	return SymbolIndex.make_type(class_scope.name if not class_scope.name.is_empty() else _base_class_name(class_scope))


static func _base_class_name(class_scope: SymbolIndex.ClassScope) -> String:
	if class_scope.inherit_type == null:
		return Language.DEFAULT_SCRIPT_BASE
	return class_scope.inherit_type.name


static func _variable_member(type: SymbolIndex.TypeData) -> Member:
	var member := Member.new()
	member.type = type
	return member


static func _method_member(method: SymbolIndex.FunctionScope) -> Member:
	var member := Member.new()
	member.kind = Member.Kind.METHOD
	member.type = method.return_type
	_add_params(member, method.params)
	return member


static func _signal_member(symbol: SymbolIndex.SignalSymbol) -> Member:
	var member := Member.new()
	member.kind = Member.Kind.SIGNAL
	_add_params(member, symbol.params)
	return member


static func _add_params(member: Member, params: Dictionary) -> void:
	for param_name: String in params:
		member.param_names.append(param_name)
		member.param_types.append(params[param_name])


static func _find_engine_member(type_name: String, member_name: String) -> Member:
	if not ClassDB.class_exists(type_name):
		return null
	for method in ClassDB.class_get_method_list(type_name):
		if method["name"] == member_name:
			return _engine_callable_member(Member.Kind.METHOD, method)
	if ClassDB.class_has_signal(type_name, member_name):
		return _engine_callable_member(Member.Kind.SIGNAL, ClassDB.class_get_signal(type_name, member_name))
	for property in ClassDB.class_get_property_list(type_name):
		if property["name"] == member_name:
			return _variable_member(_type_from_info(property, false))
	if ClassDB.class_has_integer_constant(type_name, member_name):
		return _variable_member(SymbolIndex.make_type(type_string(TYPE_INT)))
	return null


static func _engine_callable_member(kind: Member.Kind, info: Dictionary) -> Member:
	var member := Member.new()
	member.kind = kind
	if kind == Member.Kind.METHOD:
		member.type = _type_from_info(info["return"], true)
	for argument: Dictionary in info["args"]:
		member.param_names.append(argument["name"])
		member.param_types.append(_type_from_info(argument, false))
	return member


static func _type_from_info(info: Dictionary, is_return: bool) -> SymbolIndex.TypeData:
	var type: int = info.get("type", TYPE_NIL)
	var hint: int = info.get("hint", PROPERTY_HINT_NONE)
	var hint_string: String = info.get("hint_string", "")
	var object_class := String(info.get("class_name", &""))
	if type == TYPE_OBJECT:
		if not object_class.is_empty():
			return SymbolIndex.make_type(object_class)
		if hint == PROPERTY_HINT_RESOURCE_TYPE and is_identifier(hint_string):
			return SymbolIndex.make_type(hint_string)
		return SymbolIndex.make_type(Language.OBJECT_TYPE_NAME)
	if type == TYPE_NIL:
		var is_variant: bool = info.get("usage", 0) & PROPERTY_USAGE_NIL_IS_VARIANT != 0
		return SymbolIndex.make_type(Language.VOID_TYPE_NAME if is_return and not is_variant else Language.VARIANT_TYPE_NAME)
	if type == TYPE_ARRAY and hint == PROPERTY_HINT_ARRAY_TYPE and is_identifier(hint_string):
		return SymbolIndex.parse_type(TYPED_ARRAY_TEMPLATE % hint_string)
	return SymbolIndex.make_type(type_string(type))
