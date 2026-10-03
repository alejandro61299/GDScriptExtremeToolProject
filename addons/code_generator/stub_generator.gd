@tool
extends RefCounted

const SymbolIndex = preload("res://addons/code_generator/analysis/symbol_index.gd")
const SymbolIndexBuilder = preload("res://addons/code_generator/analysis/symbol_index_builder.gd")
const SourceScanner = preload("res://addons/code_generator/analysis/source_scanner.gd")
const CallSiteParser = preload("res://addons/code_generator/analysis/call_site_parser.gd")
const TypeResolver = preload("res://addons/code_generator/analysis/type_resolver.gd")
const Language = preload("res://addons/code_generator/analysis/language.gd")
const Settings = preload("res://addons/code_generator/code_generator_settings.gd")
const Snippet = preload("res://addons/code_generator/editing/snippet.gd")
const EditPlan = preload("res://addons/code_generator/editing/edit_plan.gd")
const Placement = preload("res://addons/code_generator/editing/placement.gd")
const EditApplier = preload("res://addons/code_generator/editing/edit_applier.gd")
const Indentation = preload("res://addons/code_generator/editing/indentation.gd")

const UNNAMED_ARGUMENT_KEYWORDS : Array[String] = ["null", "true", "false", "self"]
const SELF_ACCESS : String = "self."
const NAME_PLACEHOLDER : String = "{name}"
const METHOD_HEADER_TEMPLATE : String = "%sfunc %s(%s) -> %s:"
const STATIC_PREFIX : String = "static "
const TYPED_PARAM_TEMPLATE : String = "%s: %s"
const PARAM_SEPARATOR : String = ", "
const RETURN_TEMPLATE : String = "return %s"
const EMPTY_BODY : String = "pass"


class Target:
	var name: String = ""
	var name_offset: int = 0
	var range_start: int = 0
	var range_end: int = 0
	var target_class: SymbolIndex.ClassScope
	var is_static: bool = false
	var call: CallSiteParser.CallSite
	var signal_member: TypeResolver.Member

	func name_end() -> int:
		return name_offset + name.length()


class MethodSignature:
	var name: String = ""
	var is_static: bool = false
	var param_names: PackedStringArray = []
	var param_types: Array[SymbolIndex.TypeData] = []
	var return_type: SymbolIndex.TypeData


func generate_stub(editor: CodeEdit) -> void:
	if editor == null:
		return
	var lines := editor.text.split("\n")
	var index := SymbolIndexBuilder.build(lines)
	var caret_line := editor.get_caret_line()
	var statement := SourceScanner.find_statement_at(index.statements, caret_line)
	if statement == null:
		return
	var scope_info := SymbolIndex.get_scope_info_for_line(index, caret_line)
	var target := _choose_target(_find_targets(statement.code, scope_info), _selection_range(editor, statement))
	if target == null:
		return
	var signature := _build_signature(target, statement.code, scope_info)
	var indent_unit := Indentation.detect_unit(lines, Indentation.editor_unit(editor))
	var plan := EditPlan.new()
	plan.insert(Placement.new_method(target.target_class, scope_info, lines, indent_unit), _build_snippet(signature))
	EditApplier.apply(editor, plan)


func _selection_range(editor: CodeEdit, statement: SourceScanner.Statement) -> Vector2i:
	var caret := statement.offset_at(editor.get_caret_line(), editor.get_caret_column())
	if not editor.has_selection():
		return Vector2i(caret, caret)
	var from := statement.offset_at(editor.get_selection_from_line(), editor.get_selection_from_column())
	var to := statement.offset_at(editor.get_selection_to_line(), editor.get_selection_to_column())
	if from == -1 or to == -1:
		return Vector2i(caret, caret)
	return Vector2i(from, to)


func _find_targets(code: String, scope_info: SymbolIndex.ScopeInfo) -> Array[Target]:
	var targets: Array[Target] = []
	for call in CallSiteParser.parse(code):
		var call_target := _call_target(call, scope_info)
		if call_target != null:
			targets.append(call_target)
		var callback_target := _callback_target(call, scope_info)
		if callback_target != null:
			targets.append(callback_target)
	return targets


func _call_target(call: CallSiteParser.CallSite, scope_info: SymbolIndex.ScopeInfo) -> Target:
	if call.name == Language.CONSTRUCTOR_NAME or call.receiver == Language.SUPER_KEYWORD:
		return null
	var target := Target.new()
	target.call = call
	target.name = call.name
	target.name_offset = call.name_offset
	target.range_start = call.expression_offset
	target.range_end = call.expression_end()
	if call.receiver.is_empty():
		if TypeResolver.is_function_defined(call.name, scope_info) or SymbolIndex.find_variable(call.name, scope_info).is_defined:
			return null
		var caller := SymbolIndex.find_top_level_function(scope_info)
		target.target_class = scope_info.class_scope
		target.is_static = caller != null and caller.is_static
		return target
	var receiver := TypeResolver.resolve_expression(call.receiver, scope_info)
	if receiver.class_scope == null or TypeResolver.find_class_member(receiver.class_scope, call.name) != null:
		return null
	target.target_class = receiver.class_scope
	target.is_static = receiver.is_class_reference
	return target


