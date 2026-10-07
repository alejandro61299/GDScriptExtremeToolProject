@tool
extends RefCounted

const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")
const GDSExLanguage = preload("res://addons/gdscript_extreme_tool/analysis/language.gd")

const ARRAY_OPENING: String = "["
const DICTIONARY_OPENING: String = "{"
const ELEMENT_SEPARATOR: String = ","
const KEY_SEPARATOR: String = ":"
const ASSIGNMENT: String = "="
const OPERATOR_CHARACTERS: String = "=!<>:"
const SUBSCRIPTABLE_ENDINGS: String = ")]}\"'"
const BLANK_CHARACTERS: String = " \t"
const NO_GROUP: int = -1

enum GDSExRole { NONE, ELEMENT_SEPARATOR, KEY_SEPARATOR }


class GDSExGroup:
	var open_offset: int = 0
	var close_offset: int = 0
	var is_collection: bool = false
	var separator_offsets: PackedInt32Array = []
	var key_count: int = 0
	var spaced_key_count: int = 0

	func spaces_keys() -> bool:
		return spaced_key_count * 2 > key_count


class GDSExGroups:
	var groups: Array[GDSExGroup] = []
	var owners: PackedInt32Array = []
	var roles: PackedByteArray = []

	func group_at(offset: int) -> GDSExGroup:
		if offset < 0 or offset >= owners.size() or owners[offset] == NO_GROUP:
			return null
		return groups[owners[offset]]

	func role_at(offset: int) -> GDSExRole:
		if offset < 0 or offset >= roles.size():
			return GDSExRole.NONE
		return roles[offset] as GDSExRole

	func opens_collection(offset: int) -> bool:
		var group := group_at(offset + 1)
		return group != null and group.is_collection and group.open_offset == offset

	func closes_collection(offset: int) -> bool:
		var group := group_at(offset)
		return group != null and group.is_collection and group.close_offset == offset


static func has_collection_brackets(code: String) -> bool:
	return code.contains(ARRAY_OPENING) or code.contains(DICTIONARY_OPENING)


static func find(code: String) -> GDSExGroups:
	var found := GDSExGroups.new()
	found.owners.resize(code.length())
	found.roles.resize(code.length())
	var open_indices: PackedInt32Array = []
	var keyed_elements: Array[bool] = []
	for offset in code.length():
		var character := code[offset]
		var current := NO_GROUP if open_indices.is_empty() else open_indices[open_indices.size() - 1]
		found.owners[offset] = current
		if GDSExSourceScanner.OPENING_BRACKETS.contains(character):
			var group := GDSExGroup.new()
			group.open_offset = offset
			group.is_collection = _is_collection_literal(code, offset)
			open_indices.append(found.groups.size())
			keyed_elements.append(false)
			found.groups.append(group)
		elif GDSExSourceScanner.CLOSING_BRACKETS.contains(character):
			if current == NO_GROUP or not _is_pair(code[found.groups[current].open_offset], character):
				return GDSExGroups.new()
			found.groups[current].close_offset = offset
			open_indices.remove_at(open_indices.size() - 1)
			keyed_elements.remove_at(keyed_elements.size() - 1)
		elif current != NO_GROUP and found.groups[current].is_collection:
			var group := found.groups[current]
			var element := keyed_elements.size() - 1
			if character == ELEMENT_SEPARATOR:
				group.separator_offsets.append(offset)
				found.roles[offset] = GDSExRole.ELEMENT_SEPARATOR
				keyed_elements[element] = false
			elif (character == KEY_SEPARATOR or character == ASSIGNMENT) and not keyed_elements[element] and code[group.open_offset] == DICTIONARY_OPENING:
				keyed_elements[element] = _read_key_separator(code, offset, group, found)
	return found if open_indices.is_empty() else GDSExGroups.new()


static func _is_pair(opening: String, closing: String) -> bool:
	return GDSExSourceScanner.OPENING_BRACKETS.find(opening) == GDSExSourceScanner.CLOSING_BRACKETS.find(closing)


static func _read_key_separator(code: String, offset: int, group: GDSExGroup, found: GDSExGroups) -> bool:
	var character := code[offset]
	var is_followed_by_assignment := offset + 1 < code.length() and code[offset + 1] == ASSIGNMENT
	if character == ASSIGNMENT:
		return not is_followed_by_assignment and not OPERATOR_CHARACTERS.contains(code[offset - 1])
	if not is_followed_by_assignment:
		found.roles[offset] = GDSExRole.KEY_SEPARATOR
		group.key_count += 1
		if BLANK_CHARACTERS.contains(code[offset - 1]):
			group.spaced_key_count += 1
	return true


static func _is_collection_literal(code: String, open_offset: int) -> bool:
	if code[open_offset] == DICTIONARY_OPENING:
		return true
	if code[open_offset] != ARRAY_OPENING:
		return false
	var index := open_offset - 1
	while index >= 0 and BLANK_CHARACTERS.contains(code[index]):
		index -= 1
	if index < 0:
		return true
	if SUBSCRIPTABLE_ENDINGS.contains(code[index]):
		return false
	if not GDSExSourceScanner.is_identifier_character(code[index]):
		return true
	var word_end := index + 1
	while index >= 0 and GDSExSourceScanner.is_identifier_character(code[index]):
		index -= 1
	return GDSExLanguage.NON_CALL_KEYWORDS.has(code.substr(index + 1, word_end - index - 1))
