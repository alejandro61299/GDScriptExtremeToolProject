@tool
extends "res://addons/gdscript_extreme_tool/actions/code_action.gd"

const GDSExExtractVariable = preload("res://addons/gdscript_extreme_tool/actions/extract_variable.gd")
const GDSExExtractVariableDialog = preload("res://addons/gdscript_extreme_tool/extract_variable_dialog.gd")

const LABEL : String = "Extract Variable..."


func get_label() -> String:
	return LABEL


func build_plan(context: GDSExCodeContext) -> GDSExEditPlan:
	return GDSExExtractVariable.build_default_plan(context)


func create_dialog(context: GDSExCodeContext, on_plan_ready: Callable) -> Window:
	var dialog := GDSExExtractVariableDialog.new()
	dialog.setup(context, on_plan_ready)
	return dialog
