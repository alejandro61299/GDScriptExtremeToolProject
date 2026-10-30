@tool
extends RefCounted

const GDSExCliSession = preload("res://addons/gdscript_extreme_tool/cli/cli_session.gd")
const GDSExCliTarget = preload("res://addons/gdscript_extreme_tool/cli/cli_target.gd")
const GDSExCliLineMap = preload("res://addons/gdscript_extreme_tool/cli/cli_line_map.gd")
const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExEditPlan = preload("res://addons/gdscript_extreme_tool/editing/edit_plan.gd")
const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExScriptTypeNames = preload("res://addons/gdscript_extreme_tool/analysis/script_type_names.gd")
const GDSExAddExplicitTypeAction = preload("res://addons/gdscript_extreme_tool/actions/add_explicit_type_action.gd")
const GDSExReorderClassMembersAction = preload("res://addons/gdscript_extreme_tool/actions/reorder_class_members_action.gd")
const GDSExFormatClassMembersAction = preload("res://addons/gdscript_extreme_tool/actions/format_class_members_action.gd")
const GDSExGenerateFunctionAction = preload("res://addons/gdscript_extreme_tool/actions/generate_function_action.gd")
const GDSExGenerateLocalVariableAction = preload("res://addons/gdscript_extreme_tool/actions/generate_local_variable_action.gd")
const GDSExGenerateClassVariableAction = preload("res://addons/gdscript_extreme_tool/actions/generate_class_variable_action.gd")
const GDSExActionRegistry = preload("res://addons/gdscript_extreme_tool/actions/action_registry.gd")
const GDSExCodeAction = preload("res://addons/gdscript_extreme_tool/actions/code_action.gd")
const GDSExInitFunction = preload("res://addons/gdscript_extreme_tool/actions/init_function.gd")
const GDSExMemberCategories = preload("res://addons/gdscript_extreme_tool/analysis/member_categories.gd")
const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExExtractFunction = preload("res://addons/gdscript_extreme_tool/actions/extract_function.gd")
const GDSExExtractVariable = preload("res://addons/gdscript_extreme_tool/actions/extract_variable.gd")
const GDSExStatementRange = preload("res://addons/gdscript_extreme_tool/analysis/statement_range.gd")

const TYPES_STEP: String = "types"
const REORDER_STEP: String = "reorder"
const FORMAT_STEP: String = "format"
const TIDY_STEPS: Array[String] = [TYPES_STEP, REORDER_STEP, FORMAT_STEP]
const STEP_SEPARATOR: String = ","
const SUMMARY_SEPARATOR: String = ", "
const TYPED_SUMMARY: String = "typed %d"
const NOTHING_TO_TYPE_SUMMARY: String = "nothing to type"
const REORDERED_SUMMARY: String = "reordered"
const FORMATTED_SUMMARY: String = "formatted"
const UNCHANGED_SUMMARY: String = "unchanged"
const UNTYPED_SUMMARY: String = "%s; untyped %d: %s"
const UNTYPED_ENTRY: String = "%s %d"
const UNTYPED_LIMIT: int = 10
const MORE_ENTRIES: String = "..."
const UNCHANGED_NOTE: String = "%d unchanged"
const NO_SCRIPTS_MESSAGE: String = "No .gd files in %s."
const MISSING_FILE_MESSAGE: String = "%s does not exist."
const OUTSIDE_PROJECT_MESSAGE: String = "%s is outside the project."
const NOT_A_SCRIPT_MESSAGE: String = "%s is not a .gd file."
const UNKNOWN_STEP_MESSAGE: String = "Unknown step '%s' in --only. Use %s."
const NO_CHANGED_SCRIPTS_MESSAGE: String = "No .gd files changed in git."
const NOT_A_REPOSITORY_MESSAGE: String = "The project is not in a git repository, so --changed has nothing to compare."
const NEEDS_A_FILE_MESSAGE: String = "%s needs a .gd file or a folder."
const CLASS_PATH_SEPARATOR: String = "."
const STANDARD_INPUT_PATH: String = "res://stdin.gd"
const SCRIPT_EXTENSION: String = "gd"
const NTH_OPTION: String = "--nth"
const ONLY_OPTION: String = "--only"
const CHANGED_FLAG: String = "--changed"
const NAME_OPTION: String = "--name"
const VARS_OPTION: String = "--vars"
const ALL_VARS_FLAG: String = "--all-vars"
const FUNCTION_COMMAND: String = "function"
const LOCAL_COMMAND: String = "local"
const MEMBER_COMMAND: String = "member"
const CONNECT_COMMAND: String = "connect"
const INIT_COMMAND: String = "init"
const ACTION_SCRIPT_SUFFIX: String = "_action"
const CONNECT_ACTION: String = "generate_connected_function"
const ACTION_COMMANDS: Dictionary[String, String] = {
	"generate_function": FUNCTION_COMMAND,
	"generate_local_variable": LOCAL_COMMAND,
	"generate_class_variable": MEMBER_COMMAND,
	"generate_connected_function": CONNECT_COMMAND,
	"generate_default_init": INIT_COMMAND,
	"generate_custom_init": INIT_COMMAND,
	"add_explicit_type": TYPES_STEP,
	"extract_function": "extract-function",
	"extract_variable": "extract-variable",
	"reorder_class_members": REORDER_STEP,
	"format_class_members": FORMAT_STEP,
}
const NOT_AVAILABLE_MESSAGE: String = "%s does not apply at %s. %s"
const AVAILABLE_HERE_MESSAGE: String = "Available there: %s."
const NOTHING_AVAILABLE_MESSAGE: String = "Nothing applies there."
const AVAILABLE_SUMMARY: String = "%s: %s"
const NOTHING_AVAILABLE_SUMMARY: String = "%s: nothing"
const NEEDS_A_POSITION_MESSAGE: String = "%s needs a position, such as %s:42:name."
const NO_MISSING_FUNCTIONS_SUMMARY: String = "no missing functions"
const FOUND_ELSEWHERE_SUMMARY: String = "%s; %s"
const NO_INIT_VARIABLES_MESSAGE: String = "The class at %s has no private variables. Use --vars a,b or --all-vars."
const UNKNOWN_INIT_VARIABLE_MESSAGE: String = "'%s' is not a variable that init can take. Variables: %s."

