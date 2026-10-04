@tool
extends "res://addons/gdscript_extreme_tool/actions/variable_action.gd"

const LABEL : String = "Generate Local Variable"
const INITIALIZER_TEMPLATE : String = "%s = "


func get_label() -> String:
	return LABEL


func build_plan(context: GDSExCodeContext) -> GDSExEditPlan:
	var identifier := find_undefined_identifier(context)
	if identifier == null:
		return null
	var scope := _declaration_scope(context.scope_info.scope)
	if scope == null:
		return null
	var declaration := INITIALIZER_TEMPLATE % declaration_text(identifier)
	var value := GDSExTypeResolver.default_variable_value(identifier.type)
	var snippet := GDSExSnippet.new()
	snippet.add_line(0, declaration + value)
	snippet.select(0, declaration.length(), declaration.length() + value.length())
	var plan := GDSExEditPlan.new()
	plan.reveal(plan.insert(GDSExPlacement.scope_start(scope), snippet))
	return plan


func _declaration_scope(scope: GDSExSymbolIndex.GDSExScopeBase) -> GDSExSymbolIndex.GDSExScopeBase:
	var current := scope
	while current != null and not current.accepts_declarations():
		current = current.parent
	return current
