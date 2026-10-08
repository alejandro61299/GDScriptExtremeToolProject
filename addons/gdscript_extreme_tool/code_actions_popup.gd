@tool
extends PopupMenu

const GDSExActionRegistry = preload("res://addons/gdscript_extreme_tool/actions/action_registry.gd")
const GDSExCodeAction = preload("res://addons/gdscript_extreme_tool/actions/code_action.gd")
const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExEditApplier = preload("res://addons/gdscript_extreme_tool/editing/edit_applier.gd")
const GDSExEditPlan = preload("res://addons/gdscript_extreme_tool/editing/edit_plan.gd")
const GDSExOpenScripts = preload("res://addons/gdscript_extreme_tool/open_scripts.gd")
const GDSExScriptLibrary = preload("res://addons/gdscript_extreme_tool/analysis/script_library.gd")

const NO_ACTIONS_LABEL : String = "No actions available here"

var _editor : CodeEdit
var _actions : Array[GDSExCodeAction] = []


func _init() -> void:
	_add_no_actions_item()
	about_to_popup.connect(_fill)
	index_pressed.connect(_run_action)


func setup(editor : CodeEdit, actions : Array[GDSExCodeAction]) -> void:
	_editor = editor
	_actions = actions


func popup_at_caret() -> void:
	position = Vector2i(_editor.get_screen_position() + _editor.get_caret_draw_pos())
	reset_size()
	popup()
	if not is_item_disabled(0):
		set_focused_item(0)


func _fill() -> void:
	clear()
	if _editor != null:
		for available in GDSExActionRegistry.find_available(_actions, _create_context()):
			add_item(available.label)
			set_item_metadata(item_count - 1, available.action)
	if item_count == 0:
		_add_no_actions_item()


func _add_no_actions_item() -> void:
	add_item(NO_ACTIONS_LABEL)
	set_item_disabled(item_count - 1, true)


func _run_action(index : int) -> void:
	var action := get_item_metadata(index) as GDSExCodeAction
	if action == null or _editor == null:
		return
	var context := _create_context()
	var dialog := action.create_dialog(context, apply_plan.bind(_editor))
	if dialog == null:
		_apply_action(action, context)
		return
	dialog.visibility_changed.connect(_free_when_hidden.bind(dialog))
	_editor.get_window().add_child(dialog)
	dialog.popup_centered()


func _apply_action(action : GDSExCodeAction, context : GDSExCodeContext) -> void:
	var plan := action.build_plan(context)
	if plan == null or not plan.is_for_another_script():
		apply_plan(plan, _editor)
		return
	_save_navigation_history(_editor)
	apply_in_tab(action, _editor, context, plan.script_path, GDSExOpenScripts.open(plan.script_path))


func _create_context() -> GDSExCodeContext:
	return GDSExCodeContext.new(_editor, GDSExOpenScripts.find_path(_editor), GDSExOpenScripts.find_unsaved_sources())


static func forget_scripts() -> void:
	GDSExScriptLibrary.clear()


static func apply_plan(plan : GDSExEditPlan, editor : CodeEdit) -> void:
	if plan == null or editor == null or plan.is_for_another_script():
		return
	if plan.leaves_current_position():
		_save_navigation_history(editor)
	GDSExEditApplier.apply(editor, plan)
	editor.grab_focus()


static func apply_in_tab(action : GDSExCodeAction, editor : CodeEdit, context : GDSExCodeContext, tab_script_path : String, tab_editor : CodeEdit) -> void:
	if tab_editor == null or tab_editor == editor or not tab_editor.editable:
		return
	var sources := context.unsaved_sources.duplicate()
	sources[tab_script_path] = tab_editor.text
	var plan := action.build_plan(GDSExCodeContext.new(editor, context.script_path, sources))
	if plan == null or plan.script_path != tab_script_path:
		return
	GDSExEditApplier.apply(tab_editor, plan)
	tab_editor.grab_focus()


static func _free_when_hidden(dialog : Window) -> void:
	if not dialog.visible:
		dialog.queue_free()


static func _save_navigation_history(editor : CodeEdit) -> void:
	if not Engine.is_editor_hint():
		return
	for script_editor in EditorInterface.get_script_editor().get_open_script_editors():
		if script_editor.get_base_editor() == editor:
			script_editor.request_save_history.emit()
			return
