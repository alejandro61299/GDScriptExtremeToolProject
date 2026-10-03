@tool
extends RefCounted

const SymbolIndex = preload("res://addons/code_generator/analysis/symbol_index.gd")
const SourceScanner = preload("res://addons/code_generator/analysis/source_scanner.gd")

const FUNCTION_KEYWORD: String = "func"
const CONSTANT_KEYWORD: String = "const"
const SETTER_NAME: String = "set"
const GETTER_NAME: String = "get"
const INTEGER_TYPE_NAME: String = "int"
const RANGE_CALL: String = "range("

static var _modifiers_pattern := RegEx.create_from_string("^(?:(?:@\\w+(?:\\([^)]*\\))?|static)\\s+)+")
static var _class_name_pattern := RegEx.create_from_string("^class_name\\s+(\\w+)")
static var _extends_pattern := RegEx.create_from_string("\\bextends\\b\\s*([\\w\\.]*)")
static var _class_pattern := RegEx.create_from_string("^class\\s+(\\w+)")
static var _signal_pattern := RegEx.create_from_string("^signal\\s+(\\w+)\\s*(?:\\((.*)\\))?")
static var _variable_pattern := RegEx.create_from_string("^(var|const)\\s+(\\w+)(.*)$")
static var _block_pattern := RegEx.create_from_string("^(if|elif|else|for|while|match)\\b")
static var _for_pattern := RegEx.create_from_string("^for\\s+(\\w+)\\s*(?::\\s*(.+?))?\\s+in\\s+(.+):$")
static var _setter_pattern := RegEx.create_from_string("^set\\s*\\(\\s*(\\w+)\\s*\\)\\s*:")
static var _getter_pattern := RegEx.create_from_string("^get\\s*(?:\\(\\s*\\))?\\s*:")
static var _static_function_pattern := RegEx.create_from_string("\\bstatic\\s+func\\b")


class FunctionHeader:
	var name: String = ""
	var params_text: String = ""
	var return_text: String = ""


static func build(lines: PackedStringArray) -> SymbolIndex.SymbolIndexData:
	var root := SymbolIndex.ClassScope.new()
	root.body_start_line = 0
	root.end_line = maxi(0, lines.size() - 1)
	var data := SymbolIndex.SymbolIndexData.new()
	data.root = root
	data.statements = SourceScanner.new().scan(lines)
	_add_class_members(root, data.statements)
	return data


static func _add_class_members(class_scope: SymbolIndex.ClassScope, statements: Array[SourceScanner.Statement]) -> void:
	for statement in statements:
		var code := _strip_modifiers(statement.code)
		var class_name_match := _class_name_pattern.search(code)
		if class_name_match != null:
			class_scope.name = class_name_match.get_string(1)
			_read_extends(class_scope, statement, code)
		elif code.begins_with("extends"):
			_read_extends(class_scope, statement, code)
		elif _class_pattern.search(code) != null:
			_add_inner_class(class_scope, statement, code)
		elif _is_function_declaration(code):
			_add_method(class_scope, statement, code)
		elif _signal_pattern.search(code) != null:
			_add_signal(class_scope, code)
		elif _variable_pattern.search(code) != null:
			_add_member_variable(class_scope, statement, code)
		else:
			_add_lambdas(class_scope, statement, null)


static func _read_extends(class_scope: SymbolIndex.ClassScope, statement: SourceScanner.Statement, code: String) -> void:
	var extends_match := _extends_pattern.search(code)
	if extends_match == null:
		return
	class_scope.extends_line = statement.first_line
	if not extends_match.get_string(1).is_empty():
		class_scope.inherit_type = SymbolIndex.parse_type(extends_match.get_string(1))


static func _add_inner_class(parent: SymbolIndex.ClassScope, statement: SourceScanner.Statement, code: String) -> void:
	var inner := SymbolIndex.ClassScope.new()
	inner.name = _class_pattern.search(code).get_string(1)
	inner.start_line = statement.first_line
	inner.end_line = statement.last_line
	inner.attach_to(parent)
	parent.inner_classes[inner.name] = inner
	_read_extends(inner, statement, code)
	var body := _own_block(statement, false)
	if body != null:
		inner.body_start_line = body.header_line + 1
		inner.body_indent_text = body.indent_text
		_add_class_members(inner, body.statements)


