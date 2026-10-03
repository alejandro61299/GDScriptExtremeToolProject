@tool
extends RefCounted

const SymbolApi = preload("res://addons/code_generator/symbol_index.gd")
const EditPlan = preload("res://addons/code_generator/editing/edit_plan.gd")
const Indentation = preload("res://addons/code_generator/editing/indentation.gd")

const BLANK_LINES_AROUND_METHODS: int = 2
const BLANK_LINES_AFTER_CLASS_HEADER: int = 1


static func new_method(target_class: SymbolApi.ClassScope, scope_info: SymbolApi.ScopeInfo, lines: PackedStringArray, indent_unit: String) -> EditPlan.InsertionPoint:
	var enclosing_method := _top_level_method(scope_info)
	if enclosing_method != null and scope_info.class_scope == target_class:
		return after_method(enclosing_method, target_class, lines, indent_unit)
	return end_of_class(target_class, lines, indent_unit)


static func after_method(method: SymbolApi.MethodScope, class_scope: SymbolApi.ClassScope, lines: PackedStringArray, indent_unit: String) -> EditPlan.InsertionPoint:
	return _member_point(class_scope, method.end_line + 1, BLANK_LINES_AROUND_METHODS, lines, indent_unit)


static func end_of_class(class_scope: SymbolApi.ClassScope, lines: PackedStringArray, indent_unit: String) -> EditPlan.InsertionPoint:
	var last_member_end := _last_member_end_line(class_scope)
	if last_member_end == -1:
		return class_header(class_scope, lines, indent_unit)
	return _member_point(class_scope, last_member_end + 1, BLANK_LINES_AROUND_METHODS, lines, indent_unit)


static func class_header(class_scope: SymbolApi.ClassScope, lines: PackedStringArray, indent_unit: String) -> EditPlan.InsertionPoint:
	var header_line := class_scope.extends_line if class_scope.extends_line != -1 else class_scope.start_line
	return _member_point(class_scope, maxi(0, header_line) + 1, BLANK_LINES_AFTER_CLASS_HEADER, lines, indent_unit)


static func _member_point(class_scope: SymbolApi.ClassScope, line: int, blank_lines_before: int, lines: PackedStringArray, indent_unit: String) -> EditPlan.InsertionPoint:
	var point := EditPlan.InsertionPoint.new()
	point.line = line
	point.indent_text = _member_indent_text(class_scope, lines, indent_unit)
	point.blank_lines_before = blank_lines_before
	point.blank_lines_after = BLANK_LINES_AROUND_METHODS
	return point


static func _member_indent_text(class_scope: SymbolApi.ClassScope, lines: PackedStringArray, indent_unit: String) -> String:
	if class_scope.parent == null:
		return ""
	return Indentation.leading_whitespace(lines[class_scope.start_line]) + indent_unit


static func _top_level_method(scope_info: SymbolApi.ScopeInfo) -> SymbolApi.MethodScope:
	var method := scope_info.method_scope
	while method != null and method.parent is SymbolApi.MethodScope:
		method = method.parent as SymbolApi.MethodScope
	return method


static func _last_member_end_line(class_scope: SymbolApi.ClassScope) -> int:
	var last_end := -1
	for method_name in class_scope.methods:
		for method: SymbolApi.MethodScope in class_scope.methods[method_name]:
			last_end = maxi(last_end, method.end_line)
	for variable_name in class_scope.vars:
		var variable: SymbolApi.VarScope = class_scope.vars[variable_name]
		last_end = maxi(last_end, variable.end_line)
	return last_end