const LIST_SEPARATOR: String = ", "
const FORM_OPTION: String = "--form"
const PLACE_OPTION: String = "--place"
const CONSTANT_FLAG: String = "--const"
const STATIC_FLAG: String = "--static"
const PRIVATE_FLAG: String = "--private"
const PUBLIC_FLAG: String = "--public"
const ON_READY_FLAG: String = "--onready"
const EXTRACT_FUNCTION_COMMAND: String = "extract-function"
const EXTRACT_VARIABLE_COMMAND: String = "extract-variable"
const FUNCTION_KEYWORD: String = "func "
const STATIC_PREFIX: String = "static "
const CHANGED_SUMMARY: String = "+%d -%d"
const CALL_OPENER: String = "("
const BODY_SUFFIX: String = "(+%d)"
const NO_FORM_MESSAGE: String = "No --form %s for these lines. Forms here: %s."
const CANNOT_EXTRACT_MESSAGE: String = "extract-function does not apply to %s: %s"
const RANGE_REJECTIONS: Dictionary[String, String] = {
	"NO_SELECTION": "select whole lines, such as player.gd:30-38.",
	"NOT_IN_FUNCTION": "the lines are not inside a function.",
	"PARTIAL_STATEMENT": "the lines cut a statement in two.",
	"DIFFERENT_BLOCKS": "the lines belong to different blocks.",
	"SPLIT_CONDITION": "the lines separate an if from its elif or else.",
	"MATCH_BRANCHES": "the lines are branches of a match.",
	"SHARED_LINE": "another statement shares a line with them.",
	"OUTER_LOOP_JUMP": "they break or continue a loop that stays outside.",
	"EARLY_RETURN": "they return in the middle.",
	"BARE_SUPER": "they call super() without a name, which only works in the original function.",
}
const EXTRACTION_REJECTIONS: Dictionary[String, String] = {
	"TOO_MANY_OUTPUTS": "more than one variable would have to come back.",
	"UNKNOWN_TYPE": "a variable that the rest of the function uses would lose its inferred type.",
}

var session: GDSExCliSession
var standard_input: String = ""
var standard_input_path: String = STANDARD_INPUT_PATH


