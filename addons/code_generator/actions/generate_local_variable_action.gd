@tool
extends "res://addons/code_generator/actions/variable_action.gd"

const LABEL : String = "Generate Local Variable"
const INITIALIZER_TEMPLATE : String = "%s = "


func get_label() -> String:
	return LABEL


func build_plan(context: CodeContext) -> EditPlan:
	var identifier := find_undefined_identifier(context)
	if identifier == null:
		return null
	var scope := _declaration_scope(context.scope_info.scope)
	if scope == null:
		return null
	var declaration := INITIALIZER_TEMPLATE % declaration_text(identifier)
	var value := TypeResolver.default_variable_value(identifier.type)
	var snippet := Snippet.new()
	snippet.add_line(0, declaration + value)
	snippet.select(0, declaration.length(), declaration.length() + value.length())
	var plan := EditPlan.new()
	plan.insert(Placement.scope_start(scope), snippet)
	return plan


func _declaration_scope(scope: SymbolIndex.ScopeBase) -> SymbolIndex.ScopeBase:
	var current := scope
	while current != null and not current.accepts_declarations():
		current = current.parent
	return current
