@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExBracketLayout = preload("res://addons/gdscript_extreme_tool/analysis/bracket_layout.gd")
const GDSExTokenSpacing = preload("res://addons/gdscript_extreme_tool/analysis/token_spacing.gd")
const GDSExMemberCategories = preload("res://addons/gdscript_extreme_tool/analysis/member_categories.gd")
const GDSExPluginProjectSettings = preload("res://addons/gdscript_extreme_tool/plugin_project_settings.gd")

const COMMENT_START: String = "#"
const REGION_START: String = "#region"
const REGION_END: String = "#endregion"
const SUBGROUP_ANNOTATION: String = "@export_subgroup"
const GROUP_STARTERS: Array[String] = ["@export_category", "@export_group"]
const INDENT_CHARACTERS: String = " \t"

enum GDSExPhase { STATIC, REGULAR, READY }

static var _identifier_pattern := RegEx.create_from_string("(?<![\\w.])[A-Za-z_]\\w*")


class GDSExBlock:
	var first_line: int = 0
	var last_line: int = 0
	var member_first_line: int = 0
	var member_last_line: int = 0
	var category: int = 0
	var is_tall: bool = false
	var original_index: int = 0
	var provided: Dictionary[String, GDSExPhase] = {}
	var required: PackedStringArray = []


class GDSExLayout:
	var first_line: int = 0
	var last_line: int = 0
	var lines: PackedStringArray = []
	var line_map: PackedInt32Array = []


class GDSExDraft:
	var source: PackedStringArray = []
	var first_line: int = 0
	var lines: PackedStringArray = []
	var line_map: PackedInt32Array = []
	var rewrites: Dictionary[int, PackedStringArray] = {}
	var blank_line: String = ""


	func _init(source_lines: PackedStringArray, source_first_line: int, source_last_line: int) -> void:
		source = source_lines
		first_line = source_first_line
		line_map.resize(source_last_line - source_first_line + 1)
		line_map.fill(-1)


	func copy_lines(from: int, to: int) -> void:
		for line in range(from, to + 1):
			_copy_line(line, source[line])


	func copy_limiting_blank_lines(from: int, to: int, max_blank_lines: int) -> void:
		var blank_lines := 0
		for line in range(from, to + 1):
			if not _is_blank_line(line):
				blank_lines = 0
				_copy_line(line, source[line])
				continue
			blank_lines += 1
			if blank_lines <= max_blank_lines:
				_copy_line(line, blank_line)


	func copy_block(block: GDSExBlock, glues_comments: bool) -> void:
		for line in range(block.first_line, block.last_line + 1):
			var is_inside_member := line >= block.member_first_line and line <= block.member_last_line
			if is_inside_member or not glues_comments or not _is_blank_line(line):
				_copy_line(line, source[line])


	func add_blank_lines(count: int, replaced_first_line: int, replaced_count: int) -> void:
		for offset in mini(replaced_count, count):
			line_map[replaced_first_line + offset - first_line] = first_line + lines.size() + offset
		for blank in count:
			lines.append(blank_line)


	func _copy_line(line: int, text: String) -> void:
		if not rewrites.has(line):
			line_map[line - first_line] = first_line + lines.size()
			lines.append(text)
		elif not rewrites[line].is_empty():
			line_map[line - first_line] = first_line + lines.size()
			lines.append_array(rewrites[line])


	func _is_blank_line(line: int) -> bool:
		return source[line].strip_edges().is_empty()


static func reorder(class_scope: GDSExSymbolIndex.GDSExClassScope, lines: PackedStringArray) -> GDSExLayout:
	var body_first := class_scope.header_end_line + 1
	var body_last := _last_line_with_comments(class_scope, lines)
	var blocks := _merge_regions(_build_blocks(class_scope, true), lines, body_first, body_last)
	if blocks.size() < 2:
		return null
	for index in blocks.size():
		blocks[index].original_index = index
	_attach_comments(blocks, lines, body_first, body_last)
	_find_dependencies(blocks, class_scope)
	var ordered := _order(blocks)
	if ordered == blocks:
		return null
	return _compose(class_scope, blocks, ordered, _new_draft(class_scope, lines, body_first, body_last), body_last, false)


