@tool
extends ConfirmationDialog

const GDSExFunctionNameCheck = preload("res://addons/gdscript_extreme_tool/actions/function_name_check.gd")

const NAME_TEXT : String = "Name"
const MESSAGE_BULLET : String = "• "
const FONT_COLOR : StringName = &"font_color"
const FONT : StringName = &"font"
const EDITOR_THEME_TYPE : StringName = &"Editor"
const EDITOR_FONTS_THEME_TYPE : StringName = &"EditorFonts"
const SOURCE_FONT : StringName = &"source"
const LEVEL_COLOR_NAMES : Array[StringName] = [&"success_color", &"warning_color", &"error_color"]
const LEVEL_FALLBACK_COLORS : Array[Color] = [Color("73f280"), Color("d4c79e"), Color("ff786b")]
const FUNCTION_TEXT : String = "New function"
const PREVIEW_MINIMUM_HEIGHT : float = 120.0
const HIGHLIGHTER_CLASS : StringName = &"GDScriptSyntaxHighlighter"
const FONT_SIZE : StringName = &"font_size"
const SOURCE_FONT_SIZE : StringName = &"source_size"
const ACCENT_COLOR : StringName = &"accent_color"
const ACCENT_FALLBACK_COLOR : Color = Color("569eff")

var name_edit : LineEdit
var validation_label : Label

var _name_check : GDSExFunctionNameCheck.GDSExNameCheck


func _refresh() -> void:
	pass


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


func _build_code_label() -> Label:
	var label := Label.new()
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label


func _add_code_preview(content : Control, title_text : String) -> CodeEdit:
	var title_label := Label.new()
	title_label.text = title_text
	content.add_child(title_label)
	var preview := CodeEdit.new()
	preview.editable = false
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size.y = PREVIEW_MINIMUM_HEIGHT
	content.add_child(preview)
	return preview


func _style_code_preview(preview : CodeEdit) -> void:
	_use_source_font(preview)
	if has_theme_font_size(SOURCE_FONT_SIZE, EDITOR_FONTS_THEME_TYPE):
		preview.add_theme_font_size_override(FONT_SIZE, get_theme_font_size(SOURCE_FONT_SIZE, EDITOR_FONTS_THEME_TYPE))
	if ClassDB.can_instantiate(HIGHLIGHTER_CLASS):
		preview.syntax_highlighter = ClassDB.instantiate(HIGHLIGHTER_CLASS) as SyntaxHighlighter


func _editor_color(color_name : StringName, fallback_color : Color) -> Color:
	return get_theme_color(color_name, EDITOR_THEME_TYPE) if has_theme_color(color_name, EDITOR_THEME_TYPE) else fallback_color


func _build_validation_panel() -> Control:
	var panel := PanelContainer.new()
	validation_label = _build_code_label()
	panel.add_child(validation_label)
	return panel


func _use_scaled_size(minimum_size : Vector2i) -> void:
	if Engine.is_editor_hint():
		min_size = Vector2i(Vector2(minimum_size) * EditorInterface.get_editor_scale())


func _use_source_font(control : Control) -> void:
	if has_theme_font(SOURCE_FONT, EDITOR_FONTS_THEME_TYPE):
		control.add_theme_font_override(FONT, get_theme_font(SOURCE_FONT, EDITOR_FONTS_THEME_TYPE))


func _show_name_check(name_check : GDSExFunctionNameCheck.GDSExNameCheck) -> void:
	_name_check = name_check
	var level_color := _level_color(name_check.level)
	validation_label.text = MESSAGE_BULLET + name_check.message
	validation_label.tooltip_text = name_check.message
	validation_label.add_theme_color_override(FONT_COLOR, level_color)
	get_ok_button().disabled = name_check.is_error()
	if name_check.is_error():
		name_edit.add_theme_color_override(FONT_COLOR, level_color)
	else:
		name_edit.remove_theme_color_override(FONT_COLOR)


func _level_color(level : GDSExFunctionNameCheck.GDSExNameCheck.GDSExLevel) -> Color:
	return _editor_color(LEVEL_COLOR_NAMES[level], LEVEL_FALLBACK_COLORS[level])


func _submit() -> void:
	if not get_ok_button().disabled:
		get_ok_button().pressed.emit()


func _focus_name() -> void:
	if visible:
		name_edit.grab_focus.call_deferred()
		name_edit.select_all.call_deferred()


func _on_name_changed(_new_text : String) -> void:
	_refresh()


func _on_name_submitted(_submitted_text : String) -> void:
	_submit()