class GDSExJob:
	var document: GDSExCliSession.GDSExDocument
	var target: GDSExCliTarget.GDSExTarget
	var class_path: String = ""


class GDSExRequest:
	var command: String = ""
	var targets: PackedStringArray = []
	var values: Dictionary[String, String] = {}
	var flags: Dictionary[String, bool] = {}
	var error: String = ""

	func has_flag(flag: String) -> bool:
		return flags.get(flag, false)

	func value(option: String, default_value: String = "") -> String:
		return values.get(option, default_value)

	func nth() -> int:
		return value(NTH_OPTION, "0").to_int()


func _init(command_session: GDSExCliSession) -> void:
	session = command_session


func run_types(request: GDSExRequest) -> void:
	_run_whole_scripts(request, [TYPES_STEP])


func run_reorder(request: GDSExRequest) -> void:
	_run_whole_scripts(request, [REORDER_STEP])


func run_format(request: GDSExRequest) -> void:
	_run_whole_scripts(request, [FORMAT_STEP])


func run_tidy(request: GDSExRequest) -> void:
	var steps: Array[String] = []
	for step in request.value(ONLY_OPTION, STEP_SEPARATOR.join(TIDY_STEPS)).split(STEP_SEPARATOR, false):
		var cleaned := step.strip_edges()
		if not TIDY_STEPS.has(cleaned):
			session.add_error(UNKNOWN_STEP_MESSAGE % [cleaned, STEP_SEPARATOR.join(TIDY_STEPS)])
			return
		if not steps.has(cleaned):
			steps.append(cleaned)
	var ordered: Array[String] = []
	for step in TIDY_STEPS:
		if steps.has(step):
			ordered.append(step)
	_run_whole_scripts(request, ordered)


func run_function(request: GDSExRequest) -> void:
	for written in request.targets:
		var target := GDSExCliTarget.parse(written)
		if target.is_whole_script():
			_generate_missing_functions(target)
			continue
		_run_action_at(target, request, GDSExGenerateFunctionAction.new(), FUNCTION_COMMAND)


func run_local(request: GDSExRequest) -> void:
	for written in request.targets:
		_run_action_at(GDSExCliTarget.parse(written), request, GDSExGenerateLocalVariableAction.new(), LOCAL_COMMAND)


func run_member(request: GDSExRequest) -> void:
	for written in request.targets:
		_run_action_at(GDSExCliTarget.parse(written), request, GDSExGenerateClassVariableAction.new(), MEMBER_COMMAND)


func run_connect(request: GDSExRequest) -> void:
	for written in request.targets:
		_run_action_at(GDSExCliTarget.parse(written), request, registered_action(CONNECT_ACTION), CONNECT_COMMAND)


func run_init(request: GDSExRequest) -> void:
	for written in request.targets:
		var target := GDSExCliTarget.parse(written)
		var document := open_target(target)
		if document == null:
			continue
		var position := GDSExCliTarget.locate(target, document, request.nth())
		if not position.error.is_empty():
			session.add_error(position.error)
			continue
		var editor := _editor_at(document, position, false)
		var context := session.new_context(document, editor)
		editor.free()
		var chosen: Variant = _init_variable_names(context, request, target)
		if chosen == null:
			continue
		var names: PackedStringArray = chosen
		var function_name := request.value(NAME_OPTION, GDSExInitFunction.default_function_name(context))
		var check := GDSExInitFunction.check_function_name(context, function_name, names.size())
		if check.is_error():
			session.add_error(check.message)
			continue
		var change := session.apply(document, GDSExInitFunction.build_plan(context, function_name, names))
		var block := _change_block(change, position.note)
		if block != null and check.level == check.GDSExLevel.WARNING:
			block.warnings.append(check.message)


