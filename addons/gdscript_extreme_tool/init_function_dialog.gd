@tool
extends "res://addons/gdscript_extreme_tool/function_name_dialog.gd"

const GDSExCodeContext = preload("res://addons/gdscript_extreme_tool/actions/code_context.gd")
const GDSExInitFunction = preload("res://addons/gdscript_extreme_tool/actions/init_function.gd")
const GDSExMemberCategories = preload("res://addons/gdscript_extreme_tool/analysis/member_categories.gd")

const TITLE : String = "Generate Custom Init Definition"
const GENERATE_TEXT : String = "Generate"
const ALL_TEXT : String = "All"
const NONE_TEXT : String = "None"
const FILTER_CATEGORIES : Array[String] = [GDSExMemberCategories.PRIVATE_VARIABLES, GDSExMemberCategories.PUBLIC_VARIABLES, GDSExMemberCategories.EXPORTS]
const FILTER_TEXTS : Array[String] = ["Private", "Public", "Exports"]
const UNAVAILABLE_FILTER_TEXT : String = "The class has no variables of this group."
const MINIMUM_SIZE : Vector2i = Vector2i(680, 560)
const LIST_MINIMUM_HEIGHT : float = 160.0
const NAME_COLUMN : int = 0
const TYPE_COLUMN : int = 1
const NORMAL_STYLE : StringName = &"normal"
const SELECTED_STYLES : Array[StringName] = [&"pressed", &"hover_pressed"]
const SELECTED_FONT_COLORS : Array[StringName] = [&"font_pressed_color", &"font_hover_pressed_color"]
const UNAVAILABLE_STYLE : StringName = &"disabled"
const UNAVAILABLE_FONT_COLOR : StringName = &"font_disabled_color"
const BRIGHT_FONT_COLOR : StringName = &"font_hover_color"
const BRIGHT_FONT_FALLBACK_COLOR : Color = Color.WHITE
const UNAVAILABLE_FALLBACK_COLOR : Color = Color(1.0, 1.0, 1.0, 0.3)
const SELECTED_FILTER_OPACITIES : Array[float] = [0.35, 0.5]
const UNAVAILABLE_FILTER_OPACITY : float = 0.0
const FILTER_BORDER_WIDTH : int = 1

var filter_buttons : Dictionary[String, Button] = {}
var all_button : Button
var none_button : Button
var variable_tree : Tree
var function_preview : CodeEdit

var _context : GDSExCodeContext
var _on_plan_ready : Callable


func _init() -> void:
	title = TITLE
	ok_button_text = GENERATE_TEXT
	min_size = MINIMUM_SIZE
	var content := VBoxContainer.new()
	add_child(content)
	content.add_child(_build_name_row())
	content.add_child(_build_toolbar())
	content.add_child(_build_variable_tree())
	function_preview = _add_code_preview(content, FUNCTION_TEXT)
	content.add_child(_build_validation_panel())
	confirmed.connect(_on_confirmed)
	visibility_changed.connect(_focus_name)


func _ready() -> void:
	_use_scaled_size(MINIMUM_SIZE)
	_style_code_preview(function_preview)
	for category in filter_buttons:
		_style_filter_button(filter_buttons[category])
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
	for category in filter_buttons:
		filter_buttons[category].tooltip_text = UNAVAILABLE_FILTER_TEXT if filter_buttons[category].disabled else ""
	_refresh()


func get_selected_variable_names() -> PackedStringArray:
	var names := PackedStringArray()
	for item in variable_tree.get_root().get_children():
		if item.is_checked(NAME_COLUMN):
			names.append(item.get_text(NAME_COLUMN))
	return names


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


func _style_filter_button(filter_button : Button) -> void:
	var accent_color := _editor_color(ACCENT_COLOR, ACCENT_FALLBACK_COLOR)
	var unavailable_color := _editor_color(UNAVAILABLE_FONT_COLOR, UNAVAILABLE_FALLBACK_COLOR)
	for index in SELECTED_STYLES.size():
		filter_button.add_theme_stylebox_override(SELECTED_STYLES[index], _build_filter_style(filter_button, accent_color, SELECTED_FILTER_OPACITIES[index]))
		filter_button.add_theme_color_override(SELECTED_FONT_COLORS[index], _editor_color(BRIGHT_FONT_COLOR, BRIGHT_FONT_FALLBACK_COLOR))
	filter_button.add_theme_stylebox_override(UNAVAILABLE_STYLE, _build_filter_style(filter_button, unavailable_color, UNAVAILABLE_FILTER_OPACITY))
	filter_button.add_theme_color_override(UNAVAILABLE_FONT_COLOR, unavailable_color)


func _build_filter_style(filter_button : Button, border_color : Color, fill_opacity : float) -> StyleBoxFlat:
	var normal_style := filter_button.get_theme_stylebox(NORMAL_STYLE)
	var style := StyleBoxFlat.new()
	if normal_style is StyleBoxFlat:
		style = normal_style.duplicate() as StyleBoxFlat
	elif normal_style != null:
		for side : Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_content_margin(side, normal_style.get_content_margin(side))
	style.bg_color = Color(border_color, fill_opacity)
	style.draw_center = fill_opacity > 0.0
	style.border_color = border_color
	style.set_border_width_all(FILTER_BORDER_WIDTH)
	return style


func _refresh() -> void:
	if _context == null:
		return
	var variable_names := get_selected_variable_names()
	function_preview.text = GDSExInitFunction.function_text(_context, name_edit.text, variable_names)
	_show_name_check(GDSExInitFunction.check_function_name(_context, name_edit.text, variable_names.size()))


func _set_visible_checked(is_checked : bool) -> void:
	for item in variable_tree.get_root().get_children():
		if item.visible:
			item.set_checked(NAME_COLUMN, is_checked)
	_refresh()


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
	if not _name_check.is_error():
		_on_plan_ready.call(GDSExInitFunction.build_plan(_context, name_edit.text, get_selected_variable_names()))
