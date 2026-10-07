@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")

const FUNCTION_KEYWORD: String = "func"
const CONSTANT_KEYWORD: String = "const"
const SETTER_NAME: String = "set"
const GETTER_NAME: String = "get"
const RANGE_CALL: String = "range("
const RETURN_ARROW: String = "->"
const PATTERN_GUARD: String = " when "

static var _modifiers_pattern := RegEx.create_from_string("^(?:(?:@\\w+(?:\\([^)]*\\))?|static)\\s+)+")
static var _class_name_pattern := RegEx.create_from_string("^class_name\\s+(\\w+)")
static var _extends_pattern := RegEx.create_from_string("\\bextends\\b\\s*([\\w\\.]*)")
static var _class_pattern := RegEx.create_from_string("^class\\s+(\\w+)")
static var _signal_pattern := RegEx.create_from_string("^signal\\s+(\\w+)\\s*(?:\\((.*)\\))?")
static var _variable_pattern := RegEx.create_from_string("^(var|const)\\s+(\\w+)(.*)$")
static var _block_pattern := RegEx.create_from_string("^(if|elif|else|for|while|match)\\b")
static var _for_pattern := RegEx.create_from_string("^for\\s+(\\w+)\\s*(?::\\s*(.+?))?\\s+in\\s+(.+):$")
static var _match_pattern := RegEx.create_from_string("^match\\s+(.*):$")
static var _binding_pattern := RegEx.create_from_string("\\bvar\\s+(\\w+)")
static var _return_pattern := RegEx.create_from_string("^return\\b(.*)$")
static var _setter_pattern := RegEx.create_from_string("^set\\s*\\(\\s*(\\w+)\\s*\\)\\s*:")
static var _getter_pattern := RegEx.create_from_string("^get\\s*(?:\\(\\s*\\))?\\s*:")
static var _static_function_pattern := RegEx.create_from_string("\\bstatic\\s+func\\b")
static var _script_preload_pattern := RegEx.create_from_string("=\\s*preload\\(\\s*[\"'][^\"']*\\.gd[\"']\\s*\\)")
static var _enum_pattern := RegEx.create_from_string("^enum\\b\\s*(\\w*)\\s*\\{(.*)\\}")
static var _annotation_pattern := RegEx.create_from_string("^@\\w+")
static var _extends_path_pattern := RegEx.create_from_string("\\bextends\\s+[\"']([^\"']+)[\"']")


class GDSExFunctionHeader:
	var name: String = ""
	var params_text: String = ""
	var return_text: String = ""
	var body_offset: int = -1


static func build(lines: PackedStringArray) -> GDSExSymbolIndex.GDSExSymbolIndexData:
	var root := GDSExSymbolIndex.GDSExClassScope.new()
	root.body_start_line = 0
	root.end_line = maxi(0, lines.size() - 1)
	var data := GDSExSymbolIndex.GDSExSymbolIndexData.new()
	data.root = root
	data.statements = GDSExSourceScanner.new().scan(lines)
	_add_class_members(root, data.statements, lines)
	return data


static func _add_class_members(class_scope: GDSExSymbolIndex.GDSExClassScope, statements: Array[GDSExSourceScanner.GDSExStatement], lines: PackedStringArray) -> void:
	var is_in_header := true
	for statement in statements:
		var code := _strip_modifiers(statement.code)
		var class_name_match := _class_name_pattern.search(code)
		var is_header_statement := true
		if class_name_match != null:
			class_scope.name = class_name_match.get_string(1)
			_read_extends(class_scope, statement, code, lines)
		elif code.begins_with("extends"):
			_read_extends(class_scope, statement, code, lines)
		elif _is_header_annotation(code):
			pass
		else:
			is_header_statement = false
			_add_class_member(class_scope, statement, code, lines)
		is_in_header = is_in_header and is_header_statement
		if is_in_header:
			class_scope.header_end_line = statement.last_line