func run_extract_function(request: GDSExRequest) -> void:
	var target := GDSExCliTarget.parse(request.targets[0])
	var document := open_target(target)
	if document == null:
		return
	if target.is_whole_script():
		session.add_error(NEEDS_A_POSITION_MESSAGE % [EXTRACT_FUNCTION_COMMAND, target.path])
		return
	var position := GDSExCliTarget.locate(target, document, request.nth())
	if not position.error.is_empty():
		session.add_error(position.error)
		return
	var editor := session.new_editor(document)
	editor.select(position.first_line, 0, position.last_line, document.lines[position.last_line].length())
	var context := session.new_context(document, editor)
	editor.free()
	var form := request.value(FORM_OPTION)
	var extraction := GDSExExtractFunction.alternative_with_form(context, form)
	if extraction == null:
		session.add_error(_extraction_failure(context, form, target.written))
		return
	var function_name := request.value(NAME_OPTION, GDSExExtractFunction.default_function_name(extraction))
	var check := GDSExExtractFunction.check_function_name(extraction, function_name)
	if check.is_error():
		session.add_error(check.message)
		return
	var plan := GDSExExtractFunction.build_plan_for(extraction, context, function_name)
	var line_count := document.lines.size()
	var change := session.apply(document, plan)
	if change == null:
		return
	var removed := plan.line_replacement.last_line - plan.line_replacement.first_line + 1
	var summary := CHANGED_SUMMARY % [removed + document.lines.size() - line_count, removed]
	var block := session.add_block(document, summary if position.note.is_empty() else FOUND_ELSEWHERE_SUMMARY % [summary, position.note])
	_show_extracted_function(block, change, plan, function_name)
	if check.level == check.GDSExLevel.WARNING:
		block.warnings.append(check.message)


func run_extract_variable(request: GDSExRequest) -> void:
	var target := GDSExCliTarget.parse(request.targets[0])
	var document := open_target(target)
	if document == null:
		return
	if target.is_whole_script():
		session.add_error(NEEDS_A_POSITION_MESSAGE % [EXTRACT_VARIABLE_COMMAND, target.path])
		return
	var position := GDSExCliTarget.locate(target, document, request.nth())
	if not position.error.is_empty():
		session.add_error(position.error)
		return
	var extraction: GDSExExtractVariable.GDSExExtraction = null
	var context: GDSExCodeContext = null
	for selects in position.selection_attempts():
		var editor := _editor_at(document, position, selects)
		context = session.new_context(document, editor)
		editor.free()
		extraction = GDSExExtractVariable.analyze(context)
		if extraction != null:
			break
	if extraction == null:
		session.add_error(_not_available_message(EXTRACT_VARIABLE_COMMAND, target.written, document, position))
		return
	var requested := _requested_variable_options(request)
	var chosen := GDSExExtractVariable.choice_from_options(extraction, request.value(PLACE_OPTION), requested)
	if not chosen.error.is_empty():
		session.add_error(chosen.error)
		return
	var variable_name := request.value(NAME_OPTION, GDSExExtractVariable.default_name(extraction, chosen.choice))
	var check := GDSExExtractVariable.check_name(extraction, chosen.choice, variable_name)
	if check.is_error():
		session.add_error(check.message)
		return
	var change := session.apply(document, GDSExExtractVariable.build_plan_for(extraction, chosen.choice, variable_name, context.indent_unit))
	var block := _change_block(change, position.note)
	if block == null:
		return
	if check.level == check.GDSExLevel.WARNING:
		block.warnings.append(check.message)
	block.warnings.append_array(GDSExExtractVariable.find_warnings(extraction, chosen.choice))


func run_actions(request: GDSExRequest) -> void:
	for written in request.targets:
		var target := GDSExCliTarget.parse(written)
		var document := open_target(target)
		if document == null:
			continue
		var position := GDSExCliTarget.locate(target, document, request.nth())
		if not position.error.is_empty():
			session.add_error(position.error)
			continue
		var available := _available_commands(document, position)
		var summary := NOTHING_AVAILABLE_SUMMARY % target.written if available.is_empty() else AVAILABLE_SUMMARY % [target.written, LIST_SEPARATOR.join(available)]
		session.add_note(summary)


func registered_action(script_name: String) -> GDSExCodeAction:
	for registered in GDSExActionRegistry.create_actions():
		if _script_name(registered) == script_name:
			return registered
	return null


func open_target(target: GDSExCliTarget.GDSExTarget) -> GDSExCliSession.GDSExDocument:
	if target.is_standard_input():
		return session.documents[standard_input_path] if session.documents.has(standard_input_path) else session.open_virtual(standard_input_path, standard_input)
	var path := session.local_path(target.path)
	if path.is_empty():
		session.add_error(OUTSIDE_PROJECT_MESSAGE % target.path)
		return null
	if path.get_extension() != SCRIPT_EXTENSION:
		session.add_error(NOT_A_SCRIPT_MESSAGE % target.path)
		return null
	var document := session.open(path)
	if document == null:
		session.add_error(MISSING_FILE_MESSAGE % target.path)
	return document


