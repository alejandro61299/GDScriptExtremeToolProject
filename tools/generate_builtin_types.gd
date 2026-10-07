extends SceneTree

const OUTPUT_PATH: String = "res://addons/gdscript_extreme_tool/analysis/builtin_types.gd"
const GENERATOR_PATH: String = "res://tools/generate_builtin_types.gd"
const VOID_TYPE_NAME: String = "void"
const USAGE: String = "Usage: godot --headless --path . --script res://tools/generate_builtin_types.gd -- <path to extension_api.json>"
const ENTRY_TEMPLATE: String = "\t\t\"%s\": \"%s\","
const GROUP_OPEN_TEMPLATE: String = "\t\"%s\": {"
const GROUP_CLOSE: String = "\t},"
const FLAT_ENTRY_TEMPLATE: String = "\t\"%s\": \"%s\","
const GLOBAL_CONSTANT_TYPE: String = "int"
const ENUM_TYPE_TEMPLATE: String = "%s.%s"


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		print(USAGE)
		quit(1)
		return
	var api: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	var header: Dictionary = api["header"]
	var functions := PackedStringArray()
	var members := PackedStringArray()
	var indexing := PackedStringArray()
	var type_constants := PackedStringArray()
	for builtin_class: Dictionary in api["builtin_classes"]:
		var type_name: String = builtin_class["name"]
		_append_group(functions, type_name, builtin_class.get("methods", []), _function_signature)
		_append_group(members, type_name, builtin_class.get("members", []), _member_type)
		_append_group(type_constants, type_name, _typed_constants(type_name, builtin_class), _member_type)
		if builtin_class.has("indexing_return_type"):
			indexing.append(FLAT_ENTRY_TEMPLATE % [type_name, builtin_class["indexing_return_type"]])

	var constants := PackedStringArray()
	for constant: Dictionary in api["global_constants"]:
		constants.append(FLAT_ENTRY_TEMPLATE % [constant["name"], GLOBAL_CONSTANT_TYPE])
	for global_enum: Dictionary in api["global_enums"]:
		for value: Dictionary in global_enum["values"]:
			constants.append(FLAT_ENTRY_TEMPLATE % [value["name"], global_enum["name"]])

	var output := PackedStringArray([
		"@tool",
		"extends RefCounted",
		"",
		"const GENERATED_BY: String = \"%s\"" % GENERATOR_PATH,
		"const ENGINE_VERSION: String = \"%d.%d.%d\"" % [header["version_major"], header["version_minor"], header["version_patch"]],
		"const SIGNATURE_SEPARATOR: String = \"|\"",
		"const ARGUMENT_SEPARATOR: String = \",\"",
		"",
		"const FUNCTIONS: Dictionary[String, Dictionary] = {",
	])
	output.append_array(functions)
	output.append_array(["}", "", "const MEMBERS: Dictionary[String, Dictionary] = {"])
	output.append_array(members)
	output.append_array(["}", "", "const INDEXING: Dictionary[String, String] = {"])
	output.append_array(indexing)
	output.append_array(["}", "", "const CONSTANTS: Dictionary[String, Dictionary] = {"])
	output.append_array(type_constants)
	output.append_array(["}", "", "const GLOBAL_CONSTANTS: Dictionary[String, String] = {"])
	output.append_array(constants)
	output.append_array(["}", ""])

	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	file.store_string("\n".join(output))
	file.close()
	print("Wrote %s" % OUTPUT_PATH)
	quit()


func _append_group(output: PackedStringArray, type_name: String, entries: Array, describe: Callable) -> void:
	if entries.is_empty():
		return
	output.append(GROUP_OPEN_TEMPLATE % type_name)
	for entry: Dictionary in entries:
		output.append(ENTRY_TEMPLATE % [entry["name"], describe.call(entry)])
	output.append(GROUP_CLOSE)


func _typed_constants(type_name: String, builtin_class: Dictionary) -> Array:
	var constants: Array = builtin_class.get("constants", []).duplicate()
	for type_enum: Dictionary in builtin_class.get("enums", []):
		for value: Dictionary in type_enum["values"]:
			constants.append({"name": value["name"], "type": ENUM_TYPE_TEMPLATE % [type_name, type_enum["name"]]})
	return constants


func _function_signature(function: Dictionary) -> String:
	var argument_types := PackedStringArray()
	for argument: Dictionary in function.get("arguments", []):
		argument_types.append(argument["type"])
	return "%s|%s" % [function.get("return_type", VOID_TYPE_NAME), ",".join(argument_types)]


func _member_type(member: Dictionary) -> String:
	return member["type"]
