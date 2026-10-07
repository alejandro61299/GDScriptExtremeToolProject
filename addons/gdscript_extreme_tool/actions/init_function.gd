@tool
extends RefCounted

const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExTypeResolver = preload("res://addons/gdscript_extreme_tool/analysis/type_resolver.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")
const GDSExMemberCategories = preload("res://addons/gdscript_extreme_tool/analysis/member_categories.gd")
const GDSExParamNames = preload("res://addons/gdscript_extreme_tool/analysis/param_names.gd")
const GDSExPluginProjectSettings = preload("res://addons/gdscript_extreme_tool/plugin_project_settings.gd")
const GDSExEditPlan = preload("res://addons/gdscript_extreme_tool/editing/edit_plan.gd")
const GDSExPlacement = preload("res://addons/gdscript_extreme_tool/editing/placement.gd")
const GDSExSnippet = preload("res://addons/gdscript_extreme_tool/editing/snippet.gd")
const GDSExFunctionNameCheck = preload("res://addons/gdscript_extreme_tool/actions/function_name_check.gd")

const INIT_FUNCTION: String = "_init"
const SELECTABLE_CATEGORIES: Array[String] = [GDSExMemberCategories.PRIVATE_VARIABLES, GDSExMemberCategories.PUBLIC_VARIABLES, GDSExMemberCategories.EXPORTS]
const ENGINE_INSTANTIATED_CLASSES: Array[String] = ["Node", "Resource"]
const SIGNATURE_TEMPLATE: String = "func %s(%s) -> void"
const HEADER_END: String = ":"
const TYPED_PARAM_TEMPLATE: String = "%s: %s"
const PARAM_SEPARATOR: String = ", "
const ASSIGNMENT_TEMPLATE: String = "%s = %s"
const EMPTY_BODY: String = "pass"
const LINE_SEPARATOR: String = "\n"
const ENGINE_INIT_MESSAGE: String = "Godot calls _init() without arguments in nodes and resources."


class GDSExInitVariable:
	var name: String = ""
	var category: String = ""
	var type_text: String = ""
	var param_name: String = ""


static func find_variables(context: GDSExCodeContext) -> Array[GDSExInitVariable]:
	var class_scope := context.scope_info.class_scope
	var class_info := _class_info(context)
	var categories := GDSExMemberCategories.of_variables(class_scope)
	var variables: Array[GDSExInitVariable] = []
	for variable_name: String in categories:
		if not SELECTABLE_CATEGORIES.has(categories[variable_name]):
			continue
		var variable := GDSExInitVariable.new()
		variable.name = variable_name
		variable.category = categories[variable_name]
		variable.type_text = GDSExSymbolIndex.type_to_string(GDSExTypeResolver.resolve_expression_type(variable_name, class_info))
		variables.append(variable)
	return variables


static func find_variable_names(context: GDSExCodeContext, category: String) -> PackedStringArray:
	var names := PackedStringArray()
	for variable in find_variables(context):
		if variable.category == category:
			names.append(variable.name)
	return names


static func has_init(context: GDSExCodeContext) -> bool:
	return context.scope_info.class_scope.functions.has(INIT_FUNCTION)


static func is_instantiated_by_engine(context: GDSExCodeContext) -> bool:
	var base_type := GDSExTypeResolver.engine_base_type(context.scope_info.class_scope)
	if not ClassDB.class_exists(base_type):
		return false
	for engine_class in ENGINE_INSTANTIATED_CLASSES:
		if ClassDB.is_parent_class(base_type, engine_class):
			return true
	return false


static func default_function_name(context: GDSExCodeContext) -> String:
	if has_init(context) or is_instantiated_by_engine(context):
		return GDSExPluginProjectSettings.alternative_init_function_name()
	return INIT_FUNCTION


static func check_function_name(context: GDSExCodeContext, function_name: String, parameter_count: int) -> GDSExFunctionNameCheck.GDSExNameCheck:
	var check := GDSExFunctionNameCheck.check_name(context.scope_info.class_scope, function_name, INIT_FUNCTION)
	if not check.is_error() and function_name == INIT_FUNCTION and parameter_count > 0 and is_instantiated_by_engine(context):
		return GDSExFunctionNameCheck.warning(ENGINE_INIT_MESSAGE)
	return check


static func function_text(context: GDSExCodeContext, function_name: String, variable_names: PackedStringArray) -> String:
	var text := PackedStringArray()
	for line in _function_snippet(context, function_name, variable_names).lines:
		text.append(context.indent_unit.repeat(line.indent) + line.text)
	return LINE_SEPARATOR.join(text)


static func build_plan(context: GDSExCodeContext, function_name: String, variable_names: PackedStringArray) -> GDSExEditPlan:
	var snippet := _function_snippet(context, function_name, variable_names)
	var last_line := snippet.lines.size() - 1
	var last_line_length := snippet.lines[last_line].text.length()
	snippet.select(last_line, last_line_length, last_line_length)
	var plan := GDSExEditPlan.new()
	plan.reveal(plan.insert(GDSExPlacement.function_by_order(context.scope_info.class_scope, function_name, context.lines, context.indent_unit), snippet))
	return plan


static func _function_snippet(context: GDSExCodeContext, function_name: String, variable_names: PackedStringArray) -> GDSExSnippet:
	var selected := _select_variables(context, variable_names)
	var snippet := GDSExSnippet.new()
	snippet.add_line(0, _signature(function_name, selected) + HEADER_END)
	for variable in selected:
		snippet.add_line(1, ASSIGNMENT_TEMPLATE % [variable.name, variable.param_name])
	if selected.is_empty():
		snippet.add_line(1, EMPTY_BODY)
	return snippet


static func _signature(function_name: String, selected: Array[GDSExInitVariable]) -> String:
	var params := PackedStringArray()
	for variable in selected:
		params.append(variable.param_name if variable.type_text.is_empty() else TYPED_PARAM_TEMPLATE % [variable.param_name, variable.type_text])
	return SIGNATURE_TEMPLATE % [function_name, PARAM_SEPARATOR.join(params)]


static func _select_variables(context: GDSExCodeContext, variable_names: PackedStringArray) -> Array[GDSExInitVariable]:
	var class_info := _class_info(context)
	var selected: Array[GDSExInitVariable] = []
	var param_names := PackedStringArray()
	for variable in find_variables(context):
		if not variable_names.has(variable.name):
			continue
		variable.param_name = _unique_param_name(variable.name, param_names, class_info)
		param_names.append(variable.param_name)
		selected.append(variable)
	return selected


static func _unique_param_name(variable_name: String, taken_names: PackedStringArray, class_info: GDSExSymbolIndex.GDSExScopeInfo) -> String:
	var param_name := GDSExParamNames.from_source(variable_name)
	var index := taken_names.size()
	while param_name.is_empty() or taken_names.has(param_name) or _is_reserved(param_name, class_info):
		param_name = GDSExParamNames.fallback(index)
		index += 1
	return param_name


static func _is_reserved(identifier: String, class_info: GDSExSymbolIndex.GDSExScopeInfo) -> bool:
	if GDSExLanguage.DECLARATION_KEYWORDS.has(identifier) or GDSExLanguage.is_known_type(identifier):
		return true
	return GDSExTypeResolver.is_name_defined(identifier, class_info)


static func _class_info(context: GDSExCodeContext) -> GDSExSymbolIndex.GDSExScopeInfo:
	var class_scope := context.scope_info.class_scope
	return GDSExSymbolIndex.get_scope_info_for_scope(context.index, class_scope, class_scope.body_start_line)
