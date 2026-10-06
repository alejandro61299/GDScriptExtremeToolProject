@tool
extends PopupMenu

const GDSExActionRegistry = preload("res://addons/gdscript_extreme_tool/actions/action_registry.gd")
const GDSExCodeAction = preload("res://addons/gdscript_extreme_tool/actions/code_action.gd")
const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExEditApplier = preload("res://addons/gdscript_extreme_tool/editing/edit_applier.gd")
const GDSExEditPlan = preload("res://addons/gdscript_extreme_tool/editing/edit_plan.gd")

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
	var context := GDSExCodeContext.new(_editor)
	var dialog := action.create_dialog(context, apply_plan.bind(_editor))
	if dialog == null:
		apply_plan(action.build_plan(context), _editor)
		return
	dialog.visibility_changed.connect(_free_when_hidden.bind(dialog))
	_editor.get_window().add_child(dialog)
	dialog.popup_centered()


static func apply_plan(plan : GDSExEditPlan, editor : CodeEdit) -> void:
	if plan == null or editor == null:
		return
	if plan.leaves_current_position():
		_save_navigation_history(editor)
	GDSExEditApplier.apply(editor, plan)
	editor.grab_focus()


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
