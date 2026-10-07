@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExTypeResolver = preload("res://addons/gdscript_extreme_tool/analysis/type_resolver.gd")
const GDSExBuiltinTypes = preload("res://addons/gdscript_extreme_tool/analysis/builtin_types.gd")
const GDSExVariableUsage = preload("res://addons/gdscript_extreme_tool/analysis/variable_usage.gd")
const GDSExBracketGroups = preload("res://addons/gdscript_extreme_tool/analysis/bracket_groups.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")

const NULL_LITERAL: String = "null"
const MEMBER_ACCESS: String = "."
const CALL_OPENER: String = "("
const PLACEHOLDER_OPENER: String = "<"
const COMPOUND_VALUE_TEMPLATE: String = "%s %s (%s)"

static var _enum_value_pattern := RegEx.create_from_string("^(?:(\\w+)\\.)?(\\w+)$")
static var _identifier_pattern := RegEx.create_from_string("(?:(\\.)\\s*|(?<![\\w.]))([A-Za-z_]\\w*)")
static var _written_member_pattern := RegEx.create_from_string("\\.\\s*(\\w+)$")

var _index: GDSExSymbolIndex.GDSExSymbolIndexData
var _untyped: Dictionary[GDSExSymbolIndex.GDSExVariableSymbol, GDSExTypedVariable] = {}
var _untyped_members: Dictionary[String, Array] = {}
var _untyped_function_names: Dictionary[String, bool] = {}


class GDSExValueType:
	var text: String = ""
	var is_object: bool = false


class GDSExTypedVariable:
	var symbol: GDSExSymbolIndex.GDSExVariableSymbol
	var type: GDSExValueType
	var sources: Array[GDSExSymbolIndex.GDSExVariableSymbol] = []
	var is_rejected: bool = false


static func find(index: GDSExSymbolIndex.GDSExSymbolIndexData) -> Array[GDSExTypedVariable]:
	return new()._find(index)


func _find(index: GDSExSymbolIndex.GDSExSymbolIndexData) -> Array[GDSExTypedVariable]:
	_index = index
	var symbols := GDSExSymbolIndex.find_variables(index.root)
	var variables: Array[GDSExTypedVariable] = []
	for symbol in symbols:
		var variable := _read_variable(symbol)
		if variable == null:
			continue
		variables.append(variable)
		if symbol.is_untyped:
			_untyped[symbol] = variable
	if not _untyped.is_empty():
		_collect_untyped_members(index.root)
		for symbol in _untyped:
			_untyped[symbol].is_rejected = not _add_sources(_untyped[symbol], symbol.declaration.value, _scope_info(symbol.start_line))
		_check_writes(index.statements)
		_reject_guessed(symbols)
	var accepted: Array[GDSExTypedVariable] = []
	for variable in variables:
		if not variable.is_rejected:
			accepted.append(variable)
	return accepted


func _read_variable(symbol: GDSExSymbolIndex.GDSExVariableSymbol) -> GDSExTypedVariable:
	var declaration := symbol.declaration
	if declaration == null or symbol.is_const or declaration.has_type() or not declaration.has_value():
		return null
	var type := _value_type(declaration.value, _scope_info(symbol.start_line))
	if type == null:
		return null
	var variable := GDSExTypedVariable.new()
	variable.symbol = symbol
	variable.type = type
	return variable


func _scope_info(line: int) -> GDSExSymbolIndex.GDSExScopeInfo:
	return GDSExSymbolIndex.get_scope_info_for_line(_index, line)


func _collect_untyped_members(class_scope: GDSExSymbolIndex.GDSExClassScope) -> void:
	for member: GDSExSymbolIndex.GDSExVariableSymbol in class_scope.vars.values():
		if member.is_untyped:
			if not _untyped_members.has(member.name):
				_untyped_members[member.name] = []
			_untyped_members[member.name].append(member)
	for function_name: String in class_scope.functions:
		for function: GDSExSymbolIndex.GDSExFunctionScope in class_scope.functions[function_name]:
			if function.return_type == null:
				_untyped_function_names[function_name] = true
	for inner_name: String in class_scope.inner_classes:
		_collect_untyped_members(class_scope.inner_classes[inner_name])