static func format(class_scope: GDSExSymbolIndex.GDSExClassScope, statements: Array[GDSExSourceScanner.GDSExStatement], lines: PackedStringArray, indent_unit: String) -> GDSExLayout:
	var blocks := _build_blocks(class_scope, false)
	if blocks.is_empty():
		return null
	var scope_first := class_scope.start_line
	var scope_last := _last_line_with_comments(class_scope, lines)
	for index in blocks.size():
		blocks[index].original_index = index
	_attach_comments(blocks, lines, scope_first, scope_last)
	if _has_header(class_scope):
		_split_gap(_new_block(class_scope.header_end_line, class_scope.header_end_line, 0), blocks[0], lines)
	var draft := _new_draft(class_scope, lines, scope_first, scope_last)
	draft.rewrites = _code_rewrites(class_scope, statements, lines, _own_line_ranges(class_scope, scope_first, scope_last), indent_unit)
	return _compose(class_scope, blocks, blocks, draft, scope_last, true)


static func _new_draft(class_scope: GDSExSymbolIndex.GDSExClassScope, lines: PackedStringArray, first_line: int, last_line: int) -> GDSExDraft:
	var draft := GDSExDraft.new(lines, first_line, last_line)
	if class_scope.parent != null:
		draft.blank_line = class_scope.body_indent_text
	return draft


static func _code_rewrites(class_scope: GDSExSymbolIndex.GDSExClassScope, statements: Array[GDSExSourceScanner.GDSExStatement], lines: PackedStringArray, line_ranges: Array[Vector2i], indent_unit: String) -> Dictionary[int, PackedStringArray]:
	var tidied_lines := GDSExTokenSpacing.tidy(_own_statements(class_scope, statements), lines, line_ranges)
	var tidied_statements := statements if tidied_lines == lines else GDSExSourceScanner.new().scan(tidied_lines)
	var rewrites := GDSExBracketLayout.new(tidied_lines, indent_unit).rewrite(_member_statements(class_scope, tidied_statements))
	for line_range in line_ranges:
		for line in range(line_range.x, line_range.y + 1):
			if tidied_lines[line] != lines[line] and not rewrites.has(line):
				rewrites[line] = PackedStringArray([tidied_lines[line]])
	return rewrites


static func _own_line_ranges(class_scope: GDSExSymbolIndex.GDSExClassScope, first_line: int, last_line: int) -> Array[Vector2i]:
	var ranges: Array[Vector2i] = []
	var range_start := first_line
	for member in class_scope.members:
		if member.kind == GDSExSymbolIndex.GDSExClassMember.GDSExKind.CLASS:
			ranges.append(Vector2i(range_start, member.start_line))
			range_start = member.end_line + 1
	ranges.append(Vector2i(range_start, last_line))
	return ranges


static func _own_statements(class_scope: GDSExSymbolIndex.GDSExClassScope, statements: Array[GDSExSourceScanner.GDSExStatement]) -> Array[GDSExSourceScanner.GDSExStatement]:
	var own: Array[GDSExSourceScanner.GDSExStatement] = []
	for statement in _scope_statements(class_scope, statements, true):
		if _is_class_header(class_scope, statement):
			own.append(statement)
		else:
			_collect_statements(statement, own)
	return own


static func _member_statements(class_scope: GDSExSymbolIndex.GDSExClassScope, statements: Array[GDSExSourceScanner.GDSExStatement]) -> Array[GDSExSourceScanner.GDSExStatement]:
	var member_statements: Array[GDSExSourceScanner.GDSExStatement] = []
	for statement in _scope_statements(class_scope, statements, false):
		if not _is_class_header(class_scope, statement) and not _has_abandoned_statements(statement):
			member_statements.append(statement)
	return member_statements


static func _has_abandoned_statements(statement: GDSExSourceScanner.GDSExStatement) -> bool:
	if statement.is_abandoned:
		return true
	for block in statement.blocks:
		for inner in block.statements:
			if _has_abandoned_statements(inner):
				return true
	return false


