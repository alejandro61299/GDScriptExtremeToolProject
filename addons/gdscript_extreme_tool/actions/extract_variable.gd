@tool
extends RefCounted

const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExCallSiteParser = preload("res://addons/gdscript_extreme_tool/analysis/call_site_parser.gd")
const GDSExTypeResolver = preload("res://addons/gdscript_extreme_tool/analysis/type_resolver.gd")
const GDSExVariableUsage = preload("res://addons/gdscript_extreme_tool/analysis/variable_usage.gd")
const GDSExValueFinder = preload("res://addons/gdscript_extreme_tool/analysis/value_finder.gd")
const GDSExValueNames = preload("res://addons/gdscript_extreme_tool/analysis/value_names.gd")
const GDSExValueDependencies = preload("res://addons/gdscript_extreme_tool/analysis/value_dependencies.gd")
const GDSExBuiltinTypes = preload("res://addons/gdscript_extreme_tool/analysis/builtin_types.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")

enum GDSExPlace { BLOCK, FUNCTION, CLASS, SCRIPT }
enum GDSExOption { CONSTANT, STATIC, PRIVATE, ON_READY }
enum GDSExSite { BODY, HEADER, MEMBER, ANNOTATION, ENUM }

const PLACES: Array[GDSExPlace] = [GDSExPlace.BLOCK, GDSExPlace.FUNCTION, GDSExPlace.CLASS, GDSExPlace.SCRIPT]
const OPTIONS: Array[GDSExOption] = [GDSExOption.CONSTANT, GDSExOption.STATIC, GDSExOption.PRIVATE, GDSExOption.ON_READY]
const PLACE_LABELS: Array[String] = ["Block", "Function", "Class", "Script"]
const OPTION_LABELS: Array[String] = ["Constant", "Static", "Private", "On ready"]

const READS_LOOP_MESSAGE: String = "The value reads '%s', which only exists inside the loop."
const READS_BLOCK_MESSAGE: String = "The value reads '%s', which only exists inside its block."
const READS_LAMBDA_MESSAGE: String = "The value reads '%s', which only exists inside the lambda."
const READS_FUNCTION_MESSAGE: String = "The value reads '%s', which only exists inside this function."
const READS_CLASS_MESSAGE: String = "The value reads '%s', which belongs to the class %s."
const WHOLE_LINE_MESSAGE: String = "The value is the whole line."
const ALREADY_A_VARIABLE_MESSAGE: String = "The value already has a name on this line."
const AWAIT_MESSAGE: String = "The value waits with await, which only a function can do."
const CONSTANT_RESULT_MESSAGE: String = "A constant cannot hold the result of '%s'."
const CONSTANT_READ_MESSAGE: String = "A constant cannot read '%s'."
const CONSTANT_ONLY_MESSAGE: String = "Only a constant can be used here."
const SCRIPT_CONSTANT_MESSAGE: String = "A class inside the script can only read the constants of the script."
const STATIC_PLACE_MESSAGE: String = "Only a variable of the class can be static."
const STATIC_READ_MESSAGE: String = "A static variable cannot read '%s', which belongs to the object."
const STATIC_TREE_MESSAGE: String = "A static variable cannot read the scene tree."
const STATIC_FUNCTION_MESSAGE: String = "A static function cannot read a variable of the object."
const PRIVATE_PLACE_MESSAGE: String = "Only a member of a class can be private."
const ON_READY_PLACE_MESSAGE: String = "Only a variable of the class can be @onready."
const ON_READY_NODE_MESSAGE: String = "Only scripts that extend Node have @onready."
const ON_READY_TREE_MESSAGE: String = "The value needs the scene tree, which is not there until the node is ready."
const SOMETIMES_WARNING: String = "Here the value runs only sometimes, or more than once. The variable will compute it once, before this line."
const ORDER_WARNING: String = "'%s' will now run before '%s'."
const LOOP_WARNING: String = "The value will be computed once, before the loop."
const BRANCH_WARNING: String = "The value will be computed even when that branch does not run."
const LAMBDA_WARNING: String = "The value will be computed when the function runs, not when the lambda is called."
const OBJECT_WARNING: String = "The value will be computed once, when the object is created."
const SCRIPT_WARNING: String = "The value will be computed once, when the script is loaded."
const READY_WARNING: String = "The value will be computed once, when the node is ready."

