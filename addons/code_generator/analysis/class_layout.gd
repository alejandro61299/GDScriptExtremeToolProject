@tool
extends RefCounted

const SymbolIndex = preload("res://addons/code_generator/analysis/symbol_index.gd")
const TypeResolver = preload("res://addons/code_generator/analysis/type_resolver.gd")
const Settings = preload("res://addons/code_generator/code_generator_settings.gd")

const COMMENT_START: String = "#"
const REGION_START: String = "#region"
const REGION_END: String = "#endregion"
const EXPORT_ANNOTATION: String = "@export"
const ONREADY_ANNOTATION: String = "@onready"
const SUBGROUP_ANNOTATION: String = "@export_subgroup"
const GROUP_STARTERS: Array[String] = ["@export_category", "@export_group"]
const PRIVATE_PREFIX: String = "_"
const INIT_METHOD: String = "_init"
const EXPORTS_CATEGORY: String = "exports"
const INDENT_CHARACTERS: String = " \t"

enum Phase { STATIC, REGULAR, READY }

static var _static_pattern := RegEx.create_from_string("\\bstatic\\b")
static var _identifier_pattern := RegEx.create_from_string("(?<![\\w.])[A-Za-z_]\\w*")


class Block:
	var first_line: int = 0
	var last_line: int = 0
	var member_first_line: int = 0
	var member_last_line: int = 0
	var category: int = 0
	var is_tall: bool = false
	var original_index: int = 0
	var provided: Dictionary[String, Phase] = {}
	var required: PackedStringArray = []


class Layout:
	var first_line: int = 0
	var last_line: int = 0
	var lines: PackedStringArray = []
	var line_map: PackedInt32Array = []


class Draft:
	var source: PackedStringArray = []
	var first_line: int = 0
	var lines: PackedStringArray = []
	var line_map: PackedInt32Array = []


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
				_copy_line(line, "")


	func copy_block(block: Block, glues_comments: bool) -> void:
		for line in range(block.first_line, block.last_line + 1):
			var is_inside_member := line >= block.member_first_line and line <= block.member_last_line
			if is_inside_member or not glues_comments or not _is_blank_line(line):
				_copy_line(line, source[line])


	func add_blank_lines(count: int, replaced_first_line: int, replaced_count: int) -> void:
		for offset in mini(replaced_count, count):
			line_map[replaced_first_line + offset - first_line] = first_line + lines.size() + offset
		for blank in count:
			lines.append("")


	func _copy_line(line: int, text: String) -> void:
		line_map[line - first_line] = first_line + lines.size()
		lines.append(text)


	func _is_blank_line(line: int) -> bool:
		return source[line].strip_edges().is_empty()


static func reorder(class_scope: SymbolIndex.ClassScope, lines: PackedStringArray) -> Layout:
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
	return _compose(class_scope, blocks, ordered, lines, body_first, body_last, false)


static func format(class_scope: SymbolIndex.ClassScope, lines: PackedStringArray) -> Layout:
	var blocks := _build_blocks(class_scope, false)
	if blocks.is_empty():
		return null
	var scope_first := class_scope.body_start_line
	var scope_last := _last_line_with_comments(class_scope, lines)
	for index in blocks.size():
		blocks[index].original_index = index
	_attach_comments(blocks, lines, scope_first, scope_last)
	if _has_header(class_scope):
		_split_gap(_new_block(class_scope.header_end_line, class_scope.header_end_line, 0), blocks[0], lines)
	return _compose(class_scope, blocks, blocks, lines, scope_first, scope_last, true)


static func _last_line_with_comments(class_scope: SymbolIndex.ClassScope, lines: PackedStringArray) -> int:
	var last_line := mini(class_scope.end_line, lines.size() - 1)
	if class_scope.parent == null:
		return last_line
	var body_indent := class_scope.body_indent_text.length()
	for line in range(last_line + 1, lines.size()):
		if _is_blank(lines[line]):
			continue
		if not _is_comment(lines[line]) or _indent_width(lines[line]) < body_indent:
			break
		last_line = line
	return last_line


static func _build_blocks(class_scope: SymbolIndex.ClassScope, merges_export_groups: bool) -> Array[Block]:
	var blocks: Array[Block] = []
	var group: Block = null
	var tentative: Array[Block] = []
	var annotations: Array[SymbolIndex.ClassMember] = []
	for member in class_scope.members:
		if member.kind == SymbolIndex.ClassMember.Kind.ANNOTATION:
			var continues_group := member.name == SUBGROUP_ANNOTATION and group != null
			if GROUP_STARTERS.has(member.name) or (member.name == SUBGROUP_ANNOTATION and group == null):
				blocks.append_array(tentative)
				tentative.clear()
				var group_header := _new_block(member.start_line, member.end_line, _category_index(EXPORTS_CATEGORY))
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
		if block.category == group.category and member.kind != SymbolIndex.ClassMember.Kind.ANNOTATION:
			for inner in tentative:
				_absorb(group, inner)
			tentative.clear()
	blocks.append_array(tentative)
	for annotation in annotations:
		blocks.append(_new_block(annotation.start_line, annotation.end_line, _last_category(blocks)))
	return blocks


