@tool
extends RefCounted

const GDSExCodeAction = preload("res://addons/gdscript_extreme_tool/actions/code_action.gd")
const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExGenerateMethodAction = preload("res://addons/gdscript_extreme_tool/actions/generate_method_action.gd")
const GDSExGenerateLocalVariableAction = preload("res://addons/gdscript_extreme_tool/actions/generate_local_variable_action.gd")
const GDSExGenerateClassVariableAction = preload("res://addons/gdscript_extreme_tool/actions/generate_class_variable_action.gd")
const GDSExGenerateConnectedFunctionAction = preload("res://addons/gdscript_extreme_tool/actions/generate_connected_function_action.gd")
const GDSExReorderClassMembersAction = preload("res://addons/gdscript_extreme_tool/actions/reorder_class_members_action.gd")
const GDSExFormatClassMembersAction = preload("res://addons/gdscript_extreme_tool/actions/format_class_members_action.gd")


static func create_actions() -> Array[GDSExCodeAction]:
	var actions: Array[GDSExCodeAction] = []
	actions.append(GDSExGenerateMethodAction.new())
	actions.append(GDSExGenerateLocalVariableAction.new())
	actions.append(GDSExGenerateClassVariableAction.new())
	actions.append(GDSExGenerateConnectedFunctionAction.new())
	actions.append(GDSExReorderClassMembersAction.new())
	actions.append(GDSExFormatClassMembersAction.new())
	return actions


static func find_available(actions: Array[GDSExCodeAction], context: GDSExCodeContext) -> Array[GDSExCodeAction]:
	var available: Array[GDSExCodeAction] = []
	for action in actions:
		var plan := action.build_plan(context)
		if plan != null and not plan.is_empty():
			available.append(action)
	return available
