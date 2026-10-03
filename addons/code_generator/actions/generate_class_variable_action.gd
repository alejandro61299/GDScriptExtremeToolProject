@tool
extends "res://addons/code_generator/actions/variable_action.gd"

const LABEL : String = "Generate Class Variable"
const STATIC_PREFIX : String = "static "


func get_label() -> String:
	return LABEL


func build_plan(context: CodeContext) -> EditPlan:
	var identifier := find_undefined_identifier(context)
	if identifier == null:
		return null
	var caller := SymbolIndex.find_top_level_function(context.scope_info)
	var prefix := STATIC_PREFIX if caller != null and caller.is_static else ""
	var snippet := Snippet.new()
	snippet.add_line(0, prefix + declaration_text(identifier))
	var plan := EditPlan.new()
	plan.insert(Placement.member_variable(context.scope_info.class_scope, context.lines, context.indent_unit), snippet)
	return plan
