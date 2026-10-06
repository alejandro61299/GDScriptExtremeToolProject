@tool
extends "res://addons/gdscript_extreme_tool/actions/code_action.gd"

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExCallSiteParser = preload("res://addons/gdscript_extreme_tool/analysis/call_site_parser.gd")
const GDSExTypeResolver = preload("res://addons/gdscript_extreme_tool/analysis/type_resolver.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")
const GDSExParamNames = preload("res://addons/gdscript_extreme_tool/analysis/param_names.gd")
const GDSExSnippet = preload("res://addons/gdscript_extreme_tool/editing/snippet.gd")
const GDSExPlacement = preload("res://addons/gdscript_extreme_tool/editing/placement.gd")

const LABEL : String = "Generate Function Definition"
const SELF_ACCESS : String = "self."
const FUNCTION_HEADER_TEMPLATE : String = "%sfunc %s(%s) -> %s:"
const STATIC_PREFIX : String = "static "
const TYPED_PARAM_TEMPLATE : String = "%s: %s"
const PARAM_SEPARATOR : String = ", "
const RETURN_TEMPLATE : String = "return %s"
const EMPTY_BODY : String = "pass"


class GDSExTarget:
	var name: String = ""
	var name_offset: int = 0
	var range_start: int = 0
	var range_end: int = 0
	var target_class: GDSExSymbolIndex.GDSExClassScope
	var is_static: bool = false
	var call: GDSExCallSiteParser.GDSExCallSite
	var signal_member: GDSExTypeResolver.GDSExMember

	func name_end() -> int:
		return name_offset + name.length()


class GDSExFunctionSignature:
	var name: String = ""
	var is_static: bool = false
	var param_names: PackedStringArray = []
	var param_types: Array[GDSExSymbolIndex.GDSExTypeData] = []
	var return_type: GDSExSymbolIndex.GDSExTypeData


func get_label() -> String:
	return LABEL


func build_plan(context: GDSExCodeContext) -> GDSExEditPlan:
	if context.statement == null:
		return null
	var code := context.statement.code
	var target := _choose_target(find_targets(code, context.scope_info), context.selection_from, context.selection_to)
	if target == null:
		return null
	var signature := _build_signature(target, code, context.scope_info)
	var plan := GDSExEditPlan.new()
	plan.reveal(plan.insert(GDSExPlacement.new_function(target.target_class, context.scope_info, context.lines, context.indent_unit), _build_snippet(signature)))
	return plan


