@tool
extends EditorPlugin

const ActionRegistry = preload("res://addons/code_generator/actions/action_registry.gd")
const CodeAction = preload("res://addons/code_generator/actions/code_action.gd")
const CodeContext = preload("res://addons/code_generator/actions/code_context.gd")
const EditApplier = preload("res://addons/code_generator/editing/edit_applier.gd")

var _context_menu_plugin : CodeActionsMenuPlugin


func _enter_tree() -> void:
	_context_menu_plugin = CodeActionsMenuPlugin.new()
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, _context_menu_plugin)


func _exit_tree() -> void:
	remove_context_menu_plugin(_context_menu_plugin)
	_context_menu_plugin = null


class CodeActionsMenuPlugin extends EditorContextMenuPlugin:

	var _actions : Array[CodeAction] = ActionRegistry.create_actions()


	func _popup_menu(paths : PackedStringArray) -> void:
		var editor := _find_editor(paths)
		if editor == null:
			return
		for action in ActionRegistry.find_available(_actions, CodeContext.new(editor)):
			add_context_menu_item(action.get_label(), _run_action.bind(action))


	func _run_action(target : Variant, action : CodeAction) -> void:
		var editor : CodeEdit = target if target is CodeEdit else _current_editor()
		if editor != null:
			EditApplier.apply(editor, action.build_plan(CodeContext.new(editor)))


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
