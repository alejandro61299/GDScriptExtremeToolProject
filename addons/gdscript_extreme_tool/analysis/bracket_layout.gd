@tool
extends RefCounted

const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExBracketGroups = preload("res://addons/gdscript_extreme_tool/analysis/bracket_groups.gd")

const ELEMENT_SEPARATOR: String = ","
const COMMENT_START: String = "#"
const INDENT_CHARACTERS: String = " \t"

enum GDSExIndent { CHILD, ALIGNED, CONTINUATION, TRAILER, SHIFTED }


class GDSExShift:
	var old_prefix: String = ""
	var new_prefix: String = ""
	var header_column: int = 0


class GDSExIndentRule:
	var kind: GDSExIndent = GDSExIndent.CHILD
	var anchor: Vector2i = Vector2i.ZERO
	var shift: GDSExShift


class GDSExSegment:
	var start_column: int = 0
	var indent_text: String = ""
	var starts_line: bool = true


class GDSExLineEdits:
	var start_rule: GDSExIndentRule
	var breaks: Dictionary[int, GDSExIndentRule] = {}
	var added_separator_columns: PackedInt32Array = []
	var removed_columns: PackedInt32Array = []
	var is_removed: bool = false
	var opened_shift: GDSExShift


class GDSExPieceMap:
	var _pieces: Array[GDSExSourceScanner.GDSExPiece] = []
	var _offsets: PackedInt32Array = []

	func _init(statement: GDSExSourceScanner.GDSExStatement) -> void:
		_pieces = statement.pieces
		for piece in _pieces:
			_offsets.append(piece.offset)

	func index_at(offset: int) -> int:
		return maxi(0, _offsets.bsearch(offset, false) - 1)

	func piece_at(offset: int) -> GDSExSourceScanner.GDSExPiece:
		return _pieces[index_at(offset)]

	func position_at(offset: int) -> Vector2i:
		var piece := piece_at(offset)
		return Vector2i(piece.line, piece.column + offset - piece.offset)


var _lines: PackedStringArray = []
var _indent_unit: String = ""
var _edits: Dictionary[int, GDSExLineEdits] = {}
var _segments: Dictionary[int, Array] = {}


func _init(lines: PackedStringArray, indent_unit: String) -> void:
	_lines = lines
	_indent_unit = indent_unit


func rewrite(statements: Array[GDSExSourceScanner.GDSExStatement]) -> Dictionary[int, PackedStringArray]:
	for statement in statements:
		_collect_statement(statement, null)
	var edited_lines := _edits.keys()
	edited_lines.sort()
	var rewrites: Dictionary[int, PackedStringArray] = {}
	for line: int in edited_lines:
		var rewritten := _rewrite_line(line, _edits[line])
		if rewritten.size() != 1 or rewritten[0] != _lines[line]:
			rewrites[line] = rewritten
	return rewrites


func _collect_statement(statement: GDSExSourceScanner.GDSExStatement, shift: GDSExShift) -> void:
	if statement.pieces.is_empty():
		return
	if shift != null and _starts_line(statement.pieces[0]):
		_edits_of(statement.first_line).start_rule = _new_rule(GDSExIndent.SHIFTED, Vector2i.ZERO, shift)
	if statement.pieces.size() > 1 or GDSExBracketGroups.has_collection_brackets(statement.code):
		var groups := GDSExBracketGroups.find(statement.code)
		var pieces := GDSExPieceMap.new(statement)
		for index in range(1, statement.pieces.size()):
			_collect_gap(statement, groups, pieces, statement.pieces[index - 1], statement.pieces[index])
			_collect_line_start(statement, groups, pieces, index)
		for group in groups.groups:
			_collect_group(statement, pieces, group)
	for block in statement.blocks:
		_collect_block(statement, block)


