extends SceneTree

const GDSExActionRegistry = preload("res://addons/gdscript_extreme_tool/actions/action_registry.gd")
const GDSExCodeAction = preload("res://addons/gdscript_extreme_tool/actions/code_action.gd")
const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExGenerateFunctionAction = preload("res://addons/gdscript_extreme_tool/actions/generate_function_action.gd")
const GDSExVariableAction = preload("res://addons/gdscript_extreme_tool/actions/variable_action.gd")
const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSymbolIndexBuilder = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index_builder.gd")
const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExSnippet = preload("res://addons/gdscript_extreme_tool/editing/snippet.gd")
const GDSExEditPlan = preload("res://addons/gdscript_extreme_tool/editing/edit_plan.gd")
const GDSExEditApplier = preload("res://addons/gdscript_extreme_tool/editing/edit_applier.gd")
const GDSExPluginProjectSettings = preload("res://addons/gdscript_extreme_tool/plugin_project_settings.gd")
const GDSExCodeActionsPopup = preload("res://addons/gdscript_extreme_tool/code_actions_popup.gd")
const GDSExInitFunction = preload("res://addons/gdscript_extreme_tool/actions/init_function.gd")
const GDSExGenerateDefaultInitAction = preload("res://addons/gdscript_extreme_tool/actions/generate_default_init_action.gd")
const GDSExGenerateCustomInitAction = preload("res://addons/gdscript_extreme_tool/actions/generate_custom_init_action.gd")
const GDSExInitFunctionDialog = preload("res://addons/gdscript_extreme_tool/init_function_dialog.gd")
const GDSExFunctionNameDialog = preload("res://addons/gdscript_extreme_tool/function_name_dialog.gd")
const GDSExExtractFunctionDialog = preload("res://addons/gdscript_extreme_tool/extract_function_dialog.gd")
const GDSExExtractFunctionAction = preload("res://addons/gdscript_extreme_tool/actions/extract_function_action.gd")
const GDSExMemberCategories = preload("res://addons/gdscript_extreme_tool/analysis/member_categories.gd")
const GDSExStatementRange = preload("res://addons/gdscript_extreme_tool/analysis/statement_range.gd")
const GDSExExtractFunction = preload("res://addons/gdscript_extreme_tool/actions/extract_function.gd")
const GDSExScriptLibrary = preload("res://addons/gdscript_extreme_tool/analysis/script_library.gd")

const CASES_ROOT: String = "res://tests/cases"
const CASE_EXTENSION: String = "txt"
const SECTION_PREFIX: String = "=== "
const END_SECTION: String = "end"
const CARET_MARK: String = "<|>"
const SELECTION_OPEN: String = "<|"
const SELECTION_CLOSE: String = "|>"
const DEFAULT_INDENT_SIZE: int = 4
const MEMORY_CHECK_BUILDS: int = 100
const DETAILS_ARGUMENT: String = "--details"
const SCOPES_ACTION: String = "describe_scopes"
const EXTRACTION_RANGE_ACTION: String = "describe_extraction_range"
const EXTRACTION_ACTION: String = "describe_extraction"
const EXTRACTION_NAME: String = "_new"
const EXTRACTION_SAMPLE_STEP: int = 60
const EXTRACTION_RANGE_SIZES: Array[int] = [0, 1, 2]
const DESCRIPTION_ACTIONS: Array[String] = [SCOPES_ACTION, EXTRACTION_RANGE_ACTION, EXTRACTION_ACTION]
const SCRIPT_EXTENSION: String = "gd"
const PROJECT_SCRIPT_ROOTS: Array[String] = ["res://addons", "res://tools"]
const PROJECT_SCRIPTS: Array[String] = ["res://tests/run_tests.gd"]
const INTERNAL_FUNCTION_PREFIX: String = "@"
const ACTION_SCRIPT_SUFFIX: String = "_action"
const VIEW_WIDTH: float = 900.0
const VIEW_CARET_VISIBLE: String = "caret_visible"
const VIEW_UNCHANGED: String = "unchanged"
const VIEW_SAME_TOP_TEXT: String = "same_top_text"
const VIEW_TEXT_VISIBLE: String = "text_visible"
const VIEW_CARET_ROW_UNCHANGED: String = "caret_row_unchanged"
const REORDER_ACTION: String = "reorder_class_members"
const FORMAT_ACTION: String = "format_class_members"
const EXPLICIT_TYPE_ACTION: String = "add_explicit_type"
const FIXTURES_ROOT: String = "res://tests/fixtures/other_scripts"
const TEMPORARY_ROOT: String = "user://gdscript_extreme_tool_tests"
const LIBRARY_SCRIPT_VERSIONS: Array[String] = ["extends RefCounted\n\n\nfunc first() -> int:\n\treturn 1\n", "extends RefCounted\n\n\nfunc second() -> int:\n\treturn 2\n", "extends RefCounted\n\n\nfunc unsaved() -> int:\n\treturn 3\n"]
const SPLIT_OPERATORS: Array[String] = [" : = ", ":\t=", " :  =\t", ": =", " :="]
const SETTING_COUNT: int = 10
const NAME_CHECK_LEVELS: Array[String] = ["valid", "warning", "error"]
const DIALOG_SAMPLE: String = "extends RefCounted\n\n@export var speed : float = 1.0\n\nvar health : int = 0\n\nvar _name : String\nvar _secret : String\n\n\nfunc heal() -> void:\n\tpass\n"
const EXTRACT_DIALOG_SAMPLE: String = "extends Node\n\n\nfunc run(items : Array[int]) -> void:\n\tvar total := 0\n\tfor item in items:\n\t\ttotal += item\n\tprint(total)\n\n\nfunc _existing() -> void:\n\tpass\n"
const DIALOG_NODE_SAMPLE: String = "extends Node\n\nvar _health : int\n"
const BLANK_CHARACTERS: Array[String] = [" ", "\t", "\n"]
const COLLECTION_CLOSINGS: Array[String] = ["]", "}"]
const STRING_LITERAL_PATTERN: String = "\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'"
const PLAN_ACTION: String = "apply_plan"
const DESCRIPTION_INDENT: String = "  "

var _error_collector: ErrorCollector = ErrorCollector.new()
var _shows_pending_details: bool = false
var _passed: PackedStringArray = []
var _pending: PackedStringArray = []
var _failed: PackedStringArray = []
var _script_path: String = ""


class MarkedText:
	var text: String = ""
	var has_marks: bool = false
	var from_line: int = 0
	var from_column: int = 0
	var to_line: int = 0
	var to_column: int = 0

	static func parse(raw: String) -> MarkedText:
		var result := MarkedText.new()
		var caret_offset := raw.find(CARET_MARK)
		if caret_offset != -1:
			result.text = raw.substr(0, caret_offset) + raw.substr(caret_offset + CARET_MARK.length())
			result._set_range(caret_offset, caret_offset)
			return result
		var open_offset := raw.find(SELECTION_OPEN)
		var close_offset := raw.find(SELECTION_CLOSE, open_offset + SELECTION_OPEN.length())
		if open_offset != -1 and close_offset != -1:
			var selected := raw.substr(open_offset + SELECTION_OPEN.length(), close_offset - open_offset - SELECTION_OPEN.length())
			result.text = raw.substr(0, open_offset) + selected + raw.substr(close_offset + SELECTION_CLOSE.length())
			result._set_range(open_offset, open_offset + selected.length())
			return result
		result.text = raw
		return result

	func _set_range(from_offset: int, to_offset: int) -> void:
		has_marks = true
		var from := _offset_to_position(from_offset)
		var to := _offset_to_position(to_offset)
		from_line = from.x
		from_column = from.y
		to_line = to.x
		to_column = to.y

	func _offset_to_position(offset: int) -> Vector2i:
		var before := text.substr(0, offset)
		return Vector2i(before.count("\n"), offset - (before.rfind("\n") + 1))


class TestCase:
	var name: String = ""
	var action: String = ""
	var is_pending: bool = false
	var skips_compile_check: bool = false
	var uses_spaces: bool = false
	var indent_size: int = DEFAULT_INDENT_SIZE
	var input: MarkedText
	var expected: MarkedText
	var expected_raw: String = ""
	var plan_description: String = ""
	var viewport_lines: int = 0
	var scroll_to_line: int = 0
	var expected_view: String = ""
	var view_text: String = ""
	var breakpoints: PackedInt32Array = []
	var bookmarks: PackedInt32Array = []
	var expected_breakpoints: PackedInt32Array = []
	var expected_bookmarks: PackedInt32Array = []
	var folds: PackedInt32Array = []
	var expected_folds: PackedInt32Array = []
	var settings: Dictionary = {}
	var headers: Dictionary[String, String] = {}


class DialogTestAction extends "res://addons/gdscript_extreme_tool/actions/code_action.gd":
	var dialog: AcceptDialog

	func get_label() -> String:
		return "Dialog Test"

	func build_plan(context: GDSExCodeContext) -> GDSExEditPlan:
		return GDSExGenerateDefaultInitAction.new().build_plan(context)

	func create_dialog(context: GDSExCodeContext, on_plan_ready: Callable) -> Window:
		dialog = AcceptDialog.new()
		dialog.confirmed.connect(func() -> void: on_plan_ready.call(build_plan(context)))
		return dialog


class ExtractTestAction extends "res://addons/gdscript_extreme_tool/actions/code_action.gd":
	var function_name: String = ""
	var form_name: String = ""

	func get_label() -> String:
		return "Extract Test"

	func build_plan(context: GDSExCodeContext) -> GDSExEditPlan:
		for alternative in GDSExExtractFunction.find_alternatives(context):
			if alternative.is_valid() and (form_name.is_empty() or GDSExExtractFunction.GDSExForm.find_key(alternative.form) == form_name):
				return GDSExExtractFunction.build_plan_for(alternative, context, function_name)
		return null


class ErrorCollector extends Logger:
	var _mutex: Mutex = Mutex.new()
	var _errors: PackedStringArray = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		_errors.append(code if rationale.is_empty() else rationale)
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var taken := _errors.duplicate()
		_errors.clear()
		_mutex.unlock()
		return taken


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.add_logger(_error_collector)
	var filters := OS.get_cmdline_user_args()
	_shows_pending_details = filters.has(DETAILS_ARGUMENT)
	filters.erase(DETAILS_ARGUMENT)
	for path in _collect_paths(CASES_ROOT, CASE_EXTENSION):
		if _matches_filters(path, filters):
			await _run_case(path)
	OS.remove_logger(_error_collector)
	print("\n%d passed, %d pending, %d failed" % [_passed.size(), _pending.size(), _failed.size()])
	quit(0 if _failed.is_empty() else 1)