static func _add_class_member(class_scope: GDSExSymbolIndex.GDSExClassScope, statement: GDSExSourceScanner.GDSExStatement, code: String, lines: PackedStringArray) -> void:
	var member := GDSExSymbolIndex.GDSExClassMember.new()
	member.modifiers = statement.code.substr(0, statement.code.length() - code.length())
	member.start_line = statement.first_line
	member.end_line = statement.last_line
	class_scope.members.append(member)
	var annotation_match := _annotation_pattern.search(code)
	if _class_pattern.search(code) != null:
		_add_inner_class(class_scope, statement, code, lines)
		member.kind = GDSExSymbolIndex.GDSExClassMember.GDSExKind.CLASS
		member.name = _class_pattern.search(code).get_string(1)
	elif _starts_with_function(code):
		_add_function(class_scope, statement, code)
		member.kind = GDSExSymbolIndex.GDSExClassMember.GDSExKind.FUNCTION
		member.name = _parse_function_header(code).name
	elif _signal_pattern.search(code) != null:
		_add_signal(class_scope, code)
		member.kind = GDSExSymbolIndex.GDSExClassMember.GDSExKind.SIGNAL
		member.name = _signal_pattern.search(code).get_string(1)
	elif _enum_pattern.search(code) != null:
		_add_enum(class_scope, statement, code)
		member.kind = GDSExSymbolIndex.GDSExClassMember.GDSExKind.ENUM
		member.name = _enum_pattern.search(code).get_string(1)
	elif _variable_pattern.search(code) != null:
		var variable := _add_member_variable(class_scope, statement, code)
		variable.is_script_alias = variable.is_const and _script_preload_pattern.search(lines[statement.first_line]) != null
		member.kind = GDSExSymbolIndex.GDSExClassMember.GDSExKind.CONSTANT if variable.is_const else GDSExSymbolIndex.GDSExClassMember.GDSExKind.VARIABLE
		member.name = variable.name
	else:
		member.kind = GDSExSymbolIndex.GDSExClassMember.GDSExKind.OTHER if annotation_match == null else GDSExSymbolIndex.GDSExClassMember.GDSExKind.ANNOTATION
		member.name = "" if annotation_match == null else annotation_match.get_string(0)
		_add_lambdas(class_scope, statement, null)


static func _is_header_annotation(code: String) -> bool:
	var annotation_match := _annotation_pattern.search(code)
	return annotation_match != null and GDSExLanguage.HEADER_ANNOTATIONS.has(annotation_match.get_string(0))


static func _add_enum(class_scope: GDSExSymbolIndex.GDSExClassScope, statement: GDSExSourceScanner.GDSExStatement, code: String) -> void:
	var enum_match := _enum_pattern.search(code)
	var names := PackedStringArray([enum_match.get_string(1)])
	if names[0].is_empty():
		names.clear()
		for value in GDSExSymbolIndex.split_top_level(enum_match.get_string(2), GDSExSymbolIndex.TYPE_SEPARATOR):
			names.append(value.get_slice(GDSExSymbolIndex.ASSIGNMENT, 0).strip_edges())
	for constant_name in names:
		var constant := GDSExSymbolIndex.GDSExVariableSymbol.new()
		constant.name = constant_name
		constant.is_const = true
		constant.start_line = statement.first_line
		constant.end_line = statement.last_line
		if enum_match.get_string(1).is_empty():
			constant.type = GDSExSymbolIndex.make_type(GDSExLanguage.INTEGER_TYPE_NAME)
		class_scope.vars[constant_name] = constant


static func _read_extends(class_scope: GDSExSymbolIndex.GDSExClassScope, statement: GDSExSourceScanner.GDSExStatement, code: String, lines: PackedStringArray) -> void:
	var extends_match := _extends_pattern.search(code)
	if extends_match == null:
		return
	class_scope.extends_line = statement.first_line
	if not extends_match.get_string(1).is_empty():
		class_scope.inherit_type = GDSExSymbolIndex.parse_type(extends_match.get_string(1))
		return
	var path_match := _extends_path_pattern.search(lines[statement.first_line])
	if path_match != null:
		class_scope.base_script_path = path_match.get_string(1)


static func _add_inner_class(parent: GDSExSymbolIndex.GDSExClassScope, statement: GDSExSourceScanner.GDSExStatement, code: String, lines: PackedStringArray) -> void:
	var inner := GDSExSymbolIndex.GDSExClassScope.new()
	inner.name = _class_pattern.search(code).get_string(1)
	inner.start_line = statement.first_line
	inner.end_line = statement.last_line
	inner.header_end_line = statement.first_line
	inner.attach_to(parent)
	parent.inner_classes[inner.name] = inner
	_read_extends(inner, statement, code, lines)
	var body := _own_block(statement, false)
	if body != null:
		inner.header_end_line = body.header_line
		inner.body_start_line = body.header_line + 1
		inner.body_indent_text = body.indent_text
		_add_class_members(inner, body.statements, lines)


