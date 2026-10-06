@tool
extends "res://addons/gdscript_extreme_tool/actions/code_action.gd"

const GDSExInitFunction = preload("res://addons/gdscript_extreme_tool/actions/init_function.gd")
const GDSExMemberCategories = preload("res://addons/gdscript_extreme_tool/analysis/member_categories.gd")

const LABEL : String = "Generate Default Init Definition"


func get_label() -> String:
	return LABEL


func build_plan(context: GDSExCodeContext) -> GDSExEditPlan:
	if GDSExInitFunction.has_init(context) or GDSExInitFunction.is_instantiated_by_engine(context):
		return null
	var private_names := GDSExInitFunction.find_variable_names(context, GDSExMemberCategories.PRIVATE_VARIABLES)
	if private_names.is_empty():
		return null
	return GDSExInitFunction.build_plan(context, GDSExInitFunction.INIT_FUNCTION, private_names)
