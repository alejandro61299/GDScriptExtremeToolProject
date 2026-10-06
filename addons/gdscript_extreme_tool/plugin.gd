@tool
extends EditorPlugin

const GDSExActionRegistry = preload("res://addons/gdscript_extreme_tool/actions/action_registry.gd")
const GDSExCodeAction = preload("res://addons/gdscript_extreme_tool/actions/code_action.gd")
const GDSExCodeActionsPopup = preload("res://addons/gdscript_extreme_tool/code_actions_popup.gd")
const GDSExPluginProjectSettings = preload("res://addons/gdscript_extreme_tool/plugin_project_settings.gd")

const SUBMENU_LABEL : String = "GDScript Extreme Tool"
const SHORTCUT_PATH : String = "gdscript_extreme_tool/show_code_actions"
const SHORTCUT_NAME : String = "Show Code Actions"

var _actions : Array[GDSExCodeAction] = GDSExActionRegistry.create_actions()
var _context_menu_plugin : GDSExCodeActionsMenuPlugin


func _enter_tree() -> void:
	GDSExPluginProjectSettings.register()
	_register_shortcut()
	_context_menu_plugin = GDSExCodeActionsMenuPlugin.new()
	_context_menu_plugin.actions = _actions
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, _context_menu_plugin)


func _exit_tree() -> void:
	remove_context_menu_plugin(_context_menu_plugin)
	_context_menu_plugin = null


func _shortcut_input(event : InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if not EditorInterface.get_editor_settings().is_shortcut(SHORTCUT_PATH, event):
		return
	var editor := _focused_code_editor()
	if editor == null:
		return
	get_viewport().set_input_as_handled()
	var popup := GDSExCodeActionsPopup.new()
	popup.setup(editor, _actions)
	popup.popup_hide.connect(popup.queue_free)
	EditorInterface.get_base_control().add_child(popup)
	popup.popup_at_caret()


func _register_shortcut() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.alt_pressed = true
	var shortcut := Shortcut.new()
	shortcut.resource_name = SHORTCUT_NAME
	shortcut.events = [key]
	EditorInterface.get_editor_settings().add_shortcut(SHORTCUT_PATH, shortcut)


func _focused_code_editor() -> CodeEdit:
	var script_editor := EditorInterface.get_script_editor().get_current_editor()
	if script_editor == null:
		return null
	var editor := script_editor.get_base_editor() as CodeEdit
	return editor if editor != null and editor.has_focus() else null


class GDSExCodeActionsMenuPlugin extends EditorContextMenuPlugin:

	var actions : Array[GDSExCodeAction] = []


	func _popup_menu(paths : PackedStringArray) -> void:
		var editor := _find_editor(paths)
		if editor == null:
			return
		var submenu := GDSExCodeActionsPopup.new()
		submenu.setup(editor, actions)
		add_context_submenu_item(SUBMENU_LABEL, submenu)


	func _find_editor(paths : PackedStringArray) -> CodeEdit:
		var scene_tree := Engine.get_main_loop() as SceneTree
		if not paths.is_empty() and scene_tree != null:
			var editor := scene_tree.root.get_node_or_null(paths[0]) as CodeEdit
			if editor != null:
				return editor
		var script_editor := EditorInterface.get_script_editor().get_current_editor()
		return script_editor.get_base_editor() as CodeEdit if script_editor != null else null