const ANNOTATION_PREFIX: String = "@"
const ENUM_KEYWORD: String = "enum"
const MATCH_KEYWORD: String = "match"
const CONSTANT_KEYWORD: String = "const"
const CALL_TEMPLATE: String = "%s()"
const REPEATED_HEADERS: Array[String] = ["while", "elif"]
const SHORT_CIRCUIT_WORDS: Array[String] = ["and", "or", "else"]
const SHORT_CIRCUIT_SIGNS: Array[String] = ["&&", "||"]
const CONDITION_WORD: String = "if"
const SEPARATOR: String = ","

static var _modifiers_pattern := RegEx.create_from_string("^(?:(?:@\\w+(?:\\([^)]*\\))?|static)\\s+)+")
static var _first_word_pattern := RegEx.create_from_string("^\\w+")
static var _word_pattern := RegEx.create_from_string("\\w+")


class GDSExChoice:
	var place: GDSExPlace = GDSExPlace.FUNCTION
	var is_constant: bool = false
	var is_static: bool = false
	var is_private: bool = false
	var is_on_ready: bool = false
	var has_chosen_privacy: bool = false

	func has(option: GDSExOption) -> bool:
		match option:
			GDSExOption.CONSTANT:
				return is_constant
			GDSExOption.STATIC:
				return is_static
			GDSExOption.PRIVATE:
				return is_private
		return is_on_ready

	func put(option: GDSExOption, is_pressed: bool) -> void:
		match option:
			GDSExOption.CONSTANT:
				is_constant = is_pressed
			GDSExOption.STATIC:
				is_static = is_pressed
			GDSExOption.PRIVATE:
				is_private = is_pressed
			GDSExOption.ON_READY:
				is_on_ready = is_pressed

	func copy() -> GDSExChoice:
		var copied := GDSExChoice.new()
		copied.place = place
		copied.is_constant = is_constant
		copied.is_static = is_static
		copied.is_private = is_private
		copied.is_on_ready = is_on_ready
		copied.has_chosen_privacy = has_chosen_privacy
		return copied


class GDSExState:
	var is_shown: bool = true
	var is_forced: bool = false
	var reason: String = ""

	func is_enabled() -> bool:
		return is_shown and not is_forced and reason.is_empty()

	func is_usable() -> bool:
		return is_shown and reason.is_empty()


class GDSExExtraction:
	var value: GDSExValueFinder.GDSExValue
	var scope_info: GDSExSymbolIndex.GDSExScopeInfo
	var type: GDSExSymbolIndex.GDSExTypeData
	var proposed_name: String = ""
	var value_text: String = ""
	var dependencies: GDSExValueDependencies.GDSExDependencies
	var site: GDSExSite = GDSExSite.BODY
	var top_function: GDSExSymbolIndex.GDSExFunctionScope
	var block_anchor: GDSExSourceScanner.GDSExStatement
	var function_anchor: GDSExSourceScanner.GDSExStatement
	var member_statement: GDSExSourceScanner.GDSExStatement
	var is_whole_statement: bool = false
	var is_whole_declared_value: bool = false
	var is_whole_constant_value: bool = false

	func is_nested() -> bool:
		return block_anchor != function_anchor

	func needs_a_constant() -> bool:
		return site == GDSExSite.ANNOTATION or site == GDSExSite.ENUM

	func is_in_a_static_function() -> bool:
		return top_function != null and top_function.is_static


static func analyze(context: GDSExCodeContext) -> GDSExExtraction:
	return analyze_selection(context.index, context.lines, context.statement, context.selection_from, context.selection_to)