static func _add_method(class_scope: SymbolIndex.ClassScope, statement: SourceScanner.Statement, code: String) -> void:
	var body := _own_block(statement, true)
	var method := _create_function_scope(code, false, statement.first_line, statement.last_line, body)
	method.is_static = _static_function_pattern.search(statement.code) != null
	method.attach_to(class_scope)
	if not method.name.is_empty():
		if not class_scope.methods.has(method.name):
			class_scope.methods[method.name] = []
		class_scope.methods[method.name].append(method)
	if body != null:
		_add_body_statements(method, body.statements)
	_add_lambdas(method, statement, body)


static func _add_signal(class_scope: SymbolIndex.ClassScope, code: String) -> void:
	var signal_match := _signal_pattern.search(code)
	var symbol := SymbolIndex.SignalSymbol.new()
	symbol.name = signal_match.get_string(1)
	symbol.params = SymbolIndex.parse_func_parameters(signal_match.get_string(2))
	class_scope.signals[symbol.name] = symbol


static func _add_member_variable(class_scope: SymbolIndex.ClassScope, statement: SourceScanner.Statement, code: String) -> void:
	var accessors := _own_block(statement, false)
	var variable := _parse_variable(code, statement, accessors != null)
	class_scope.vars[variable.name] = variable
	if accessors != null:
		_add_property(class_scope, statement, accessors, variable)
	_add_lambdas(class_scope, statement, accessors)


static func _add_property(class_scope: SymbolIndex.ClassScope, statement: SourceScanner.Statement, accessors: SourceScanner.Block, variable: SymbolIndex.VariableSymbol) -> void:
	var property := _create_block_scope(SymbolIndex.BlockScope.Kind.PROPERTY, statement, accessors)
	property.attach_to(class_scope)
	for accessor in accessors.statements:
		var setter_match := _setter_pattern.search(accessor.code)
		if setter_match == null and _getter_pattern.search(accessor.code) == null:
			continue
		var function := SymbolIndex.FunctionScope.new()
		function.name = GETTER_NAME if setter_match == null else SETTER_NAME
		if setter_match != null:
			function.params[setter_match.get_string(1)] = variable.type
		function.start_line = accessor.first_line
		function.end_line = accessor.last_line
		function.attach_to(property)
		var body := _own_block(accessor, false)
		if body != null:
			function.body_start_line = body.header_line + 1
			function.body_indent_text = body.indent_text
			_add_body_statements(function, body.statements)
		_add_lambdas(function, accessor, body)


static func _add_body_statements(scope: SymbolIndex.ScopeBase, statements: Array[SourceScanner.Statement]) -> void:
	for statement in statements:
		var code := _strip_modifiers(statement.code)
		var body := _own_block(statement, false)
		if _variable_pattern.search(code) != null:
			scope.locals.append(_parse_variable(code, statement, false))
		if body != null:
			_add_block(scope, statement, body, code)
		_add_lambdas(scope, statement, body)


static func _add_block(scope: SymbolIndex.ScopeBase, statement: SourceScanner.Statement, body: SourceScanner.Block, code: String) -> void:
	var kind := _block_kind(code)
	var block_scope := _create_block_scope(kind, statement, body)
	block_scope.attach_to(scope)
	if kind == SymbolIndex.BlockScope.Kind.FOR:
		_add_loop_variable(block_scope, statement, code)
	if kind != SymbolIndex.BlockScope.Kind.MATCH:
		_add_body_statements(block_scope, body.statements)
		return
	for branch in body.statements:
		var branch_body := _own_block(branch, false)
		if branch_body != null:
			var branch_scope := _create_block_scope(SymbolIndex.BlockScope.Kind.MATCH_BRANCH, branch, branch_body)
			branch_scope.attach_to(block_scope)
			_add_body_statements(branch_scope, branch_body.statements)
		_add_lambdas(block_scope, branch, branch_body)


static func _add_loop_variable(block_scope: SymbolIndex.BlockScope, statement: SourceScanner.Statement, code: String) -> void:
	var for_match := _for_pattern.search(code)
	if for_match == null:
		return
	var variable := SymbolIndex.VariableSymbol.new()
	variable.name = for_match.get_string(1)
	variable.start_line = statement.first_line
	variable.end_line = statement.first_line
	if for_match.get_string(2).is_empty():
		variable.type = _infer_loop_variable_type(for_match.get_string(3))
	else:
		variable.type = SymbolIndex.parse_type(for_match.get_string(2))
	block_scope.locals.append(variable)


static func _infer_loop_variable_type(iterable: String) -> SymbolIndex.TypeData:
	var text := iterable.strip_edges()
	if text.begins_with(RANGE_CALL) or text.is_valid_int():
		return SymbolIndex.parse_type(INTEGER_TYPE_NAME)
	return null