func _collect_line_start(statement: GDSExSourceScanner.GDSExStatement, groups: GDSExBracketGroups.GDSExGroups, pieces: GDSExPieceMap, piece_index: int) -> void:
	var piece := statement.pieces[piece_index]
	if not _starts_line(piece) or statement.string_lines.has(piece.line):
		return
	var anchor := _start_of(statement)
	if _lambda_before(statement, piece_index) != null:
		_edits_of(piece.line).start_rule = _new_rule(GDSExIndent.ALIGNED, anchor, null)
		return
	var group := groups.group_at(piece.offset)
	var closes_group := group != null and group.close_offset == piece.offset
	var kind := GDSExIndent.TRAILER if closes_group or statement.code[piece.offset] == ELEMENT_SEPARATOR else GDSExIndent.CONTINUATION
	if group != null:
		anchor = pieces.position_at(group.open_offset)
		if group.is_collection and not closes_group:
			if _starts_element(statement.code, group, piece.offset):
				kind = GDSExIndent.CHILD
			else:
				anchor = pieces.position_at(_element_start(statement.code, group, piece.offset))
	_edits_of(piece.line).start_rule = _new_rule(kind, anchor, null)


func _collect_gap(statement: GDSExSourceScanner.GDSExStatement, groups: GDSExBracketGroups.GDSExGroups, pieces: GDSExPieceMap, previous: GDSExSourceScanner.GDSExPiece, piece: GDSExSourceScanner.GDSExPiece) -> void:
	var group := groups.group_at(piece.offset)
	if group == null or piece.line - previous.line < 2:
		return
	var anchor := pieces.position_at(group.open_offset)
	for line in range(previous.line + 1, piece.line):
		if statement.string_lines.has(line) or _is_inside_block(statement, line):
			continue
		var text := _lines[line].strip_edges()
		if text.is_empty() and group.is_collection:
			_edits_of(line).is_removed = true
		elif text.begins_with(COMMENT_START):
			_edits_of(line).start_rule = _new_rule(GDSExIndent.CHILD if group.is_collection else GDSExIndent.CONTINUATION, anchor, null)


func _collect_group(statement: GDSExSourceScanner.GDSExStatement, pieces: GDSExPieceMap, group: GDSExBracketGroups.GDSExGroup) -> void:
	var opening := pieces.position_at(group.open_offset)
	var closing := pieces.position_at(group.close_offset)
	if opening.x == closing.x:
		if group.is_collection:
			_remove_trailing_separator(statement.code, pieces, group)
		return
	var lambda := _lambda_ending_at(statement, pieces, group.close_offset)
	if not group.is_collection and lambda == null:
		return
	_edits_of(closing.x).breaks[closing.y] = _new_rule(GDSExIndent.ALIGNED, opening if group.is_collection else _start_of(statement), null)
	if not group.is_collection:
		return
	_break_after_opening(statement.code, pieces, group, opening)
	if lambda != null:
		if not lambda.statements.is_empty():
			_add_separator(_code_end(lambda.statements[lambda.statements.size() - 1]))
		return
	var last_offset := group.close_offset - 1
	while INDENT_CHARACTERS.contains(statement.code[last_offset]):
		last_offset -= 1
	if last_offset != group.open_offset and statement.code[last_offset] != ELEMENT_SEPARATOR:
		_add_separator(pieces.position_at(last_offset) + Vector2i(0, 1))


func _collect_block(statement: GDSExSourceScanner.GDSExStatement, block: GDSExSourceScanner.GDSExBlock) -> void:
	var shift := GDSExShift.new()
	shift.old_prefix = block.indent_text
	shift.new_prefix = block.indent_text
	shift.header_column = _last_code_column(statement, block.header_line)
	_edits_of(block.header_line).opened_shift = shift
	var next_line := block.header_line + 1
	for inner in block.statements:
		_shift_comments(next_line, inner.first_line - 1, shift)
		_collect_statement(inner, shift)
		next_line = inner.last_line + 1
	_shift_comments(next_line, block.last_line, shift)


func _shift_comments(from: int, to: int, shift: GDSExShift) -> void:
	for line in range(from, to + 1):
		if _lines[line].strip_edges().begins_with(COMMENT_START):
			_edits_of(line).start_rule = _new_rule(GDSExIndent.SHIFTED, Vector2i.ZERO, shift)


