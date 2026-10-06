@tool
extends RefCounted

const GDSExTypeResolver = preload("res://addons/gdscript_extreme_tool/analysis/type_resolver.gd")
const GDSExPluginProjectSettings = preload("res://addons/gdscript_extreme_tool/plugin_project_settings.gd")

const UNNAMED_ARGUMENT_KEYWORDS: Array[String] = ["null", "true", "false", "self"]
const NAME_PLACEHOLDER: String = "{name}"
const PRIVATE_PREFIX: String = "_"


static func from_source(source_name: String) -> String:
	if not GDSExTypeResolver.is_identifier(source_name) or UNNAMED_ARGUMENT_KEYWORDS.has(source_name):
		return ""
	var base_name := source_name.to_lower().lstrip(PRIVATE_PREFIX)
	if base_name.is_empty():
		return ""
	if _matches_format(base_name):
		return base_name
	return GDSExPluginProjectSettings.generated_param_format().format({"name": base_name})


static func fallback(index: int) -> String:
	return GDSExPluginProjectSettings.fallback_param_format().format({"index": index})


static func _matches_format(param_name: String) -> bool:
	var affixes := GDSExPluginProjectSettings.generated_param_format().split(NAME_PLACEHOLDER)
	var prefix := affixes[0]
	var suffix := affixes[1] if affixes.size() > 1 else ""
	if prefix.is_empty() and suffix.is_empty():
		return false
	if param_name.length() <= prefix.length() + suffix.length():
		return false
	return param_name.begins_with(prefix) and param_name.ends_with(suffix)