static func _add_lambdas(scope: SymbolIndex.ScopeBase, statement: SourceScanner.Statement, own_block: SourceScanner.Block) -> void:
	for block in statement.blocks:
		if block == own_block or not block.opened_by_function:
			continue
		var lambda := _create_function_scope(block.header_code, true, block.header_line, block.last_line, block)
		lambda.attach_to(scope)
		_add_body_statements(lambda, block.statements)


static func _create_function_scope(header_code: String, is_lambda: bool, start_line: int, end_line: int, body: SourceScanner.Block) -> SymbolIndex.FunctionScope:
	var header := _parse_function_header(header_code)
	var function := SymbolIndex.FunctionScope.new()
	function.name = header.name
	function.is_lambda = is_lambda
	function.params = SymbolIndex.parse_func_parameters(header.params_text)
	if not header.return_text.is_empty():
		function.return_type = SymbolIndex.parse_type(header.return_text)
	function.start_line = start_line
	function.end_line = end_line
	if body != null:
		function.body_start_line = body.header_line + 1
		function.body_indent_text = body.indent_text
	return function


static func _create_block_scope(kind: SymbolIndex.BlockScope.Kind, statement: SourceScanner.Statement, body: SourceScanner.Block) -> SymbolIndex.BlockScope:
	var scope := SymbolIndex.BlockScope.new()
	scope.kind = kind
	scope.start_line = statement.first_line
	scope.body_start_line = body.header_line + 1
	scope.end_line = body.last_line
	scope.body_indent_text = body.indent_text
	return scope


static func _parse_variable(code: String, statement: SourceScanner.Statement, has_accessors: bool) -> SymbolIndex.VariableSymbol:
	var variable_match := _variable_pattern.search(code)
	var tail := variable_match.get_string(3).strip_edges()
	if has_accessors:
		tail = tail.trim_suffix(SourceScanner.BLOCK_OPENER)
	var declaration := SymbolIndex.parse_declaration_tail(tail)
	var variable := SymbolIndex.VariableSymbol.new()
	variable.name = variable_match.get_string(2)
	variable.is_const = variable_match.get_string(1) == CONSTANT_KEYWORD
	variable.type = declaration.type
	variable.start_line = statement.first_line
	variable.end_line = statement.last_line
	return variable


static func _parse_function_header(code: String) -> FunctionHeader:
	var header := FunctionHeader.new()
	var index := SourceScanner.skip_spaces(code, FUNCTION_KEYWORD.length())
	var name_start := index
	while index < code.length() and SourceScanner.is_identifier_character(code[index]):
		index += 1
	header.name = code.substr(name_start, index - name_start)
	index = SourceScanner.skip_spaces(code, index)
	if index >= code.length() or code[index] != "(":
		return header
	var close := SourceScanner.find_matching_bracket(code, index)
	if close == -1:
		return header
	header.params_text = code.substr(index + 1, close - index - 1)
	var rest := code.substr(close + 1).strip_edges()
	if rest.begins_with("->"):
		var colon := rest.find(SourceScanner.BLOCK_OPENER)
		var return_end := rest.length() if colon == -1 else colon
		header.return_text = rest.substr(2, return_end - 2).strip_edges()
	return header


static func _block_kind(code: String) -> SymbolIndex.BlockScope.Kind:
	var block_match := _block_pattern.search(code)
	if block_match == null:
		return SymbolIndex.BlockScope.Kind.OTHER
	match block_match.get_string(1):
		"if":
			return SymbolIndex.BlockScope.Kind.IF
		"elif":
			return SymbolIndex.BlockScope.Kind.ELIF
		"else":
			return SymbolIndex.BlockScope.Kind.ELSE
		"for":
			return SymbolIndex.BlockScope.Kind.FOR
		"while":
			return SymbolIndex.BlockScope.Kind.WHILE
	return SymbolIndex.BlockScope.Kind.MATCH


static func _own_block(statement: SourceScanner.Statement, opened_by_function: bool) -> SourceScanner.Block:
	if statement.blocks.is_empty():
		return null
	var last: SourceScanner.Block = statement.blocks.back()
	return last if last.opened_by_function == opened_by_function else null


static func _is_function_declaration(code: String) -> bool:
	if not code.begins_with(FUNCTION_KEYWORD):
		return false
	return code.length() == FUNCTION_KEYWORD.length() or not SourceScanner.is_identifier_character(code[FUNCTION_KEYWORD.length()])


static func _strip_modifiers(code: String) -> String:
	return _modifiers_pattern.sub(code, "")
