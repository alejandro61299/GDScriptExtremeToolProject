@tool
extends RefCounted

const EditPlan = preload("res://addons/code_generator/editing/edit_plan.gd")
const Indentation = preload("res://addons/code_generator/editing/indentation.gd")


class ResolvedInsertion:
	var order: int = 0
	var line: int = 0
	var block_lines: PackedStringArray = []
	var snippet_offset: int = 0
	var snippet_size: int = 0
	var is_revealed: bool = false
	var has_selection: bool = false
	var selection_line: int = 0
	var selection_from: int = 0
	var selection_to: int = 0

	func is_above(other: ResolvedInsertion) -> bool:
		return line < other.line or (line == other.line and order < other.order)


static func apply(editor: CodeEdit, plan: EditPlan) -> void:
	if editor == null or plan == null or plan.is_empty():
		return
	if plan.line_replacement != null:
		_replace_lines(editor, plan.line_replacement)
		return
	var indent_unit := Indentation.detect_unit(editor.text.split("\n"), Indentation.editor_unit(editor))
	var resolved: Array[ResolvedInsertion] = []
	for insertion in plan.insertions:
		var resolved_insertion := _resolve(editor, insertion, indent_unit, resolved.size())
		resolved_insertion.is_revealed = insertion == plan.revealed_insertion
		resolved.append(resolved_insertion)

	var bottom_up: Array[ResolvedInsertion] = resolved.duplicate()
	bottom_up.sort_custom(func(first: ResolvedInsertion, second: ResolvedInsertion) -> bool: return second.is_above(first))

	var replacements: Array[EditPlan.Replacement] = plan.replacements.duplicate()
	replacements.sort_custom(func(first: EditPlan.Replacement, second: EditPlan.Replacement) -> bool: return first.line > second.line or (first.line == second.line and first.from_column > second.from_column))

	var scroll_before := editor.scroll_vertical
	var first_visible_line := editor.get_first_visible_line()

	editor.begin_complex_operation()
	for replacement in replacements:
		editor.remove_text(replacement.line, replacement.from_column, replacement.line, replacement.to_column)
		editor.insert_text(replacement.text, replacement.line, replacement.from_column)
	for insertion in bottom_up:
		_insert_block(editor, insertion)
	editor.end_complex_operation()

	if not _select_first_selection(editor, resolved) and not plan.replacements.is_empty():
		_place_caret_after(editor, plan.replacements[plan.replacements.size() - 1], resolved)

	for insertion in resolved:
		if insertion.is_revealed:
			var first_line := _final_line(insertion, resolved) + insertion.snippet_offset
			_now_and_next_frame(editor, _reveal_lines.bind(first_line, first_line + insertion.snippet_size - 1))
			return
	var lines_inserted_above := 0
	for insertion in resolved:
		if insertion.line <= first_visible_line:
			lines_inserted_above += insertion.block_lines.size()
	_now_and_next_frame(editor, _restore_scroll.bind(scroll_before + lines_inserted_above))


static func _replace_lines(editor: CodeEdit, replacement: EditPlan.LineReplacement) -> void:
	var caret_line := editor.get_caret_line()
	var caret_column := editor.get_caret_column()
	var scroll_before := editor.scroll_vertical
	var breakpoints := _lines_in_range(editor.get_breakpointed_lines(), replacement)
	var bookmarks := _lines_in_range(editor.get_bookmarked_lines(), replacement)
	var folded := _lines_in_range(PackedInt32Array(editor.get_folded_lines()), replacement)
	for line in folded:
		editor.unfold_line(line)

	editor.begin_complex_operation()
	if replacement.lines.is_empty():
		_remove_lines(editor, replacement.first_line, replacement.last_line)
	elif replacement.last_line >= replacement.first_line:
		editor.remove_text(replacement.first_line, 0, replacement.last_line, editor.get_line(replacement.last_line).length())
		editor.insert_text("\n".join(replacement.lines), replacement.first_line, 0)
	else:
		_insert_lines(editor, replacement.first_line, replacement.lines)
	editor.end_complex_operation()

	for line in range(replacement.first_line, replacement.first_line + replacement.lines.size()):
		editor.set_line_as_breakpoint(line, false)
		editor.set_line_as_bookmarked(line, false)
	for line in breakpoints:
		editor.set_line_as_breakpoint(_moved_line(replacement, line), true)
	for line in bookmarks:
		editor.set_line_as_bookmarked(_moved_line(replacement, line), true)
	for line in folded:
		editor.fold_line(_moved_line(replacement, line))

	var new_caret_line := mini(_moved_line(replacement, caret_line), editor.get_line_count() - 1)
	editor.remove_secondary_carets()
	editor.deselect()
	editor.set_caret_line(new_caret_line)
	editor.set_caret_column(caret_column)
	_now_and_next_frame(editor, _restore_scroll.bind(scroll_before + new_caret_line - caret_line))


static func _remove_lines(editor: CodeEdit, first_line: int, last_line: int) -> void:
	if last_line + 1 < editor.get_line_count():
		editor.remove_text(first_line, 0, last_line + 1, 0)
	elif first_line > 0:
		editor.remove_text(first_line - 1, editor.get_line(first_line - 1).length(), last_line, editor.get_line(last_line).length())
	else:
		editor.remove_text(first_line, 0, last_line, editor.get_line(last_line).length())