static func _scope_statements(class_scope: GDSExSymbolIndex.GDSExClassScope, statements: Array[GDSExSourceScanner.GDSExStatement], includes_header: bool) -> Array[GDSExSourceScanner.GDSExStatement]:
	if class_scope.parent == null:
		return statements
	var scope_statements: Array[GDSExSourceScanner.GDSExStatement] = []
	var class_statement := GDSExSourceScanner.find_statement_at(statements, class_scope.start_line)
	if class_statement == null:
		return scope_statements
	if includes_header:
		scope_statements.append(class_statement)
	for block in class_statement.blocks:
		scope_statements.append_array(block.statements)
	return scope_statements


static func _is_class_header(class_scope: GDSExSymbolIndex.GDSExClassScope, statement: GDSExSourceScanner.GDSExStatement) -> bool:
	if class_scope.parent != null and statement.first_line == class_scope.start_line:
		return true
	for member in class_scope.members:
		if member.kind == GDSExSymbolIndex.GDSExClassMember.GDSExKind.CLASS and member.start_line == statement.first_line:
			return true
	return false


static func _collect_statements(statement: GDSExSourceScanner.GDSExStatement, collected: Array[GDSExSourceScanner.GDSExStatement]) -> void:
	if statement == null:
		return
	collected.append(statement)
	for block in statement.blocks:
		for inner in block.statements:
			_collect_statements(inner, collected)


static func _last_line_with_comments(class_scope: GDSExSymbolIndex.GDSExClassScope, lines: PackedStringArray) -> int:
	var last_line := mini(class_scope.end_line, lines.size() - 1)
	if class_scope.parent == null:
		return last_line
	var body_indent := class_scope.body_indent_text.length()
	for line in range(last_line + 1, lines.size()):
		if lines[line].is_empty():
			continue
		if _indent_width(lines[line]) < body_indent or not (_is_blank(lines[line]) or _is_comment(lines[line])):
			break
		last_line = line
	return last_line


static func _build_blocks(class_scope: GDSExSymbolIndex.GDSExClassScope, merges_export_groups: bool) -> Array[GDSExBlock]:
	var blocks: Array[GDSExBlock] = []
	var group: GDSExBlock = null
	var tentative: Array[GDSExBlock] = []
	var annotations: Array[GDSExSymbolIndex.GDSExClassMember] = []
	for member in class_scope.members:
		if member.kind == GDSExSymbolIndex.GDSExClassMember.GDSExKind.ANNOTATION:
			var continues_group := member.name == SUBGROUP_ANNOTATION and group != null
			if GROUP_STARTERS.has(member.name) or (member.name == SUBGROUP_ANNOTATION and group == null):
				blocks.append_array(tentative)
				tentative.clear()
				var group_header := _new_block(member.start_line, member.end_line, GDSExMemberCategories.index_of(GDSExMemberCategories.EXPORTS))
				blocks.append(group_header)
				group = group_header if merges_export_groups else null
				continue
			if not continues_group:
				annotations.append(member)
				continue
		var block := _member_block(member, annotations, class_scope, blocks)
		annotations.clear()
		if group == null:
			blocks.append(block)
			continue
		tentative.append(block)
		if block.category == group.category and member.kind != GDSExSymbolIndex.GDSExClassMember.GDSExKind.ANNOTATION:
			for inner in tentative:
				_absorb(group, inner)
			tentative.clear()
	blocks.append_array(tentative)
	for annotation in annotations:
		blocks.append(_new_block(annotation.start_line, annotation.end_line, _last_category(blocks)))
	return blocks


