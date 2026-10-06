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

const INIT_FUNCTION: String = "_init"
const SELECTABLE_CATEGORIES: Array[String] = [GDSExMemberCategories.PRIVATE_VARIABLES, GDSExMemberCategories.PUBLIC_VARIABLES, GDSExMemberCategories.EXPORTS]
const ENGINE_INSTANTIATED_CLASSES: Array[String] = ["Node", "Resource"]
const SIGNATURE_TEMPLATE: String = "func %s(%s) -> void"
const HEADER_END: String = ":"
const TYPED_PARAM_TEMPLATE: String = "%s: %s"
const PARAM_SEPARATOR: String = ", "
const ASSIGNMENT_TEMPLATE: String = "%s = %s"
const EMPTY_BODY: String = "pass"
const VALID_NAME_MESSAGE: String = "Function name is valid."
const EMPTY_NAME_MESSAGE: String = "Enter a function name."
const INVALID_NAME_MESSAGE: String = "'%s' is not a valid function name."
const EXISTING_FUNCTION_MESSAGE: String = "The class already has a function named '%s'."
const EXISTING_MEMBER_MESSAGE: String = "The class already has a member named '%s'."
const ENGINE_FUNCTION_MESSAGE: String = "'%s' is a function of the engine class %s."
const INHERITED_MEMBER_MESSAGE: String = "'%s' is already defined in a base class."
const ENGINE_INIT_MESSAGE: String = "Godot calls _init() without arguments in nodes and resources."


class GDSExNameCheck:
	enum GDSExLevel { VALID, WARNING, ERROR }

	var level: GDSExLevel = GDSExLevel.VALID
	var message: String = ""


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


static func check_function_name(context: GDSExCodeContext, function_name: String, parameter_count: int) -> GDSExNameCheck:
	var error := _find_name_error(context.scope_info.class_scope, function_name)
	if not error.is_empty():
		return _name_check(GDSExNameCheck.GDSExLevel.ERROR, error)
	if function_name == INIT_FUNCTION and parameter_count > 0 and is_instantiated_by_engine(context):
		return _name_check(GDSExNameCheck.GDSExLevel.WARNING, ENGINE_INIT_MESSAGE)
	return _name_check(GDSExNameCheck.GDSExLevel.VALID, VALID_NAME_MESSAGE)


static func build_signature(context: GDSExCodeContext, function_name: String, variable_names: PackedStringArray) -> String:
	return _signature(function_name, _select_variables(context, variable_names))


static func build_plan(context: GDSExCodeContext, function_name: String, variable_names: PackedStringArray) -> GDSExEditPlan:
	var selected := _select_variables(context, variable_names)
	var body_lines := PackedStringArray()
	for variable in selected:
		body_lines.append(ASSIGNMENT_TEMPLATE % [variable.name, variable.param_name])
	if body_lines.is_empty():
		body_lines.append(EMPTY_BODY)
	var snippet := GDSExSnippet.new()
	snippet.add_line(0, _signature(function_name, selected) + HEADER_END)
	for body_line in body_lines:
		snippet.add_line(1, body_line)
	var last_line_length := body_lines[body_lines.size() - 1].length()
	snippet.select(body_lines.size(), last_line_length, last_line_length)
	var plan := GDSExEditPlan.new()
	plan.reveal(plan.insert(GDSExPlacement.function_by_order(context.scope_info.class_scope, function_name, context.lines, context.indent_unit), snippet))
	return plan


static func _name_check(level: GDSExNameCheck.GDSExLevel, message: String) -> GDSExNameCheck:
	var check := GDSExNameCheck.new()
	check.level = level
	check.message = message
	return check


static func _find_name_error(class_scope: GDSExSymbolIndex.GDSExClassScope, function_name: String) -> String:
	if function_name.is_empty():
		return EMPTY_NAME_MESSAGE
	if not GDSExTypeResolver.is_identifier(function_name) or _is_keyword(function_name):
		return INVALID_NAME_MESSAGE % function_name
	if class_scope.functions.has(function_name):
		return EXISTING_FUNCTION_MESSAGE % function_name
	if class_scope.vars.has(function_name) or class_scope.signals.has(function_name) or class_scope.inner_classes.has(function_name):
		return EXISTING_MEMBER_MESSAGE % function_name
	if function_name == INIT_FUNCTION:
		return ""
	var base_type := GDSExTypeResolver.engine_base_type(class_scope)
	if ClassDB.class_has_method(base_type, function_name):
		return ENGINE_FUNCTION_MESSAGE % [function_name, base_type]
	if GDSExTypeResolver.find_class_member(class_scope, function_name) != null and not _is_engine_property_or_signal(base_type, function_name):
		return INHERITED_MEMBER_MESSAGE % function_name
	return ""


static func _is_keyword(identifier: String) -> bool:
	return GDSExLanguage.NON_CALL_KEYWORDS.has(identifier) or GDSExLanguage.LITERAL_KEYWORDS.has(identifier) or GDSExLanguage.DECLARATION_KEYWORDS.has(identifier)


static func _is_engine_property_or_signal(base_type: String, member_name: String) -> bool:
	if not ClassDB.class_exists(base_type):
		return false
	if ClassDB.class_has_signal(base_type, member_name):
		return true
	for property in ClassDB.class_get_property_list(base_type):
		if property["name"] == member_name:
			return true
	return false


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