static func analyze_selection(index: GDSExSymbolIndex.GDSExSymbolIndexData, lines: PackedStringArray, statement: GDSExSourceScanner.GDSExStatement, selection_from: int, selection_to: int) -> GDSExExtraction:
	var value := GDSExValueFinder.find(statement, selection_from, selection_to)
	if value == null:
		return null
	var scope_info := GDSExSymbolIndex.get_scope_info_for_line(index, value.first_position().x)
	var resolved := GDSExTypeResolver.resolve_expression(value.code, scope_info)
	if resolved.returns_nothing or resolved.is_class_reference:
		return null
	var extraction := GDSExExtraction.new()
	extraction.value = value
	extraction.scope_info = scope_info
	extraction.type = null if resolved.type == null or resolved.is_preloaded or resolved.type.name == GDSExLanguage.VARIANT_TYPE_NAME else resolved.type
	extraction.value_text = GDSExValueFinder.source_text(value, lines)
	extraction.proposed_name = GDSExValueNames.propose(value, lines, scope_info)
	extraction.dependencies = GDSExValueDependencies.find(value, scope_info)
	_find_site(extraction, index)
	return extraction if default_choice(extraction) != null else null


static func place_state(extraction: GDSExExtraction, place: GDSExPlace) -> GDSExState:
	var state := GDSExState.new()
	var dependencies := extraction.dependencies
	match place:
		GDSExPlace.BLOCK:
			state.is_shown = extraction.site == GDSExSite.BODY and extraction.is_nested()
			state.reason = _nearest_place_reason(extraction)
		GDSExPlace.FUNCTION:
			state.is_shown = extraction.site == GDSExSite.BODY
			if not extraction.is_nested():
				state.reason = _nearest_place_reason(extraction)
			elif not dependencies.block_name.is_empty():
				state.reason = _block_message(dependencies.block_home) % dependencies.block_name
			elif extraction.is_whole_statement:
				state.reason = WHOLE_LINE_MESSAGE
		GDSExPlace.CLASS:
			state.reason = _member_place_reason(extraction)
			if state.reason.is_empty() and extraction.needs_a_constant() and not dependencies.is_constant():
				state.reason = _constant_reason(dependencies)
		GDSExPlace.SCRIPT:
			state.is_shown = extraction.scope_info.class_scope.parent != null
			state.reason = _member_place_reason(extraction)
			if state.reason.is_empty() and not dependencies.is_constant():
				state.reason = _constant_reason(dependencies)
			elif state.reason.is_empty() and not dependencies.inner_name.is_empty():
				state.reason = READS_CLASS_MESSAGE % [dependencies.inner_name, extraction.scope_info.class_scope.name]
	return state


static func option_state(extraction: GDSExExtraction, choice: GDSExChoice, option: GDSExOption) -> GDSExState:
	var state := GDSExState.new()
	var dependencies := extraction.dependencies
	var is_in_the_class := choice.place == GDSExPlace.CLASS
	match option:
		GDSExOption.CONSTANT:
			if not dependencies.is_constant():
				state.reason = _constant_reason(dependencies)
			elif choice.place == GDSExPlace.SCRIPT:
				state.is_forced = true
				state.reason = SCRIPT_CONSTANT_MESSAGE
			elif extraction.needs_a_constant():
				state.is_forced = true
				state.reason = CONSTANT_ONLY_MESSAGE
		GDSExOption.STATIC:
			if not is_in_the_class:
				state.reason = STATIC_PLACE_MESSAGE
			elif extraction.needs_a_constant():
				state.reason = CONSTANT_ONLY_MESSAGE
			elif dependencies.needs_tree:
				state.reason = STATIC_TREE_MESSAGE
			elif not dependencies.member_name.is_empty():
				state.reason = STATIC_READ_MESSAGE % dependencies.member_name
			elif extraction.is_in_a_static_function() and not choice.is_constant:
				state.is_forced = true
				state.reason = STATIC_FUNCTION_MESSAGE
		GDSExOption.PRIVATE:
			if not is_in_the_class and choice.place != GDSExPlace.SCRIPT:
				state.reason = PRIVATE_PLACE_MESSAGE
		GDSExOption.ON_READY:
			if not is_in_the_class:
				state.reason = ON_READY_PLACE_MESSAGE
			elif not _extends_node(extraction.scope_info.class_scope):
				state.reason = ON_READY_NODE_MESSAGE
			elif extraction.needs_a_constant():
				state.reason = CONSTANT_ONLY_MESSAGE
			elif extraction.is_in_a_static_function():
				state.reason = STATIC_FUNCTION_MESSAGE
			elif dependencies.needs_tree:
				state.is_forced = true
				state.reason = ON_READY_TREE_MESSAGE
	return state