static func _member_block(member: GDSExSymbolIndex.GDSExClassMember, annotations: Array[GDSExSymbolIndex.GDSExClassMember], class_scope: GDSExSymbolIndex.GDSExClassScope, previous_blocks: Array[GDSExBlock]) -> GDSExBlock:
	var modifiers := member.modifiers
	for annotation in annotations:
		modifiers += annotation.name + " "
	var first_line := member.start_line if annotations.is_empty() else annotations[0].start_line
	var category_name := GDSExMemberCategories.of_member(member, modifiers, class_scope)
	var category := _last_category(previous_blocks) if category_name.is_empty() else GDSExMemberCategories.index_of(category_name)
	var block := _new_block(first_line, member.end_line, category)
	block.is_tall = member.kind == GDSExSymbolIndex.GDSExClassMember.GDSExKind.FUNCTION or member.kind == GDSExSymbolIndex.GDSExClassMember.GDSExKind.CLASS
	if member.kind == GDSExSymbolIndex.GDSExClassMember.GDSExKind.VARIABLE:
		block.provided[member.name] = _phase(modifiers)
	return block


static func _new_block(first_line: int, last_line: int, category: int) -> GDSExBlock:
	var block := GDSExBlock.new()
	block.first_line = first_line
	block.last_line = last_line
	block.member_first_line = first_line
	block.member_last_line = last_line
	block.category = category
	return block


static func _absorb(block: GDSExBlock, inner: GDSExBlock) -> void:
	block.first_line = mini(block.first_line, inner.first_line)
	block.last_line = maxi(block.last_line, inner.last_line)
	block.member_first_line = block.first_line
	block.member_last_line = block.last_line
	block.is_tall = block.is_tall or inner.is_tall
	block.provided.merge(inner.provided)


static func _last_category(blocks: Array[GDSExBlock]) -> int:
	return 0 if blocks.is_empty() else blocks[blocks.size() - 1].category


static func _phase(modifiers: String) -> GDSExPhase:
	if GDSExMemberCategories.is_static(modifiers):
		return GDSExPhase.STATIC
	return GDSExPhase.READY if modifiers.contains(GDSExMemberCategories.ONREADY_ANNOTATION) else GDSExPhase.REGULAR


static func _merge_regions(blocks: Array[GDSExBlock], lines: PackedStringArray, body_first: int, body_last: int) -> Array[GDSExBlock]:
	var open_lines: Array[int] = []
	var regions: Array[Vector2i] = []
	var block_index := 0
	for line in range(body_first, body_last + 1):
		while block_index < blocks.size() and blocks[block_index].last_line < line:
			block_index += 1
		if block_index < blocks.size() and line >= blocks[block_index].first_line:
			continue
		var text := lines[line].strip_edges()
		if text.begins_with(REGION_START):
			open_lines.append(line)
		elif text.begins_with(REGION_END) and not open_lines.is_empty():
			var start: int = open_lines.pop_back()
			if open_lines.is_empty():
				regions.append(Vector2i(start, line))
	if regions.is_empty():
		return blocks

	var merged: Array[GDSExBlock] = []
	var region_index := 0
	var region_block: GDSExBlock = null
	for block in blocks:
		while region_index < regions.size() and regions[region_index].y < block.first_line:
			region_index += 1
			region_block = null
		if region_index >= regions.size() or block.first_line < regions[region_index].x:
			merged.append(block)
			continue
		if region_block == null:
			region_block = _new_block(regions[region_index].x, regions[region_index].y, block.category)
			merged.append(region_block)
		region_block.is_tall = region_block.is_tall or block.is_tall
		region_block.provided.merge(block.provided)
	return merged


static func _attach_comments(blocks: Array[GDSExBlock], lines: PackedStringArray, body_first: int, body_last: int) -> void:
	for index in blocks.size():
		var limit_line := blocks[index + 1].first_line - 1 if index + 1 < blocks.size() else body_last
		_absorb_comments_inside_member(blocks[index], lines, limit_line)
	var first_block := blocks[0]
	while first_block.first_line > body_first and _is_comment(lines[first_block.first_line - 1]):
		first_block.first_line -= 1
	var last_block := blocks[blocks.size() - 1]
	while last_block.last_line < body_last and _is_comment(lines[last_block.last_line + 1]):
		last_block.last_line += 1
	for index in range(1, blocks.size()):
		_split_gap(blocks[index - 1], blocks[index], lines)