func _run_whole_scripts(request: GDSExRequest, steps: Array[String]) -> void:
	var jobs := _whole_script_jobs(request)
	var unchanged := 0
	for job in jobs:
		var summary := _apply_steps(job.document, steps, job.target, job.class_path)
		if summary.is_empty():
			unchanged += 1
			continue
		session.add_block(job.document, summary)
	if unchanged == 0:
		return
	if jobs.size() == 1:
		session.add_block(jobs[0].document, UNCHANGED_SUMMARY)
	else:
		session.add_note(UNCHANGED_NOTE % unchanged)


func _whole_script_jobs(request: GDSExRequest) -> Array[GDSExJob]:
	var jobs: Array[GDSExJob] = []
	if request.has_flag(CHANGED_FLAG):
		if not session.files.is_git_repository():
			session.add_error(NOT_A_REPOSITORY_MESSAGE)
			return jobs
		var changed := session.files.changed_scripts()
		if changed.is_empty():
			session.add_note(NO_CHANGED_SCRIPTS_MESSAGE)
		for path in changed:
			_add_job(session.open(path), null, "", jobs)
	for written in request.targets:
		var target := GDSExCliTarget.parse(written)
		if not target.is_standard_input() and target.path.get_extension() != SCRIPT_EXTENSION:
			_add_folder_jobs(target.path, jobs)
			continue
		var document := open_target(target)
		if document == null:
			continue
		if target.is_whole_script():
			_add_job(document, null, "", jobs)
			continue
		var position := GDSExCliTarget.locate(target, document, request.nth())
		if not position.error.is_empty():
			session.add_error(position.error)
			continue
		_add_job(document, target, _class_path_at(document, position.line), jobs)
	return jobs


func _add_job(document: GDSExCliSession.GDSExDocument, target: GDSExCliTarget.GDSExTarget, class_path: String, jobs: Array[GDSExJob]) -> void:
	if document == null:
		return
	var job := GDSExJob.new()
	job.document = document
	job.target = target
	job.class_path = class_path
	jobs.append(job)


func _add_folder_jobs(written_folder: String, jobs: Array[GDSExJob]) -> void:
	var folder := session.local_path(written_folder)
	if folder.is_empty():
		session.add_error(OUTSIDE_PROJECT_MESSAGE % written_folder)
		return
	if not session.files.has_folder(folder):
		session.add_error(MISSING_FILE_MESSAGE % written_folder)
		return
	var scripts := session.files.list_scripts(folder)
	if scripts.is_empty():
		session.add_note(NO_SCRIPTS_MESSAGE % written_folder)
	for path in scripts:
		_add_job(session.open(path), null, "", jobs)


func _apply_steps(document: GDSExCliSession.GDSExDocument, steps: Array[String], target: GDSExCliTarget.GDSExTarget, class_path: String) -> String:
	var parts := PackedStringArray()
	var only_one_class := target != null
	for step in steps:
		match step:
			TYPES_STEP:
				var typed := _add_types(document)
				if typed > 0:
					parts.append(TYPED_SUMMARY % typed)
				elif steps.size() == 1:
					parts.append(NOTHING_TO_TYPE_SUMMARY)
			REORDER_STEP:
				if _lay_out(document, REORDER_STEP, class_path, only_one_class):
					parts.append(REORDERED_SUMMARY)
			FORMAT_STEP:
				if _lay_out(document, FORMAT_STEP, class_path, only_one_class):
					parts.append(FORMATTED_SUMMARY)
	var summary := SUMMARY_SEPARATOR.join(parts)
	if steps.has(TYPES_STEP):
		var untyped := _untyped_variables(document)
		if not untyped.is_empty():
			return UNTYPED_SUMMARY % [summary if not summary.is_empty() else UNCHANGED_SUMMARY, untyped.size(), _listed_untyped(untyped)]
		if summary == NOTHING_TO_TYPE_SUMMARY:
			return ""
	return summary


func _add_types(document: GDSExCliSession.GDSExDocument) -> int:
	var editor := session.new_editor(document)
	var context := session.new_context(document, editor)
	var plan := GDSExAddExplicitTypeAction.new().build_plan(context)
	var count := 0 if plan == null else plan.replacements.size()
	session.apply(document, plan, editor)
	editor.free()
	return count


