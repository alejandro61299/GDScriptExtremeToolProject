@tool
extends EditorPlugin

const GDSExActionRegistry = preload("res://addons/gdscript_extreme_tool/actions/action_registry.gd")
const GDSExCodeAction = preload("res://addons/gdscript_extreme_tool/actions/code_action.gd")
const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExEditApplier = preload("res://addons/gdscript_extreme_tool/editing/edit_applier.gd")
const GDSExPluginProjectSettings = preload("res://addons/gdscript_extreme_tool/plugin_project_settings.gd")

var _context_menu_plugin : GDSExCodeActionsMenuPlugin


func _enter_tree() -> void:
	GDSExPluginProjectSettings.register()
	_context_menu_plugin = GDSExCodeActionsMenuPlugin.new()
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, _context_menu_plugin)


func _exit_tree() -> void:
	remove_context_menu_plugin(_context_menu_plugin)
	_context_menu_plugin = null


class GDSExCodeActionsMenuPlugin extends EditorContextMenuPlugin:

	var _actions : Array[GDSExCodeAction] = GDSExActionRegistry.create_actions()


	func _popup_menu(paths : PackedStringArray) -> void:
		var editor := _find_editor(paths)
		if editor == null:
			return
		for action in GDSExActionRegistry.find_available(_actions, GDSExCodeContext.new(editor)):
			add_context_menu_item(action.get_label(), _run_action.bind(action))


	func _run_action(target : Variant, action : GDSExCodeAction) -> void:
		var editor : CodeEdit = target if target is CodeEdit else _current_editor()
		if editor == null:
			return
		var plan := action.build_plan(GDSExCodeContext.new(editor))
		if plan != null and plan.leaves_current_position():
			_save_navigation_history(editor)
		GDSExEditApplier.apply(editor, plan)


	func _save_navigation_history(editor : CodeEdit) -> void:
		for script_editor in EditorInterface.get_script_editor().get_open_script_editors():
			if script_editor.get_base_editor() == editor:
				script_editor.request_save_history.emit()
				return


	func _find_editor(paths : PackedStringArray) -> CodeEdit:
		var scene_tree := Engine.get_main_loop() as SceneTree
		if not paths.is_empty() and scene_tree != null:
			var editor := scene_tree.root.get_node_or_null(paths[0]) as CodeEdit
			if editor != null:
				return editor
		return _current_editor()


	func _current_editor() -> CodeEdit:
		var script_editor := EditorInterface.get_script_editor().get_current_editor()
		return script_editor.get_base_editor() as CodeEdit if script_editor != null else null
