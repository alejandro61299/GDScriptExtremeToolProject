@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")

const CONDITION_CONTINUATIONS: Array[String] = ["elif", "else"]
const LOOP_KEYWORDS: Array[String] = ["for", "while"]
const MATCH_KEYWORD: String = "match"
const RETURN_KEYWORD: String = "return"

enum GDSExRejection {
	NONE,
	NO_SELECTION,
	NOT_IN_FUNCTION,
	PARTIAL_STATEMENT,
	DIFFERENT_BLOCKS,
	SPLIT_CONDITION,
	MATCH_BRANCHES,
	SHARED_LINE,
	OUTER_LOOP_JUMP,
	EARLY_RETURN,
	BARE_SUPER,
}

static var _first_word_pattern := RegEx.create_from_string("^\\w+")
static var _lambda_pattern := RegEx.create_from_string("\\bfunc\\b")
static var _jump_pattern := RegEx.create_from_string("\\b(?:break|continue)\\b")
static var _return_pattern := RegEx.create_from_string("\\breturn\\b\\s*(\\S?)")
static var _await_pattern := RegEx.create_from_string("\\bawait\\b")
static var _bare_super_pattern := RegEx.create_from_string("\\bsuper\\s*\\(")


class GDSExLocation:
	var siblings: Array[GDSExSourceScanner.GDSExStatement] = []
	var index: int = -1
	var owners: Array[GDSExSourceScanner.GDSExStatement] = []


class GDSExRange:
	var rejection: GDSExRejection = GDSExRejection.NONE
	var first_line: int = -1
	var last_line: int = -1
	var siblings: Array[GDSExSourceScanner.GDSExStatement] = []
	var first_index: int = -1
	var last_index: int = -1
	var scope_info: GDSExSymbolIndex.GDSExScopeInfo
	var function: GDSExSymbolIndex.GDSExFunctionScope
	var has_return: bool = false
	var has_value_return: bool = false
	var return_values: PackedStringArray = []
	var return_lines: PackedInt32Array = []
	var ends_with_return: bool = false
	var reaches_function_end: bool = false
	var has_await: bool = false

	func is_valid() -> bool:
		return rejection == GDSExRejection.NONE

	func statements() -> Array[GDSExSourceScanner.GDSExStatement]:
		return siblings.slice(first_index, last_index + 1)

	func first_statement() -> GDSExSourceScanner.GDSExStatement:
		return siblings[first_index]

	func last_statement() -> GDSExSourceScanner.GDSExStatement:
		return siblings[last_index]

	func following_statements() -> Array[GDSExSourceScanner.GDSExStatement]:
		return siblings.slice(last_index + 1)


static func find(index: GDSExSymbolIndex.GDSExSymbolIndexData, lines: PackedStringArray, first_selected_line: int, last_selected_line: int) -> GDSExRange:
	var found := GDSExRange.new()
	found.first_line = first_selected_line
	found.last_line = mini(last_selected_line, lines.size() - 1)
	while found.first_line <= found.last_line and found.first_line >= 0 and lines[found.first_line].strip_edges().is_empty():
		found.first_line += 1
	while found.last_line >= found.first_line and found.last_line >= 0 and lines[found.last_line].strip_edges().is_empty():
		found.last_line -= 1
	var first_code_line := _find_code_line(index, found.first_line, found.last_line, 1)
	var last_code_line := _find_code_line(index, found.last_line, found.first_line, -1)
	if first_selected_line < 0 or first_code_line == -1:
		return _rejected(found, GDSExRejection.NO_SELECTION)
	var location := _locate(index.statements, first_code_line, [])
	if location == null or location.siblings[location.index].first_line != first_code_line:
		return _rejected(found, GDSExRejection.PARTIAL_STATEMENT)
	found.siblings = location.siblings
	found.first_index = location.index
	found.last_index = _find_last_index(found, last_code_line)
	if found.last_index == -1:
		return _rejected(found, GDSExRejection.DIFFERENT_BLOCKS)
	if last_code_line < last_code_line_of(found.last_statement()):
		return _rejected(found, GDSExRejection.DIFFERENT_BLOCKS if _is_inside_block(found.last_statement(), last_code_line) else GDSExRejection.PARTIAL_STATEMENT)
	found.last_line = mini(found.last_line, maxi(last_code_line, found.last_statement().last_line))
	found.scope_info = GDSExSymbolIndex.get_scope_info_for_line(index, first_code_line)
	found.function = found.scope_info.function_scope
	if found.function == null or found.function.body_start_line == -1 or first_code_line < found.function.body_start_line:
		return _rejected(found, GDSExRejection.NOT_IN_FUNCTION)
	if _shares_a_line(location.owners, first_code_line, last_code_line):
		return _rejected(found, GDSExRejection.SHARED_LINE)
	if _splits_a_condition(found):
		return _rejected(found, GDSExRejection.SPLIT_CONDITION)
	if not location.owners.is_empty() and first_word(location.owners[location.owners.size() - 1].code) == MATCH_KEYWORD:
		return _rejected(found, GDSExRejection.MATCH_BRANCHES)
	return _check_control_flow(found)


