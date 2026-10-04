@tool
extends RefCounted

const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExEditPlan = preload("res://addons/gdscript_extreme_tool/editing/edit_plan.gd")


func get_label() -> String:
	return ""


func build_plan(_context: GDSExCodeContext) -> GDSExEditPlan:
	return null
