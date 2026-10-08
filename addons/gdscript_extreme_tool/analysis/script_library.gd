@tool
extends RefCounted

const GDSExSymbolIndex = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index.gd")
const GDSExSymbolIndexBuilder = preload("res://addons/gdscript_extreme_tool/analysis/symbol_index_builder.gd")

const SCRIPT_EXTENSION: String = "gd"
const LINE_SEPARATOR: String = "\n"
const WINDOWS_LINE_SEPARATOR: String = "\r\n"

static var _entries: Dictionary[String, GDSExEntry] = {}
static var _unsaved_sources: Dictionary[String, String] = {}
static var _generation: int = 0
static var _global_class_paths: Dictionary[String, String] = {}
static var _global_classes_generation: int = -1


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
	return _global_class_paths.get(global_name, "")


static func clear() -> void:
	_entries.clear()
	_unsaved_sources = {}
	_global_class_paths.clear()
	_global_classes_generation = -1


static func _has_source(script_path: String) -> bool:
	if script_path.get_extension() != SCRIPT_EXTENSION:
		return false
	return _unsaved_sources.has(script_path) or FileAccess.file_exists(script_path)


static func _read_source(script_path: String) -> String:
	var source: String = _unsaved_sources[script_path] if _unsaved_sources.has(script_path) else FileAccess.get_file_as_string(script_path)
	return source.replace(WINDOWS_LINE_SEPARATOR, LINE_SEPARATOR)