static func default_choice(extraction: GDSExExtraction) -> GDSExChoice:
	for place in PLACES:
		if place_state(extraction, place).is_usable():
			return choice_for_place(extraction, place, GDSExChoice.new())
	return null


static func choice_for_place(extraction: GDSExExtraction, place: GDSExPlace, previous: GDSExChoice) -> GDSExChoice:
	var choice := previous.copy()
	choice.place = place
	return normalized(extraction, choice)


static func choice_with_option(extraction: GDSExExtraction, previous: GDSExChoice, option: GDSExOption, is_pressed: bool) -> GDSExChoice:
	var choice := previous.copy()
	choice.put(option, is_pressed)
	if option == GDSExOption.PRIVATE:
		choice.has_chosen_privacy = true
	if is_pressed and option == GDSExOption.CONSTANT:
		choice.is_static = false
		choice.is_on_ready = false
	elif is_pressed and option == GDSExOption.STATIC:
		choice.is_constant = false
		choice.is_on_ready = false
	elif is_pressed and option == GDSExOption.ON_READY:
		choice.is_constant = false
		choice.is_static = false
	return normalized(extraction, choice)


static func normalized(extraction: GDSExExtraction, choice: GDSExChoice) -> GDSExChoice:
	var result := choice.copy()
	for option in OPTIONS:
		var state := option_state(extraction, result, option)
		if state.is_forced:
			result.put(option, true)
		elif not state.reason.is_empty():
			result.put(option, false)
	if result.is_constant:
		result.is_static = false
		result.is_on_ready = false
	if result.is_on_ready:
		result.is_static = false
	if not result.has_chosen_privacy:
		result.is_private = result.place == GDSExPlace.CLASS and not result.is_constant
	return result


static func find_warnings(extraction: GDSExExtraction, choice: GDSExChoice) -> PackedStringArray:
	var warnings := PackedStringArray()
	if extraction.dependencies.is_constant():
		return warnings
	match choice.place:
		GDSExPlace.BLOCK:
			_add_position_warnings(extraction, warnings)
		GDSExPlace.FUNCTION:
			if extraction.is_nested():
				warnings.append(_leaving_warning(extraction))
			else:
				_add_position_warnings(extraction, warnings)
		GDSExPlace.CLASS:
			warnings.append(READY_WARNING if choice.is_on_ready else SCRIPT_WARNING if choice.is_static else OBJECT_WARNING)
	return warnings


static func _find_site(extraction: GDSExExtraction, index: GDSExSymbolIndex.GDSExSymbolIndexData) -> void:
	var value := extraction.value
	var code := value.statement.code
	var modifiers := _modifiers_pattern.search(code)
	var modifiers_end := 0 if modifiers == null else modifiers.get_end()
	var path := _find_path(index.statements, value.statement)
	extraction.top_function = GDSExSymbolIndex.find_top_level_function(extraction.scope_info)
	extraction.is_whole_statement = value.is_whole_statement()
	extraction.member_statement = null if path.is_empty() else path[0]
	_read_declaration(extraction, code, modifiers_end)
	var first_word := _first_word_pattern.search(code.substr(modifiers_end))
	if code.begins_with(ANNOTATION_PREFIX) and (modifiers == null or value.end <= modifiers_end):
		extraction.site = GDSExSite.ANNOTATION
		return
	if first_word != null and first_word.get_string() == ENUM_KEYWORD:
		extraction.site = GDSExSite.ENUM
		return
	if extraction.top_function == null:
		extraction.site = GDSExSite.MEMBER
		return
	var function_index := -1
	for path_index in path.size():
		if path[path_index].first_line == extraction.top_function.start_line:
			function_index = path_index
	if function_index == -1 or function_index == path.size() - 1:
		extraction.site = GDSExSite.HEADER
		return
	extraction.site = GDSExSite.BODY
	extraction.function_anchor = path[function_index + 1]
	var anchor_index := path.size() - 1
	while anchor_index > function_index + 1 and _starts_with(path[anchor_index - 1].code, MATCH_KEYWORD):
		anchor_index -= 1
	extraction.block_anchor = path[anchor_index]
	if extraction.block_anchor != value.statement:
		extraction.is_whole_statement = false
		extraction.is_whole_declared_value = false


