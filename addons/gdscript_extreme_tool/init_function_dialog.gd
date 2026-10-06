@tool
extends ConfirmationDialog

const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExInitFunction = preload("res://addons/gdscript_extreme_tool/actions/init_function.gd")
const GDSExMemberCategories = preload("res://addons/gdscript_extreme_tool/analysis/member_categories.gd")

const TITLE : String = "Generate Custom Init Definition"
const GENERATE_TEXT : String = "Generate"
const NAME_TEXT : String = "Name"
const ALL_TEXT : String = "All"
const NONE_TEXT : String = "None"
const FILTER_CATEGORIES : Array[String] = [GDSExMemberCategories.PRIVATE_VARIABLES, GDSExMemberCategories.PUBLIC_VARIABLES, GDSExMemberCategories.EXPORTS]
const FILTER_TEXTS : Array[String] = ["Private", "Public", "Exports"]
const MESSAGE_BULLET : String = "• "
const MINIMUM_SIZE : Vector2i = Vector2i(560, 420)
const LIST_MINIMUM_HEIGHT : float = 160.0
const NAME_COLUMN : int = 0
const TYPE_COLUMN : int = 1
const FONT_COLOR : StringName = &"font_color"
const EDITOR_THEME_TYPE : StringName = &"Editor"
const EDITOR_FONTS_THEME_TYPE : StringName = &"EditorFonts"
const SOURCE_FONT : StringName = &"source"
const LEVEL_COLOR_NAMES : Array[StringName] = [&"success_color", &"warning_color", &"error_color"]
const LEVEL_FALLBACK_COLORS : Array[Color] = [Color("73f280"), Color("d4c79e"), Color("ff786b")]

var name_edit : LineEdit
var filter_buttons : Dictionary[String, Button] = {}
var all_button : Button
var none_button : Button
var variable_tree : Tree
var preview_label : Label
var validation_label : Label

var _context : GDSExCodeContext
var _on_plan_ready : Callable
var _name_check : GDSExInitFunction.GDSExNameCheck


func _init() -> void:
	title = TITLE
	ok_button_text = GENERATE_TEXT
	min_size = MINIMUM_SIZE
	var content := VBoxContainer.new()
	add_child(content)
	content.add_child(_build_name_row())
	content.add_child(_build_toolbar())
	content.add_child(_build_variable_tree())
	content.add_child(_build_preview())
	content.add_child(_build_validation_panel())
	confirmed.connect(_on_confirmed)
	visibility_changed.connect(_on_visibility_changed)


func _ready() -> void:
	if Engine.is_editor_hint():
		min_size = Vector2i(Vector2(MINIMUM_SIZE) * EditorInterface.get_editor_scale())
	if has_theme_font(SOURCE_FONT, EDITOR_FONTS_THEME_TYPE):
		preview_label.add_theme_font_override(&"font", get_theme_font(SOURCE_FONT, EDITOR_FONTS_THEME_TYPE))
	_refresh()


func setup(context : GDSExCodeContext, on_plan_ready : Callable) -> void:
	_context = context
	_on_plan_ready = on_plan_ready
	name_edit.text = GDSExInitFunction.default_function_name(context)
	for variable in GDSExInitFunction.find_variables(context):
		var item := variable_tree.create_item()
		item.set_cell_mode(NAME_COLUMN, TreeItem.CELL_MODE_CHECK)
		item.set_editable(NAME_COLUMN, true)
		item.set_text(NAME_COLUMN, variable.name)
		item.set_checked(NAME_COLUMN, variable.category == GDSExMemberCategories.PRIVATE_VARIABLES)
		item.set_metadata(NAME_COLUMN, variable.category)
		item.set_text(TYPE_COLUMN, variable.type_text)
		filter_buttons[variable.category].disabled = false
	_refresh()


func get_selected_variable_names() -> PackedStringArray:
	var names := PackedStringArray()
	for item in variable_tree.get_root().get_children():
		if item.is_checked(NAME_COLUMN):
			names.append(item.get_text(NAME_COLUMN))
	return names


func _build_name_row() -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = NAME_TEXT
	row.add_child(label)
	name_edit = LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.keep_editing_on_text_submit = true
	name_edit.text_changed.connect(_on_name_changed)
	name_edit.text_submitted.connect(_on_name_submitted)
	row.add_child(name_edit)
	return row


