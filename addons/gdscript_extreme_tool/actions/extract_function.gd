@tool
extends RefCounted

const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExTypeResolver = preload("res://addons/gdscript_extreme_tool/analysis/type_resolver.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")
const GDSExStatementRange = preload("res://addons/gdscript_extreme_tool/analysis/statement_range.gd")
const GDSExVariableUsage = preload("res://addons/gdscript_extreme_tool/analysis/variable_usage.gd")
const GDSExBracketGroups = preload("res://addons/gdscript_extreme_tool/analysis/bracket_groups.gd")
const GDSExIndentation = preload("res://addons/gdscript_extreme_tool/editing/indentation.gd")
const GDSExEditPlan = preload("res://addons/gdscript_extreme_tool/editing/edit_plan.gd")
const GDSExPlacement = preload("res://addons/gdscript_extreme_tool/editing/placement.gd")
const GDSExSnippet = preload("res://addons/gdscript_extreme_tool/editing/snippet.gd")
const GDSExFunctionNameCheck = preload("res://addons/gdscript_extreme_tool/actions/function_name_check.gd")

const DEFAULT_FUNCTION_NAME: String = "_extracted_function"
const NUMBERED_NAME_TEMPLATE: String = "%s_%d"
const FIRST_NAME_NUMBER: int = 2
const VALUE_TYPES_WITH_FIELDS: Array[String] = [
	"Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i", "Rect2", "Rect2i", "Color", "Plane",
	"Quaternion", "AABB", "Basis", "Transform2D", "Transform3D", "Projection",
]
const SIGNATURE_TEMPLATE: String = "%sfunc %s(%s)%s"
const STATIC_PREFIX: String = "static "
const RETURN_TYPE_TEMPLATE: String = " -> %s"
const TYPED_PARAM_TEMPLATE: String = "%s: %s"
const PARAM_SEPARATOR: String = ", "
const CALL_TEMPLATE: String = "%s%s(%s)"
const AWAIT_PREFIX: String = "await "
const RETURN_STATEMENT: String = "return"
const RETURN_TEMPLATE: String = "return %s"
const ASSIGNMENT_TEMPLATE: String = "%s = %s"
const VALUE_SEPARATOR: String = " "
const HEADER_END: String = ":"
const GROUPING_OPENER: String = "("
const PRIVATE_PREFIX: String = "_"
const CONSTRUCTOR_NAME: String = "_init"
const CONSTRUCTOR_MESSAGE: String = "'_init' is the constructor of the class."
const LOCAL_NAME_MESSAGE: String = "The function has a variable named '%s'."
const PUBLIC_NAME_MESSAGE: String = "The function will be public: its name does not start with '_'."

enum GDSExForm { RETURN, ASSIGNMENT, OUTPUT, PLAIN }
enum GDSExRejection { NONE, RANGE, TOO_MANY_OUTPUTS, UNKNOWN_TYPE }

static var _loop_pattern := RegEx.create_from_string("^for\\s+(\\w+)\\s*(:?)")


class GDSExParameter:
	var name: String = ""
	var type_text: String = ""
	var is_typed_by_the_engine: bool = false


class GDSExExtraction:
	var rejection: GDSExRejection = GDSExRejection.NONE
	var statement_range: GDSExStatementRange.GDSExRange
	var form: GDSExForm = GDSExForm.PLAIN
	var parameters: Array[GDSExParameter] = []
	var output_name: String = ""
	var declares_output: bool = false
	var return_type_text: String = ""
	var is_static: bool = false
	var assignment: GDSExVariableUsage.GDSExAssignment
	var target_statement: GDSExSourceScanner.GDSExStatement

	func is_valid() -> bool:
		return rejection == GDSExRejection.NONE


class GDSExOutputs:
	var names: PackedStringArray = []
	var declared_inside: Dictionary[String, int] = {}

	func add(output_name: String) -> void:
		if not names.has(output_name):
			names.append(output_name)