static func _add_function(class_scope: GDSExSymbolIndex.GDSExClassScope, statement: GDSExSourceScanner.GDSExStatement, code: String) -> void:
	var body := _own_block(statement, true)
	var function := _create_function_scope(code, false, statement.first_line, statement.last_line, body)
	function.is_static = _static_function_pattern.search(statement.code) != null
	function.attach_to(class_scope)
	if not function.name.is_empty():
		if not class_scope.functions.has(function.name):
			class_scope.functions[function.name] = []
		class_scope.functions[function.name].append(function)
	if body == null:
		_record_inline_return(function, code, statement.first_line)
	else:
		_add_body_statements(function, body.statements)
	_add_lambdas(function, statement, body)


static func _add_signal(class_scope: GDSExSymbolIndex.GDSExClassScope, code: String) -> void:
	var signal_match := _signal_pattern.search(code)
	var symbol := GDSExSymbolIndex.GDSExSignalSymbol.new()
	symbol.name = signal_match.get_string(1)
	symbol.params = GDSExSymbolIndex.parse_func_parameters(signal_match.get_string(2))
	class_scope.signals[symbol.name] = symbol


static func _add_member_variable(class_scope: GDSExSymbolIndex.GDSExClassScope, statement: GDSExSourceScanner.GDSExStatement, code: String) -> GDSExSymbolIndex.GDSExVariableSymbol:
	var accessors := _own_block(statement, false)
	var variable := _parse_variable(code, statement)
	class_scope.vars[variable.name] = variable
	if accessors != null:
		_add_property(class_scope, statement, accessors, variable)
	_link_function(variable, _add_lambdas(class_scope, statement, accessors), class_scope, statement)
	return variable


static func _add_property(class_scope: GDSExSymbolIndex.GDSExClassScope, statement: GDSExSourceScanner.GDSExStatement, accessors: GDSExSourceScanner.GDSExBlock, variable: GDSExSymbolIndex.GDSExVariableSymbol) -> void:
	var property := _create_block_scope(GDSExSymbolIndex.GDSExBlockScope.GDSExKind.PROPERTY, statement, accessors)
	property.attach_to(class_scope)
	for accessor in accessors.statements:
		var setter_match := _setter_pattern.search(accessor.code)
		if setter_match == null and _getter_pattern.search(accessor.code) == null:
			continue
		var function := GDSExSymbolIndex.GDSExFunctionScope.new()
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


static func _add_body_statements(scope: GDSExSymbolIndex.GDSExScopeBase, statements: Array[GDSExSourceScanner.GDSExStatement]) -> void:
	for statement in statements:
		var code := _strip_modifiers(statement.code)
		var body := _own_block(statement, false)
		var variable: GDSExSymbolIndex.GDSExVariableSymbol = null
		if _variable_pattern.search(code) != null:
			variable = _parse_variable(code, statement)
			scope.locals.append(variable)
		else:
			_record_return(scope, code, statement.first_line)
		if body != null:
			_add_block(scope, statement, body, code)
		var lambdas := _add_lambdas(scope, statement, body)
		if variable != null:
			_link_function(variable, lambdas, scope, statement)


static func _add_block(scope: GDSExSymbolIndex.GDSExScopeBase, statement: GDSExSourceScanner.GDSExStatement, body: GDSExSourceScanner.GDSExBlock, code: String) -> void:
	var kind := _block_kind(code)
	var block_scope := _create_block_scope(kind, statement, body)
	block_scope.attach_to(scope)
	if kind == GDSExSymbolIndex.GDSExBlockScope.GDSExKind.FOR:
		_add_loop_variable(block_scope, statement, code)
	if kind != GDSExSymbolIndex.GDSExBlockScope.GDSExKind.MATCH:
		_add_body_statements(block_scope, body.statements)
		return
	var subject_match := _match_pattern.search(code)
	var subject := "" if subject_match == null else subject_match.get_string(1).strip_edges()
	for branch in body.statements:
		var branch_body := _own_block(branch, false)
		if branch_body != null:
			var branch_scope := _create_block_scope(GDSExSymbolIndex.GDSExBlockScope.GDSExKind.MATCH_BRANCH, branch, branch_body)
			branch_scope.attach_to(block_scope)
			_add_pattern_bindings(branch_scope, branch, subject)
			_add_body_statements(branch_scope, branch_body.statements)
		_add_lambdas(block_scope, branch, branch_body)


