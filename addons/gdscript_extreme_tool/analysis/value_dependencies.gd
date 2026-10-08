@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExCallSiteParser = preload("res://addons/gdscript_extreme_tool/analysis/call_site_parser.gd")
const GDSExTypeResolver = preload("res://addons/gdscript_extreme_tool/analysis/type_resolver.gd")
const GDSExVariableUsage = preload("res://addons/gdscript_extreme_tool/analysis/variable_usage.gd")
const GDSExValueFinder = preload("res://addons/gdscript_extreme_tool/analysis/value_finder.gd")
const GDSExMemberCategories = preload("res://addons/gdscript_extreme_tool/analysis/member_categories.gd")
const GDSExScriptLibrary = preload("res://addons/gdscript_extreme_tool/analysis/script_library.gd")
const GDSExBuiltinTypes = preload("res://addons/gdscript_extreme_tool/analysis/builtin_types.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")

const MEMBER_ACCESS: String = "."
const CALL_OPENER: String = "("
const CALL_TEMPLATE: String = "%s()"
const MEMBER_CALL_TEMPLATE: String = "%s.%s()"
const PRELOAD_FUNCTION: String = "preload"
const PACKED_ARRAY_PREFIX: String = "Packed"
const TREE_FUNCTION: String = "get_node"
const ANNOTATION_PREFIX: String = "@"
const SIMPLE_RECEIVER_LENGTH: int = 24
const OPERATOR_WORDS: Array[String] = ["and", "or", "not", "in", "is", "as", "if", "else", "true", "false", "null"]

static var _identifier_pattern := RegEx.create_from_string("(?<![\\w.$%@])[A-Za-z_]\\w*")
static var _chain_pattern := RegEx.create_from_string("(?<![\\w.$%@)\\]}\"'])([A-Za-z_]\\w*)((?:\\s*\\.\\s*[A-Za-z_]\\w*)+)")
static var _await_pattern := RegEx.create_from_string("(?<![\\w.])await(?!\\w)")
static var _lambda_pattern := RegEx.create_from_string("(?<![\\w.])func(?!\\w)")
static var _simple_receiver_pattern := RegEx.create_from_string("^[A-Za-z_][\\w.]*$")


class GDSExDependencies:
	enum GDSExHome { NONE, LOOP, BLOCK, LAMBDA }

	var lambda_name: String = ""
	var block_name: String = ""
	var block_home: GDSExHome = GDSExHome.NONE
	var local_name: String = ""
	var member_name: String = ""
	var member_variables: PackedStringArray = []
	var inner_name: String = ""
	var needs_tree: bool = false
	var has_await: bool = false
	var blocker: String = ""
	var blocker_is_a_call: bool = false

	func is_constant() -> bool:
		return blocker.is_empty()

	func block(name: String, is_a_call: bool) -> void:
		if blocker.is_empty():
			blocker = name
			blocker_is_a_call = is_a_call


