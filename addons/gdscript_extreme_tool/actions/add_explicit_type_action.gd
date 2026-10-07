@tool
extends "res://addons/gdscript_extreme_tool/actions/code_action.gd"

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExTypeResolver = preload("res://addons/gdscript_extreme_tool/analysis/type_resolver.gd")
const GDSExBuiltinTypes = preload("res://addons/gdscript_extreme_tool/analysis/builtin_types.gd")

const LABEL : String = "Add Explicit Type"
const INFERRED_ASSIGNMENT : String = ":="
const ASSIGNMENT : String = "="
const ACCESSOR_SEPARATOR : String = ":"
const NULL_LITERAL : String = "null"
const VARIANT_TYPE_NAME : String = "Variant"
const MEMBER_ACCESS : String = "."
const TYPE_TEMPLATE : String = ": %s ="
const VALUE_SEPARATOR : String = " "

static var _variable_pattern := RegEx.create_from_string("^(?:(?:@\\w+(?:\\([^)]*\\))?|static)\\s+)*var\\s+(\\w+)")
static var _enum_value_pattern := RegEx.create_from_string("^(?:(\\w+)\\.)?(\\w+)$")


func get_label() -> String:
	return LABEL


func build_plan(context: GDSExCodeContext) -> GDSExEditPlan:
	var statement := context.statement
	if statement == null:
		return null
	var code := statement.code
	var variable := _variable_pattern.search(code)
	if variable == null:
		return null
	var name_end := variable.get_end(1)
	var operator_start := GDSExSourceScanner.skip_spaces(code, name_end)
	var is_inferred := code.substr(operator_start, INFERRED_ASSIGNMENT.length()) == INFERRED_ASSIGNMENT
	if not is_inferred and not _is_assignment(code, operator_start):
		return null
	var operator_end := operator_start + (INFERRED_ASSIGNMENT.length() if is_inferred else ASSIGNMENT.length())
	var declaration_scope := GDSExSymbolIndex.get_scope_info_for_line(context.index, statement.first_line)
	var type_text := _value_type_text(code, operator_end, declaration_scope)
	if type_text.is_empty():
		return null
	var from := statement.position_at(name_end)
	var to := statement.position_at(operator_end)
	if from.x != to.x:
		return null
	var text := TYPE_TEMPLATE % type_text
	var value := statement.position_at(GDSExSourceScanner.skip_spaces(code, operator_end))
	if value.x == to.x and value.y < context.lines[to.x].length():
		to = value
		text += VALUE_SEPARATOR
	var plan := GDSExEditPlan.new()
	plan.keeps_caret = true
	plan.replace(from.x, from.y, to.y, text)
	return plan


func _is_assignment(code: String, offset: int) -> bool:
	return code.substr(offset, ASSIGNMENT.length()) == ASSIGNMENT and code.substr(offset + ASSIGNMENT.length(), ASSIGNMENT.length()) != ASSIGNMENT


func _value_type_text(code: String, value_start: int, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> String:
	var accessors_start := GDSExSymbolIndex.find_top_level(code, ACCESSOR_SEPARATOR, value_start)
	var value_end := code.length() if accessors_start == -1 else accessors_start
	var value := code.substr(value_start, value_end - value_start).strip_edges()
	if value.is_empty() or value == NULL_LITERAL:
		return ""
	var enum_type_text := _enum_type_text(value, scope_info)
	if not enum_type_text.is_empty():
		return enum_type_text
	var resolved := GDSExTypeResolver.resolve_expression(value, scope_info)
	if resolved.is_class_reference or resolved.is_preloaded or resolved.type == null:
		return ""
	var type_text := GDSExSymbolIndex.type_to_string(resolved.type)
	return "" if type_text == VARIANT_TYPE_NAME else type_text


func _enum_type_text(value: String, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> String:
	var enum_value := _enum_value_pattern.search(value)
	if enum_value == null:
		return ""
	var owner_name := enum_value.get_string(1)
	var constant_name := enum_value.get_string(2)
	if owner_name.is_empty():
		return GDSExBuiltinTypes.GLOBAL_CONSTANTS.get(constant_name, "")
	if _declares_enum(scope_info.class_scope, owner_name):
		return owner_name
	var builtin_type: String = GDSExBuiltinTypes.CONSTANTS.get(owner_name, {}).get(constant_name, "")
	if builtin_type.contains(MEMBER_ACCESS):
		return builtin_type
	if not ClassDB.class_exists(owner_name) or not ClassDB.class_has_integer_constant(owner_name, constant_name):
		return ""
	var enum_name := ClassDB.class_get_integer_constant_enum(owner_name, constant_name)
	var declaring_class := owner_name
	while not enum_name.is_empty() and not declaring_class.is_empty() and not ClassDB.class_has_enum(declaring_class, enum_name, true):
		declaring_class = ClassDB.get_parent_class(declaring_class)
	return "" if enum_name.is_empty() or declaring_class.is_empty() else declaring_class + MEMBER_ACCESS + enum_name


func _declares_enum(class_scope: GDSExSymbolIndex.GDSExClassScope, enum_name: String) -> bool:
	var current: GDSExSymbolIndex.GDSExScopeBase = class_scope
	while current != null:
		if current is GDSExSymbolIndex.GDSExClassScope:
			for member in (current as GDSExSymbolIndex.GDSExClassScope).members:
				if member.kind == GDSExSymbolIndex.GDSExClassMember.GDSExKind.ENUM and member.name == enum_name:
					return true
		current = current.parent
	return false