func _lay_out(document: GDSExCliSession.GDSExDocument, step: String, class_path: String, only_one_class: bool) -> bool:
	var changed := false
	var editor := session.new_editor(document)
	var context := session.new_context(document, editor)
	var class_paths := PackedStringArray([class_path]) if only_one_class else _class_paths(context.index.root)
	for path in class_paths:
		var class_scope := _find_class(context.index.root, path)
		if class_scope == null:
			continue
		var plan: GDSExEditPlan
		if step == REORDER_STEP:
			plan = GDSExReorderClassMembersAction.plan_for_class(class_scope, context)
		else:
			plan = GDSExFormatClassMembersAction.plan_for_class(class_scope, context)
		if plan == null or plan.is_empty():
			continue
		var lines_before := document.lines
		session.apply(document, plan, editor)
		if document.lines == lines_before:
			continue
		changed = true
		editor.free()
		editor = session.new_editor(document)
		context = session.new_context(document, editor)
	editor.free()
	return changed


func _class_paths(root: GDSExSymbolIndex.GDSExClassScope) -> PackedStringArray:
	var paths := PackedStringArray([""])
	_collect_class_paths(root, "", paths)
	return paths


func _collect_class_paths(class_scope: GDSExSymbolIndex.GDSExClassScope, prefix: String, paths: PackedStringArray) -> void:
	for inner_name: String in class_scope.inner_classes:
		var path := inner_name if prefix.is_empty() else prefix + CLASS_PATH_SEPARATOR + inner_name
		paths.append(path)
		_collect_class_paths(class_scope.inner_classes[inner_name], path, paths)


func _find_class(root: GDSExSymbolIndex.GDSExClassScope, class_path: String) -> GDSExSymbolIndex.GDSExClassScope:
	var current := root
	for inner_name in class_path.split(CLASS_PATH_SEPARATOR, false):
		current = current.inner_classes.get(inner_name)
		if current == null:
			return null
	return current


func _class_path_at(document: GDSExCliSession.GDSExDocument, line: int) -> String:
	var editor := session.new_editor(document)
	editor.set_caret_line(line)
	var context := session.new_context(document, editor)
	editor.free()
	return GDSExScriptTypeNames.class_path(context.scope_info.class_scope)


func _untyped_variables(document: GDSExCliSession.GDSExDocument) -> Array[GDSExSymbolIndex.GDSExVariableSymbol]:
	var editor := session.new_editor(document)
	var context := session.new_context(document, editor)
	editor.free()
	var untyped: Array[GDSExSymbolIndex.GDSExVariableSymbol] = []
	for symbol in GDSExSymbolIndex.find_variables(context.index.root):
		if symbol.declaration != null and not symbol.is_const and not symbol.declaration.has_type():
			untyped.append(symbol)
	return untyped


func _listed_untyped(untyped: Array[GDSExSymbolIndex.GDSExVariableSymbol]) -> String:
	var entries := PackedStringArray()
	for index in mini(untyped.size(), UNTYPED_LIMIT):
		entries.append(UNTYPED_ENTRY % [untyped[index].name, untyped[index].start_line + 1])
	if untyped.size() > UNTYPED_LIMIT:
		entries.append(MORE_ENTRIES)
	return SUMMARY_SEPARATOR.join(entries)


func _run_action_at(target: GDSExCliTarget.GDSExTarget, request: GDSExRequest, action: GDSExCodeAction, command: String) -> GDSExCliSession.GDSExChange:
	var document := open_target(target)
	if document == null:
		return null
	if target.is_whole_script():
		session.add_error(NEEDS_A_POSITION_MESSAGE % [command, target.path])
		return null
	var position := GDSExCliTarget.locate(target, document, request.nth())
	if not position.error.is_empty():
		session.add_error(position.error)
		return null
	var plan := _plan_at(document, position, action.build_plan)
	if plan == null:
		session.add_error(_not_available_message(command, target.written, document, position))
		return null
	var change := session.apply(document, plan)
	_change_block(change, position.note)
	return change


