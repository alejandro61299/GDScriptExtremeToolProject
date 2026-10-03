@tool
extends RefCounted

const STRING_FILLER: String = "?"
const OPENING_BRACKETS: String = "([{"
const CLOSING_BRACKETS: String = ")]}"
const COMMENT_START: String = "#"
const FUNCTION_KEYWORD: String = "func"
const BLOCK_OPENER: String = ":"
const LINE_CONTINUATION: String = "\\"


class Block:
	var header_line: int = 0
	var opened_by_function: bool = false
	var header_code: String = ""
	var indent_text: String = ""
	var last_line: int = 0
	var trailing_comment_line: int = -1
	var statements: Array[Statement] = []


class Statement:
	var first_line: int = 0
	var own_last_line: int = 0
	var last_line: int = 0
	var indent_text: String = ""
	var code: String = ""
	var blocks: Array[Block] = []


class Frame:
	var block: Block
	var owner: Statement
	var indent_length: int = 0
	var resume_depth: int = 0


var _frames: Array[Frame] = []
var _open_statement: Statement
var _depth: int = 0
var _string_delimiter: String = ""
var _pending_frame: Frame
var _pending_comments: Array[Vector2i] = []


func scan(lines: PackedStringArray) -> Array[Statement]:
	var root := Block.new()
	var root_frame := Frame.new()
	root_frame.block = root
	_frames.clear()
	_frames.append(root_frame)
	for line_index in lines.size():
		_scan_line(lines[line_index], line_index)
	while _frames.size() > 1:
		_close_frame(_frames.pop_back())
	_finish_block(root)
	return root.statements


static func find_matching_bracket(code: String, open_index: int) -> int:
	var depth := 0
	for index in range(open_index, code.length()):
		var character := code[index]
		if OPENING_BRACKETS.contains(character):
			depth += 1
		elif CLOSING_BRACKETS.contains(character):
			depth -= 1
			if depth == 0:
				return index
	return -1


static func is_identifier_character(character: String) -> bool:
	return character == "_" or (character >= "a" and character <= "z") or (character >= "A" and character <= "Z") or (character >= "0" and character <= "9")


static func skip_spaces(code: String, index: int) -> int:
	while index < code.length() and (code[index] == " " or code[index] == "\t"):
		index += 1
	return index


func _scan_line(raw: String, line_index: int) -> void:
	var masked := _mask(raw)
	var has_code := not masked.strip_edges().is_empty()
	if _open_statement != null:
		if has_code:
			_append_code(masked, line_index)
		return
	if not has_code:
		if raw.strip_edges().begins_with(COMMENT_START):
			_pending_comments.append(Vector2i(line_index, _indent_length(raw)))
		return

	var indent_length := _indent_length(raw)
	if _pending_frame != null:
		var pending := _pending_frame
		_pending_frame = null
		if indent_length > pending.owner.indent_text.length():
			pending.indent_length = indent_length
			pending.block.indent_text = raw.substr(0, indent_length)
			pending.owner.blocks.append(pending.block)
			_frames.append(pending)
		elif pending.resume_depth > 0:
			_resume(pending, masked, line_index)
			return

	while _frames.size() > 1 and indent_length < _frames.back().indent_length:
		var frame: Frame = _frames.pop_back()
		_close_frame(frame)
		if frame.resume_depth > 0:
			_resume(frame, masked, line_index)
			return

	_pending_comments.clear()
	var statement := Statement.new()
	statement.first_line = line_index
	statement.own_last_line = line_index
	statement.indent_text = raw.substr(0, indent_length)
	_frames.back().block.statements.append(statement)
	_open_statement = statement
	_depth = 0
	_append_code(masked, line_index)


func _resume(frame: Frame, masked: String, line_index: int) -> void:
	_pending_comments.clear()
	_open_statement = frame.owner
	_depth = frame.resume_depth
	_append_code(masked, line_index)


func _append_code(masked: String, line_index: int) -> void:
	var first_top_level_comma := -1
	for column in masked.length():
		var character := masked[column]
		if OPENING_BRACKETS.contains(character):
			_depth += 1
		elif CLOSING_BRACKETS.contains(character):
			if _depth > 0:
				_depth -= 1
			elif _split_at(masked, column if first_top_level_comma == -1 else first_top_level_comma, line_index):
				return
		elif character == "," and _depth == 0 and first_top_level_comma == -1:
			first_top_level_comma = column

	var text := masked.strip_edges()
	if _depth == 0 and first_top_level_comma != -1 and text.ends_with(",") and _split_at(masked, first_top_level_comma, line_index):
		return

	_add_text(text, line_index)
	if text.ends_with(LINE_CONTINUATION):
		_open_statement.code = _open_statement.code.trim_suffix(LINE_CONTINUATION).strip_edges(false, true)
		return
	if not _string_delimiter.is_empty():
		return
	if text.ends_with(BLOCK_OPENER):
		var function_offset := _trailing_function_offset(_open_statement.code)
		if _depth == 0 or function_offset != -1:
			_open_pending_block(function_offset, line_index)
		return
	if _depth == 0:
		_open_statement = null


