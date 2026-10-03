@tool
extends RefCounted

const SymbolIndex = preload("res://addons/code_generator/analysis/symbol_index.gd")
const SourceScanner = preload("res://addons/code_generator/analysis/source_scanner.gd")
const CallSiteParser = preload("res://addons/code_generator/analysis/call_site_parser.gd")
const Language = preload("res://addons/code_generator/analysis/language.gd")
const BuiltinTypes = preload("res://addons/code_generator/analysis/builtin_types.gd")

const MEMBER_ACCESS: String = "."
const CONNECT_METHOD: String = "connect"
const EMIT_METHOD: String = "emit"
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
const MAX_INHERITANCE_DEPTH: int = 32
const MAX_DEFERRED_DEPTH: int = 16
const NULL_LITERAL: String = "null"
const CONSTRUCTOR_TEMPLATE: String = "%s.new()"
const TYPED_ARRAY_TEMPLATE: String = "Array[%s]"

static var _modifiers_pattern := RegEx.create_from_string("^(?:(?:@\\w+(?:\\([^)]*\\))?|static)\\s+)+")
static var _declaration_pattern := RegEx.create_from_string("^(?:var|const)\\s+\\w+(.*)$")
static var _return_pattern := RegEx.create_from_string("^return\\b(.*)$")
static var _condition_pattern := RegEx.create_from_string("^(?:if|elif|while)\\b(.*):$")
static var _for_pattern := RegEx.create_from_string("^for\\s+\\w+\\s*(?::\\s*(.+?))?\\s+in\\s+(.+):$")
static var _identifier_pattern := RegEx.create_from_string("^[A-Za-z_]\\w*$")
static var _deferred_depth: int = 0


class Member:
	enum Kind { VARIABLE, METHOD, SIGNAL }

	var kind: Kind = Kind.VARIABLE
	var type: SymbolIndex.TypeData
	var param_names: PackedStringArray = []
	var param_types: Array[SymbolIndex.TypeData] = []
	var function: SymbolIndex.FunctionScope
	var symbol: SymbolIndex.VariableSymbol


class Resolved:
	var type: SymbolIndex.TypeData
	var class_scope: SymbolIndex.ClassScope
	var function: SymbolIndex.FunctionScope
	var is_class_reference: bool = false

	func is_known() -> bool:
		return type != null or class_scope != null


class ChainToken:
	var text: String = ""
	var name: String = ""
	var is_call: bool = false
	var is_indexed: bool = false
	var is_valid: bool = true


static func resolve_expression_type(expression: String, scope_info: SymbolIndex.ScopeInfo) -> SymbolIndex.TypeData:
	return resolve_expression(expression, scope_info).type


