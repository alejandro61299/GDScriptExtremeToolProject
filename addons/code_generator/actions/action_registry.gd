@tool
extends RefCounted

const CodeAction = preload("res://addons/code_generator/actions/code_action.gd")
const CodeContext = preload("res://addons/code_generator/actions/code_context.gd")
const GenerateMethodAction = preload("res://addons/code_generator/actions/generate_method_action.gd")
const GenerateLocalVariableAction = preload("res://addons/code_generator/actions/generate_local_variable_action.gd")
const GenerateClassVariableAction = preload("res://addons/code_generator/actions/generate_class_variable_action.gd")
const GenerateConnectedFunctionAction = preload("res://addons/code_generator/actions/generate_connected_function_action.gd")
const ReorderClassMembersAction = preload("res://addons/code_generator/actions/reorder_class_members_action.gd")


static func create_actions() -> Array[CodeAction]:
	var actions: Array[CodeAction] = []
	actions.append(GenerateMethodAction.new())
	actions.append(GenerateLocalVariableAction.new())
	actions.append(GenerateClassVariableAction.new())
	actions.append(GenerateConnectedFunctionAction.new())
	actions.append(ReorderClassMembersAction.new())
	return actions


static func find_available(actions: Array[CodeAction], context: CodeContext) -> Array[CodeAction]:
	var available: Array[CodeAction] = []
	for action in actions:
		var plan := action.build_plan(context)
		if plan != null and not plan.is_empty():
			available.append(action)
	return available
