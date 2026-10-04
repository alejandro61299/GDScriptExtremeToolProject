extends SceneTree

const GDSExActionRegistry = preload("res://addons/gdscript_extreme_tool/actions/action_registry.gd")
const GDSExCodeAction = preload("res://addons/gdscript_extreme_tool/actions/code_action.gd")
const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExGenerateMethodAction = preload("res://addons/gdscript_extreme_tool/actions/generate_method_action.gd")
const GDSExVariableAction = preload("res://addons/gdscript_extreme_tool/actions/variable_action.gd")
const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSymbolIndexBuilder = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index_builder.gd")
const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExSnippet = preload("res://addons/gdscript_extreme_tool/editing/snippet.gd")
const GDSExEditPlan = preload("res://addons/gdscript_extreme_tool/editing/edit_plan.gd")
const GDSExEditApplier = preload("res://addons/gdscript_extreme_tool/editing/edit_applier.gd")
const GDSExSettings = preload("res://addons/gdscript_extreme_tool/settings.gd")
const GDSExDefaultSettings = preload("res://addons/gdscript_extreme_tool/default_settings.gd")

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
const SCRIPT_EXTENSION: String = "gd"
const PROJECT_SCRIPT_ROOTS: Array[String] = ["res://addons", "res://tools"]
const PROJECT_SCRIPTS: Array[String] = ["res://tests/run_tests.gd"]
const INTERNAL_METHOD_PREFIX: String = "@"
const ACTION_SCRIPT_SUFFIX: String = "_action"
const VIEW_WIDTH: float = 900.0
const VIEW_CARET_VISIBLE: String = "caret_visible"
const VIEW_UNCHANGED: String = "unchanged"
const VIEW_SAME_TOP_TEXT: String = "same_top_text"
const VIEW_TEXT_VISIBLE: String = "text_visible"
const VIEW_CARET_ROW_UNCHANGED: String = "caret_row_unchanged"
const REORDER_ACTION: String = "reorder_class_members"
const FORMAT_ACTION: String = "format_class_members"
const SETTING_COUNT: int = 8
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
	var problems := _run_action(test_case, editor)
	editor.free()
	if test_case.viewport_lines > 0 and problems.is_empty():
		problems.append_array(await _check_view(test_case))
	_override_settings(test_case.settings, false)
	for error in _error_collector.take():
		problems.append("Engine error: %s" % error)
	_report(test_case, problems)


func _override_settings(settings: Dictionary, is_applied: bool) -> void:
	for key: String in settings:
		ProjectSettings.set_setting(GDSExSettings.setting_path(key), settings[key] if is_applied else null)


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
	GDSExEditApplier.apply(editor, _build_plan(test_case.plan_description) if test_case.action == PLAN_ACTION else action.build_plan(GDSExCodeContext.new(editor)))
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
	script.source_code = test_case.input.text if test_case.action == SCOPES_ACTION else test_case.expected.text
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
	var is_offered := not GDSExActionRegistry.find_available(actions, GDSExCodeContext.new(editor)).is_empty()
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
	GDSExEditApplier.apply(editor, action.build_plan(GDSExCodeContext.new(editor)))
	if PackedInt32Array(editor.get_folded_lines()) != test_case.expected_folds:
		problems.append("Folded lines are %s instead of %s." % [_one_based(PackedInt32Array(editor.get_folded_lines())), _one_based(test_case.expected_folds)])
	if editor.get_breakpointed_lines() != test_case.expected_breakpoints:
		problems.append("Breakpoints are on lines %s instead of %s." % [_one_based(editor.get_breakpointed_lines()), _one_based(test_case.expected_breakpoints)])
	if editor.get_bookmarked_lines() != test_case.expected_bookmarks:
		problems.append("Bookmarks are on lines %s instead of %s." % [_one_based(editor.get_bookmarked_lines()), _one_based(test_case.expected_bookmarks)])
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
	var index := GDSExSymbolIndexBuilder.build(editor.text.split("\n"))
	var actual := "\n".join(_describe_scope(index.root, 0))
	if actual == test_case.expected_raw:
		return PackedStringArray()
	return PackedStringArray(["Unexpected scopes.\n--- expected ---\n%s\n--- actual ---\n%s" % [test_case.expected_raw, actual]])


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
	var generator := GDSExGenerateMethodAction.new()
	for path in _project_script_paths():
		var index := GDSExSymbolIndexBuilder.build(FileAccess.get_file_as_string(path).split("\n"))
		_collect_false_targets(path, index, index.statements, generator, problems)
	return problems


