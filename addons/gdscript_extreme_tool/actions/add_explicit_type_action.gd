@tool
extends "res://addons/gdscript_extreme_tool/actions/code_action.gd"

const GDSExExplicitTypes = preload("res://addons/gdscript_extreme_tool/analysis/explicit_types.gd")

const LABEL : String = "Add Explicit Types"
const TYPE_TEMPLATE : String = ": %s ="
const VALUE_SEPARATOR : String = " "


func get_label() -> String:
	return LABEL


func build_plan(context: GDSExCodeContext) -> GDSExEditPlan:
	var plan := GDSExEditPlan.new()
	plan.keeps_caret = true
	for variable in GDSExExplicitTypes.find(context.index):
		_add_type(plan, variable, context.lines)
	return null if plan.is_empty() else plan


func _add_type(plan: GDSExEditPlan, variable: GDSExExplicitTypes.GDSExTypedVariable, lines: PackedStringArray) -> void:
	var declaration := variable.symbol.declaration
	var statement := variable.symbol.statement
	var from := statement.position_at(declaration.start)
	var to := statement.position_at(declaration.operator_end)
	if from.x != to.x:
		return
	var text := TYPE_TEMPLATE % variable.type.text
	var value := statement.position_at(declaration.value_start)
	if value.x == to.x and value.y < lines[to.x].length():
		to = value
		text += VALUE_SEPARATOR
	plan.replace(from.x, from.y, to.y, text)
