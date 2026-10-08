@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExCallSiteParser = preload("res://addons/gdscript_extreme_tool/analysis/call_site_parser.gd")
const GDSExTypeResolver = preload("res://addons/gdscript_extreme_tool/analysis/type_resolver.gd")
const GDSExVariableUsage = preload("res://addons/gdscript_extreme_tool/analysis/variable_usage.gd")
const GDSExValueFinder = preload("res://addons/gdscript_extreme_tool/analysis/value_finder.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")

const DEFAULT_NAME: String = "value"
const PRIVATE_PREFIX: String = "_"
const MEMBER_ACCESS: String = "."
const PATH_SEPARATOR: String = "/"
const NUMBERED_NAME_TEMPLATE: String = "%s_%d"
const NAME_VERBS: Array[String] = ["get", "find", "make", "create", "build", "load", "compute", "calculate"]
const WORD_SEPARATOR: String = "_"
const NODE_FUNCTIONS: Array[String] = ["get_node", "get_node_or_null", "find_child"]
const FILE_FUNCTIONS: Array[String] = ["preload", "load"]

static var _quoted_pattern := RegEx.create_from_string("[\"']([^\"']*)[\"']")
static var _target_end_pattern := RegEx.create_from_string("(\\w+)\\s*(?::[^=]*)?$")


static func propose(value: GDSExValueFinder.GDSExValue, lines: PackedStringArray, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> String:
	var proposed := ""
	if value.kind == GDSExValueFinder.GDSExValue.GDSExKind.NODE:
		proposed = _from_path(GDSExValueFinder.source_text(value, lines).substr(1))
	elif value.kind == GDSExValueFinder.GDSExValue.GDSExKind.CALL:
		proposed = _from_call(value, lines, scope_info)
	if proposed.is_empty():
		proposed = _from_use(value, scope_info)
	if proposed.is_empty() and value.kind == GDSExValueFinder.GDSExValue.GDSExKind.CALL:
		proposed = value.call.name.to_snake_case()
	proposed = proposed.lstrip(PRIVATE_PREFIX)
	return proposed if _is_usable(proposed) else DEFAULT_NAME


static func written_as(base_name: String, is_constant: bool, is_private: bool) -> String:
	var written := base_name.to_upper() if is_constant else base_name
	return PRIVATE_PREFIX + written if is_private else written


static func numbered(base_name: String, number: int) -> String:
	return NUMBERED_NAME_TEMPLATE % [base_name, number]


static func _from_call(value: GDSExValueFinder.GDSExValue, lines: PackedStringArray, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> String:
	var call := value.call
	if call.name == GDSExLanguage.CONSTRUCTOR_NAME:
		return call.receiver.get_slice(MEMBER_ACCESS, call.receiver.get_slice_count(MEMBER_ACCESS) - 1).strip_edges().to_snake_case()
	if call.receiver.is_empty() and GDSExLanguage.is_builtin_type(call.name):
		return ""
	if NODE_FUNCTIONS.has(call.name) or FILE_FUNCTIONS.has(call.name):
		var quoted := _quoted_pattern.search(GDSExValueFinder.source_text(value, lines))
		if quoted != null:
			return _from_path(quoted.get_string(1).get_basename() if FILE_FUNCTIONS.has(call.name) else quoted.get_string(1))
	var function_name := call.name.lstrip(PRIVATE_PREFIX)
	for verb in NAME_VERBS:
		if function_name == verb:
			return _from_type(value, scope_info)
		if function_name.begins_with(verb + WORD_SEPARATOR):
			var shortened := function_name.trim_prefix(verb + WORD_SEPARATOR)
			return shortened if _is_usable(shortened) else _from_type(value, scope_info)
	return function_name


static func _from_type(value: GDSExValueFinder.GDSExValue, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> String:
	var resolved := GDSExTypeResolver.resolve_expression(value.code, scope_info)
	if resolved.type == null or resolved.class_scope == null:
		return ""
	return resolved.type.name.get_slice(MEMBER_ACCESS, resolved.type.name.get_slice_count(MEMBER_ACCESS) - 1).to_snake_case()


static func _from_path(path: String) -> String:
	var text := path.strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
	return text.get_slice(PATH_SEPARATOR, text.get_slice_count(PATH_SEPARATOR) - 1).to_snake_case()


static func _from_use(value: GDSExValueFinder.GDSExValue, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> String:
	var code := value.statement.code
	var assignment := GDSExVariableUsage.parse_assignment(code)
	if assignment != null and assignment.value_start == value.start and value.end == code.length():
		var target := _target_end_pattern.search(code.substr(assignment.statement_start, assignment.operator_start - assignment.statement_start).strip_edges())
		if target != null:
			return target.get_string(1)
	for call in GDSExCallSiteParser.parse(code):
		for index in call.arguments.size():
			var argument := call.arguments[index]
			if argument.offset == value.start and argument.offset + argument.length == value.end:
				return _parameter_name(call, index, scope_info)
	return ""


static func _parameter_name(call: GDSExCallSiteParser.GDSExCallSite, index: int, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> String:
	var member: GDSExTypeResolver.GDSExMember = null
	if call.receiver.is_empty():
		member = GDSExTypeResolver.find_class_member(scope_info.class_scope, call.name)
	else:
		member = GDSExTypeResolver.find_member(GDSExTypeResolver.resolve_expression(call.receiver, scope_info), call.name)
	if member == null or member.kind != GDSExTypeResolver.GDSExMember.GDSExKind.FUNCTION or index >= member.param_names.size():
		return ""
	return member.param_names[index]


static func _is_usable(text: String) -> bool:
	return GDSExTypeResolver.is_identifier(text) and not GDSExLanguage.NON_CALL_KEYWORDS.has(text) and not GDSExLanguage.LITERAL_KEYWORDS.has(text) and not GDSExLanguage.DECLARATION_KEYWORDS.has(text)