func find_targets(code: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> Array[GDSExTarget]:
	var targets: Array[GDSExTarget] = []
	for call in GDSExCallSiteParser.parse(code):
		var call_target := _call_target(call, scope_info)
		if call_target != null:
			targets.append(call_target)
		var callback_target := _callback_target(call, scope_info)
		if callback_target != null:
			targets.append(callback_target)
	return targets


func _call_target(call: GDSExCallSiteParser.GDSExCallSite, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExTarget:
	if call.name == GDSExLanguage.CONSTRUCTOR_NAME or call.receiver == GDSExLanguage.SUPER_KEYWORD:
		return null
	var target := GDSExTarget.new()
	target.call = call
	target.name = call.name
	target.name_offset = call.name_offset
	target.range_start = call.expression_offset
	target.range_end = call.expression_end()
	if call.receiver.is_empty():
		if GDSExTypeResolver.is_function_defined(call.name, scope_info) or GDSExSymbolIndex.find_variable(call.name, scope_info).is_defined:
			return null
		var caller := GDSExSymbolIndex.find_top_level_function(scope_info)
		target.target_class = scope_info.class_scope
		target.is_static = caller != null and caller.is_static
		return target
	var receiver := GDSExTypeResolver.resolve_expression(call.receiver, scope_info)
	if receiver.class_scope == null or GDSExTypeResolver.find_class_member(receiver.class_scope, call.name) != null:
		return null
	target.target_class = receiver.class_scope
	target.is_static = receiver.is_class_reference
	return target


func _callback_target(call: GDSExCallSiteParser.GDSExCallSite, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExTarget:
	if call.name != GDSExTypeResolver.CONNECT_FUNCTION or call.receiver.is_empty() or call.arguments.is_empty():
		return null
	var argument := call.arguments[0]
	var callback_name := argument.text.trim_prefix(SELF_ACCESS)
	if not GDSExTypeResolver.is_identifier(callback_name):
		return null
	if GDSExTypeResolver.is_function_defined(callback_name, scope_info) or GDSExSymbolIndex.find_variable(callback_name, scope_info).is_defined:
		return null
	var signal_member := GDSExTypeResolver.resolve_signal(call.receiver, scope_info)
	if signal_member == null:
		return null
	var target := GDSExTarget.new()
	target.name = callback_name
	target.name_offset = argument.offset + argument.length - callback_name.length()
	target.range_start = target.name_offset
	target.range_end = target.name_end()
	target.target_class = scope_info.class_scope
	target.signal_member = signal_member
	return target


func _choose_target(targets: Array[GDSExTarget], selection_from: int, selection_to: int) -> GDSExTarget:
	if selection_from != selection_to:
		var selected := targets.filter(func(target: GDSExTarget) -> bool: return target.name_offset < selection_to and target.name_end() > selection_from)
		return selected[0] if selected.size() == 1 else null
	for target in targets:
		if selection_from >= target.name_offset and selection_from <= target.name_end():
			return target
	if targets.size() == 1:
		return targets[0]
	var enclosing: GDSExTarget = null
	for target in targets:
		if selection_from < target.range_start or selection_from > target.range_end:
			continue
		if enclosing == null or target.range_start > enclosing.range_start:
			enclosing = target
	return enclosing


func _build_signature(target: GDSExTarget, code: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExFunctionSignature:
	var signature := GDSExFunctionSignature.new()
	signature.name = target.name
	signature.is_static = target.is_static
	if target.signal_member != null:
		for index in target.signal_member.param_names.size():
			_add_param(signature, target.signal_member.param_names[index], target.signal_member.param_types[index])
		signature.return_type = GDSExSymbolIndex.make_type(GDSExLanguage.VOID_TYPE_NAME)
		return signature
	for argument in target.call.arguments:
		_add_param(signature, argument.text, GDSExTypeResolver.resolve_expression_type(argument.text, scope_info))
	signature.return_type = GDSExTypeResolver.expected_type(code, target.call, scope_info)
	return signature


func _add_param(signature: GDSExFunctionSignature, source_name: String, type: GDSExSymbolIndex.GDSExTypeData) -> void:
	var param_name := GDSExParamNames.from_source(source_name)
	if param_name.is_empty() or signature.param_names.has(param_name):
		param_name = GDSExParamNames.fallback(signature.param_names.size())
	signature.param_names.append(param_name)
	signature.param_types.append(type)


func _build_snippet(signature: GDSExFunctionSignature) -> GDSExSnippet:
	var params := PackedStringArray()
	for index in signature.param_names.size():
		var type_text := GDSExSymbolIndex.type_to_string(signature.param_types[index])
		var param_name := signature.param_names[index]
		params.append(param_name if type_text.is_empty() else TYPED_PARAM_TEMPLATE % [param_name, type_text])
	var default_value := GDSExTypeResolver.default_value_text(signature.return_type)
	var snippet := GDSExSnippet.new()
	snippet.add_line(0, FUNCTION_HEADER_TEMPLATE % [
		STATIC_PREFIX if signature.is_static else "",
		signature.name,
		PARAM_SEPARATOR.join(params),
		GDSExSymbolIndex.type_to_string(signature.return_type),
	])
	snippet.add_line(1, EMPTY_BODY if default_value.is_empty() else RETURN_TEMPLATE % default_value)
	snippet.select_line(1)
	return snippet
