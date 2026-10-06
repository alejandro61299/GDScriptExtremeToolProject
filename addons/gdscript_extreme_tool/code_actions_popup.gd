@tool
extends PopupMenu

const GDSExActionRegistry = preload("res://addons/gdscript_extreme_tool/actions/action_registry.gd")
const GDSExCodeAction = preload("res://addons/gdscript_extreme_tool/actions/code_action.gd")
const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExEditApplier = preload("res://addons/gdscript_extreme_tool/editing/edit_applier.gd")

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
		for action in GDSExActionRegistry.find_available(_actions, GDSExCodeContext.new(_editor)):
			add_item(action.get_label())
			set_item_metadata(item_count - 1, action)
	if item_count == 0:
		_add_no_actions_item()


func _add_no_actions_item() -> void:
	add_item(NO_ACTIONS_LABEL)
	set_item_disabled(item_count - 1, true)


func _run_action(index : int) -> void:
	var action := get_item_metadata(index) as GDSExCodeAction
	if action == null or _editor == null:
		return
	var plan := action.build_plan(GDSExCodeContext.new(_editor))
	if plan != null and plan.leaves_current_position():
		_save_navigation_history()
	GDSExEditApplier.apply(_editor, plan)
	_editor.grab_focus()


func _save_navigation_history() -> void:
	if not Engine.is_editor_hint():
		return
	for script_editor in EditorInterface.get_script_editor().get_open_script_editors():
		if script_editor.get_base_editor() == _editor:
			script_editor.request_save_history.emit()
			return