static func _absorb_comments_inside_member(block: GDSExBlock, lines: PackedStringArray, limit_line: int) -> void:
	var member_indent := _indent_width(lines[block.member_first_line])
	for line in range(block.last_line + 1, limit_line + 1):
		if _is_blank(lines[line]):
			continue
		if not _is_comment(lines[line]) or _indent_width(lines[line]) <= member_indent:
			return
		block.last_line = line
		block.member_last_line = line


static func _split_gap(above: GDSExBlock, below: GDSExBlock, lines: PackedStringArray) -> void:
	var gap_end := below.first_line - 1
	var cursor := above.last_line + 1
	while cursor <= gap_end:
		var run_start := cursor
		while run_start <= gap_end and not _is_comment(lines[run_start]):
			run_start += 1
		if run_start > gap_end:
			return
		var run_end := run_start
		while run_end < gap_end and _is_comment(lines[run_end + 1]) and not _starts_with(lines[run_end], REGION_END) and not _starts_with(lines[run_end + 1], REGION_START):
			run_end += 1
		var blank_before := run_start - cursor
		var blank_after := 0
		while run_end + 1 + blank_after <= gap_end and not _is_comment(lines[run_end + 1 + blank_after]):
			blank_after += 1
		if _belongs_to_member_below(lines[run_start], lines[run_end], blank_before, blank_after):
			below.first_line = run_start
			return
		above.last_line = run_end
		cursor = run_end + 1


static func _belongs_to_member_below(first_comment: String, last_comment: String, blank_before: int, blank_after: int) -> bool:
	if _starts_with(first_comment, REGION_START):
		return true
	if _starts_with(last_comment, REGION_END):
		return false
	return blank_before >= blank_after


static func _is_comment(line: String) -> bool:
	return _starts_with(line, COMMENT_START)


static func _starts_with(line: String, prefix: String) -> bool:
	return line.strip_edges().begins_with(prefix)


static func _is_blank(line: String) -> bool:
	return line.strip_edges().is_empty()


static func _indent_width(line: String) -> int:
	return line.length() - line.lstrip(INDENT_CHARACTERS).length()


static func _find_dependencies(blocks: Array[GDSExBlock], class_scope: GDSExSymbolIndex.GDSExClassScope) -> void:
	var phases: Dictionary[String, GDSExPhase] = {}
	for block in blocks:
		phases.merge(block.provided)
	for block in blocks:
		for variable_name: String in block.provided:
			var symbol: GDSExSymbolIndex.GDSExVariableSymbol = class_scope.vars.get(variable_name)
			if symbol == null:
				continue
			for occurrence in _identifier_pattern.search_all(symbol.value_code):
				var identifier := occurrence.get_string()
				if phases.get(identifier, -1) == block.provided[variable_name] and not block.provided.has(identifier) and not block.required.has(identifier):
					block.required.append(identifier)


static func _order(blocks: Array[GDSExBlock]) -> Array[GDSExBlock]:
	var remaining: Array[GDSExBlock] = blocks.duplicate()
	remaining.sort_custom(func(first: GDSExBlock, second: GDSExBlock) -> bool:
		return first.category < second.category or (first.category == second.category and first.original_index < second.original_index))
	var ordered: Array[GDSExBlock] = []
	var declared: Dictionary[String, bool] = {}
	while not remaining.is_empty():
		var picked := 0
		for index in remaining.size():
			if _is_ready(remaining[index], declared):
				picked = index
				break
		var block := remaining[picked]
		remaining.remove_at(picked)
		ordered.append(block)
		for variable_name: String in block.provided:
			declared[variable_name] = true
	return ordered


static func _is_ready(block: GDSExBlock, declared: Dictionary[String, bool]) -> bool:
	for required_name in block.required:
		if not declared.has(required_name):
			return false
	return true


