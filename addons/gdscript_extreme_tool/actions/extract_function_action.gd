@tool
extends "res://addons/gdscript_extreme_tool/actions/code_action.gd"

const GDSExExtractFunction = preload("res://addons/gdscript_extreme_tool/actions/extract_function.gd")
const GDSExExtractFunctionDialog = preload("res://addons/gdscript_extreme_tool/extract_function_dialog.gd")

const LABEL : String = "Extract Function..."


func get_label() -> String:
	return LABEL


func build_plan(context: GDSExCodeContext) -> GDSExEditPlan:
	return GDSExExtractFunction.build_default_plan(context)


func create_dialog(context: GDSExCodeContext, on_plan_ready: Callable) -> Window:
	var dialog := GDSExExtractFunctionDialog.new()
	dialog.setup(context, on_plan_ready)
	return dialog