static func analyze(context: GDSExCodeContext) -> GDSExExtraction:
	var extraction := GDSExExtraction.new()
	var found := GDSExStatementRange.find(context.index, context.lines, context.selection_first_line, context.selection_last_line)
	extraction.statement_range = found
	if not found.is_valid():
		extraction.rejection = GDSExRejection.RANGE
		return extraction
	var index := context.index
	var top_function := GDSExSymbolIndex.find_top_level_function(found.scope_info)
	extraction.is_static = top_function.is_static
	var local_names := GDSExVariableUsage.find_local_names(top_function)
	var statements := found.statements()
	var last := found.last_statement()
	var first_line := found.first_statement().first_line
	var last_line := GDSExStatementRange.last_code_line_of(last)
	var inside := GDSExVariableUsage.find_occurrences(index, statements, local_names)
	var after := GDSExVariableUsage.find_occurrences(index, found.following_statements(), local_names)
	var writes := GDSExVariableUsage.find_writes(statements)
	if found.has_return:
		extraction.form = GDSExForm.RETURN
		extraction.parameters = _parameters(index, inside, first_line, last_line)
		extraction.return_type_text = _returned_type_text(index, found)
	elif not _fits_assignment_form(extraction, index, inside, after, writes, local_names, first_line):
		var outputs := _find_outputs(index, after, writes, null, local_names, first_line, last_line)
		if outputs.names.size() > 1:
			extraction.rejection = GDSExRejection.TOO_MANY_OUTPUTS
			return extraction
		extraction.parameters = _parameters(index, inside, first_line, last_line)
		extraction.return_type_text = GDSExLanguage.VOID_TYPE_NAME
		if outputs.names.size() == 1:
			extraction.form = GDSExForm.OUTPUT
			extraction.output_name = outputs.names[0]
			extraction.declares_output = outputs.declared_inside.has(extraction.output_name)
			var type_line: int = outputs.declared_inside.get(extraction.output_name, first_line)
			extraction.return_type_text = _variable_type_text(index, extraction.output_name, type_line)
			if extraction.declares_output:
				_read_output_declaration(extraction, statements, writes)
	if _loses_an_inferred_type(extraction, inside, after):
		extraction.rejection = GDSExRejection.UNKNOWN_TYPE
	return extraction


static func build_default_plan(context: GDSExCodeContext) -> GDSExEditPlan:
	var extraction := analyze(context)
	return _build_plan(extraction, context, default_function_name(extraction)) if extraction.is_valid() else null


static func build_plan(context: GDSExCodeContext, function_name: String) -> GDSExEditPlan:
	var extraction := analyze(context)
	return _build_plan(extraction, context, function_name) if extraction.is_valid() else null


static func default_function_name(extraction: GDSExExtraction) -> String:
	var function_name := DEFAULT_FUNCTION_NAME
	var number := FIRST_NAME_NUMBER
	while check_function_name(extraction, function_name).is_error():
		function_name = NUMBERED_NAME_TEMPLATE % [DEFAULT_FUNCTION_NAME, number]
		number += 1
	return function_name


static func _build_plan(extraction: GDSExExtraction, context: GDSExCodeContext, function_name: String) -> GDSExEditPlan:
	var found := extraction.statement_range
	var lines := context.lines
	var first_statement_line := found.first_statement().first_line
	var base_indent := GDSExIndentation.leading_whitespace(lines[first_statement_line])
	var snippet := GDSExSnippet.new()
	snippet.add_line(0, signature(extraction, function_name) + HEADER_END)
	_add_body_lines(snippet, extraction, lines, base_indent)
	var call := PackedStringArray()
	for call_line in call_lines(extraction, function_name, lines):
		call.append(base_indent + call_line)
	var line_map := PackedInt32Array()
	line_map.resize(found.last_line - found.first_line + 1)
	line_map.fill(-1)
	line_map[first_statement_line - found.first_line] = found.first_line
	var plan := GDSExEditPlan.new()
	plan.replace_lines(found.first_line, found.last_line, call, line_map)
	plan.line_replacement.caret = Vector2i(0, call[0].length())
	plan.insert(GDSExPlacement.function_by_order(found.scope_info.class_scope, function_name, lines, context.indent_unit), snippet)
	return plan


static func check_function_name(extraction: GDSExExtraction, function_name: String) -> GDSExFunctionNameCheck.GDSExNameCheck:
	var scope_info := extraction.statement_range.scope_info
	var check := GDSExFunctionNameCheck.check_name(scope_info.class_scope, function_name, "")
	if check.is_error():
		return check
	if function_name == CONSTRUCTOR_NAME:
		return GDSExFunctionNameCheck.error(CONSTRUCTOR_MESSAGE)
	if GDSExVariableUsage.find_local_names(GDSExSymbolIndex.find_top_level_function(scope_info)).has(function_name):
		return GDSExFunctionNameCheck.warning(LOCAL_NAME_MESSAGE % function_name)
	if not function_name.begins_with(PRIVATE_PREFIX):
		return GDSExFunctionNameCheck.warning(PUBLIC_NAME_MESSAGE)
	return check


