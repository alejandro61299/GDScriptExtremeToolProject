@tool
extends RefCounted

const SCRIPT_TAB_CLASS : String = "ScriptTextEditor"
const EXTERNAL_EDITOR_SETTING : String = "text_editor/external/use_external_editor"


static func find_path(editor : CodeEdit) -> String:
	if not Engine.is_editor_hint():
		return ""
	var script_editor := EditorInterface.get_script_editor()
	var current_tab := script_editor.get_current_editor()
	var current_script := script_editor.get_current_script()
	if current_tab != null and current_script != null and current_tab.get_base_editor() == editor:
		return current_script.resource_path
	var tabs := _find_tabs()
	for script_path : String in tabs:
		if tabs[script_path] == editor:
			return script_path
	return ""


static func find_unsaved_sources() -> Dictionary[String, String]:
	var sources : Dictionary[String, String] = {}
	var tabs := _find_tabs()
	for script_path : String in tabs:
		var editor := tabs[script_path]
		if editor.get_version() != editor.get_saved_version():
			sources[script_path] = editor.text
	return sources


static func can_edit(script_path : String) -> bool:
	if script_path.is_empty():
		return false
	if not Engine.is_editor_hint():
		return true
	var settings := EditorInterface.get_editor_settings()
	if settings.has_setting(EXTERNAL_EDITOR_SETTING) and settings.get_setting(EXTERNAL_EDITOR_SETTING):
		return false
	return _find_open_script(script_path) != null or FileAccess.file_exists(script_path)


static func open(script_path : String) -> CodeEdit:
	if not Engine.is_editor_hint():
		return null
	var script := _find_open_script(script_path)
	if script == null and ResourceLoader.exists(script_path):
		script = load(script_path) as Script
	if script == null:
		return null
	EditorInterface.edit_script(script)
	var script_editor := EditorInterface.get_script_editor()
	var current_tab := script_editor.get_current_editor()
	if current_tab == null or script_editor.get_current_script() != script:
		return null
	return current_tab.get_base_editor() as CodeEdit


static func _find_open_script(script_path : String) -> Script:
	for script : Script in EditorInterface.get_script_editor().get_open_scripts():
		if script.resource_path == script_path:
			return script
	return null


static func _find_tabs() -> Dictionary[String, CodeEdit]:
	var tabs : Dictionary[String, CodeEdit] = {}
	if not Engine.is_editor_hint():
		return tabs
	var script_editor := EditorInterface.get_script_editor()
	var editors : Array[CodeEdit] = []
	for tab in script_editor.get_open_script_editors():
		if tab.get_class() == SCRIPT_TAB_CLASS:
			editors.append(tab.get_base_editor() as CodeEdit)
	var scripts := script_editor.get_open_scripts()
	if editors.size() != scripts.size():
		return tabs
	for index in scripts.size():
		var script_path := (scripts[index] as Script).resource_path
		if editors[index] != null and not script_path.is_empty():
			tabs[script_path] = editors[index]
	return tabs
