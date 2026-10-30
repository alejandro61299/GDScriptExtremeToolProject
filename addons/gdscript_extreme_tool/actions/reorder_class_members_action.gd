@tool
extends "res://addons/gdscript_extreme_tool/actions/code_action.gd"

const GDSExClassLayout = preload("res://addons/gdscript_extreme_tool/analysis/class_layout.gd")
const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")

const LABEL : String = "Reorder Class Members"


func get_label() -> String:
	return LABEL


func build_plan(context: GDSExCodeContext) -> GDSExEditPlan:
	return plan_for_class(context.scope_info.class_scope, context)


static func plan_for_class(class_scope: GDSExSymbolIndex.GDSExClassScope, context: GDSExCodeContext) -> GDSExEditPlan:
	var layout := GDSExClassLayout.reorder(class_scope, context.lines)
	if layout == null:
		return null
	var plan := GDSExEditPlan.new()
	plan.replace_lines(layout.first_line, layout.last_line, layout.lines, layout.line_map)
	return plan