func _matches_filters(path: String, filters: PackedStringArray) -> bool:
	if filters.is_empty():
		return true
	for filter in filters:
		if path.contains(filter):
			return true
	return false


func _collect_paths(directory: String, extension: String) -> PackedStringArray:
	var paths := PackedStringArray()
	for subdirectory in DirAccess.get_directories_at(directory):
		paths.append_array(_collect_paths(directory.path_join(subdirectory), extension))
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() == extension:
			paths.append(directory.path_join(file))
	paths.sort()
	return paths


func _run_case(path: String) -> void:
	var test_case := _parse_case(path)
	var case_problems := _check_expected_compiles(test_case)
	if not case_problems.is_empty():
		_fail(test_case, case_problems)
		return
	var editor := _create_editor(test_case)
	_error_collector.take()
	_override_settings(test_case.settings, true)
	_script_path = test_case.headers.get("script_path", "")
	var problems := _run_action(test_case, editor)
	_script_path = ""
	editor.free()
	if test_case.viewport_lines > 0 and problems.is_empty():
		problems.append_array(await _check_view(test_case))
	_override_settings(test_case.settings, false)
	for error in _error_collector.take():
		problems.append("Engine error: %s" % error)
	_report(test_case, problems)


func _context(editor: CodeEdit) -> GDSExCodeContext:
	return GDSExCodeContext.new(editor, _script_path)


func _override_settings(settings: Dictionary, is_applied: bool) -> void:
	for key: String in settings:
		ProjectSettings.set_setting(GDSExPluginProjectSettings.setting_path(key), settings[key] if is_applied else null)


func _check_view(test_case: TestCase) -> PackedStringArray:
	var problems := PackedStringArray()
	var action := _find_code_action(test_case.action)
	var editor := _create_editor(test_case)
	editor.size = Vector2(VIEW_WIDTH, editor.get_line_height() * (test_case.viewport_lines + 0.5))
	await process_frame
	if test_case.scroll_to_line > 0:
		editor.set_line_as_first_visible(test_case.scroll_to_line - 1)
		await process_frame
	var top_line := editor.get_first_visible_line()
	var top_text := editor.get_line(top_line)
	var caret_row := editor.get_caret_line() - top_line
	if test_case.expected_view == VIEW_SAME_TOP_TEXT and top_text.strip_edges().is_empty():
		problems.append("The view starts on an empty line; scroll to a line with code.")
	GDSExEditApplier.apply(editor, _build_plan(test_case.plan_description) if test_case.action == PLAN_ACTION else action.build_plan(_context(editor)))
	await process_frame
	await process_frame
	var first_line := editor.get_first_visible_line()
	var last_line := editor.get_last_full_visible_line()
	var caret_line := editor.get_caret_line()
	match test_case.expected_view:
		VIEW_CARET_VISIBLE:
			if caret_line < first_line or caret_line > last_line:
				problems.append("The caret is on line %d, outside the visible lines %d..%d." % [caret_line + 1, first_line + 1, last_line + 1])
		VIEW_UNCHANGED:
			if first_line != top_line:
				problems.append("The view moved: its first line went from %d to %d." % [top_line + 1, first_line + 1])
		VIEW_SAME_TOP_TEXT:
			if editor.get_line(first_line) != top_text:
				problems.append("The view shows different code: its first line was '%s' and now is '%s'." % [top_text, editor.get_line(first_line)])
		VIEW_CARET_ROW_UNCHANGED:
			if caret_line - first_line != caret_row:
				problems.append("The caret was on row %d of the view and now is on row %d." % [caret_row + 1, caret_line - first_line + 1])
		VIEW_TEXT_VISIBLE:
			var text_line := -1
			for line in editor.get_line_count():
				if editor.get_line(line).strip_edges() == test_case.view_text:
					text_line = line
			if text_line < first_line or text_line > last_line:
				problems.append("'%s' is on line %d, outside the visible lines %d..%d." % [test_case.view_text, text_line + 1, first_line + 1, last_line + 1])
		_:
			problems.append("Unknown expect_view '%s'." % test_case.expected_view)
	editor.free()
	return problems


func _parse_case(path: String) -> TestCase:
	var headers: Dictionary[String, String] = {}
	var sections: Dictionary[String, String] = {}
	var section_name := ""
	var section_lines := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with(SECTION_PREFIX):
			if not section_name.is_empty():
				sections[section_name] = "\n".join(section_lines)
			section_name = line.trim_prefix(SECTION_PREFIX).strip_edges()
			section_lines = PackedStringArray()
			if section_name == END_SECTION:
				break
		elif section_name.is_empty():
			var separator := line.find(":")
			if separator != -1:
				headers[line.substr(0, separator).strip_edges()] = line.substr(separator + 1).strip_edges()
		else:
			section_lines.append(line)

	var test_case := TestCase.new()
	test_case.headers = headers
	test_case.name = path.trim_prefix(CASES_ROOT + "/").get_basename()
	test_case.action = headers.get("action", "")
	test_case.is_pending = headers.get("status", "") == "pending"
	test_case.skips_compile_check = headers.get("compile_check", "") == "skip"
	test_case.uses_spaces = headers.get("indent", "tabs") == "spaces"
	test_case.input = MarkedText.parse(sections.get("input", ""))
	test_case.expected_raw = sections.get("expected", test_case.input.text)
	test_case.expected = MarkedText.parse(test_case.expected_raw)
	test_case.plan_description = sections.get("plan", "")
	test_case.viewport_lines = int(headers.get("viewport_lines", "0"))
	test_case.scroll_to_line = int(headers.get("scroll_to_line", "0"))
	test_case.expected_view = headers.get("expect_view", "")
	test_case.view_text = headers.get("view_text", "")
	test_case.breakpoints = _parse_lines(headers.get("breakpoints", ""))
	test_case.bookmarks = _parse_lines(headers.get("bookmarks", ""))
	test_case.expected_breakpoints = _parse_lines(headers.get("expect_breakpoints", ""))
	test_case.expected_bookmarks = _parse_lines(headers.get("expect_bookmarks", ""))
	test_case.folds = _parse_lines(headers.get("folds", ""))
	test_case.expected_folds = _parse_lines(headers.get("expect_folds", ""))
	var settings: Variant = str_to_var(headers.get("settings", "{}"))
	if settings is Dictionary:
		test_case.settings = settings
	return test_case


func _parse_lines(text: String) -> PackedInt32Array:
	var lines := PackedInt32Array()
	for part in text.split(",", false):
		lines.append(int(part) - 1)
	return lines


func _check_expected_compiles(test_case: TestCase) -> PackedStringArray:
	var problems := PackedStringArray()
	if test_case.skips_compile_check:
		return problems
	var script := GDScript.new()
	script.source_code = test_case.input.text if DESCRIPTION_ACTIONS.has(test_case.action) else test_case.expected.text
	_error_collector.take()
	if script.reload() != OK:
		problems.append("The script of the case is not valid GDScript.")
		problems.append_array(_error_collector.take())
	return problems


func _create_editor(test_case: TestCase) -> CodeEdit:
	var editor := CodeEdit.new()
	root.add_child(editor)
	editor.indent_use_spaces = test_case.uses_spaces
	editor.indent_size = test_case.indent_size
	editor.text = test_case.input.text
	editor.clear_undo_history()
	var input := test_case.input
	if input.has_marks:
		editor.set_caret_line(input.to_line)
		editor.set_caret_column(input.to_column)
		if input.from_line != input.to_line or input.from_column != input.to_column:
			editor.select(input.from_line, input.from_column, input.to_line, input.to_column)
	return editor


func _run_action(test_case: TestCase, editor: CodeEdit) -> PackedStringArray:
	match test_case.action:
		"apply_plan":
			GDSExEditApplier.apply(editor, _build_plan(test_case.plan_description))
			return _check_edit(test_case, editor)
		SCOPES_ACTION:
			return _check_scopes(test_case, editor)
		EXTRACTION_RANGE_ACTION:
			return _check_description(test_case, _describe_extraction_range(editor))
		EXTRACTION_ACTION:
			return _check_description(test_case, _describe_extraction(editor))
		"check_project_scripts":
			return _check_project_scripts()
		"check_no_false_targets":
			return _check_no_false_targets()
		"check_no_undefined_identifiers":
			return _check_no_undefined_identifiers()
		"check_reorder_project_scripts":
			return _check_layout_of_project_scripts(REORDER_ACTION, false)
		"check_format_project_scripts":
			return _check_layout_of_project_scripts(FORMAT_ACTION, true)
		"check_index_memory":
			return _check_index_memory(editor)
		"check_settings_registration":
			return _check_settings_registration()
		"run_first_popup_action":
			return _check_code_actions_popup(test_case, editor)
		"check_init_function_name":
			return _check_init_function_name(test_case, editor)
		"check_extract_function_name":
			return _check_extract_function_name(test_case, editor)
		"generate_custom_init":
			return _check_custom_init(test_case, editor)
		"extract_function":
			return _check_extract_function(test_case, editor)
		"run_dialog_action":
			return _check_dialog_action(test_case, editor)
		"run_custom_init_dialog":
			return _check_custom_init_dialog(test_case, editor)
		"check_init_dialog":
			return _check_init_dialog()
		"check_extract_project_scripts":
			return _check_extract_project_scripts(int(test_case.headers.get("sample_step", str(EXTRACTION_SAMPLE_STEP))))
		"check_extraction_behavior":
			return _check_extraction_behavior(editor)
		"run_extract_function_dialog":
			return _check_extract_function_dialog(test_case, editor)
		"check_extract_dialog":
			return _check_extract_dialog()
		"check_explicit_types_of_project_scripts":
			return _check_explicit_types_of_project_scripts()
		"check_script_library":
			return _check_script_library()
	var action := _find_code_action(test_case.action)
	if action == null:
		return PackedStringArray(["Unknown action '%s'." % test_case.action])
	return _check_code_action(test_case, action, editor)


