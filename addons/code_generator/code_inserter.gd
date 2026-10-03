@tool
extends RefCounted

const SymbolApi = preload("res://addons/code_generator/symbol_index.gd")

## Inserts generated code text into the editor.
##
## Parameters:
## - text: The full string of code to insert.
## - target_class: The class scope (for determining position).
## - context_scope: The caller scope (for determining position).
## - select_start_idx: Start char index within 'text' to select. -1 to disable.
## - select_end_idx: End char index within 'text' to select. -1 to disable.
static func insert_stub(editor: CodeEdit, text: String, target_class: SymbolApi.ClassScope, context_scope: SymbolApi.ScopeInfo, select_start_idx: int = -1, select_end_idx: int = -1) -> void:
	if not editor or text.is_empty(): return
	
	# 1. Compute Anchor
	var insertion_info = _compute_insertion_position(target_class, context_scope)
	var anchor_line = insertion_info.line
	var is_header = insertion_info.is_header
	
	# 2. Determine Spacing
	# Policy: 1 blank line after header, 2 after methods
	var target_top = 1 if is_header else 2
	var target_bottom = 2
	
	# 3. Analyze Insertion Point
	var insert_at_idx = anchor_line + 1
	var line_count = editor.get_line_count()
	if insert_at_idx > line_count: insert_at_idx = line_count
	
	var existing_blanks_below = 0
	var scan_idx = insert_at_idx
	while scan_idx < line_count:
		if editor.get_line(scan_idx).strip_edges().is_empty():
			existing_blanks_below += 1
			scan_idx += 1
		else:
			break
			
	var needed_top = target_top
	var needed_bottom = 0
	if scan_idx < line_count:
		needed_bottom = max(0, target_bottom - existing_blanks_below)
	
	# 4. Perform Insertion
	editor.begin_complex_operation()
	
	var current_pos = insert_at_idx
	
	# Top Padding
	for i in range(needed_top):
		editor.insert_line_at(current_pos, "")
		current_pos += 1
		
	var start_content_line = current_pos
	
	# Content
	var lines = text.split("\n")
	for line in lines:
		editor.insert_line_at(current_pos, line)
		current_pos += 1
		
	# Bottom Padding
	for i in range(needed_bottom):
		editor.insert_line_at(current_pos, "")
		current_pos += 1
		
	editor.end_complex_operation()
	
	# 5. Handle Selection & Caret
	if select_start_idx != -1 and select_end_idx != -1:
		# Map text offsets to (Line, Col) relative to the inserted block
		var start_map = _map_offset_to_line_col(text, select_start_idx)
		var end_map = _map_offset_to_line_col(text, select_end_idx)
		
		var abs_start_line = start_content_line + start_map.x
		var abs_start_col = start_map.y
		
		var abs_end_line = start_content_line + end_map.x
		var abs_end_col = end_map.y
		
		editor.set_caret_line(abs_end_line)
		editor.set_caret_column(abs_end_col)
		editor.select(abs_start_line, abs_start_col, abs_end_line, abs_end_col)
		editor.center_viewport_to_caret()
		
	else:
		# Default: Place caret after the last visible character of the inserted block
		var last_rel_line = lines.size() - 1
		var last_line_text = lines[last_rel_line]
		var trimmed = last_line_text.strip_edges(false, true) # Strip right only
		
		var abs_line = start_content_line + last_rel_line
		var abs_col = trimmed.length()
		
		editor.set_caret_line(abs_line)
		editor.set_caret_column(abs_col)
		editor.deselect()
		editor.center_viewport_to_caret()

## Utility: Returns [start_index, end_index] of the visible content (trimmed) for a specific line index within the text.
## Useful for selecting the body of a generated function (e.g. line 1).
static func get_visible_range_of_line(text: String, line_index: int) -> Vector2i:
	var current_idx = 0
	var lines = text.split("\n")
	
	if line_index < 0 or line_index >= lines.size():
		return Vector2i(-1, -1)
		
	# Advance to target line
	for i in range(line_index):
		# Add length of line + 1 for newline char
		current_idx += lines[i].length() + 1
		
	var target_line = lines[line_index]
	var trimmed_left = target_line.strip_edges(true, false)
	var indent_size = target_line.length() - trimmed_left.length()
	
	var trimmed_full = target_line.strip_edges()
	var content_len = trimmed_full.length()
	
	if content_len == 0:
		# Empty line, just place cursor there
		return Vector2i(current_idx + indent_size, current_idx + indent_size)
		
	var start = current_idx + indent_size
	var end = start + content_len
	
	return Vector2i(start, end)

static func _map_offset_to_line_col(text: String, offset: int) -> Vector2i:
	# Returns Vector2i(line_index, col_index)
	var current_idx = 0
	var lines = text.split("\n")
	
	for i in range(lines.size()):
		var line_len = lines[i].length()
		# Check if offset is within this line (including the newline char at end)
		# Note: text.length() might imply the offset allows pointing slightly past end?
		if offset <= current_idx + line_len:
			return Vector2i(i, offset - current_idx)
		
		# Move past this line + newline
		current_idx += line_len + 1
		
	# Fallback (should not happen if offset is valid)
	return Vector2i(lines.size()-1, lines.back().length())

static func _compute_insertion_position(target_class: SymbolApi.ClassScope, context_scope: SymbolApi.ScopeInfo) -> Dictionary:
	var call_class = context_scope.class_scope
	var call_method = context_scope.method_scope
	
	if call_method and call_class == target_class:
		var m = call_method
		while m.parent is SymbolApi.MethodScope:
			m = m.parent
		return { "line": m.end_line, "is_header": false }
		
	var last_item_end = -1
	for m_name in target_class.methods:
		var arr = target_class.methods[m_name]
		for m in arr:
			if m.end_line > last_item_end: last_item_end = m.end_line
	for v_name in target_class.vars:
		var vs = target_class.vars[v_name]
		if vs.end_line > last_item_end: last_item_end = vs.end_line
		
	if last_item_end != -1:
		return { "line": last_item_end, "is_header": false }
		
	var base = target_class.extends_line if target_class.extends_line != -1 else target_class.start_line
	return { "line": max(0, base), "is_header": true }