static func _read_declaration(extraction: GDSExExtraction, code: String, modifiers_end: int) -> void:
	var assignment := GDSExVariableUsage.parse_assignment(code.substr(modifiers_end))
	if assignment == null or not assignment.is_declaration or assignment.statement_start != 0:
		return
	if assignment.value_start + modifiers_end != extraction.value.start or extraction.value.end != code.length():
		return
	extraction.is_whole_declared_value = true
	extraction.is_whole_constant_value = assignment.keyword == CONSTANT_KEYWORD


static func _find_path(statements: Array[GDSExSourceScanner.GDSExStatement], target: GDSExSourceScanner.GDSExStatement) -> Array[GDSExSourceScanner.GDSExStatement]:
	for statement in statements:
		if statement == target:
			return [statement]
		if target.first_line < statement.first_line or target.first_line > statement.last_line:
			continue
		for block in statement.blocks:
			var inner := _find_path(block.statements, target)
			if not inner.is_empty():
				inner.insert(0, statement)
				return inner
	return []


static func _nearest_place_reason(extraction: GDSExExtraction) -> String:
	if not extraction.dependencies.lambda_name.is_empty():
		return READS_LAMBDA_MESSAGE % extraction.dependencies.lambda_name
	return ALREADY_A_VARIABLE_MESSAGE if extraction.is_whole_declared_value else ""


static func _member_place_reason(extraction: GDSExExtraction) -> String:
	var dependencies := extraction.dependencies
	if not dependencies.lambda_name.is_empty():
		return READS_LAMBDA_MESSAGE % dependencies.lambda_name
	if not dependencies.local_name.is_empty():
		return READS_FUNCTION_MESSAGE % dependencies.local_name
	if dependencies.has_await:
		return AWAIT_MESSAGE
	if extraction.is_whole_statement and extraction.site == GDSExSite.BODY:
		return WHOLE_LINE_MESSAGE
	if extraction.is_whole_constant_value and extraction.site == GDSExSite.MEMBER:
		return ALREADY_A_VARIABLE_MESSAGE
	return ""


static func _block_message(home: GDSExValueDependencies.GDSExDependencies.GDSExHome) -> String:
	match home:
		GDSExValueDependencies.GDSExDependencies.GDSExHome.LOOP:
			return READS_LOOP_MESSAGE
		GDSExValueDependencies.GDSExDependencies.GDSExHome.LAMBDA:
			return READS_LAMBDA_MESSAGE
	return READS_BLOCK_MESSAGE


static func _constant_reason(dependencies: GDSExValueDependencies.GDSExDependencies) -> String:
	return (CONSTANT_RESULT_MESSAGE if dependencies.blocker_is_a_call else CONSTANT_READ_MESSAGE) % dependencies.blocker


static func _extends_node(class_scope: GDSExSymbolIndex.GDSExClassScope) -> bool:
	var base_type := GDSExTypeResolver.engine_base_type(class_scope)
	return base_type == GDSExLanguage.NODE_TYPE_NAME or (ClassDB.class_exists(base_type) and ClassDB.is_parent_class(base_type, GDSExLanguage.NODE_TYPE_NAME))


static func _starts_with(code: String, keyword: String) -> bool:
	var first_word := _first_word_pattern.search(code)
	return first_word != null and first_word.get_string() == keyword


static func _leaving_warning(extraction: GDSExExtraction) -> String:
	var leaves_a_lambda := false
	var scope := extraction.scope_info.scope
	while scope != null and scope != extraction.top_function:
		var block := scope as GDSExSymbolIndex.GDSExBlockScope
		if block != null and (block.kind == GDSExSymbolIndex.GDSExBlockScope.GDSExKind.FOR or block.kind == GDSExSymbolIndex.GDSExBlockScope.GDSExKind.WHILE):
			return LOOP_WARNING
		leaves_a_lambda = leaves_a_lambda or scope is GDSExSymbolIndex.GDSExFunctionScope
		scope = scope.parent
	return LAMBDA_WARNING if leaves_a_lambda else BRANCH_WARNING


