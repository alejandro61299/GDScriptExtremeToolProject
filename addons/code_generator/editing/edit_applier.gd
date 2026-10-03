@tool
extends RefCounted

const EditPlan = preload("res://addons/code_generator/editing/edit_plan.gd")
const Indentation = preload("res://addons/code_generator/editing/indentation.gd")


class ResolvedInsertion:
	var order: int = 0
	var line: int = 0
	var block_lines: PackedStringArray = []
	var has_selection: bool = false
	var selection_line: int = 0
	var selection_from: int = 0
	var selection_to: int = 0

	func is_above(other: ResolvedInsertion) -> bool:
		return line < other.line or (line == other.line and order < other.order)


static func apply(editor: CodeEdit, plan: EditPlan) -> void:
	if editor == null or plan == null or plan.is_empty():
		return
	var indent_unit := Indentation.detect_unit(editor.text.split("\n"), Indentation.editor_unit(editor))
	var resolved: Array[ResolvedInsertion] = []
	for insertion in plan.insertions:
		resolved.append(_resolve(editor, insertion, indent_unit, resolved.size()))

	var bottom_up: Array[ResolvedInsertion] = resolved.duplicate()
	bottom_up.sort_custom(func(first: ResolvedInsertion, second: ResolvedInsertion) -> bool: return second.is_above(first))

	editor.begin_complex_operation()
	for insertion in bottom_up:
		_insert_block(editor, insertion)
	editor.end_complex_operation()

	_select_first_selection(editor, resolved)


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
	var text := "\n".join(insertion.block_lines)
	if insertion.line < editor.get_line_count():
		editor.insert_text(text + "\n", insertion.line, 0)
		return
	var last_line := editor.get_line_count() - 1
	editor.insert_text("\n" + text, last_line, editor.get_line(last_line).length())


static func _select_first_selection(editor: CodeEdit, resolved: Array[ResolvedInsertion]) -> void:
	for insertion in resolved:
		if not insertion.has_selection:
			continue
		var line := insertion.line + insertion.selection_line
		for other in resolved:
			if other != insertion and other.is_above(insertion):
				line += other.block_lines.size()
		editor.remove_secondary_carets()
		editor.select(line, insertion.selection_from, line, insertion.selection_to)
		editor.center_viewport_to_caret()
		return
