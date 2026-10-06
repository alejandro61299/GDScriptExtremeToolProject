@tool
extends "res://addons/gdscript_extreme_tool/actions/code_action.gd"

const GDSExInitFunction = preload("res://addons/gdscript_extreme_tool/actions/init_function.gd")
const GDSExMemberCategories = preload("res://addons/gdscript_extreme_tool/analysis/member_categories.gd")
const GDSExInitFunctionDialog = preload("res://addons/gdscript_extreme_tool/init_function_dialog.gd")

const LABEL : String = "Generate Custom Init Definition..."


func get_label() -> String:
	return LABEL


func build_plan(context: GDSExCodeContext) -> GDSExEditPlan:
	if GDSExInitFunction.find_variables(context).is_empty():
		return null
	var private_names := GDSExInitFunction.find_variable_names(context, GDSExMemberCategories.PRIVATE_VARIABLES)
	return GDSExInitFunction.build_plan(context, GDSExInitFunction.default_function_name(context), private_names)


func create_dialog(context: GDSExCodeContext, on_plan_ready: Callable) -> Window:
	var dialog := GDSExInitFunctionDialog.new()
	dialog.setup(context, on_plan_ready)
	return dialog