static func signature(extraction: GDSExExtraction, function_name: String) -> String:
	var params := PackedStringArray()
	for parameter in extraction.parameters:
		params.append(parameter.name if parameter.type_text.is_empty() else TYPED_PARAM_TEMPLATE % [parameter.name, parameter.type_text])
	var return_type := "" if extraction.return_type_text.is_empty() else RETURN_TYPE_TEMPLATE % extraction.return_type_text
	return SIGNATURE_TEMPLATE % [STATIC_PREFIX if extraction.is_static else "", function_name, PARAM_SEPARATOR.join(params), return_type]


static func call_lines(extraction: GDSExExtraction, function_name: String, lines: PackedStringArray) -> PackedStringArray:
	var found := extraction.statement_range
	var arguments := PackedStringArray()
	for parameter in extraction.parameters:
		arguments.append(parameter.name)
	var call := CALL_TEMPLATE % [AWAIT_PREFIX if found.has_await else "", function_name, PARAM_SEPARATOR.join(arguments)]
	match extraction.form:
		GDSExForm.RETURN:
			if found.has_value_return:
				return PackedStringArray([RETURN_TEMPLATE % call])
			return PackedStringArray([call, RETURN_STATEMENT]) if found.ends_with_return else PackedStringArray([call])
		GDSExForm.ASSIGNMENT:
			return PackedStringArray([_target_text(extraction, lines) + call])
		GDSExForm.OUTPUT:
			if not extraction.declares_output:
				return PackedStringArray([ASSIGNMENT_TEMPLATE % [extraction.output_name, call]])
			if extraction.assignment == null:
				return PackedStringArray([ASSIGNMENT_TEMPLATE % [extraction.target_statement.code, call]])
			return PackedStringArray([_target_text(extraction, lines) + call])
	return PackedStringArray([call])


static func _add_body_lines(snippet: GDSExSnippet, extraction: GDSExExtraction, lines: PackedStringArray, base_indent: String) -> void:
	var found := extraction.statement_range
	var string_lines: Dictionary[int, bool] = {}
	for statement in found.statements():
		_collect_string_lines(statement, string_lines)
	var returned := extraction.target_statement if extraction.form == GDSExForm.ASSIGNMENT else null
	var value := Vector2i(-1, -1) if returned == null else returned.position_at(extraction.assignment.value_start)
	for line in range(found.first_line, found.last_line + 1):
		var raw := lines[line]
		if line == value.x:
			snippet.add_line(1, RETURN_TEMPLATE % raw.substr(value.y))
		elif returned != null and line >= returned.first_line and line < value.x:
			continue
		elif string_lines.has(line):
			snippet.add_verbatim_line(raw)
		elif raw.strip_edges().is_empty():
			snippet.add_line(0, "")
		else:
			snippet.add_line(1, raw.trim_prefix(base_indent) if raw.begins_with(base_indent) else raw.strip_edges(true, false))
	if extraction.form == GDSExForm.OUTPUT:
		snippet.add_line(1, RETURN_TEMPLATE % extraction.output_name)


static func _collect_string_lines(statement: GDSExSourceScanner.GDSExStatement, string_lines: Dictionary[int, bool]) -> void:
	for line in statement.string_lines:
		string_lines[line] = true
	for block in statement.blocks:
		for inner in block.statements:
			_collect_string_lines(inner, string_lines)


static func _fits_assignment_form(extraction: GDSExExtraction, index: GDSExSymbolIndex.GDSExSymbolIndexData, inside: Array[GDSExVariableUsage.GDSExOccurrence], after: Array[GDSExVariableUsage.GDSExOccurrence], writes: Dictionary[GDSExSourceScanner.GDSExStatement, GDSExVariableUsage.GDSExAssignment], local_names: Dictionary[String, bool], first_line: int) -> bool:
	var last := extraction.statement_range.last_statement()
	var assignment: GDSExVariableUsage.GDSExAssignment = writes.get(last)
	if assignment == null or assignment.statement_start != 0 or not last.blocks.is_empty():
		return false
	var moved: Array[GDSExVariableUsage.GDSExOccurrence] = []
	var kept: Array[GDSExVariableUsage.GDSExOccurrence] = []
	for occurrence in inside:
		if occurrence.statement != last or occurrence.offset >= assignment.value_start:
			moved.append(occurrence)
		elif occurrence.offset < assignment.operator_start:
			kept.append(occurrence)
	kept.append_array(after)
	var inner_last_line := last.first_line - 1
	var outputs := _find_outputs(index, kept, writes, last, local_names, first_line, inner_last_line)
	if not assignment.is_declaration and not assignment.is_compound and assignment.is_plain_target:
		outputs.names.erase(assignment.root_name)
	if not outputs.names.is_empty():
		return false
	extraction.form = GDSExForm.ASSIGNMENT
	extraction.assignment = assignment
	extraction.target_statement = last
	extraction.parameters = _parameters(index, moved, first_line, inner_last_line)
	extraction.return_type_text = assignment.declared_type_text
	if extraction.return_type_text.is_empty():
		extraction.return_type_text = GDSExSymbolIndex.type_to_string(GDSExTypeResolver.resolve_expression_type(last.code.substr(assignment.value_start), GDSExSymbolIndex.get_scope_info_for_line(index, last.first_line)))
	return true