func _check_settings_registration() -> PackedStringArray:
	var problems := PackedStringArray()
	var prefix := GDSExSettings.SECTION + "/"
	var names_before := _setting_names(prefix)
	GDSExSettings.register()
	var names := _setting_names(prefix)
	if names.size() != SETTING_COUNT:
		problems.append("Expected %d registered settings, found %d: %s" % [SETTING_COUNT, names.size(), names])
	for setting_name in names:
		var value: Variant = ProjectSettings.get_setting(setting_name)
		if value != ProjectSettings.property_get_revert(setting_name):
			problems.append("%s does not start at its default value." % setting_name)
	if GDSExSettings.class_member_order() != PackedStringArray(GDSExDefaultSettings.CLASS_MEMBER_ORDER) or GDSExSettings.generated_param_format() != GDSExDefaultSettings.GENERATED_PARAM_FORMAT:
		problems.append("The settings do not return the defaults when nothing is overridden.")

	var blank_lines := GDSExSettings.setting_path(GDSExSettings.BLANK_LINES_AROUND_METHODS_AND_CLASSES)
	ProjectSettings.set_setting(blank_lines, 4)
	if GDSExSettings.blank_lines_around_methods_and_classes() != 4:
		problems.append("An overridden value is not returned.")
	ProjectSettings.set_setting(blank_lines, "many")
	if GDSExSettings.blank_lines_around_methods_and_classes() != GDSExDefaultSettings.BLANK_LINES_AROUND_METHODS_AND_CLASSES:
		problems.append("A value of the wrong type should fall back to the default.")
	ProjectSettings.set_setting(blank_lines, -3)
	if GDSExSettings.blank_lines_around_methods_and_classes() != 0:
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


func _apply_to_every_class(editor: CodeEdit, action: GDSExCodeAction, class_names: PackedStringArray) -> void:
	editor.set_caret_line(0)
	GDSExEditApplier.apply(editor, action.build_plan(GDSExCodeContext.new(editor)))
	for inner_name in class_names:
		var scope := GDSExSymbolIndex.find_class(GDSExSymbolIndexBuilder.build(editor.text.split("\n")).root, inner_name)
		if scope != null and scope.body_start_line != -1:
			editor.set_caret_line(scope.body_start_line)
			GDSExEditApplier.apply(editor, action.build_plan(GDSExCodeContext.new(editor)))


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


func _collect_false_targets(path: String, index: GDSExSymbolIndex.GDSExSymbolIndexData, statements: Array[GDSExSourceScanner.GDSExStatement], generator: GDSExGenerateMethodAction, problems: PackedStringArray) -> void:
	for statement in statements:
		var scope_info := GDSExSymbolIndex.get_scope_info_for_line(index, statement.first_line)
		for target in generator.find_targets(statement.code, scope_info):
			problems.append("%s:%d: '%s' is defined but was taken for an undefined method." % [path, statement.first_line + 1, target.name])
		for block in statement.blocks:
			_collect_false_targets(path, index, block.statements, generator, problems)


func _compare_with_engine(path: String, root_class: GDSExSymbolIndex.GDSExClassScope, script: GDScript) -> PackedStringArray:
	var problems := PackedStringArray()
	var base_script := script.get_base_script() as GDScript
	var inherited_methods: Array = [] if base_script == null else _names_of(base_script.get_script_method_list(), 0)
	var inherited_variables: Array = [] if base_script == null else _names_of(base_script.get_script_property_list(), PROPERTY_USAGE_SCRIPT_VARIABLE)
	var engine_methods := _unique(_names_of(script.get_script_method_list(), 0).filter(func(method_name: String) -> bool: return not method_name.begins_with(INTERNAL_METHOD_PREFIX)))
	var indexed_methods := _unique(root_class.methods.keys() + inherited_methods.filter(func(method_name: String) -> bool: return not method_name.begins_with(INTERNAL_METHOD_PREFIX)))
	engine_methods.sort()
	indexed_methods.sort()
	if engine_methods != indexed_methods:
		problems.append("%s: methods differ.\n  engine: %s\n  index:  %s" % [path, engine_methods, indexed_methods])

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
