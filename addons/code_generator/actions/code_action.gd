@tool
extends RefCounted

const CodeContext = preload("res://addons/code_generator/actions/code_context.gd")
const EditPlan = preload("res://addons/code_generator/editing/edit_plan.gd")


func get_label() -> String:
	return ""


func build_plan(_context: CodeContext) -> EditPlan:
	return null