static func _member_block(member: SymbolIndex.ClassMember, annotations: Array[SymbolIndex.ClassMember], class_scope: SymbolIndex.ClassScope, previous_blocks: Array[Block]) -> Block:
	var modifiers := member.modifiers
	for annotation in annotations:
		modifiers += annotation.name + " "
	var first_line := member.start_line if annotations.is_empty() else annotations[0].start_line
	var category_name := _category_name(member, modifiers, class_scope)
	var category := _last_category(previous_blocks) if category_name.is_empty() else _category_index(category_name)
	var block := _new_block(first_line, member.end_line, category)
	block.is_tall = member.kind == SymbolIndex.ClassMember.Kind.METHOD or member.kind == SymbolIndex.ClassMember.Kind.CLASS
	if member.kind == SymbolIndex.ClassMember.Kind.VARIABLE:
		block.provided[member.name] = _phase(modifiers)
	return block


static func _new_block(first_line: int, last_line: int, category: int) -> Block:
	var block := Block.new()
	block.first_line = first_line
	block.last_line = last_line
	block.member_first_line = first_line
	block.member_last_line = last_line
	block.category = category
	return block


static func _absorb(block: Block, inner: Block) -> void:
	block.first_line = mini(block.first_line, inner.first_line)
	block.last_line = maxi(block.last_line, inner.last_line)
	block.member_first_line = block.first_line
	block.member_last_line = block.last_line
	block.is_tall = block.is_tall or inner.is_tall
	block.provided.merge(inner.provided)


static func _last_category(blocks: Array[Block]) -> int:
	return 0 if blocks.is_empty() else blocks[blocks.size() - 1].category


static func _category_index(category_name: String) -> int:
	var index := Settings.CLASS_MEMBER_ORDER.find(category_name)
	return Settings.CLASS_MEMBER_ORDER.size() if index == -1 else index


static func _category_name(member: SymbolIndex.ClassMember, modifiers: String, class_scope: SymbolIndex.ClassScope) -> String:
	var is_static := _static_pattern.search(modifiers) != null
	var is_private := member.name.begins_with(PRIVATE_PREFIX)
	match member.kind:
		SymbolIndex.ClassMember.Kind.SIGNAL:
			return "signals"
		SymbolIndex.ClassMember.Kind.CONSTANT:
			return "constants"
		SymbolIndex.ClassMember.Kind.ENUM:
			return "enums"
		SymbolIndex.ClassMember.Kind.CLASS:
			return "inner_classes"
		SymbolIndex.ClassMember.Kind.VARIABLE:
			if is_static:
				return "static_variables"
			if modifiers.contains(EXPORT_ANNOTATION):
				return EXPORTS_CATEGORY
			if modifiers.contains(ONREADY_ANNOTATION):
				return "onready_variables"
			return "private_variables" if is_private else "public_variables"
		SymbolIndex.ClassMember.Kind.METHOD:
			if is_static:
				return "static_private_methods" if is_private else "static_public_methods"
			if member.name == INIT_METHOD:
				return "init"
			if TypeResolver.is_engine_callback(class_scope, member.name):
				return "engine_methods"
			return "private_methods" if is_private else "public_methods"
	return ""


static func _phase(modifiers: String) -> Phase:
	if _static_pattern.search(modifiers) != null:
		return Phase.STATIC
	return Phase.READY if modifiers.contains(ONREADY_ANNOTATION) else Phase.REGULAR


static func _merge_regions(blocks: Array[Block], lines: PackedStringArray, body_first: int, body_last: int) -> Array[Block]:
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

	var merged: Array[Block] = []
	var region_index := 0
	var region_block: Block = null
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


static func _attach_comments(blocks: Array[Block], lines: PackedStringArray, body_first: int, body_last: int) -> void:
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


static func _absorb_comments_inside_member(block: Block, lines: PackedStringArray, limit_line: int) -> void:
	var member_indent := _indent_width(lines[block.member_first_line])
	for line in range(block.last_line + 1, limit_line + 1):
		if _is_blank(lines[line]):
			continue
		if not _is_comment(lines[line]) or _indent_width(lines[line]) <= member_indent:
			return
		block.last_line = line
		block.member_last_line = line


