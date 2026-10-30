@tool
extends RefCounted

const GDSExCliFiles = preload("res://addons/gdscript_extreme_tool/cli/cli_files.gd")
const GDSExCliLineMap = preload("res://addons/gdscript_extreme_tool/cli/cli_line_map.gd")
const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExEditPlan = preload("res://addons/gdscript_extreme_tool/editing/edit_plan.gd")
const GDSExEditApplier = preload("res://addons/gdscript_extreme_tool/editing/edit_applier.gd")

const LINE_SEPARATOR: String = "\n"
const WINDOWS_LINE_SEPARATOR: String = "\r\n"
const PROJECT_ROOT: String = "res://"
const FOLDER_SEPARATOR: String = "/"
const PARENT_FOLDER: String = ".."
const STANDARD_INPUT: String = "-"
const ADDED_TEMPLATE: String = "+%d"
const REMOVED_TEMPLATE: String = "-%d"
const CHANGED_TEMPLATE: String = "+%d -%d"


class GDSExDocument:
	var path: String = ""
	var display_path: String = ""
	var lines: PackedStringArray = []
	var original_lines: PackedStringArray = []
	var uses_windows_line_separators: bool = false
	var is_virtual: bool = false
	var origin_map: PackedInt32Array = []

	func text() -> String:
		return LINE_SEPARATOR.join(lines)

	func written_text() -> String:
		var joined := text()
		return joined.replace(LINE_SEPARATOR, WINDOWS_LINE_SEPARATOR) if uses_windows_line_separators else joined

	func is_changed() -> bool:
		return lines != original_lines

	func current_line(original_line: int) -> int:
		if original_line < 0 or original_line >= origin_map.size():
			return GDSExCliLineMap.REMOVED
		return origin_map[original_line]

	func code_line_count() -> int:
		return lines.size() - 1 if not lines.is_empty() and lines[lines.size() - 1].is_empty() else lines.size()


class GDSExChange:
	var document: GDSExDocument
	var old_lines: PackedStringArray = []
	var map: PackedInt32Array = []
	var new_lines: PackedInt32Array = []
	var removed: int = 0

	func added() -> int:
		return new_lines.size()

	func summary() -> String:
		if removed == 0:
			return ADDED_TEMPLATE % added()
		if added() == 0:
			return REMOVED_TEMPLATE % removed
		return CHANGED_TEMPLATE % [added(), removed]


class GDSExBlock:
	var document: GDSExDocument
	var summary: String = ""
	var lines: PackedInt32Array = []
	var suffixes: PackedStringArray = []
	var warnings: PackedStringArray = []
	var is_error: bool = false

	func show_line(line: int, suffix: String = "") -> void:
		lines.append(line)
		suffixes.append(suffix)

	func show_lines(first_line: int, last_line: int) -> void:
		for line in range(first_line, last_line + 1):
			show_line(line)


var files: GDSExCliFiles
var working_folder: String = ""
var documents: Dictionary[String, GDSExDocument] = {}
var blocks: Array[GDSExBlock] = []


func _init(session_files: GDSExCliFiles, session_working_folder: String) -> void:
	files = session_files
	working_folder = session_working_folder.trim_suffix(FOLDER_SEPARATOR)


func local_path(written_path: String) -> String:
	if written_path.begins_with(PROJECT_ROOT):
		return written_path.simplify_path()
	var absolute := written_path if written_path.is_absolute_path() else working_folder.path_join(written_path)
	var local := ProjectSettings.localize_path(absolute.simplify_path())
	return local if local.begins_with(PROJECT_ROOT) else ""


func display_path(path: String) -> String:
	var parts := ProjectSettings.globalize_path(path).split(FOLDER_SEPARATOR, false)
	var folder_parts := working_folder.split(FOLDER_SEPARATOR, false)
	var shared := 0
	while shared < folder_parts.size() and shared < parts.size() - 1 and parts[shared] == folder_parts[shared]:
		shared += 1
	if shared == 0:
		return path
	var relative := PackedStringArray()
	for index in folder_parts.size() - shared:
		relative.append(PARENT_FOLDER)
	relative.append_array(parts.slice(shared))
	return FOLDER_SEPARATOR.join(relative)


