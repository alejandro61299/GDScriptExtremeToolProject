@tool
extends RefCounted

const DEFAULT_GENERATED_PARAM_FORMAT : String = "p_{name}"
const DEFAULT_FALLBACK_PARAM_FORMAT : String = "param_{index}"
const DEFAULT_GENERATED_SIGNAL_CALLBACK_FORMAT : String = "_on_{name}"
const DEFAULT_BLANK_LINES_AROUND_METHODS_AND_CLASSES : int = 2
const DEFAULT_BLANK_LINES_BETWEEN_MEMBER_CATEGORIES : int = 1
const DEFAULT_MAX_BLANK_LINES_INSIDE_MEMBER_CATEGORY : int = 1
const DEFAULT_MAX_BLANK_LINES_OUTSIDE_MEMBERS : int = 1
const DEFAULT_CLASS_MEMBER_ORDER : Array[String] = [
	"signals",
	"constants",
	"static_variables",
	"enums",
	"exports",
	"onready_variables",
	"public_variables",
	"private_variables",
	"inner_classes",
	"static_public_methods",
	"static_private_methods",
	"init",
	"engine_methods",
	"public_methods",
	"private_methods",
]

const SECTION : String = "gdscript_extreme_tool"
const GENERATED_PARAM_FORMAT_KEY : String = "naming/generated_param_format"
const FALLBACK_PARAM_FORMAT_KEY : String = "naming/fallback_param_format"
const GENERATED_SIGNAL_CALLBACK_FORMAT_KEY : String = "naming/generated_signal_callback_format"
const BLANK_LINES_AROUND_METHODS_AND_CLASSES_KEY : String = "format/blank_lines_around_methods_and_classes"
const BLANK_LINES_BETWEEN_MEMBER_CATEGORIES_KEY : String = "format/blank_lines_between_member_categories"
const MAX_BLANK_LINES_INSIDE_MEMBER_CATEGORY_KEY : String = "format/max_blank_lines_inside_member_category"
const MAX_BLANK_LINES_OUTSIDE_MEMBERS_KEY : String = "format/max_blank_lines_outside_members"
const CLASS_MEMBER_ORDER_KEY : String = "order/class_member_order"
const BLANK_LINES_RANGE : String = "0,10,1"


static func register() -> void:
	var defaults := _defaults()
	for key : String in defaults:
		var setting_name := setting_path(key)
		var default_value : Variant = defaults[key]
		if not ProjectSettings.has_setting(setting_name):
			ProjectSettings.set_setting(setting_name, default_value)
		ProjectSettings.set_initial_value(setting_name, default_value)
		ProjectSettings.set_as_basic(setting_name, true)
		ProjectSettings.add_property_info(_property_info(setting_name, default_value))


static func setting_path(key : String) -> String:
	return SECTION + "/" + key


static func generated_param_format() -> String:
	return _value(GENERATED_PARAM_FORMAT_KEY, DEFAULT_GENERATED_PARAM_FORMAT)


static func fallback_param_format() -> String:
	return _value(FALLBACK_PARAM_FORMAT_KEY, DEFAULT_FALLBACK_PARAM_FORMAT)


static func generated_signal_callback_format() -> String:
	return _value(GENERATED_SIGNAL_CALLBACK_FORMAT_KEY, DEFAULT_GENERATED_SIGNAL_CALLBACK_FORMAT)


static func blank_lines_around_methods_and_classes() -> int:
	return maxi(0, _value(BLANK_LINES_AROUND_METHODS_AND_CLASSES_KEY, DEFAULT_BLANK_LINES_AROUND_METHODS_AND_CLASSES))


static func blank_lines_between_member_categories() -> int:
	return maxi(0, _value(BLANK_LINES_BETWEEN_MEMBER_CATEGORIES_KEY, DEFAULT_BLANK_LINES_BETWEEN_MEMBER_CATEGORIES))


static func max_blank_lines_inside_member_category() -> int:
	return maxi(0, _value(MAX_BLANK_LINES_INSIDE_MEMBER_CATEGORY_KEY, DEFAULT_MAX_BLANK_LINES_INSIDE_MEMBER_CATEGORY))


static func max_blank_lines_outside_members() -> int:
	return maxi(0, _value(MAX_BLANK_LINES_OUTSIDE_MEMBERS_KEY, DEFAULT_MAX_BLANK_LINES_OUTSIDE_MEMBERS))


static func class_member_order() -> PackedStringArray:
	return _value(CLASS_MEMBER_ORDER_KEY, PackedStringArray(DEFAULT_CLASS_MEMBER_ORDER))


static func _value(key : String, default_value : Variant) -> Variant:
	var value : Variant = ProjectSettings.get_setting(setting_path(key), default_value)
	return value if typeof(value) == typeof(default_value) else default_value


static func _defaults() -> Dictionary[String, Variant]:
	return {
		GENERATED_PARAM_FORMAT_KEY: DEFAULT_GENERATED_PARAM_FORMAT,
		FALLBACK_PARAM_FORMAT_KEY: DEFAULT_FALLBACK_PARAM_FORMAT,
		GENERATED_SIGNAL_CALLBACK_FORMAT_KEY: DEFAULT_GENERATED_SIGNAL_CALLBACK_FORMAT,
		BLANK_LINES_AROUND_METHODS_AND_CLASSES_KEY: DEFAULT_BLANK_LINES_AROUND_METHODS_AND_CLASSES,
		BLANK_LINES_BETWEEN_MEMBER_CATEGORIES_KEY: DEFAULT_BLANK_LINES_BETWEEN_MEMBER_CATEGORIES,
		MAX_BLANK_LINES_INSIDE_MEMBER_CATEGORY_KEY: DEFAULT_MAX_BLANK_LINES_INSIDE_MEMBER_CATEGORY,
		MAX_BLANK_LINES_OUTSIDE_MEMBERS_KEY: DEFAULT_MAX_BLANK_LINES_OUTSIDE_MEMBERS,
		CLASS_MEMBER_ORDER_KEY: PackedStringArray(DEFAULT_CLASS_MEMBER_ORDER),
	}


static func _property_info(setting_name : String, default_value : Variant) -> Dictionary:
	var info := {"name": setting_name, "type": typeof(default_value)}
	if default_value is int:
		info["hint"] = PROPERTY_HINT_RANGE
		info["hint_string"] = BLANK_LINES_RANGE
	return info
