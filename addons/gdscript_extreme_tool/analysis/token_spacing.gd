@tool
extends RefCounted

const GDSExSourceScanner = preload("res://addons/gdscript_extreme_tool/analysis/source_scanner.gd")

const BLANK_CHARACTERS: String = " \t"
const SEPARATOR: String = " "


static func tidy(statements: Array[GDSExSourceScanner.GDSExStatement], lines: PackedStringArray, line_ranges: Array[Vector2i]) -> PackedStringArray:
	var runs: Dictionary[int, Array] = {}
	var code_ends: Dictionary[int, int] = {}
	for statement in statements:
		for piece in statement.pieces:
			_find_untidy_runs(statement.code.substr(piece.offset, piece.length), piece, lines, runs)
			code_ends[piece.line] = maxi(code_ends.get(piece.line, 0), piece.column + piece.length)
	var tidied := lines.duplicate()
	for line: int in runs:
		var line_runs: Array = runs[line]
		line_runs.sort_custom(func(first: Vector2i, second: Vector2i) -> bool: return first.x > second.x)
		for run: Vector2i in line_runs:
			tidied[line] = tidied[line].substr(0, run.x) + SEPARATOR + tidied[line].substr(run.x + run.y)
	for line_range in line_ranges:
		for line in range(line_range.x, line_range.y + 1):
			if code_ends.get(line, 0) < lines[line].length() and not lines[line].strip_edges().is_empty():
				tidied[line] = tidied[line].rstrip(BLANK_CHARACTERS)
	return tidied


static func _find_untidy_runs(code: String, piece: GDSExSourceScanner.GDSExPiece, lines: PackedStringArray, runs: Dictionary[int, Array]) -> void:
	var index := 0
	while index < code.length():
		if not BLANK_CHARACTERS.contains(code[index]):
			index += 1
			continue
		var run_start := index
		while index < code.length() and BLANK_CHARACTERS.contains(code[index]):
			index += 1
		var run := Vector2i(piece.column + run_start, index - run_start)
		var is_untidy := run.y > 1 or code[run_start] != SEPARATOR
		if is_untidy and lines[piece.line].substr(run.x, run.y).strip_edges().is_empty():
			if not runs.has(piece.line):
				runs[piece.line] = []
			runs[piece.line].append(run)