func open(path: String) -> GDSExDocument:
	if documents.has(path):
		return documents[path]
	if not files.has_file(path):
		return null
	return _add_document(path, files.read_text(path), false)


func open_virtual(path: String, text: String) -> GDSExDocument:
	return _add_document(path, text, true)


func source_overrides() -> Dictionary[String, String]:
	var sources := files.unsaved_sources().duplicate()
	for path in documents:
		var document := documents[path]
		if document.is_changed() or document.is_virtual:
			sources[path] = document.text()
	return sources


func new_editor(document: GDSExDocument) -> CodeEdit:
	var editor := CodeEdit.new()
	editor.text = document.text()
	editor.clear_undo_history()
	return editor


func new_context(document: GDSExDocument, editor: CodeEdit) -> GDSExCodeContext:
	return GDSExCodeContext.new(editor, document.path, source_overrides())


func apply(document: GDSExDocument, plan: GDSExEditPlan, editor: CodeEdit = null) -> GDSExChange:
	if plan == null or plan.is_empty():
		return null
	var target := document
	if plan.is_for_another_script():
		target = open(plan.script_path)
		if target == null:
			return null
		editor = null
	var owned_editor := editor == null
	var target_editor := new_editor(target) if owned_editor else editor
	GDSExEditApplier.apply(target_editor, plan)
	var new_lines := target_editor.text.split(LINE_SEPARATOR)
	if owned_editor:
		target_editor.free()
	return record_change(target, new_lines, plan)


func record_change(document: GDSExDocument, new_lines: PackedStringArray, plan: GDSExEditPlan = null) -> GDSExChange:
	var change := GDSExChange.new()
	change.document = document
	change.old_lines = document.lines
	change.map = GDSExCliLineMap.between(document.lines, new_lines, plan)
	var images: Dictionary[int, bool] = {}
	for line in change.map.size():
		var image := change.map[line]
		if image != GDSExCliLineMap.REMOVED and change.old_lines[line] == new_lines[image]:
			images[image] = true
		else:
			change.removed += 1
	for line in new_lines.size():
		if not images.has(line):
			change.new_lines.append(line)
	document.lines = new_lines
	document.origin_map = GDSExCliLineMap.compose(document.origin_map, change.map)
	for block in blocks:
		if block.document == document:
			block.lines = GDSExCliLineMap.compose(block.lines, change.map)
	return change


func add_block(document: GDSExDocument, summary: String) -> GDSExBlock:
	var block := GDSExBlock.new()
	block.document = document
	block.summary = summary
	blocks.append(block)
	return block


func add_error(message: String) -> GDSExBlock:
	var block := add_block(null, message)
	block.is_error = true
	return block


func add_note(message: String) -> GDSExBlock:
	return add_block(null, message)


func has_errors() -> bool:
	for block in blocks:
		if block.is_error:
			return true
	return false


func changed_documents() -> Array[GDSExDocument]:
	var changed: Array[GDSExDocument] = []
	for path in documents:
		if documents[path].is_changed():
			changed.append(documents[path])
	return changed


func write_changes() -> PackedStringArray:
	var failed := PackedStringArray()
	for document in changed_documents():
		if document.is_virtual:
			continue
		if not files.write_text(document.path, document.written_text()):
			failed.append(document.display_path)
	return failed


func _add_document(path: String, text: String, is_virtual: bool) -> GDSExDocument:
	var document := GDSExDocument.new()
	document.path = path
	document.display_path = display_path(path) if not is_virtual else STANDARD_INPUT
	document.is_virtual = is_virtual
	document.uses_windows_line_separators = text.contains(WINDOWS_LINE_SEPARATOR)
	document.lines = text.replace(WINDOWS_LINE_SEPARATOR, LINE_SEPARATOR).split(LINE_SEPARATOR)
	document.original_lines = document.lines.duplicate()
	document.origin_map = GDSExCliLineMap.identity(document.lines.size())
	documents[path] = document
	return document
