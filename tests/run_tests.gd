extends SceneTree

const Generator = preload("res://addons/code_generator/stub_generator.gd")
const SymbolApi = preload("res://addons/code_generator/symbol_index.gd")
const Snippet = preload("res://addons/code_generator/editing/snippet.gd")
const EditPlan = preload("res://addons/code_generator/editing/edit_plan.gd")
const EditApplier = preload("res://addons/code_generator/editing/edit_applier.gd")

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
	for path in _collect_case_paths(CASES_ROOT):
		if _matches_filters(path, filters):
			_run_case(path)
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


func _collect_case_paths(directory: String) -> PackedStringArray:
	var paths := PackedStringArray()
	for subdirectory in DirAccess.get_directories_at(directory):
		paths.append_array(_collect_case_paths(directory.path_join(subdirectory)))
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() == CASE_EXTENSION:
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
	var problems := _run_action(test_case, editor)
	for error in _error_collector.take():
		problems.append("Engine error: %s" % error)
	editor.free()
	_report(test_case, problems)


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
	return test_case


func _check_expected_compiles(test_case: TestCase) -> PackedStringArray:
	var problems := PackedStringArray()
	if test_case.skips_compile_check:
		return problems
	var script := GDScript.new()
	script.source_code = test_case.expected.text
	_error_collector.take()
	if script.reload() != OK:
		problems.append("The expected text is not valid GDScript.")
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
		"generate_method":
			Generator.new().generate_stub(editor)
			return _check_edit(test_case, editor)
		"apply_plan":
			EditApplier.apply(editor, _build_plan(test_case.plan_description))
			return _check_edit(test_case, editor)
		"check_index_memory":
			return _check_index_memory(editor)
	return PackedStringArray(["Unknown action '%s'." % test_case.action])


func _build_plan(description: String) -> EditPlan:
	var plan := EditPlan.new()
	for entry: Dictionary in JSON.parse_string(description):
		var point := EditPlan.InsertionPoint.new()
		point.line = int(entry.get("line", 0))
		point.indent_text = entry.get("indent_text", "")
		point.blank_lines_before = int(entry.get("blank_lines_before", 0))
		point.blank_lines_after = int(entry.get("blank_lines_after", 0))
		var snippet := Snippet.new()
		for line: Array in entry.get("lines", []):
			snippet.add_line(int(line[0]), line[1])
		if entry.has("select"):
			var selection: Array = entry["select"]
			snippet.select(int(selection[0]), int(selection[1]), int(selection[2]))
		plan.insert(point, snippet)
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


func _check_index_memory(editor: CodeEdit) -> PackedStringArray:
	var lines := editor.text.split("\n")
	var before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for i in MEMORY_CHECK_BUILDS:
		SymbolApi.build_symbol_index(lines)
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