func _plan_at(document: GDSExCliSession.GDSExDocument, position: GDSExCliTarget.GDSExPosition, builder: Callable) -> GDSExEditPlan:
	for selects in position.selection_attempts():
		var editor := _editor_at(document, position, selects)
		var plan: GDSExEditPlan = builder.call(session.new_context(document, editor))
		editor.free()
		if plan != null and not plan.is_empty():
			return plan
	return null


func _editor_at(document: GDSExCliSession.GDSExDocument, position: GDSExCliTarget.GDSExPosition, selects: bool) -> CodeEdit:
	var editor := session.new_editor(document)
	if selects and position.has_selection():
		editor.select(position.first_line, position.from_column, position.last_line, position.to_column)
	else:
		editor.set_caret_line(position.line)
		editor.set_caret_column(position.from_column)
	return editor


func _change_block(change: GDSExCliSession.GDSExChange, note: String) -> GDSExCliSession.GDSExBlock:
	if change == null:
		return null
	var summary := change.summary()
	var block := session.add_block(change.document, summary if note.is_empty() else FOUND_ELSEWHERE_SUMMARY % [summary, note])
	for line in change.new_lines:
		if not change.document.lines[line].strip_edges().is_empty():
			block.show_line(line)
	return block


func _not_available_message(command: String, written: String, document: GDSExCliSession.GDSExDocument, position: GDSExCliTarget.GDSExPosition) -> String:
	var available := _available_commands(document, position)
	var hint := NOTHING_AVAILABLE_MESSAGE if available.is_empty() else AVAILABLE_HERE_MESSAGE % LIST_SEPARATOR.join(available)
	return NOT_AVAILABLE_MESSAGE % [command, written, hint]


func _available_commands(document: GDSExCliSession.GDSExDocument, position: GDSExCliTarget.GDSExPosition) -> PackedStringArray:
	var commands := PackedStringArray()
	for selects in position.selection_attempts():
		var editor := _editor_at(document, position, selects)
		var context := session.new_context(document, editor)
		editor.free()
		for available in GDSExActionRegistry.find_available(GDSExActionRegistry.create_actions(), context):
			var script_name := _script_name(available.action)
			var command: String = ACTION_COMMANDS.get(script_name, script_name)
			if not commands.has(command):
				commands.append(command)
	return commands


func _generate_missing_functions(target: GDSExCliTarget.GDSExTarget) -> void:
	var document := open_target(target)
	if document == null:
		return
	var positions := _missing_call_positions(document)
	var generated := 0
	var generator := GDSExGenerateFunctionAction.new()
	for index in positions.size():
		var at := positions[index]
		if at.x == GDSExCliLineMap.REMOVED:
			continue
		var position := GDSExCliTarget.GDSExPosition.new()
		position.line = at.x
		position.first_line = at.x
		position.last_line = at.x
		position.from_column = at.y
		position.to_column = at.y
		var change := session.apply(document, _plan_at(document, position, generator.build_plan))
		if change == null:
			continue
		generated += 1
		_change_block(change, "")
		if change.document != document:
			continue
		for later in range(index + 1, positions.size()):
			var line := positions[later].x
			positions[later].x = change.map[line] if line >= 0 and line < change.map.size() else GDSExCliLineMap.REMOVED
	if generated == 0:
		session.add_block(document, NO_MISSING_FUNCTIONS_SUMMARY)


func _missing_call_positions(document: GDSExCliSession.GDSExDocument) -> Array[Vector2i]:
	var editor := session.new_editor(document)
	var context := session.new_context(document, editor)
	editor.free()
	var generator := GDSExGenerateFunctionAction.new()
	var positions: Array[Vector2i] = []
	var statements: Array[GDSExSourceScanner.GDSExStatement] = []
	_collect_statements(context.index.statements, statements)
	for statement in statements:
		var scope_info := GDSExSymbolIndex.get_scope_info_for_line(context.index, statement.first_line)
		for function_target in generator.find_targets(statement.code, scope_info):
			positions.append(statement.position_at(function_target.name_offset))
	return positions


func _collect_statements(statements: Array[GDSExSourceScanner.GDSExStatement], collected: Array[GDSExSourceScanner.GDSExStatement]) -> void:
	for statement in statements:
		collected.append(statement)
		for block in statement.blocks:
			_collect_statements(block.statements, collected)