static func _find_outputs(index: GDSExSymbolIndex.GDSExSymbolIndexData, outside: Array[GDSExVariableUsage.GDSExOccurrence], writes: Dictionary[GDSExSourceScanner.GDSExStatement, GDSExVariableUsage.GDSExAssignment], kept_statement: GDSExSourceScanner.GDSExStatement, local_names: Dictionary[String, bool], first_line: int, last_line: int) -> GDSExOutputs:
	var outputs := GDSExOutputs.new()
	for occurrence in outside:
		if _is_declared_inside(occurrence.lookup, first_line, last_line):
			outputs.add(occurrence.name)
			if not outputs.declared_inside.has(occurrence.name):
				outputs.declared_inside[occurrence.name] = occurrence.line
	for statement: GDSExSourceScanner.GDSExStatement in writes:
		var assignment := writes[statement]
		if statement == kept_statement or assignment.is_declaration or not local_names.has(assignment.root_name):
			continue
		var scope_info := GDSExSymbolIndex.get_scope_info_for_line(index, statement.first_line)
		var lookup := GDSExSymbolIndex.find_variable(assignment.root_name, scope_info)
		if not lookup.is_defined or lookup.scope is GDSExSymbolIndex.GDSExClassScope or _is_declared_inside(lookup, first_line, last_line):
			continue
		var is_untyped := lookup.symbol != null and lookup.symbol.is_untyped
		if assignment.is_plain_target or is_untyped or _is_copied_by_value(GDSExTypeResolver.resolve_expression_type(assignment.root_name, scope_info)):
			outputs.add(assignment.root_name)
	return outputs


static func _is_copied_by_value(type: GDSExSymbolIndex.GDSExTypeData) -> bool:
	return type == null or VALUE_TYPES_WITH_FIELDS.has(type.name)


static func _is_declared_inside(lookup: GDSExSymbolIndex.GDSExVariableLookup, first_line: int, last_line: int) -> bool:
	var declaration_line := lookup.scope.start_line if lookup.symbol == null else lookup.symbol.start_line
	return declaration_line >= first_line and declaration_line <= last_line


static func _parameters(index: GDSExSymbolIndex.GDSExSymbolIndexData, occurrences: Array[GDSExVariableUsage.GDSExOccurrence], first_line: int, last_line: int) -> Array[GDSExParameter]:
	var parameters: Array[GDSExParameter] = []
	var names: Dictionary[String, bool] = {}
	for occurrence in occurrences:
		if names.has(occurrence.name) or _is_declared_inside(occurrence.lookup, first_line, last_line):
			continue
		names[occurrence.name] = true
		var parameter := GDSExParameter.new()
		parameter.name = occurrence.name
		var symbol := occurrence.lookup.symbol
		parameter.type_text = "" if symbol != null and symbol.is_untyped else _type_text(index, occurrence.name, occurrence.line)
		parameter.is_typed_by_the_engine = parameter.type_text.is_empty() and symbol != null and not symbol.is_untyped
		parameters.append(parameter)
	return parameters


static func _loses_an_inferred_type(extraction: GDSExExtraction, inside: Array[GDSExVariableUsage.GDSExOccurrence], after: Array[GDSExVariableUsage.GDSExOccurrence]) -> bool:
	var found := extraction.statement_range
	var untyped_names: Dictionary[String, bool] = {}
	for parameter in extraction.parameters:
		if parameter.is_typed_by_the_engine:
			untyped_names[parameter.name] = true
	var kept_statement := extraction.target_statement if extraction.form == GDSExForm.ASSIGNMENT else null
	for statement in found.statements():
		if statement != kept_statement and _breaks_inference(statement, inside, untyped_names):
			return true
	var assignment := extraction.assignment
	if assignment == null or not assignment.is_inferred or not extraction.return_type_text.is_empty():
		return false
	var declared_names: Dictionary[String, bool] = {assignment.root_name: true}
	for statement in found.following_statements():
		if _breaks_inference(statement, after, declared_names):
			return true
	return false