static func _add_pattern_bindings(branch_scope: GDSExSymbolIndex.GDSExBlockScope, branch: GDSExSourceScanner.GDSExStatement, subject: String) -> void:
	var pattern := branch.code.trim_suffix(GDSExSourceScanner.BLOCK_OPENER).strip_edges()
	var guard := pattern.find(PATTERN_GUARD)
	if guard != -1:
		pattern = pattern.substr(0, guard).strip_edges()
	for binding in _binding_pattern.search_all(pattern):
		var variable := GDSExSymbolIndex.GDSExVariableSymbol.new()
		variable.name = binding.get_string(1)
		variable.start_line = branch.first_line
		variable.end_line = branch.first_line
		if binding.get_string(0) == pattern and not subject.is_empty():
			variable.value_code = subject
			variable.deferred = GDSExSymbolIndex.GDSExVariableSymbol.GDSExDeferred.VALUE
		branch_scope.locals.append(variable)


static func _add_loop_variable(block_scope: GDSExSymbolIndex.GDSExBlockScope, statement: GDSExSourceScanner.GDSExStatement, code: String) -> void:
	var for_match := _for_pattern.search(code)
	if for_match == null:
		return
	var iterable := for_match.get_string(3).strip_edges()
	var variable := GDSExSymbolIndex.GDSExVariableSymbol.new()
	variable.name = for_match.get_string(1)
	variable.start_line = statement.first_line
	variable.end_line = statement.first_line
	variable.value_code = iterable
	if not for_match.get_string(2).is_empty():
		variable.type = GDSExSymbolIndex.parse_type(for_match.get_string(2))
	elif iterable.begins_with(RANGE_CALL) or iterable.is_valid_int():
		variable.type = GDSExSymbolIndex.make_type(GDSExLanguage.INTEGER_TYPE_NAME)
	else:
		variable.deferred = GDSExSymbolIndex.GDSExVariableSymbol.GDSExDeferred.ITERATION
	block_scope.locals.append(variable)


static func _add_lambdas(scope: GDSExSymbolIndex.GDSExScopeBase, statement: GDSExSourceScanner.GDSExStatement, own_block: GDSExSourceScanner.GDSExBlock) -> Array[GDSExSymbolIndex.GDSExFunctionScope]:
	var lambdas: Array[GDSExSymbolIndex.GDSExFunctionScope] = []
	for block in statement.blocks:
		if block == own_block or not block.opened_by_function:
			continue
		var lambda := _create_function_scope(block.header_code, true, block.header_line, block.last_line, block)
		lambda.attach_to(scope)
		_add_body_statements(lambda, block.statements)
		lambdas.append(lambda)
	return lambdas


static func _link_function(variable: GDSExSymbolIndex.GDSExVariableSymbol, lambdas: Array[GDSExSymbolIndex.GDSExFunctionScope], scope: GDSExSymbolIndex.GDSExScopeBase, statement: GDSExSourceScanner.GDSExStatement) -> void:
	if not _starts_with_function(variable.value_code):
		return
	if not lambdas.is_empty():
		variable.function = lambdas[0]
		return
	var inline_function := _create_function_scope(variable.value_code, true, statement.first_line, statement.first_line, null)
	inline_function.is_inline = true
	inline_function.enclose_in(scope)
	_record_inline_return(inline_function, variable.value_code, statement.first_line)
	variable.function = inline_function


static func _create_function_scope(header_code: String, is_lambda: bool, start_line: int, end_line: int, body: GDSExSourceScanner.GDSExBlock) -> GDSExSymbolIndex.GDSExFunctionScope:
	var header := _parse_function_header(header_code)
	var function := GDSExSymbolIndex.GDSExFunctionScope.new()
	function.name = header.name
	function.is_lambda = is_lambda
	function.params = GDSExSymbolIndex.parse_func_parameters(header.params_text)
	function.untyped_params = GDSExSymbolIndex.find_untyped_parameters(header.params_text)
	if not header.return_text.is_empty():
		function.return_type = GDSExSymbolIndex.parse_type(header.return_text)
	function.start_line = start_line
	function.end_line = end_line
	if body != null:
		function.body_start_line = body.header_line + 1
		function.body_indent_text = body.indent_text
	return function


static func _create_block_scope(kind: GDSExSymbolIndex.GDSExBlockScope.GDSExKind, statement: GDSExSourceScanner.GDSExStatement, body: GDSExSourceScanner.GDSExBlock) -> GDSExSymbolIndex.GDSExBlockScope:
	var scope := GDSExSymbolIndex.GDSExBlockScope.new()
	scope.kind = kind
	scope.start_line = statement.first_line
	scope.body_start_line = body.header_line + 1
	scope.end_line = body.last_line
	scope.body_indent_text = body.indent_text
	return scope