static func _split_gap(above: Block, below: Block, lines: PackedStringArray) -> void:
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


static func _find_dependencies(blocks: Array[Block], class_scope: SymbolIndex.ClassScope) -> void:
	var phases: Dictionary[String, Phase] = {}
	for block in blocks:
		phases.merge(block.provided)
	for block in blocks:
		for variable_name: String in block.provided:
			var symbol: SymbolIndex.VariableSymbol = class_scope.vars.get(variable_name)
			if symbol == null:
				continue
			for occurrence in _identifier_pattern.search_all(symbol.value_code):
				var identifier := occurrence.get_string()
				if phases.get(identifier, -1) == block.provided[variable_name] and not block.provided.has(identifier) and not block.required.has(identifier):
					block.required.append(identifier)


static func _order(blocks: Array[Block]) -> Array[Block]:
	var remaining: Array[Block] = blocks.duplicate()
	remaining.sort_custom(func(first: Block, second: Block) -> bool:
		return first.category < second.category or (first.category == second.category and first.original_index < second.original_index))
	var ordered: Array[Block] = []
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


static func _is_ready(block: Block, declared: Dictionary[String, bool]) -> bool:
	for required_name in block.required:
		if not declared.has(required_name):
			return false
	return true


static func _compose(class_scope: SymbolIndex.ClassScope, blocks: Array[Block], ordered: Array[Block], lines: PackedStringArray, body_first: int, body_last: int, applies_format: bool) -> Layout:
	var draft := Draft.new(lines, body_first, body_last)
	var first_block := blocks[0]
	var head_first := body_first
	if applies_format and class_scope.parent == null:
		while head_first < first_block.first_line and _is_blank(lines[head_first]):
			head_first += 1
	var leading_blank := 0
	while first_block.first_line - 1 - leading_blank >= head_first and _is_blank(lines[first_block.first_line - 1 - leading_blank]):
		leading_blank += 1
	_copy_outside_members(draft, head_first, first_block.first_line - 1 - leading_blank, applies_format)
	var is_at_top := not _has_header(class_scope) and (applies_format or draft.lines.is_empty())

	for index in ordered.size():
		var block := ordered[index]
		var previous: Block = ordered[index - 1] if index > 0 else null
		var is_in_place := block == first_block if previous == null else block.original_index == previous.original_index + 1
		var existing := 0
		if is_in_place:
			existing = leading_blank if previous == null else block.first_line - previous.last_line - 1
		var gap := existing
		if applies_format or not is_in_place:
			gap = _leading_gap(block, existing, is_at_top) if previous == null else _standard_gap(previous, block, existing)
		draft.add_blank_lines(gap, block.first_line - existing, existing)
		draft.copy_block(block, applies_format)

	_copy_outside_members(draft, blocks[blocks.size() - 1].last_line + 1, body_last, applies_format)
	return _trimmed_layout(draft, body_last)


static func _copy_outside_members(draft: Draft, from: int, to: int, applies_format: bool) -> void:
	if applies_format:
		draft.copy_limiting_blank_lines(from, to, Settings.MAX_BLANK_LINES_OUTSIDE_MEMBERS)
	else:
		draft.copy_lines(from, to)


static func _has_header(class_scope: SymbolIndex.ClassScope) -> bool:
	return class_scope.header_end_line >= class_scope.body_start_line


static func _leading_gap(block: Block, existing: int, is_at_top: bool) -> int:
	if is_at_top:
		return mini(existing, Settings.MAX_BLANK_LINES_OUTSIDE_MEMBERS)
	return Settings.BLANK_LINES_AROUND_METHODS_AND_CLASSES if block.is_tall else Settings.BLANK_LINES_BETWEEN_MEMBER_CATEGORIES


static func _standard_gap(previous: Block, block: Block, existing: int) -> int:
	if previous.is_tall or block.is_tall:
		return Settings.BLANK_LINES_AROUND_METHODS_AND_CLASSES
	if previous.category != block.category:
		return Settings.BLANK_LINES_BETWEEN_MEMBER_CATEGORIES
	return mini(existing, Settings.MAX_BLANK_LINES_INSIDE_MEMBER_CATEGORY)


static func _trimmed_layout(draft: Draft, last_line: int) -> Layout:
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
	var layout := Layout.new()
	layout.first_line = draft.first_line + prefix
	layout.last_line = last_line - suffix
	layout.lines = draft.lines.slice(prefix, new_count - suffix)
	layout.line_map = draft.line_map.slice(prefix, old_count - suffix)
	return layout
