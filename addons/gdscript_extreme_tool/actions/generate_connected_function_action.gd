@tool
extends "res://addons/gdscript_extreme_tool/actions/generate_method_action.gd"

const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")

const CONNECTED_FUNCTION_LABEL : String = "Generate Connected Function"
const CONNECTION_TEMPLATE : String = ".connect(%s)"
const SIGNAL_KEYWORD : String = "signal"
const MEMBER_ACCESS : String = "."
const CALL_OPENER : String = "("
const CALL_CLOSER : String = ")"
const NAME_PREFIX_TO_SKIP : String = "_"

static var _identifier_pattern := RegEx.create_from_string("[A-Za-z_]\\w*")
static var _signal_declaration_pattern := RegEx.create_from_string("^(?:@\\w+(?:\\([^)]*\\))?\\s+)*signal\\b")


class GDSExConnection:
	var signal_name: String = ""
	var signal_member: GDSExTypeResolver.GDSExMember
	var tail_start: int = 0
	var tail_end: int = 0


func get_label() -> String:
	return CONNECTED_FUNCTION_LABEL


func build_plan(context: GDSExCodeContext) -> GDSExEditPlan:
	if context.statement == null:
		return null
	var code := context.statement.code
	var connection := _find_connection(code, context.selection_from, context.scope_info)
	if connection == null:
		return null
	var from := context.statement.position_at(connection.tail_start)
	var to := context.statement.position_at(connection.tail_end)
	var callback_name := callback_name_for(connection.signal_name)
	if from.x == -1 or from.x != to.x or callback_name.is_empty():
		return null
	var plan := GDSExEditPlan.new()
	plan.replace(from.x, from.y, to.y, CONNECTION_TEMPLATE % callback_name)
	if not _is_callback_defined(callback_name, context.scope_info):
		var target := GDSExTarget.new()
		target.name = callback_name
		target.target_class = context.scope_info.class_scope
		target.signal_member = connection.signal_member
		var snippet := _build_snippet(_build_signature(target, code, context.scope_info))
		plan.reveal(plan.insert(GDSExPlacement.new_method(target.target_class, context.scope_info, context.lines, context.indent_unit), snippet))
	return plan


func _is_callback_defined(callback_name: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> bool:
	if GDSExTypeResolver.find_class_member(scope_info.class_scope, callback_name) != null:
		return true
	return GDSExSymbolIndex.find_variable(callback_name, scope_info).is_defined


func callback_name_for(signal_name: String) -> String:
	var base_name := signal_name.lstrip(NAME_PREFIX_TO_SKIP)
	if base_name.is_empty():
		return ""
	return GDSExSettings.generated_signal_callback_format().format({"name": base_name})


func _find_connection(code: String, caret: int, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExConnection:
	if _signal_declaration_pattern.search(code) != null:
		return null
	for occurrence in _identifier_pattern.search_all(code):
		var tail_end := _connection_tail_end(code, occurrence.get_end())
		if tail_end != code.length() or GDSExCallSiteParser.chain_start(code, occurrence.get_start()) != 0:
			continue
		if caret < 0 or caret > tail_end:
			continue
		var signal_member := _resolve_signal(code.substr(0, occurrence.get_end()), scope_info)
		if signal_member == null:
			continue
		var connection := GDSExConnection.new()
		connection.signal_name = occurrence.get_string()
		connection.signal_member = signal_member
		connection.tail_start = occurrence.get_end()
		connection.tail_end = tail_end
		return connection
	return null


func _resolve_signal(expression: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExTypeResolver.GDSExMember:
	var signal_member := GDSExTypeResolver.resolve_signal(expression, scope_info)
	if signal_member != null:
		return signal_member
	var type := GDSExTypeResolver.resolve_expression_type(expression, scope_info)
	if type == null or type.name != GDSExLanguage.SIGNAL_TYPE_NAME:
		return null
	var untyped_signal := GDSExTypeResolver.GDSExMember.new()
	untyped_signal.kind = GDSExTypeResolver.GDSExMember.GDSExKind.SIGNAL
	return untyped_signal


func _connection_tail_end(code: String, expression_end: int) -> int:
	var index := expression_end
	if index >= code.length():
		return index
	if code[index] != MEMBER_ACCESS:
		return -1
	var word_end := index + 1
	while word_end < code.length() and GDSExSourceScanner.is_identifier_character(code[word_end]):
		word_end += 1
	if not GDSExTypeResolver.CONNECT_METHOD.begins_with(code.substr(index + 1, word_end - index - 1)):
		return -1
	index = GDSExSourceScanner.skip_spaces(code, word_end)
	if index >= code.length():
		return code.length()
	if code[index] != CALL_OPENER:
		return -1
	index = GDSExSourceScanner.skip_spaces(code, index + 1)
	if index >= code.length():
		return code.length()
	return index + 1 if code[index] == CALL_CLOSER else -1