static func _parse_variable(code: String, statement: GDSExSourceScanner.GDSExStatement) -> GDSExSymbolIndex.GDSExVariableSymbol:
	var variable_match := _variable_pattern.search(code)
	var declaration := GDSExSymbolIndex.parse_declaration_tail(statement.code, statement.code.length() - code.length() + variable_match.get_start(3))
	var variable := GDSExSymbolIndex.GDSExVariableSymbol.new()
	variable.name = variable_match.get_string(2)
	variable.is_const = variable_match.get_string(1) == CONSTANT_KEYWORD
	variable.is_untyped = not variable.is_const and not declaration.is_inferred and not declaration.has_type()
	variable.declaration = declaration
	variable.statement = statement
	variable.type = declaration.type
	variable.value_code = declaration.value
	if declaration.type == null and not declaration.value.is_empty():
		variable.deferred = GDSExSymbolIndex.GDSExVariableSymbol.GDSExDeferred.VALUE
	variable.start_line = statement.first_line
	variable.end_line = statement.last_line
	return variable


static func _parse_function_header(code: String) -> GDSExFunctionHeader:
	var header := GDSExFunctionHeader.new()
	var index := GDSExSourceScanner.skip_spaces(code, FUNCTION_KEYWORD.length())
	var name_start := index
	while index < code.length() and GDSExSourceScanner.is_identifier_character(code[index]):
		index += 1
	header.name = code.substr(name_start, index - name_start)
	index = GDSExSourceScanner.skip_spaces(code, index)
	if index >= code.length() or code[index] != "(":
		return header
	var close := GDSExSourceScanner.find_matching_bracket(code, index)
	if close == -1:
		return header
	header.params_text = code.substr(index + 1, close - index - 1)
	var colon := code.find(GDSExSourceScanner.BLOCK_OPENER, close + 1)
	var header_end := code.length() if colon == -1 else colon
	var return_part := code.substr(close + 1, header_end - close - 1).strip_edges()
	if return_part.begins_with(RETURN_ARROW):
		header.return_text = return_part.substr(RETURN_ARROW.length()).strip_edges()
	if colon != -1:
		header.body_offset = colon + 1
	return header


static func _record_return(scope: GDSExSymbolIndex.GDSExScopeBase, code: String, line: int) -> void:
	var return_match := _return_pattern.search(code)
	if return_match == null:
		return
	var current := scope
	while current != null and not current is GDSExSymbolIndex.GDSExFunctionScope:
		current = current.parent
	if current != null:
		var function := current as GDSExSymbolIndex.GDSExFunctionScope
		function.return_codes.append(return_match.get_string(1).strip_edges())
		function.return_lines.append(line)


static func _record_inline_return(function: GDSExSymbolIndex.GDSExFunctionScope, code: String, line: int) -> void:
	var header := _parse_function_header(code)
	if header.body_offset == -1:
		return
	var return_match := _return_pattern.search(code.substr(header.body_offset).strip_edges())
	if return_match != null:
		function.return_codes.append(return_match.get_string(1).strip_edges())
		function.return_lines.append(line)


static func _block_kind(code: String) -> GDSExSymbolIndex.GDSExBlockScope.GDSExKind:
	var block_match := _block_pattern.search(code)
	if block_match == null:
		return GDSExSymbolIndex.GDSExBlockScope.GDSExKind.OTHER
	match block_match.get_string(1):
		"if":
			return GDSExSymbolIndex.GDSExBlockScope.GDSExKind.IF
		"elif":
			return GDSExSymbolIndex.GDSExBlockScope.GDSExKind.ELIF
		"else":
			return GDSExSymbolIndex.GDSExBlockScope.GDSExKind.ELSE
		"for":
			return GDSExSymbolIndex.GDSExBlockScope.GDSExKind.FOR
		"while":
			return GDSExSymbolIndex.GDSExBlockScope.GDSExKind.WHILE
	return GDSExSymbolIndex.GDSExBlockScope.GDSExKind.MATCH


static func _own_block(statement: GDSExSourceScanner.GDSExStatement, opened_by_function: bool) -> GDSExSourceScanner.GDSExBlock:
	if statement.blocks.is_empty():
		return null
	var last: GDSExSourceScanner.GDSExBlock = statement.blocks.back()
	return last if last.opened_by_function == opened_by_function else null


static func _starts_with_function(code: String) -> bool:
	if not code.begins_with(FUNCTION_KEYWORD):
		return false
	return code.length() == FUNCTION_KEYWORD.length() or not GDSExSourceScanner.is_identifier_character(code[FUNCTION_KEYWORD.length()])


static func _strip_modifiers(code: String) -> String:
	return _modifiers_pattern.sub(code, "")