static func _add_position_warnings(extraction: GDSExExtraction, warnings: PackedStringArray) -> void:
	var value := extraction.value
	var code := value.statement.code
	var segment_start := _find_segment_start(code, value.start)
	if segment_start == -1 or _is_inside_an_inline_lambda(value) or _is_short_circuited(code, segment_start, value):
		warnings.append(SOMETIMES_WARNING)
		return
	for call in GDSExCallSiteParser.parse(code):
		if call.expression_offset < segment_start or call.close_offset >= value.start:
			continue
		if call.receiver.is_empty() and (GDSExBuiltinTypes.MATH_FUNCTIONS.has(call.name) or GDSExLanguage.is_builtin_type(call.name)):
			continue
		var value_label := CALL_TEMPLATE % value.call.name if value.call != null else value.code
		warnings.append(ORDER_WARNING % [value_label, CALL_TEMPLATE % call.name])
		return


static func _find_segment_start(code: String, value_start: int) -> int:
	var start := 0
	var is_in_a_body := false
	var header := _first_word_pattern.search(code)
	if header != null and GDSExVariableUsage.INLINE_BLOCK_KEYWORDS.has(header.get_string()) and code.ends_with(GDSExSourceScanner.BLOCK_OPENER):
		return -1 if REPEATED_HEADERS.has(header.get_string()) else 0
	while true:
		var word := _first_word_pattern.search(code.substr(start))
		if word == null or not GDSExVariableUsage.INLINE_BLOCK_KEYWORDS.has(word.get_string()):
			return -1 if is_in_a_body else start
		var opener := GDSExSymbolIndex.find_top_level(code, GDSExSourceScanner.BLOCK_OPENER, start)
		while opener != -1 and code.substr(opener + 1, 1) == "=":
			opener = GDSExSymbolIndex.find_top_level(code, GDSExSourceScanner.BLOCK_OPENER, opener + 1)
		if opener == -1 or value_start < opener:
			return -1 if is_in_a_body or REPEATED_HEADERS.has(word.get_string()) else start
		start = GDSExSourceScanner.skip_spaces(code, opener + 1)
		is_in_a_body = true
	return start


static func _is_inside_an_inline_lambda(value: GDSExValueFinder.GDSExValue) -> bool:
	for lambda in GDSExVariableUsage.find_lambdas(value.statement):
		if value.start > lambda.close_offset and value.start < lambda.end_offset:
			return true
	return false


static func _is_short_circuited(code: String, segment_start: int, value: GDSExValueFinder.GDSExValue) -> bool:
	if _finds_word(code, value.start - 1, segment_start - 1, -1, SHORT_CIRCUIT_WORDS, SHORT_CIRCUIT_SIGNS):
		return true
	return _finds_word(code, value.end, code.length(), 1, [CONDITION_WORD], [])


static func _finds_word(code: String, from: int, to: int, step: int, words: Array[String], signs: Array[String]) -> bool:
	var depth := 0
	var blocked_depth := 1
	var index := from
	while index != to:
		var character := code[index]
		var opens := GDSExSourceScanner.OPENING_BRACKETS.contains(character)
		var closes := GDSExSourceScanner.CLOSING_BRACKETS.contains(character)
		if (opens and step == -1) or (closes and step == 1):
			depth -= 1
		elif opens or closes:
			depth += 1
		elif character == SEPARATOR and depth <= 0:
			blocked_depth = depth
		elif depth <= 0 and depth < blocked_depth:
			for sign in signs:
				if code.substr(index - sign.length() + 1 if step == -1 else index, sign.length()) == sign:
					return true
			if GDSExSourceScanner.is_identifier_character(character) and _is_one_of(code, index, step, words):
				return true
		index += step
	return false


static func _is_one_of(code: String, index: int, step: int, words: Array[String]) -> bool:
	var start := index
	var end := index + 1
	while start > 0 and GDSExSourceScanner.is_identifier_character(code[start - 1]):
		start -= 1
	while end < code.length() and GDSExSourceScanner.is_identifier_character(code[end]):
		end += 1
	if (step == -1 and index != end - 1) or (step == 1 and index != start):
		return false
	return words.has(code.substr(start, end - start)) and (start == 0 or code[start - 1] != ".")