func _find_code_action(action_name: String) -> GDSExCodeAction:
	for action in GDSExActionRegistry.create_actions():
		var script_path: String = (action.get_script() as Script).resource_path
		if script_path.get_file().get_basename().trim_suffix(ACTION_SCRIPT_SUFFIX) == action_name:
			return action
	return null


func _check_code_action(test_case: TestCase, action: GDSExCodeAction, editor: CodeEdit) -> PackedStringArray:
	var problems := PackedStringArray()
	var actions: Array[GDSExCodeAction] = [action]
	var is_offered := not GDSExActionRegistry.find_available(actions, _context(editor)).is_empty()
	var expects_change := test_case.expected.text != test_case.input.text
	if is_offered and not expects_change:
		problems.append("The action is offered in the menu but nothing should change.")
	if not is_offered and expects_change:
		problems.append("The action is not offered in the menu.")
	for line in test_case.breakpoints:
		editor.set_line_as_breakpoint(line, true)
	for line in test_case.bookmarks:
		editor.set_line_as_bookmarked(line, true)
	editor.line_folding = not test_case.folds.is_empty()
	for line in test_case.folds:
		editor.fold_line(line)
	GDSExEditApplier.apply(editor, action.build_plan(_context(editor)))
	if PackedInt32Array(editor.get_folded_lines()) != test_case.expected_folds:
		problems.append("Folded lines are %s instead of %s." % [_one_based(PackedInt32Array(editor.get_folded_lines())), _one_based(test_case.expected_folds)])
	if editor.get_breakpointed_lines() != test_case.expected_breakpoints:
		problems.append("Breakpoints are on lines %s instead of %s." % [_one_based(editor.get_breakpointed_lines()), _one_based(test_case.expected_breakpoints)])
	if editor.get_bookmarked_lines() != test_case.expected_bookmarks:
		problems.append("Bookmarks are on lines %s instead of %s." % [_one_based(editor.get_bookmarked_lines()), _one_based(test_case.expected_bookmarks)])
	if test_case.action == FORMAT_ACTION and action.build_plan(_context(editor)) != null:
		problems.append("Running the action again on the formatted result changes it.")
	problems.append_array(_check_edit(test_case, editor))
	return problems


func _one_based(lines: PackedInt32Array) -> Array:
	var shifted: Array = []
	for line in lines:
		shifted.append(line + 1)
	return shifted


func _build_plan(description: String) -> GDSExEditPlan:
	var plan := GDSExEditPlan.new()
	for entry: Dictionary in JSON.parse_string(description):
		if entry.has("replace"):
			var range: Array = entry["replace"]
			plan.replace(int(range[0]), int(range[1]), int(range[2]), entry.get("text", ""))
			continue
		var point := GDSExEditPlan.GDSExInsertionPoint.new()
		point.line = int(entry.get("line", 0))
		point.indent_text = entry.get("indent_text", "")
		point.blank_lines_before = int(entry.get("blank_lines_before", 0))
		point.blank_lines_after = int(entry.get("blank_lines_after", 0))
		var snippet := GDSExSnippet.new()
		for line: Array in entry.get("lines", []):
			snippet.add_line(int(line[0]), line[1])
		if entry.has("select"):
			var selection: Array = entry["select"]
			snippet.select(int(selection[0]), int(selection[1]), int(selection[2]))
		var insertion := plan.insert(point, snippet)
		if entry.get("reveal", false):
			plan.reveal(insertion)
	return plan


func _check_edit(test_case: TestCase, editor: CodeEdit) -> PackedStringArray:
	var problems := PackedStringArray()
	var actual := _render_with_marks(editor) if test_case.expected.has_marks else editor.text
	if actual != test_case.expected_raw:
		problems.append("Unexpected result.\n--- expected ---\n%s\n--- actual ---\n%s" % [_visualize(test_case.expected_raw), _visualize(actual)])
	if editor.text != test_case.input.text:
		editor.undo()
		if editor.text != test_case.input.text:
			problems.append("A single undo does not restore the original text.")
	return problems


func _check_scopes(test_case: TestCase, editor: CodeEdit) -> PackedStringArray:
	var index := GDSExSymbolIndexBuilder.build(editor.text.split("\n"), _script_path)
	var actual := "\n".join(_describe_scope(index.root, 0))
	if actual == test_case.expected_raw:
		return PackedStringArray()
	return PackedStringArray(["Unexpected scopes.\n--- expected ---\n%s\n--- actual ---\n%s" % [test_case.expected_raw, actual]])


func _check_description(test_case: TestCase, actual: String) -> PackedStringArray:
	if actual == test_case.expected_raw:
		return PackedStringArray()
	return PackedStringArray(["Unexpected description.\n--- expected ---\n%s\n--- actual ---\n%s" % [test_case.expected_raw, actual]])


func _describe_extraction_range(editor: CodeEdit) -> String:
	var context := _context(editor)
	var found := GDSExStatementRange.find(context.index, context.lines, context.selection_first_line, context.selection_last_line)
	if not found.is_valid():
		return "rejected: %s" % GDSExStatementRange.GDSExRejection.find_key(found.rejection)
	var description := PackedStringArray(["lines %d-%d" % [found.first_line + 1, found.last_line + 1], "statements %d" % found.statements().size()])
	var flags := PackedStringArray()
	for flag: String in ["has_return", "has_value_return", "ends_with_return", "reaches_function_end", "has_await"]:
		if found.get(flag):
			flags.append(flag)
	if not flags.is_empty():
		description.append("flags: %s" % ", ".join(flags))
	return "\n".join(description)


func _describe_extraction(editor: CodeEdit) -> String:
	var context := _context(editor)
	var alternatives := GDSExExtractFunction.find_alternatives(context)
	var extraction := alternatives[0]
	if extraction.rejection == GDSExExtractFunction.GDSExRejection.RANGE:
		return "rejected: %s" % GDSExStatementRange.GDSExRejection.find_key(extraction.statement_range.rejection)
	if not extraction.is_valid():
		return "rejected: %s" % GDSExExtractFunction.GDSExRejection.find_key(extraction.rejection)
	var description := PackedStringArray([
		"form: %s" % GDSExExtractFunction.GDSExForm.find_key(extraction.form),
		"signature: %s" % GDSExExtractFunction.signature(extraction, EXTRACTION_NAME),
		"call: %s" % " | ".join(GDSExExtractFunction.call_lines(extraction, EXTRACTION_NAME, context.lines)),
	])
	for alternative in alternatives.slice(1):
		description.append("or %s: %s -> %s" % [GDSExExtractFunction.GDSExForm.find_key(alternative.form), GDSExExtractFunction.signature(alternative, EXTRACTION_NAME), " | ".join(GDSExExtractFunction.call_lines(alternative, EXTRACTION_NAME, context.lines))])
	return "\n".join(description)


func _describe_scope(scope: GDSExSymbolIndex.GDSExScopeBase, depth: int) -> PackedStringArray:
	var description := PackedStringArray([DESCRIPTION_INDENT.repeat(depth) + _scope_label(scope)])
	var member_indent := DESCRIPTION_INDENT.repeat(depth + 1)
	var variables: Array = scope.locals
	if scope is GDSExSymbolIndex.GDSExClassScope:
		var class_scope := scope as GDSExSymbolIndex.GDSExClassScope
		variables = class_scope.vars.values()
		for signal_name: String in class_scope.signals:
			description.append("%ssignal %s(%s)" % [member_indent, signal_name, _params_label(class_scope.signals[signal_name].params)])
	var entries: Array = []
	for variable: GDSExSymbolIndex.GDSExVariableSymbol in variables:
		entries.append([variable.start_line * 2, PackedStringArray([member_indent + _variable_label(variable)])])
	for child in scope.children:
		entries.append([child.start_line * 2 + 1, _describe_scope(child, depth + 1)])
	entries.sort_custom(func(first: Array, second: Array) -> bool: return first[0] < second[0])
	for entry: Array in entries:
		description.append_array(entry[1])
	return description


func _scope_label(scope: GDSExSymbolIndex.GDSExScopeBase) -> String:
	var label := ""
	if scope is GDSExSymbolIndex.GDSExClassScope:
		var class_scope := scope as GDSExSymbolIndex.GDSExClassScope
		label = "class %s" % ("<root>" if class_scope.parent == null else class_scope.name)
		if not class_scope.base_script_path.is_empty():
			label += " extends %s" % class_scope.base_script_path
	elif scope is GDSExSymbolIndex.GDSExFunctionScope:
		var function := scope as GDSExSymbolIndex.GDSExFunctionScope
		label = "lambda" if function.is_lambda else "function %s" % function.name
		label += "(%s)" % _params_label(function.params)
		if function.return_type != null:
			label += " -> %s" % GDSExSymbolIndex.type_to_string(function.return_type)
	else:
		label = GDSExSymbolIndex.GDSExBlockScope.GDSExKind.find_key((scope as GDSExSymbolIndex.GDSExBlockScope).kind).to_lower()
	label += " %d-%d" % [scope.start_line + 1, scope.end_line + 1]
	if scope.body_start_line != -1 and scope.parent != null:
		label += " body %d" % (scope.body_start_line + 1)
	return label


func _params_label(params: Dictionary) -> String:
	var labels := PackedStringArray()
	for param_name: String in params:
		labels.append(_typed_label(param_name, params[param_name]))
	return ", ".join(labels)


func _variable_label(variable: GDSExSymbolIndex.GDSExVariableSymbol) -> String:
	var label := "%s %s" % ["const" if variable.is_const else "var", _typed_label(variable.name, variable.type)]
	label += " %d" % (variable.start_line + 1)
	if variable.end_line != variable.start_line:
		label += "-%d" % (variable.end_line + 1)
	if variable.is_script_alias:
		label += " script %s" % ("<unknown path>" if variable.script_path.is_empty() else variable.script_path)
	return label


func _typed_label(symbol_name: String, type: GDSExSymbolIndex.GDSExTypeData) -> String:
	return symbol_name if type == null else "%s: %s" % [symbol_name, GDSExSymbolIndex.type_to_string(type)]


func _check_project_scripts() -> PackedStringArray:
	var problems := PackedStringArray()
	for path in _project_script_paths():
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			problems.append("%s does not compile." % path)
			continue
		var index := GDSExSymbolIndexBuilder.build(FileAccess.get_file_as_string(path).split("\n"))
		problems.append_array(_compare_with_engine(path, index.root, script))
	return problems


