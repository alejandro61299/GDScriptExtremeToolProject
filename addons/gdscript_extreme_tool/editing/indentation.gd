@tool
extends RefCounted

const TAB: String = "\t"


static func editor_unit(editor: CodeEdit) -> String:
	if editor.is_indent_using_spaces():
		return " ".repeat(editor.get_indent_size())
	return TAB


static func detect_unit(lines: PackedStringArray, fallback: String) -> String:
	var shortest := ""
	for line in lines:
		var leading := leading_whitespace(line)
		if leading.is_empty() or leading.length() == line.length():
			continue
		if leading.begins_with(TAB):
			return TAB
		if shortest.is_empty() or leading.length() < shortest.length():
			shortest = leading
	return fallback if shortest.is_empty() else shortest


static func leading_whitespace(line: String) -> String:
	return line.substr(0, line.length() - line.strip_edges(true, false).length())
