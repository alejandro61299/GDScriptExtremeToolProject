@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExTypeResolver = preload("res://addons/gdscript_extreme_tool/analysis/type_resolver.gd")
const GDSExPluginProjectSettings = preload("res://addons/gdscript_extreme_tool/plugin_project_settings.gd")

const EXPORT_ANNOTATION: String = "@export"
const ONREADY_ANNOTATION: String = "@onready"
const PRIVATE_PREFIX: String = "_"
const INIT_FUNCTION: String = "_init"

const SIGNALS: String = "signals"
const CONSTANTS: String = "constants"
const STATIC_VARIABLES: String = "static_variables"
const ENUMS: String = "enums"
const EXPORTS: String = "exports"
const ONREADY_VARIABLES: String = "onready_variables"
const PUBLIC_VARIABLES: String = "public_variables"
const PRIVATE_VARIABLES: String = "private_variables"
const INNER_CLASSES: String = "inner_classes"
const STATIC_PUBLIC_FUNCTIONS: String = "static_public_functions"
const STATIC_PRIVATE_FUNCTIONS: String = "static_private_functions"
const INIT: String = "init"
const ENGINE_FUNCTIONS: String = "engine_functions"
const PUBLIC_FUNCTIONS: String = "public_functions"
const PRIVATE_FUNCTIONS: String = "private_functions"
const NONE: String = ""

static var _static_pattern := RegEx.create_from_string("\\bstatic\\b")


static func of_member(member: GDSExSymbolIndex.GDSExClassMember, modifiers: String, class_scope: GDSExSymbolIndex.GDSExClassScope) -> String:
	match member.kind:
		GDSExSymbolIndex.GDSExClassMember.GDSExKind.SIGNAL:
			return SIGNALS
		GDSExSymbolIndex.GDSExClassMember.GDSExKind.CONSTANT:
			return CONSTANTS
		GDSExSymbolIndex.GDSExClassMember.GDSExKind.ENUM:
			return ENUMS
		GDSExSymbolIndex.GDSExClassMember.GDSExKind.CLASS:
			return INNER_CLASSES
		GDSExSymbolIndex.GDSExClassMember.GDSExKind.VARIABLE:
			return of_variable(member.name, modifiers)
		GDSExSymbolIndex.GDSExClassMember.GDSExKind.FUNCTION:
			return of_function(member.name, is_static(modifiers), class_scope)
	return NONE


static func of_variable(variable_name: String, modifiers: String) -> String:
	if is_static(modifiers):
		return STATIC_VARIABLES
	if modifiers.contains(EXPORT_ANNOTATION):
		return EXPORTS
	if modifiers.contains(ONREADY_ANNOTATION):
		return ONREADY_VARIABLES
	return PRIVATE_VARIABLES if is_private(variable_name) else PUBLIC_VARIABLES


static func of_function(function_name: String, is_static_function: bool, class_scope: GDSExSymbolIndex.GDSExClassScope) -> String:
	if is_static_function:
		return STATIC_PRIVATE_FUNCTIONS if is_private(function_name) else STATIC_PUBLIC_FUNCTIONS
	if function_name == INIT_FUNCTION:
		return INIT
	if GDSExTypeResolver.is_engine_callback(class_scope, function_name):
		return ENGINE_FUNCTIONS
	return PRIVATE_FUNCTIONS if is_private(function_name) else PUBLIC_FUNCTIONS


static func index_of(category: String) -> int:
	var order := GDSExPluginProjectSettings.class_member_order()
	var index := order.find(category)
	return order.size() if index == -1 else index


static func is_static(modifiers: String) -> bool:
	return _static_pattern.search(modifiers) != null


static func is_private(member_name: String) -> bool:
	return member_name.begins_with(PRIVATE_PREFIX)