func _project_script_paths() -> PackedStringArray:
	var paths := PackedStringArray(PROJECT_SCRIPTS)
	for root_directory in PROJECT_SCRIPT_ROOTS:
		paths.append_array(_collect_paths(root_directory, SCRIPT_EXTENSION))
	return paths


func _check_no_false_targets() -> PackedStringArray:
	var problems := PackedStringArray()
	var generator := GDSExGenerateFunctionAction.new()
	for path in _project_script_paths():
		var index := GDSExSymbolIndexBuilder.build(FileAccess.get_file_as_string(path).split("\n"))
		_collect_false_targets(path, index, index.statements, generator, problems)
	return problems


func _check_custom_init(test_case: TestCase, editor: CodeEdit) -> PackedStringArray:
	if not test_case.headers.has("options"):
		return _check_code_action(test_case, GDSExGenerateCustomInitAction.new(), editor)
	var options: Dictionary = str_to_var(test_case.headers["options"])
	var plan := GDSExInitFunction.build_plan(_context(editor), options["name"], PackedStringArray(options["variables"]))
	GDSExEditApplier.apply(editor, plan)
	return _check_edit(test_case, editor)


func _check_extract_function(test_case: TestCase, editor: CodeEdit) -> PackedStringArray:
	if not test_case.headers.has("options"):
		return _check_code_action(test_case, _find_code_action(test_case.action), editor)
	var options: Dictionary = str_to_var(test_case.headers["options"])
	var action := ExtractTestAction.new()
	action.function_name = options["name"]
	action.form_name = options.get("form", "")
	return _check_code_action(test_case, action, editor)


func _check_dialog_action(test_case: TestCase, editor: CodeEdit) -> PackedStringArray:
	var problems := PackedStringArray()
	var action := DialogTestAction.new()
	var actions: Array[GDSExCodeAction] = [action]
	var popup := GDSExCodeActionsPopup.new()
	root.add_child(popup)
	popup.setup(editor, actions)
	popup.about_to_popup.emit()
	popup.index_pressed.emit(0)
	popup.free()
	if editor.text != test_case.input.text:
		problems.append("The action changed the script before its dialog was confirmed.")
	if action.dialog == null or action.dialog.get_parent() != editor.get_window() or not action.dialog.visible:
		problems.append("The dialog of the action is not open in the window of the editor.")
		return problems
	action.dialog.confirmed.emit()
	action.dialog.hide()
	if not action.dialog.is_queued_for_deletion():
		problems.append("The dialog is not freed after it closes.")
	problems.append_array(_check_edit(test_case, editor))
	return problems


func _check_custom_init_dialog(test_case: TestCase, editor: CodeEdit) -> PackedStringArray:
	var problems := PackedStringArray()
	var popup := GDSExCodeActionsPopup.new()
	root.add_child(popup)
	popup.setup(editor, GDSExActionRegistry.create_actions())
	popup.about_to_popup.emit()
	for index in popup.item_count:
		if popup.get_item_text(index) == GDSExGenerateCustomInitAction.LABEL:
			popup.index_pressed.emit(index)
	popup.free()
	var dialog: GDSExInitFunctionDialog = null
	for child in editor.get_window().get_children():
		if child is GDSExInitFunctionDialog:
			dialog = child
	if dialog == null or not dialog.visible:
		return PackedStringArray(["The menu did not open the custom init dialog."])
	if editor.text != test_case.input.text:
		problems.append("The script changed before the dialog was confirmed.")
	if test_case.headers.has("options"):
		var options: Dictionary = str_to_var(test_case.headers["options"])
		_type_dialog_name(dialog, options["name"])
		for item in dialog.variable_tree.get_root().get_children():
			item.set_checked(0, (options["variables"] as Array).has(item.get_text(0)))
		dialog.variable_tree.item_edited.emit()
	dialog.get_ok_button().pressed.emit()
	if dialog.visible or not dialog.is_queued_for_deletion():
		problems.append("The dialog is not closed and freed after generating.")
	problems.append_array(_check_edit(test_case, editor))
	return problems


func _check_extract_project_scripts(sample_step: int) -> PackedStringArray:
	var problems := PackedStringArray()
	var editor := CodeEdit.new()
	root.add_child(editor)
	var range_count := 0
	for path in _project_script_paths():
		_script_path = path
		var source := FileAccess.get_file_as_string(path)
		var lines := source.split("\n")
		var ranges: Array[Vector2i] = []
		_collect_statement_ranges(GDSExSymbolIndexBuilder.build(lines).statements, ranges)
		for selected in ranges:
			range_count += 1
			if range_count % sample_step != 0:
				continue
			editor.text = source
			editor.select(selected.x, 0, selected.y, lines[selected.y].length())
			var plan := GDSExExtractFunction.build_plan(_context(editor), EXTRACTION_NAME)
			if plan == null:
				continue
			GDSExEditApplier.apply(editor, plan)
			var script := GDScript.new()
			script.source_code = editor.text
			if script.reload() != OK:
				problems.append("%s: the script does not compile after extracting lines %d-%d." % [path, selected.x + 1, selected.y + 1])
	editor.free()
	return problems


func _collect_statement_ranges(statements: Array[GDSExSourceScanner.GDSExStatement], ranges: Array[Vector2i]) -> void:
	for first in statements.size():
		var lasts: Array[int] = [statements.size() - 1]
		for size in EXTRACTION_RANGE_SIZES:
			lasts.append(first + size)
		for last in lasts:
			if last >= first and last < statements.size():
				var selected := Vector2i(statements[first].first_line, GDSExStatementRange.last_code_line_of(statements[last]))
				if not ranges.has(selected):
					ranges.append(selected)
	for statement in statements:
		for block in statement.blocks:
			_collect_statement_ranges(block.statements, ranges)


func _check_extraction_behavior(editor: CodeEdit) -> PackedStringArray:
	var original := GDScript.new()
	original.source_code = editor.text
	if original.reload() != OK:
		return PackedStringArray(["The script of the case does not compile."])
	var plan := GDSExExtractFunction.build_plan(_context(editor), EXTRACTION_NAME)
	if plan == null:
		return PackedStringArray(["The selection cannot be extracted."])
	GDSExEditApplier.apply(editor, plan)
	var extracted := GDScript.new()
	extracted.source_code = editor.text
	if extracted.reload() != OK:
		return PackedStringArray(["The extracted script does not compile.\n%s" % _visualize(editor.text)])
	var problems := PackedStringArray()
	var before: Object = original.new()
	var after: Object = extracted.new()
	for arguments: Array in before.call("samples"):
		var expected := _run_sample(before, arguments)
		var actual := _run_sample(after, arguments)
		if expected != actual:
			problems.append("run%s gives %s after extracting instead of %s.\n%s" % [arguments, actual, expected, _visualize(editor.text)])
	return problems


func _run_sample(instance: Object, arguments: Array) -> String:
	var copied_arguments := arguments.duplicate(true)
	var result: Variant = instance.callv("run", copied_arguments)
	var state: Variant = instance.call("state") if instance.has_method("state") else null
	return var_to_str([result, copied_arguments, state])


func _check_extract_function_dialog(test_case: TestCase, editor: CodeEdit) -> PackedStringArray:
	var problems := PackedStringArray()
	var popup := GDSExCodeActionsPopup.new()
	root.add_child(popup)
	popup.setup(editor, GDSExActionRegistry.create_actions())
	popup.about_to_popup.emit()
	for index in popup.item_count:
		if popup.get_item_text(index) == GDSExExtractFunctionAction.LABEL:
			popup.index_pressed.emit(index)
	popup.free()
	var dialog: GDSExExtractFunctionDialog = null
	for child in editor.get_window().get_children():
		if child is GDSExExtractFunctionDialog:
			dialog = child
	if dialog == null or not dialog.visible:
		return PackedStringArray(["The menu did not open the extract function dialog."])
	if editor.text != test_case.input.text:
		problems.append("The script changed before the dialog was confirmed.")
	if test_case.headers.has("options"):
		var options: Dictionary = str_to_var(test_case.headers["options"])
		if options.has("name"):
			_type_dialog_name(dialog, options["name"])
		for index in dialog.form_button.item_count:
			if dialog.form_button.get_item_text(index) == options.get("result", ""):
				dialog.form_button.select(index)
				dialog.form_button.item_selected.emit(index)
	if test_case.headers.get("dialog", "accept") == "cancel":
		dialog.get_cancel_button().pressed.emit()
		dialog.hide()
	else:
		dialog.get_ok_button().pressed.emit()
	if dialog.visible or not dialog.is_queued_for_deletion():
		problems.append("The dialog is not closed and freed after it is answered.")
	problems.append_array(_check_edit(test_case, editor))
	return problems