static func _breaks_inference(statement: GDSExSourceScanner.GDSExStatement, occurrences: Array[GDSExVariableUsage.GDSExOccurrence], untyped_names: Dictionary[String, bool]) -> bool:
	if untyped_names.is_empty():
		return false
	var assignment := GDSExVariableUsage.parse_assignment(statement.code)
	if assignment != null and assignment.is_declaration and assignment.is_inferred and _exposes_any(occurrences, statement, assignment.value_start, untyped_names):
		return true
	var loop := _loop_pattern.search(statement.code)
	if loop != null and loop.get_string(2).is_empty() and _exposes_any(occurrences, statement, loop.get_end(1), untyped_names):
		untyped_names[loop.get_string(1)] = true
	for block in statement.blocks:
		for inner in block.statements:
			if _breaks_inference(inner, occurrences, untyped_names):
				return true
	return false


static func _exposes_any(occurrences: Array[GDSExVariableUsage.GDSExOccurrence], statement: GDSExSourceScanner.GDSExStatement, from_offset: int, names: Dictionary[String, bool]) -> bool:
	var groups: GDSExBracketGroups.GDSExGroups = null
	for occurrence in occurrences:
		if occurrence.statement != statement or occurrence.offset < from_offset or not names.has(occurrence.name):
			continue
		if groups == null:
			groups = GDSExBracketGroups.find(statement.code)
		if not _is_inside_a_typed_group(statement.code, groups, occurrence.offset, from_offset):
			return true
	return false


static func _is_inside_a_typed_group(code: String, groups: GDSExBracketGroups.GDSExGroups, offset: int, from_offset: int) -> bool:
	for group in groups.groups:
		if group.open_offset < from_offset or group.open_offset > offset or group.close_offset < offset:
			continue
		if code[group.open_offset] != GROUPING_OPENER or GDSExVariableUsage.is_call_opener(code, group.open_offset):
			return true
	return false


static func _read_output_declaration(extraction: GDSExExtraction, statements: Array[GDSExSourceScanner.GDSExStatement], writes: Dictionary[GDSExSourceScanner.GDSExStatement, GDSExVariableUsage.GDSExAssignment]) -> void:
	for statement in statements:
		var declared_name := GDSExVariableUsage.declared_name(statement.code)
		if declared_name != extraction.output_name:
			continue
		extraction.target_statement = statement
		extraction.assignment = writes.get(statement)
		var declared_type_text := GDSExVariableUsage.declared_type_text(statement.code)
		if not declared_type_text.is_empty():
			extraction.return_type_text = declared_type_text
		return


static func _variable_type_text(index: GDSExSymbolIndex.GDSExSymbolIndexData, variable_name: String, line: int) -> String:
	var scope_info := GDSExSymbolIndex.get_scope_info_for_line(index, line)
	var lookup := GDSExSymbolIndex.find_variable(variable_name, scope_info)
	if lookup.symbol != null and lookup.symbol.is_untyped:
		return ""
	return _type_text(index, variable_name, line)


static func _type_text(index: GDSExSymbolIndex.GDSExSymbolIndexData, expression: String, line: int) -> String:
	var type_text := GDSExSymbolIndex.type_to_string(GDSExTypeResolver.resolve_expression_type(expression, GDSExSymbolIndex.get_scope_info_for_line(index, line)))
	return "" if type_text == GDSExLanguage.VARIANT_TYPE_NAME else type_text


static func _returned_type_text(index: GDSExSymbolIndex.GDSExSymbolIndexData, found: GDSExStatementRange.GDSExRange) -> String:
	if found.function.return_type != null:
		return GDSExSymbolIndex.type_to_string(found.function.return_type)
	if not found.has_value_return:
		return GDSExLanguage.VOID_TYPE_NAME
	var returned_type := ""
	for value_index in found.return_values.size():
		var type_text := _type_text(index, found.return_values[value_index], found.return_lines[value_index])
		if type_text.is_empty() or (not returned_type.is_empty() and type_text != returned_type):
			return ""
		returned_type = type_text
	return returned_type


static func _target_text(extraction: GDSExExtraction, lines: PackedStringArray) -> String:
	var statement := extraction.target_statement
	var assignment := extraction.assignment
	var raw := lines[statement.first_line]
	var indent_length := GDSExIndentation.leading_whitespace(raw).length()
	var operator := statement.position_at(assignment.operator_start)
	var value := statement.position_at(assignment.value_start)
	var target := raw.substr(indent_length, value.y - indent_length) if value.x == statement.first_line else raw.substr(indent_length).strip_edges(false, true) + VALUE_SEPARATOR
	if assignment.is_inferred and extraction.return_type_text.is_empty() and operator.x == statement.first_line:
		target = target.erase(operator.y - indent_length)
	return target