static func _compose(class_scope: GDSExSymbolIndex.GDSExClassScope, blocks: Array[GDSExBlock], ordered: Array[GDSExBlock], draft: GDSExDraft, body_last: int, applies_format: bool) -> GDSExLayout:
	var lines := draft.source
	var first_block := blocks[0]
	var last_block := blocks[blocks.size() - 1]
	var head_first := draft.first_line
	var tail_last := body_last
	if applies_format:
		if class_scope.parent != null:
			draft.copy_lines(head_first, head_first)
			head_first += 1
			while tail_last > last_block.last_line and _is_blank(lines[tail_last]):
				tail_last -= 1
		while head_first < first_block.first_line and _is_blank(lines[head_first]):
			head_first += 1
	var leading_blank := 0
	while first_block.first_line - 1 - leading_blank >= head_first and _is_blank(lines[first_block.first_line - 1 - leading_blank]):
		leading_blank += 1
	var head_last := first_block.first_line - 1 - leading_blank
	var header_last := class_scope.header_end_line if applies_format and _has_header(class_scope) else head_last
	_copy_outside_members(draft, head_first, header_last, applies_format)
	draft.copy_limiting_blank_lines(header_last + 1, head_last, 0)
	var is_at_top := not _has_header(class_scope) and (applies_format or draft.lines.is_empty())

	for index in ordered.size():
		var block := ordered[index]
		var previous: GDSExBlock = ordered[index - 1] if index > 0 else null
		var is_in_place := block == first_block if previous == null else block.original_index == previous.original_index + 1
		var existing := 0
		if is_in_place:
			existing = leading_blank if previous == null else block.first_line - previous.last_line - 1
		var gap := existing
		if applies_format or not is_in_place:
			gap = _leading_gap(block, existing, is_at_top) if previous == null else _standard_gap(previous, block, existing)
		draft.add_blank_lines(gap, block.first_line - existing, existing)
		draft.copy_block(block, applies_format)

	_copy_outside_members(draft, last_block.last_line + 1, tail_last, applies_format)
	return _trimmed_layout(draft, body_last)


static func _copy_outside_members(draft: GDSExDraft, from: int, to: int, applies_format: bool) -> void:
	if applies_format:
		draft.copy_limiting_blank_lines(from, to, GDSExPluginProjectSettings.max_blank_lines_outside_members())
	else:
		draft.copy_lines(from, to)


static func _has_header(class_scope: GDSExSymbolIndex.GDSExClassScope) -> bool:
	return class_scope.header_end_line >= class_scope.body_start_line


static func _leading_gap(block: GDSExBlock, existing: int, is_at_top: bool) -> int:
	if is_at_top:
		return mini(existing, GDSExPluginProjectSettings.max_blank_lines_outside_members())
	return GDSExPluginProjectSettings.blank_lines_around_functions_and_classes() if block.is_tall else GDSExPluginProjectSettings.blank_lines_between_member_categories()


static func _standard_gap(previous: GDSExBlock, block: GDSExBlock, existing: int) -> int:
	if previous.is_tall or block.is_tall:
		return GDSExPluginProjectSettings.blank_lines_around_functions_and_classes()
	if previous.category != block.category:
		return GDSExPluginProjectSettings.blank_lines_between_member_categories()
	return mini(existing, GDSExPluginProjectSettings.max_blank_lines_inside_member_category())


static func _trimmed_layout(draft: GDSExDraft, last_line: int) -> GDSExLayout:
	var old_count := last_line - draft.first_line + 1
	var new_count := draft.lines.size()
	var prefix := 0
	while prefix < old_count and prefix < new_count and draft.source[draft.first_line + prefix] == draft.lines[prefix]:
		prefix += 1
	if prefix == old_count and prefix == new_count:
		return null
	var suffix := 0
	while suffix < old_count - prefix and suffix < new_count - prefix and draft.source[last_line - suffix] == draft.lines[new_count - 1 - suffix]:
		suffix += 1
	var layout := GDSExLayout.new()
	layout.first_line = draft.first_line + prefix
	layout.last_line = last_line - suffix
	layout.lines = draft.lines.slice(prefix, new_count - suffix)
	layout.line_map = draft.line_map.slice(prefix, old_count - suffix)
	return layout