func _check_extract_dialog() -> PackedStringArray:
	var problems := PackedStringArray()
	var editor := CodeEdit.new()
	root.add_child(editor)
	editor.text = EXTRACT_DIALOG_SAMPLE
	editor.select(5, 0, 6, editor.get_line(6).length())
	var plans: Array[GDSExEditPlan] = []
	var dialog := GDSExExtractFunctionDialog.new()
	dialog.setup(_context(editor), func(plan: GDSExEditPlan) -> void: plans.append(plan))
	root.add_child(dialog)
	dialog.popup_centered()

	var extracted_function := "func %s(items: Array[int], total: int) -> int:\n\tfor item in items:\n\t\ttotal += item\n\treturn total"
	var changed_function := "func run(items : Array[int]) -> void:\n\tvar total := 0\n\ttotal = %s(items, total)\n\tprint(total)"
	_expect(problems, "initial name", dialog.name_edit.text, "_extracted_function")
	_expect(problems, "initial function", dialog.function_preview.text, extracted_function % "_extracted_function")
	_expect(problems, "initial changed function", dialog.caller_preview.text.strip_edges(), changed_function % "_extracted_function")
	_expect(problems, "previews are read only", [dialog.function_preview.editable, dialog.caller_preview.editable], [false, false])
	_expect(problems, "call line is marked", [dialog.caller_preview.get_line_background_color(2).a > 0.0, dialog.caller_preview.get_line_background_color(1).a > 0.0], [true, false])
	_expect(problems, "one result", [dialog.form_button.item_count, dialog.form_button.disabled, dialog.form_button.get_item_text(0)], [1, true, "Return the variable 'total'"])
	_expect(problems, "initial message", dialog.validation_label.text, "• Function name is valid.")
	_expect(problems, "extract enabled at start", dialog.get_ok_button().disabled, false)

	_type_dialog_name(dialog, "_sum")
	_expect(problems, "function after typing", dialog.function_preview.text, extracted_function % "_sum")
	_expect(problems, "changed function after typing", dialog.caller_preview.text.strip_edges(), changed_function % "_sum")

	_type_dialog_name(dialog, "_existing")
	_expect(problems, "message for an existing function", dialog.validation_label.text, "• The class already has a function named '_existing'.")
	_expect(problems, "extract disabled on error", dialog.get_ok_button().disabled, true)
	_expect(problems, "name in red on error", dialog.name_edit.has_theme_color_override("font_color"), true)
	_expect(problems, "message in the error color", dialog.validation_label.get_theme_color("font_color"), GDSExFunctionNameDialog.LEVEL_FALLBACK_COLORS[2])
	dialog.name_edit.text_submitted.emit("_existing")
	_expect(problems, "accept does nothing on error", plans.size(), 0)
	_type_dialog_name(dialog, "")
	_expect(problems, "message for an empty name", dialog.validation_label.text, "• Enter a function name.")

	_type_dialog_name(dialog, "sum")
	_expect(problems, "warning for a public name", dialog.validation_label.get_theme_color("font_color"), GDSExFunctionNameDialog.LEVEL_FALLBACK_COLORS[1])
	_expect(problems, "a warning does not block", dialog.get_ok_button().disabled, false)
	_expect(problems, "name back to its normal color", dialog.name_edit.has_theme_color_override("font_color"), false)
	_type_dialog_name(dialog, "total")
	_expect(problems, "warning for the name of a variable", dialog.validation_label.text, "• The function has a variable named 'total'.")

	_type_dialog_name(dialog, "_sum")
	_expect(problems, "valid again", dialog.validation_label.get_theme_color("font_color"), GDSExFunctionNameDialog.LEVEL_FALLBACK_COLORS[0])
	dialog.name_edit.text_submitted.emit("_sum")
	_expect(problems, "accept on the name extracts", plans.size(), 1)
	_expect(problems, "dialog hidden after extracting", dialog.visible, false)
	if plans.size() == 1:
		GDSExEditApplier.apply(editor, plans[0])
		_expect(problems, "extracted function", editor.text.contains("\ttotal = _sum(items, total)\n\tprint(total)") and editor.text.contains((extracted_function % "_sum") + "\n"), true)
	dialog.free()

	editor.text = "extends Node\n\nvar _table : Dictionary = {}\n\n\nclass Inner:\n\tvar count : int = 0\n\n\tfunc run() -> void:\n\t\tif count > 0:\n\t\t\tprint(1)\n\t\t\treturn\n\t\tprint(2)\n\n\nfunc _ready() -> void:\n\tprint(\"start\")\n\t_table = { \"value\" : 2 }\n"
	editor.select(17, 0, 17, editor.get_line(17).length())
	var member_plans: Array[GDSExEditPlan] = []
	var member_dialog := GDSExExtractFunctionDialog.new()
	member_dialog.setup(_context(editor), func(plan: GDSExEditPlan) -> void: member_plans.append(plan))
	root.add_child(member_dialog)
	_expect(problems, "results for a class variable", [member_dialog.form_button.item_count, member_dialog.form_button.disabled, member_dialog.form_button.get_item_text(0), member_dialog.form_button.get_item_text(1)], [2, false, "Return nothing", "Return the value of the last line"])
	_expect(problems, "function that sets the class variable", member_dialog.function_preview.text, "func _extracted_function() -> void:\n\t_table = { \"value\" : 2 }")
	_expect(problems, "call that returns nothing", member_dialog.caller_preview.text.strip_edges(), "func _ready() -> void:\n\tprint(\"start\")\n\t_extracted_function()")
	member_dialog.form_button.select(1)
	member_dialog.form_button.item_selected.emit(1)
	_expect(problems, "function that returns the value", member_dialog.function_preview.text, "func _extracted_function() -> Dictionary:\n\treturn { \"value\" : 2 }")
	_expect(problems, "call that assigns the value", member_dialog.caller_preview.text.strip_edges(), "func _ready() -> void:\n\tprint(\"start\")\n\t_table = _extracted_function()")
	member_dialog.get_ok_button().pressed.emit()
	if member_plans.size() == 1:
		GDSExEditApplier.apply(editor, member_plans[0])
		_expect(problems, "extracted with the chosen result", editor.text.contains("\t_table = _extracted_function()\n") and editor.text.contains("func _extracted_function() -> Dictionary:\n\treturn { \"value\" : 2 }\n"), true)
	else:
		problems.append("The dialog did not extract with the chosen result.")
	member_dialog.free()

	editor.select(10, 0, 11, editor.get_line(11).length())
	var inner_dialog := GDSExExtractFunctionDialog.new()
	inner_dialog.setup(_context(editor), func(_plan: GDSExEditPlan) -> void: pass)
	root.add_child(inner_dialog)
	_expect(problems, "function of an inner class without its indentation", inner_dialog.function_preview.text, "func _extracted_function() -> void:\n\tprint(1)\n\treturn")
	_expect(problems, "changed function of an inner class", inner_dialog.caller_preview.text.strip_edges(), "func run() -> void:\n\tif count > 0:\n\t\t_extracted_function()\n\t\treturn\n\tprint(2)")
	_expect(problems, "both call lines are marked", [inner_dialog.caller_preview.get_line_background_color(2).a > 0.0, inner_dialog.caller_preview.get_line_background_color(3).a > 0.0, inner_dialog.caller_preview.get_line_background_color(4).a > 0.0], [true, true, false])
	inner_dialog.free()
	editor.free()
	return problems


func _check_init_dialog() -> PackedStringArray:
	var problems := PackedStringArray()
	var editor := CodeEdit.new()
	root.add_child(editor)
	editor.text = DIALOG_SAMPLE
	var plans: Array[GDSExEditPlan] = []
	var dialog := GDSExInitFunctionDialog.new()
	dialog.setup(_context(editor), func(plan: GDSExEditPlan) -> void: plans.append(plan))
	root.add_child(dialog)
	dialog.popup_centered()

	_expect(problems, "initial name", dialog.name_edit.text, "_init")
	_expect(problems, "rows", _dialog_rows(dialog), "[ ] speed: float, [ ] health: int, [x] _name: String, [x] _secret: String")
	_expect(problems, "initial preview", dialog.function_preview.text, "func _init(p_name: String, p_secret: String) -> void:\n\t_name = p_name\n\t_secret = p_secret")
	_expect(problems, "preview is read only", dialog.function_preview.editable, false)
	var private_filter := dialog.filter_buttons[GDSExMemberCategories.PRIVATE_VARIABLES]
	var selected_style := private_filter.get_theme_stylebox("pressed") as StyleBoxFlat
	_expect(problems, "selected filter is filled with the accent color", [private_filter.has_theme_stylebox_override("pressed"), selected_style.draw_center, selected_style.bg_color.a > 0.0, selected_style.border_color], [true, true, true, GDSExFunctionNameDialog.ACCENT_FALLBACK_COLOR])
	_expect(problems, "available filters have no tooltip", private_filter.tooltip_text, "")
	_expect(problems, "initial message", dialog.validation_label.text, "• Function name is valid.")
	_expect(problems, "generate enabled at start", dialog.get_ok_button().disabled, false)

	dialog.variable_tree.get_root().get_child(0).set_checked(0, true)
	dialog.variable_tree.item_edited.emit()
	_expect(problems, "preview after checking a row", _first_line(dialog.function_preview), "func _init(p_speed: float, p_name: String, p_secret: String) -> void")

	dialog.filter_buttons[GDSExMemberCategories.PRIVATE_VARIABLES].button_pressed = false
	_expect(problems, "rows with the private filter off", _dialog_visible_rows(dialog), "speed, health")
	_expect(problems, "hidden rows still count", _first_line(dialog.function_preview), "func _init(p_speed: float, p_name: String, p_secret: String) -> void")
	dialog.none_button.pressed.emit()
	_expect(problems, "none only clears visible rows", _first_line(dialog.function_preview), "func _init(p_name: String, p_secret: String) -> void")
	dialog.all_button.pressed.emit()
	_expect(problems, "all only checks visible rows", _first_line(dialog.function_preview), "func _init(p_speed: float, p_health: int, p_name: String, p_secret: String) -> void")
	dialog.filter_buttons[GDSExMemberCategories.PRIVATE_VARIABLES].button_pressed = true
	_expect(problems, "rows with every filter on", _dialog_visible_rows(dialog), "speed, health, _name, _secret")

	_type_dialog_name(dialog, "heal")
	_expect(problems, "message for an existing function", dialog.validation_label.text, "• The class already has a function named 'heal'.")
	_expect(problems, "generate disabled on error", dialog.get_ok_button().disabled, true)
	_expect(problems, "name in red on error", dialog.name_edit.has_theme_color_override("font_color"), true)
	_expect(problems, "message in the error color", dialog.validation_label.get_theme_color("font_color"), GDSExInitFunctionDialog.LEVEL_FALLBACK_COLORS[2])
	dialog.name_edit.text_submitted.emit("heal")
	_expect(problems, "accept does nothing on error", plans.size(), 0)
	_type_dialog_name(dialog, "")
	_expect(problems, "message for an empty name", dialog.validation_label.text, "• Enter a function name.")

	_type_dialog_name(dialog, "setup")
	_expect(problems, "generate enabled again", dialog.get_ok_button().disabled, false)
	_expect(problems, "name back to its normal color", dialog.name_edit.has_theme_color_override("font_color"), false)
	dialog.variable_tree.set_selected(dialog.variable_tree.get_root().get_child(0), 0)
	dialog.variable_tree.gui_input.emit(_key_event(KEY_SPACE))
	_expect(problems, "space unchecks the selected row", _first_line(dialog.function_preview), "func setup(p_health: int, p_name: String, p_secret: String) -> void")
	dialog.variable_tree.gui_input.emit(_key_event(KEY_SPACE))
	_expect(problems, "space checks it again and does not generate", [_first_line(dialog.function_preview), plans.size()], ["func setup(p_speed: float, p_health: int, p_name: String, p_secret: String) -> void", 0])
	dialog.variable_tree.gui_input.emit(_key_event(KEY_ENTER))
	_expect(problems, "accept on the list generates", plans.size(), 1)
	_expect(problems, "dialog hidden after generating", dialog.visible, false)
	if plans.size() == 1:
		GDSExEditApplier.apply(editor, plans[0])
		_expect(problems, "generated function", editor.text.contains("func setup(p_speed: float, p_health: int, p_name: String, p_secret: String) -> void:\n\tspeed = p_speed\n\thealth = p_health\n\t_name = p_name\n\t_secret = p_secret"), true)
	dialog.free()

	editor.text = DIALOG_NODE_SAMPLE
	var node_dialog := GDSExInitFunctionDialog.new()
	node_dialog.setup(_context(editor), func(_plan: GDSExEditPlan) -> void: pass)
	root.add_child(node_dialog)
	_expect(problems, "name in a node", node_dialog.name_edit.text, "initialize")
	var unavailable_filter := node_dialog.filter_buttons[GDSExMemberCategories.PUBLIC_VARIABLES]
	var unavailable_style := unavailable_filter.get_theme_stylebox("disabled") as StyleBoxFlat
	_expect(problems, "unavailable filter is an empty outline", [unavailable_style.draw_center, unavailable_filter.get_theme_color("font_disabled_color"), unavailable_filter.tooltip_text], [false, GDSExInitFunctionDialog.UNAVAILABLE_FALLBACK_COLOR, "The class has no variables of this group."])
	_expect(problems, "filters without variables are disabled", [node_dialog.filter_buttons[GDSExMemberCategories.PRIVATE_VARIABLES].disabled, node_dialog.filter_buttons[GDSExMemberCategories.PUBLIC_VARIABLES].disabled, node_dialog.filter_buttons[GDSExMemberCategories.EXPORTS].disabled], [false, true, true])
	_type_dialog_name(node_dialog, "_init")
	_expect(problems, "warning for _init with parameters in a node", node_dialog.validation_label.get_theme_color("font_color"), GDSExInitFunctionDialog.LEVEL_FALLBACK_COLORS[1])
	_expect(problems, "a warning does not block", node_dialog.get_ok_button().disabled, false)
	node_dialog.none_button.pressed.emit()
	_expect(problems, "no warning without parameters", node_dialog.validation_label.text, "• Function name is valid.")
	node_dialog.free()

	editor.text = "extends RefCounted\n"
	var empty_dialog := GDSExInitFunctionDialog.new()
	empty_dialog.setup(_context(editor), func(_plan: GDSExEditPlan) -> void: pass)
	root.add_child(empty_dialog)
	_expect(problems, "dialog of a class without variables", [_dialog_rows(empty_dialog), _first_line(empty_dialog.function_preview), empty_dialog.get_ok_button().disabled], ["", "func _init() -> void", false])
	empty_dialog.free()
	editor.free()
	return problems


