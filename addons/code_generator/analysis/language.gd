@tool
extends RefCounted

const VOID_TYPE_NAME: String = "void"
const VARIANT_TYPE_NAME: String = "Variant"
const CALLABLE_TYPE_NAME: String = "Callable"
const SIGNAL_TYPE_NAME: String = "Signal"
const BOOLEAN_TYPE_NAME: String = "bool"
const OBJECT_TYPE_NAME: String = "Object"
const NODE_TYPE_NAME: String = "Node"
const DEFAULT_SCRIPT_BASE: String = "RefCounted"
const SELF_KEYWORD: String = "self"
const SUPER_KEYWORD: String = "super"
const CONSTRUCTOR_NAME: String = "new"

const NON_CALL_KEYWORDS: Array[String] = [
	"if", "elif", "else", "for", "while", "match", "when", "return", "and", "or", "not", "in", "is", "as",
	"await", "func", "var", "const", "signal", "class", "class_name", "extends", "static", "enum", "pass",
	"break", "continue", "breakpoint", "yield", "void",
]

const GLOBAL_FUNCTIONS: Dictionary[String, String] = {
	"Color8": "Color",
	"abs": "Variant",
	"absf": "float",
	"absi": "int",
	"acos": "float",
	"acosh": "float",
	"angle_difference": "float",
	"asin": "float",
	"asinh": "float",
	"assert": "void",
	"atan": "float",
	"atan2": "float",
	"atanh": "float",
	"bezier_derivative": "float",
	"bezier_interpolate": "float",
	"bytes_to_var": "Variant",
	"bytes_to_var_with_objects": "Variant",
	"ceil": "Variant",
	"ceilf": "float",
	"ceili": "int",
	"char": "String",
	"clamp": "Variant",
	"clampf": "float",
	"clampi": "int",
	"convert": "Variant",
	"cos": "float",
	"cosh": "float",
	"cubic_interpolate": "float",
	"cubic_interpolate_angle": "float",
	"cubic_interpolate_angle_in_time": "float",
	"cubic_interpolate_in_time": "float",
	"db_to_linear": "float",
	"deg_to_rad": "float",
	"dict_to_inst": "Object",
	"ease": "float",
	"error_string": "String",
	"exp": "float",
	"floor": "Variant",
	"floorf": "float",
	"floori": "int",
	"fmod": "float",
	"fposmod": "float",
	"get_stack": "Array",
	"hash": "int",
	"inst_to_dict": "Dictionary",
	"instance_from_id": "Object",
	"inverse_lerp": "float",
	"is_equal_approx": "bool",
	"is_finite": "bool",
	"is_inf": "bool",
	"is_instance_id_valid": "bool",
	"is_instance_of": "bool",
	"is_instance_valid": "bool",
	"is_nan": "bool",
	"is_same": "bool",
	"is_zero_approx": "bool",
	"len": "int",
	"lerp": "Variant",
	"lerp_angle": "float",
	"lerpf": "float",
	"linear_to_db": "float",
	"load": "Resource",
	"log": "float",
	"max": "Variant",
	"maxf": "float",
	"maxi": "int",
	"min": "Variant",
	"minf": "float",
	"mini": "int",
	"move_toward": "float",
	"nearest_po2": "int",
	"ord": "int",
	"pingpong": "float",
	"posmod": "int",
	"pow": "float",
	"preload": "Resource",
	"print": "void",
	"print_debug": "void",
	"print_rich": "void",
	"print_stack": "void",
	"print_verbose": "void",
	"printerr": "void",
	"printraw": "void",
	"prints": "void",
	"printt": "void",
	"push_error": "void",
	"push_warning": "void",
	"rad_to_deg": "float",
	"rand_from_seed": "PackedInt64Array",
	"randf": "float",
	"randf_range": "float",
	"randfn": "float",
	"randi": "int",
	"randi_range": "int",
	"randomize": "void",
	"range": "Array",
	"remap": "float",
	"rid_allocate_id": "int",
	"rid_from_int64": "RID",
	"rotate_toward": "float",
	"round": "Variant",
	"roundf": "float",
	"roundi": "int",
	"seed": "void",
	"sign": "Variant",
	"signf": "float",
	"signi": "int",
	"sin": "float",
	"sinh": "float",
	"smoothstep": "float",
	"snapped": "Variant",
	"snappedf": "float",
	"snappedi": "int",
	"sqrt": "float",
	"step_decimals": "int",
	"str": "String",
	"str_to_var": "Variant",
	"tan": "float",
	"tanh": "float",
	"type_convert": "Variant",
	"type_exists": "bool",
	"type_string": "String",
	"typeof": "int",
	"var_to_bytes": "PackedByteArray",
	"var_to_bytes_with_objects": "PackedByteArray",
	"var_to_str": "String",
	"weakref": "Variant",
	"wrap": "Variant",
	"wrapf": "float",
	"wrapi": "int",
}

static var _builtin_type_names: Dictionary[String, bool] = {}


static func is_builtin_type(type_name: String) -> bool:
	if _builtin_type_names.is_empty():
		for type in TYPE_MAX:
			_builtin_type_names[type_string(type)] = true
	return _builtin_type_names.has(type_name)


static func is_known_type(type_name: String) -> bool:
	return is_builtin_type(type_name) or ClassDB.class_exists(type_name)