func _init_variable_names(context: GDSExCodeContext, request: GDSExRequest, target: GDSExCliTarget.GDSExTarget) -> Variant:
	var variables := GDSExInitFunction.find_variables(context)
	var all_names := PackedStringArray()
	for variable in variables:
		all_names.append(variable.name)
	if request.has_flag(ALL_VARS_FLAG):
		return all_names
	if request.values.has(VARS_OPTION):
		var names := PackedStringArray()
		for written_name in request.value(VARS_OPTION).split(STEP_SEPARATOR, false):
			var variable_name := written_name.strip_edges()
			if not all_names.has(variable_name):
				session.add_error(UNKNOWN_INIT_VARIABLE_MESSAGE % [variable_name, LIST_SEPARATOR.join(all_names)])
				return null
			names.append(variable_name)
		return names
	var private_names := GDSExInitFunction.find_variable_names(context, GDSExMemberCategories.PRIVATE_VARIABLES)
	if private_names.is_empty():
		session.add_error(NO_INIT_VARIABLES_MESSAGE % target.written)
		return null
	return private_names


func _script_name(code_action: GDSExCodeAction) -> String:
	return (code_action.get_script() as Script).resource_path.get_file().get_basename().trim_suffix(ACTION_SCRIPT_SUFFIX)


func _extraction_failure(context: GDSExCodeContext, form: String, written: String) -> String:
	var alternatives := GDSExExtractFunction.find_alternatives(context)
	var valid_forms := PackedStringArray()
	for alternative in alternatives:
		if alternative.is_valid():
			valid_forms.append(String(GDSExExtractFunction.GDSExForm.find_key(alternative.form)).to_lower())
	if not valid_forms.is_empty():
		return NO_FORM_MESSAGE % [form, LIST_SEPARATOR.join(valid_forms)]
	var rejected := alternatives[0]
	var reason: String = EXTRACTION_REJECTIONS.get(GDSExExtractFunction.GDSExRejection.find_key(rejected.rejection), "")
	if rejected.rejection == GDSExExtractFunction.GDSExRejection.RANGE:
		reason = RANGE_REJECTIONS.get(GDSExStatementRange.GDSExRejection.find_key(rejected.statement_range.rejection), "")
	return CANNOT_EXTRACT_MESSAGE % [written, reason]


func _show_extracted_function(block: GDSExCliSession.GDSExBlock, change: GDSExCliSession.GDSExChange, plan: GDSExEditPlan, function_name: String) -> void:
	var lines := change.document.lines
	var replacement := plan.line_replacement
	var call_start := change.map[replacement.first_line - 1] + 1
	for offset in replacement.lines.size():
		if not lines[call_start + offset].strip_edges().is_empty():
			block.show_line(call_start + offset)
	for line in lines.size():
		var text := lines[line]
		if not text.strip_edges().begins_with(FUNCTION_KEYWORD + function_name + CALL_OPENER) and not text.strip_edges().begins_with(STATIC_PREFIX + FUNCTION_KEYWORD + function_name + CALL_OPENER):
			continue
		var indent_length := text.length() - text.strip_edges(true, false).length()
		var body_lines := 0
		var next := line + 1
		while next < lines.size():
			var body := lines[next]
			if not body.strip_edges().is_empty():
				if body.length() - body.strip_edges(true, false).length() <= indent_length:
					break
				body_lines += 1
			next += 1
		block.show_line(line, BODY_SUFFIX % body_lines)
		return


func _requested_variable_options(request: GDSExRequest) -> Dictionary[GDSExExtractVariable.GDSExOption, bool]:
	var requested: Dictionary[GDSExExtractVariable.GDSExOption, bool] = {}
	if request.has_flag(CONSTANT_FLAG):
		requested[GDSExExtractVariable.GDSExOption.CONSTANT] = true
	if request.has_flag(STATIC_FLAG):
		requested[GDSExExtractVariable.GDSExOption.STATIC] = true
	if request.has_flag(PRIVATE_FLAG):
		requested[GDSExExtractVariable.GDSExOption.PRIVATE] = true
	if request.has_flag(PUBLIC_FLAG):
		requested[GDSExExtractVariable.GDSExOption.PRIVATE] = false
	if request.has_flag(ON_READY_FLAG):
		requested[GDSExExtractVariable.GDSExOption.ON_READY] = true
	return requested