func _remove_trailing_separator(code: String, pieces: GDSExPieceMap, group: GDSExBracketGroups.GDSExGroup) -> void:
	if group.separator_offsets.is_empty():
		return
	var last_separator := group.separator_offsets[group.separator_offsets.size() - 1]
	if GDSExSourceScanner.skip_spaces(code, last_separator + 1) != group.close_offset:
		return
	var position := pieces.position_at(last_separator)
	_edits_of(position.x).removed_columns.append(position.y)


func _break_after_opening(code: String, pieces: GDSExPieceMap, group: GDSExBracketGroups.GDSExGroup, opening: Vector2i) -> void:
	var piece := pieces.piece_at(group.open_offset)
	var first_offset := GDSExSourceScanner.skip_spaces(code, group.open_offset + 1)
	if first_offset < piece.offset + piece.length:
		_edits_of(opening.x).breaks[opening.y + first_offset - group.open_offset] = _new_rule(GDSExIndent.CHILD, opening, null)


func _add_separator(position: Vector2i) -> void:
	_edits_of(position.x).added_separator_columns.append(position.y)


func _edits_of(line: int) -> GDSExLineEdits:
	if not _edits.has(line):
		_edits[line] = GDSExLineEdits.new()
	return _edits[line]


func _new_rule(kind: GDSExIndent, anchor: Vector2i, shift: GDSExShift) -> GDSExIndentRule:
	var rule := GDSExIndentRule.new()
	rule.kind = kind
	rule.anchor = anchor
	rule.shift = shift
	return rule


func _starts_line(piece: GDSExSourceScanner.GDSExPiece) -> bool:
	return _lines[piece.line].substr(0, piece.column).strip_edges().is_empty()


func _starts_element(code: String, group: GDSExBracketGroups.GDSExGroup, offset: int) -> bool:
	var previous := offset - 1
	while previous > group.open_offset and INDENT_CHARACTERS.contains(code[previous]):
		previous -= 1
	return previous == group.open_offset or code[previous] == ELEMENT_SEPARATOR


func _element_start(code: String, group: GDSExBracketGroups.GDSExGroup, offset: int) -> int:
	var separator_index := group.separator_offsets.bsearch(offset) - 1
	var before := group.open_offset if separator_index < 0 else group.separator_offsets[separator_index]
	return GDSExSourceScanner.skip_spaces(code, before + 1)


func _is_inside_block(statement: GDSExSourceScanner.GDSExStatement, line: int) -> bool:
	for block in statement.blocks:
		if line > block.header_line and line <= block.last_line:
			return true
	return false


func _last_code_column(statement: GDSExSourceScanner.GDSExStatement, line: int) -> int:
	for index in range(statement.pieces.size() - 1, -1, -1):
		var piece := statement.pieces[index]
		if piece.line == line:
			return piece.column + piece.length - 1
	return 0


func _lambda_ending_at(statement: GDSExSourceScanner.GDSExStatement, pieces: GDSExPieceMap, offset: int) -> GDSExSourceScanner.GDSExBlock:
	var piece_index := pieces.index_at(offset)
	if statement.pieces[piece_index].offset != offset:
		return null
	return _lambda_before(statement, piece_index)


func _lambda_before(statement: GDSExSourceScanner.GDSExStatement, piece_index: int) -> GDSExSourceScanner.GDSExBlock:
	if piece_index == 0:
		return null
	var header_line := statement.pieces[piece_index - 1].line
	for block in statement.blocks:
		if block.opened_by_function and block.header_line == header_line:
			return block
	return null


func _start_of(statement: GDSExSourceScanner.GDSExStatement) -> Vector2i:
	return Vector2i(statement.first_line, statement.pieces[0].column)


func _code_end(statement: GDSExSourceScanner.GDSExStatement) -> Vector2i:
	var last_piece := statement.pieces[statement.pieces.size() - 1]
	var end := Vector2i(last_piece.line, last_piece.column + last_piece.length)
	for block in statement.blocks:
		if block.statements.is_empty():
			continue
		var inner_end := _code_end(block.statements[block.statements.size() - 1])
		if inner_end.x > end.x or (inner_end.x == end.x and inner_end.y > end.y):
			end = inner_end
	return end