func _check_writes(statements: Array[GDSExSourceScanner.GDSExStatement]) -> void:
	for statement in statements:
		_check_write(statement)
		for block in statement.blocks:
			_check_writes(block.statements)


func _check_write(statement: GDSExSourceScanner.GDSExStatement) -> void:
	var assignment := GDSExVariableUsage.parse_assignment(statement.code)
	if assignment == null or assignment.is_declaration:
		return
	var scope_info := _scope_info(statement.first_line)
	var target := statement.code.substr(assignment.statement_start, assignment.operator_start - assignment.statement_start).strip_edges()
	var value := statement.code.substr(assignment.value_start).strip_edges()
	if assignment.is_compound:
		var operator := statement.code.substr(assignment.operator_start, assignment.operator_end - assignment.operator_start - GDSExSymbolIndex.ASSIGNMENT.length())
		value = COMPOUND_VALUE_TEMPLATE % [target, operator, value]
	for symbol in _find_written_symbols(target, assignment, scope_info):
		var variable: GDSExTypedVariable = _untyped.get(symbol)
		if variable != null and not variable.is_rejected:
			variable.is_rejected = not _accepts(variable.type, value, scope_info) or not _add_sources(variable, value, scope_info)


func _find_written_symbols(target: String, assignment: GDSExVariableUsage.GDSExAssignment, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> Array[GDSExSymbolIndex.GDSExVariableSymbol]:
	var symbols: Array[GDSExSymbolIndex.GDSExVariableSymbol] = []
	var written_member := _written_member_pattern.search(target)
	if assignment.is_plain_target:
		var symbol := GDSExSymbolIndex.find_variable(assignment.root_name, scope_info).symbol
		if symbol != null:
			symbols.append(symbol)
	elif written_member != null:
		symbols.assign(_untyped_members.get(written_member.get_string(1), []))
	return symbols


func _accepts(type: GDSExValueType, value: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> bool:
	if value == NULL_LITERAL:
		return type.is_object
	var written := _value_type(value, scope_info)
	if written == null:
		return false
	if written.text == type.text:
		return true
	return ClassDB.class_exists(type.text) and ClassDB.class_exists(written.text) and ClassDB.is_parent_class(written.text, type.text)


func _add_sources(variable: GDSExTypedVariable, value: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> bool:
	for lambda_prefix in GDSExSymbolIndex.LAMBDA_PREFIXES:
		if value.begins_with(lambda_prefix):
			return true
	var groups := GDSExBracketGroups.find(value)
	for identifier in _identifier_pattern.search_all(value):
		if GDSExVariableUsage.is_inside_a_typed_group(value, groups, identifier.get_start(), 0):
			continue
		var identifier_name := identifier.get_string(2)
		var is_member := not identifier.get_string(1).is_empty()
		var next := GDSExSourceScanner.skip_spaces(value, identifier.get_end())
		if value.substr(next, CALL_OPENER.length()) == CALL_OPENER:
			if _untyped_function_names.has(identifier_name) or (is_member and _returns_any_value(identifier_name)):
				return false
		elif is_member:
			for member: GDSExSymbolIndex.GDSExVariableSymbol in _untyped_members.get(identifier_name, []):
				variable.sources.append(member)
		elif not _add_source(variable, identifier_name, scope_info):
			return false
	return true


func _returns_any_value(function_name: String) -> bool:
	if GDSExLanguage.CALLABLE_INVOCATIONS.has(function_name):
		return true
	var element_type: String = GDSExLanguage.ARRAY_RETURNS.get(function_name, GDSExLanguage.DICTIONARY_RETURNS.get(function_name, ""))
	return element_type.begins_with(PLACEHOLDER_OPENER)


func _add_source(variable: GDSExTypedVariable, identifier_name: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> bool:
	var lookup := GDSExSymbolIndex.find_variable(identifier_name, scope_info)
	if lookup.symbol != null:
		variable.sources.append(lookup.symbol)
		return true
	var function := lookup.scope as GDSExSymbolIndex.GDSExFunctionScope
	return function == null or not function.untyped_params.has(identifier_name)


func _reject_guessed(symbols: Array[GDSExSymbolIndex.GDSExVariableSymbol]) -> void:
	var guessed: Dictionary[GDSExSymbolIndex.GDSExVariableSymbol, bool] = {}
	var pending: Array[GDSExTypedVariable] = []
	for symbol in symbols:
		if _untyped.has(symbol):
			pending.append(_untyped[symbol])
			if _untyped[symbol].is_rejected:
				guessed[symbol] = true
		elif symbol.is_untyped:
			guessed[symbol] = true
		elif symbol.declaration == null and symbol.deferred != GDSExSymbolIndex.GDSExVariableSymbol.GDSExDeferred.NONE:
			var derived := GDSExTypedVariable.new()
			derived.symbol = symbol
			pending.append(derived)
			if not _add_sources(derived, symbol.value_code, _scope_info(symbol.start_line)):
				guessed[symbol] = true
	var has_changed := true
	while has_changed:
		has_changed = false
		for variable in pending:
			if not guessed.has(variable.symbol) and _has_guessed_source(variable, guessed):
				guessed[variable.symbol] = true
				variable.is_rejected = true
				has_changed = true


func _has_guessed_source(variable: GDSExTypedVariable, guessed: Dictionary[GDSExSymbolIndex.GDSExVariableSymbol, bool]) -> bool:
	for source in variable.sources:
		if guessed.has(source):
			return true
	return false


func _value_type(value: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExValueType:
	if value.is_empty() or value == NULL_LITERAL:
		return null
	var type := GDSExValueType.new()
	type.text = _enum_type_text(value, scope_info)
	if not type.text.is_empty():
		return type
	var resolved := GDSExTypeResolver.resolve_expression(value, scope_info)
	if resolved.is_class_reference or resolved.is_preloaded or resolved.type == null:
		return null
	type.text = GDSExSymbolIndex.type_to_string(resolved.type)
	type.is_object = resolved.class_scope != null or ClassDB.class_exists(resolved.type.name)
	return null if type.text == GDSExLanguage.VARIANT_TYPE_NAME else type


func _enum_type_text(value: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> String:
	var enum_value := _enum_value_pattern.search(value)
	if enum_value == null:
		return ""
	var owner_name := enum_value.get_string(1)
	var constant_name := enum_value.get_string(2)
	if owner_name.is_empty():
		return GDSExBuiltinTypes.GLOBAL_CONSTANTS.get(constant_name, "")
	if _declares_enum(scope_info.class_scope, owner_name):
		return owner_name
	var builtin_type: String = GDSExBuiltinTypes.CONSTANTS.get(owner_name, {}).get(constant_name, "")
	if builtin_type.contains(MEMBER_ACCESS):
		return builtin_type
	if not ClassDB.class_exists(owner_name) or not ClassDB.class_has_integer_constant(owner_name, constant_name):
		return ""
	var enum_name := ClassDB.class_get_integer_constant_enum(owner_name, constant_name)
	var declaring_class := owner_name
	while not enum_name.is_empty() and not declaring_class.is_empty() and not ClassDB.class_has_enum(declaring_class, enum_name, true):
		declaring_class = ClassDB.get_parent_class(declaring_class)
	return "" if enum_name.is_empty() or declaring_class.is_empty() else declaring_class + MEMBER_ACCESS + enum_name


func _declares_enum(class_scope: GDSExSymbolIndex.GDSExClassScope, enum_name: String) -> bool:
	var current: GDSExSymbolIndex.GDSExScopeBase = class_scope
	while current != null:
		if current is GDSExSymbolIndex.GDSExClassScope:
			for member in (current as GDSExSymbolIndex.GDSExClassScope).members:
				if member.kind == GDSExSymbolIndex.GDSExClassMember.GDSExKind.ENUM and member.name == enum_name:
					return true
		current = current.parent
	return false
