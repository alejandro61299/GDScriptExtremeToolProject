@tool
extends RefCounted

const GDSExEditPlan = preload("res://addons/gdscript_extreme_tool/editing/edit_plan.gd")

const REMOVED: int = -1


static func between(old_lines: PackedStringArray, new_lines: PackedStringArray, plan: GDSExEditPlan = null) -> PackedInt32Array:
	if plan != null and plan.line_replacement != null and plan.insertions.is_empty() and plan.replacements.is_empty():
		return _from_line_replacement(old_lines.size(), plan.line_replacement)
	var map := PackedInt32Array()
	map.resize(old_lines.size())
	map.fill(REMOVED)
	_match(old_lines, new_lines, 0, old_lines.size(), 0, new_lines.size(), map)
	return map


static func compose(first: PackedInt32Array, second: PackedInt32Array) -> PackedInt32Array:
	var composed := PackedInt32Array()
	composed.resize(first.size())
	for line in first.size():
		var middle := first[line]
		composed[line] = REMOVED if middle == REMOVED or middle >= second.size() else second[middle]
	return composed


static func identity(line_count: int) -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(line_count)
	for line in line_count:
		map[line] = line
	return map


static func count_removed(map: PackedInt32Array) -> int:
	return map.count(REMOVED)


static func _from_line_replacement(old_count: int, replacement: GDSExEditPlan.GDSExLineReplacement) -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(old_count)
	var shift := replacement.lines.size() - (replacement.last_line - replacement.first_line + 1)
	for line in old_count:
		if line < replacement.first_line:
			map[line] = line
		elif line > replacement.last_line:
			map[line] = line + shift
		else:
			map[line] = replacement.line_map[line - replacement.first_line]
	return map


static func _match(old_lines: PackedStringArray, new_lines: PackedStringArray, old_from: int, old_to: int, new_from: int, new_to: int, map: PackedInt32Array) -> void:
	while old_from < old_to and new_from < new_to and old_lines[old_from] == new_lines[new_from]:
		map[old_from] = new_from
		old_from += 1
		new_from += 1
	while old_from < old_to and new_from < new_to and old_lines[old_to - 1] == new_lines[new_to - 1]:
		map[old_to - 1] = new_to - 1
		old_to -= 1
		new_to -= 1
	if old_from == old_to or new_from == new_to:
		return
	var anchors := _unique_anchors(old_lines, new_lines, old_from, old_to, new_from, new_to)
	if anchors.is_empty():
		if old_to - old_from == new_to - new_from:
			for offset in old_to - old_from:
				map[old_from + offset] = new_from + offset
		return
	var previous_old := old_from
	var previous_new := new_from
	for anchor in anchors:
		_match(old_lines, new_lines, previous_old, anchor.x, previous_new, anchor.y, map)
		map[anchor.x] = anchor.y
		previous_old = anchor.x + 1
		previous_new = anchor.y + 1
	_match(old_lines, new_lines, previous_old, old_to, previous_new, new_to, map)


static func _unique_anchors(old_lines: PackedStringArray, new_lines: PackedStringArray, old_from: int, old_to: int, new_from: int, new_to: int) -> Array[Vector2i]:
	var old_positions := _unique_positions(old_lines, old_from, old_to)
	var new_positions := _unique_positions(new_lines, new_from, new_to)
	var pairs: Array[Vector2i] = []
	for line in range(old_from, old_to):
		var text := old_lines[line]
		if old_positions.has(text) and new_positions.has(text):
			pairs.append(Vector2i(line, new_positions[text]))
	return _longest_increasing(pairs)


static func _unique_positions(lines: PackedStringArray, from: int, to: int) -> Dictionary[String, int]:
	var positions: Dictionary[String, int] = {}
	var repeated: Dictionary[String, bool] = {}
	for line in range(from, to):
		var text := lines[line]
		if repeated.has(text):
			continue
		if positions.has(text):
			positions.erase(text)
			repeated[text] = true
			continue
		positions[text] = line
	return positions


static func _longest_increasing(pairs: Array[Vector2i]) -> Array[Vector2i]:
	var tails := PackedInt32Array()
	var previous := PackedInt32Array()
	previous.resize(pairs.size())
	for index in pairs.size():
		var low := 0
		var high := tails.size()
		while low < high:
			var middle := (low + high) / 2
			if pairs[tails[middle]].y < pairs[index].y:
				low = middle + 1
			else:
				high = middle
		previous[index] = tails[low - 1] if low > 0 else -1
		if low == tails.size():
			tails.append(index)
		else:
			tails[low] = index
	var result: Array[Vector2i] = []
	var current := tails[tails.size() - 1] if not tails.is_empty() else -1
	while current != -1:
		result.push_front(pairs[current])
		current = previous[current]
	return result
