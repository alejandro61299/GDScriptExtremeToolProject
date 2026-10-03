@tool
extends "res://addons/code_generator/actions/code_action.gd"

const ClassLayout = preload("res://addons/code_generator/analysis/class_layout.gd")

const LABEL : String = "Format Class Members"


func get_label() -> String:
	return LABEL


func build_plan(context: CodeContext) -> EditPlan:
	var layout := ClassLayout.format(context.scope_info.class_scope, context.index.statements, context.lines)
	if layout == null:
		return null
	var plan := EditPlan.new()
	plan.replace_lines(layout.first_line, layout.last_line, layout.lines, layout.line_map)
	return plan
