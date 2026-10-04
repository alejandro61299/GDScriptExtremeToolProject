@tool
extends "res://addons/gdscript_extreme_tool/actions/variable_action.gd"

const LABEL : String = "Generate Class Variable"
const STATIC_PREFIX : String = "static "


func get_label() -> String:
	return LABEL


func build_plan(context: GDSExCodeContext) -> GDSExEditPlan:
	var identifier := find_undefined_identifier(context)
	if identifier == null:
		return null
	var caller := GDSExSymbolIndex.find_top_level_function(context.scope_info)
	var prefix := STATIC_PREFIX if caller != null and caller.is_static else ""
	var snippet := GDSExSnippet.new()
	snippet.add_line(0, prefix + declaration_text(identifier))
	var plan := GDSExEditPlan.new()
	plan.insert(GDSExPlacement.member_variable(context.scope_info.class_scope, context.lines, context.indent_unit), snippet)
	return plan
