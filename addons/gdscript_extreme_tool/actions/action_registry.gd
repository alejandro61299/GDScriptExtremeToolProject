@tool
extends RefCounted

const GDSExCodeAction = preload("res://addons/gdscript_extreme_tool/actions/code_action.gd")
const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExEditPlan = preload("res://addons/gdscript_extreme_tool/editing/edit_plan.gd")
const GDSExGenerateFunctionAction = preload("res://addons/gdscript_extreme_tool/actions/generate_function_action.gd")
const GDSExGenerateLocalVariableAction = preload("res://addons/gdscript_extreme_tool/actions/generate_local_variable_action.gd")
const GDSExGenerateClassVariableAction = preload("res://addons/gdscript_extreme_tool/actions/generate_class_variable_action.gd")
const GDSExGenerateConnectedFunctionAction = preload("res://addons/gdscript_extreme_tool/actions/generate_connected_function_action.gd")
const GDSExGenerateDefaultInitAction = preload("res://addons/gdscript_extreme_tool/actions/generate_default_init_action.gd")
const GDSExGenerateCustomInitAction = preload("res://addons/gdscript_extreme_tool/actions/generate_custom_init_action.gd")
const GDSExAddExplicitTypeAction = preload("res://addons/gdscript_extreme_tool/actions/add_explicit_type_action.gd")
const GDSExExtractFunctionAction = preload("res://addons/gdscript_extreme_tool/actions/extract_function_action.gd")
const GDSExExtractVariableAction = preload("res://addons/gdscript_extreme_tool/actions/extract_variable_action.gd")
const GDSExReorderClassMembersAction = preload("res://addons/gdscript_extreme_tool/actions/reorder_class_members_action.gd")
const GDSExFormatClassMembersAction = preload("res://addons/gdscript_extreme_tool/actions/format_class_members_action.gd")

const OTHER_SCRIPT_LABEL_TEMPLATE: String = "%s in %s"


class GDSExAvailableAction:
	var action: GDSExCodeAction
	var label: String = ""


static func create_actions() -> Array[GDSExCodeAction]:
	var actions: Array[GDSExCodeAction] = []
	actions.append(GDSExGenerateFunctionAction.new())
	actions.append(GDSExGenerateLocalVariableAction.new())
	actions.append(GDSExGenerateClassVariableAction.new())
	actions.append(GDSExGenerateConnectedFunctionAction.new())
	actions.append(GDSExGenerateDefaultInitAction.new())
	actions.append(GDSExGenerateCustomInitAction.new())
	actions.append(GDSExAddExplicitTypeAction.new())
	actions.append(GDSExExtractFunctionAction.new())
	actions.append(GDSExExtractVariableAction.new())
	actions.append(GDSExReorderClassMembersAction.new())
	actions.append(GDSExFormatClassMembersAction.new())
	return actions


static func find_available(actions: Array[GDSExCodeAction], context: GDSExCodeContext) -> Array[GDSExAvailableAction]:
	var available: Array[GDSExAvailableAction] = []
	for action in actions:
		var plan := action.build_plan(context)
		if plan == null or plan.is_empty():
			continue
		var available_action := GDSExAvailableAction.new()
		available_action.action = action
		available_action.label = label_for(action, plan)
		available.append(available_action)
	return available


static func label_for(action: GDSExCodeAction, plan: GDSExEditPlan) -> String:
	if not plan.is_for_another_script():
		return action.get_label()
	return OTHER_SCRIPT_LABEL_TEMPLATE % [action.get_label(), plan.script_path.get_file()]
