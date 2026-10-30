@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSymbolIndexBuilder = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index_builder.gd")

const SCRIPT_EXTENSION: String = "gd"
const LINE_SEPARATOR: String = "\n"
const WINDOWS_LINE_SEPARATOR: String = "\r\n"
const PROJECT_ROOT: String = "res://"
const HIDDEN_PREFIX: String = "."
const GLOBAL_NAME_PATTERN: String = "(?m)^class_name\\s+([A-Za-z_]\\w*)"

static var _entries: Dictionary[String, GDSExEntry] = {}
static var _unsaved_sources: Dictionary[String, String] = {}
static var _generation: int = 0
static var _global_class_paths: Dictionary[String, String] = {}
static var _global_classes_generation: int = -1
static var scans_for_global_classes: bool = false
static var _scanned_class_paths: Dictionary[String, String] = {}
static var _has_scanned: bool = false


class GDSExEntry:
	var index: GDSExSymbolIndex.GDSExSymbolIndexData
	var source_hash: int = 0
	var generation: int = 0


static func refresh(unsaved_sources: Dictionary[String, String]) -> void:
	_unsaved_sources = unsaved_sources
	_generation += 1


static func find_index(script_path: String) -> GDSExSymbolIndex.GDSExSymbolIndexData:
	var entry: GDSExEntry = _entries.get(script_path)
	if entry != null and entry.generation == _generation:
		return entry.index
	if not _has_source(script_path):
		_entries.erase(script_path)
		return null
	var source := _read_source(script_path)
	if entry == null or entry.source_hash != source.hash():
		entry = GDSExEntry.new()
		entry.index = GDSExSymbolIndexBuilder.build(source.split(LINE_SEPARATOR), script_path)
		entry.source_hash = source.hash()
		_entries[script_path] = entry
	entry.generation = _generation
	return entry.index


static func find_lines(script_path: String) -> PackedStringArray:
	return _read_source(script_path).split(LINE_SEPARATOR) if _has_source(script_path) else PackedStringArray()


static func find_global_class_path(global_name: String) -> String:
	if _global_classes_generation != _generation:
		_global_classes_generation = _generation
		_global_class_paths.clear()
		for global_class in ProjectSettings.get_global_class_list():
			_global_class_paths[global_class["class"]] = global_class["path"]
	var path: String = _global_class_paths.get(global_name, "")
	if path.is_empty() and scans_for_global_classes and _could_be_a_global_class(global_name):
		path = _scanned_global_class_path(global_name)
	return path


static func clear() -> void:
	_entries.clear()
	_unsaved_sources = {}
	_global_class_paths.clear()
	_global_classes_generation = -1
	_scanned_class_paths.clear()
	_has_scanned = false


static func _has_source(script_path: String) -> bool:
	if script_path.get_extension() != SCRIPT_EXTENSION:
		return false
	return _unsaved_sources.has(script_path) or FileAccess.file_exists(script_path)


static func _read_source(script_path: String) -> String:
	var source: String = _unsaved_sources[script_path] if _unsaved_sources.has(script_path) else FileAccess.get_file_as_string(script_path)
	return source.replace(WINDOWS_LINE_SEPARATOR, LINE_SEPARATOR)


static func _could_be_a_global_class(global_name: String) -> bool:
	return not global_name.is_empty() and global_name[0] == global_name[0].to_upper() and global_name[0] != global_name[0].to_lower() and not ClassDB.class_exists(global_name)


static func _scanned_global_class_path(global_name: String) -> String:
	if not _has_scanned:
		_has_scanned = true
		var pattern := RegEx.create_from_string(GLOBAL_NAME_PATTERN)
		for script_path in _project_scripts(PROJECT_ROOT):
			_add_scanned_names(pattern, script_path, FileAccess.get_file_as_string(script_path))
		for script_path in _unsaved_sources:
			_add_scanned_names(pattern, script_path, _unsaved_sources[script_path])
	return _scanned_class_paths.get(global_name, "")


static func _add_scanned_names(pattern: RegEx, script_path: String, source: String) -> void:
	for found in pattern.search_all(source):
		if not _scanned_class_paths.has(found.get_string(1)):
			_scanned_class_paths[found.get_string(1)] = script_path


static func _project_scripts(folder: String) -> PackedStringArray:
	var scripts := PackedStringArray()
	for subfolder in DirAccess.get_directories_at(folder):
		if not subfolder.begins_with(HIDDEN_PREFIX):
			scripts.append_array(_project_scripts(folder.path_join(subfolder)))
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() == SCRIPT_EXTENSION:
			scripts.append(folder.path_join(file))
	return scripts