func _callback_target(call: CallSiteParser.CallSite, scope_info: SymbolIndex.ScopeInfo) -> Target:
	if call.name != TypeResolver.CONNECT_METHOD or call.receiver.is_empty() or call.arguments.is_empty():
		return null
	var argument := call.arguments[0]
	var callback_name := argument.text.trim_prefix(SELF_ACCESS)
	if not TypeResolver.is_identifier(callback_name):
		return null
	if TypeResolver.is_function_defined(callback_name, scope_info) or SymbolIndex.find_variable(callback_name, scope_info).is_defined:
		return null
	var signal_member := TypeResolver.resolve_signal(call.receiver, scope_info)
	if signal_member == null:
		return null
	var target := Target.new()
	target.name = callback_name
	target.name_offset = argument.offset + argument.length - callback_name.length()
	target.range_start = target.name_offset
	target.range_end = target.name_end()
	target.target_class = scope_info.class_scope
	target.signal_member = signal_member
	return target


func _choose_target(targets: Array[Target], selection: Vector2i) -> Target:
	if selection.x != selection.y:
		var selected := targets.filter(func(target: Target) -> bool: return target.name_offset < selection.y and target.name_end() > selection.x)
		return selected[0] if selected.size() == 1 else null
	for target in targets:
		if selection.x >= target.name_offset and selection.x <= target.name_end():
			return target
	if targets.size() == 1:
		return targets[0]
	var enclosing: Target = null
	for target in targets:
		if selection.x < target.range_start or selection.x > target.range_end:
			continue
		if enclosing == null or target.range_start > enclosing.range_start:
			enclosing = target
	return enclosing


func _build_signature(target: Target, code: String, scope_info: SymbolIndex.ScopeInfo) -> MethodSignature:
	var signature := MethodSignature.new()
	signature.name = target.name
	signature.is_static = target.is_static
	if target.signal_member != null:
		for index in target.signal_member.param_names.size():
			_add_param(signature, target.signal_member.param_names[index], target.signal_member.param_types[index])
		signature.return_type = SymbolIndex.make_type(Language.VOID_TYPE_NAME)
		return signature
	for argument in target.call.arguments:
		_add_param(signature, argument.text, TypeResolver.resolve_expression_type(argument.text, scope_info))
	signature.return_type = TypeResolver.expected_type(code, target.call, scope_info)
	return signature


func _add_param(signature: MethodSignature, source_name: String, type: SymbolIndex.TypeData) -> void:
	var param_name := _format_param_name(source_name)
	if param_name.is_empty() or signature.param_names.has(param_name):
		param_name = Settings.FALLBACK_PARAM_FORMAT.format({"index": signature.param_names.size()})
	signature.param_names.append(param_name)
	signature.param_types.append(type)


func _format_param_name(source_name: String) -> String:
	if not TypeResolver.is_identifier(source_name) or UNNAMED_ARGUMENT_KEYWORDS.has(source_name):
		return ""
	var base_name := source_name.to_lower().lstrip("_")
	if base_name.is_empty():
		return ""
	if _matches_param_format(base_name):
		return base_name
	return Settings.GENERATED_PARAM_FORMAT.format({"name": base_name})


func _matches_param_format(param_name: String) -> bool:
	var affixes := Settings.GENERATED_PARAM_FORMAT.split(NAME_PLACEHOLDER)
	var prefix := affixes[0]
	var suffix := affixes[1] if affixes.size() > 1 else ""
	if prefix.is_empty() and suffix.is_empty():
		return false
	if param_name.length() <= prefix.length() + suffix.length():
		return false
	return param_name.begins_with(prefix) and param_name.ends_with(suffix)


func _build_snippet(signature: MethodSignature) -> Snippet:
	var params := PackedStringArray()
	for index in signature.param_names.size():
		var type_text := SymbolIndex.type_to_string(signature.param_types[index])
		var param_name := signature.param_names[index]
		params.append(param_name if type_text.is_empty() else TYPED_PARAM_TEMPLATE % [param_name, type_text])
	var default_value := TypeResolver.default_value_text(signature.return_type)
	var snippet := Snippet.new()
	snippet.add_line(0, METHOD_HEADER_TEMPLATE % [
		STATIC_PREFIX if signature.is_static else "",
		signature.name,
		PARAM_SEPARATOR.join(params),
		SymbolIndex.type_to_string(signature.return_type),
	])
	snippet.add_line(1, EMPTY_BODY if default_value.is_empty() else RETURN_TEMPLATE % default_value)
	snippet.select_line(1)
	return snippet
