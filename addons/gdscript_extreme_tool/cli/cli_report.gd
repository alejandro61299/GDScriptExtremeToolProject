@tool
extends RefCounted

const GDSExCliSession = preload("res://addons/gdscript_extreme_tool/cli/cli_session.gd")
const GDSExCliLineMap = preload("res://addons/gdscript_extreme_tool/cli/cli_line_map.gd")

enum GDSExMode { LINES, SUMMARY, DIFF }

const LINE_SEPARATOR: String = "\n"
const HEADER_TEMPLATE: String = "%s %s"
const LINE_TEMPLATE: String = "%d\t%s"
const SUFFIX_TEMPLATE: String = "%s  %s"
const WARNING_TEMPLATE: String = "! %s"
const ERROR_TEMPLATE: String = "error: %s"
const DIFF_OLD_HEADER: String = "--- a/%s"
const DIFF_NEW_HEADER: String = "+++ b/%s"
const HUNK_TEMPLATE: String = "@@ -%s +%s @@"
const RANGE_TEMPLATE: String = "%d,%d"
const REMOVED_PREFIX: String = "-"
const ADDED_PREFIX: String = "+"
const PRINTED_FILE_HEADER: String = "=== %s"


static func render(session: GDSExCliSession, mode: GDSExMode) -> String:
	var output := PackedStringArray()
	if mode == GDSExMode.DIFF:
		for block in session.blocks:
			if block.is_error or block.document == null:
				output.append(_block_header(block))
		for document in session.changed_documents():
			output.append_array(diff(document))
		return _joined(output)
	for block in session.blocks:
		output.append(_block_header(block))
		if mode == GDSExMode.SUMMARY or block.document == null:
			continue
		for index in block.lines.size():
			var line := block.lines[index]
			if line == GDSExCliLineMap.REMOVED or line >= block.document.lines.size():
				continue
			var text := LINE_TEMPLATE % [line + 1, block.document.lines[line]]
			output.append(text if block.suffixes[index].is_empty() else SUFFIX_TEMPLATE % [text, block.suffixes[index]])
		for warning in block.warnings:
			output.append(WARNING_TEMPLATE % warning)
	return _joined(output)


static func render_errors(session: GDSExCliSession) -> String:
	var output := PackedStringArray()
	for block in session.blocks:
		output.append(_block_header(block))
		for warning in block.warnings:
			output.append(WARNING_TEMPLATE % warning)
	return _joined(output)


static func render_files(session: GDSExCliSession, documents: Array[GDSExCliSession.GDSExDocument]) -> String:
	if documents.size() == 1:
		return documents[0].text()
	var output := PackedStringArray()
	for document in documents:
		output.append(PRINTED_FILE_HEADER % document.display_path)
		output.append(document.text())
	return LINE_SEPARATOR.join(output)


static func diff(document: GDSExCliSession.GDSExDocument) -> PackedStringArray:
	var old_lines := document.original_lines
	var new_lines := document.lines
	var map := GDSExCliLineMap.between(old_lines, new_lines)
	var output := PackedStringArray([DIFF_OLD_HEADER % document.display_path, DIFF_NEW_HEADER % document.display_path])
	var equal_pairs: Array[Vector2i] = []
	for line in old_lines.size():
		if map[line] != GDSExCliLineMap.REMOVED and old_lines[line] == new_lines[map[line]]:
			equal_pairs.append(Vector2i(line, map[line]))
	equal_pairs.append(Vector2i(old_lines.size(), new_lines.size()))
	var old_start := 0
	var new_start := 0
	for pair in equal_pairs:
		if pair.x > old_start or pair.y > new_start:
			output.append(HUNK_TEMPLATE % [_range(old_start, pair.x - old_start), _range(new_start, pair.y - new_start)])
			for line in range(old_start, pair.x):
				output.append(REMOVED_PREFIX + old_lines[line])
			for line in range(new_start, pair.y):
				output.append(ADDED_PREFIX + new_lines[line])
		old_start = pair.x + 1
		new_start = pair.y + 1
	return output


static func _range(start: int, count: int) -> String:
	if count == 0:
		return RANGE_TEMPLATE % [start, 0]
	if count == 1:
		return str(start + 1)
	return RANGE_TEMPLATE % [start + 1, count]


static func _block_header(block: GDSExCliSession.GDSExBlock) -> String:
	if block.is_error:
		return ERROR_TEMPLATE % block.summary
	if block.document == null:
		return block.summary
	return HEADER_TEMPLATE % [block.document.display_path, block.summary]


static func _joined(output: PackedStringArray) -> String:
	return LINE_SEPARATOR.join(output)