func _rewrite_line(line: int, edits: GDSExLineEdits) -> PackedStringArray:
	var rewritten := PackedStringArray()
	if edits.is_removed:
		return rewritten
	var raw := _lines[line]
	var old_indent := _indent_of(raw)
	var segments: Array[GDSExSegment] = []
	_segments[line] = segments
	var break_columns := edits.breaks.keys()
	break_columns.sort()
	var rule := edits.start_rule
	var segment_start := old_indent.length()
	for index in break_columns.size() + 1:
		var is_last := index == break_columns.size()
		var segment_end: int = raw.length() if is_last else break_columns[index]
		var text := _edited_text(raw, segment_start, segment_end, edits)
		if not is_last:
			text = text.rstrip(INDENT_CHARACTERS)
		if not text.is_empty():
			var segment := GDSExSegment.new()
			segment.start_column = segment_start
			segment.starts_line = segments.is_empty()
			segment.indent_text = _resolve_indent(rule, old_indent)
			segments.append(segment)
			rewritten.append(segment.indent_text + text)
		if not is_last:
			rule = edits.breaks[break_columns[index]]
			segment_start = segment_end
	if edits.opened_shift != null:
		_resolve_shift(edits.opened_shift, line, old_indent)
	return rewritten


func _edited_text(raw: String, from: int, to: int, edits: GDSExLineEdits) -> String:
	var text := raw.substr(from, to - from)
	var changes: Array[Vector2i] = []
	for column in edits.added_separator_columns:
		if column > from and column <= to:
			changes.append(Vector2i(column, 1))
	for column in edits.removed_columns:
		if column >= from and column < to:
			changes.append(Vector2i(column, 0))
	changes.sort_custom(func(first: Vector2i, second: Vector2i) -> bool: return first.x > second.x)
	for change in changes:
		if change.y == 1:
			text = text.insert(change.x - from, ELEMENT_SEPARATOR)
		else:
			text = text.erase(change.x - from)
	return text


func _resolve_indent(rule: GDSExIndentRule, old_indent: String) -> String:
	if rule == null:
		return old_indent
	if rule.kind == GDSExIndent.SHIFTED:
		return _shifted(old_indent, rule.shift.old_prefix, rule.shift.new_prefix)
	var anchor := _segment_at(rule.anchor)
	match rule.kind:
		GDSExIndent.CHILD:
			return anchor.indent_text + _indent_unit
		GDSExIndent.ALIGNED:
			return anchor.indent_text
	if not anchor.starts_line:
		return anchor.indent_text if rule.kind == GDSExIndent.TRAILER else anchor.indent_text + _indent_unit
	return _shifted(old_indent, _indent_of(_lines[rule.anchor.x]), anchor.indent_text)


func _resolve_shift(shift: GDSExShift, line: int, old_indent: String) -> void:
	var header := _segment_at(Vector2i(line, shift.header_column))
	if header.starts_line and header.indent_text == old_indent:
		return
	var is_nested := shift.old_prefix.length() > old_indent.length() and shift.old_prefix.begins_with(old_indent)
	if header.starts_line and is_nested:
		shift.new_prefix = header.indent_text + shift.old_prefix.trim_prefix(old_indent)
	else:
		shift.new_prefix = header.indent_text + _indent_unit


func _shifted(indent_text: String, old_prefix: String, new_prefix: String) -> String:
	if old_prefix == new_prefix:
		return indent_text
	if indent_text.begins_with(old_prefix):
		return new_prefix + indent_text.trim_prefix(old_prefix)
	return new_prefix


func _segment_at(position: Vector2i) -> GDSExSegment:
	var found: GDSExSegment = null
	if _segments.has(position.x):
		for segment: GDSExSegment in _segments[position.x]:
			if found == null or segment.start_column <= position.y:
				found = segment
	if found == null:
		found = GDSExSegment.new()
		found.indent_text = _indent_of(_lines[position.x])
	return found


func _indent_of(line: String) -> String:
	return line.substr(0, line.length() - line.lstrip(INDENT_CHARACTERS).length())
