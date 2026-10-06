@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExEditPlan = preload("res://addons/gdscript_extreme_tool/editing/edit_plan.gd")
const GDSExIndentation = preload("res://addons/gdscript_extreme_tool/editing/indentation.gd")

const BLANK_LINES_AROUND_FUNCTIONS: int = 2
const BLANK_LINES_AFTER_CLASS_HEADER: int = 1
const BLANK_LINES_AROUND_VARIABLE_GROUP: int = 1


static func new_function(target_class: GDSExSymbolIndex.GDSExClassScope, scope_info: GDSExSymbolIndex.GDSExScopeInfo, lines: PackedStringArray, indent_unit: String) -> GDSExEditPlan.GDSExInsertionPoint:
	var enclosing_member := _enclosing_member(target_class, scope_info)
	if enclosing_member != null:
		return after_member(enclosing_member, target_class, lines, indent_unit)
	return end_of_class(target_class, lines, indent_unit)


static func after_member(member: GDSExSymbolIndex.GDSExScopeBase, class_scope: GDSExSymbolIndex.GDSExClassScope, lines: PackedStringArray, indent_unit: String) -> GDSExEditPlan.GDSExInsertionPoint:
	return _member_point(class_scope, member.end_line + 1, BLANK_LINES_AROUND_FUNCTIONS, lines, indent_unit)


static func end_of_class(class_scope: GDSExSymbolIndex.GDSExClassScope, lines: PackedStringArray, indent_unit: String) -> GDSExEditPlan.GDSExInsertionPoint:
	var last_member_end := _last_member_end_line(class_scope)
	if last_member_end == -1:
		return class_header(class_scope, lines, indent_unit)
	return _member_point(class_scope, last_member_end + 1, BLANK_LINES_AROUND_FUNCTIONS, lines, indent_unit)


static func class_header(class_scope: GDSExSymbolIndex.GDSExClassScope, lines: PackedStringArray, indent_unit: String) -> GDSExEditPlan.GDSExInsertionPoint:
	var header_line := class_scope.extends_line if class_scope.extends_line != -1 else class_scope.start_line
	return _member_point(class_scope, maxi(0, header_line) + 1, BLANK_LINES_AFTER_CLASS_HEADER, lines, indent_unit)


static func scope_start(scope: GDSExSymbolIndex.GDSExScopeBase) -> GDSExEditPlan.GDSExInsertionPoint:
	var point := GDSExEditPlan.GDSExInsertionPoint.new()
	point.line = scope.body_start_line
	point.indent_text = scope.body_indent_text
	return point


static func member_variable(class_scope: GDSExSymbolIndex.GDSExClassScope, lines: PackedStringArray, indent_unit: String) -> GDSExEditPlan.GDSExInsertionPoint:
	var last_variable: GDSExSymbolIndex.GDSExClassMember = null
	var last_declaration: GDSExSymbolIndex.GDSExClassMember = null
	var is_followed_by_function := false
	for member in class_scope.members:
		if member.kind == GDSExSymbolIndex.GDSExClassMember.GDSExKind.FUNCTION or member.kind == GDSExSymbolIndex.GDSExClassMember.GDSExKind.CLASS:
			is_followed_by_function = true
			break
		if member.kind == GDSExSymbolIndex.GDSExClassMember.GDSExKind.VARIABLE:
			last_variable = member
		elif member.kind != GDSExSymbolIndex.GDSExClassMember.GDSExKind.ANNOTATION and member.kind != GDSExSymbolIndex.GDSExClassMember.GDSExKind.OTHER:
			last_declaration = member
	var point := GDSExEditPlan.GDSExInsertionPoint.new()
	point.indent_text = _member_indent_text(class_scope, lines, indent_unit)
	if last_variable != null:
		point.line = last_variable.end_line + 1
		return point
	point.line = (class_scope.header_end_line if last_declaration == null else last_declaration.end_line) + 1
	if point.line != class_scope.body_start_line:
		point.blank_lines_before = BLANK_LINES_AROUND_VARIABLE_GROUP
	if is_followed_by_function:
		point.blank_lines_after = BLANK_LINES_AROUND_FUNCTIONS
	return point


static func _member_point(class_scope: GDSExSymbolIndex.GDSExClassScope, line: int, blank_lines_before: int, lines: PackedStringArray, indent_unit: String) -> GDSExEditPlan.GDSExInsertionPoint:
	var point := GDSExEditPlan.GDSExInsertionPoint.new()
	point.line = line
	point.indent_text = _member_indent_text(class_scope, lines, indent_unit)
	point.blank_lines_before = blank_lines_before
	point.blank_lines_after = BLANK_LINES_AROUND_FUNCTIONS
	return point


static func _member_indent_text(class_scope: GDSExSymbolIndex.GDSExClassScope, lines: PackedStringArray, indent_unit: String) -> String:
	if class_scope.parent == null:
		return ""
	if class_scope.body_start_line != -1:
		return class_scope.body_indent_text
	return GDSExIndentation.leading_whitespace(lines[class_scope.start_line]) + indent_unit


static func _enclosing_member(target_class: GDSExSymbolIndex.GDSExClassScope, scope_info: GDSExSymbolIndex.GDSExScopeInfo) -> GDSExSymbolIndex.GDSExScopeBase:
	var scope := scope_info.scope
	while scope != null and scope.parent != target_class:
		scope = scope.parent
	return scope


static func _last_member_end_line(class_scope: GDSExSymbolIndex.GDSExClassScope) -> int:
	var last_end := -1
	for function_name in class_scope.functions:
		for function: GDSExSymbolIndex.GDSExFunctionScope in class_scope.functions[function_name]:
			last_end = maxi(last_end, function.end_line)
	for variable_name in class_scope.vars:
		var variable: GDSExSymbolIndex.GDSExVariableSymbol = class_scope.vars[variable_name]
		last_end = maxi(last_end, variable.end_line)
	return last_end
