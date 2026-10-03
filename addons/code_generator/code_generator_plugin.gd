@tool
extends EditorPlugin

const Generator : GDScript = preload("res://addons/code_generator/stub_generator.gd")

# We store a reference to the context plugin to remove it later
var _context_menu_plugin : StubContextMenuPlugin


func _enter_tree() -> void:
	_context_menu_plugin = StubContextMenuPlugin.new()
	_context_menu_plugin.generate_method_stub_pressed.connect(_on_generate_method_stub_pressed)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, _context_menu_plugin)


func _exit_tree() -> void:
	remove_context_menu_plugin(_context_menu_plugin)
	_context_menu_plugin = null


func _on_generate_method_stub_pressed() -> void:
	var current_editor : ScriptEditorBase = EditorInterface.get_script_editor().get_current_editor()
	Generator.new().generate_stub(current_editor.get_base_editor() as CodeEdit)


# --- Helper Class for the Context Menu ---
class StubContextMenuPlugin extends EditorContextMenuPlugin:

	signal generate_method_stub_pressed()
	
	# This is called by Godot when the user right-clicks
	func _popup_menu(_paths: PackedStringArray) -> void:
		add_context_menu_item("Generate Method Stub", _on_generate_metod_stub_item_presed)

	# The callback for the menu item
	func _on_generate_metod_stub_item_presed(_args : Object) -> void:
		generate_method_stub_pressed.emit()
