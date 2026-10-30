@tool
extends RefCounted

const SCRIPT_EXTENSION: String = "gd"
const PROJECT_ROOT: String = "res://"
const HIDDEN_PREFIX: String = "."
const SKIPPED_FOLDERS: Array[String] = ["res://addons", "res://.godot"]
const GIT_COMMAND: String = "git"
const GIT_STATUS_ARGUMENTS: Array[String] = ["status", "--porcelain", "--untracked-files=all", "--no-renames"]
const GIT_TOP_LEVEL_ARGUMENTS: Array[String] = ["rev-parse", "--show-toplevel"]
const GIT_PATH_ARGUMENT: String = "-C"
const GIT_STATUS_PREFIX_LENGTH: int = 3
const GIT_DELETED_MARK: String = "D"
const LINE_SEPARATOR: String = "\n"
const QUOTE: String = "\""


func unsaved_sources() -> Dictionary[String, String]:
	return {}


func read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func has_file(path: String) -> bool:
	return FileAccess.file_exists(path)


func has_folder(path: String) -> bool:
	return DirAccess.dir_exists_absolute(path)


func write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func list_scripts(folder: String) -> PackedStringArray:
	var scripts := PackedStringArray()
	_collect_scripts(folder.trim_suffix("/") if folder != PROJECT_ROOT else folder, _is_skipped(folder), scripts)
	scripts.sort()
	return scripts


func changed_scripts() -> PackedStringArray:
	var top_folder := _git(GIT_TOP_LEVEL_ARGUMENTS).strip_edges()
	var scripts := PackedStringArray()
	if top_folder.is_empty():
		return scripts
	for line in _git(GIT_STATUS_ARGUMENTS).split(LINE_SEPARATOR, false):
		if line.length() <= GIT_STATUS_PREFIX_LENGTH or line.substr(0, GIT_STATUS_PREFIX_LENGTH).contains(GIT_DELETED_MARK):
			continue
		var relative := line.substr(GIT_STATUS_PREFIX_LENGTH).strip_edges().trim_prefix(QUOTE).trim_suffix(QUOTE)
		if relative.get_extension() != SCRIPT_EXTENSION:
			continue
		var local_path := ProjectSettings.localize_path(top_folder.path_join(relative))
		if local_path.begins_with(PROJECT_ROOT):
			scripts.append(local_path)
	scripts.sort()
	return scripts


func is_git_repository() -> bool:
	return not _git(GIT_TOP_LEVEL_ARGUMENTS).strip_edges().is_empty()


func _git(command_arguments: Array[String]) -> String:
	var arguments := PackedStringArray([GIT_PATH_ARGUMENT, ProjectSettings.globalize_path(PROJECT_ROOT)])
	arguments.append_array(command_arguments)
	var output: Array = []
	if OS.execute(GIT_COMMAND, arguments, output) != 0 or output.is_empty():
		return ""
	return String(output[0])


func _collect_scripts(folder: String, includes_skipped: bool, scripts: PackedStringArray) -> void:
	for subfolder in DirAccess.get_directories_at(folder):
		var path := folder.path_join(subfolder)
		if subfolder.begins_with(HIDDEN_PREFIX) or (not includes_skipped and SKIPPED_FOLDERS.has(path)):
			continue
		_collect_scripts(path, includes_skipped, scripts)
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() == SCRIPT_EXTENSION:
			scripts.append(folder.path_join(file))


func _is_skipped(folder: String) -> bool:
	for skipped in SKIPPED_FOLDERS:
		if folder == skipped or folder.begins_with(skipped + "/"):
			return true
	return false
