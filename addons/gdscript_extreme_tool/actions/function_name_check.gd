@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExTypeResolver = preload("res://addons/gdscript_extreme_tool/analysis/type_resolver.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")

const VALID_NAME_MESSAGE: String = "Function name is valid."
const EMPTY_NAME_MESSAGE: String = "Enter a function name."
const INVALID_NAME_MESSAGE: String = "'%s' is not a valid function name."
const EXISTING_FUNCTION_MESSAGE: String = "The class already has a function named '%s'."
const EXISTING_MEMBER_MESSAGE: String = "The class already has a member named '%s'."
const ENGINE_FUNCTION_MESSAGE: String = "'%s' is a function of the engine class %s."
const INHERITED_MEMBER_MESSAGE: String = "'%s' is already defined in a base class."


class GDSExNameCheck:
	enum GDSExLevel { VALID, WARNING, ERROR }

	var level: GDSExLevel = GDSExLevel.VALID
	var message: String = ""

	func is_error() -> bool:
		return level == GDSExLevel.ERROR


static func check_name(class_scope: GDSExSymbolIndex.GDSExClassScope, function_name: String, exempt_name: String) -> GDSExNameCheck:
	var error_message := _find_error(class_scope, function_name, exempt_name)
	return valid() if error_message.is_empty() else error(error_message)


static func valid() -> GDSExNameCheck:
	return _new_check(GDSExNameCheck.GDSExLevel.VALID, VALID_NAME_MESSAGE)


static func warning(message: String) -> GDSExNameCheck:
	return _new_check(GDSExNameCheck.GDSExLevel.WARNING, message)


static func error(message: String) -> GDSExNameCheck:
	return _new_check(GDSExNameCheck.GDSExLevel.ERROR, message)


static func _new_check(level: GDSExNameCheck.GDSExLevel, message: String) -> GDSExNameCheck:
	var check := GDSExNameCheck.new()
	check.level = level
	check.message = message
	return check


static func _find_error(class_scope: GDSExSymbolIndex.GDSExClassScope, function_name: String, exempt_name: String) -> String:
	if function_name.is_empty():
		return EMPTY_NAME_MESSAGE
	if not GDSExTypeResolver.is_identifier(function_name) or _is_keyword(function_name):
		return INVALID_NAME_MESSAGE % function_name
	if class_scope.functions.has(function_name):
		return EXISTING_FUNCTION_MESSAGE % function_name
	if class_scope.vars.has(function_name) or class_scope.signals.has(function_name) or class_scope.inner_classes.has(function_name):
		return EXISTING_MEMBER_MESSAGE % function_name
	if function_name == exempt_name:
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
		if property["name"] == member_name and not GDSExTypeResolver.is_a_group_of_properties(property):
			return true
	return false