func _build_toolbar() -> Control:
	var toolbar := HBoxContainer.new()
	for index in FILTER_CATEGORIES.size():
		var filter_button := Button.new()
		filter_button.text = FILTER_TEXTS[index]
		filter_button.toggle_mode = true
		filter_button.button_pressed = true
		filter_button.disabled = true
		filter_button.toggled.connect(_on_filter_toggled)
		filter_buttons[FILTER_CATEGORIES[index]] = filter_button
		toolbar.add_child(filter_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	all_button = Button.new()
	all_button.text = ALL_TEXT
	all_button.pressed.connect(_set_visible_checked.bind(true))
	toolbar.add_child(all_button)
	none_button = Button.new()
	none_button.text = NONE_TEXT
	none_button.pressed.connect(_set_visible_checked.bind(false))
	toolbar.add_child(none_button)
	return toolbar


func _build_variable_tree() -> Control:
	variable_tree = Tree.new()
	variable_tree.columns = 2
	variable_tree.hide_root = true
	variable_tree.select_mode = Tree.SELECT_ROW
	variable_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	variable_tree.custom_minimum_size.y = LIST_MINIMUM_HEIGHT
	variable_tree.create_item()
	variable_tree.item_edited.connect(_refresh)
	variable_tree.gui_input.connect(_on_tree_input)
	return variable_tree


func _build_preview() -> Control:
	preview_label = Label.new()
	preview_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview_label.mouse_filter = Control.MOUSE_FILTER_PASS
	return preview_label


func _build_validation_panel() -> Control:
	var panel := PanelContainer.new()
	validation_label = Label.new()
	validation_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	validation_label.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(validation_label)
	return panel


func _refresh() -> void:
	if _context == null:
		return
	var variable_names := get_selected_variable_names()
	preview_label.text = GDSExInitFunction.build_signature(_context, name_edit.text, variable_names)
	preview_label.tooltip_text = preview_label.text
	_name_check = GDSExInitFunction.check_function_name(_context, name_edit.text, variable_names.size())
	var level_color := _level_color(_name_check.level)
	validation_label.text = MESSAGE_BULLET + _name_check.message
	validation_label.tooltip_text = _name_check.message
	validation_label.add_theme_color_override(FONT_COLOR, level_color)
	var has_error := _name_check.level == GDSExInitFunction.GDSExNameCheck.GDSExLevel.ERROR
	get_ok_button().disabled = has_error
	if has_error:
		name_edit.add_theme_color_override(FONT_COLOR, level_color)
	else:
		name_edit.remove_theme_color_override(FONT_COLOR)


func _level_color(level : GDSExInitFunction.GDSExNameCheck.GDSExLevel) -> Color:
	if has_theme_color(LEVEL_COLOR_NAMES[level], EDITOR_THEME_TYPE):
		return get_theme_color(LEVEL_COLOR_NAMES[level], EDITOR_THEME_TYPE)
	return LEVEL_FALLBACK_COLORS[level]


func _set_visible_checked(is_checked : bool) -> void:
	for item in variable_tree.get_root().get_children():
		if item.visible:
			item.set_checked(NAME_COLUMN, is_checked)
	_refresh()


func _submit() -> void:
	if not get_ok_button().disabled:
		get_ok_button().pressed.emit()


func _on_name_changed(_new_text : String) -> void:
	_refresh()


func _on_name_submitted(_submitted_text : String) -> void:
	_submit()


func _on_filter_toggled(_is_pressed : bool) -> void:
	for item in variable_tree.get_root().get_children():
		var category : String = item.get_metadata(NAME_COLUMN)
		item.visible = filter_buttons[category].button_pressed


func _on_tree_input(event : InputEvent) -> void:
	if event.is_action_pressed(&"ui_select"):
		variable_tree.accept_event()
		var selected_item := variable_tree.get_selected()
		if selected_item != null:
			selected_item.set_checked(NAME_COLUMN, not selected_item.is_checked(NAME_COLUMN))
			_refresh()
	elif event.is_action_pressed(&"ui_accept"):
		variable_tree.accept_event()
		_submit()


func _on_confirmed() -> void:
	if _name_check.level != GDSExInitFunction.GDSExNameCheck.GDSExLevel.ERROR:
		_on_plan_ready.call(GDSExInitFunction.build_plan(_context, name_edit.text, get_selected_variable_names()))


func _on_visibility_changed() -> void:
	if visible:
		name_edit.grab_focus.call_deferred()
		name_edit.select_all.call_deferred()