static func find(value: GDSExValueFinder.GDSExValue, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExDependencies:
	var found := GDSExDependencies.new()
	var local_names := _find_locals(found, value, scope_info)
	found.has_await = _await_pattern.search(value.code) != null
	found.needs_tree = _reads_the_tree(value)
	if found.needs_tree or found.has_await or _lambda_pattern.search(value.code) != null:
		found.block(value.code, false)
	_check_calls(found, value.code, scope_info)
	_check_names(found, value.code, scope_info, local_names)
	_check_chains(found, value.code, scope_info)
	return found


static func _find_locals(found: GDSExDependencies, value: GDSExValueFinder.GDSExValue, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> Dictionary[String, bool]:
	var read_names: Dictionary[String, bool] = {}
	var top_function := GDSExSymbolIndex.find_top_level_function(scope_info)
	if top_function == null:
		return read_names
	for lambda in GDSExVariableUsage.find_lambdas(value.statement):
		if value.start <= lambda.close_offset or value.start >= lambda.end_offset:
			continue
		for identifier in _identifier_pattern.search_all(value.code):
			if lambda.parameter_names.has(identifier.get_string()) and found.lambda_name.is_empty():
				found.lambda_name = identifier.get_string()
				read_names[found.lambda_name] = true
	var statements: Array[GDSExSourceScanner.GDSExStatement] = [value.statement]
	for occurrence in GDSExVariableUsage.find_occurrences(scope_info.index, statements, GDSExVariableUsage.find_local_names(top_function)):
		if occurrence.statement != value.statement or occurrence.offset < value.start or occurrence.offset >= value.end:
			continue
		read_names[occurrence.name] = true
		if found.local_name.is_empty():
			found.local_name = occurrence.name
		if occurrence.lookup.scope != top_function and found.block_name.is_empty():
			found.block_name = occurrence.name
			found.block_home = _home_of(occurrence.lookup.scope)
	if not found.lambda_name.is_empty():
		found.local_name = found.lambda_name
		found.block_name = found.lambda_name
		found.block_home = GDSExDependencies.GDSExHome.LAMBDA
	if not found.local_name.is_empty():
		found.block(found.local_name, false)
	return read_names


static func _home_of(scope: GDSExSymbolIndex.GDSExScopeBase) -> GDSExDependencies.GDSExHome:
	if scope is GDSExSymbolIndex.GDSExFunctionScope:
		return GDSExDependencies.GDSExHome.LAMBDA
	var block := scope as GDSExSymbolIndex.GDSExBlockScope
	if block != null and (block.kind == GDSExSymbolIndex.GDSExBlockScope.GDSExKind.FOR or block.kind == GDSExSymbolIndex.GDSExBlockScope.GDSExKind.WHILE):
		return GDSExDependencies.GDSExHome.LOOP
	return GDSExDependencies.GDSExHome.BLOCK


static func _reads_the_tree(value: GDSExValueFinder.GDSExValue) -> bool:
	if value.kind == GDSExValueFinder.GDSExValue.GDSExKind.NODE or not GDSExValueFinder.find_nodes(value.code).is_empty():
		return true
	for call in GDSExCallSiteParser.parse(value.code):
		if call.name == TREE_FUNCTION and (call.receiver.is_empty() or call.receiver == GDSExLanguage.SELF_KEYWORD):
			return true
	return false


static func _check_calls(found: GDSExDependencies, code: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> void:
	for call in GDSExCallSiteParser.parse(code):
		if call.name_offset > 0 and code[call.name_offset - 1] == ANNOTATION_PREFIX:
			continue
		if not call.receiver.is_empty():
			var is_simple := call.receiver.length() <= SIMPLE_RECEIVER_LENGTH and _simple_receiver_pattern.search(call.receiver) != null
			found.block(MEMBER_CALL_TEMPLATE % [call.receiver, call.name] if is_simple else CALL_TEMPLATE % call.name, true)
			continue
		if _is_a_constant_function(call.name):
			continue
		found.block(CALL_TEMPLATE % call.name, true)
		if GDSExLanguage.GLOBAL_FUNCTIONS.has(call.name) or GDSExLanguage.is_known_type(call.name):
			continue
		var member := GDSExTypeResolver.find_class_member(scope_info.class_scope, call.name)
		var is_static := member != null and (member.kind == GDSExTypeResolver.GDSExMember.GDSExKind.CLASS or (member.function != null and member.function.is_static))
		if not is_static and found.member_name.is_empty():
			found.member_name = call.name
		if member != null:
			_note_inner(found, call.name, member.owner_scope, scope_info)


static func _is_a_constant_function(function_name: String) -> bool:
	if function_name == PRELOAD_FUNCTION or GDSExBuiltinTypes.MATH_FUNCTIONS.has(function_name):
		return true
	return GDSExLanguage.is_builtin_type(function_name) and not function_name.begins_with(PACKED_ARRAY_PREFIX)


static func _check_names(found: GDSExDependencies, code: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo, local_names: Dictionary[String, bool]) -> void:
	for identifier in _identifier_pattern.search_all(code):
		var name := identifier.get_string()
		var next := GDSExSourceScanner.skip_spaces(code, identifier.get_end())
		if OPERATOR_WORDS.has(name) or local_names.has(name) or (next < code.length() and code[next] == CALL_OPENER):
			continue
		if GDSExLanguage.NON_CALL_KEYWORDS.has(name):
			continue
		if name == GDSExLanguage.SELF_KEYWORD or name == GDSExLanguage.SUPER_KEYWORD:
			_note_member(found, name)
			continue
		var lookup := GDSExSymbolIndex.find_variable(name, scope_info)
		if lookup.is_defined and lookup.scope is GDSExSymbolIndex.GDSExClassScope:
			var owner := lookup.scope as GDSExSymbolIndex.GDSExClassScope
			_note_inner(found, name, owner, scope_info)
			if lookup.symbol != null and lookup.symbol.is_const:
				continue
			found.block(name, false)
			if not _is_a_static_variable(owner, name):
				_note_member(found, name)
				found.member_variables.append(name)
			continue
		if lookup.is_defined:
			continue
		var member := GDSExTypeResolver.find_class_member(scope_info.class_scope, name)
		if member != null:
			_note_inner(found, name, member.owner_scope, scope_info)
			if member.is_constant or member.kind == GDSExTypeResolver.GDSExMember.GDSExKind.CLASS or member.kind == GDSExTypeResolver.GDSExMember.GDSExKind.ENUM:
				continue
			found.block(name, false)
			if member.owner_scope == null or not _is_a_static_variable(member.owner_scope, name):
				_note_member(found, name)
				found.member_variables.append(name)
			continue
		if not _is_known_everywhere(name, scope_info):
			found.block(name, false)


static func _is_known_everywhere(name: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> bool:
	if GDSExLanguage.is_known_type(name) or GDSExLanguage.MATH_CONSTANTS.has(name) or GDSExBuiltinTypes.GLOBAL_CONSTANTS.has(name):
		return true
	if GDSExTypeResolver.is_global_enum(name) or not GDSExScriptLibrary.find_global_class_path(name).is_empty():
		return true
	var outer_class := scope_info.class_scope.parent
	while outer_class is GDSExSymbolIndex.GDSExClassScope:
		var outer_member := GDSExTypeResolver.find_class_member(outer_class as GDSExSymbolIndex.GDSExClassScope, name)
		if outer_member != null and (outer_member.is_constant or outer_member.kind == GDSExTypeResolver.GDSExMember.GDSExKind.CLASS or outer_member.kind == GDSExTypeResolver.GDSExMember.GDSExKind.ENUM):
			return true
		outer_class = outer_class.parent
	return false


static func _check_chains(found: GDSExDependencies, code: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> void:
	for chain in _chain_pattern.search_all(code):
		var root := chain.get_string(1)
		var next := GDSExSourceScanner.skip_spaces(code, chain.get_end())
		var segments := chain.get_string(2).replace(" ", "").replace("\t", "").split(MEMBER_ACCESS, false)
		if next < code.length() and code[next] == CALL_OPENER:
			segments.remove_at(segments.size() - 1)
		if segments.is_empty() or OPERATOR_WORDS.has(root):
			continue
		var text := root + MEMBER_ACCESS + MEMBER_ACCESS.join(segments)
		if GDSExLanguage.is_builtin_type(root):
			if not GDSExBuiltinTypes.CONSTANTS.get(root, {}).has(segments[0]):
				found.block(text, false)
		elif ClassDB.class_exists(root):
			if not ClassDB.class_has_integer_constant(root, segments[0]) and not ClassDB.class_has_enum(root, segments[0]):
				found.block(text, false)
		elif not _is_a_chain_of_constants(root, segments, scope_info):
			found.block(text, false)


static func _is_a_chain_of_constants(root: String, segments: PackedStringArray, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> bool:
	var current := GDSExTypeResolver.resolve_expression(root, scope_info)
	var prefix := root
	for segment in segments:
		if current.enum_class != null:
			return true
		if not current.is_class_reference:
			return current.type != null and GDSExLanguage.is_builtin_type(current.type.name)
		var member := GDSExTypeResolver.find_member(current, segment)
		if member == null:
			return false
		if not member.is_constant and member.kind != GDSExTypeResolver.GDSExMember.GDSExKind.CLASS and member.kind != GDSExTypeResolver.GDSExMember.GDSExKind.ENUM:
			return false
		prefix += MEMBER_ACCESS + segment
		current = GDSExTypeResolver.resolve_expression(prefix, scope_info)
	return true


static func _note_member(found: GDSExDependencies, name: String) -> void:
	if found.member_name.is_empty():
		found.member_name = name


static func _note_inner(found: GDSExDependencies, name: String, owner: GDSExSymbolIndex.GDSExClassScope, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> void:
	if owner == null or not found.inner_name.is_empty():
		return
	if owner != GDSExSymbolIndex.find_root_class(scope_info.class_scope):
		found.inner_name = name


static func _is_a_static_variable(owner: GDSExSymbolIndex.GDSExClassScope, name: String) -> bool:
	for member in owner.members:
		if member.name == name and member.kind == GDSExSymbolIndex.GDSExClassMember.GDSExKind.VARIABLE:
			return GDSExMemberCategories.is_static(member.modifiers)
	return false