static func first_word(code: String) -> String:
	var word := _first_word_pattern.search(code)
	return "" if word == null else word.get_string()


static func own_code(statement: GDSExSourceScanner.GDSExStatement) -> String:
	var lambda := _lambda_pattern.search(statement.code)
	return statement.code if lambda == null else statement.code.substr(0, lambda.get_start())


static func last_code_line_of(statement: GDSExSourceScanner.GDSExStatement) -> int:
	var last_line := statement.own_last_line
	for block in statement.blocks:
		if not block.statements.is_empty():
			last_line = maxi(last_line, last_code_line_of(block.statements[block.statements.size() - 1]))
	return last_line


static func _rejected(found: GDSExRange, rejection: GDSExRejection) -> GDSExRange:
	found.rejection = rejection
	return found


static func _find_code_line(index: GDSExSymbolIndex.GDSExSymbolIndexData, from: int, to: int, step: int) -> int:
	var line := from
	while line >= 0 and (line <= to if step > 0 else line >= to):
		if GDSExSourceScanner.find_statement_at(index.statements, line) != null:
			return line
		line += step
	return -1


static func _locate(statements: Array[GDSExSourceScanner.GDSExStatement], line: int, owners: Array[GDSExSourceScanner.GDSExStatement]) -> GDSExLocation:
	for index in statements.size():
		var statement := statements[index]
		if line < statement.first_line or line > statement.last_line:
			continue
		for block in statement.blocks:
			if line > block.header_line and line <= block.last_line:
				var inner_owners := owners.duplicate()
				inner_owners.append(statement)
				var inner := _locate(block.statements, line, inner_owners)
				if inner != null:
					return inner
		var location := GDSExLocation.new()
		location.siblings = statements
		location.index = index
		location.owners = owners
		return location
	return null


static func _find_last_index(found: GDSExRange, last_code_line: int) -> int:
	for index in range(found.first_index, found.siblings.size()):
		var statement := found.siblings[index]
		if last_code_line >= statement.first_line and last_code_line <= statement.last_line:
			return index
	return -1


static func _is_inside_block(statement: GDSExSourceScanner.GDSExStatement, line: int) -> bool:
	for block in statement.blocks:
		if line > block.header_line and line <= block.last_line:
			return true
	return false


static func _shares_a_line(owners: Array[GDSExSourceScanner.GDSExStatement], first_line: int, last_line: int) -> bool:
	for owner in owners:
		for piece in owner.pieces:
			if piece.line >= first_line and piece.line <= last_line:
				return true
	return false


static func _splits_a_condition(found: GDSExRange) -> bool:
	if CONDITION_CONTINUATIONS.has(first_word(found.first_statement().code)):
		return true
	var following := found.following_statements()
	return not following.is_empty() and CONDITION_CONTINUATIONS.has(first_word(following[0].code))


static func _check_control_flow(found: GDSExRange) -> GDSExRange:
	for statement in found.statements():
		var rejection := _scan(statement, 0, found)
		if rejection != GDSExRejection.NONE:
			return _rejected(found, rejection)
	found.ends_with_return = first_word(found.last_statement().code) == RETURN_KEYWORD
	found.reaches_function_end = found.scope_info.scope == found.function and found.last_index == found.siblings.size() - 1
	if found.has_return and not found.ends_with_return and not found.reaches_function_end:
		return _rejected(found, GDSExRejection.EARLY_RETURN)
	return found


static func _scan(statement: GDSExSourceScanner.GDSExStatement, loop_depth: int, found: GDSExRange) -> GDSExRejection:
	var code := own_code(statement)
	var depth := loop_depth + (1 if LOOP_KEYWORDS.has(first_word(code)) else 0)
	if depth == 0 and _jump_pattern.search(code) != null:
		return GDSExRejection.OUTER_LOOP_JUMP
	if _bare_super_pattern.search(code) != null:
		return GDSExRejection.BARE_SUPER
	for returned in _return_pattern.search_all(statement.code):
		if returned.get_start() >= code.length():
			break
		found.has_return = true
		if not returned.get_string(1).is_empty():
			found.has_value_return = true
			found.return_values.append(statement.code.substr(returned.get_start(1)).strip_edges())
			found.return_lines.append(statement.first_line)
	found.has_await = found.has_await or _await_pattern.search(code) != null
	for block in statement.blocks:
		if block.opened_by_function:
			continue
		for inner in block.statements:
			var rejection := _scan(inner, depth, found)
			if rejection != GDSExRejection.NONE:
				return rejection
	return GDSExRejection.NONE