static func _insert_lines(editor: CodeEdit, line: int, lines: PackedStringArray) -> void:
	var text := "\n".join(lines)
	if line < editor.get_line_count():
		editor.insert_text(text + "\n", line, 0)
		return
	var last_line := editor.get_line_count() - 1
	editor.insert_text("\n" + text, last_line, editor.get_line(last_line).length())


static func _lines_in_range(lines: PackedInt32Array, replacement: EditPlan.LineReplacement) -> PackedInt32Array:
	var inside := PackedInt32Array()
	for line in lines:
		if line >= replacement.first_line and line <= replacement.last_line and replacement.line_map[line - replacement.first_line] != -1:
			inside.append(line)
	return inside


static func _moved_line(replacement: EditPlan.LineReplacement, line: int) -> int:
	if line < replacement.first_line:
		return line
	if line > replacement.last_line:
		return line + replacement.lines.size() - (replacement.last_line - replacement.first_line + 1)
	for candidate in range(line, replacement.first_line - 1, -1):
		var moved := replacement.line_map[candidate - replacement.first_line]
		if moved != -1:
			return moved
	return replacement.first_line


static func _resolve(editor: CodeEdit, insertion: EditPlan.Insertion, indent_unit: String, order: int) -> ResolvedInsertion:
	var point := insertion.point
	var snippet := insertion.snippet
	var line_count := editor.get_line_count()
	var line := clampi(point.line, 0, line_count)
	var blank_above := _count_blank_lines(editor, line - 1, -1)
	var blank_below := _count_blank_lines(editor, line, 1)
	var missing_before := 0
	if line - blank_above > 0:
		missing_before = maxi(0, point.blank_lines_before - blank_above)
	var missing_after := 0
	if line + blank_below < line_count:
		missing_after = maxi(0, point.blank_lines_after - blank_below)

	var resolved := ResolvedInsertion.new()
	resolved.order = order
	resolved.line = line
	for i in missing_before:
		resolved.block_lines.append("")
	resolved.snippet_offset = missing_before
	resolved.snippet_size = snippet.lines.size()
	for index in snippet.lines.size():
		var snippet_line := snippet.lines[index]
		var prefix := ""
		if not snippet_line.text.is_empty():
			prefix = point.indent_text + indent_unit.repeat(snippet_line.indent)
		if snippet.selection_line == index:
			resolved.has_selection = true
			resolved.selection_line = resolved.block_lines.size()
			resolved.selection_from = prefix.length() + snippet.selection_from
			resolved.selection_to = prefix.length() + snippet.selection_to
		resolved.block_lines.append(prefix + snippet_line.text)
	for i in missing_after:
		resolved.block_lines.append("")
	return resolved


static func _count_blank_lines(editor: CodeEdit, from_line: int, step: int) -> int:
	var count := 0
	var line := from_line
	while line >= 0 and line < editor.get_line_count() and editor.get_line(line).strip_edges().is_empty():
		count += 1
		line += step
	return count


static func _insert_block(editor: CodeEdit, insertion: ResolvedInsertion) -> void:
	_insert_lines(editor, insertion.line, insertion.block_lines)


static func _select_first_selection(editor: CodeEdit, resolved: Array[ResolvedInsertion]) -> bool:
	for insertion in resolved:
		if not insertion.has_selection:
			continue
		var line := _final_line(insertion, resolved) + insertion.selection_line
		editor.remove_secondary_carets()
		editor.select(line, insertion.selection_from, line, insertion.selection_to)
		return true
	return false


static func _final_line(insertion: ResolvedInsertion, resolved: Array[ResolvedInsertion]) -> int:
	var line := insertion.line
	for other in resolved:
		if other != insertion and other.is_above(insertion):
			line += other.block_lines.size()
	return line


static func _reveal_lines(editor: CodeEdit, first_line: int, last_line: int) -> void:
	if first_line >= editor.get_first_visible_line() and last_line <= editor.get_last_full_visible_line():
		return
	editor.set_line_as_center_visible((first_line + last_line) / 2)


static func _restore_scroll(editor: CodeEdit, scroll: float) -> void:
	editor.scroll_vertical = scroll


static func _now_and_next_frame(editor: CodeEdit, view_action: Callable) -> void:
	view_action.call(editor)
	if not editor.is_inside_tree():
		return
	var editor_id := editor.get_instance_id()
	editor.get_tree().process_frame.connect(func() -> void:
		var live_editor := instance_from_id(editor_id) as CodeEdit
		if live_editor != null:
			view_action.call(live_editor)
	, CONNECT_ONE_SHOT)


static func _place_caret_after(editor: CodeEdit, replacement: EditPlan.Replacement, resolved: Array[ResolvedInsertion]) -> void:
	var line := replacement.line
	for insertion in resolved:
		if insertion.line <= replacement.line:
			line += insertion.block_lines.size()
	editor.remove_secondary_carets()
	editor.deselect()
	editor.set_caret_line(line)
	editor.set_caret_column(replacement.from_column + replacement.text.length())
