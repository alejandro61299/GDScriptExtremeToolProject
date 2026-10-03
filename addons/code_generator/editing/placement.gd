@tool
extends RefCounted

const SymbolIndex = preload("res://addons/code_generator/analysis/symbol_index.gd")
const EditPlan = preload("res://addons/code_generator/editing/edit_plan.gd")
const Indentation = preload("res://addons/code_generator/editing/indentation.gd")

const BLANK_LINES_AROUND_METHODS: int = 2
const BLANK_LINES_AFTER_CLASS_HEADER: int = 1
const BLANK_LINES_AROUND_VARIABLE_GROUP: int = 1


static func new_method(target_class: SymbolIndex.ClassScope, scope_info: SymbolIndex.ScopeInfo, lines: PackedStringArray, indent_unit: String) -> EditPlan.InsertionPoint:
	var enclosing_member := _enclosing_member(target_class, scope_info)
	if enclosing_member != null:
		return after_member(enclosing_member, target_class, lines, indent_unit)
	return end_of_class(target_class, lines, indent_unit)


static func after_member(member: SymbolIndex.ScopeBase, class_scope: SymbolIndex.ClassScope, lines: PackedStringArray, indent_unit: String) -> EditPlan.InsertionPoint:
	return _member_point(class_scope, member.end_line + 1, BLANK_LINES_AROUND_METHODS, lines, indent_unit)


static func end_of_class(class_scope: SymbolIndex.ClassScope, lines: PackedStringArray, indent_unit: String) -> EditPlan.InsertionPoint:
	var last_member_end := _last_member_end_line(class_scope)
	if last_member_end == -1:
		return class_header(class_scope, lines, indent_unit)
	return _member_point(class_scope, last_member_end + 1, BLANK_LINES_AROUND_METHODS, lines, indent_unit)


static func class_header(class_scope: SymbolIndex.ClassScope, lines: PackedStringArray, indent_unit: String) -> EditPlan.InsertionPoint:
	var header_line := class_scope.extends_line if class_scope.extends_line != -1 else class_scope.start_line
	return _member_point(class_scope, maxi(0, header_line) + 1, BLANK_LINES_AFTER_CLASS_HEADER, lines, indent_unit)


static func scope_start(scope: SymbolIndex.ScopeBase) -> EditPlan.InsertionPoint:
	var point := EditPlan.InsertionPoint.new()
	point.line = scope.body_start_line
	point.indent_text = scope.body_indent_text
	return point


static func member_variable(class_scope: SymbolIndex.ClassScope, lines: PackedStringArray, indent_unit: String) -> EditPlan.InsertionPoint:
	var last_variable: SymbolIndex.ClassMember = null
	var last_declaration: SymbolIndex.ClassMember = null
	var is_followed_by_method := false
	for member in class_scope.members:
		if member.kind == SymbolIndex.ClassMember.Kind.METHOD or member.kind == SymbolIndex.ClassMember.Kind.CLASS:
			is_followed_by_method = true
			break
		if member.kind == SymbolIndex.ClassMember.Kind.VARIABLE:
			last_variable = member
		elif member.kind != SymbolIndex.ClassMember.Kind.ANNOTATION and member.kind != SymbolIndex.ClassMember.Kind.OTHER:
			last_declaration = member
	var point := EditPlan.InsertionPoint.new()
	point.indent_text = _member_indent_text(class_scope, lines, indent_unit)
	if last_variable != null:
		point.line = last_variable.end_line + 1
		return point
	point.line = (class_scope.header_end_line if last_declaration == null else last_declaration.end_line) + 1
	if point.line != class_scope.body_start_line:
		point.blank_lines_before = BLANK_LINES_AROUND_VARIABLE_GROUP
	if is_followed_by_method:
		point.blank_lines_after = BLANK_LINES_AROUND_METHODS
	return point


static func _member_point(class_scope: SymbolIndex.ClassScope, line: int, blank_lines_before: int, lines: PackedStringArray, indent_unit: String) -> EditPlan.InsertionPoint:
	var point := EditPlan.InsertionPoint.new()
	point.line = line
	point.indent_text = _member_indent_text(class_scope, lines, indent_unit)
	point.blank_lines_before = blank_lines_before
	point.blank_lines_after = BLANK_LINES_AROUND_METHODS
	return point


static func _member_indent_text(class_scope: SymbolIndex.ClassScope, lines: PackedStringArray, indent_unit: String) -> String:
	if class_scope.parent == null:
		return ""
	if class_scope.body_start_line != -1:
		return class_scope.body_indent_text
	return Indentation.leading_whitespace(lines[class_scope.start_line]) + indent_unit


static func _enclosing_member(target_class: SymbolIndex.ClassScope, scope_info: SymbolIndex.ScopeInfo) -> SymbolIndex.ScopeBase:
	var scope := scope_info.scope
	while scope != null and scope.parent != target_class:
		scope = scope.parent
	return scope


static func _last_member_end_line(class_scope: SymbolIndex.ClassScope) -> int:
	var last_end := -1
	for method_name in class_scope.methods:
		for method: SymbolIndex.FunctionScope in class_scope.methods[method_name]:
			last_end = maxi(last_end, method.end_line)
	for variable_name in class_scope.vars:
		var variable: SymbolIndex.VariableSymbol = class_scope.vars[variable_name]
		last_end = maxi(last_end, variable.end_line)
	return last_end