static func resolve_expression(expression: String, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	var text := _unwrap(expression)
	if text.is_empty():
		return Resolved.new()
	var literal := SymbolIndex.literal_type(text)
	if literal != null:
		return _resolved_type(literal, scope_info)
	var operation := _resolve_operation(text, scope_info)
	if operation != null:
		return operation
	return _resolve_chain(text, scope_info)


static func resolve_self(scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	var resolved := Resolved.new()
	resolved.class_scope = scope_info.class_scope
	resolved.type = _class_type(scope_info.class_scope)
	return resolved


static func find_member(owner: Resolved, member_name: String) -> Member:
	if owner.class_scope != null:
		return find_class_member(owner.class_scope, member_name)
	if owner.type == null:
		return null
	if Language.is_builtin_type(owner.type.name):
		return _find_builtin_member(owner.type, member_name)
	return _find_engine_member(owner.type.name, member_name)


static func find_class_member(class_scope: SymbolIndex.ClassScope, member_name: String) -> Member:
	var root := SymbolIndex.find_root_class(class_scope)
	var current := class_scope
	for depth in MAX_INHERITANCE_DEPTH:
		if current.methods.has(member_name):
			return _method_member(current.methods[member_name][0])
		if current.vars.has(member_name):
			return _symbol_member(current.vars[member_name])
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
	var member := find_member(owner, signal_name)
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


static func function_return_type(function: SymbolIndex.FunctionScope, scope_info: SymbolIndex.ScopeInfo) -> SymbolIndex.TypeData:
	if function.return_type != null:
		return function.return_type
	if function.return_codes.is_empty() or _deferred_depth >= MAX_DEFERRED_DEPTH:
		return null
	_deferred_depth += 1
	var common: SymbolIndex.TypeData = null
	for index in function.return_codes.size():
		var line := function.return_lines[index]
		var return_scope := SymbolIndex.get_scope_info_for_scope(scope_info.index, function, line) if function.is_inline else SymbolIndex.get_scope_info_for_line(scope_info.index, line)
		var returned := resolve_expression_type(function.return_codes[index], return_scope)
		if returned == null or (common != null and SymbolIndex.type_to_string(common) != SymbolIndex.type_to_string(returned)):
			common = null
			break
		common = returned
	_deferred_depth -= 1
	return common


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
		member = find_member(resolve_expression(parent.receiver, scope_info), parent.name)
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

	var for_match := _for_pattern.search(code)
	if for_match != null:
		if not _is_whole(for_match.get_string(2), expression):
			return null
		if for_match.get_string(1).is_empty():
			return SymbolIndex.make_type(Language.ARRAY_TYPE_NAME)
		return SymbolIndex.parse_type(TYPED_ARRAY_TEMPLATE % for_match.get_string(1))

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
		if SourceScanner.OPENING_BRACKETS.contains(character):
			depth += 1
		elif SourceScanner.CLOSING_BRACKETS.contains(character):
			depth -= 1
		elif depth == 0 and index >= from and text.substr(index, needle.length()) == needle:
			return index
	return -1


static func _resolve_operation(text: String, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	var condition := _find_text(text, TERNARY_CONDITION, 0)
	var alternative := _find_text(text, TERNARY_ALTERNATIVE, condition + 1) if condition != -1 else -1
	if alternative != -1:
		var first := resolve_expression(text.substr(0, condition), scope_info)
		var second := resolve_expression(text.substr(alternative + TERNARY_ALTERNATIVE.length()), scope_info)
		return first if _same_type(first, second) else Resolved.new()

	for operator in BOOLEAN_OPERATORS:
		if _find_text(text, operator, 0) != -1:
			return _resolved_name(Language.BOOLEAN_TYPE_NAME, scope_info)
	if text.begins_with(NEGATION_PREFIXES[0]):
		return _resolved_name(Language.BOOLEAN_TYPE_NAME, scope_info)
	for operator in SHIFT_OPERATORS:
		if _find_text(text, operator, 0) != -1:
			return _resolved_name(Language.INTEGER_TYPE_NAME, scope_info)
	for operator in COMPARISON_OPERATORS:
		if _find_text(text, operator, 0) != -1:
			return _resolved_name(Language.BOOLEAN_TYPE_NAME, scope_info)
	if text.begins_with(NEGATION_PREFIXES[1]):
		return _resolved_name(Language.BOOLEAN_TYPE_NAME, scope_info)

	var cast := _find_text(text, CAST_OPERATOR, 0)
	if cast != -1:
		return _resolved_type(SymbolIndex.parse_type(text.substr(cast + CAST_OPERATOR.length())), scope_info)

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
		if SourceScanner.CLOSING_BRACKETS.contains(character):
			depth += 1
		elif SourceScanner.OPENING_BRACKETS.contains(character):
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
	while start > 0 and (text[start - 1] == NODE_PATH_SEPARATOR or SourceScanner.is_identifier_character(text[start - 1])):
		start -= 1
	return start > 0 and NODE_PATH_PREFIXES.contains(text[start - 1])


static func _arithmetic_result(left: Resolved, right: Resolved, operator: String) -> Resolved:
	if left.type == null or right.type == null:
		return Resolved.new()
	var left_name := SymbolIndex.type_to_string(left.type)
	var right_name := SymbolIndex.type_to_string(right.type)
	if left_name == right_name:
		return left
	if left_name == Language.STRING_TYPE_NAME and operator == FORMAT_OPERATOR:
		return left
	var numbers: Array[String] = [Language.INTEGER_TYPE_NAME, Language.FLOAT_TYPE_NAME]
	if numbers.has(left_name) and numbers.has(right_name):
		var result := Resolved.new()
		result.type = SymbolIndex.make_type(Language.FLOAT_TYPE_NAME)
		return result
	if numbers.has(right_name):
		return left
	if numbers.has(left_name):
		return right
	return Resolved.new()


static func _same_type(first: Resolved, second: Resolved) -> bool:
	return first.type != null and second.type != null and SymbolIndex.type_to_string(first.type) == SymbolIndex.type_to_string(second.type)


static func _resolve_chain(text: String, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	var tokens := _split_chain(text)
	if tokens.is_empty():
		return Resolved.new()
	var current := _resolve_first_token(tokens[0], scope_info)
	for index in range(1, tokens.size()):
		if not current.is_known():
			break
		current = _resolve_member_token(current, tokens[index], scope_info)
	return current


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
	while not rest.is_empty() and not token.name.is_empty():
		var close := SourceScanner.find_matching_bracket(rest, 0) if SourceScanner.OPENING_BRACKETS.contains(rest[0]) else -1
		if close == -1:
			token.is_valid = false
			break
		rest = rest.substr(close + 1).strip_edges()
	return token


static func _resolve_first_token(token_text: String, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	var token := _parse_token(token_text)
	if not token.is_valid:
		return Resolved.new()
	var resolved: Resolved
	if token.name.is_empty():
		resolved = _resolve_nameless(token.text, scope_info)
	elif token.is_call:
		resolved = _resolve_bare_call(token.name, scope_info)
	elif token.name == Language.SELF_KEYWORD:
		resolved = resolve_self(scope_info)
	else:
		resolved = _resolve_identifier(token.name, scope_info)
	return _indexed(resolved, scope_info) if token.is_indexed and not token.name.is_empty() else resolved


static func _resolve_nameless(text: String, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	if text.is_empty():
		return Resolved.new()
	if NODE_PATH_PREFIXES.contains(text[0]):
		return _resolved_name(Language.NODE_TYPE_NAME, scope_info)
	if text.begins_with("(") and SourceScanner.find_matching_bracket(text, 0) == text.length() - 1:
		return resolve_expression(text, scope_info)
	return _resolved_type(SymbolIndex.literal_type(text), scope_info)


static func _resolve_bare_call(function_name: String, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	if Language.is_builtin_type(function_name):
		return _resolved_name(function_name, scope_info)
	if Language.GLOBAL_FUNCTIONS.has(function_name):
		return _resolved_return(SymbolIndex.make_type(Language.GLOBAL_FUNCTIONS[function_name]), scope_info)
	var member := find_class_member(scope_info.class_scope, function_name)
	if member != null and member.kind == Member.Kind.METHOD:
		return _resolved_member(member, true, scope_info)
	return Resolved.new()


static func _resolve_identifier(identifier: String, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	var variable := SymbolIndex.find_variable(identifier, scope_info)
	if variable.is_defined:
		return _resolve_symbol(variable.symbol, variable.type, scope_info)
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


static func _resolve_symbol(symbol: SymbolIndex.VariableSymbol, known_type: SymbolIndex.TypeData, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	if symbol == null or symbol.deferred == SymbolIndex.VariableSymbol.Deferred.NONE:
		var resolved := _resolved_type(known_type, scope_info)
		if symbol != null:
			resolved.function = symbol.function
		return resolved
	if _deferred_depth >= MAX_DEFERRED_DEPTH:
		return Resolved.new()
	_deferred_depth += 1
	var declaration_scope := SymbolIndex.get_scope_info_for_line(scope_info.index, symbol.start_line)
	var value := resolve_expression(symbol.value_code, declaration_scope)
	_deferred_depth -= 1
	if symbol.deferred == SymbolIndex.VariableSymbol.Deferred.ITERATION:
		return _iterated(value, scope_info)
	return value


static func _resolve_member_token(owner: Resolved, token_text: String, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	var token := _parse_token(token_text)
	if not token.is_valid or token.name.is_empty():
		return Resolved.new()
	var resolved := Resolved.new()
	if owner.function != null and token.is_call and Language.CALLABLE_INVOCATIONS.has(token.name):
		resolved = _resolved_return(function_return_type(owner.function, scope_info), scope_info)
	elif owner.function != null and token.is_call and Language.CALLABLE_BINDINGS.has(token.name):
		resolved = owner
	elif token.is_call and token.name == Language.CONSTRUCTOR_NAME:
		resolved.type = owner.type
		resolved.class_scope = owner.class_scope
	else:
		var member := find_member(owner, token.name)
		if member != null:
			resolved = _resolved_member(member, token.is_call, scope_info)
		elif owner.is_class_reference and owner.class_scope == null and Language.is_builtin_type(owner.type.name):
			resolved.type = owner.type
	return _indexed(resolved, scope_info) if token.is_indexed else resolved


static func _resolved_member(member: Member, is_call: bool, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	match member.kind:
		Member.Kind.SIGNAL:
			return _resolved_name(Language.SIGNAL_TYPE_NAME, scope_info)
		Member.Kind.METHOD:
			if is_call:
				var return_type := member.type
				if return_type == null and member.function != null:
					return_type = function_return_type(member.function, scope_info)
				return _resolved_return(return_type, scope_info)
			var reference := _resolved_name(Language.CALLABLE_TYPE_NAME, scope_info)
			reference.function = member.function
			return reference
	if member.symbol != null:
		return _resolve_symbol(member.symbol, member.type, scope_info)
	return _resolved_type(member.type, scope_info)


static func _resolved_return(type: SymbolIndex.TypeData, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	if type != null and type.name == Language.VOID_TYPE_NAME:
		return Resolved.new()
	return _resolved_type(type, scope_info)


static func _resolved_name(type_name: String, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	return _resolved_type(SymbolIndex.make_type(type_name), scope_info)


static func _resolved_type(type: SymbolIndex.TypeData, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	var resolved := Resolved.new()
	resolved.type = type
	if type != null:
		resolved.class_scope = SymbolIndex.find_class(SymbolIndex.find_root_class(scope_info.class_scope), type.name)
	return resolved


static func _indexed(resolved: Resolved, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	if resolved.type == null:
		return Resolved.new()
	if not resolved.type.generics.is_empty():
		return _resolved_type(resolved.type.generics[resolved.type.generics.size() - 1], scope_info)
	var element: String = BuiltinTypes.INDEXING.get(resolved.type.name, "")
	if element.is_empty() or element == Language.VARIANT_TYPE_NAME:
		return Resolved.new()
	return _resolved_name(element, scope_info)


static func _iterated(resolved: Resolved, scope_info: SymbolIndex.ScopeInfo) -> Resolved:
	if resolved.type == null:
		return Resolved.new()
	if not resolved.type.generics.is_empty():
		return _resolved_type(resolved.type.generics[0], scope_info)
	if resolved.type.name == Language.INTEGER_TYPE_NAME or resolved.type.name == Language.FLOAT_TYPE_NAME:
		return _resolved_type(resolved.type, scope_info)
	return _indexed(resolved, scope_info)


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


static func _symbol_member(symbol: SymbolIndex.VariableSymbol) -> Member:
	var member := _variable_member(symbol.type)
	member.symbol = symbol
	return member


static func _method_member(method: SymbolIndex.FunctionScope) -> Member:
	var member := Member.new()
	member.kind = Member.Kind.METHOD
	member.type = method.return_type
	member.function = method
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


static func _find_builtin_member(type: SymbolIndex.TypeData, member_name: String) -> Member:
	var methods: Dictionary = BuiltinTypes.METHODS.get(type.name, {})
	if methods.has(member_name):
		var signature: PackedStringArray = (methods[member_name] as String).split(BuiltinTypes.SIGNATURE_SEPARATOR)
		var member := Member.new()
		member.kind = Member.Kind.METHOD
		member.type = SymbolIndex.make_type(signature[0])
		for argument_type in signature[1].split(BuiltinTypes.ARGUMENT_SEPARATOR, false):
			member.param_names.append("")
			member.param_types.append(SymbolIndex.make_type(argument_type))
		_apply_generics(member, type, member_name)
		return member
	var members: Dictionary = BuiltinTypes.MEMBERS.get(type.name, {})
	if members.has(member_name):
		return _variable_member(SymbolIndex.make_type(members[member_name]))
	return null


static func _apply_generics(member: Member, type: SymbolIndex.TypeData, member_name: String) -> void:
	if type.generics.is_empty():
		return
	var is_array := type.name == Language.ARRAY_TYPE_NAME
	var returns := Language.ARRAY_RETURNS if is_array else Language.DICTIONARY_RETURNS
	var params := Language.ARRAY_PARAMS if is_array else Language.DICTIONARY_PARAMS
	if returns.has(member_name):
		member.type = _substitute_generics(returns[member_name], type)
	if params.has(member_name):
		var templates: Array = params[member_name]
		for index in mini(templates.size(), member.param_types.size()):
			member.param_types[index] = _substitute_generics(templates[index], type)


static func _substitute_generics(template: String, type: SymbolIndex.TypeData) -> SymbolIndex.TypeData:
	var first := SymbolIndex.type_to_string(type.generics[0])
	var last := SymbolIndex.type_to_string(type.generics[type.generics.size() - 1])
	var text := template.replace(Language.ELEMENT_PLACEHOLDER, first).replace(Language.KEY_PLACEHOLDER, first).replace(Language.VALUE_PLACEHOLDER, last)
	return SymbolIndex.parse_type(text)


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
		return _variable_member(SymbolIndex.make_type(Language.INTEGER_TYPE_NAME))
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