func _split_at(masked: String, column: int, line_index: int) -> bool:
	var frame_index := _find_resumable_frame_index()
	if frame_index == -1:
		return false
	_add_text(masked.substr(0, column).strip_edges(), line_index)
	if _open_statement.code.is_empty():
		_frames.back().block.statements.erase(_open_statement)
	_open_statement = null
	var frame: Frame
	while _frames.size() > frame_index:
		frame = _frames.pop_back()
		_close_frame(frame)
	_resume(frame, " ".repeat(column) + masked.substr(column), line_index)
	return true


func _find_resumable_frame_index() -> int:
	for index in range(_frames.size() - 1, 0, -1):
		if _frames[index].resume_depth > 0:
			return index
	return -1


func _add_text(text: String, line_index: int) -> void:
	if text.is_empty():
		return
	_open_statement.code = text if _open_statement.code.is_empty() else _open_statement.code + " " + text
	_open_statement.own_last_line = line_index


func _open_pending_block(function_offset: int, line_index: int) -> void:
	var block := Block.new()
	block.header_line = line_index
	block.opened_by_function = function_offset != -1
	if block.opened_by_function:
		block.header_code = _open_statement.code.substr(function_offset)
	_pending_frame = Frame.new()
	_pending_frame.block = block
	_pending_frame.owner = _open_statement
	_pending_frame.resume_depth = _depth
	_open_statement = null


func _close_frame(frame: Frame) -> void:
	for comment in _pending_comments:
		if comment.y < frame.indent_length:
			break
		frame.block.trailing_comment_line = comment.x


func _finish_block(block: Block) -> void:
	block.last_line = maxi(block.header_line, block.trailing_comment_line)
	for statement in block.statements:
		statement.last_line = statement.own_last_line
		for inner_block in statement.blocks:
			_finish_block(inner_block)
			statement.last_line = maxi(statement.last_line, inner_block.last_line)
		block.last_line = maxi(block.last_line, statement.last_line)


func _mask(raw: String) -> String:
	var masked := ""
	var index := 0
	while index < raw.length():
		var character := raw[index]
		if _string_delimiter.is_empty():
			if character == COMMENT_START:
				break
			if character == "\"" or character == "'":
				var triple := character.repeat(3)
				_string_delimiter = triple if raw.substr(index, 3) == triple else character
				masked += _string_delimiter
				index += _string_delimiter.length()
				continue
			masked += character
			index += 1
		elif character == LINE_CONTINUATION:
			masked += STRING_FILLER.repeat(mini(2, raw.length() - index))
			index += 2
		elif raw.substr(index, _string_delimiter.length()) == _string_delimiter:
			masked += _string_delimiter
			index += _string_delimiter.length()
			_string_delimiter = ""
		else:
			masked += STRING_FILLER
			index += 1
	if _string_delimiter.length() == 1 and not raw.ends_with(LINE_CONTINUATION):
		_string_delimiter = ""
	return masked


func _indent_length(raw: String) -> int:
	return raw.length() - raw.strip_edges(true, false).length()


func _trailing_function_offset(code: String) -> int:
	var offset := code.rfind(FUNCTION_KEYWORD)
	while offset != -1:
		if _is_keyword_at(code, offset):
			return offset if _is_function_header(code, offset + FUNCTION_KEYWORD.length()) else -1
		offset = code.rfind(FUNCTION_KEYWORD, offset - 1) if offset > 0 else -1
	return -1


func _is_keyword_at(code: String, offset: int) -> bool:
	var end := offset + FUNCTION_KEYWORD.length()
	if offset > 0 and is_identifier_character(code[offset - 1]):
		return false
	return end >= code.length() or not is_identifier_character(code[end])


func _is_function_header(code: String, index: int) -> bool:
	index = skip_spaces(code, index)
	while index < code.length() and is_identifier_character(code[index]):
		index += 1
	index = skip_spaces(code, index)
	if index >= code.length() or code[index] != "(":
		return false
	index = find_matching_bracket(code, index)
	if index == -1:
		return false
	index = skip_spaces(code, index + 1)
	if code.substr(index, 2) == "->":
		index = code.find(BLOCK_OPENER, index)
		if index == -1:
			return false
	return index < code.length() and code[index] == BLOCK_OPENER and code.substr(index + 1).strip_edges().is_empty()
