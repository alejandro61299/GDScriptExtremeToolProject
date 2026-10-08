@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExTypeResolver = preload("res://addons/gdscript_extreme_tool/analysis/type_resolver.gd")
const GDSExScriptLibrary = preload("res://addons/gdscript_extreme_tool/analysis/script_library.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")
const GDSExFunctionNameCheck = preload("res://addons/gdscript_extreme_tool/actions/function_name_check.gd")

const VALID_NAME_MESSAGE: String = "Variable name is valid."
const EMPTY_NAME_MESSAGE: String = "Enter a variable name."
const INVALID_NAME_MESSAGE: String = "'%s' is not a valid variable name."
const LOCAL_NAME_MESSAGE: String = "This function already has a variable named '%s'."
const EXISTING_MEMBER_MESSAGE: String = "The class already has a member named '%s'."
const ENGINE_PROPERTY_MESSAGE: String = "'%s' is a property of the engine class %s."
const INHERITED_MEMBER_MESSAGE: String = "'%s' is already defined in a base class."
const GLOBAL_CLASS_MESSAGE: String = "'%s' is the name of a global class."
const HIDES_MEMBER_MESSAGE: String = "'%s' will hide the member of the class with that name."
const HIDES_GLOBAL_CLASS_MESSAGE: String = "'%s' will hide the global class with that name."


static func check_local(variable_name: String, usage_scope: GDSExSymbolIndex.GDSExScopeInfo, declaration_scope: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExFunctionNameCheck.GDSExNameCheck:
	var invalid_message := _find_invalid(variable_name)
	if not invalid_message.is_empty():
		return GDSExFunctionNameCheck.error(invalid_message)
	if _is_a_visible_local(variable_name, usage_scope) or _is_a_visible_local(variable_name, declaration_scope) or _declares_later(declaration_scope.scope, variable_name, declaration_scope.line):
		return GDSExFunctionNameCheck.error(LOCAL_NAME_MESSAGE % variable_name)
	if _is_a_global_class(variable_name):
		return GDSExFunctionNameCheck.warning(HIDES_GLOBAL_CLASS_MESSAGE % variable_name)
	if not _find_member_conflict(variable_name, usage_scope.class_scope).is_empty():
		return GDSExFunctionNameCheck.warning(HIDES_MEMBER_MESSAGE % variable_name)
	return _valid()


static func check_member(variable_name: String, usage_scope: GDSExSymbolIndex.GDSExScopeInfo, class_scope: GDSExSymbolIndex.GDSExClassScope) -> GDSExFunctionNameCheck.GDSExNameCheck:
	var invalid_message := _find_invalid(variable_name)
	if not invalid_message.is_empty():
		return GDSExFunctionNameCheck.error(invalid_message)
	if _is_a_visible_local(variable_name, usage_scope):
		return GDSExFunctionNameCheck.error(LOCAL_NAME_MESSAGE % variable_name)
	if _is_a_global_class(variable_name):
		return GDSExFunctionNameCheck.error(GLOBAL_CLASS_MESSAGE % variable_name)
	var conflict := _find_member_conflict(variable_name, class_scope)
	if conflict.is_empty() and class_scope != usage_scope.class_scope:
		conflict = _find_member_conflict(variable_name, usage_scope.class_scope)
	return _valid() if conflict.is_empty() else GDSExFunctionNameCheck.error(conflict)


static func _valid() -> GDSExFunctionNameCheck.GDSExNameCheck:
	var check := GDSExFunctionNameCheck.valid()
	check.message = VALID_NAME_MESSAGE
	return check


static func _find_invalid(variable_name: String) -> String:
	if variable_name.is_empty():
		return EMPTY_NAME_MESSAGE
	if not GDSExTypeResolver.is_identifier(variable_name) or _is_keyword(variable_name):
		return INVALID_NAME_MESSAGE % variable_name
	return ""


static func _is_keyword(identifier: String) -> bool:
	return GDSExLanguage.NON_CALL_KEYWORDS.has(identifier) or GDSExLanguage.LITERAL_KEYWORDS.has(identifier) or GDSExLanguage.DECLARATION_KEYWORDS.has(identifier) or GDSExLanguage.MATH_CONSTANTS.has(identifier)


static func _is_a_visible_local(variable_name: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> bool:
	var lookup := GDSExSymbolIndex.find_variable(variable_name, scope_info)
	return lookup.is_defined and not lookup.scope is GDSExSymbolIndex.GDSExClassScope


static func _declares_later(scope: GDSExSymbolIndex.GDSExScopeBase, variable_name: String, from_line: int) -> bool:
	if scope is GDSExSymbolIndex.GDSExClassScope:
		return false
	for local in scope.locals:
		if local.name == variable_name:
			return true
	for child in scope.children:
		if child.end_line >= from_line and _declares_later(child, variable_name, from_line):
			return true
	return false


static func _is_a_global_class(variable_name: String) -> bool:
	return ClassDB.class_exists(variable_name) or not GDSExScriptLibrary.find_global_class_path(variable_name).is_empty()


static func _find_member_conflict(variable_name: String, class_scope: GDSExSymbolIndex.GDSExClassScope) -> String:
	if class_scope.vars.has(variable_name) or class_scope.functions.has(variable_name) or class_scope.signals.has(variable_name) or class_scope.inner_classes.has(variable_name):
		return EXISTING_MEMBER_MESSAGE % variable_name
	var base_type := GDSExTypeResolver.engine_base_type(class_scope)
	if _is_engine_property_or_signal(base_type, variable_name):
		return ENGINE_PROPERTY_MESSAGE % [variable_name, base_type]
	if ClassDB.class_has_method(base_type, variable_name):
		return ""
	return INHERITED_MEMBER_MESSAGE % variable_name if GDSExTypeResolver.find_class_member(class_scope, variable_name) != null else ""


static func _is_engine_property_or_signal(base_type: String, member_name: String) -> bool:
	if not ClassDB.class_exists(base_type):
		return false
	if ClassDB.class_has_signal(base_type, member_name):
		return true
	for property in ClassDB.class_get_property_list(base_type):
		if property["name"] == member_name:
			return true
	return false