func _first_line(preview: CodeEdit) -> String:
	return preview.get_line(0).trim_suffix(":")


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _type_dialog_name(dialog: GDSExFunctionNameDialog, function_name: String) -> void:
	dialog.name_edit.text = function_name
	dialog.name_edit.text_changed.emit(function_name)


func _dialog_rows(dialog: GDSExInitFunctionDialog) -> String:
	var rows := PackedStringArray()
	for item in dialog.variable_tree.get_root().get_children():
		rows.append("[%s] %s: %s" % ["x" if item.is_checked(0) else " ", item.get_text(0), item.get_text(1)])
	return ", ".join(rows)


func _dialog_visible_rows(dialog: GDSExInitFunctionDialog) -> String:
	var rows := PackedStringArray()
	for item in dialog.variable_tree.get_root().get_children():
		if item.visible:
			rows.append(item.get_text(0))
	return ", ".join(rows)


func _expect(problems: PackedStringArray, what: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		problems.append("%s: expected %s but got %s" % [what, expected, actual])


func _check_init_function_name(test_case: TestCase, editor: CodeEdit) -> PackedStringArray:
	var problems := PackedStringArray()
	var context := _context(editor)
	if test_case.headers.has("expect_default_name"):
		var default_name := GDSExInitFunction.default_function_name(context)
		if default_name != test_case.headers["expect_default_name"]:
			problems.append("The default name is '%s' but '%s' was expected." % [default_name, test_case.headers["expect_default_name"]])
	if test_case.headers.has("expect_check"):
		var check := GDSExInitFunction.check_function_name(context, test_case.headers.get("init_name", ""), int(test_case.headers.get("init_parameters", "0")))
		var level := NAME_CHECK_LEVELS[check.level]
		if level != test_case.headers["expect_check"]:
			problems.append("The name '%s' is %s (%s) but %s was expected." % [test_case.headers.get("init_name", ""), level, check.message, test_case.headers["expect_check"]])
		if check.message.is_empty():
			problems.append("The check has no message.")
	return problems


func _check_extract_function_name(test_case: TestCase, editor: CodeEdit) -> PackedStringArray:
	var extraction := GDSExExtractFunction.analyze(_context(editor))
	if not extraction.is_valid():
		return PackedStringArray(["The selection cannot be extracted."])
	var function_name: String = test_case.headers.get("function_name", "")
	var check := GDSExExtractFunction.check_function_name(extraction, function_name)
	var level := NAME_CHECK_LEVELS[check.level]
	if level != test_case.headers["expect_check"]:
		return PackedStringArray(["The name '%s' is %s (%s) but %s was expected." % [function_name, level, check.message, test_case.headers["expect_check"]]])
	return PackedStringArray(["The check has no message."]) if check.message.is_empty() else PackedStringArray()


func _check_code_actions_popup(test_case: TestCase, editor: CodeEdit) -> PackedStringArray:
	var problems := PackedStringArray()
	var actions := GDSExActionRegistry.create_actions()
	var available_labels := PackedStringArray()
	for action in GDSExActionRegistry.find_available(actions, _context(editor)):
		available_labels.append(action.get_label())
	var popup := GDSExCodeActionsPopup.new()
	root.add_child(popup)
	popup.setup(editor, actions)
	if popup.item_count != 1 or not popup.is_item_disabled(0):
		problems.append("The popup should hold a single disabled item until it opens.")
	popup.about_to_popup.emit()
	var listed_labels := PackedStringArray()
	for index in popup.item_count:
		if not popup.is_item_disabled(index):
			listed_labels.append(popup.get_item_text(index))
	if listed_labels != available_labels:
		problems.append("The popup lists %s but the available actions are %s." % [listed_labels, available_labels])
	var chosen_index := maxi(0, listed_labels.find(test_case.headers.get("popup_action", "")))
	popup.index_pressed.emit(chosen_index)
	popup.free()
	problems.append_array(_check_edit(test_case, editor))
	return problems


func _check_settings_registration() -> PackedStringArray:
	var problems := PackedStringArray()
	var prefix := GDSExPluginProjectSettings.SECTION + "/"
	var names_before := _setting_names(prefix)
	GDSExPluginProjectSettings.register()
	var names := _setting_names(prefix)
	if names.size() != SETTING_COUNT:
		problems.append("Expected %d registered settings, found %d: %s" % [SETTING_COUNT, names.size(), names])
	for setting_name in names:
		var value: Variant = ProjectSettings.get_setting(setting_name)
		if value != ProjectSettings.property_get_revert(setting_name):
			problems.append("%s does not start at its default value." % setting_name)
	if GDSExPluginProjectSettings.class_member_order() != PackedStringArray(GDSExPluginProjectSettings.DEFAULT_CLASS_MEMBER_ORDER) or GDSExPluginProjectSettings.generated_param_format() != GDSExPluginProjectSettings.DEFAULT_GENERATED_PARAM_FORMAT:
		problems.append("The settings do not return the defaults when nothing is overridden.")

	var blank_lines := GDSExPluginProjectSettings.setting_path(GDSExPluginProjectSettings.BLANK_LINES_AROUND_FUNCTIONS_AND_CLASSES_KEY)
	ProjectSettings.set_setting(blank_lines, 4)
	if GDSExPluginProjectSettings.blank_lines_around_functions_and_classes() != 4:
		problems.append("An overridden value is not returned.")
	ProjectSettings.set_setting(blank_lines, "many")
	if GDSExPluginProjectSettings.blank_lines_around_functions_and_classes() != GDSExPluginProjectSettings.DEFAULT_BLANK_LINES_AROUND_FUNCTIONS_AND_CLASSES:
		problems.append("A value of the wrong type should fall back to the default.")
	ProjectSettings.set_setting(blank_lines, -3)
	if GDSExPluginProjectSettings.blank_lines_around_functions_and_classes() != 0:
		problems.append("A negative amount of blank lines should count as zero.")

	for setting_name in names:
		ProjectSettings.set_setting(setting_name, null)
	if not names_before.is_empty():
		problems.append("The project overrides plugin settings, so the other cases do not run with the defaults: %s" % [names_before])
	return problems


func _setting_names(prefix: String) -> PackedStringArray:
	var names := PackedStringArray()
	for property in ProjectSettings.get_property_list():
		var property_name: String = property["name"]
		if property_name.begins_with(prefix) and ProjectSettings.has_setting(property_name):
			names.append(property_name)
	return names


func _check_layout_of_project_scripts(action_name: String, keeps_line_order: bool) -> PackedStringArray:
	var problems := PackedStringArray()
	var action := _find_code_action(action_name)
	for path in _project_script_paths():
		_script_path = path
		var original := FileAccess.get_file_as_string(path)
		var editor := CodeEdit.new()
		root.add_child(editor)
		editor.text = original
		var class_names := _inner_class_names(GDSExSymbolIndexBuilder.build(original.split("\n")).root)
		_apply_to_every_class(editor, action, class_names)
		var changed := editor.text
		var keeps_code := _code_lines(changed) == _code_lines(original)
		if keeps_line_order:
			keeps_code = _compact_code(changed) == _compact_code(original) and _string_literals(changed) == _string_literals(original)
		if not keeps_code:
			problems.append("%s: %s lost, duplicated or misplaced code." % [path, action_name])
		var script := GDScript.new()
		script.source_code = changed
		if script.reload() != OK:
			problems.append("%s: the script does not compile after %s." % [path, action_name])
		else:
			problems.append_array(_compare_scripts(path, load(path) as GDScript, script))
		_apply_to_every_class(editor, action, class_names)
		if editor.text != changed:
			problems.append("%s: running %s a second time changes the script again." % [path, action_name])
		editor.free()
	return problems


func _check_explicit_types_of_project_scripts() -> PackedStringArray:
	var problems := PackedStringArray()
	var action := _find_code_action(EXPLICIT_TYPE_ACTION)
	var editor := CodeEdit.new()
	root.add_child(editor)
	var typed_count := 0
	for path in _project_script_paths():
		_script_path = path
		var original := FileAccess.get_file_as_string(path)
		editor.text = original
		var plan := action.build_plan(_context(editor))
		if plan == null:
			continue
		typed_count += plan.replacements.size()
		GDSExEditApplier.apply(editor, plan)
		if editor.get_line_count() != original.count("\n") + 1:
			problems.append("%s: adding the types changed the number of lines." % path)
		var script := GDScript.new()
		script.source_code = editor.text
		if script.reload() != OK:
			problems.append("%s: the script does not compile after adding the types." % path)
			continue
		problems.append_array(_compare_scripts(path, load(path) as GDScript, script))
		problems.append_array(_compare_property_types(path, load(path) as GDScript, script))
		if action.build_plan(_context(editor)) != null:
			problems.append("%s: running the action a second time changes the script again." % path)
		var typed_lines := editor.text.split("\n")
		editor.text = _split_inferred_operators(original)
		GDSExEditApplier.apply(editor, action.build_plan(_context(editor)))
		var original_lines := original.split("\n")
		for line in typed_lines.size():
			if typed_lines[line] != original_lines[line] and editor.get_line(line) != typed_lines[line]:
				problems.append("%s: line %d gets another result when its operator is written with spaces." % [path, line + 1])
	if typed_count == 0:
		problems.append("No variable of the project got a type.")
	editor.free()
	return problems


func _split_inferred_operators(source: String) -> String:
	var lines := source.split("\n")
	var declaration_count := 0
	for symbol in GDSExSymbolIndex.find_variables(GDSExSymbolIndexBuilder.build(lines).root):
		var declaration := symbol.declaration
		if declaration == null or not declaration.is_inferred:
			continue
		var from := symbol.statement.position_at(declaration.start)
		var to := symbol.statement.position_at(declaration.value_start)
		if to.x != from.x:
			to = symbol.statement.position_at(declaration.operator_end)
		lines[from.x] = lines[from.x].substr(0, from.y) + SPLIT_OPERATORS[declaration_count % SPLIT_OPERATORS.size()] + lines[from.x].substr(to.y)
		declaration_count += 1
	return "\n".join(lines)


func _check_script_library() -> PackedStringArray:
	var problems := PackedStringArray()
	var shapes_path := FIXTURES_ROOT.path_join("shapes.gd")
	GDSExScriptLibrary.clear()
	GDSExScriptLibrary.refresh({})
	var shapes := GDSExScriptLibrary.find_index(shapes_path)
	if shapes == null:
		return PackedStringArray(["The library does not find %s." % shapes_path])
	_expect(problems, "path of the index", shapes.script_path, shapes_path)
	_expect(problems, "inner classes of the script", _inner_class_names(shapes.root), PackedStringArray(["Circle", "Center"]))
	_expect(problems, "functions of the script", shapes.root.functions.keys(), ["make", "make_all", "by_name", "kind_of", "count_of", "guess", "total", "pick"])
	var center := GDSExSymbolIndex.find_class(shapes.root, "Center")
	_expect(problems, "index found from an inner class", GDSExSymbolIndex.find_index(center) == shapes, true)
	_expect(problems, "index found from a function", GDSExSymbolIndex.find_index(shapes.root.functions["total"][0]) == shapes, true)
	_expect(problems, "same analysis on a second request", GDSExScriptLibrary.find_index(shapes_path) == shapes, true)
	GDSExScriptLibrary.refresh({})
	_expect(problems, "same analysis while the file does not change", GDSExScriptLibrary.find_index(shapes_path) == shapes, true)

	_expect(problems, "missing file", GDSExScriptLibrary.find_index(FIXTURES_ROOT.path_join("missing.gd")) == null, true)
	_expect(problems, "file that is not a script", GDSExScriptLibrary.find_index("res://icon.svg") == null, true)
	_expect(problems, "empty path", GDSExScriptLibrary.find_index("") == null, true)

	DirAccess.make_dir_recursive_absolute(TEMPORARY_ROOT)
	var temporary_path := TEMPORARY_ROOT.path_join("library_script.gd")
	_write_file(temporary_path, LIBRARY_SCRIPT_VERSIONS[0])
	GDSExScriptLibrary.refresh({})
	var first_version := GDSExScriptLibrary.find_index(temporary_path)
	_expect(problems, "functions of the first version", first_version.root.functions.keys(), ["first"])
	_write_file(temporary_path, LIBRARY_SCRIPT_VERSIONS[1])
	_expect(problems, "a changed file is not read again before the next menu", GDSExScriptLibrary.find_index(temporary_path) == first_version, true)
	GDSExScriptLibrary.refresh({})
	_expect(problems, "functions after the file changes", GDSExScriptLibrary.find_index(temporary_path).root.functions.keys(), ["second"])
	GDSExScriptLibrary.refresh({temporary_path: LIBRARY_SCRIPT_VERSIONS[2]})
	_expect(problems, "functions of the unsaved text", GDSExScriptLibrary.find_index(temporary_path).root.functions.keys(), ["unsaved"])
	GDSExScriptLibrary.refresh({})
	_expect(problems, "functions once the unsaved text is gone", GDSExScriptLibrary.find_index(temporary_path).root.functions.keys(), ["second"])
	_write_file(temporary_path, LIBRARY_SCRIPT_VERSIONS[1].replace("\n", "\r\n"))
	GDSExScriptLibrary.refresh({})
	_expect(problems, "functions of a file with Windows line endings", GDSExScriptLibrary.find_index(temporary_path).root.functions.keys(), ["second"])
	DirAccess.remove_absolute(temporary_path)
	GDSExScriptLibrary.refresh({})
	_expect(problems, "deleted file", GDSExScriptLibrary.find_index(temporary_path) == null, true)
	var unsaved_path := TEMPORARY_ROOT.path_join("never_saved.gd")
	GDSExScriptLibrary.refresh({unsaved_path: LIBRARY_SCRIPT_VERSIONS[2]})
	_expect(problems, "functions of a script that only exists in a tab", GDSExScriptLibrary.find_index(unsaved_path).root.functions.keys(), ["unsaved"])

	var consumer_path := FIXTURES_ROOT.path_join("consumer.gd")
	_expect(problems, "absolute path", GDSExSymbolIndex.resolve_script_path(shapes_path, consumer_path), shapes_path)
	_expect(problems, "relative path", GDSExSymbolIndex.resolve_script_path("shapes.gd", consumer_path), shapes_path)
	_expect(problems, "relative path through the parent folder", GDSExSymbolIndex.resolve_script_path("../other_scripts/shapes.gd", consumer_path), shapes_path)
	_expect(problems, "relative path without a known folder", GDSExSymbolIndex.resolve_script_path("shapes.gd", ""), "")
	_expect(problems, "unknown uid", GDSExSymbolIndex.resolve_script_path("uid://gdsex0unknown0uid", consumer_path), "")
	var uid := ResourceUID.create_id()
	ResourceUID.add_id(uid, shapes_path)
	var uid_text := ResourceUID.id_to_text(uid)
	_expect(problems, "known uid", GDSExSymbolIndex.resolve_script_path(uid_text, ""), shapes_path)
	var with_uid := GDSExSymbolIndexBuilder.build(PackedStringArray(["extends RefCounted", "const Shapes = preload(\"%s\")" % uid_text, "const Missing = preload(\"uid://gdsex0unknown0uid\")"]))
	_expect(problems, "path of a constant loaded by uid", (with_uid.root.vars["Shapes"] as GDSExSymbolIndex.GDSExVariableSymbol).script_path, shapes_path)
	_expect(problems, "constant loaded by an unknown uid is not a script", (with_uid.root.vars["Missing"] as GDSExSymbolIndex.GDSExVariableSymbol).is_script_alias, false)
	ResourceUID.remove_id(uid)

	GDSExScriptLibrary.refresh({})
	var cycle_first := GDSExScriptLibrary.find_index(FIXTURES_ROOT.path_join("cycle_first.gd"))
	var cycle_second := GDSExScriptLibrary.find_index((cycle_first.root.vars["CycleSecond"] as GDSExSymbolIndex.GDSExVariableSymbol).script_path)
	_expect(problems, "second script of the cycle", cycle_second != null and cycle_second.script_path == FIXTURES_ROOT.path_join("cycle_second.gd"), true)
	_expect(problems, "the cycle leads back to the first script", GDSExScriptLibrary.find_index((cycle_second.root.vars["CycleFirst"] as GDSExSymbolIndex.GDSExVariableSymbol).script_path) == cycle_first, true)

	GDSExScriptLibrary.clear()
	var before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for round_index in MEMORY_CHECK_BUILDS:
		GDSExScriptLibrary.refresh({shapes_path: "%s\n# %d" % [LIBRARY_SCRIPT_VERSIONS[0], round_index]})
		GDSExScriptLibrary.find_index(shapes_path)
	GDSExScriptLibrary.clear()
	var leaked := int(Performance.get_monitor(Performance.OBJECT_COUNT)) - before
	if leaked >= MEMORY_CHECK_BUILDS:
		problems.append("%d objects still alive after %d analyses of the library." % [leaked, MEMORY_CHECK_BUILDS])
	DirAccess.remove_absolute(TEMPORARY_ROOT)
	return problems


func _write_file(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func _compare_property_types(path: String, original: GDScript, changed: GDScript) -> PackedStringArray:
	var problems := PackedStringArray()
	var changed_types: Dictionary[String, String] = {}
	for property in changed.get_script_property_list():
		changed_types[property["name"]] = _property_type_label(property)
	for property in original.get_script_property_list():
		var type_label := _property_type_label(property)
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE != 0 and changed_types.get(property["name"], type_label) != type_label:
			problems.append("%s: the engine sees %s as %s instead of %s afterwards." % [path, property["name"], changed_types[property["name"]], type_label])
	return problems


func _property_type_label(property: Dictionary) -> String:
	return "%s %s %s" % [type_string(property["type"]), property["class_name"], property["hint_string"]]


func _apply_to_every_class(editor: CodeEdit, action: GDSExCodeAction, class_names: PackedStringArray) -> void:
	editor.set_caret_line(0)
	GDSExEditApplier.apply(editor, action.build_plan(_context(editor)))
	for inner_name in class_names:
		var scope := GDSExSymbolIndex.find_class(GDSExSymbolIndexBuilder.build(editor.text.split("\n")).root, inner_name)
		if scope != null and scope.body_start_line != -1:
			editor.set_caret_line(scope.body_start_line)
			GDSExEditApplier.apply(editor, action.build_plan(_context(editor)))


func _inner_class_names(class_scope: GDSExSymbolIndex.GDSExClassScope) -> PackedStringArray:
	var names := PackedStringArray()
	for inner_name: String in class_scope.inner_classes:
		names.append(inner_name)
		names.append_array(_inner_class_names(class_scope.inner_classes[inner_name]))
	return names


func _code_lines(text: String) -> PackedStringArray:
	var code_lines := PackedStringArray()
	for line in text.split("\n"):
		if not line.strip_edges().is_empty():
			code_lines.append(line)
	code_lines.sort()
	return code_lines


func _string_literals(text: String) -> PackedStringArray:
	var literals := PackedStringArray()
	for literal in RegEx.create_from_string(STRING_LITERAL_PATTERN).search_all(text):
		literals.append(literal.get_string())
	return literals


func _compact_code(text: String) -> String:
	var compact := text
	for blank in BLANK_CHARACTERS:
		compact = compact.replace(blank, "")
	for closing in COLLECTION_CLOSINGS:
		compact = compact.replace("," + closing, closing)
	return compact


func _compare_scripts(path: String, original: GDScript, changed: GDScript) -> PackedStringArray:
	var problems := PackedStringArray()
	var original_members := [_names_of(original.get_script_method_list(), 0), _names_of(original.get_script_signal_list(), 0), _names_of(original.get_script_property_list(), PROPERTY_USAGE_SCRIPT_VARIABLE), original.get_script_constant_map().keys()]
	var changed_members := [_names_of(changed.get_script_method_list(), 0), _names_of(changed.get_script_signal_list(), 0), _names_of(changed.get_script_property_list(), PROPERTY_USAGE_SCRIPT_VARIABLE), changed.get_script_constant_map().keys()]
	for index in original_members.size():
		var before: Array = original_members[index]
		var after: Array = changed_members[index]
		before.sort()
		after.sort()
		if before != after:
			problems.append("%s: the engine sees different members afterwards.\n  before: %s\n  after:  %s" % [path, before, after])
	var original_constants := original.get_script_constant_map()
	var changed_constants := changed.get_script_constant_map()
	for constant_name: String in original_constants:
		var value: Variant = original_constants[constant_name]
		if typeof(value) != TYPE_OBJECT and changed_constants.has(constant_name) and changed_constants[constant_name] != value:
			problems.append("%s: the constant %s has a different value afterwards." % [path, constant_name])
	return problems


func _check_no_undefined_identifiers() -> PackedStringArray:
	var problems := PackedStringArray()
	var action := GDSExVariableAction.new()
	var identifier_pattern := RegEx.create_from_string("[A-Za-z_]\\w*")
	for path in _project_script_paths():
		var index := GDSExSymbolIndexBuilder.build(FileAccess.get_file_as_string(path).split("\n"))
		_collect_undefined_identifiers(path, index, index.statements, action, identifier_pattern, problems)
	return problems


func _collect_undefined_identifiers(path: String, index: GDSExSymbolIndex.GDSExSymbolIndexData, statements: Array[GDSExSourceScanner.GDSExStatement], action: GDSExVariableAction, identifier_pattern: RegEx, problems: PackedStringArray) -> void:
	for statement in statements:
		var scope_info := GDSExSymbolIndex.get_scope_info_for_line(index, statement.first_line)
		for occurrence in identifier_pattern.search_all(statement.code):
			var identifier := action.find_undefined_identifier_at(statement.code, occurrence.get_start(), occurrence.get_end(), scope_info)
			if identifier != null:
				problems.append("%s:%d: '%s' is defined but was taken for an undefined identifier." % [path, statement.first_line + 1, identifier.name])
		for block in statement.blocks:
			_collect_undefined_identifiers(path, index, block.statements, action, identifier_pattern, problems)


func _collect_false_targets(path: String, index: GDSExSymbolIndex.GDSExSymbolIndexData, statements: Array[GDSExSourceScanner.GDSExStatement], generator: GDSExGenerateFunctionAction, problems: PackedStringArray) -> void:
	for statement in statements:
		var scope_info := GDSExSymbolIndex.get_scope_info_for_line(index, statement.first_line)
		for target in generator.find_targets(statement.code, scope_info):
			problems.append("%s:%d: '%s' is defined but was taken for an undefined function." % [path, statement.first_line + 1, target.name])
		for block in statement.blocks:
			_collect_false_targets(path, index, block.statements, generator, problems)


func _compare_with_engine(path: String, root_class: GDSExSymbolIndex.GDSExClassScope, script: GDScript) -> PackedStringArray:
	var problems := PackedStringArray()
	var base_script := script.get_base_script() as GDScript
	var inherited_functions: Array = [] if base_script == null else _names_of(base_script.get_script_method_list(), 0)
	var inherited_variables: Array = [] if base_script == null else _names_of(base_script.get_script_property_list(), PROPERTY_USAGE_SCRIPT_VARIABLE)
	var engine_functions := _unique(_names_of(script.get_script_method_list(), 0).filter(func(function_name: String) -> bool: return not function_name.begins_with(INTERNAL_FUNCTION_PREFIX)))
	var indexed_functions := _unique(root_class.functions.keys() + inherited_functions.filter(func(function_name: String) -> bool: return not function_name.begins_with(INTERNAL_FUNCTION_PREFIX)))
	engine_functions.sort()
	indexed_functions.sort()
	if engine_functions != indexed_functions:
		problems.append("%s: functions differ.\n  engine: %s\n  index:  %s" % [path, engine_functions, indexed_functions])

	var engine_signals := _names_of(script.get_script_signal_list(), 0)
	var indexed_signals: Array = root_class.signals.keys()
	engine_signals.sort()
	indexed_signals.sort()
	if engine_signals != indexed_signals:
		problems.append("%s: signals differ.\n  engine: %s\n  index:  %s" % [path, engine_signals, indexed_signals])

	var constants := script.get_script_constant_map()
	for variable_name: String in root_class.vars:
		var variable: GDSExSymbolIndex.GDSExVariableSymbol = root_class.vars[variable_name]
		if variable.is_const and not constants.has(variable_name):
			problems.append("%s: constant '%s' is unknown to the engine." % [path, variable_name])
	for inner_class_name: String in root_class.inner_classes:
		if not constants.has(inner_class_name):
			problems.append("%s: inner class '%s' is unknown to the engine." % [path, inner_class_name])
	for variable_name: String in _names_of(script.get_script_property_list(), PROPERTY_USAGE_SCRIPT_VARIABLE):
		if not root_class.vars.has(variable_name) and not inherited_variables.has(variable_name):
			problems.append("%s: variable '%s' is missing from the index." % [path, variable_name])
	return problems


func _unique(names: Array) -> Array:
	var unique_names: Array = []
	for entry: String in names:
		if not unique_names.has(entry):
			unique_names.append(entry)
	return unique_names


func _names_of(entries: Array[Dictionary], required_usage: int) -> Array:
	var names: Array = []
	for entry in entries:
		if required_usage == 0 or entry.get("usage", 0) & required_usage != 0:
			names.append(String(entry["name"]))
	return names


func _check_index_memory(editor: CodeEdit) -> PackedStringArray:
	var lines := editor.text.split("\n")
	var before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for i in MEMORY_CHECK_BUILDS:
		GDSExSymbolIndexBuilder.build(lines)
	var leaked := int(Performance.get_monitor(Performance.OBJECT_COUNT)) - before
	if leaked >= MEMORY_CHECK_BUILDS:
		return PackedStringArray(["%d objects still alive after %d index builds." % [leaked, MEMORY_CHECK_BUILDS]])
	return PackedStringArray()


func _render_with_marks(editor: CodeEdit) -> String:
	var lines := editor.text.split("\n")
	if editor.has_selection():
		_insert_mark(lines, editor.get_selection_to_line(), editor.get_selection_to_column(), SELECTION_CLOSE)
		_insert_mark(lines, editor.get_selection_from_line(), editor.get_selection_from_column(), SELECTION_OPEN)
	else:
		_insert_mark(lines, editor.get_caret_line(), editor.get_caret_column(), CARET_MARK)
	return "\n".join(lines)


func _insert_mark(lines: PackedStringArray, line: int, column: int, mark: String) -> void:
	lines[line] = lines[line].insert(column, mark)


func _visualize(text: String) -> String:
	var rendered := PackedStringArray()
	var lines := text.split("\n")
	for i in lines.size():
		rendered.append("%3d| %s" % [i, lines[i].replace("\t", "→   ").replace(" ", "·")])
	return "\n".join(rendered)


func _report(test_case: TestCase, problems: PackedStringArray) -> void:
	if test_case.is_pending and not problems.is_empty():
		_pending.append(test_case.name)
		print("PENDING  %s" % test_case.name)
		if _shows_pending_details:
			_print_problems(problems)
		return
	if test_case.is_pending:
		problems.append("The case passes now. Remove 'status: pending'.")
	if problems.is_empty():
		_passed.append(test_case.name)
		print("PASS     %s" % test_case.name)
		return
	_fail(test_case, problems)


func _fail(test_case: TestCase, problems: PackedStringArray) -> void:
	_failed.append(test_case.name)
	print("FAIL     %s" % test_case.name)
	_print_problems(problems)


func _print_problems(problems: PackedStringArray) -> void:
	for problem in problems:
		print(problem.indent("         "))
